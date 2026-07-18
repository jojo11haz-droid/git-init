import crypto from 'crypto';

// Password hashing + session tokens using Node's built-in crypto (scrypt),
// so there are no extra dependencies to audit. Hash format:
//   scrypt$N$r$p$<salt hex>$<derived key hex>
// The parameters are stored per-hash so they can be raised later without
// invalidating existing accounts.

const SCRYPT_N = 16384;
const SCRYPT_R = 8;
const SCRYPT_P = 1;
const KEY_LEN = 64;

function scryptAsync(password, salt, N, r, p) {
  return new Promise((resolve, reject) => {
    crypto.scrypt(password, salt, KEY_LEN, { N, r, p, maxmem: 128 * 1024 * 1024 }, (err, key) => {
      if (err) reject(err); else resolve(key);
    });
  });
}

export async function hashPassword(password) {
  const salt = crypto.randomBytes(16);
  const key = await scryptAsync(password, salt, SCRYPT_N, SCRYPT_R, SCRYPT_P);
  return `scrypt$${SCRYPT_N}$${SCRYPT_R}$${SCRYPT_P}$${salt.toString('hex')}$${key.toString('hex')}`;
}

export async function verifyPassword(password, stored) {
  try {
    const [scheme, nStr, rStr, pStr, saltHex, keyHex] = (stored || '').split('$');
    if (scheme !== 'scrypt') return false;
    const expected = Buffer.from(keyHex, 'hex');
    const actual = await scryptAsync(password, Buffer.from(saltHex, 'hex'),
      parseInt(nStr, 10), parseInt(rStr, 10), parseInt(pStr, 10));
    return actual.length === expected.length && crypto.timingSafeEqual(actual, expected);
  } catch {
    return false;
  }
}

// Session tokens: the browser holds the random token; the database only ever
// stores its SHA-256, so a leaked DB dump can't be replayed as a session.

export const SESSION_COOKIE = 'between_session';
export const SESSION_TTL_DAYS = 30;

export function generateSessionToken() {
  return crypto.randomBytes(32).toString('base64url');
}

export function hashSessionToken(token) {
  return crypto.createHash('sha256').update(token).digest('hex');
}

export function readSessionCookie(req) {
  const header = req.headers.cookie;
  if (!header) return null;
  for (const part of header.split(';')) {
    const eq = part.indexOf('=');
    if (eq === -1) continue;
    if (part.slice(0, eq).trim() === SESSION_COOKIE) {
      return decodeURIComponent(part.slice(eq + 1).trim());
    }
  }
  return null;
}

export function sessionCookieHeader(token, req, { clear = false } = {}) {
  const secure = req.secure || req.headers['x-forwarded-proto'] === 'https';
  const attrs = [
    `${SESSION_COOKIE}=${clear ? '' : encodeURIComponent(token)}`,
    'HttpOnly',
    'Path=/',
    'SameSite=Lax',
    clear ? 'Max-Age=0' : `Max-Age=${SESSION_TTL_DAYS * 24 * 60 * 60}`
  ];
  if (secure) attrs.push('Secure');
  return attrs.join('; ');
}
