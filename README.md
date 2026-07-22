# Between — backend

A minimal Express server that serves the Between site and handles AI summarization **server-side**, so your Anthropic API key never reaches the browser.

## What this fixes vs. the earlier prototype
The standalone `prototype.html` called the Anthropic API directly from the browser — that only worked inside Claude's own environment. This version moves that call into `server.js`, which runs on a server and reads the API key from an environment variable. The frontend now calls your own `/api/summarize` endpoint instead.

## Run it locally

```bash
npm install
cp .env.example .env
# edit .env: paste in your Anthropic API key and a DATABASE_URL (see below)
npm start
```

Then open `http://localhost:3000` — the site, AI summarization, and check-in persistence should all work.

### Getting a database
Free hosted Postgres, either works:
- **[Neon](https://neon.tech)** — free tier, gives you a `DATABASE_URL` connection string immediately after signup.
- **[Supabase](https://supabase.com)** — also free tier, same idea, connection string is under Project Settings → Database.

Paste that connection string into `.env` as `DATABASE_URL`. The server creates its own tables automatically on startup — no manual migration step needed for this MVP schema.

If `DATABASE_URL` isn't set, the server still runs (so you can test the static site and `/api/summarize`), but every `/api/patients/*` and check-in endpoint will return a 503 instead of silently losing data.

## API endpoints

### Auth (clinician accounts)

| Route | What it does |
|---|---|
| `POST /api/auth/signup` | Create a clinician account (`{ name, email, password, licenceNumber, province?, practiceName? }`). `licenceNumber` is required per `backend-spec.md`; verification against the provincial order registry is stubbed for now (`licence_verified` stays false). Passwords are hashed with scrypt. Signs you in on success. |
| `POST /api/auth/login` | `{ email, password }` — sets an httpOnly session cookie (30-day, DB-backed) |
| `POST /api/auth/logout` | Deletes the session server-side and clears the cookie |
| `GET /api/auth/me` | The signed-in clinician, or 401 |
| `POST /api/auth/password/reset-request` | `{ email }` — always returns ok (no account enumeration). Emails a 60-minute reset link via Resend if `RESEND_API_KEY` is set, otherwise prints it to the server logs |
| `POST /api/auth/password/reset-confirm` | `{ token, newPassword }` — single-use token; also revokes every existing session for the account |
| `POST /api/auth/mfa/enroll` | Generate a TOTP secret + `otpauth://` URL (shown once). Not active until verified |
| `POST /api/auth/mfa/verify` | `{ code }` — confirm one authenticator code to switch MFA on |
| `POST /api/auth/mfa/disable` | `{ code }` — turn MFA off (requires a current code) |
| `POST /api/auth/login/mfa` | `{ mfaToken, code }` — when login returns `{ mfaRequired, mfaToken }`, complete it here to get the session |

Two-factor is standard TOTP (RFC 6238), so any authenticator app works (Google Authenticator, 1Password, Authy…). Implemented on Node's `crypto` — no extra dependencies.

### Patients & check-ins (require auth)

Every route below requires a signed-in clinician, and every lookup is scoped to that clinician server-side — a clinician can only ever see or modify their own patients. Requests for another clinician's patient return 404.

| Route | What it does |
|---|---|
| `POST /api/patients` | Create a patient (`{ displayName }`) under the signed-in clinician — returns a one-time `invite_code` for the patient app |
| `GET /api/patients` | Caseload for the signed-in clinician (includes `check_in_count` and `has_recent_risk`) |
| `POST /api/patients/:id/reset-access` | Patient "password reset", therapist-mediated: issues a fresh invite code, clears the patient's password, revokes their sessions. History and consent stay intact |
| `POST /api/patients/:id/consent` | Set `ai_consent_enabled` (`{ enabled: true/false }`) |
| `GET /api/patients/:id/check-ins/:checkInId/audio` | Stream a check-in's voice memo |
| `GET /api/alerts` | Risk-alert feed for the signed-in clinician (created automatically when a check-in is risk-flagged; also emailed if email is configured) |
| `POST /api/alerts/:id/mark-viewed` | For the clinician's own tracking only — no escalation logic, per the no-response-required product decision |
| `POST /api/patients/:id/check-ins` | Create a check-in (`{ text, moodScore, manualTags }`) — only calls the AI if that patient has consent enabled; if the AI call fails, the check-in is stored raw instead of being lost |
| `GET /api/patients/:id/check-ins` | List a patient's check-in history |
| `DELETE /api/patients/:id/check-ins/:checkInId` | Soft-delete one check-in |
| `DELETE /api/patients/:id/check-ins` | Soft-delete all of a patient's check-ins (the "request deletion" button) |

### Patient scope (`/api/patient/*`, Bearer-token auth — used by the Flutter app)

Separate auth scope for patients, used by the mobile app in `patient_app/`. Authenticated with `Authorization: Bearer <token>` (no cookies). Every route is limited to the signed-in patient's own row — this scope has no caseload concept and no way to reach another patient's data. CORS is enabled for this scope only.

| Route | What it does |
|---|---|
| `POST /api/patient/accept-invite` | `{ inviteCode, email, password }` — one-time: turns a therapist-issued invite code into the patient's own login |
| `POST /api/patient/login` / `logout` | Bearer-token session (30 days, revocable) |
| `GET /api/patient/me` | The signed-in patient |
| `GET/POST /api/patient/consent` | Read / record the patient's own consent (version + timestamp, Law 25). Check-ins are blocked until consent is recorded |
| `POST /api/patient/check-ins` | Send a check-in (`{ text?, moodScore?, manualTags?, audioUploadId? }`). AI runs only if this patient opted in. If risk is flagged, crisis resources come back in the same response |
| `POST /api/patient/check-ins/audio-upload-url` | Returns a short-lived signed upload URL for a voice memo — raw audio never goes through the JSON API |
| `PUT /api/patient/audio-upload/:token` | Upload the audio bytes (single-use token, 15 MB max). Stored in Postgres for the MVP; move to object storage at scale. **No transcription yet** — voice memos are stored and playable, but not summarized or risk-screened until a speech-to-text provider is added |
| `GET /api/patient/check-ins/:id/audio` | Stream the patient's own voice memo |
| `GET /api/patient/check-ins` | Own history only |
| `DELETE /api/patient/check-ins/:id` | 15-minute grace-period undo (refused for risk-flagged check-ins) |
| `DELETE /api/patient/check-ins` | Request deletion of the whole history (erasure right, not time-limited) |
| `POST /api/patient/check-ins/:id/flag-inaccurate` | Contest an AI summary |

### Unauthenticated

| Route | What it does |
|---|---|
| `POST /api/summarize` | Stateless — summarize arbitrary text, nothing saved. Kept for the standalone demo; rate-limit or remove before production. |
| `GET /health` | Uptime check |

**Migrating a pre-auth database:** the server adds `patients.clinician_id` automatically on startup. Patients created before auth existed keep a `NULL` clinician_id and are invisible to every account (rather than leaking to the first signup) — reassign them in SQL if you need them back.

## Deploy it (get a real public link)

Any Node-friendly host works. **Render** is a good first choice — free tier, simple env-var UI, no credit card required to start.

### Render
1. Push this folder to a GitHub repo.
2. On [render.com](https://render.com), click **New → Web Service**, connect the repo.
3. Build command: `npm install` · Start command: `npm start`.
4. Under **Environment**, add `ANTHROPIC_API_KEY` with your real key. Never put it in the code or commit it.
5. Deploy. You'll get a URL like `between-xyz.onrender.com`.

### Railway / Fly.io
Similar flow — connect the repo or `git push`, set `ANTHROPIC_API_KEY` as a secret/environment variable in their dashboard, deploy.

### Custom domain
Once deployed, every host above has a "custom domain" setting — point your domain's DNS at what they give you (usually a CNAME record).

## Important before this touches real patients
This is still a prototype backend, not a production one. Before any real check-in data flows through it:

- **Auth.** Clinician signup/login and patient invite/login with hashed passwords, strict per-account data scoping, password reset for both scopes (email-link for clinicians, therapist-mediated access reset for patients), and optional TOTP two-factor for clinicians are all in place. Licence verification is still stubbed (`licence_verified` is never set true) — the remaining item in `backend-spec.md` before real use.
- **Voice-memo transcription needs a Deepgram key to be active.** With `DEEPGRAM_API_KEY` set, voice memos are transcribed server-side and flow through the same consent-gated AI summary + risk screening as typed check-ins. Without it, memos are stored and playable but not transcribed or risk-screened. Alert delivery is email-only (via Resend if configured); real push/SMS is future work.
- **Rate limiting is in-memory and single-instance.** Login (10 tries per account per 15 min, 50 per IP), signup (10/hour per IP), `/api/summarize` (10/min per IP), and check-in creation (15/min per clinician) are all rate-limited via `rate-limit.js`. Counters live in process memory, so they reset on restart and aren't shared across instances — fine for one Render dyno, but swap in Redis/Postgres-backed counters before scaling out.
- **Canadian data residency** — the Anthropic API call in `server.js` has a placeholder comment where you'd add the region setting once confirmed available on your account (see `docs.claude.com` data-residency page, and the earlier Law 25 discussion). Also confirm your Postgres provider's region — Neon and Supabase both let you pick one.
- **Risk-classifier validation** — the summarization prompt includes a basic risk flag, but per `risk-classifier-eval.md`, this needs real clinical review and testing before it's trusted with real patients.

The frontend (`public/index.html`) is now wired to these endpoints: sign up or log in from the header, and the dashboard shows your real caseload — add patients (each gets a one-time invite code for the patient app), send check-ins (stored in Postgres), toggle per-patient AI consent, and view/delete stored data.

The patient-facing mobile app lives in `patient_app/` (Flutter) — see its README. Patients accept their therapist's invite code, record their own consent, and send check-ins that land on the therapist dashboard.

This backend is meant as a working starting point to build the rest of `backend-spec.md` onto — not a finished product.
