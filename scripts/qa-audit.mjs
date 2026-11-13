// Nightly QA walk of the public site, with no database needed.
//
// For each of the 11 professional fields plus "On your own", in English and
// French, at desktop and phone width, it loads the field's page and checks:
//   - page errors (uncaught JavaScript exceptions)
//   - horizontal overflow on a phone (something wider than the screen)
//   - profession mix-ups: the wrong word for the person (patient / client /
//     player / member / student), another profession's title, or the wrong
//     scale ("mood" on a pain field, "pain" on a mood field)
// It also loads the features page per field.
//
// Run:  node scripts/qa-audit.mjs            (writes qa-report.txt, exits 1 on findings)
// Needs Playwright with Chromium (preinstalled in the cloud environment).

import { spawn } from 'child_process';
import { writeFileSync } from 'fs';

let chromium;
try { ({ chromium } = await import('playwright')); }
catch (e) { ({ chromium } = await import('/opt/node-tools/node_modules/playwright/index.mjs')); }

const PORT = 4890, B = 'http://localhost:' + PORT;
const srv = spawn('node', ['server.js'], { env: { ...process.env, PORT: String(PORT), NODE_ENV: 'test', DATABASE_URL: '', DISABLE_REMINDER_SWEEP: '1' }, stdio: 'ignore' });
await new Promise(r => setTimeout(r, 2000));

const FIELDS = ['therapy', 'physio', 'kinesiology', 'osteo', 'occupational', 'neuropsych', 'nutrition', 'sports', 'fitness', 'recovery', 'schools'];
const SLUG = { therapy: 'therapy', physio: 'physio', kinesiology: 'kinesiology', osteo: 'osteopathy', occupational: 'occupational-therapy', neuropsych: 'neuropsychology', nutrition: 'nutrition', sports: 'sports', fitness: 'fitness', recovery: 'addiction', schools: 'schools', individual: 'individual' };
const NOUN = { physio: 'patient', sports: 'player', recovery: 'member', schools: 'student' };
const PAIN = ['physio', 'kinesiology', 'osteo', 'occupational'];
// Mental-health fields: must never read rehab wording (home program, dose, discomfort…).
const MIND = ['therapy', 'neuropsych', 'recovery'];
const PROF = { therapy: ['psychotherapist', 'therapist', 'counsellor'], physio: ['physio', 'physiotherapist'], kinesiology: ['kinesiologist'], osteo: ['osteopath'], occupational: ['occupational therapist', 'therapist'], neuropsych: ['neuropsychologist'], nutrition: ['nutritionist', 'dietitian'], sports: ['coach'], fitness: ['trainer', 'coach'], recovery: ['mentor'], schools: ['school staff', 'teacher', 'counsellor', 'counselor'] };
const ALLPROF = ['psychotherapist', 'therapist', 'physiotherapist', 'physio', 'kinesiologist', 'osteopath', 'occupational therapist', 'neuropsychologist', 'nutritionist', 'dietitian', 'coach', 'trainer', 'mentor', 'teacher', 'school staff'];
const PFR = { therapy: ['psychothérapeute', 'thérapeute'], physio: ['physiothérapeute', 'physio'], kinesiology: ['kinésiologue'], osteo: ['ostéopathe'], occupational: ['ergothérapeute'], neuropsych: ['neuropsychologue'], nutrition: ['nutritionniste', 'diététiste'], sports: ['entraîneur', 'entraîneuse'], fitness: ['entraîneur', 'entraîneuse'], recovery: ['mentor'], schools: ['enseignant', 'enseignante', 'personnel scolaire'] };
const ALLFR = ['psychothérapeute', 'thérapeute', 'physiothérapeute', 'kinésiologue', 'ostéopathe', 'ergothérapeute', 'neuropsychologue', 'nutritionniste', 'entraîneur', 'mentor', 'enseignant', 'personnel scolaire'];
// Lines that are right on every field (the emergency notice, staff wording…).
const ALLOW = [/severe pain|douleur intense/i, /membre du personnel/i, /counsellors? &/i];

function scan(field, lang, where, text) {
  const out = []; const t = ' ' + text.replace(/\s+/g, ' ') + ' ';
  const ctx = (i, len) => t.slice(Math.max(0, i - 45), i + len + 45).trim();
  const add = (kind, m, i) => { const c = ctx(i, m.length); if (!ALLOW.some(re => re.test(c))) out.push(`[${field}/${lang}] ${where}: ${kind} "${m}" … ${c}`); };
  if (lang === 'en') {
    const want = NOUN[field] || 'client';
    for (const m of t.matchAll(/\b(patients?|clients?|players?|members?|students?)\b/gi)) { if (m[1].toLowerCase().replace(/s$/, '') !== want) add('NOUN', m[1], m.index); }
    for (const p of ALLPROF) for (const m of t.matchAll(new RegExp('\\b' + p + 's?\\b', 'gi'))) { if (!(PROF[field] || []).includes(p)) add('PROFESSION', m[0], m.index); }
    if (field !== 'sports' && field !== 'fitness') for (const m of t.matchAll(PAIN.includes(field) ? /\bmood\b/gi : /\bpain\b/gi)) add('SCALE', m[0], m.index);
    if (MIND.includes(field)) for (const m of t.matchAll(/\b(home program|dose|discomfort|progress or ease off|SOAP, DAP or ADIME|sore spots?)\b/gi)) add('REHAB', m[0], m.index);
  } else {
    const want = { physio: 'patient', sports: 'joueu', recovery: 'membre', schools: 'élève' }[field] || 'client';
    for (const m of t.matchAll(/(^|[^\p{L}])(patient(e)?s?|client(e)?s?|joueu(r|se)s?|membres?|élèves?)(?![\p{L}])/giu)) { if (!m[2].toLowerCase().startsWith(want)) add('NOUN', m[2], m.index); }
    for (const p of ALLFR) for (const m of t.matchAll(new RegExp('(^|[^\\p{L}])' + p + 's?(?![\\p{L}])', 'giu'))) { if (!(PFR[field] || []).includes(p)) add('PROFESSION', m[0].trim(), m.index); }
    if (field !== 'sports' && field !== 'fitness') for (const m of t.matchAll(PAIN.includes(field) ? /(^|[^\p{L}])humeur(?![\p{L}])/giu : /(^|[^\p{L}])douleurs?(?![\p{L}])/giu)) add('SCALE', m[0].trim(), m.index);
    if (MIND.includes(field)) for (const m of t.matchAll(/(programme à domicile|inconfort|progresser ou alléger|SOAP, DAP ou ADIME|points sensibles)/giu)) add('REHAB', m[0], m.index);
  }
  return [...new Set(out)];
}

const b = await chromium.launch();
const findings = [];
let pages = 0;
for (const lang of ['en', 'fr']) {
  for (const f of [...FIELDS, 'individual']) {
    for (const [vpName, vp] of [['desktop', { width: 1280, height: 900 }], ['phone', { width: 390, height: 844 }]]) {
      const p = await b.newPage({ viewport: vp });
      const errs = []; p.on('pageerror', e => errs.push(String(e).slice(0, 200)));
      await p.route('**/fonts.g*/**', r => r.abort());
      await p.addInitScript(l => { try { localStorage.setItem('btw_lang', l); localStorage.setItem('btw_tour_v2', 'done'); } catch (e) {} }, lang);
      await p.goto(B + '/' + SLUG[f], { waitUntil: 'networkidle' }); await p.waitForTimeout(400);
      pages++;
      errs.forEach(e => findings.push(`[${f}/${lang}] ${vpName}: PAGE ERROR ${e}`));
      if (vpName === 'phone') {
        const over = await p.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
        if (over > 2) findings.push(`[${f}/${lang}] phone: HORIZONTAL OVERFLOW ${over}px wider than the screen`);
      } else if (f !== 'individual') {
        const txt = await p.evaluate(() => { const v = document.querySelector('.btw-view.active'); return v ? v.innerText : ''; });
        findings.push(...scan(f, lang, 'public page', txt));
      }
      await p.close();
    }
    if (f !== 'individual') {
      const p = await b.newPage({ viewport: { width: 1200, height: 900 } });
      const errs = []; p.on('pageerror', e => errs.push(String(e).slice(0, 200)));
      await p.goto(`${B}/features?field=${f}&lang=${lang}`, { waitUntil: 'networkidle' });
      pages++;
      errs.forEach(e => findings.push(`[${f}/${lang}] features: PAGE ERROR ${e}`));
      const txt = await p.evaluate(() => document.body.innerText);
      if (/\{[a-zA-Z]+\}/.test(txt)) findings.push(`[${f}/${lang}] features: UNFILLED PLACEHOLDER`);
      await p.close();
    }
  }
}
await b.close(); srv.kill();
const report = `QA audit — ${new Date().toISOString()}\nPages checked: ${pages}\nFindings: ${findings.length}\n\n` + (findings.join('\n') || 'None.');
writeFileSync('qa-report.txt', report + '\n');
console.log(report);
process.exit(findings.length ? 1 : 0);
