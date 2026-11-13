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
  & patient dashboards), `server.js`, `db.js`, `stripe.js`, `email.js`, `errors_fr.js`.
- **Mobile**: `patient_app/` (Flutter, patient-facing only). Key files:
  `lib/screens/home_screen.dart` (check-in composer), `lib/body_map.dart`,
  `lib/app_state.dart` (API + models), `lib/api.dart`, `lib/strings.dart`
  (EN/FR `S` class).

When a change touches a check-in's data (new field on a check-in), wire it the
whole way: `db.js` column + `createCheckIn`, `server.js` sanitizer + the two
check-in endpoints (`/api/patients/:id/check-ins` and `/api/patient/check-ins`)
+ serializers, web `public/index.html`, and the app (`sendCheckIn` payload +
`CheckIn` getter + the relevant screens).

## Error messages in French
Server error text is written in English in `server.js`. `errors_fr.js` holds the
French for each one, and its `localizeErrors` middleware swaps it in whenever a
request carries `X-Btw-Lang: fr` (the website adds that header to every `/api/`
call while the page is in French; the app adds it in `lib/api.dart`). Adding or
rewording an `error:` string, or a rate limiter `message:`, means adding its
French to `errors_fr.js` too: the unit tests fail if one is missing.

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
  CI pins Flutter **3.47.9** (`flutter-version` in `ci.yml`). Flutter 3.50
  deprecates `package:flutter/material.dart` in favour of `package:material_ui`,
  which fails the check in every file; moving the app to it is a deliberate,
  separate change (bump the pin and the imports together).

## Branch
Develop on `claude/between-clinician-auth-vvl9zb`. Don't open a PR unless asked.

## Deploying to production
Production serves from `main` (Render). Deploy by cherry-picking the SPECIFIC
feature commit(s) onto a throwaway branch off `origin/main`, never by merging
dev — dev carries undeployed work. Before pushing to main: `git diff --stat
origin/main HEAD`, confirm the promo grep below adds 0, `node --check`, and
`npm test`.

## Held feature — the promo code path (removed from dev, in history only)
A signup promo feature (markers: `PROMO_CODES`, `applyPromoCode`, `free_until`,
`btwSuPromo`) was built for a Kinatex partner deal — free-for-N-months clinic
codes that also AUTO-APPROVE the account (skipping manual licence review). It
was **removed from the dev branch** (commit `b3b4ee1`) and now lives only in git
history (feature commits `a06bc14`, `848ca1a`, `5b9ba8a`). Do not re-introduce or
deploy it without deliberate intent — the auto-approve bypass is why it stays
off production. As lingering hygiene, before any push to main confirm it adds
nothing: `git diff origin/main HEAD | grep -E '^\+' | grep -c 'PROMO_CODES\|btwSuPromo\|free_until\|applyPromoCode'` → `0`.
