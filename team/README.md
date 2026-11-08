# Between's AI team

A handful of scheduled Claude sessions, each with one job. They run early in
the morning, Montreal time, and notify the owner's phone when they finish.

| Role | When | What it does | Where its work goes |
|---|---|---|---|
| QA tester | Every night, 4:47 | Runs the tests and `scripts/qa-audit.mjs` (every field, EN/FR, desktop + phone), spot-checks recent changes, fixes small bugs | `qa/YYYY-MM-DD` branches |
| Ops / release manager | Every day, 5:23 | Checks the live site, runs the tests on dev and main, lists branches waiting, checks the held promo code isn't on main | Phone notification only |
| Sales outreach | Tuesdays, 5:37 | Finds 10 Quebec clinics with a published business email, writes personalised outreach drafts | `team-notes/sales/` on the `team/notes` branch |
| Marketing | Wednesdays, 5:41 | Writes 5 Instagram post drafts (rotating professions, EN/FR) and one bigger idea | `team-notes/marketing/` on `team/notes` |
| Weekly report | Mondays, 6:07 | One page: shipped, waiting on you, problems, top 3 suggestions | `team-notes/reports/` on `team/notes` |
| Support inbox | Daily, 6:13 and 16:13 | Drafts replies to Between emails in Gmail | Gmail drafts (set up in claude.ai, see `support-inbox-routine.md`) |

## Rules every role follows

- Never deploy: nothing is pushed to `main` or merged into the dev branch.
  The owner reviews and deploys.
- Never send, post or publish: emails and posts are drafts.
- Never read patient/client data and never sign in to the live site.
- Never touch licence verification.
- Never bring back the held promo feature.

## Managing them

The schedules live under "scheduled tasks" (Routines) in claude.ai. Pause or
delete any of them there, or ask Claude in a session to change one.
