// Thin Stripe helper — talks to the Stripe REST API directly over fetch, so we
// don't pull in the SDK. Everything is gated on STRIPE_SECRET_KEY: if it's
// unset, stripeConfigured() is false and callers fall back to creating the
// account without charging (dev/no-Stripe mode). STRIPE_API_BASE lets tests
// point at a mock server instead of the real api.stripe.com.
import crypto from 'crypto';

const BASE = process.env.STRIPE_API_BASE || 'https://api.stripe.com';

export function stripeConfigured() {
  return !!process.env.STRIPE_SECRET_KEY;
}

// Which Stripe Price a plan id maps to. Set these to your real price_… ids.
export function priceForPlan(plan) {
  const map = {
    patient_monthly: process.env.STRIPE_PRICE_PATIENT_MONTHLY,
    patient_annual: process.env.STRIPE_PRICE_PATIENT_ANNUAL
  };
  return map[plan] || null;
}

async function stripeRequest(method, path, params) {
  const key = process.env.STRIPE_SECRET_KEY;
  if (!key) throw new Error('Stripe is not configured.');
  const opts = { method, headers: { Authorization: 'Bearer ' + key } };
  if (params) {
    opts.headers['Content-Type'] = 'application/x-www-form-urlencoded';
    // params is already a flat map of Stripe's bracket-notation keys.
    opts.body = new URLSearchParams(params).toString();
  }
  const resp = await fetch(BASE + path, opts);
  const data = await resp.json().catch(() => null);
  if (!resp.ok) {
    const err = new Error((data && data.error && data.error.message) || ('Stripe error ' + resp.status));
    err.status = resp.status;
    throw err;
  }
  return data;
}

// Creates a hosted Checkout session for a subscription. The patient is sent to
// session.url to enter their card; Stripe redirects back to success/cancel.
export async function createSubscriptionCheckout({ priceId, customerEmail, patientId, successUrl, cancelUrl }) {
  return stripeRequest('POST', '/v1/checkout/sessions', {
    mode: 'subscription',
    'line_items[0][price]': priceId,
    'line_items[0][quantity]': '1',
    customer_email: customerEmail,
    client_reference_id: patientId,
    'subscription_data[metadata][patient_id]': patientId,
    'metadata[patient_id]': patientId,
    success_url: successUrl,
    cancel_url: cancelUrl,
    allow_promotion_codes: 'true'
  });
}

export async function retrieveCheckoutSession(id) {
  return stripeRequest('GET', '/v1/checkout/sessions/' + encodeURIComponent(id));
}

// Verifies a Stripe webhook signature (the Stripe-Signature header) against the
// raw request body using the webhook signing secret. Returns the parsed event,
// or throws if the signature is missing/stale/invalid.
export function constructWebhookEvent(rawBody, signatureHeader, secret, toleranceSeconds = 300) {
  if (!secret) throw new Error('No webhook secret configured.');
  if (!signatureHeader) throw new Error('Missing Stripe-Signature header.');
  const parts = Object.fromEntries(
    signatureHeader.split(',').map(kv => kv.split('=').map(s => s.trim()))
  );
  const timestamp = parts.t;
  const expected = parts.v1;
  if (!timestamp || !expected) throw new Error('Malformed signature header.');
  const payload = timestamp + '.' + (Buffer.isBuffer(rawBody) ? rawBody.toString('utf8') : rawBody);
  const digest = crypto.createHmac('sha256', secret).update(payload, 'utf8').digest('hex');
  const a = Buffer.from(digest); const b = Buffer.from(expected);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
    throw new Error('Signature verification failed.');
  }
  if (Math.abs(Math.floor(Date.now() / 1000) - Number(timestamp)) > toleranceSeconds) {
    throw new Error('Signature timestamp outside tolerance.');
  }
  return JSON.parse(Buffer.isBuffer(rawBody) ? rawBody.toString('utf8') : rawBody);
}
