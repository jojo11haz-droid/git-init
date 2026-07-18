import pg from 'pg';

const { Pool } = pg;

// DATABASE_URL is provided by your host (Neon/Supabase/Render Postgres all give you one
// connection string). Locally, put it in .env as DATABASE_URL=postgres://...
const pool = process.env.DATABASE_URL
  ? new Pool({
      connectionString: process.env.DATABASE_URL,
      ssl: { rejectUnauthorized: false } // most hosted free-tier Postgres requires SSL
    })
  : null;

export function dbEnabled() {
  return !!pool;
}

// Minimal schema for now — a trimmed version of backend-spec.md's full model.
// No clinicians/auth table yet: that has to arrive before this is used with real patient data.
const SCHEMA = `
CREATE TABLE IF NOT EXISTS patients (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  display_name TEXT NOT NULL,
  ai_consent_enabled BOOLEAN NOT NULL DEFAULT false,
  consent_recorded_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS check_ins (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
  mood_score INT,
  manual_tags TEXT[],
  raw_text TEXT,
  summary_text TEXT,
  auto_tags TEXT[],
  risk_flag BOOLEAN NOT NULL DEFAULT false,
  model_version TEXT,
  submitted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);
`;

export async function initDb() {
  if (!pool) {
    console.warn('⚠️  DATABASE_URL not set — running without persistence (check-ins will not be saved).');
    return;
  }
  await pool.query('CREATE EXTENSION IF NOT EXISTS "pgcrypto";'); // needed for gen_random_uuid()
  await pool.query(SCHEMA);
  console.log('✅ Database ready.');
}

export async function createPatient(displayName) {
  const { rows } = await pool.query(
    `INSERT INTO patients (display_name) VALUES ($1) RETURNING *`,
    [displayName]
  );
  return rows[0];
}

export async function setPatientConsent(patientId, enabled) {
  const { rows } = await pool.query(
    `UPDATE patients SET ai_consent_enabled = $1, consent_recorded_at = now() WHERE id = $2 RETURNING *`,
    [enabled, patientId]
  );
  return rows[0];
}

export async function getPatient(patientId) {
  const { rows } = await pool.query(`SELECT * FROM patients WHERE id = $1`, [patientId]);
  return rows[0] || null;
}

export async function listPatients() {
  const { rows } = await pool.query(`SELECT * FROM patients ORDER BY created_at DESC`);
  return rows;
}

export async function createCheckIn({ patientId, moodScore, manualTags, rawText, summaryText, autoTags, riskFlag, modelVersion }) {
  const { rows } = await pool.query(
    `INSERT INTO check_ins (patient_id, mood_score, manual_tags, raw_text, summary_text, auto_tags, risk_flag, model_version)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8) RETURNING *`,
    [patientId, moodScore, manualTags || [], rawText || null, summaryText || null, autoTags || [], !!riskFlag, modelVersion || null]
  );
  return rows[0];
}

export async function listCheckIns(patientId) {
  const { rows } = await pool.query(
    `SELECT * FROM check_ins WHERE patient_id = $1 AND deleted_at IS NULL ORDER BY submitted_at DESC`,
    [patientId]
  );
  return rows;
}

export async function softDeleteCheckIn(checkInId, patientId) {
  const { rows } = await pool.query(
    `UPDATE check_ins SET deleted_at = now() WHERE id = $1 AND patient_id = $2 RETURNING *`,
    [checkInId, patientId]
  );
  return rows[0] || null;
}

export async function deleteAllCheckIns(patientId) {
  await pool.query(`UPDATE check_ins SET deleted_at = now() WHERE patient_id = $1`, [patientId]);
}
