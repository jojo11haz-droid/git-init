// Focused automated tests for the flows and bug-classes that actually bit us
// this cycle. Kept dependency-free and DB-free so it runs anywhere `npm test`
// runs (CI has no Postgres and no API keys):
//
//   A. A static guard for the "[hidden] loses to display" bug. A panel styled
//      display:flex/grid/… that also uses the `hidden` attribute must re-assert
//      display:none under `[hidden]`, or it never hides. We shipped this bug
//      twice (demo caseload, then the chat panel) because author `display`
//      beats the UA `[hidden]{display:none}` rule at equal/greater specificity.
//      jsdom's getComputedStyle does NOT reproduce this cascade, so a DOM test
//      would give false confidence — a static check is the reliable guard.
//
//   B. HTTP smoke tests against the real server: the public pages serve, unknown
//      paths 404, and the JSON API answers (cleanly, not a crash) rather than
//      hanging. These catch broken routing, a bad static path, or a startup
//      regression that still lets the process boot.
//
// Exits non-zero on the first category with a failure so CI turns red.

import { spawn } from 'child_process';
import { readFileSync, readdirSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
let failures = 0;
const fail = (msg) => { console.error('  ✗ ' + msg); failures++; };
const ok = (msg) => console.log('  ✓ ' + msg);

// ---------------------------------------------------------------------------
// A. Static [hidden] guard
// ---------------------------------------------------------------------------
console.log('Checking [hidden] panels re-assert display:none...');
{
  const html = readFileSync(join(root, 'public', 'index.html'), 'utf8');

  // Pull every <style> block's text (ignore <script>, attributes, etc.).
  let css = '';
  const styleRe = /<style[^>]*>([\s\S]*?)<\/style>/gi;
  let sm;
  while ((sm = styleRe.exec(html))) css += '\n' + sm[1];

  // Parse flat CSS rules: "selectors { declarations }". Good enough for this
  // codebase's single-level stylesheet (no nested at-rules with braces inside
  // the declaration bodies we care about).
  const rules = [];
  const ruleRe = /([^{}]+)\{([^{}]*)\}/g;
  let rm;
  while ((rm = ruleRe.exec(css))) {
    rules.push({ selectors: rm[1].trim(), decls: rm[2] });
  }
  const displayOf = (decls) => {
    const m = /(?:^|[;{\s])display\s*:\s*([a-z-]+)/i.exec(decls);
    return m ? m[1].toLowerCase() : null;
  };
  // A token (.class or #id) that some non-[hidden] rule gives a visible display.
  const tokenSetsVisibleDisplay = (token) => rules.some(r => {
    if (/\[hidden\]/.test(r.selectors)) return false;
    const d = displayOf(r.decls);
    if (!d || d === 'none') return false;
    // Word-boundary match so ".btw-mk" doesn't match ".btw-mk-body".
    const esc = token.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    return new RegExp(esc + '(?![\\w-])').test(r.selectors);
  });
  // A rule "<token>[hidden]" that forces display:none for this token.
  const hasHiddenOverride = (token) => rules.some(r => {
    const esc = token.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    if (!new RegExp(esc + '\\[hidden\\]').test(r.selectors)) return false;
    return displayOf(r.decls) === 'none';
  });

  // Every element that carries the real `hidden` attribute (not aria-hidden).
  const tagRe = /<([a-zA-Z][a-zA-Z0-9]*)\b([^>]*?)>/g;
  let tm, checked = 0;
  while ((tm = tagRe.exec(html))) {
    const attrs = tm[2];
    // The real boolean `hidden` attribute: the token `hidden` preceded by start
    // or whitespace (so `aria-hidden`, preceded by `-`, doesn't count) and
    // followed by whitespace, `=`, `/`, or end of the attribute list.
    if (!/(^|\s)hidden(\s|=|\/|$)/.test(attrs)) continue;
    const tokens = [];
    const cls = /\bclass\s*=\s*"([^"]*)"/.exec(attrs);
    if (cls) cls[1].split(/\s+/).filter(Boolean).forEach(c => tokens.push('.' + c));
    const id = /\bid\s*=\s*"([^"]*)"/.exec(attrs);
    if (id && id[1]) tokens.push('#' + id[1]);
    if (!tokens.length) continue;
    const visible = tokens.filter(tokenSetsVisibleDisplay);
    if (!visible.length) continue; // relies on UA [hidden]{display:none} — fine
    checked++;
    const guarded = tokens.some(hasHiddenOverride);
    if (!guarded) {
      const who = id ? '#' + id[1] : tokens[0];
      fail(`${who} gets a visible display via ${visible.join(', ')} but has no ` +
        `"${visible[0]}[hidden]{display:none}" rule — it will not hide when the hidden attribute is set.`);
    }
  }
  if (!failures) ok(`${checked} hidden panel(s) with visible display all re-assert display:none`);
}

// ---------------------------------------------------------------------------
// B. HTTP smoke tests against the booted server
// ---------------------------------------------------------------------------
const PORT = 3983;
const base = `http://127.0.0.1:${PORT}`;

function startServer() {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, ['server.js'], {
      cwd: root,
      env: { ...process.env, PORT: String(PORT), NODE_ENV: 'test', DISABLE_REMINDER_SWEEP: '1' }
    });
    let out = '';
    const timer = setTimeout(() => { reject(new Error('server did not start in 15s\n' + out)); }, 15000);
    child.stdout.on('data', d => { out += d; if (/running on port/i.test(out)) { clearTimeout(timer); resolve(child); } });
    child.stderr.on('data', d => { out += d; });
    child.on('exit', code => { clearTimeout(timer); reject(new Error('server exited early (code ' + code + ')\n' + out)); });
  });
}

console.log('Running HTTP smoke tests...');
let server;
try {
  server = await startServer();

  const get = async (p, opts) => {
    const res = await fetch(base + p, opts);
    const body = await res.text();
    return { status: res.status, type: res.headers.get('content-type') || '', body };
  };

  // Public pages serve.
  for (const [path, needle] of [
    ['/', 'Between'],
    ['/clinic-data-agreement.html', 'Clinic Data Agreement'],
    ['/privacy.html', 'Privacy'],
  ]) {
    const r = await get(path);
    if (r.status === 200 && r.body.includes(needle)) ok(`GET ${path} → 200`);
    else fail(`GET ${path} → ${r.status}${r.body.includes(needle) ? '' : ' (missing "' + needle + '")'}`);
  }

  // Unknown paths 404 (not a 500 or a hang).
  {
    const r = await get('/definitely-not-a-real-page-xyz.html');
    if (r.status === 404) ok('GET unknown path → 404');
    else fail('GET unknown path → ' + r.status + ' (expected 404)');
  }

  // The JSON API answers cleanly. Without a DB (as in CI) the DB-guarded
  // routes return 503; with a DB they do their real thing. Either is a pass —
  // what we're guarding against is a 500/crash/hang from broken wiring.
  {
    const r = await get('/api/reminders/unsubscribe?token=smoke-test-nope');
    // This route returns an HTML confirmation page (200) when the DB is on, or
    // 503 JSON when it's off. Never a 500.
    if (r.status === 200 || r.status === 503) ok(`GET /api/reminders/unsubscribe → ${r.status}`);
    else fail('GET /api/reminders/unsubscribe → ' + r.status + ' (expected 200 or 503)');
  }
  {
    const r = await get('/api/patient/reminders', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{"enabled":true}'
    });
    // No session + (in CI) no DB → 401/403/503, never a 500.
    if ([401, 403, 503].includes(r.status)) ok(`POST /api/patient/reminders (unauthed) → ${r.status}`);
    else fail('POST /api/patient/reminders → ' + r.status + ' (expected 401/403/503)');
  }
  {
    // Multi-seat practice routes are registered and gated, not crashing.
    const r = await get('/api/practice');
    if ([401, 403, 503].includes(r.status)) ok(`GET /api/practice (unauthed) → ${r.status}`);
    else fail('GET /api/practice → ' + r.status + ' (expected 401/403/503)');
  }
  {
    const r = await get('/api/practice/invite-info?token=smoke-nope');
    // requireDb runs first (503 in CI); with a DB it's a 404 for a bad token. Never 500.
    if ([404, 503].includes(r.status)) ok(`GET /api/practice/invite-info → ${r.status}`);
    else fail('GET /api/practice/invite-info → ' + r.status + ' (expected 404 or 503)');
  }
  {
    // Apple Health sync route is registered and gated, not crashing.
    const r = await get('/api/patient/health', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: '{"days":[{"day":"2024-01-01","sleepMinutes":440}]}'
    });
    if ([401, 403, 503].includes(r.status)) ok(`POST /api/patient/health (unauthed) → ${r.status}`);
    else fail('POST /api/patient/health → ' + r.status + ' (expected 401/403/503)');
  }
  {
    // Owner engagement analytics is registered and gated, not crashing.
    const r = await get('/api/admin/engagement');
    if ([401, 403, 503].includes(r.status)) ok(`GET /api/admin/engagement (unauthed) → ${r.status}`);
    else fail('GET /api/admin/engagement → ' + r.status + ' (expected 401/403/503)');
  }

  // Field landing pages (/physio, /nutrition, …) each serve their own <head>
  // meta. This once broke silently: the server swapped tags by matching the
  // default copy's exact text, the copy was edited, and every field page sent
  // Google and link previews the therapy description. Also checks the server's
  // copy matches FIELD_HEAD in index.html (what an in-page field switch sets),
  // and that only the <head> is rewritten — the SPA body must be untouched.
  {
    const indexSrc = readFileSync(join(root, 'public', 'index.html'), 'utf8');
    const split = (html) => { const i = html.indexOf('</head>'); return [html.slice(0, i), html.slice(i)]; };
    const decode = (s) => s.replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
    const tag = (head, re) => { const m = head.match(re); return m ? decode(m[1]) : null; };
    const [baseHead, baseBody] = split(indexSrc);
    const defaultDesc = tag(baseHead, /<meta name="description" content="([^"]*)"/);
    // path → a word its title or description must contain
    const FIELDS = {
      '/individual': 'yourself', '/physio': 'physiotherap', '/kinesiology': 'kinesiolog',
      '/osteopathy': 'osteopath', '/occupational-therapy': 'occupational therap',
      '/neuropsychology': 'neuropsycholog', '/sports': 'coaches', '/fitness': 'personal trainers',
      '/addiction': 'recovery', '/schools': 'school', '/nutrition': 'nutritionist'
    };
    for (const [p, word] of Object.entries(FIELDS)) {
      const r = await get(p);
      const [head, body] = split(r.body);
      const title = tag(head, /<title>([^<]*)<\/title>/);
      const desc = tag(head, /<meta name="description" content="([^"]*)"/);
      const url = 'https://betweenpsych.com' + p;
      const problems = [];
      if (r.status !== 200) problems.push('status ' + r.status);
      if (!desc || desc === defaultDesc) problems.push('description is the default therapy copy');
      if (!((title || '') + ' ' + (desc || '')).toLowerCase().includes(word)) problems.push('title/description never mention "' + word + '"');
      if (tag(head, /<meta property="og:title" content="([^"]*)"/) !== title || tag(head, /<meta name="twitter:title" content="([^"]*)"/) !== title) problems.push('og/twitter title ≠ <title>');
      if (tag(head, /<meta property="og:description" content="([^"]*)"/) !== desc || tag(head, /<meta name="twitter:description" content="([^"]*)"/) !== desc) problems.push('og/twitter description ≠ meta description');
      if (tag(head, /<link rel="canonical" href="([^"]*)"/) !== url || tag(head, /<meta property="og:url" content="([^"]*)"/) !== url) problems.push('canonical/og:url ≠ ' + url);
      const img = 'https://betweenpsych.com/og' + p + '.png';
      if (tag(head, /<meta property="og:image" content="([^"]*)"/) !== img || tag(head, /<meta name="twitter:image" content="([^"]*)"/) !== img) problems.push('og/twitter image ≠ ' + img);
      const card = await fetch(base + '/og' + p + '.png');
      if (card.status !== 200 || card.headers.get('content-type') !== 'image/png') problems.push('/og' + p + '.png → ' + card.status + ' ' + card.headers.get('content-type'));
      await card.arrayBuffer();
      if (!indexSrc.includes("title: '" + title + "'") || !indexSrc.includes("desc: '" + desc + "'")) problems.push('copy out of sync with FIELD_HEAD in index.html');
      if (body !== baseBody) problems.push('page body was rewritten (only <head> should change)');
      if (problems.length) fail(`GET ${p} head meta — ${problems.join('; ')}`);
      else ok(`GET ${p} → own title, description, canonical, preview card`);
    }
    {
      const img = tag(baseHead, /<meta property="og:image" content="([^"]*)"/) || '';
      const card = await fetch(base + img.replace('https://betweenpsych.com', ''));
      await card.arrayBuffer();
      if (img.endsWith('/og/therapy.png') && card.status === 200) ok('GET / → default preview card /og/therapy.png');
      else fail('GET / preview card — og:image "' + img + '" → ' + card.status);
    }
    const t = await get('/therapy');
    if (t.status === 200 && t.body === indexSrc) ok('GET /therapy → base page (canonical "/")');
    else fail('GET /therapy → ' + t.status + ' (expected the unmodified base page)');

    // sitemap.xml: lists every field page (not /therapy — it canonicalizes to
    // "/") and every guide; each listed URL serves, and so does its og:image.
    const sm = await get('/sitemap.xml');
    const locs = [...sm.body.matchAll(/<loc>https:\/\/betweenpsych\.com([^<]*)<\/loc>/g)].map((m) => m[1]);
    const guides = readdirSync(join(root, 'public', 'guides')).filter((f) => f.endsWith('.html'))
      .map((f) => '/guides/' + (f === 'index.html' ? '' : f));
    const missing = [...Object.keys(FIELDS), ...guides].filter((p) => !locs.includes(p));
    const problems = [];
    if (sm.status !== 200 || !locs.length) problems.push('sitemap → ' + sm.status + ', ' + locs.length + ' URLs');
    if (missing.length) problems.push('not listed: ' + missing.join(', '));
    if (locs.includes('/therapy')) problems.push('lists /therapy (canonical is "/")');
    for (const p of locs) {
      const r = await get(p);
      if (r.status !== 200) { problems.push(p + ' → ' + r.status); continue; }
      const img = tag(split(r.body)[0], /<meta property="og:image" content="https:\/\/betweenpsych\.com([^"]*)"/);
      if (img) { const c = await fetch(base + img); await c.arrayBuffer(); if (c.status !== 200) problems.push(p + ' og:image ' + img + ' → ' + c.status); }
      else if (p === '/' || p.startsWith('/guides/') || FIELDS[p]) problems.push(p + ' has no og:image');
    }
    if (problems.length) fail('sitemap — ' + problems.join('; '));
    else ok(`sitemap.xml → ${locs.length} URLs, all serve, previews present`);

    // Structured data: valid JSON, every plan price is one the pricing page
    // actually shows (data-cad="…"), and the logo it names serves.
    {
      const blocks = [...baseHead.matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)].map((m) => m[1]);
      const probs = [];
      let graph = [];
      try { graph = blocks.flatMap((b) => JSON.parse(b)['@graph'] || []); } catch (e) { probs.push('invalid JSON-LD: ' + e.message); }
      const app = graph.find((n) => n['@type'] === 'SoftwareApplication');
      const org = graph.find((n) => n['@type'] === 'Organization');
      const offers = (app && app.offers) || [];
      if (!app || !org) probs.push('missing SoftwareApplication or Organization');
      if (!offers.length) probs.push('no offers');
      for (const o of offers) if (!indexSrc.includes('data-cad="' + o.price + '"')) probs.push('"' + o.name + '" price ' + o.price + ' not on the pricing page');
      if (org && org.logo) { const r = await fetch(base + org.logo.replace('https://betweenpsych.com', '')); await r.arrayBuffer(); if (r.status !== 200) probs.push('logo → ' + r.status); }
      if (probs.length) fail('JSON-LD — ' + probs.join('; '));
      else ok(`JSON-LD → ${graph.length} entities, ${offers.length} offers match the pricing page`);
    }
    // iOS ignores an SVG apple-touch-icon, so it must be the PNG; and the
    // "Skip to content" link must point at the <main> landmark.
    {
      const icon = await fetch(base + '/apple-touch-icon.png'); await icon.arrayBuffer();
      const probs = [];
      if (icon.status !== 200 || icon.headers.get('content-type') !== 'image/png') probs.push('/apple-touch-icon.png → ' + icon.status);
      if (!baseHead.includes('<link rel="apple-touch-icon" href="/apple-touch-icon.png">')) probs.push('apple-touch-icon link is not the PNG');
      if (!indexSrc.includes('<a class="btw-skip" href="#btwMain">') || !indexSrc.includes('<main id="btwMain" tabindex="-1">')) probs.push('skip link or <main id="btwMain"> missing');
      if (probs.length) fail('icons / a11y — ' + probs.join('; '));
      else ok('apple-touch-icon PNG serves; skip link → <main>');
    }
    // Refresh flash, static guards (scripts/flash-check.mjs is the full visual
    // check, needs Playwright): the first frame, before the main script runs,
    // must already carry what that script would add, or a refresh flashes.
    {
      const probs = [];
      if (/class="btw-chooser-card[^"]*\bactive\b/.test(indexSrc)) probs.push('a chooser card is pre-highlighted in the markup');
      const cards = (indexSrc.match(/<button type="button" class="btw-chooser-card[^"]*" data-aud="[a-z]+">/g) || []).length;
      const withArt = (indexSrc.match(/<button type="button" class="btw-chooser-card[^"]*" data-aud="[a-z]+"><span class="ic"/g) || []).length;
      if (!cards || withArt !== cards) probs.push(`${cards - withArt} chooser card(s) with no illustration in the markup`);
      if (!/id="btwThemeBtn"[^>]*><svg class="ic-moon"[^]*?<svg class="ic-sun"/.test(indexSrc)) probs.push('theme icons not in the button markup');
      if (!indexSrc.includes('html.btw-pre-gated #btwLoginBtn')) probs.push('first frame of the gated landing shows Log in / Sign up');
      if (!indexSrc.includes('html.btw-pre-resolving #btwLoginBtn')) probs.push('first frame of a signed-in refresh shows Log in / Sign up');
      if (!indexSrc.includes('<div class="btw-chooser-groups btw-accordion">')) probs.push("phone accordion isn't collapsed in the first frame");
      if (!indexSrc.includes('html.btw-pre-gated .btw-home .btw-chooser{')) probs.push('first frame of the gated landing lacks the chooser panel');
      if (probs.length) fail('refresh flash — ' + probs.join('; '));
      else ok(`refresh flash guards → ${cards} chooser cards with art, header + panel + accordion set from the first frame`);
    }
  }
} catch (err) {
  fail('HTTP smoke tests — ' + err.message);
} finally {
  if (server) { try { server.kill('SIGKILL'); } catch (_) {} }
}

if (failures) { console.error('\n' + failures + ' app test(s) failed.'); process.exit(1); }
console.log('\nAll app tests passed.');
