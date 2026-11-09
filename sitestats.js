// Website statistics, privacy-first: the browser sends a tiny event ("someone
// opened the Pricing page on a phone, in French, for physio") and we add 1 to
// that day's total. No cookies, no visitor ID, no IP address, no user agent is
// stored — only daily counts. Everything is checked against fixed lists so the
// table can't be filled with junk.

export const STAT_EVENTS = [
  'visit',         // a new browser tab opened the site (once per tab)
  'view',          // a page was opened (home, how it works, pricing, guide, dashboard)
  'signup_click',  // pressed a "Start free trial" / "Sign up" button
  'login_click',
  'demo_open',     // opened "Book a 15-min demo"
  'demo_sent',     // sent the demo request
  'tour_start',    // "Walk me through it"
  'voice_demo',    // tried the demo mic
  'try_demo'       // sent a check-in in the live demo
];
export const STAT_FIELDS = ['therapy', 'individual', 'physio', 'kinesiology', 'osteo', 'occupational', 'neuropsych', 'nutrition', 'sports', 'fitness', 'recovery', 'schools'];
export const STAT_PAGES = ['home', 'learn', 'pricing', 'guide', 'product', 'features', 'chooser'];

const BOT_RE = /bot|crawl|spider|slurp|preview|headless|lighthouse|facebookexternalhit|embedly|monitor|curl|wget|python|axios|node-fetch/i;

// Where the visit came from: a search engine / site name, a campaign tag, or "direct".
export function cleanSource(s) {
  if (!s || typeof s !== 'string') return 'direct';
  let v = s.trim().toLowerCase();
  try { if (/^https?:\/\//.test(v)) v = new URL(v).hostname; } catch (e) { return 'direct'; }
  v = v.replace(/^www\./, '').replace(/^m\./, '').replace(/^l\./, '').replace(/^lm\./, '');
  // Group the big ones so the list stays readable.
  if (/(^|\.)google\./.test(v)) return 'google';
  if (/(^|\.)bing\.com$/.test(v)) return 'bing';
  if (/duckduckgo\.com$/.test(v)) return 'duckduckgo';
  if (/(^|\.)facebook\.com$|(^|\.)fb\.com$/.test(v)) return 'facebook';
  if (/instagram\.com$/.test(v)) return 'instagram';
  if (/linkedin\.com$|lnkd\.in$/.test(v)) return 'linkedin';
  if (/(^|\.)t\.co$|twitter\.com$|x\.com$/.test(v)) return 'x';
  if (/chatgpt\.com$|openai\.com$/.test(v)) return 'chatgpt';
  if (/perplexity\.ai$/.test(v)) return 'perplexity';
  if (/claude\.ai$/.test(v)) return 'claude';
  if (/betweenpsych\.com$/.test(v)) return 'direct';
  v = v.replace(/[^a-z0-9.\-_]/g, '').slice(0, 40);
  return v || 'direct';
}

// Turn the browser's report into one row to count, or null to ignore it.
export function sanitizeStat(body, userAgent) {
  if (!body || typeof body !== 'object') return null;
  if (BOT_RE.test(String(userAgent || ''))) return null;
  const event = String(body.e || '');
  if (!STAT_EVENTS.includes(event)) return null;
  const field = STAT_FIELDS.includes(body.f) ? body.f : '';
  const page = STAT_PAGES.includes(body.p) ? body.p : '';
  const lang = body.l === 'fr' ? 'fr' : 'en';
  const device = ['phone', 'tablet', 'desktop'].includes(body.d) ? body.d : '';
  // Only a visit carries a source; other events would just repeat it.
  const source = event === 'visit' ? cleanSource(body.s) : '';
  return { event, field, page, source, lang, device };
}
