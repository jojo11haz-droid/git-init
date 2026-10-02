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
import { readFileSync } from 'fs';
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
} catch (err) {
  fail('HTTP smoke tests — ' + err.message);
} finally {
  if (server) { try { server.kill('SIGKILL'); } catch (_) {} }
}

if (failures) { console.error('\n' + failures + ' app test(s) failed.'); process.exit(1); }
console.log('\nAll app tests passed.');
