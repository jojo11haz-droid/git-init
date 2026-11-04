// Refresh-flash check: the first frame a browser paints (before the main
// script runs) must look like the page the script then settles on, or a
// refresh shows a "split second" of the wrong page. The first-paint script at
// the top of <body> + the html.btw-pre-* CSS make that frame; they drift
// whenever the script's look changes and the pre-classes don't follow.
//
//   node scripts/flash-check.mjs
//
// Needs Playwright (not a project dependency — run where it's installed).
// Frame A = the page with every script after the first-paint one stripped.
// Frame B = the real page after it settles. Signed-out landings must match
// pixel for pixel (small anti-aliasing noise allowed); for a signed-in
// refresh the header must already show what the signed-in header shows.

import { createRequire } from 'module';
import { spawn } from 'child_process';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const require = createRequire(import.meta.url);
const { chromium, devices } = require('playwright');
const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const PORT = 3987, base = `http://127.0.0.1:${PORT}`;
const MAX_DIFF_PCT = 3;
let failures = 0;

const server = spawn(process.execPath, ['server.js'], { cwd: root, env: { ...process.env, PORT: String(PORT), DISABLE_REMINDER_SWEEP: '1' } });
const browser = await chromium.launch();
try {
  for (let i = 0; i < 60; i++) { try { await fetch(base + '/health'); break; } catch (e) { await new Promise((r) => setTimeout(r, 250)); } }
  const full = await (await fetch(base + '/')).text();
  const bodyAt = full.search(/\n<body>\s*<script>/);
  const gateEnd = full.indexOf('</script>', bodyAt) + '</script>'.length;
  const firstFrameHtml = full.slice(0, gateEnd) + full.slice(gateEnd).replace(/<script\b[\s\S]*?<\/script>/g, '');

  async function open(ctxOpts, storage, firstFrame, mockSession) {
    const ctx = await browser.newContext({ viewport: { width: 1000, height: 700 }, deviceScaleFactor: 1, ...ctxOpts });
    await ctx.addInitScript((s) => { try { for (const k in s) localStorage.setItem(k, s[k]); } catch (e) {} }, storage);
    const page = await ctx.newPage();
    await page.route(/fonts\.(googleapis|gstatic)\.com/, (r) => r.fulfill({ status: 200, body: '' }));
    if (mockSession) {
      await page.route(base + '/api/**', (r) => {
        const u = r.request().url();
        if (u.includes('/api/auth/me')) return r.fulfill({ json: { clinician: { id: 'c1', name: 'Test', email: 'test@example.com', verified: true, subscription_status: 'active', discipline: 'psychotherapy' }, billingEnabled: false, freeAccess: true } });
        if (/\/api\/(patients|alerts)(\?|$)/.test(u) || /check-ins|caseload|digest|outcomes/.test(u)) return r.fulfill({ json: [] });
        return r.fulfill({ json: {} });
      });
    }
    if (firstFrame) await page.route(base + '/', (r) => r.fulfill({ status: 200, contentType: 'text/html', body: firstFrameHtml }));
    await page.goto(base + '/', { waitUntil: 'load' });
    await page.waitForTimeout(firstFrame ? 300 : 1500);
    return page;
  }

  // Signed-out landings: first frame vs settled, pixel diff.
  for (const [name, ctxOpts, storage] of [
    ['desktop', {}, {}],
    ['returning visitor', {}, { btw_field: 'physio' }],
    ['dark mode', { colorScheme: 'dark' }, {}],
    ['phone', { ...devices['iPhone 13'], deviceScaleFactor: 1 }, {}]
  ]) {
    const a = await open(ctxOpts, storage, true), shotA = (await a.screenshot()).toString('base64'); await a.context().close();
    const b = await open(ctxOpts, storage, false), shotB = (await b.screenshot()).toString('base64'); await b.close();
    const cmp = await (await browser.newPage()).evaluate(async ([x, y]) => {
      const load = (s) => new Promise((r) => { const i = new Image(); i.onload = () => r(i); i.src = 'data:image/png;base64,' + s; });
      const [i1, i2] = await Promise.all([load(x), load(y)]);
      const c = document.createElement('canvas'); c.width = i1.width; c.height = i1.height; const g = c.getContext('2d');
      g.drawImage(i1, 0, 0); const d1 = g.getImageData(0, 0, c.width, c.height).data;
      g.drawImage(i2, 0, 0); const d2 = g.getImageData(0, 0, c.width, c.height).data;
      let n = 0; for (let k = 0; k < d1.length; k += 4) if (Math.abs(d1[k] - d2[k]) + Math.abs(d1[k + 1] - d2[k + 1]) + Math.abs(d1[k + 2] - d2[k + 2]) > 24) n++;
      return 100 * n / (c.width * c.height);
    }, [shotA, shotB]);
    const line = `${name}: first frame vs settled differ by ${cmp.toFixed(2)}% of pixels`;
    if (cmp > MAX_DIFF_PCT) { console.error('  ✗ ' + line + ` (max ${MAX_DIFF_PCT}%)`); failures++; } else console.log('  ✓ ' + line);
  }

  // Signed-in refresh: the first frame's header must already match the
  // settled signed-in header (no Log in / Sign up, no marketing chrome).
  const vis = (p) => p.evaluate(() => ['.btw-nav', '.btw-audnow', '#btwLoginBtn', '#btwSignupBtn'].map((s) => {
    const e = document.querySelector(s); return s + '=' + (!!e && getComputedStyle(e).display !== 'none');
  }).join(' '));
  const a = await open({}, { btw_session: '1' }, true, true), firstHeader = await vis(a); await a.context().close();
  const b = await open({}, { btw_session: '1' }, false, true), settledHeader = await vis(b); await b.context().close();
  if (firstHeader === settledHeader) console.log('  ✓ signed-in: first-frame header matches the signed-in header');
  else { console.error(`  ✗ signed-in header flips:\n      first:   ${firstHeader}\n      settled: ${settledHeader}`); failures++; }
} finally {
  await browser.close();
  server.kill('SIGKILL');
}
if (failures) { console.error(`\n${failures} refresh-flash check(s) failed.`); process.exit(1); }
console.log('\nNo refresh flash.');
