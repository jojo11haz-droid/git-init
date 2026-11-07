// Personalization: a professional's branding (what their clients see) and an
// individual's own page preferences. Pure helpers so they can be unit-tested.
//
// Accents are preset keys, never free-form colours, so nobody can pick a
// colour that makes buttons unreadable; the web and app map each key to a
// light and a dark shade.

export const ACCENTS = ['blue', 'teal', 'green', 'plum', 'berry', 'clay', 'slate', 'indigo'];
// Sections an individual can hide from their own check-in page.
export const HIDEABLE = ['streak', 'reflection', 'goals'];

const clip = (v, n) => (typeof v === 'string' ? v.replace(/[\u0000-\u0008\u000B-\u001F\u007F]/g, '').trim().slice(0, n) : '');

// What a professional saved. Unknown keys are dropped; an unknown accent is
// cleared. The logo itself is stored separately; `logo_v` only versions its URL.
export function sanitizeBrand(input, prev) {
  const b = input && typeof input === 'object' ? input : {};
  const out = {
    clinic: clip(b.clinic, 80),
    welcome: clip(b.welcome, 500),
    accent: ACCENTS.includes(b.accent) ? b.accent : ''
  };
  const v = prev && typeof prev === 'object' ? prev.logo_v : null;
  if (v) out.logo_v = String(v).slice(0, 20);
  return out;
}

// What clients actually get. The welcome note is free for everyone; the clinic
// name, logo and accent are Premium. A lapsed plan keeps the saved values but
// stops showing them until Premium is back.
export function effectiveBrand(clinicianId, brand, premium) {
  const b = brand && typeof brand === 'object' ? brand : {};
  const out = {};
  const welcome = clip(b.welcome, 500);
  if (welcome) out.welcome = welcome;
  if (premium) {
    const clinic = clip(b.clinic, 80);
    if (clinic) out.clinic = clip(clinic, 80);
    if (ACCENTS.includes(b.accent)) out.accent = b.accent;
    if (b.logo_v && clinicianId) out.logo_url = '/api/brand-logo/' + encodeURIComponent(clinicianId) + '?v=' + encodeURIComponent(String(b.logo_v));
  }
  return Object.keys(out).length ? out : null;
}

// An individual's own preferences (Premium).
export function sanitizePrefs(input) {
  const p = input && typeof input === 'object' ? input : {};
  const hide = Array.isArray(p.hide) ? [...new Set(p.hide.filter(h => HIDEABLE.includes(h)))] : [];
  return { accent: ACCENTS.includes(p.accent) ? p.accent : '', hide };
}

// Logos: PNG, JPEG or WebP only (never SVG, which can carry script), checked
// by their magic bytes rather than the declared type.
export const LOGO_MAX_BYTES = 300 * 1024;
export function sniffImage(buf) {
  if (!buf || buf.length < 12) return null;
  if (buf[0] === 0x89 && buf[1] === 0x50 && buf[2] === 0x4E && buf[3] === 0x47) return 'image/png';
  if (buf[0] === 0xFF && buf[1] === 0xD8 && buf[2] === 0xFF) return 'image/jpeg';
  if (buf.slice(0, 4).toString('latin1') === 'RIFF' && buf.slice(8, 12).toString('latin1') === 'WEBP') return 'image/webp';
  return null;
}
