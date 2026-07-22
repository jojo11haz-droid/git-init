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
  mfa_secret TEXT,
  mfa_enabled BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS mfa_challenges (
  token_hash TEXT PRIMARY KEY,
  clinician_id UUID NOT NULL REFERENCES clinicians(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL
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

CREATE TABLE IF NOT EXISTS audio_uploads (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
  mime TEXT NOT NULL,
  data BYTEA NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS audio_upload_tokens (
  token_hash TEXT PRIMARY KEY,
  patient_id UUID NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
  expires_at TIMESTAMPTZ NOT NULL,
  used_at TIMESTAMPTZ
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
  audio_upload_id UUID REFERENCES audio_uploads(id),
  submitted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS password_resets (
  token_hash TEXT PRIMARY KEY,
  clinician_id UUID NOT NULL REFERENCES clinicians(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL,
  used_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS alerts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  check_in_id UUID NOT NULL REFERENCES check_ins(id) ON DELETE CASCADE,
  clinician_id UUID NOT NULL REFERENCES clinicians(id) ON DELETE CASCADE,
  delivery_channel TEXT,
  delivered_at TIMESTAMPTZ,
  viewed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
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
ALTER TABLE clinicians ADD COLUMN IF NOT EXISTS mfa_secret TEXT;
ALTER TABLE clinicians ADD COLUMN IF NOT EXISTS mfa_enabled BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE check_ins ADD COLUMN IF NOT EXISTS patient_flagged_inaccurate BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE check_ins ADD COLUMN IF NOT EXISTS audio_upload_id UUID REFERENCES audio_uploads(id);
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

const CLINICIAN_PUBLIC_COLS = 'id, name, email, licence_number, licence_verified, province, practice_name, mfa_enabled, created_at';

export async function createClinician({ name, email, passwordHash, licenceNumber, province, practiceName }) {
  const { rows } = await pool.query(
    `INSERT INTO clinicians (name, email, password_hash, licence_number, province, practice_name)
     VALUES ($1, lower($2), $3, $4, $5, $6)
     RETURNING ${CLINICIAN_PUBLIC_COLS}`,
    [name, email, passwordHash, licenceNumber, province || null, practiceName || null]
  );
  return rows[0];
}

export async function getClinicianById(id) {
  const { rows } = await pool.query(
    `SELECT ${CLINICIAN_PUBLIC_COLS} FROM clinicians WHERE id = $1`,
    [id]
  );
  return rows[0] || null;
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

export async function deleteClinicianSessions(clinicianId) {
  await pool.query(`DELETE FROM auth_sessions WHERE clinician_id = $1`, [clinicianId]);
}

// --- MFA (TOTP) ---

export async function getClinicianMfa(clinicianId) {
  const { rows } = await pool.query(
    `SELECT id, mfa_secret, mfa_enabled FROM clinicians WHERE id = $1`,
    [clinicianId]
  );
  return rows[0] || null;
}

export async function setMfaSecret(clinicianId, secret) {
  await pool.query(
    `UPDATE clinicians SET mfa_secret = $1, mfa_enabled = false, updated_at = now() WHERE id = $2`,
    [secret, clinicianId]
  );
}

export async function setMfaEnabled(clinicianId, enabled) {
  await pool.query(
    `UPDATE clinicians SET mfa_enabled = $1, mfa_secret = CASE WHEN $1 THEN mfa_secret ELSE NULL END, updated_at = now() WHERE id = $2`,
    [enabled, clinicianId]
  );
}

// Short-lived challenge issued after a correct password when MFA is on; the
// session only starts once the TOTP code checks out.
export async function createMfaChallenge(tokenHash, clinicianId, ttlMinutes) {
  await pool.query(
    `INSERT INTO mfa_challenges (token_hash, clinician_id, expires_at)
     VALUES ($1, $2, now() + ($3 || ' minutes')::interval)`,
    [tokenHash, clinicianId, String(ttlMinutes)]
  );
}

export async function getValidMfaChallenge(tokenHash) {
  const { rows } = await pool.query(
    `SELECT * FROM mfa_challenges WHERE token_hash = $1 AND expires_at > now()`,
    [tokenHash]
  );
  return rows[0] || null;
}

export async function deleteMfaChallenge(tokenHash) {
  await pool.query(`DELETE FROM mfa_challenges WHERE token_hash = $1`, [tokenHash]);
}

// --- Clinician password reset ---

export async function createPasswordReset(tokenHash, clinicianId, ttlMinutes) {
  await pool.query(
    `INSERT INTO password_resets (token_hash, clinician_id, expires_at)
     VALUES ($1, $2, now() + ($3 || ' minutes')::interval)`,
    [tokenHash, clinicianId, String(ttlMinutes)]
  );
}

export async function getValidPasswordReset(tokenHash) {
  const { rows } = await pool.query(
    `SELECT * FROM password_resets
     WHERE token_hash = $1 AND used_at IS NULL AND expires_at > now()`,
    [tokenHash]
  );
  return rows[0] || null;
}

export async function consumePasswordReset(tokenHash, clinicianId, newPasswordHash) {
  // One transaction: mark the token used, set the new password, and revoke
  // every existing session for the account.
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(
      `UPDATE password_resets SET used_at = now() WHERE token_hash = $1`,
      [tokenHash]
    );
    await client.query(
      `UPDATE clinicians SET password_hash = $1, updated_at = now() WHERE id = $2`,
      [newPasswordHash, clinicianId]
    );
    await client.query(
      `DELETE FROM auth_sessions WHERE clinician_id = $1`,
      [clinicianId]
    );
    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
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

// Patient "password reset" is therapist-mediated (no patient email infra
// needed): the clinician resets app access, which issues a fresh one-time
// invite code, clears the old password, and revokes the patient's sessions.
// History and consent stay intact — same patient row.
export async function resetPatientAccess(clinicianId, patientId, newInviteCode) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const { rows } = await client.query(
      `UPDATE patients SET invite_code = $1, invite_status = 'pending', password_hash = NULL
       WHERE id = $2 AND clinician_id = $3 RETURNING ${PATIENT_ROW_COLS}`,
      [newInviteCode, patientId, clinicianId]
    );
    if (rows[0]) {
      await client.query(`DELETE FROM patient_sessions WHERE patient_id = $1`, [patientId]);
    }
    await client.query('COMMIT');
    return rows[0] || null;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

// --- Audio uploads (voice memos) ---
// Stored as bytea for the MVP so no object-storage account is needed.
// TODO before real scale: move to S3/R2-style object storage and keep only
// the object key here (backend-spec.md's audio_object_key).

export async function createAudioUploadToken(tokenHash, patientId, ttlMinutes) {
  await pool.query(
    `INSERT INTO audio_upload_tokens (token_hash, patient_id, expires_at)
     VALUES ($1, $2, now() + ($3 || ' minutes')::interval)`,
    [tokenHash, patientId, String(ttlMinutes)]
  );
}

export async function consumeAudioUploadToken(tokenHash) {
  const { rows } = await pool.query(
    `UPDATE audio_upload_tokens SET used_at = now()
     WHERE token_hash = $1 AND used_at IS NULL AND expires_at > now()
     RETURNING patient_id`,
    [tokenHash]
  );
  return rows[0] || null;
}

export async function storeAudioUpload(patientId, mime, data) {
  const { rows } = await pool.query(
    `INSERT INTO audio_uploads (patient_id, mime, data) VALUES ($1, $2, $3) RETURNING id`,
    [patientId, mime, data]
  );
  return rows[0].id;
}

export async function getAudioUploadOwned(uploadId, patientId) {
  const { rows } = await pool.query(
    `SELECT id, mime, data FROM audio_uploads WHERE id = $1 AND patient_id = $2`,
    [uploadId, patientId]
  );
  return rows[0] || null;
}

export async function getAudioForClinician(uploadId, clinicianId) {
  const { rows } = await pool.query(
    `SELECT a.id, a.mime, a.data
     FROM audio_uploads a JOIN patients p ON p.id = a.patient_id
     WHERE a.id = $1 AND p.clinician_id = $2`,
    [uploadId, clinicianId]
  );
  return rows[0] || null;
}

// --- Alerts (risk-flag notifications for clinicians) ---

export async function createAlert({ checkInId, clinicianId, deliveryChannel, deliveredAt }) {
  const { rows } = await pool.query(
    `INSERT INTO alerts (check_in_id, clinician_id, delivery_channel, delivered_at)
     VALUES ($1, $2, $3, $4) RETURNING *`,
    [checkInId, clinicianId, deliveryChannel || null, deliveredAt || null]
  );
  return rows[0];
}

export async function listAlerts(clinicianId) {
  const { rows } = await pool.query(
    `SELECT al.id, al.check_in_id, al.viewed_at, al.created_at,
            al.delivery_channel, al.delivered_at,
            p.id AS patient_id, p.display_name AS patient_name,
            c.summary_text, c.submitted_at
     FROM alerts al
     JOIN check_ins c ON c.id = al.check_in_id
     JOIN patients p ON p.id = c.patient_id
     WHERE al.clinician_id = $1 AND c.deleted_at IS NULL
     ORDER BY al.created_at DESC
     LIMIT 50`,
    [clinicianId]
  );
  return rows;
}

export async function markAlertViewed(alertId, clinicianId) {
  const { rows } = await pool.query(
    `UPDATE alerts SET viewed_at = now() WHERE id = $1 AND clinician_id = $2 RETURNING *`,
    [alertId, clinicianId]
  );
  return rows[0] || null;
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

export async function createCheckIn({ patientId, moodScore, manualTags, rawText, summaryText, autoTags, riskFlag, modelVersion, audioUploadId }) {
  const { rows } = await pool.query(
    `INSERT INTO check_ins (patient_id, mood_score, manual_tags, raw_text, summary_text, auto_tags, risk_flag, model_version, audio_upload_id)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING *`,
    [patientId, moodScore, manualTags || [], rawText || null, summaryText || null, autoTags || [], !!riskFlag, modelVersion || null, audioUploadId || null]
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
