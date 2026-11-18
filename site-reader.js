// Reads a clinic's public website as plain text, for the owner's outreach
// tool (a personal first line written from the clinic's own words).
//
// Safety: only http(s); the host must resolve to public addresses (no
// localhost, private, link-local or metadata ranges), redirects are checked
// the same way, each page is size- and time-limited, and only a few pages on
// the same site are read: the home page plus its about / team / services pages.
import dns from 'dns/promises';
import net from 'net';

const MAX_BYTES = 600 * 1024;
const TIMEOUT_MS = 8000;
const MAX_PAGES = 4;
const MAX_CHARS = 14000;
// Subpages worth reading: who they are, how they work, what they treat.
const SUBPAGE = /(a-propos|apropos|about|qui-sommes|equipe|équipe|team|notre-|our-|services|approche|approach|specialit|spécialit|mission|clinique|clinic|physio|therap|soins|treatment)/i;

function isPrivateIp(ip) {
  if (net.isIPv4(ip)) {
    const [a, b] = ip.split('.').map(Number);
    return a === 10 || a === 127 || a === 0 || (a === 169 && b === 254) || (a === 172 && b >= 16 && b <= 31) ||
      (a === 192 && b === 168) || (a === 100 && b >= 64 && b <= 127) || a >= 224;
  }
  const v = ip.toLowerCase();
  return v === '::1' || v === '::' || v.startsWith('fc') || v.startsWith('fd') || v.startsWith('fe80') ||
    (v.startsWith('::ffff:') && isPrivateIp(v.slice(7)));
}

async function assertPublic(u, allowLocal) {
  if (u.protocol !== 'http:' && u.protocol !== 'https:') throw new Error('bad_url');
  if (allowLocal) return;
  const host = u.hostname.replace(/^\[|\]$/g, '');
  if (host === 'localhost' || host.endsWith('.local') || host.endsWith('.internal')) throw new Error('bad_url');
  const addrs = net.isIP(host) ? [host] : (await dns.lookup(host, { all: true })).map(a => a.address);
  if (!addrs.length || addrs.some(isPrivateIp)) throw new Error('bad_url');
}

async function fetchPage(url, allowLocal) {
  let u = new URL(url);
  for (let hop = 0; hop < 4; hop++) {
    await assertPublic(u, allowLocal);
    const ctl = new AbortController();
    const timer = setTimeout(() => ctl.abort(), TIMEOUT_MS);
    let res;
    try {
      res = await fetch(u, { redirect: 'manual', signal: ctl.signal,
        headers: { 'User-Agent': 'Mozilla/5.0 (compatible; BetweenOutreach/1.0)', 'Accept': 'text/html,application/xhtml+xml', 'Accept-Language': 'fr-CA,fr;q=0.9,en;q=0.8' } });
    } finally { clearTimeout(timer); }
    if (res.status >= 300 && res.status < 400 && res.headers.get('location')) { u = new URL(res.headers.get('location'), u); continue; }
    if (!res.ok) throw new Error('http_' + res.status);
    const type = res.headers.get('content-type') || '';
    if (type && !/html|text\/plain/i.test(type)) throw new Error('not_html');
    const reader = res.body.getReader(); const chunks = []; let n = 0;
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      n += value.length; chunks.push(value);
      if (n > MAX_BYTES) { try { await reader.cancel(); } catch (e) {} break; }
    }
    return { url: u.toString(), html: Buffer.concat(chunks.map(c => Buffer.from(c))).toString('utf8') };
  }
  throw new Error('too_many_redirects');
}

const ENT = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', eacute: 'é', egrave: 'è', ecirc: 'ê', agrave: 'à', acirc: 'â', ccedil: 'ç', ocirc: 'ô', ucirc: 'û', ugrave: 'ù', icirc: 'î', iuml: 'ï', euml: 'ë', rsquo: '’', lsquo: '‘', ldquo: '“', rdquo: '”', laquo: '«', raquo: '»', hellip: '…', ndash: '–', mdash: '—', Eacute: 'É', Agrave: 'À' };
function decode(s) {
  return s.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (m, e) => e[0] === '#'
    ? String.fromCodePoint(e[1].toLowerCase() === 'x' ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10))
    : (ENT[e] != null ? ENT[e] : m));
}
export function htmlToText(html) {
  const title = (html.match(/<title[^>]*>([\s\S]*?)<\/title>/i) || [])[1] || '';
  const desc = (html.match(/<meta[^>]+name=["']description["'][^>]*content=["']([^"']*)["']/i) || [])[1] || '';
  let body = html.replace(/<(script|style|noscript|svg|iframe|template)[\s\S]*?<\/\1>/gi, ' ')
    .replace(/<!--[\s\S]*?-->/g, ' ')
    .replace(/<(br|\/p|\/div|\/li|\/h\d|\/section|\/tr)[^>]*>/gi, '\n')
    .replace(/<[^>]+>/g, ' ');
  body = decode(body).replace(/[ \t\f\v\r]+/g, ' ').replace(/\n\s*/g, '\n').replace(/\n{2,}/g, '\n').trim();
  return [decode(title).trim(), decode(desc).trim(), body].filter(Boolean).join('\n');
}

function subpageLinks(html, base) {
  const out = []; const seen = new Set([base.split('#')[0]]);
  const b = new URL(base);
  for (const m of html.matchAll(/<a\b[^>]*href=["']([^"'#]+)["'][^>]*>([\s\S]*?)<\/a>/gi)) {
    let u; try { u = new URL(decode(m[1]), b); } catch (e) { continue; }
    if (u.hostname !== b.hostname || !/^https?:$/.test(u.protocol) || /\.(pdf|jpe?g|png|gif|webp|zip|docx?)$/i.test(u.pathname)) continue;
    const key = u.toString().split('#')[0];
    if (seen.has(key)) continue;
    if (SUBPAGE.test(u.pathname) || SUBPAGE.test(m[2].replace(/<[^>]+>/g, ''))) { seen.add(key); out.push(key); }
  }
  return out.slice(0, MAX_PAGES - 1);
}

// → { pages: [{ url, text }], text } or throws (bad_url / http_xxx / not_html / timeout).
export async function readSite(url, opts = {}) {
  const allowLocal = !!opts.allowLocal;
  let start = String(url || '').trim();
  if (/^[a-z][a-z0-9+.-]*:/i.test(start) && !/^https?:\/\//i.test(start)) throw new Error('bad_url'); // file:, ftp:, javascript:…
  if (!/^https?:\/\//i.test(start)) start = 'https://' + start;
  const home = await fetchPage(start, allowLocal);
  const pages = [{ url: home.url, text: htmlToText(home.html) }];
  for (const link of subpageLinks(home.html, home.url)) {
    try { const p = await fetchPage(link, allowLocal); pages.push({ url: p.url, text: htmlToText(p.html) }); } catch (e) {}
  }
  let budget = MAX_CHARS; const parts = [];
  for (const p of pages) {
    if (budget <= 0) break;
    const t = p.text.slice(0, Math.max(1500, Math.floor(MAX_CHARS / pages.length)));
    const piece = t.slice(0, budget);
    parts.push('--- ' + p.url + '\n' + piece); budget -= piece.length;
  }
  return { pages: pages.map(p => ({ url: p.url })), text: parts.join('\n\n') };
}
