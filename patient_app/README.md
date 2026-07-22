# Between — patient app (Flutter)

The patient-facing mobile app. Warm, calm, minimal — the softer sibling of the
therapist web dashboard. It talks to the same Node/Postgres backend over HTTP
and can only ever see the signed-in patient's own data: there is no caseload
concept anywhere in this codebase.

## How a patient gets in

1. The therapist adds them in the web dashboard and gets a one-time **invite
   code** (shown after adding the patient, and again under "View patient data
   & AI settings").
2. In this app: **"I have an invite from my therapist"** → enter the code plus
   an email and password. That becomes their login; the code stops working.
3. Consent screen (gates everything): plain-language disclosure, AI toggle
   **off by default**, explicit checkbox. Nothing can be sent before this.

## Screens

- **Check-in** (home): greeting, free-text or a voice memo first, mood + tags
  as a light optional step after. Crisis line quietly at the bottom. Voice
  memos upload through a short-lived signed URL (never the JSON API) and are
  playable by the therapist on the web dashboard.
- **Sent**: confirmation; if the server flagged risk language, crisis
  resources (988/911) appear immediately — independent of any therapist alert.
  15-minute undo, except for risk-flagged check-ins.
- **My history**: everything on file, AI summaries labeled, each flaggable as
  "not accurate".
- **My data & settings**: AI consent toggle (turning it on re-confirms),
  request deletion of history, logout.

## Run / build

The API base URL is compiled in via `--dart-define` (defaults to
`http://localhost:3000`):

```bash
cd patient_app
flutter pub get

# run against a local backend
flutter run --dart-define=API_BASE=http://localhost:3000

# build for your deployed backend
flutter build apk --dart-define=API_BASE=https://your-app.onrender.com
flutter build web --dart-define=API_BASE=https://your-app.onrender.com
```

The web build is fully self-contained (CanvasKit and the Roboto font are
bundled — no CDN requests), so `build/web/` can be hosted anywhere static,
or used to smoke-test the app in a browser. The backend allows cross-origin
requests on the `/api/patient` scope only (Bearer tokens, no cookies), so the
app works from any origin.

## Not built yet (deliberately)

- **Transcription** — voice memos are stored and playable, but not
  transcribed, summarized, or risk-screened until a speech-to-text provider
  is added server-side. The check-in shows "Voice memo (no transcript yet)".
- Push notifications, offline queueing.

Forgot password? It's therapist-mediated: the clinician hits "Reset app
access" on their dashboard, which issues a fresh invite code and revokes the
old login — history and consent stay intact. No patient email infrastructure
needed.

The auth token is kept in `flutter_secure_storage` (Keychain/Keystore on
mobile). Sessions last 30 days; logout revokes server-side.
