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

| Route | What it does |
|---|---|
| `POST /api/summarize` | Stateless — summarize arbitrary text, nothing saved. Used by the demo prototype. |
| `POST /api/patients` | Create a patient (`{ displayName }`) |
| `GET /api/patients` | List all patients |
| `POST /api/patients/:id/consent` | Set `ai_consent_enabled` (`{ enabled: true/false }`) |
| `POST /api/patients/:id/check-ins` | Create a check-in (`{ text, moodScore, manualTags }`) — only calls the AI if that patient has consent enabled |
| `GET /api/patients/:id/check-ins` | List a patient's check-in history |
| `DELETE /api/patients/:id/check-ins/:checkInId` | Soft-delete one check-in |
| `DELETE /api/patients/:id/check-ins` | Soft-delete all of a patient's check-ins (the "request deletion" button) |

**Note:** none of these routes have auth yet (see below). They work for testing, but are open to anyone with the URL right now.

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

- **No auth yet — this is now the most urgent gap.** Check-ins persist now, which means anyone with your deployed URL can read or write any patient's data via the API routes above. Do not point this at real people until the auth system in `backend-spec.md` (clinician login, patient-scoped access) is in place.
- **No rate limiting** — add something like `express-rate-limit` before this is public, so `/api/summarize` and the check-in routes can't be abused to run up your API bill.
- **Canadian data residency** — the Anthropic API call in `server.js` has a placeholder comment where you'd add the region setting once confirmed available on your account (see `docs.claude.com` data-residency page, and the earlier Law 25 discussion). Also confirm your Postgres provider's region — Neon and Supabase both let you pick one.
- **Risk-classifier validation** — the summarization prompt includes a basic risk flag, but per `risk-classifier-eval.md`, this needs real clinical review and testing before it's trusted with real patients.
- **The frontend (`public/index.html`) still uses in-memory demo data** for the caseload/timeline view — it isn't wired to these new `/api/patients` endpoints yet. That's the natural next step once you're ready.

This backend is meant as a working starting point to build the rest of `backend-spec.md` onto — not a finished product.
