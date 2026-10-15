# Moving media to Cloudflare R2 (object storage)

Right now photos and voice memos are stored as bytes **inside Postgres**, which
is the expensive place to keep them. Cloudflare R2 is object storage built for
exactly this — far cheaper per GB, no egress fees — so the database stays small
and cheap and only holds a short reference to each file.

**Cost:** R2 is about **$0.015 / GB / month** with no egress charges. 10 GB of
photos ≈ **$0.15/month** on R2 vs. paying for a bigger Postgres plan.

This guide has two parts: **the steps you do in Cloudflare + Render** (1–4), and
**the code wiring I do once your credentials are set** (5–6). Nothing changes
for patients or clinicians — uploads and viewing work the same; the files just
live in R2 instead of the database.

---

## Part A — steps you do

### 1. Create a Cloudflare account and an R2 bucket
1. Sign up / log in at **dash.cloudflare.com**.
2. In the left sidebar, open **R2**. (You'll be asked to add a payment method;
   R2 has a generous free tier and is pay-as-you-go after that.)
3. Click **Create bucket**. Name it e.g. `between-media`. Region: **Automatic**.
4. Leave it **private** (do NOT enable public access — patient media must stay
   private; the app will serve it through its own authenticated endpoints).

### 2. Create an API token (credentials)
1. In **R2 → Overview**, click **Manage R2 API Tokens** → **Create API token**.
2. Permissions: **Object Read & Write**. Scope it to the **`between-media`**
   bucket only.
3. Create it, then copy these four values (you won't see the secret again):
   - **Access Key ID**
   - **Secret Access Key**
   - **Account ID** (shown on the R2 overview page)
   - The **S3 API endpoint**, which looks like
     `https://<ACCOUNT_ID>.r2.cloudflarestorage.com`

### 3. Add the credentials to Render (as secrets)
In the Render dashboard → your **between** web service → **Environment** → add:

| Key | Value |
|---|---|
| `R2_ACCOUNT_ID` | your Account ID |
| `R2_ACCESS_KEY_ID` | the Access Key ID |
| `R2_SECRET_ACCESS_KEY` | the Secret Access Key |
| `R2_BUCKET` | `between-media` |
| `R2_ENDPOINT` | `https://<ACCOUNT_ID>.r2.cloudflarestorage.com` |

Mark them as secret. Save — Render redeploys automatically.

### 4. Tell me they're set
Once those five variables exist on Render, let me know and I'll turn on the code
(Part B). Until they're set, the app keeps using the database exactly as now, so
there's no rush and nothing breaks.

---

## Part B — code wiring I do (once credentials exist)

This is behind a feature flag (the presence of the R2 env vars), with the
database as a fallback, so it's safe to roll out:

1. **Write path:** when a patient uploads a photo/voice memo, store the bytes in
   R2 under a key like `photos/<id>` instead of the `data` column. The DB row
   keeps only the key + mime (a few bytes).
2. **Read path:** the existing authed endpoints
   (`/api/patient/check-ins/:id/photo`, `/api/patients/:id/check-ins/:id/photo`)
   fetch the object from R2 and stream it — so access control is unchanged and
   the bucket stays private.
3. **Fallback:** rows that still have inline `data` (old uploads) keep working;
   new uploads go to R2.
4. **Implementation note:** R2 speaks the S3 API. I'll add a tiny AWS
   SigV4 signer using Node's built-in `crypto` (no heavyweight AWS SDK, keeping
   the project's minimal-dependency style), or add `@aws-sdk/client-s3` if you'd
   rather — your call.

### Migrating the media you already have
A one-time script (`scripts/migrate-media-to-r2.mjs`, which I'll write) walks the
`photo_uploads` / `audio_uploads` tables, uploads each `data` blob to R2, writes
back the key, and clears the `data` column. It's safe to run more than once
(skips rows already migrated) and can run in batches. After it finishes, the
database shrinks to almost nothing and the Storage card reflects it.

### Rollback
If anything looks off, remove the R2 env vars and redeploy — the app falls back
to storing and serving media from the database again. No data is lost because
migration only clears `data` after a successful R2 upload.

---

## tl;dr
1. Make an R2 bucket (private) → 2. create an API token → 3. put the 5 values in
Render → 4. ping me. Then I flip it on and migrate the existing files. Patients
and clinicians notice nothing; your Postgres stops growing and your bill stays
flat.
