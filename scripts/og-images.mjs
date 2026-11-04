// Renders the 1200×630 link-preview cards (og:image / twitter:image) into
// public/og/<slug>.png — one per field landing page, slug = URL path
// (/physio → physio.png; "/" uses therapy.png), plus one per guide article.
// Re-run after changing a headline, an illustration, or the brand look:
//
//   node scripts/og-images.mjs
//
// Needs Playwright (not a project dependency — run where it's installed).
// Fonts load from Google Fonts; set OG_FONT_DIR to a folder holding
// newsreader-latin.woff2 + newsreader-latin-italic.woff2 to work offline.

import { createRequire } from 'module';
import { readFileSync, mkdirSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright');
const root = join(dirname(fileURLToPath(import.meta.url)), '..');

// lead + em = the headline (em is set in italic navy, like the site's hero).
// art = the illustration in public/assets/fields/.
const CARDS = {
  therapy: { lead: 'Between-session check-ins for', em: 'therapy', art: 'therapy', sub: 'Clients send a quick note between sessions. You see the pattern before the next one.' },
  individual: { lead: 'Private check-ins for', em: 'yourself', art: 'individual', sub: 'Your mood trend and the themes that keep returning, kept private to you.' },
  physio: { lead: 'Between-visit pain check-ins for', em: 'physiotherapy', art: 'physio', sub: 'Patients mark where it hurts on a body map. You see the pain trend before the next appointment.' },
  kinesiology: { lead: 'Between-session check-ins for', em: 'kinesiology', art: 'kinesiology', sub: 'Clients track movement and pain between sessions. You see the trend before the next appointment.' },
  osteopathy: { lead: 'Between-visit check-ins for', em: 'osteopathy', art: 'osteo', sub: 'Patients note pain and recovery between treatments. You see the trend before the next appointment.' },
  'occupational-therapy': { lead: 'Between-visit check-ins for', em: 'occupational therapy', art: 'occupational', sub: 'Patients note how daily activities and recovery are going. You see the trend before the next visit.' },
  neuropsychology: { lead: 'Between-session check-ins for', em: 'neuropsychology', art: 'neuropsych', sub: 'Focus, memory, mental fatigue and mood, noted between sessions. You see the trend before the next one.' },
  sports: { lead: 'Between-practice check-ins for', em: 'sports teams', art: 'sports', sub: 'Players check in between practices, games and tournaments. Coaches see how the team is doing.' },
  fitness: { lead: 'Between-session check-ins for', em: 'personal trainers', art: 'fitness', sub: 'Clients check in between workouts. You see how they are doing before the next session.' },
  addiction: { lead: 'Between-session check-ins for', em: 'recovery programs', art: 'recovery', sub: 'People check in between meetings. Mentors see how they are doing.' },
  schools: { lead: 'Between-session check-ins for', em: 'schools', art: 'schools', sub: 'Students check in between sessions. School staff see how they are doing.' },
  nutrition: { lead: 'Between-session check-ins for', em: 'nutritionists', art: 'nutrition', sub: 'Energy, cravings and how the plan is going, noted between sessions. You see the trend before the next appointment.' }
};

// Guide articles: public/og/guide-<file name>.png (the index → guides.png).
const GUIDES = {
  guides: { kicker: 'Guides', lead: 'Getting more from the time', em: 'between sessions', art: 'individual', sub: 'Practical guides for clients and the professionals who work with them.' },
  'guide-between-session-check-ins': { kicker: 'Guide', lead: 'What are between-session', em: 'check-ins?', art: 'therapy', sub: 'Short notes captured in the moment, so patterns are visible before the next session.' },
  'guide-what-to-talk-about-in-therapy': { kicker: 'Guide', lead: 'How to remember what to talk about in', em: 'therapy', art: 'therapy', sub: 'Why you blank in session, and simple ways to capture moments between appointments.' },
  'guide-voice-journaling-for-anxiety': { kicker: 'Guide', lead: 'Voice journaling for', em: 'anxiety', art: 'individual', sub: 'Does it actually help? Why speaking your thoughts out loud is easier to keep up than writing.' },
  'guide-therapy-homework-what-works-instead': { kicker: 'Guide', lead: 'Therapy homework, and', em: 'what works instead', art: 'therapy', sub: 'Why homework is hard to finish, and a lighter in-the-moment approach that sticks.' },
  'guide-improve-client-engagement-between-sessions': { kicker: 'Guide', lead: 'Improving client engagement', em: 'between sessions', art: 'therapy', sub: 'Practical, consent-first ways to keep clients engaged without adding to your workload.' }
};

const LOGO = readFileSync(join(root, 'public', 'favicon.svg'), 'utf8');
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
// Never break a line inside "check-ins" / "Between-session".
const keepHyphens = (s) => esc(s).split(' ').map((w) => (w.includes('-') ? `<span class="nb">${w}</span>` : w)).join(' ');

function cardHtml(c) {
  const art = 'data:image/png;base64,' + readFileSync(join(root, 'public', 'assets', 'fields', c.art + '.png')).toString('base64');
  const long = (c.lead + ' ' + c.em).length > 44;
  return `<!doctype html><html><head><meta charset="utf-8"><style>
  @font-face{font-family:Newsreader;font-style:normal;font-weight:400 700;src:url(https://fonts.gstatic.com/s/newsreader/v26/cY9VfjOCX1hbuyalUrK49dLafXjalZCsZBsSBgbNJYQ.woff2) format('woff2');}
  @font-face{font-family:Newsreader;font-style:italic;font-weight:400 700;src:url(https://fonts.gstatic.com/s/newsreader/v26/cY9XfjOCX1hbuyalUrK439vogqCz_goCYw7oReyJFYYzbA.woff2) format('woff2');}
  *{box-sizing:border-box;margin:0;padding:0}
  html,body{width:1200px;height:630px;overflow:hidden}
  body{background:#F5F4F1;color:#1A1E1C;font-family:Inter,system-ui,sans-serif;position:relative}
  .copy{position:absolute;left:72px;top:64px;bottom:60px;width:640px;display:flex;flex-direction:column}
  .brand{display:flex;align-items:center;gap:14px}
  .brand svg{width:50px;height:50px;display:block}
  .brand span{font-family:Newsreader,Georgia,serif;font-weight:600;font-size:34px;letter-spacing:-0.01em}
  .kicker{margin-top:auto;margin-bottom:14px;font-size:17px;font-weight:600;letter-spacing:0.12em;text-transform:uppercase;color:#C0392B}
  h1{font-family:Newsreader,Georgia,serif;font-weight:600;font-size:${long ? 56 : 62}px;line-height:1.08;letter-spacing:-0.02em}
  .brand + h1{margin-top:auto}
  h1 em,.nb{white-space:nowrap}
  h1 em{font-style:italic;color:#1E4C86;position:relative}
  h1 em::after{content:"";position:absolute;left:2px;right:2px;bottom:4px;height:4px;background:#DCE6F3;border-radius:3px;z-index:-1}
  p{font-size:25px;line-height:1.42;color:#5A6169;margin-top:22px;max-width:600px}
  .url{margin-top:auto;font-size:21px;font-weight:500;color:#1E4C86;letter-spacing:0.01em}
  .art{position:absolute;right:56px;top:50%;width:400px;height:400px;margin-top:-200px}
  .c{position:absolute;width:330px;height:330px;border-radius:50%;top:35px}
  .c1{left:0;background:#E2EAF5}
  .c2{left:70px;background:#F8E7E4;overflow:hidden}
  /* the overlap, like the logo's red centre: c1's circle clipped to c2 */
  .lens{position:absolute;left:-70px;top:0;width:330px;height:330px;border-radius:50%;background:#F1D3CD}
  .art img{position:absolute;left:50%;top:50%;width:310px;height:310px;margin:-155px 0 0 -155px;image-rendering:auto}
  </style></head><body>
  <div class="copy">
    <div class="brand">${LOGO}<span>Between</span></div>${c.kicker ? `
    <div class="kicker">${esc(c.kicker)}</div>` : ''}
    <h1>${keepHyphens(c.lead)} <em>${esc(c.em)}</em></h1>
    <p>${esc(c.sub)}</p>
    <div class="url">betweenpsych.com</div>
  </div>
  <div class="art"><div class="c c1"></div><div class="c c2"><div class="lens"></div></div><img src="${art}" alt=""></div>
  </body></html>`;
}

const outDir = join(root, 'public', 'og');
mkdirSync(outDir, { recursive: true });
const browser = await chromium.launch();
try {
  const page = await browser.newPage({ viewport: { width: 1200, height: 630 }, deviceScaleFactor: 1 });
  if (process.env.OG_FONT_DIR) {
    await page.route('https://fonts.gstatic.com/**', (route) => {
      const italic = route.request().url().includes('cY9Xf');
      route.fulfill({ contentType: 'font/woff2', body: readFileSync(join(process.env.OG_FONT_DIR, italic ? 'newsreader-latin-italic.woff2' : 'newsreader-latin.woff2')) });
    });
  }
  for (const [slug, c] of Object.entries({ ...CARDS, ...GUIDES })) {
    await page.setContent(cardHtml(c), { waitUntil: 'load' });
    await page.evaluate(() => document.fonts.ready);
    const h1 = await page.$eval('h1', (el) => el.getBoundingClientRect().height);
    await page.screenshot({ path: join(outDir, slug + '.png') });
    console.log(`${slug}.png  (headline ${Math.round(h1)}px tall)`);
  }
} finally {
  await browser.close();
}
