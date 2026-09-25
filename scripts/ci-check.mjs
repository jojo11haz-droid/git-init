// Fast checks that catch the breakages that used to need a manual look:
//   1. every backend .js file parses (node --check)
//   2. the big inline <script> in public/index.html parses
//   3. the server boots — all imports resolve and nothing throws on startup
// Exits non-zero on the first failure so CI turns red.

import { execFileSync, spawn } from 'child_process';
import { readFileSync, readdirSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import vm from 'vm';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
let failures = 0;
const fail = (msg) => { console.error('  ✗ ' + msg); failures++; };
const ok = (msg) => console.log('  ✓ ' + msg);

// 1. Syntax-check every top-level backend .js file.
console.log('Checking backend JS syntax...');
for (const f of readdirSync(root).filter(n => n.endsWith('.js')).sort()) {
  try { execFileSync(process.execPath, ['--check', join(root, f)], { stdio: 'pipe' }); ok(f); }
  catch (e) { fail(f + ' — ' + (e.stderr ? e.stderr.toString().split('\n')[0] : e.message)); }
}

// 2. Parse the inline scripts inside public/index.html.
console.log('Checking public/index.html inline scripts...');
const html = readFileSync(join(root, 'public', 'index.html'), 'utf8');
const re = /<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/g;
let m, n = 0;
while ((m = re.exec(html))) {
  n++;
  try { vm.compileFunction(m[1], [], {}); }
  catch (e) { fail('inline script #' + n + ' — ' + e.message); }
}
if (!failures) ok(n + ' inline script(s)');

// 3. Boot the server and confirm it starts listening (catches bad imports,
//    missing exports, and other startup throws).
async function bootCheck() {
  console.log('Booting the server...');
  await new Promise((resolve) => {
    const child = spawn(process.execPath, ['server.js'], {
      cwd: root,
      env: { ...process.env, PORT: '3971', NODE_ENV: 'test' }
    });
    let out = '';
    let done = false;
    const finish = (good, why) => {
      if (done) return; done = true;
      clearTimeout(timer);
      try { child.kill('SIGKILL'); } catch (_) {}
      if (good) ok('server started'); else fail('server did not start — ' + why + (out ? '\n' + out.trim() : ''));
      resolve();
    };
    child.stdout.on('data', d => { out += d; if (/running on port/i.test(out)) finish(true); });
    child.stderr.on('data', d => { out += d; });
    child.on('exit', code => finish(code === 0, 'exited with code ' + code));
    const timer = setTimeout(() => finish(false, 'timed out after 15s'), 15000);
  });
}
await bootCheck();

if (failures) { console.error('\n' + failures + ' check(s) failed.'); process.exit(1); }
console.log('\nAll checks passed.');
