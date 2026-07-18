# Between — Backend Spec (Database Schema & API Routes)

Companion to `spec.md`. This is detailed enough to hand to an engineer (or Claude Code) as a build spec. Written framework-agnostic — pick your stack, the shape stays the same.

---

## 1. Database schema

### `clinicians`
| column | type | notes |
|---|---|---|
| id | uuid, pk | |
| practice_id | uuid, fk → practices.id, nullable | null until they join/create a practice |
| name | text | |
| email | text, unique | |
| password_hash | text | |
| licence_number | text | professional order/licence number, captured at signup |
| licence_verified | boolean, default false | manual or automated check against provincial order registry |
| province | text | drives which privacy regime applies (Law 25 vs. others) |
| role | enum: clinician, practice_admin | |
| mfa_enabled | boolean, default false | |
| trial_ends_at | timestamp | null once converted to paid |
| plan | enum: trial, solo_monthly, solo_annual, group | |
| created_at, updated_at | timestamp | |

### `practices`
| column | type | notes |
|---|---|---|
| id | uuid, pk | |
| name | text | |
| billing_owner_id | uuid, fk → clinicians.id | who's billed for the group plan |
| created_at | timestamp | |

### `patients`
| column | type | notes |
|---|---|---|
| id | uuid, pk | |
| clinician_id | uuid, fk → clinicians.id | primary treating clinician |
| display_name | text | as entered by clinician, not necessarily legal name |
| invite_email | text, nullable | for the invite flow |
| invite_status | enum: pending, accepted, revoked | |
| ai_consent_enabled | boolean, default false | **defaults false — privacy-by-default (Law 25)** |
| consent_recorded_at | timestamp, nullable | |
| consent_version | text | which version of the consent copy they agreed to — needed for audit trail |
| created_at | timestamp | |

### `check_ins`
| column | type | notes |
|---|---|---|
| id | uuid, pk | |
| patient_id | uuid, fk → patients.id | |
| input_type | enum: text, audio | |
| raw_text | text, nullable | patient's typed or transcribed text |
| audio_object_key | text, nullable | pointer to encrypted object storage, not a public URL |
| mood_score | int (1–10), nullable | |
| manual_tags | text[] | patient-selected tags |
| submitted_at | timestamp | |
| deleted_at | timestamp, nullable | soft delete — honors the patient's delete-within-grace-period and Law 25 erasure right |

### `summaries`
| column | type | notes |
|---|---|---|
| id | uuid, pk | |
| check_in_id | uuid, fk → check_ins.id, unique | one summary per check-in |
| summary_text | text | AI-generated, neutral, in patient's own words |
| auto_tags | text[] | AI-extracted themes |
| risk_flag | boolean, default false | |
| model_version | text | e.g. `claude-sonnet-5-2026-06-30` — required for audit/explainability under Law 25 automated-decision rules |
| generated_at | timestamp | |
| patient_flagged_inaccurate | boolean, default false | patient's right to contest an automated output |

### `alerts`
| column | type | notes |
|---|---|---|
| id | uuid, pk | |
| check_in_id | uuid, fk → check_ins.id | |
| clinician_id | uuid, fk → clinicians.id | |
| delivered_at | timestamp, nullable | when the notification was actually sent |
| delivery_channel | enum: push, email, sms | |
| viewed_at | timestamp, nullable | **not** an acknowledgment/response — just "was it seen" for the clinician's own reference, no escalation logic attached (matches the no-response-required decision) |

### `audit_log`
| column | type | notes |
|---|---|---|
| id | uuid, pk | |
| actor_type | enum: patient, clinician, system | |
| actor_id | uuid | |
| action | text | e.g. `consent.updated`, `check_in.deleted`, `data.exported` |
| target_id | uuid | |
| metadata | jsonb | |
| created_at | timestamp | |
| *(retain 5+ years — matches Law 25 PIA record-keeping expectations)* | | |

---

## 2. API routes

Grouped by who calls them. All routes require auth except signup/login. All patient/clinician-data routes are scoped server-side to the authenticated user's own records — never trust a client-supplied patient_id or clinician_id without checking ownership.

### Auth & account
```
POST   /auth/signup                 clinician account creation (spec: licence_number required)
POST   /auth/login
POST   /auth/logout
POST   /auth/mfa/enroll
POST   /auth/password/reset-request
POST   /auth/password/reset-confirm
```

### Clinician / practice
```
GET    /clinician/me
PATCH  /clinician/me
GET    /practice/:id
POST   /practice                    create a practice (group plan)
POST   /practice/:id/invite-clinician
```

### Patients (clinician-facing)
```
GET    /patients                    caseload list for the authenticated clinician
POST   /patients                    add a patient, triggers invite_email
GET    /patients/:id
PATCH  /patients/:id
POST   /patients/:id/revoke         revoke access / offboard a patient
GET    /patients/:id/digest         computed "since last session" stats (§Digest below)
```

### Patient self-service (patient-facing, separate auth scope)
```
POST   /patient/consent             record ai_consent_enabled + consent_version + timestamp
GET    /patient/consent
GET    /patient/me/check-ins        patient's own history — satisfies Law 25 access right
DELETE /patient/me/check-ins        request deletion — satisfies Law 25 erasure right
```

### Check-ins
```
POST   /check-ins                   create a check-in (patient-facing)
  body: { patient_id, input_type, raw_text? , audio_upload_id?, mood_score, manual_tags[] }
  server-side: if ai_consent_enabled → call AI pipeline (§3) synchronously or via queue
               else → skip AI, summary_text = raw_text (or null), no profiling

GET    /check-ins/:id                clinician or owning patient only
DELETE /check-ins/:id                soft delete, honors grace period

POST   /check-ins/audio-upload-url   returns a short-lived signed upload URL (never accept raw audio through the main API)
```

### Summaries & trends
```
GET    /patients/:id/summaries       list, paginated
GET    /patients/:id/trends/mood     time series for chart
GET    /patients/:id/trends/themes   tag-frequency aggregation for pie chart
POST   /summaries/:id/flag-inaccurate
```

### Alerts (real-time, no-response-required per product decision)
```
GET    /alerts                       clinician's alert feed
POST   /alerts/:id/mark-viewed       optional, for the clinician's own tracking only
```
Delivery itself (push/email/SMS) is a background job triggered on `check_ins` insert when `summaries.risk_flag = true`, not a route the client calls directly.

---

## 3. AI pipeline (server-side only)

Never call the AI API from the browser — the prototype does this only because it's a demo. In production:

```
check-in submitted
  → if !ai_consent_enabled: skip straight to storage, no AI call
  → transcribe (if audio)
  → call Claude API server-side, inference_geo = "ca" (or account's confirmed Canadian region)
      - Prompt returns: { summary, auto_tags[], risk_flag }
      - Store model_version alongside the output
  → risk_flag = true:
      - immediately return crisis-resources payload to the patient client (independent of alert delivery)
      - enqueue alert delivery job (push/email/SMS per clinician's channel prefs)
  → persist summary, update trend aggregates
```

Keep the risk-screening check as a **separate, more conservative prompt/pass** from the general summarizer, per the spec — don't let one call serve both jobs.

---

## 4. Open build-order recommendation
1. Auth + clinician signup (licence field, no verification logic yet — stub it)
2. Patient invite + consent recording (this blocks everything downstream, build it early not late)
3. Check-in submission without AI (text only, mood, tags) — get the core loop working
4. AI pipeline behind the consent flag
5. Risk-flagging + alert delivery
6. Trend aggregation endpoints + dashboard
7. Billing/trial-to-paid conversion
8. Audio upload + transcription
9. Licence verification automation, MFA, audit-log surfacing for compliance exports
