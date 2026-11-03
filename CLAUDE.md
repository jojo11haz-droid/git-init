# Between — project notes for Claude

## Golden rule: website changes must also land in the mobile app
Whenever a user-facing feature is added or changed on the **website**, make the
matching change in the **Flutter patient app** in the same piece of work —
don't ship the web side alone. The user expects the app and site to stay in
lockstep. If a feature genuinely has no place in the app (e.g. a clinician-only
view — the app is patient-facing), say so explicitly rather than skipping it
silently.

The two surfaces:
- **Website / backend**: `public/index.html` (SPA: marketing site + clinician
  & patient dashboards), `server.js`, `db.js`, `stripe.js`, `email.js`.
- **Mobile**: `patient_app/` (Flutter, patient-facing only). Key files:
  `lib/screens/home_screen.dart` (check-in composer), `lib/body_map.dart`,
  `lib/app_state.dart` (API + models), `lib/api.dart`, `lib/strings.dart`
  (EN/FR `S` class).

When a change touches a check-in's data (new field on a check-in), wire it the
whole way: `db.js` column + `createCheckIn`, `server.js` sanitizer + the two
check-in endpoints (`/api/patients/:id/check-ins` and `/api/patient/check-ins`)
+ serializers, web `public/index.html`, and the app (`sendCheckIn` payload +
`CheckIn` getter + the relevant screens).

## Verifying
- Backend/web: `npm test`, and for DB work use the ephemeral Postgres cluster
  (user `pgtest`, socket `/home/pgtest/pg2`, port 5434, db `dashdemo`); it gets
  reclaimed on idle — restart with
  `pg_ctl -D /home/pgtest/pg2 -o "-k /home/pgtest/pg2 -p 5434" start`.
  Run app code against it with `DATABASE_SSL=disable`.
- **Mobile has no Dart/Flutter toolchain in this environment**, so app code is
  not compile-verified locally. Hand-check it (bracket balance, theme tokens,
  call sites) — then push: CI (`.github/workflows/ci.yml`, `app` job) runs
  `flutter analyze` on every push to a `claude/**` branch, so it's the real
  compile-check. Watch that run (GitHub Actions tools) and fix what it flags.
  Note `flutter analyze` fails on **any** issue, including info-level lints.

## Branch
Develop on `claude/between-clinician-auth-vvl9zb`. Don't open a PR unless asked.

## Deploying to production
Production serves from `main` (Render). Deploy by cherry-picking the SPECIFIC
feature commit(s) onto a throwaway branch off `origin/main`, never by merging
dev — dev carries undeployed work. Before pushing to main: `git diff --stat
origin/main HEAD`, confirm the promo grep below adds 0, `node --check`, and
`npm test`.

## Held feature — do NOT deploy the promo code path
There's a signup promo feature (markers: `PROMO_CODES`, `applyPromoCode`,
`free_until`, `btwSuPromo`) built for a Kinatex partner deal and **held off
`main`**. It lives on the dev branch only. It is env-gated — a clean no-op
unless `PROMO_CODES` is set — but a valid code also AUTO-APPROVES a clinician
(skips the manual licence review), so it stays off production until deliberately
enabled. Because it sits on dev, cherry-picks of nearby lines sometimes conflict
in the FR-dictionary / signup areas; resolve by keeping your change and dropping
the promo lines. Always verify before every push to main:
`git diff origin/main HEAD | grep -E '^\+' | grep -c 'PROMO_CODES\|btwSuPromo\|free_until\|applyPromoCode'` → must be `0`.
