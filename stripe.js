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

// The env var base name for each plan. The CAD price lives in that var; the USD
// price (for US customers) lives in the same name with a _USD suffix, e.g.
// STRIPE_PRICE_PATIENT_MONTHLY (CAD) and STRIPE_PRICE_PATIENT_MONTHLY_USD.
const PLAN_PRICE_VAR = {
  patient_monthly: 'STRIPE_PRICE_PATIENT_MONTHLY',
  patient_annual: 'STRIPE_PRICE_PATIENT_ANNUAL',
  patient_premium: 'STRIPE_PRICE_PATIENT_PREMIUM',
  patient_premium_annual: 'STRIPE_PRICE_PATIENT_PREMIUM_ANNUAL',
  solo_monthly: 'STRIPE_PRICE_THERAPIST_MONTHLY',
  solo_annual: 'STRIPE_PRICE_THERAPIST_ANNUAL',
  solo_premium: 'STRIPE_PRICE_THERAPIST_PREMIUM',
  team_monthly: 'STRIPE_PRICE_TEAM_MONTHLY',
  team_annual: 'STRIPE_PRICE_TEAM_ANNUAL',
  team_premium: 'STRIPE_PRICE_TEAM_PREMIUM',
  school_monthly: 'STRIPE_PRICE_SCHOOL_MONTHLY',
  school_annual: 'STRIPE_PRICE_SCHOOL_ANNUAL',
  school_premium: 'STRIPE_PRICE_SCHOOL_PREMIUM',
  trainer_monthly: 'STRIPE_PRICE_TRAINER_MONTHLY',
  trainer_annual: 'STRIPE_PRICE_TRAINER_ANNUAL',
  trainer_premium: 'STRIPE_PRICE_TRAINER_PREMIUM',
  mentor_monthly: 'STRIPE_PRICE_MENTOR_MONTHLY',
  mentor_annual: 'STRIPE_PRICE_MENTOR_ANNUAL'
};

// Which Stripe Price a plan id maps to, in the requested currency. Pass 'USD'
// to bill a US customer in dollars — if a USD price isn't configured for that
// plan it safely falls back to the CAD price (the customer's bank converts), so
// enabling USD is purely additive and never breaks an unconfigured plan.
export function priceForPlan(plan, currency) {
  const base = PLAN_PRICE_VAR[plan];
  if (!base) return null;
  if (String(currency).toUpperCase() === 'USD' && process.env[base + '_USD']) {
    return process.env[base + '_USD'];
  }
  return process.env[base] || null;
}

// True once at least one USD price id is configured, so the site can tell US
// visitors they'll be billed in USD (rather than the CAD-conversion fallback).
export function usdConfigured() {
  return Object.values(PLAN_PRICE_VAR).some(base => !!process.env[base + '_USD']);
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

export async function retrieveSubscription(id) {
  return stripeRequest('GET', '/v1/subscriptions/' + encodeURIComponent(id));
}

// Change an existing subscription's plan by swapping the price on its single
// line item — this keeps the SAME subscription (no second one is created, so no
// double billing) and prorates the difference. Used for in-place upgrades and
// downgrades. Returns the updated subscription.
export async function changeSubscriptionPrice(subscriptionId, newPriceId, prorationBehavior = 'create_prorations') {
  const sub = await retrieveSubscription(subscriptionId);
  const itemId = sub && sub.items && sub.items.data && sub.items.data[0] && sub.items.data[0].id;
  if (!itemId) throw new Error('Subscription has no line item to update.');
  return stripeRequest('POST', '/v1/subscriptions/' + encodeURIComponent(subscriptionId), {
    'items[0][id]': itemId,
    'items[0][price]': newPriceId,
    proration_behavior: prorationBehavior
  });
}

// Cancel-at-period-end (kind cancel: keep access through the paid period) or
// undo it. Pass cancel=false to reactivate a subscription set to cancel.
export async function setSubscriptionCancelAtPeriodEnd(subscriptionId, cancel) {
  return stripeRequest('POST', '/v1/subscriptions/' + encodeURIComponent(subscriptionId), {
    cancel_at_period_end: cancel ? 'true' : 'false'
  });
}

// A Stripe-hosted page where the customer updates their card, sees invoices and
// manages their subscription. We never see or store card details ourselves.
// End a subscription right now (no further invoices or payment retries). Used
// when the last payment failed: there is no paid period left to run out.
export async function cancelSubscriptionNow(subscriptionId) {
  return stripeRequest('DELETE', '/v1/subscriptions/' + encodeURIComponent(subscriptionId));
}

export async function createBillingPortalSession(customerId, returnUrl) {
  return stripeRequest('POST', '/v1/billing_portal/sessions', {
    customer: customerId,
    return_url: returnUrl
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

// ---- Owner check: is every plan's Stripe price set up the way the site sells it? ----
// Reads each configured price from Stripe (read-only) and reports, in plain
// words, anything that would break checkout: no price set, a price Stripe does
// not know, a one-time price where a subscription is needed, the wrong billing
// period, an archived price, or the wrong currency. No price ids are returned.
const PLAN_LABEL = {
  patient_monthly: 'Personal, monthly', patient_annual: 'Personal, yearly',
  patient_premium: 'Personal Premium, monthly', patient_premium_annual: 'Personal Premium, yearly',
  solo_monthly: 'Solo, monthly', solo_annual: 'Solo, yearly', solo_premium: 'Solo Premium, monthly',
  team_monthly: 'Team, monthly', team_annual: 'Team, yearly', team_premium: 'Team Premium, monthly',
  school_monthly: 'School, monthly', school_annual: 'School, yearly', school_premium: 'School Premium, monthly',
  trainer_monthly: 'Trainer, monthly', trainer_annual: 'Trainer, yearly', trainer_premium: 'Trainer Premium, monthly',
  mentor_monthly: 'Mentor (addiction support), monthly', mentor_annual: 'Mentor (addiction support), yearly'
};
export async function auditPrices() {
  const rows = [];
  for (const [plan, base] of Object.entries(PLAN_PRICE_VAR)) {
    const wantInterval = /_annual$/.test(plan) ? 'year' : 'month';
    for (const cur of ['CAD', 'USD']) {
      const envVar = cur === 'USD' ? base + '_USD' : base;
      const id = process.env[envVar];
      if (!id && cur === 'USD') continue;            // USD prices are optional
      const row = { plan, label: PLAN_LABEL[plan] || plan, currency: cur, setting: envVar, wantInterval, ok: false, problem: null, amount: null, interval: null };
      rows.push(row);
      if (!id) { row.problem = 'missing'; continue; }
      let price;
      try { price = await stripeRequest('GET', '/v1/prices/' + encodeURIComponent(id)); }
      catch (err) { row.problem = (err && err.status === 404) ? 'not_found' : 'stripe_error'; row.detail = String((err && err.message) || '').slice(0, 200); continue; }
      row.amount = typeof price.unit_amount === 'number' ? price.unit_amount / 100 : null;
      row.priceCurrency = String(price.currency || '').toUpperCase();
      row.interval = price.recurring ? price.recurring.interval : null;
      const every = price.recurring ? (price.recurring.interval_count || 1) : 1;
      if (price.type !== 'recurring' || !price.recurring) row.problem = 'one_time';
      else if (row.interval !== wantInterval || every !== 1) row.problem = 'wrong_interval';
      else if (price.active === false) row.problem = 'archived';
      else if (row.priceCurrency !== cur) row.problem = 'wrong_currency';
      else row.ok = true;
    }
  }
  return rows;
}
