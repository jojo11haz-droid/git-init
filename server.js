import express from 'express';
import path from 'path';
import { fileURLToPath } from 'url';
import {
  dbEnabled, initDb, createPatient, setPatientConsent, getPatient, listPatients,
  createCheckIn, listCheckIns, softDeleteCheckIn, deleteAllCheckIns,
  createClinician, getClinicianByEmail, createSession, getClinicianBySession, deleteSession
} from './db.js';
import {
  hashPassword, verifyPassword, generateSessionToken, hashSessionToken,
  readSessionCookie, sessionCookieHeader, SESSION_TTL_DAYS
} from './auth.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const app = express();
app.set('trust proxy', 1); // honor x-forwarded-proto behind Render/Railway/Fly
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

const ANTHROPIC_API_KEY = process.env.ANTHROPIC_API_KEY;
if (!ANTHROPIC_API_KEY) {
  console.warn('⚠️  ANTHROPIC_API_KEY is not set. /api/summarize will return errors until it is.');
}

const VALID_TAGS = ['Sleep', 'Work', 'Conflict', 'Craving', 'Panic', 'Family', 'Health', 'Win', 'Social', 'Other'];
const MODEL_VERSION = 'claude-sonnet-5';

async function summarizeCheckIn(text) {
  if (!ANTHROPIC_API_KEY) {
    throw new Error('Server is not configured with an API key.');
  }

  const prompt = `A patient sent this between-session check-in to their therapist: "${text.replace(/"/g, '\\"')}"

Respond with ONLY a JSON object, no preamble, no markdown fences, in exactly this shape:
{"summary": "2-3 neutral sentences describing what the patient reported, close to their own words, no clinical diagnosis or interpretation", "auto_tags": ["choose 0-3 from: Sleep, Work, Conflict, Craving, Panic, Family, Health, Win, Social, Other"], "risk_flag": true or false (true ONLY if there is language suggesting self-harm, suicidal ideation, or an acute safety concern)}`;

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

  return {
    summary: typeof parsed.summary === 'string' ? parsed.summary.slice(0, 1000) : 'Check-in received.',
    auto_tags: Array.isArray(parsed.auto_tags) ? parsed.auto_tags.filter(t => VALID_TAGS.includes(t)).slice(0, 3) : [],
    risk_flag: parsed.risk_flag === true
  };
}

app.post('/api/summarize', async (req, res) => {
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

app.post('/api/auth/signup', requireDb, async (req, res) => {
  try {
    const { name, email, password, licenceNumber, province, practiceName } = req.body || {};
    if (!name || !name.trim()) return res.status(400).json({ error: 'Name is required.' });
    if (!email || !EMAIL_RE.test(email.trim())) return res.status(400).json({ error: 'A valid email is required.' });
    if (!password || password.length < 10) return res.status(400).json({ error: 'Password must be at least 10 characters.' });
    // Licence number is required at signup per backend-spec.md — verification
    // against the provincial order registry is stubbed for now (licence_verified
    // stays false until that exists).
    if (!licenceNumber || !licenceNumber.trim()) return res.status(400).json({ error: 'A professional licence/order number is required.' });

    if (await getClinicianByEmail(email.trim())) {
      return res.status(409).json({ error: 'An account with this email already exists.' });
    }

    const clinician = await createClinician({
      name: name.trim(),
      email: email.trim(),
      passwordHash: await hashPassword(password),
      licenceNumber: licenceNumber.trim(),
      province: typeof province === 'string' ? province.trim() : null,
      practiceName: typeof practiceName === 'string' ? practiceName.trim() : null
    });
    await startSession(res, req, clinician.id);
    res.status(201).json({ clinician });
  } catch (err) {
    if (err && err.code === '23505') { // unique_violation — signup raced the pre-check
      return res.status(409).json({ error: 'An account with this email already exists.' });
    }
    console.error('Error in signup:', err);
    res.status(500).json({ error: 'Could not create account.' });
  }
});

app.post('/api/auth/login', requireDb, async (req, res) => {
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

    await startSession(res, req, clinician.id);
    const { password_hash, ...publicClinician } = clinician;
    res.json({ clinician: publicClinician });
  } catch (err) {
    console.error('Error in login:', err);
    res.status(500).json({ error: 'Could not sign in.' });
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
  res.json({ clinician: req.clinician });
});

// --- Patients ---
// All patient routes require a signed-in clinician, and every lookup is scoped
// to that clinician server-side — client-supplied patient IDs are never
// trusted (backend-spec.md §2).

app.post('/api/patients', requireDb, requireAuth, async (req, res) => {
  try {
    const { displayName } = req.body || {};
    if (!displayName || !displayName.trim()) {
      return res.status(400).json({ error: 'displayName is required.' });
    }
    const patient = await createPatient(req.clinician.id, displayName.trim());
    res.status(201).json(patient);
  } catch (err) {
    console.error('Error creating patient:', err);
    res.status(500).json({ error: 'Could not create patient.' });
  }
});

app.get('/api/patients', requireDb, requireAuth, async (req, res) => {
  try {
    res.json(await listPatients(req.clinician.id));
  } catch (err) {
    console.error('Error listing patients:', err);
    res.status(500).json({ error: 'Could not list patients.' });
  }
});

app.post('/api/patients/:id/consent', requireDb, requireAuth, async (req, res) => {
  try {
    const { enabled } = req.body || {};
    const patient = await setPatientConsent(req.clinician.id, req.params.id, !!enabled);
    if (!patient) return res.status(404).json({ error: 'Patient not found.' });
    res.json(patient);
  } catch (err) {
    console.error('Error updating consent:', err);
    res.status(500).json({ error: 'Could not update consent.' });
  }
});

// --- Check-ins ---

app.post('/api/patients/:id/check-ins', requireDb, requireAuth, async (req, res) => {
  try {
    const { moodScore, manualTags, text } = req.body || {};

    const patient = await getPatient(req.clinician.id, req.params.id);
    if (!patient) return res.status(404).json({ error: 'Patient not found.' });

    let summaryText = null, autoTags = [], riskFlag = false, modelVersion = null;

    // Only call the AI if this patient has actually opted in — mirrors the
    // privacy-by-default rule from the consent flow, enforced server-side too.
    if (patient.ai_consent_enabled && text && text.trim()) {
      try {
        const result = await summarizeCheckIn(text.trim());
        summaryText = result.summary;
        autoTags = result.auto_tags;
        riskFlag = result.risk_flag;
        modelVersion = MODEL_VERSION;
      } catch (aiErr) {
        // Don't lose the check-in because the AI call failed — store it raw.
        console.error('AI summarization failed, storing check-in without summary:', aiErr);
        summaryText = text.trim().slice(0, 1000);
      }
    } else if (text && text.trim()) {
      summaryText = text.trim().slice(0, 1000); // no AI: store as-typed, no profiling
    }

    const checkIn = await createCheckIn({
      patientId: patient.id, moodScore, manualTags, rawText: text || null,
      summaryText, autoTags, riskFlag, modelVersion
    });

    res.status(201).json(checkIn);
  } catch (err) {
    console.error('Error creating check-in:', err);
    res.status(500).json({ error: 'Could not create check-in.' });
  }
});

app.get('/api/patients/:id/check-ins', requireDb, requireAuth, async (req, res) => {
  try {
    const patient = await getPatient(req.clinician.id, req.params.id);
    if (!patient) return res.status(404).json({ error: 'Patient not found.' });
    res.json(await listCheckIns(patient.id));
  } catch (err) {
    console.error('Error listing check-ins:', err);
    res.status(500).json({ error: 'Could not list check-ins.' });
  }
});

app.delete('/api/patients/:id/check-ins/:checkInId', requireDb, requireAuth, async (req, res) => {
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

app.delete('/api/patients/:id/check-ins', requireDb, requireAuth, async (req, res) => {
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

// Simple health check — useful for most hosting platforms' uptime checks
app.get('/health', (req, res) => res.json({ ok: true }));

const PORT = process.env.PORT || 3000;
initDb().then(() => {
  app.listen(PORT, () => console.log(`Between server running on port ${PORT}`));
}).catch(err => {
  console.error('Failed to initialize database:', err);
  app.listen(PORT, () => console.log(`Between server running on port ${PORT} (without DB)`));
});
