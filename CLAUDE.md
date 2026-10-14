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
  not compile-verified here. Hand-check it (bracket balance, theme tokens, call
  sites) and tell the user to run `flutter analyze` before shipping.

## Branch
Develop on `claude/between-clinician-auth-vvl9zb`. Don't open a PR unless asked.
