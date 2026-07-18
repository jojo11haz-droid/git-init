import express from 'express';
import path from 'path';
import { fileURLToPath } from 'url';
import {
  dbEnabled, initDb, createPatient, setPatientConsent, getPatient, listPatients,
  createCheckIn, listCheckIns, softDeleteCheckIn, deleteAllCheckIns
} from './db.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const app = express();
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

// --- Patients ---
// No auth yet — these are open. Do not point this at real patient data until
// the auth system in backend-spec.md is in place.

app.post('/api/patients', async (req, res) => {
  if (!dbEnabled()) return res.status(503).json({ error: 'Database not configured.' });
  try {
    const { displayName } = req.body || {};
    if (!displayName || !displayName.trim()) {
      return res.status(400).json({ error: 'displayName is required.' });
    }
    const patient = await createPatient(displayName.trim());
    res.status(201).json(patient);
  } catch (err) {
    console.error('Error creating patient:', err);
    res.status(500).json({ error: 'Could not create patient.' });
  }
});

app.get('/api/patients', async (req, res) => {
  if (!dbEnabled()) return res.status(503).json({ error: 'Database not configured.' });
  try {
    res.json(await listPatients());
  } catch (err) {
    console.error('Error listing patients:', err);
    res.status(500).json({ error: 'Could not list patients.' });
  }
});

app.post('/api/patients/:id/consent', async (req, res) => {
  if (!dbEnabled()) return res.status(503).json({ error: 'Database not configured.' });
  try {
    const { enabled } = req.body || {};
    const patient = await setPatientConsent(req.params.id, !!enabled);
    if (!patient) return res.status(404).json({ error: 'Patient not found.' });
    res.json(patient);
  } catch (err) {
    console.error('Error updating consent:', err);
    res.status(500).json({ error: 'Could not update consent.' });
  }
});

// --- Check-ins ---

app.post('/api/patients/:id/check-ins', async (req, res) => {
  if (!dbEnabled()) return res.status(503).json({ error: 'Database not configured.' });
  try {
    const patientId = req.params.id;
    const { moodScore, manualTags, text } = req.body || {};

    const patient = await getPatient(patientId);
    if (!patient) return res.status(404).json({ error: 'Patient not found.' });

    let summaryText = null, autoTags = [], riskFlag = false, modelVersion = null;

    // Only call the AI if this patient has actually opted in — mirrors the
    // privacy-by-default rule from the consent flow, enforced server-side too.
    if (patient.ai_consent_enabled && text && text.trim()) {
      const result = await summarizeCheckIn(text.trim());
      summaryText = result.summary;
      autoTags = result.auto_tags;
      riskFlag = result.risk_flag;
      modelVersion = MODEL_VERSION;
    } else if (text && text.trim()) {
      summaryText = text.trim().slice(0, 1000); // no AI: store as-typed, no profiling
    }

    const checkIn = await createCheckIn({
      patientId, moodScore, manualTags, rawText: text || null,
      summaryText, autoTags, riskFlag, modelVersion
    });

    res.status(201).json(checkIn);
  } catch (err) {
    console.error('Error creating check-in:', err);
    res.status(500).json({ error: err.message || 'Could not create check-in.' });
  }
});

app.get('/api/patients/:id/check-ins', async (req, res) => {
  if (!dbEnabled()) return res.status(503).json({ error: 'Database not configured.' });
  try {
    res.json(await listCheckIns(req.params.id));
  } catch (err) {
    console.error('Error listing check-ins:', err);
    res.status(500).json({ error: 'Could not list check-ins.' });
  }
});

app.delete('/api/patients/:id/check-ins/:checkInId', async (req, res) => {
  if (!dbEnabled()) return res.status(503).json({ error: 'Database not configured.' });
  try {
    const deleted = await softDeleteCheckIn(req.params.checkInId, req.params.id);
    if (!deleted) return res.status(404).json({ error: 'Check-in not found.' });
    res.json({ ok: true });
  } catch (err) {
    console.error('Error deleting check-in:', err);
    res.status(500).json({ error: 'Could not delete check-in.' });
  }
});

app.delete('/api/patients/:id/check-ins', async (req, res) => {
  if (!dbEnabled()) return res.status(503).json({ error: 'Database not configured.' });
  try {
    await deleteAllCheckIns(req.params.id);
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
