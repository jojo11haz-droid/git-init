// Small in-memory fixed-window rate limiter — enough for a single-instance
// deploy (Render/Railway free tier). If this ever runs multi-instance, swap
// the Map for something shared (Redis or a Postgres counter): each instance
// currently counts separately.

export function rateLimit({ windowMs, max, keyFn, message }) {
  const hits = new Map(); // key -> { count, windowStart }

  // Prune dead windows so long-running servers don't accumulate old keys.
  const prune = setInterval(() => {
    const now = Date.now();
    for (const [key, entry] of hits) {
      if (now - entry.windowStart >= windowMs) hits.delete(key);
    }
  }, windowMs);
  prune.unref(); // don't keep the process alive for the timer

  return function rateLimitMiddleware(req, res, next) {
    const key = keyFn ? keyFn(req) : req.ip;
    const now = Date.now();
    let entry = hits.get(key);
    if (!entry || now - entry.windowStart >= windowMs) {
      entry = { count: 0, windowStart: now };
      hits.set(key, entry);
    }
    entry.count++;
    if (entry.count > max) {
      const retryAfterSec = Math.ceil((entry.windowStart + windowMs - now) / 1000);
      res.setHeader('Retry-After', String(retryAfterSec));
      return res.status(429).json({
        error: message || 'Too many requests — please wait a moment and try again.'
      });
    }
    next();
  };
}
