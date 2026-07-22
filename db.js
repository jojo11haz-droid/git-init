import pg from 'pg';

const { Pool } = pg;

// DATABASE_URL is provided by your host (Neon/Supabase/Render Postgres all give you one
// connection string). Locally, put it in .env as DATABASE_URL=postgres://...
const pool = process.env.DATABASE_URL
  ? new Pool({
      connectionString: process.env.DATABASE_URL,
      ssl: process.env.DATABASE_SSL === 'disable'
        ? false
        : { rejectUnauthorized: false } // most hosted free-tier Postgres requires SSL
    })
  : null;

export function dbEnabled() {
  return !!pool;
}

// Minimal schema for now — a trimmed version of backend-spec.md's full model.
const SCHEMA = `
CREATE TABLE IF NOT EXISTS clinicians (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  licence_number TEXT NOT NULL,
  licence_verified BOOLEAN NOT NULL DEFAULT false,
  province TEXT,
  practice_name TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS auth_sessions (
  token_hash TEXT PRIMARY KEY,
  clinician_id UUID NOT NULL REFERENCES clinicians(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE IF NOT EXISTS patients (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  clinician_id UUID REFERENCES clinicians(id),
  display_name TEXT NOT NULL,
  email TEXT,
  password_hash TEXT,
  invite_code TEXT,
  invite_status TEXT NOT NULL DEFAULT 'pending',
  ai_consent_enabled BOOLEAN NOT NULL DEFAULT false,
  consent_recorded_at TIMESTAMPTZ,
  consent_version TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS patient_sessions (
  token_hash TEXT PRIMARY KEY,
  patient_id UUID NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL
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
  patient_flagged_inaccurate BOOLEAN NOT NULL DEFAULT false,
  submitted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);
`;

// Databases created before the auth release have a patients table without
// clinician_id. Pre-auth rows keep a NULL clinician_id and become invisible
// to every account (rather than leaking to the first signup); reassign them
// manually if they matter.
const MIGRATIONS = `
ALTER TABLE patients ADD COLUMN IF NOT EXISTS clinician_id UUID REFERENCES clinicians(id);
ALTER TABLE patients ADD COLUMN IF NOT EXISTS email TEXT;
ALTER TABLE patients ADD COLUMN IF NOT EXISTS password_hash TEXT;
ALTER TABLE patients ADD COLUMN IF NOT EXISTS invite_code TEXT;
ALTER TABLE patients ADD COLUMN IF NOT EXISTS invite_status TEXT NOT NULL DEFAULT 'pending';
ALTER TABLE patients ADD COLUMN IF NOT EXISTS consent_version TEXT;
ALTER TABLE check_ins ADD COLUMN IF NOT EXISTS patient_flagged_inaccurate BOOLEAN NOT NULL DEFAULT false;
CREATE UNIQUE INDEX IF NOT EXISTS patients_email_key ON patients (lower(email)) WHERE email IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS patients_invite_code_key ON patients (invite_code) WHERE invite_code IS NOT NULL;
`;

export async function initDb() {
  if (!pool) {
    console.warn('⚠️  DATABASE_URL not set — running without persistence (check-ins will not be saved).');
    return;
  }
  await pool.query('CREATE EXTENSION IF NOT EXISTS "pgcrypto";'); // needed for gen_random_uuid()
  await pool.query(SCHEMA);
  await pool.query(MIGRATIONS);
  console.log('✅ Database ready.');
}

// --- Clinicians & sessions ---

const CLINICIAN_PUBLIC_COLS = 'id, name, email, licence_number, licence_verified, province, practice_name, created_at';

export async function createClinician({ name, email, passwordHash, licenceNumber, province, practiceName }) {
  const { rows } = await pool.query(
    `INSERT INTO clinicians (name, email, password_hash, licence_number, province, practice_name)
     VALUES ($1, lower($2), $3, $4, $5, $6)
     RETURNING ${CLINICIAN_PUBLIC_COLS}`,
    [name, email, passwordHash, licenceNumber, province || null, practiceName || null]
  );
  return rows[0];
}

export async function getClinicianByEmail(email) {
  const { rows } = await pool.query(
    `SELECT * FROM clinicians WHERE email = lower($1)`,
    [email]
  );
  return rows[0] || null;
}

export async function createSession(tokenHash, clinicianId, ttlDays) {
  await pool.query(
    `INSERT INTO auth_sessions (token_hash, clinician_id, expires_at)
     VALUES ($1, $2, now() + ($3 || ' days')::interval)`,
    [tokenHash, clinicianId, String(ttlDays)]
  );
}

export async function getClinicianBySession(tokenHash) {
  const { rows } = await pool.query(
    `SELECT ${CLINICIAN_PUBLIC_COLS.split(', ').map(c => 'c.' + c).join(', ')}
     FROM auth_sessions s JOIN clinicians c ON c.id = s.clinician_id
     WHERE s.token_hash = $1 AND s.expires_at > now()`,
    [tokenHash]
  );
  return rows[0] || null;
}

export async function deleteSession(tokenHash) {
  await pool.query(`DELETE FROM auth_sessions WHERE token_hash = $1`, [tokenHash]);
}

// --- Patients ---
// Every query below is scoped by clinician_id: a clinician can only ever see
// or touch their own patients, no matter what IDs the client sends.
// PATIENT_ROW_COLS deliberately excludes password_hash so patient credentials
// never ride along in an API response.

const PATIENT_ROW_COLS = 'id, clinician_id, display_name, email, invite_code, invite_status, ai_consent_enabled, consent_recorded_at, consent_version, created_at';

export async function createPatient(clinicianId, displayName, inviteCode) {
  const { rows } = await pool.query(
    `INSERT INTO patients (clinician_id, display_name, invite_code) VALUES ($1, $2, $3)
     RETURNING ${PATIENT_ROW_COLS}`,
    [clinicianId, displayName, inviteCode]
  );
  return rows[0];
}

export async function setPatientConsent(clinicianId, patientId, enabled, consentVersion) {
  const { rows } = await pool.query(
    `UPDATE patients SET ai_consent_enabled = $1, consent_recorded_at = now(), consent_version = $2
     WHERE id = $3 AND clinician_id = $4 RETURNING ${PATIENT_ROW_COLS}`,
    [enabled, consentVersion, patientId, clinicianId]
  );
  return rows[0] || null;
}

export async function getPatient(clinicianId, patientId) {
  const { rows } = await pool.query(
    `SELECT ${PATIENT_ROW_COLS} FROM patients WHERE id = $1 AND clinician_id = $2`,
    [patientId, clinicianId]
  );
  return rows[0] || null;
}

export async function listPatients(clinicianId) {
  const { rows } = await pool.query(
    `SELECT ${PATIENT_ROW_COLS.split(', ').map(c => 'p.' + c).join(', ')},
       count(c.id) FILTER (WHERE c.deleted_at IS NULL)::int AS check_in_count,
       coalesce(bool_or(c.risk_flag AND c.deleted_at IS NULL AND c.submitted_at > now() - interval '48 hours'), false) AS has_recent_risk
     FROM patients p
     LEFT JOIN check_ins c ON c.patient_id = p.id
     WHERE p.clinician_id = $1
     GROUP BY p.id
     ORDER BY p.created_at DESC`,
    [clinicianId]
  );
  return rows;
}

// --- Patient auth (patient-facing scope) ---
// A patient signs in with credentials attached to their own patients row.
// There is deliberately no query here that returns more than one patient:
// the patient scope has no caseload concept at all.

export async function getPatientByInviteCode(inviteCode) {
  const { rows } = await pool.query(
    `SELECT * FROM patients WHERE invite_code = $1`,
    [inviteCode]
  );
  return rows[0] || null;
}

export async function getPatientByEmail(email) {
  const { rows } = await pool.query(
    `SELECT * FROM patients WHERE lower(email) = lower($1)`,
    [email]
  );
  return rows[0] || null;
}

export async function acceptPatientInvite(patientId, email, passwordHash) {
  const { rows } = await pool.query(
    `UPDATE patients SET email = $1, password_hash = $2, invite_status = 'accepted'
     WHERE id = $3 AND invite_status = 'pending'
     RETURNING ${PATIENT_ROW_COLS}`,
    [email, passwordHash, patientId]
  );
  return rows[0] || null;
}

export async function setOwnConsent(patientId, enabled, consentVersion) {
  const { rows } = await pool.query(
    `UPDATE patients SET ai_consent_enabled = $1, consent_recorded_at = now(), consent_version = $2
     WHERE id = $3 RETURNING ${PATIENT_ROW_COLS}`,
    [enabled, consentVersion, patientId]
  );
  return rows[0] || null;
}

export async function createPatientSession(tokenHash, patientId, ttlDays) {
  await pool.query(
    `INSERT INTO patient_sessions (token_hash, patient_id, expires_at)
     VALUES ($1, $2, now() + ($3 || ' days')::interval)`,
    [tokenHash, patientId, String(ttlDays)]
  );
}

export async function getPatientBySession(tokenHash) {
  const { rows } = await pool.query(
    `SELECT ${PATIENT_ROW_COLS.split(', ').map(c => 'p.' + c).join(', ')}
     FROM patient_sessions s JOIN patients p ON p.id = s.patient_id
     WHERE s.token_hash = $1 AND s.expires_at > now()`,
    [tokenHash]
  );
  return rows[0] || null;
}

export async function deletePatientSession(tokenHash) {
  await pool.query(`DELETE FROM patient_sessions WHERE token_hash = $1`, [tokenHash]);
}

export async function flagCheckInInaccurate(checkInId, patientId) {
  const { rows } = await pool.query(
    `UPDATE check_ins SET patient_flagged_inaccurate = true
     WHERE id = $1 AND patient_id = $2 AND deleted_at IS NULL RETURNING *`,
    [checkInId, patientId]
  );
  return rows[0] || null;
}

export async function getCheckIn(checkInId, patientId) {
  const { rows } = await pool.query(
    `SELECT * FROM check_ins WHERE id = $1 AND patient_id = $2 AND deleted_at IS NULL`,
    [checkInId, patientId]
  );
  return rows[0] || null;
}

// --- Check-ins ---
// Routes must resolve the patient through getPatient (clinician-scoped) first,
// so by the time these run, patientId is known to belong to the caller.

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
