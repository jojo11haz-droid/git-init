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
    patient_annual: process.env.STRIPE_PRICE_PATIENT_ANNUAL,
    solo_monthly: process.env.STRIPE_PRICE_THERAPIST_MONTHLY,
    solo_annual: process.env.STRIPE_PRICE_THERAPIST_ANNUAL,
    solo_premium: process.env.STRIPE_PRICE_THERAPIST_PREMIUM,
    team_monthly: process.env.STRIPE_PRICE_TEAM_MONTHLY,
    team_annual: process.env.STRIPE_PRICE_TEAM_ANNUAL,
    team_premium: process.env.STRIPE_PRICE_TEAM_PREMIUM,
    school_monthly: process.env.STRIPE_PRICE_SCHOOL_MONTHLY,
    school_annual: process.env.STRIPE_PRICE_SCHOOL_ANNUAL,
    school_premium: process.env.STRIPE_PRICE_SCHOOL_PREMIUM,
    trainer_monthly: process.env.STRIPE_PRICE_TRAINER_MONTHLY,
    trainer_annual: process.env.STRIPE_PRICE_TRAINER_ANNUAL,
    trainer_premium: process.env.STRIPE_PRICE_TRAINER_PREMIUM,
    mentor_monthly: process.env.STRIPE_PRICE_MENTOR_MONTHLY,
    mentor_annual: process.env.STRIPE_PRICE_MENTOR_ANNUAL
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

// Creates a hosted Checkout session for a subscription. The user is sent to
// session.url to enter their card; Stripe redirects back to success/cancel.
// refType is 'patient' or 'clinician' — the id is stamped on both the session
// and the subscription metadata so we can reconcile on return and via webhook.
// trialDays (optional) starts the subscription with a free trial (no charge
// today), used for clinician plans.
export async function createSubscriptionCheckout({ priceId, customerEmail, refType, refId, trialDays, successUrl, cancelUrl }) {
  const metaKey = (refType || 'patient') + '_id';
  const params = {
    mode: 'subscription',
    'line_items[0][price]': priceId,
    'line_items[0][quantity]': '1',
    customer_email: customerEmail,
    client_reference_id: refId,
    ['subscription_data[metadata][' + metaKey + ']']: refId,
    ['metadata[' + metaKey + ']']: refId,
    success_url: successUrl,
    cancel_url: cancelUrl,
    allow_promotion_codes: 'true'
  };
  if (trialDays && Number(trialDays) > 0) {
    params['subscription_data[trial_period_days]'] = String(Math.floor(trialDays));
  }
  return stripeRequest('POST', '/v1/checkout/sessions', params);
}

export async function retrieveCheckoutSession(id) {
  return stripeRequest('GET', '/v1/checkout/sessions/' + encodeURIComponent(id));
}

// Cancel-at-period-end (kind cancel: keep access through the paid period) or
// undo it. Pass cancel=false to reactivate a subscription set to cancel.
export async function setSubscriptionCancelAtPeriodEnd(subscriptionId, cancel) {
  return stripeRequest('POST', '/v1/subscriptions/' + encodeURIComponent(subscriptionId), {
    cancel_at_period_end: cancel ? 'true' : 'false'
  });
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
