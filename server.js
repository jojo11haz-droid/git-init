import express from 'express';
import path from 'path';
import { fileURLToPath } from 'url';
import {
  dbEnabled, initDb, createPatient, setPatientConsent, getPatient, listPatients, markPatientReviewed,
  createCheckIn, listCheckIns, softDeleteCheckIn, deleteAllCheckIns,
  createClinician, getClinicianByEmail, createSession, getClinicianBySession, deleteSession,
  listCliniciansForReview, setClinicianLicenceVerified,
  updateClinicianSubscription, getClinicianByStripeSubscription,
  getPatientByInviteCode, getPatientByEmail, acceptPatientInvite, createSelfServePatient, setOwnConsent,
  updatePatientSubscription, getPatientById, getPatientByStripeSubscription, getPatientStripe, getClinicianStripe,
  createPatientSession, getPatientBySession, deletePatientSession,
  flagCheckInInaccurate, getCheckIn,
  createFutureNote, listFutureNotes, deleteFutureNote,
  getClinicianById, createPasswordReset, getValidPasswordReset, consumePasswordReset,
  resetPatientAccess, deletePatient,
  createAudioUploadToken, consumeAudioUploadToken, storeAudioUpload,
  getAudioUploadOwned, getAudioForClinician,
  createAlert, listAlerts, markAlertViewed
} from './db.js';
import { sendEmail, emailConfigured } from './email.js';
import { transcribeAudio } from './transcribe.js';
import {
  hashPassword, verifyPassword, generateSessionToken, hashSessionToken,
  readSessionCookie, sessionCookieHeader, SESSION_TTL_DAYS,
  generateInviteCode, readBearerToken,
  generateTotpSecret, verifyTotp, otpauthUrl
} from './auth.js';
import {
  getClinicianMfa, setMfaSecret, setMfaEnabled,
  createMfaChallenge, getValidMfaChallenge, deleteMfaChallenge
} from './db.js';
import { rateLimit } from './rate-limit.js';
import {
  stripeConfigured, priceForPlan, createSubscriptionCheckout,
  retrieveCheckoutSession, constructWebhookEvent, setSubscriptionCancelAtPeriodEnd
} from './stripe.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const app = express();
app.set('trust proxy', 1); // honor x-forwarded-proto behind Render/Railway/Fly

// Stripe webhook must see the RAW body to verify the signature, so it's mounted
// before express.json() consumes it. Best-effort: activation also happens on
// the checkout return, so the app is correct even if webhooks aren't set up.
app.post('/api/stripe/webhook', express.raw({ type: '*/*' }), async (req, res) => {
  const secret = process.env.STRIPE_WEBHOOK_SECRET;
  if (!secret) return res.status(400).json({ error: 'Webhook not configured.' });
  let event;
  try {
    event = constructWebhookEvent(req.body, req.headers['stripe-signature'], secret);
  } catch (err) {
    return res.status(400).json({ error: 'Signature check failed.' });
  }
  try {
    const obj = event.data && event.data.object ? event.data.object : {};
    const meta = obj.metadata || {};
    if (event.type === 'checkout.session.completed') {
      // A trial checkout completes with payment_status 'no_payment_required';
      // treat any completed session as the subscription being live (trialing
      // or active). The next subscription.updated will refine the status.
      const fields = { status: 'active', customerId: obj.customer, subscriptionId: obj.subscription };
      if (meta.clinician_id) await updateClinicianSubscription(meta.clinician_id, fields);
      else if (meta.patient_id || obj.client_reference_id) {
        await updatePatientSubscription(meta.patient_id || obj.client_reference_id, fields);
      }
    } else if (event.type === 'customer.subscription.deleted' || event.type === 'customer.subscription.updated') {
      const status = event.type === 'customer.subscription.deleted'
        ? 'canceled'
        : (obj.cancel_at_period_end ? 'canceling' : obj.status);
      if (meta.clinician_id) await updateClinicianSubscription(meta.clinician_id, { status });
      else if (meta.patient_id) await updatePatientSubscription(meta.patient_id, { status });
      else {
        const p = await getPatientByStripeSubscription(obj.id);
        if (p) await updatePatientSubscription(p.id, { status });
        else { const c = await getClinicianByStripeSubscription(obj.id); if (c) await updateClinicianSubscription(c.id, { status }); }
      }
    }
    res.json({ received: true });
  } catch (err) {
    console.error('Error handling Stripe webhook:', err);
    res.status(500).json({ error: 'Webhook handler failed.' });
  }
});

app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

const ANTHROPIC_API_KEY = process.env.ANTHROPIC_API_KEY;
if (!ANTHROPIC_API_KEY) {
  console.warn('⚠️  ANTHROPIC_API_KEY is not set. /api/summarize will return errors until it is.');
}

const VALID_TAGS = ['Sleep', 'Work', 'Conflict', 'Craving', 'Panic', 'Family', 'Health', 'Money', 'Loneliness', 'Anger', 'Win', 'Social', 'Other'];
const MODEL_VERSION = 'claude-sonnet-5';

async function summarizeCheckIn(text) {
  if (!ANTHROPIC_API_KEY) {
    throw new Error('Server is not configured with an API key.');
  }

  const prompt = `A patient sent this between-session check-in to their therapist: "${text.replace(/"/g, '\\"')}"

Respond with ONLY a JSON object, no preamble, no markdown fences, in exactly this shape:
{"summary": "2-3 neutral sentences describing what the patient reported, close to their own words, no clinical diagnosis or interpretation. Write the summary in the SAME language the patient wrote in (e.g. French if they wrote in French).", "auto_tags": ["choose 0-3 from these exact English keys regardless of the patient's language: Sleep, Work, Conflict, Craving, Panic, Family, Health, Money, Loneliness, Anger, Win, Social, Other"], "mood_estimate": an integer from 1 (very low) to 10 (very good) estimating the patient's current mood from what they wrote, or null if there is genuinely not enough emotional content to estimate, "risk_flag": true or false (true ONLY if there is language, in any language, suggesting self-harm, suicidal ideation, or an acute safety concern)}`;

  const response = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': ANTHROPIC_API_KEY,
      'anthropic-version': '2023-06-01'
    },
    body: JSON.stringify({
      model: MODEL_VERSION,
      max_tokens: 500,
      messages: [{ role: 'user', content: prompt }]
    })
  });

  if (!response.ok) {
    const errText = await response.text();
    console.error('Anthropic API error:', response.status, errText);
    throw new Error('AI summarization failed.');
  }

  const data = await response.json();
  const raw = (data.content || []).map(b => b.text || '').join('');
  const clean = raw.replace(/```json|```/g, '').trim();

  let parsed;
  try {
    parsed = JSON.parse(clean);
  } catch (e) {
    console.error('Model did not return valid JSON:', clean);
    throw new Error('AI returned an unexpected format.');
  }

  // An estimated mood, only when the model returned a whole number in 1..10.
  let moodEstimate = null;
  const me = parsed.mood_estimate;
  if (typeof me === 'number' && Number.isFinite(me)) {
    const r = Math.round(me);
    if (r >= 1 && r <= 10) moodEstimate = r;
  }

  return {
    summary: typeof parsed.summary === 'string' ? parsed.summary.slice(0, 1000) : 'Check-in received.',
    auto_tags: Array.isArray(parsed.auto_tags) ? parsed.auto_tags.filter(t => VALID_TAGS.includes(t)).slice(0, 3) : [],
    mood_estimate: moodEstimate,
    risk_flag: parsed.risk_flag === true
  };
}

// --- Rate limits ---
// All in-memory (single instance). Login is keyed per IP+email so one office
// behind a shared IP can't lock everyone out, with a wider per-IP backstop
// against sweeping many emails from one machine.

const summarizeLimiter = rateLimit({
  windowMs: 60 * 1000, max: 10,
  message: 'Too many summarize requests — wait a minute and try again.'
});
const loginEmailLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, max: 10,
  keyFn: req => req.ip + '|' + String((req.body && req.body.email) || '').trim().toLowerCase(),
  message: 'Too many login attempts for this account — wait 15 minutes and try again.'
});
const loginIpLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, max: 50,
  message: 'Too many login attempts — wait 15 minutes and try again.'
});
const signupLimiter = rateLimit({
  windowMs: 60 * 60 * 1000, max: 10,
  message: 'Too many signup attempts — wait an hour and try again.'
});
const checkInLimiter = rateLimit({
  windowMs: 60 * 1000, max: 15,
  keyFn: req => (req.clinician && req.clinician.id) || req.ip,
  message: 'Too many check-ins at once — wait a minute and try again.'
});

app.post('/api/summarize', summarizeLimiter, async (req, res) => {
  try {
    const { text } = req.body || {};
    if (!text || typeof text !== 'string' || !text.trim()) {
      return res.status(400).json({ error: 'Missing "text" in request body.' });
    }
    if (text.length > 4000) {
      return res.status(400).json({ error: 'Check-in text is too long.' });
    }
    const result = await summarizeCheckIn(text);
    res.json(result);
  } catch (err) {
    console.error('Unexpected error in /api/summarize:', err);
    res.status(502).json({ error: err.message || 'Something went wrong.' });
  }
});

// --- Auth ---
// Cookie-based sessions: the token lives in an httpOnly cookie, its hash in
// the auth_sessions table. See backend-spec.md §Auth & account.

function requireDb(req, res, next) {
  if (!dbEnabled()) return res.status(503).json({ error: 'Database not configured.' });
  next();
}

async function requireAuth(req, res, next) {
  try {
    const token = readSessionCookie(req);
    if (token) {
      const clinician = await getClinicianBySession(hashSessionToken(token));
      if (clinician) {
        req.clinician = clinician;
        return next();
      }
    }
    res.status(401).json({ error: 'Not signed in.' });
  } catch (err) {
    console.error('Auth check failed:', err);
    res.status(500).json({ error: 'Could not verify session.' });
  }
}

async function startSession(res, req, clinicianId) {
  const token = generateSessionToken();
  await createSession(hashSessionToken(token), clinicianId, SESSION_TTL_DAYS);
  res.setHeader('Set-Cookie', sessionCookieHeader(token, req));
}

const EMAIL_RE = /^\S+@\S+\.\S+$/;

const THERAPIST_PLANS = ['solo_monthly', 'solo_annual'];

app.post('/api/auth/signup', requireDb, signupLimiter, async (req, res) => {
  try {
    const { name, email, password, licenceNumber, licenceOrder, province, practiceName } = req.body || {};
    const plan = THERAPIST_PLANS.includes((req.body || {}).plan) ? req.body.plan : 'solo_monthly';
    if (!name || !name.trim()) return res.status(400).json({ error: 'Name is required.' });
    if (!email || !EMAIL_RE.test(email.trim())) return res.status(400).json({ error: 'A valid email is required.' });
    if (!password || password.length < 10) return res.status(400).json({ error: 'Password must be at least 10 characters.' });
    // A licence/order number is required at signup. It isn't trusted on its own:
    // the account stays unverified (no access to patient data, no billing) until
    // the owner checks the name + number against the professional order's public
    // registry and approves it. There's no public API for those registries, so
    // this is a manual review step, not an automated lookup.
    if (!licenceNumber || !licenceNumber.trim()) return res.status(400).json({ error: 'A professional licence/order number is required.' });

    if (await getClinicianByEmail(email.trim())) {
      return res.status(409).json({ error: 'An account with this email already exists.' });
    }

    const clinician = await createClinician({
      name: name.trim(),
      email: email.trim(),
      passwordHash: await hashPassword(password),
      licenceNumber: licenceNumber.trim(),
      licenceOrder: typeof licenceOrder === 'string' ? licenceOrder.trim() : null,
      province: typeof province === 'string' ? province.trim() : null,
      practiceName: typeof practiceName === 'string' ? practiceName.trim() : null,
      plan
    });
    await startSession(res, req, clinician.id);

    // No Stripe checkout yet: an unverified account shouldn't put a card on file
    // or start a trial clock, so billing waits until the licence is approved
    // (the owner's free-access account skips verification and never pays).
    const owner = isFreeAccess(clinician.email);
    res.status(201).json({
      clinician,
      verificationRequired: !owner && !clinician.licence_verified,
      billingEnabled: stripeConfigured(),
      freeAccess: owner
    });
  } catch (err) {
    if (err && err.code === '23505') { // unique_violation — signup raced the pre-check
      return res.status(409).json({ error: 'An account with this email already exists.' });
    }
    console.error('Error in signup:', err);
    res.status(500).json({ error: 'Could not create account.' });
  }
});

app.post('/api/auth/login', requireDb, loginIpLimiter, loginEmailLimiter, async (req, res) => {
  try {
    const { email, password } = req.body || {};
    if (!email || !password) return res.status(400).json({ error: 'Email and password are required.' });

    const clinician = await getClinicianByEmail(email.trim());
    // Verify against a throwaway hash when the account doesn't exist, so the
    // response time doesn't reveal which emails are registered.
    const ok = await verifyPassword(password, clinician
      ? clinician.password_hash
      : 'scrypt$16384$8$1$00000000000000000000000000000000$00');
    if (!clinician || !ok) {
      return res.status(401).json({ error: 'Incorrect email or password.' });
    }

    // With MFA on, a correct password only earns a short-lived challenge —
    // the session starts after the authenticator code checks out.
    if (clinician.mfa_enabled) {
      const mfaToken = generateSessionToken();
      await createMfaChallenge(hashSessionToken(mfaToken), clinician.id, 5);
      return res.json({ mfaRequired: true, mfaToken });
    }

    await startSession(res, req, clinician.id);
    const { password_hash, mfa_secret, ...publicClinician } = clinician;
    res.json({ clinician: publicClinician, billingEnabled: stripeConfigured(), freeAccess: isFreeAccess(publicClinician.email) });
  } catch (err) {
    console.error('Error in login:', err);
    res.status(500).json({ error: 'Could not sign in.' });
  }
});

const mfaCodeLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, max: 20,
  message: 'Too many code attempts — wait 15 minutes and try again.'
});

app.post('/api/auth/login/mfa', requireDb, mfaCodeLimiter, async (req, res) => {
  try {
    const { mfaToken, code } = req.body || {};
    if (!mfaToken || !code) return res.status(400).json({ error: 'Missing code.' });
    const challenge = await getValidMfaChallenge(hashSessionToken(mfaToken));
    if (!challenge) return res.status(401).json({ error: 'This login attempt expired — start again.' });
    const mfa = await getClinicianMfa(challenge.clinician_id);
    if (!mfa || !mfa.mfa_secret || !verifyTotp(mfa.mfa_secret, code)) {
      return res.status(401).json({ error: 'That code isn\'t right. Check your authenticator app.' });
    }
    await deleteMfaChallenge(challenge.token_hash);
    await startSession(res, req, challenge.clinician_id);
    const clinician = await getClinicianById(challenge.clinician_id);
    res.json({ clinician, billingEnabled: stripeConfigured(), freeAccess: isFreeAccess(clinician.email) });
  } catch (err) {
    console.error('Error in MFA login:', err);
    res.status(500).json({ error: 'Could not sign in.' });
  }
});

// MFA enrolment: generate a secret (shown once, entered into any
// authenticator app), then verify one code to switch it on. Disabling also
// requires a current code.
app.post('/api/auth/mfa/enroll', requireDb, requireAuth, async (req, res) => {
  try {
    if (req.clinician.mfa_enabled) {
      return res.status(400).json({ error: 'Two-factor is already enabled.' });
    }
    const secret = generateTotpSecret();
    await setMfaSecret(req.clinician.id, secret);
    res.json({ secret, otpauthUrl: otpauthUrl(secret, req.clinician.email) });
  } catch (err) {
    console.error('Error in MFA enroll:', err);
    res.status(500).json({ error: 'Could not start two-factor setup.' });
  }
});

app.post('/api/auth/mfa/verify', requireDb, requireAuth, mfaCodeLimiter, async (req, res) => {
  try {
    const mfa = await getClinicianMfa(req.clinician.id);
    if (!mfa || !mfa.mfa_secret) return res.status(400).json({ error: 'Start two-factor setup first.' });
    if (!verifyTotp(mfa.mfa_secret, (req.body || {}).code)) {
      return res.status(400).json({ error: 'That code isn\'t right. Check your authenticator app.' });
    }
    await setMfaEnabled(req.clinician.id, true);
    res.json({ ok: true, mfa_enabled: true });
  } catch (err) {
    console.error('Error in MFA verify:', err);
    res.status(500).json({ error: 'Could not enable two-factor.' });
  }
});

app.post('/api/auth/mfa/disable', requireDb, requireAuth, mfaCodeLimiter, async (req, res) => {
  try {
    const mfa = await getClinicianMfa(req.clinician.id);
    if (!mfa || !mfa.mfa_enabled) return res.status(400).json({ error: 'Two-factor is not enabled.' });
    if (!verifyTotp(mfa.mfa_secret, (req.body || {}).code)) {
      return res.status(400).json({ error: 'That code isn\'t right. Check your authenticator app.' });
    }
    await setMfaEnabled(req.clinician.id, false);
    res.json({ ok: true, mfa_enabled: false });
  } catch (err) {
    console.error('Error in MFA disable:', err);
    res.status(500).json({ error: 'Could not disable two-factor.' });
  }
});

app.post('/api/auth/logout', requireDb, async (req, res) => {
  try {
    const token = readSessionCookie(req);
    if (token) await deleteSession(hashSessionToken(token));
    res.setHeader('Set-Cookie', sessionCookieHeader('', req, { clear: true }));
    res.json({ ok: true });
  } catch (err) {
    console.error('Error in logout:', err);
    res.status(500).json({ error: 'Could not sign out.' });
  }
});

app.get('/api/auth/me', requireDb, requireAuth, (req, res) => {
  res.json({ clinician: req.clinician, billingEnabled: stripeConfigured(), freeAccess: isFreeAccess(req.clinician.email) });
});

// --- Owner: clinician licence review ---
// Manual verification: the owner sees each clinician's submitted name, order,
// and licence number and confirms it against the professional order's public
// registry before approving. Only then can the clinician reach patient data.
app.get('/api/admin/clinicians', requireDb, requireAuth, requireOwner, async (req, res) => {
  try {
    res.json(await listCliniciansForReview());
  } catch (err) {
    console.error('Error listing clinicians for review:', err);
    res.status(500).json({ error: 'Could not load clinicians.' });
  }
});

app.post('/api/admin/clinicians/:id/verify', requireDb, requireAuth, requireOwner, async (req, res) => {
  try {
    const verified = !(req.body && req.body.verified === false); // default true
    const updated = await setClinicianLicenceVerified(req.params.id, verified);
    if (!updated) return res.status(404).json({ error: 'Clinician not found.' });
    res.json({ clinician: updated });
  } catch (err) {
    console.error('Error updating clinician verification:', err);
    res.status(500).json({ error: 'Could not update verification.' });
  }
});

// Start (or restart) clinician checkout — used after a cancel, or to add a card
// during/after the trial.
app.post('/api/auth/checkout/start', requireDb, requireAuth, async (req, res) => {
  try {
    if (!stripeConfigured()) return res.status(400).json({ error: 'Billing is not enabled on this server.' });
    const plan = THERAPIST_PLANS.includes((req.body || {}).plan) ? req.body.plan : (req.clinician.plan || 'solo_monthly');
    const url = await startClinicianCheckout(req.clinician, plan, siteOrigin(req));
    if (!url) return res.status(400).json({ error: 'That plan is not available for checkout.' });
    if (plan !== req.clinician.plan) await updateClinicianSubscription(req.clinician.id, { plan });
    res.json({ checkoutUrl: url });
  } catch (err) {
    console.error('Error starting clinician checkout:', err);
    res.status(500).json({ error: 'Could not start checkout.' });
  }
});

// Confirm the clinician's checkout when Stripe redirects back.
app.post('/api/auth/checkout/verify', requireDb, requireAuth, async (req, res) => {
  try {
    if (!stripeConfigured()) return res.json({ clinician: req.clinician });
    const { sessionId } = req.body || {};
    if (!sessionId) return res.status(400).json({ error: 'Missing session id.' });
    const session = await retrieveCheckoutSession(sessionId);
    const belongs = session && (
      (session.metadata && session.metadata.clinician_id === req.clinician.id) ||
      session.client_reference_id === req.clinician.id
    );
    if (!belongs) return res.status(403).json({ error: 'That checkout does not belong to your account.' });
    // A trial checkout is "complete" with no payment due — that still means the
    // subscription is live (trialing). Treat complete OR paid as active.
    const live = session.status === 'complete' || session.payment_status === 'paid' || session.payment_status === 'no_payment_required';
    const updated = await updateClinicianSubscription(req.clinician.id, {
      status: live ? 'active' : 'incomplete',
      customerId: session.customer,
      subscriptionId: session.subscription
    });
    res.json({ clinician: updated || req.clinician, active: live });
  } catch (err) {
    console.error('Error verifying clinician checkout:', err);
    res.status(500).json({ error: 'Could not verify your subscription.' });
  }
});

app.post('/api/auth/subscription/cancel', requireDb, requireAuth, async (req, res) => {
  try {
    if (!stripeConfigured()) return res.status(400).json({ error: 'Billing is not enabled on this server.' });
    const reactivate = !!(req.body && req.body.reactivate);
    const s = await getClinicianStripe(req.clinician.id);
    if (!s || !s.stripe_subscription_id) return res.status(400).json({ error: 'No subscription on file.' });
    await setSubscriptionCancelAtPeriodEnd(s.stripe_subscription_id, !reactivate);
    const updated = await updateClinicianSubscription(req.clinician.id, { status: reactivate ? 'active' : 'canceling' });
    res.json({ clinician: updated || req.clinician });
  } catch (err) {
    console.error('Error changing clinician subscription:', err);
    res.status(500).json({ error: 'Could not update your subscription.' });
  }
});

// --- Clinician password reset ---
// Token flow: request → emailed link (or server console in dev, when no email
// provider is configured) → confirm with new password. Responses never reveal
// whether an email has an account.

const RESET_TTL_MINUTES = 60;
const resetRequestLimiter = rateLimit({
  windowMs: 60 * 60 * 1000, max: 5,
  keyFn: req => req.ip + '|r|' + String((req.body && req.body.email) || '').trim().toLowerCase(),
  message: 'Too many reset requests — wait an hour and try again.'
});

app.post('/api/auth/password/reset-request', requireDb, resetRequestLimiter, async (req, res) => {
  try {
    const { email } = req.body || {};
    if (!email || !EMAIL_RE.test(email.trim())) {
      return res.status(400).json({ error: 'A valid email is required.' });
    }
    const clinician = await getClinicianByEmail(email.trim());
    if (clinician) {
      const token = generateSessionToken();
      await createPasswordReset(hashSessionToken(token), clinician.id, RESET_TTL_MINUTES);
      const origin = `${req.secure || req.headers['x-forwarded-proto'] === 'https' ? 'https' : 'http'}://${req.headers.host}`;
      await sendEmail({
        to: clinician.email,
        subject: 'Reset your Between password',
        text: `Someone (hopefully you) asked to reset the password for this Between account.\n\n` +
          `Open this link within ${RESET_TTL_MINUTES} minutes to choose a new password:\n` +
          `${origin}/?reset=${token}\n\nIf this wasn't you, you can ignore this email.`
      });
    }
    // Same response either way — no account enumeration.
    res.json({ ok: true, emailConfigured: emailConfigured() });
  } catch (err) {
    console.error('Error in reset-request:', err);
    res.status(500).json({ error: 'Could not process the request.' });
  }
});

app.post('/api/auth/password/reset-confirm', requireDb, async (req, res) => {
  try {
    const { token, newPassword } = req.body || {};
    if (!token) return res.status(400).json({ error: 'Missing reset token.' });
    if (!newPassword || newPassword.length < 10) {
      return res.status(400).json({ error: 'Password must be at least 10 characters.' });
    }
    const reset = await getValidPasswordReset(hashSessionToken(token));
    if (!reset) {
      return res.status(400).json({ error: 'This reset link is invalid or has expired. Request a new one.' });
    }
    await consumePasswordReset(reset.token_hash, reset.clinician_id, await hashPassword(newPassword));
    res.json({ ok: true });
  } catch (err) {
    console.error('Error in reset-confirm:', err);
    res.status(500).json({ error: 'Could not reset the password.' });
  }
});

// --- Patients ---
// All patient routes require a signed-in clinician, and every lookup is scoped
// to that clinician server-side — client-supplied patient IDs are never
// trusted (backend-spec.md §2).

app.post('/api/patients', requireDb, requireAuth, requireVerifiedClinician, requireClinicianSubscription, async (req, res) => {
  try {
    const { displayName } = req.body || {};
    if (!displayName || !displayName.trim()) {
      return res.status(400).json({ error: 'displayName is required.' });
    }
    const patient = await createPatient(req.clinician.id, displayName.trim(), generateInviteCode());
    res.status(201).json(patient);
  } catch (err) {
    console.error('Error creating patient:', err);
    res.status(500).json({ error: 'Could not create patient.' });
  }
});

app.get('/api/patients', requireDb, requireAuth, requireVerifiedClinician, async (req, res) => {
  try {
    res.json(await listPatients(req.clinician.id));
  } catch (err) {
    console.error('Error listing patients:', err);
    res.status(500).json({ error: 'Could not list patients.' });
  }
});

app.post('/api/patients/:id/consent', requireDb, requireAuth, requireVerifiedClinician, async (req, res) => {
  try {
    const { enabled } = req.body || {};
    const patient = await setPatientConsent(req.clinician.id, req.params.id, !!enabled, 'v1-clinician-recorded');
    if (!patient) return res.status(404).json({ error: 'Patient not found.' });
    res.json(patient);
  } catch (err) {
    console.error('Error updating consent:', err);
    res.status(500).json({ error: 'Could not update consent.' });
  }
});

// Reset a patient's app access: issues a fresh one-time invite code, clears
// their password, and signs them out everywhere. This is the patient
// "password reset" — mediated by the therapist, so no patient email
// infrastructure is needed. History and consent are untouched.
app.post('/api/patients/:id/reset-access', requireDb, requireAuth, requireVerifiedClinician, async (req, res) => {
  try {
    const patient = await resetPatientAccess(req.clinician.id, req.params.id, generateInviteCode());
    if (!patient) return res.status(404).json({ error: 'Patient not found.' });
    res.json(patient);
  } catch (err) {
    console.error('Error resetting patient access:', err);
    res.status(500).json({ error: 'Could not reset access.' });
  }
});

// Permanently delete a patient and all of their data (check-ins, summaries,
// voice memos, alerts). Scoped to the signed-in clinician; irreversible.
app.delete('/api/patients/:id', requireDb, requireAuth, requireVerifiedClinician, async (req, res) => {
  try {
    const deleted = await deletePatient(req.clinician.id, req.params.id);
    if (!deleted) return res.status(404).json({ error: 'Patient not found.' });
    res.json({ ok: true });
  } catch (err) {
    console.error('Error deleting patient:', err);
    res.status(500).json({ error: 'Could not delete the patient.' });
  }
});

// --- Alerts (risk-flag feed for the signed-in clinician) ---

app.get('/api/alerts', requireDb, requireAuth, requireVerifiedClinician, async (req, res) => {
  try {
    res.json(await listAlerts(req.clinician.id));
  } catch (err) {
    console.error('Error listing alerts:', err);
    res.status(500).json({ error: 'Could not load alerts.' });
  }
});

app.post('/api/alerts/:id/mark-viewed', requireDb, requireAuth, requireVerifiedClinician, async (req, res) => {
  try {
    const alert = await markAlertViewed(req.params.id, req.clinician.id);
    if (!alert) return res.status(404).json({ error: 'Alert not found.' });
    res.json(alert);
  } catch (err) {
    console.error('Error marking alert viewed:', err);
    res.status(500).json({ error: 'Could not update the alert.' });
  }
});

// --- Check-ins ---

// Shared by the clinician route below and the patient-facing route further
// down: applies the consent rule, calls the AI only when opted in, and never
// loses a check-in to an AI failure.
// When a check-in raises a risk flag, record an alert for the treating
// clinician and try to deliver it by email. Delivery is best-effort and
// independent of the patient's crisis resources, which are returned in the
// check-in response itself.
async function raiseRiskAlert(patient, checkIn) {
  try {
    let deliveredAt = null;
    let channel = null;
    const clinician = patient.clinician_id ? await getClinicianById(patient.clinician_id) : null;
    if (clinician) {
      channel = 'email';
      const { delivered } = await sendEmail({
        to: clinician.email,
        subject: `Between: check-in flagged for ${patient.display_name}`,
        text: `A check-in from ${patient.display_name} was flagged for possible safety concern.\n\n` +
          `Open your Between dashboard to review it. The patient has already been shown crisis resources in the app.\n\n` +
          `(No response is required through Between — it is a documentation tool, not a monitoring service.)`
      });
      if (delivered) deliveredAt = new Date();
      await createAlert({ checkInId: checkIn.id, clinicianId: clinician.id, deliveryChannel: channel, deliveredAt });
    }
  } catch (err) {
    console.error('Failed to record/deliver risk alert:', err);
  }
}

async function buildAndStoreCheckIn(patient, { text, moodScore, manualTags, audioUploadId }) {
  let summaryText = null, autoTags = [], riskFlag = false, modelVersion = null;

  // Whether the patient left the mood unset (they can skip the slider). Only
  // then may the AI fill one in, and we record that it was estimated so it's
  // never shown as if the patient rated it themselves.
  const moodProvided = moodScore != null;
  let finalMood = moodProvided ? moodScore : null;
  let moodInferred = false;

  // Only call the AI if this patient has actually opted in — mirrors the
  // privacy-by-default rule from the consent flow, enforced server-side too.
  if (patient.ai_consent_enabled && text && text.trim()) {
    try {
      const result = await summarizeCheckIn(text.trim());
      summaryText = result.summary;
      autoTags = result.auto_tags;
      riskFlag = result.risk_flag;
      modelVersion = MODEL_VERSION;
      if (!moodProvided && result.mood_estimate != null) {
        finalMood = result.mood_estimate;
        moodInferred = true;
      }
    } catch (aiErr) {
      // Don't lose the check-in because the AI call failed — store it raw.
      console.error('AI summarization failed, storing check-in without summary:', aiErr);
      summaryText = text.trim().slice(0, 1000);
    }
  } else if (text && text.trim()) {
    summaryText = text.trim().slice(0, 1000); // no AI: store as-typed, no profiling
  }

  const checkIn = await createCheckIn({
    patientId: patient.id, moodScore: finalMood, moodInferred, manualTags, rawText: text || null,
    summaryText, autoTags, riskFlag, modelVersion, audioUploadId
  });
  if (checkIn.risk_flag) await raiseRiskAlert(patient, checkIn);
  return checkIn;
}

app.post('/api/patients/:id/check-ins', requireDb, requireAuth, requireVerifiedClinician, requireClinicianSubscription, checkInLimiter, async (req, res) => {
  try {
    const { moodScore, manualTags, text } = req.body || {};

    const patient = await getPatient(req.clinician.id, req.params.id);
    if (!patient) return res.status(404).json({ error: 'Patient not found.' });

    const checkIn = await buildAndStoreCheckIn(patient, { text, moodScore, manualTags });
    res.status(201).json(checkIn);
  } catch (err) {
    console.error('Error creating check-in:', err);
    res.status(500).json({ error: 'Could not create check-in.' });
  }
});

app.get('/api/patients/:id/check-ins', requireDb, requireAuth, requireVerifiedClinician, async (req, res) => {
  try {
    const patient = await getPatient(req.clinician.id, req.params.id);
    if (!patient) return res.status(404).json({ error: 'Patient not found.' });
    const checkIns = await listCheckIns(patient.id);
    // Opening a patient counts as reviewing them — clears their "new" badge.
    markPatientReviewed(req.clinician.id, patient.id).catch(() => {});
    res.json(checkIns);
  } catch (err) {
    console.error('Error listing check-ins:', err);
    res.status(500).json({ error: 'Could not list check-ins.' });
  }
});

// Stream a check-in's voice memo to its treating clinician.
app.get('/api/patients/:id/check-ins/:checkInId/audio', requireDb, requireAuth, requireVerifiedClinician, async (req, res) => {
  try {
    const patient = await getPatient(req.clinician.id, req.params.id);
    if (!patient) return res.status(404).json({ error: 'Patient not found.' });
    const checkIn = await getCheckIn(req.params.checkInId, patient.id);
    if (!checkIn || !checkIn.audio_upload_id) return res.status(404).json({ error: 'No audio for this check-in.' });
    const audio = await getAudioForClinician(checkIn.audio_upload_id, req.clinician.id);
    if (!audio) return res.status(404).json({ error: 'No audio for this check-in.' });
    res.setHeader('Content-Type', audio.mime);
    res.setHeader('Cache-Control', 'private, no-store');
    res.send(audio.data);
  } catch (err) {
    console.error('Error streaming audio:', err);
    res.status(500).json({ error: 'Could not load the audio.' });
  }
});

app.delete('/api/patients/:id/check-ins/:checkInId', requireDb, requireAuth, requireVerifiedClinician, async (req, res) => {
  try {
    const patient = await getPatient(req.clinician.id, req.params.id);
    if (!patient) return res.status(404).json({ error: 'Patient not found.' });
    const deleted = await softDeleteCheckIn(req.params.checkInId, patient.id);
    if (!deleted) return res.status(404).json({ error: 'Check-in not found.' });
    res.json({ ok: true });
  } catch (err) {
    console.error('Error deleting check-in:', err);
    res.status(500).json({ error: 'Could not delete check-in.' });
  }
});

app.delete('/api/patients/:id/check-ins', requireDb, requireAuth, requireVerifiedClinician, async (req, res) => {
  try {
    const patient = await getPatient(req.clinician.id, req.params.id);
    if (!patient) return res.status(404).json({ error: 'Patient not found.' });
    await deleteAllCheckIns(patient.id);
    res.json({ ok: true });
  } catch (err) {
    console.error('Error deleting check-ins:', err);
    res.status(500).json({ error: 'Could not delete check-ins.' });
  }
});

// --- Patient-facing API (mobile app scope) ---
// Authenticated with "Authorization: Bearer <token>" (native apps keep the
// token in secure storage; there is no cookie in this scope). Every route
// operates only on the signed-in patient's own row — this scope has no
// caseload concept and no route that can return another patient's data.

const CONSENT_VERSION = 'v1';
const CHECK_IN_GRACE_MINUTES = 15;
const CRISIS_RESOURCES = {
  message: "This sounds like a lot to carry right now. Between isn't a crisis service — if you're in immediate danger or thinking about suicide, please reach out now.",
  lines: [
    { name: '988 Suicide Crisis Helpline (call or text, Canada)', number: '988' },
    { name: 'Emergency services', number: '911' }
  ]
};

// CORS for the patient scope only: Bearer auth doesn't rely on cookies, so a
// wildcard origin is safe here, and the Flutter web build / local dev can call
// the API cross-origin. The cookie-authenticated clinician routes stay
// same-origin only.
app.use('/api/patient', (req, res, next) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  if (req.method === 'OPTIONS') return res.sendStatus(204);
  next();
});

async function requirePatientAuth(req, res, next) {
  try {
    const token = readBearerToken(req);
    if (token) {
      const patient = await getPatientBySession(hashSessionToken(token));
      if (patient) {
        req.patient = patient;
        return next();
      }
    }
    res.status(401).json({ error: 'Not signed in.' });
  } catch (err) {
    console.error('Patient auth check failed:', err);
    res.status(500).json({ error: 'Could not verify session.' });
  }
}

async function startPatientSession(patientId) {
  const token = generateSessionToken();
  await createPatientSession(hashSessionToken(token), patientId, SESSION_TTL_DAYS);
  return token;
}

function publicPatient(p) {
  return {
    id: p.id,
    display_name: p.display_name,
    email: p.email,
    ai_consent_enabled: p.ai_consent_enabled,
    consent_recorded_at: p.consent_recorded_at,
    consent_version: p.consent_version,
    plan: p.plan,
    subscription_status: p.subscription_status
  };
}

// Build the Checkout URL for a plan, or null if Stripe/plan isn't set up.
async function startPatientCheckout(patient, plan, origin) {
  const priceId = priceForPlan(plan);
  if (!stripeConfigured() || !priceId) return null;
  const session = await createSubscriptionCheckout({
    priceId,
    customerEmail: patient.email,
    refType: 'patient',
    refId: patient.id,
    successUrl: `${origin}/?checkout=success&session_id={CHECKOUT_SESSION_ID}`,
    cancelUrl: `${origin}/?checkout=cancel`
  });
  return session.url || null;
}

// Clinician checkout — same idea, but with a 14-day free trial so no card is
// charged today (honoring the "14-day free trial" on the pricing page).
const CLINICIAN_TRIAL_DAYS = 14;
async function startClinicianCheckout(clinician, plan, origin) {
  const priceId = priceForPlan(plan);
  if (!stripeConfigured() || !priceId) return null;
  const session = await createSubscriptionCheckout({
    priceId,
    customerEmail: clinician.email,
    refType: 'clinician',
    refId: clinician.id,
    trialDays: CLINICIAN_TRIAL_DAYS,
    successUrl: `${origin}/?checkout=success&session_id={CHECKOUT_SESSION_ID}`,
    cancelUrl: `${origin}/?checkout=cancel`
  });
  return session.url || null;
}

function siteOrigin(req) {
  return process.env.PUBLIC_BASE_URL || `${req.protocol}://${req.get('host')}`;
}

// --- Subscription gating ---
// A paid subscription is required to use the app once Stripe is configured.
// 'canceling' still grants access (they keep the period they paid for) until
// the webhook flips it to 'canceled'. Invited patients (no self-serve plan)
// are covered by their therapist's seat and are never gated.
function subActive(status) {
  return status === 'active' || status === 'trialing' || status === 'canceling';
}
// Owner/comp accounts that always get in free (e.g. the site owner using their
// own site). Set FREE_ACCESS_EMAILS to a comma-separated list; defaults to the
// owner's address.
const FREE_ACCESS_EMAILS = (process.env.FREE_ACCESS_EMAILS || 'jojo11haz@gmail.com')
  .split(',').map(e => e.trim().toLowerCase()).filter(Boolean);
function isFreeAccess(email) {
  return !!email && FREE_ACCESS_EMAILS.includes(String(email).toLowerCase());
}
function patientNeedsSub(p) {
  return stripeConfigured() && !isFreeAccess(p.email) && !!p.plan && !subActive(p.subscription_status);
}
function clinicianNeedsSub(c) {
  return stripeConfigured() && !isFreeAccess(c.email) && !subActive(c.subscription_status);
}
function requirePatientSubscription(req, res, next) {
  if (patientNeedsSub(req.patient)) {
    return res.status(402).json({ error: 'A subscription is needed to continue — subscribe from your settings.', code: 'subscription_required' });
  }
  next();
}
function requireClinicianSubscription(req, res, next) {
  if (clinicianNeedsSub(req.clinician)) {
    return res.status(402).json({ error: 'An active subscription is needed to continue — open Billing to subscribe.', code: 'subscription_required' });
  }
  next();
}
// A clinician account can only reach patient data once its professional licence
// has been confirmed by the owner. The owner's own (free-access) account is
// treated as verified so they can always use and administer the site.
function clinicianVerified(c) {
  return !!c && (isFreeAccess(c.email) || !!c.licence_verified);
}
function requireVerifiedClinician(req, res, next) {
  if (!clinicianVerified(req.clinician)) {
    return res.status(403).json({
      error: 'Your account is pending licence verification. You will get access once your professional licence is confirmed.',
      code: 'verification_required'
    });
  }
  next();
}
// Owner-only routes (licence review). Gated to the free-access/comp list so a
// regular clinician can never reach another clinician's account.
function requireOwner(req, res, next) {
  if (!req.clinician || !isFreeAccess(req.clinician.email)) {
    return res.status(403).json({ error: 'Owner access required.' });
  }
  next();
}

const inviteLimiter = rateLimit({
  windowMs: 60 * 60 * 1000, max: 10,
  message: 'Too many attempts — wait an hour and try again.'
});
const patientLoginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, max: 10,
  keyFn: req => req.ip + '|p|' + String((req.body && req.body.email) || '').trim().toLowerCase(),
  message: 'Too many login attempts for this account — wait 15 minutes and try again.'
});
const patientCheckInLimiter = rateLimit({
  windowMs: 60 * 1000, max: 15,
  keyFn: req => (req.patient && req.patient.id) || req.ip,
  message: 'Too many check-ins at once — wait a minute and try again.'
});

// Accept the therapist's invite: turns an invite code into login credentials
// on the patient's own row. One-time — the code stops working once accepted.
app.post('/api/patient/accept-invite', requireDb, inviteLimiter, async (req, res) => {
  try {
    const { inviteCode, email, password } = req.body || {};
    if (!inviteCode || !inviteCode.trim()) return res.status(400).json({ error: 'An invite code is required.' });
    if (!email || !EMAIL_RE.test(email.trim())) return res.status(400).json({ error: 'A valid email is required.' });
    if (!password || password.length < 10) return res.status(400).json({ error: 'Password must be at least 10 characters.' });

    const code = inviteCode.trim().toUpperCase();
    const found = await getPatientByInviteCode(code);
    if (!found || found.invite_status !== 'pending') {
      return res.status(404).json({ error: 'That invite code is not valid. Check it with your therapist.' });
    }
    // Conflict check excludes the invited patient's own row, so re-onboarding
    // with the same email after a therapist access-reset works.
    const existing = await getPatientByEmail(email.trim());
    if (existing && existing.id !== found.id) {
      return res.status(409).json({ error: 'An account with this email already exists. Try logging in instead.' });
    }

    const patient = await acceptPatientInvite(found.id, email.trim(), await hashPassword(password));
    if (!patient) return res.status(404).json({ error: 'That invite code is not valid. Check it with your therapist.' });

    const token = await startPatientSession(patient.id);
    res.status(201).json({ token, patient: publicPatient(patient), billingEnabled: stripeConfigured(), freeAccess: isFreeAccess(patient.email) });
  } catch (err) {
    if (err && err.code === '23505') {
      return res.status(409).json({ error: 'An account with this email already exists. Try logging in instead.' });
    }
    console.error('Error accepting invite:', err);
    res.status(500).json({ error: 'Could not set up your account.' });
  }
});

// Self-serve patient signup: a patient buys Between for themselves, with no
// therapist. Creates a standalone account (clinician_id NULL) and signs them
// in. AI profiling stays off until they explicitly opt in, exactly as with an
// invited patient — but they still record a consent decision at onboarding.
const PATIENT_PLANS = ['patient_monthly', 'patient_annual'];

app.post('/api/patient/signup', requireDb, inviteLimiter, async (req, res) => {
  try {
    const { name, email, password } = req.body || {};
    const plan = PATIENT_PLANS.includes((req.body || {}).plan) ? req.body.plan : 'patient_monthly';
    if (!name || !name.trim()) return res.status(400).json({ error: 'A name is required.' });
    if (!email || !EMAIL_RE.test(email.trim())) return res.status(400).json({ error: 'A valid email is required.' });
    if (!password || password.length < 10) return res.status(400).json({ error: 'Password must be at least 10 characters.' });

    const existing = await getPatientByEmail(email.trim());
    if (existing) {
      return res.status(409).json({ error: 'An account with this email already exists. Try logging in instead.' });
    }

    const patient = await createSelfServePatient(name.trim(), email.trim(), await hashPassword(password), plan);
    const token = await startPatientSession(patient.id);

    // Hand back a Stripe Checkout URL so the client can send them to pay. If
    // Stripe isn't configured, checkoutUrl is null and the account is simply
    // created for free (dev/no-Stripe mode).
    let checkoutUrl = null;
    try { checkoutUrl = await startPatientCheckout(patient, plan, siteOrigin(req)); }
    catch (e) { console.error('Could not start checkout:', e.message); }

    res.status(201).json({ token, patient: publicPatient(patient), checkoutUrl, billingEnabled: stripeConfigured(), freeAccess: isFreeAccess(patient.email) });
  } catch (err) {
    if (err && err.code === '23505') {
      return res.status(409).json({ error: 'An account with this email already exists. Try logging in instead.' });
    }
    console.error('Error in patient signup:', err);
    res.status(500).json({ error: 'Could not set up your account.' });
  }
});

// Start (or restart) checkout for an already-signed-in patient — used when they
// cancelled, or signed up before billing was switched on.
app.post('/api/patient/checkout/start', requireDb, requirePatientAuth, async (req, res) => {
  try {
    if (!stripeConfigured()) return res.status(400).json({ error: 'Billing is not enabled on this server.' });
    const plan = PATIENT_PLANS.includes((req.body || {}).plan) ? req.body.plan : (req.patient.plan || 'patient_monthly');
    const url = await startPatientCheckout(req.patient, plan, siteOrigin(req));
    if (!url) return res.status(400).json({ error: 'That plan is not available for checkout.' });
    if (plan !== req.patient.plan) await updatePatientSubscription(req.patient.id, { plan });
    res.json({ checkoutUrl: url });
  } catch (err) {
    console.error('Error starting checkout:', err);
    res.status(500).json({ error: 'Could not start checkout.' });
  }
});

// Confirm payment when Stripe redirects back. We query Stripe directly with our
// secret key, so this is trustworthy on its own (webhooks are a nice-to-have).
app.post('/api/patient/checkout/verify', requireDb, requirePatientAuth, async (req, res) => {
  try {
    if (!stripeConfigured()) return res.json({ patient: publicPatient(req.patient) });
    const { sessionId } = req.body || {};
    if (!sessionId) return res.status(400).json({ error: 'Missing session id.' });
    const session = await retrieveCheckoutSession(sessionId);
    const belongs = session && (
      (session.metadata && session.metadata.patient_id === req.patient.id) ||
      session.client_reference_id === req.patient.id
    );
    if (!belongs) return res.status(403).json({ error: 'That checkout does not belong to your account.' });
    const paid = session.payment_status === 'paid' || session.status === 'complete';
    const updated = await updatePatientSubscription(req.patient.id, {
      status: paid ? 'active' : 'incomplete',
      customerId: session.customer,
      subscriptionId: session.subscription
    });
    res.json({ patient: publicPatient(updated || req.patient), paid });
  } catch (err) {
    console.error('Error verifying checkout:', err);
    res.status(500).json({ error: 'Could not verify your payment.' });
  }
});

// Cancel at period end (keep access through the paid period) or undo a
// pending cancel. Body { reactivate: true } flips it back on.
app.post('/api/patient/subscription/cancel', requireDb, requirePatientAuth, async (req, res) => {
  try {
    if (!stripeConfigured()) return res.status(400).json({ error: 'Billing is not enabled on this server.' });
    const reactivate = !!(req.body && req.body.reactivate);
    const s = await getPatientStripe(req.patient.id);
    if (!s || !s.stripe_subscription_id) return res.status(400).json({ error: 'No subscription on file.' });
    await setSubscriptionCancelAtPeriodEnd(s.stripe_subscription_id, !reactivate);
    const updated = await updatePatientSubscription(req.patient.id, { status: reactivate ? 'active' : 'canceling' });
    res.json({ patient: publicPatient(updated || req.patient) });
  } catch (err) {
    console.error('Error changing patient subscription:', err);
    res.status(500).json({ error: 'Could not update your subscription.' });
  }
});

app.post('/api/patient/login', requireDb, patientLoginLimiter, async (req, res) => {
  try {
    const { email, password } = req.body || {};
    if (!email || !password) return res.status(400).json({ error: 'Email and password are required.' });

    const patient = await getPatientByEmail(email.trim());
    const ok = await verifyPassword(password, patient && patient.password_hash
      ? patient.password_hash
      : 'scrypt$16384$8$1$00000000000000000000000000000000$00');
    if (!patient || !ok || patient.invite_status === 'revoked') {
      return res.status(401).json({ error: 'Incorrect email or password.' });
    }

    const token = await startPatientSession(patient.id);
    res.json({ token, patient: publicPatient(patient), billingEnabled: stripeConfigured(), freeAccess: isFreeAccess(patient.email) });
  } catch (err) {
    console.error('Error in patient login:', err);
    res.status(500).json({ error: 'Could not sign in.' });
  }
});

app.post('/api/patient/logout', requireDb, async (req, res) => {
  try {
    const token = readBearerToken(req);
    if (token) await deletePatientSession(hashSessionToken(token));
    res.json({ ok: true });
  } catch (err) {
    console.error('Error in patient logout:', err);
    res.status(500).json({ error: 'Could not sign out.' });
  }
});

app.get('/api/patient/me', requireDb, requirePatientAuth, (req, res) => {
  res.json({ patient: publicPatient(req.patient), billingEnabled: stripeConfigured(), freeAccess: isFreeAccess(req.patient.email) });
});

app.get('/api/patient/consent', requireDb, requirePatientAuth, (req, res) => {
  res.json({
    ai_consent_enabled: req.patient.ai_consent_enabled,
    consent_recorded_at: req.patient.consent_recorded_at,
    consent_version: req.patient.consent_version,
    current_consent_version: CONSENT_VERSION
  });
});

// Records the patient's own consent decision (Law 25: consent version +
// timestamp). Called from onboarding and from settings when they change the
// AI toggle. enabled:false is a valid, recordable choice — consent to use the
// app without profiling.
app.post('/api/patient/consent', requireDb, requirePatientAuth, async (req, res) => {
  try {
    const { enabled } = req.body || {};
    const patient = await setOwnConsent(req.patient.id, !!enabled, CONSENT_VERSION);
    res.json({ patient: publicPatient(patient) });
  } catch (err) {
    console.error('Error recording patient consent:', err);
    res.status(500).json({ error: 'Could not record your choice.' });
  }
});

// Voice memos, step 1: ask for a short-lived signed upload URL. Raw audio
// never rides through the JSON API (backend-spec.md) — it goes to the URL
// below. Stored in Postgres for the MVP; move to object storage at scale.
const AUDIO_TOKEN_TTL_MINUTES = 10;
const AUDIO_MAX_BYTES = 15 * 1024 * 1024;
const AUDIO_MIMES = ['audio/webm', 'audio/mp4', 'audio/mpeg', 'audio/ogg', 'audio/wav', 'audio/aac', 'audio/x-m4a'];

app.post('/api/patient/check-ins/audio-upload-url', requireDb, requirePatientAuth, async (req, res) => {
  try {
    const token = generateSessionToken();
    await createAudioUploadToken(hashSessionToken(token), req.patient.id, AUDIO_TOKEN_TTL_MINUTES);
    res.json({
      uploadUrl: `/api/patient/audio-upload/${token}`,
      method: 'PUT',
      maxBytes: AUDIO_MAX_BYTES,
      expiresInMinutes: AUDIO_TOKEN_TTL_MINUTES
    });
  } catch (err) {
    console.error('Error creating upload URL:', err);
    res.status(500).json({ error: 'Could not prepare the upload.' });
  }
});

// Step 2: PUT the audio bytes to the signed URL. The token is single-use and
// itself authenticates the request (that's what makes the URL "signed").
app.put('/api/patient/audio-upload/:token',
  express.raw({ type: () => true, limit: AUDIO_MAX_BYTES }),
  requireDb,
  async (req, res) => {
    try {
      const grant = await consumeAudioUploadToken(hashSessionToken(req.params.token));
      if (!grant) return res.status(403).json({ error: 'Upload link expired — try recording again.' });
      const mime = (req.headers['content-type'] || '').split(';')[0].trim();
      if (!AUDIO_MIMES.includes(mime)) {
        return res.status(415).json({ error: 'Unsupported audio format.' });
      }
      if (!req.body || !req.body.length) {
        return res.status(400).json({ error: 'No audio received.' });
      }
      const audioUploadId = await storeAudioUpload(grant.patient_id, mime, req.body);
      res.status(201).json({ audioUploadId });
    } catch (err) {
      console.error('Error storing audio upload:', err);
      res.status(500).json({ error: 'Could not save the recording.' });
    }
  });

app.post('/api/patient/check-ins', requireDb, requirePatientAuth, requirePatientSubscription, patientCheckInLimiter, async (req, res) => {
  try {
    if (!req.patient.consent_recorded_at) {
      return res.status(403).json({ error: 'Please complete the consent step before sending check-ins.' });
    }
    const { moodScore, manualTags, text, audioUploadId } = req.body || {};
    if (text && (typeof text !== 'string' || text.length > 4000)) {
      return res.status(400).json({ error: 'Check-in text is too long.' });
    }

    let effectiveText = text;
    if (audioUploadId) {
      const audio = await getAudioUploadOwned(audioUploadId, req.patient.id);
      if (!audio) {
        return res.status(400).json({ error: 'That recording could not be found — try again.' });
      }
      // Transcribe the memo server-side when no text was typed, so voice
      // check-ins flow through the same consent-gated AI summarization and
      // risk screening as typed ones. If transcription is unconfigured or
      // fails, the memo is stored playable-but-untranscribed (and therefore
      // not risk-screened — documented in the README).
      if (!effectiveText || !effectiveText.trim()) {
        const transcript = await transcribeAudio(audio.data, audio.mime);
        if (transcript) effectiveText = transcript.slice(0, 4000);
      }
    }

    const checkIn = await buildAndStoreCheckIn(req.patient, { text: effectiveText, moodScore, manualTags, audioUploadId });

    // Crisis resources are returned directly to the patient, independent of
    // any therapist alert — the safety net must never wait on a human.
    const body = { checkIn };
    if (checkIn.risk_flag) body.crisis = CRISIS_RESOURCES;
    res.status(201).json(body);
  } catch (err) {
    console.error('Error creating patient check-in:', err);
    res.status(500).json({ error: 'Could not send your check-in.' });
  }
});

app.get('/api/patient/check-ins', requireDb, requirePatientAuth, async (req, res) => {
  try {
    res.json(await listCheckIns(req.patient.id));
  } catch (err) {
    console.error('Error listing patient check-ins:', err);
    res.status(500).json({ error: 'Could not load your history.' });
  }
});

// --- Future-self notes ---
// A private note a patient leaves for a harder day; the app surfaces it back to
// them when their mood is low. Patient-scoped only; never visible to a clinician.
app.get('/api/patient/future-notes', requireDb, requirePatientAuth, async (req, res) => {
  try {
    res.json(await listFutureNotes(req.patient.id));
  } catch (err) {
    console.error('Error listing future notes:', err);
    res.status(500).json({ error: 'Could not load your notes.' });
  }
});

app.post('/api/patient/future-notes', requireDb, requirePatientAuth, requirePatientSubscription, async (req, res) => {
  try {
    const body = (req.body && typeof req.body.body === 'string') ? req.body.body.trim() : '';
    if (!body) return res.status(400).json({ error: 'Write a few words first.' });
    if (body.length > 1000) return res.status(400).json({ error: 'That note is a bit long — keep it under 1000 characters.' });
    res.status(201).json(await createFutureNote(req.patient.id, body));
  } catch (err) {
    console.error('Error creating future note:', err);
    res.status(500).json({ error: 'Could not save your note.' });
  }
});

app.delete('/api/patient/future-notes/:id', requireDb, requirePatientAuth, async (req, res) => {
  try {
    const deleted = await deleteFutureNote(req.params.id, req.patient.id);
    if (!deleted) return res.status(404).json({ error: 'Note not found.' });
    res.json({ ok: true });
  } catch (err) {
    console.error('Error deleting future note:', err);
    res.status(500).json({ error: 'Could not delete the note.' });
  }
});

// Grace-period undo: a patient can delete a just-sent check-in within
// CHECK_IN_GRACE_MINUTES, unless it raised a risk flag (the safety record
// stays). Full-history deletion below is the Law 25 erasure path and is not
// time-limited.
app.delete('/api/patient/check-ins/:id', requireDb, requirePatientAuth, async (req, res) => {
  try {
    const checkIn = await getCheckIn(req.params.id, req.patient.id);
    if (!checkIn) return res.status(404).json({ error: 'Check-in not found.' });
    if (checkIn.risk_flag) {
      return res.status(403).json({ error: 'This check-in raised a safety flag and can’t be removed this way. You can still request deletion of your history in settings.' });
    }
    const ageMs = Date.now() - new Date(checkIn.submitted_at).getTime();
    if (ageMs > CHECK_IN_GRACE_MINUTES * 60 * 1000) {
      return res.status(403).json({ error: `The ${CHECK_IN_GRACE_MINUTES}-minute undo window has passed. You can request deletion of your history in settings.` });
    }
    await softDeleteCheckIn(checkIn.id, req.patient.id);
    res.json({ ok: true });
  } catch (err) {
    console.error('Error undoing check-in:', err);
    res.status(500).json({ error: 'Could not remove the check-in.' });
  }
});

app.delete('/api/patient/check-ins', requireDb, requirePatientAuth, async (req, res) => {
  try {
    await deleteAllCheckIns(req.patient.id);
    res.json({ ok: true });
  } catch (err) {
    console.error('Error deleting patient history:', err);
    res.status(500).json({ error: 'Could not delete your history.' });
  }
});

// Stream the patient's own voice memo back to them.
app.get('/api/patient/check-ins/:id/audio', requireDb, requirePatientAuth, async (req, res) => {
  try {
    const checkIn = await getCheckIn(req.params.id, req.patient.id);
    if (!checkIn || !checkIn.audio_upload_id) return res.status(404).json({ error: 'No audio for this check-in.' });
    const audio = await getAudioUploadOwned(checkIn.audio_upload_id, req.patient.id);
    if (!audio) return res.status(404).json({ error: 'No audio for this check-in.' });
    res.setHeader('Content-Type', audio.mime);
    res.setHeader('Cache-Control', 'private, no-store');
    res.send(audio.data);
  } catch (err) {
    console.error('Error streaming patient audio:', err);
    res.status(500).json({ error: 'Could not load the audio.' });
  }
});

// The patient's right to contest an automated output (Law 25).
app.post('/api/patient/check-ins/:id/flag-inaccurate', requireDb, requirePatientAuth, async (req, res) => {
  try {
    const updated = await flagCheckInInaccurate(req.params.id, req.patient.id);
    if (!updated) return res.status(404).json({ error: 'Check-in not found.' });
    res.json({ ok: true });
  } catch (err) {
    console.error('Error flagging summary:', err);
    res.status(500).json({ error: 'Could not flag the summary.' });
  }
});

// --- Contact form ---
// Public "Talk to us" form. Emails the message to the site owner so any
// visitor can reach them without needing their own mail app. Reply-To is set
// to the sender so the owner can just hit reply. Needs RESEND_API_KEY to
// actually deliver; without it the message is logged (see email.js).
const CONTACT_EMAIL = process.env.CONTACT_EMAIL || 'jojo11haz@gmail.com';
const contactLimiter = rateLimit({
  windowMs: 60 * 60 * 1000, max: 8,
  message: 'Too many messages — please wait a little while and try again.'
});
app.post('/api/contact', contactLimiter, async (req, res) => {
  try {
    const { name, email, message } = req.body || {};
    if (!name || !name.trim()) return res.status(400).json({ error: 'Please include your name.' });
    if (!email || !EMAIL_RE.test(email.trim())) return res.status(400).json({ error: 'Please include a valid email so we can reply.' });
    if (!message || !message.trim()) return res.status(400).json({ error: 'Please include a message.' });
    if (message.length > 5000) return res.status(400).json({ error: 'That message is too long.' });

    const { delivered } = await sendEmail({
      to: CONTACT_EMAIL,
      replyTo: email.trim(),
      subject: `Between — message from ${name.trim()}`,
      text: `From: ${name.trim()} <${email.trim()}>\n\n${message.trim()}`
    });
    res.json({ ok: true, delivered });
  } catch (err) {
    console.error('Error handling contact form:', err);
    res.status(500).json({ error: 'Could not send your message — please try again.' });
  }
});

// Simple health check — useful for most hosting platforms' uptime checks
app.get('/health', (req, res) => res.json({ ok: true }));

const PORT = process.env.PORT || 3000;
initDb().then(() => {
  app.listen(PORT, () => console.log(`Between server running on port ${PORT}`));
}).catch(err => {
  console.error('Failed to initialize database:', err);
  app.listen(PORT, () => console.log(`Between server running on port ${PORT} (without DB)`));
});
