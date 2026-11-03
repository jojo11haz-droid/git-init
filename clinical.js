// Pure, dependency-free helpers shared by the server and exercised directly by
// the unit tests (scripts/unit-tests.mjs). Keeping them here — rather than
// inline in server.js, which boots an HTTP server on import — means the
// health-critical logic (which discipline lens to use, how patient-entered
// input is sanitised) can be tested without a database or a running server.

// Which discipline-specific "signature read" lens applies, from the clinician's
// discipline and account type. Must stay in sync with the client-side
// signatureLensClient() in public/index.html.
export function signatureLens(discipline, accountType) {
  const d = discipline || '', a = accountType || '';
  if (['physio', 'kinesiology', 'osteo', 'occupational'].includes(d)) return 'trajectory';
  if (d === 'nutrition') return 'triggers';
  if (d === 'recovery' || a === 'mentor') return 'radar';
  if (d === 'sports') return 'readiness';
  if (d === 'fitness' || a === 'trainer') return 'drift';
  if (d === 'neuropsych') return 'cognitive';
  return 'thread';
}

export const SIGNATURE_LENS = {
  thread: { role: 'psychotherapist or counsellor',
    task: "Trace the one recurring thread that runs through $who's weeks — the theme they keep circling back to — and note any shift in how they relate to it.",
    read_hint: 'name the recurring thread and how it has moved over the weeks',
    points_hint: 'the thread, any paired triggers (e.g. sleep, conflict), and a shift worth opening with' },
  cognitive: { role: 'neuropsychology clinician',
    task: "Identify what precedes $who's hardest cognitive days (fatigue, fog, focus) and how mood and cognitive load move together.",
    read_hint: 'describe the conditions around their worst cognitive days',
    points_hint: 'load/fatigue patterns and anything trending the wrong way' },
  trajectory: { role: 'physical-rehabilitation clinician (e.g. physiotherapy)',
    task: "Read whether the most-affected body area is improving, plateauing or worsening, whether pain seems to be migrating to new areas, and what days or themes the flares cluster around. Note gently if anything looks worth a closer in-person look — never diagnose.",
    read_hint: 'the arc of the main area and any flare pattern',
    points_hint: 'most-affected area + direction, any migration, flare triggers, and a review nudge only if warranted' },
  triggers: { role: 'nutrition professional',
    task: "Surface, without any judgment, the patterns around $who's harder days — the moods, stress, sleep or themes that cravings or struggles cluster with. This is about the relationship with food, never calories or weight.",
    read_hint: 'the conditions cravings or struggles cluster with, non-judgmentally',
    points_hint: 'trigger patterns and a steadying bright spot if there is one' },
  radar: { role: 'recovery mentor or counsellor',
    task: "Watch for rising-risk stretches in $who's weeks — cravings, triggers, and HALT states (hungry, angry, lonely, tired) — and name steady stretches or milestones. Supportive, never alarmist.",
    read_hint: 'where risk rose or steadied over the weeks',
    points_hint: 'triggers, any HALT pattern, and a milestone or win to name' },
  readiness: { role: 'sports coach or clinician',
    task: "Combine $who's soreness/energy and mood into a simple read of whether they look ready, worth monitoring, or in need of a lighter load, and flag any drift toward burnout or overtraining.",
    read_hint: 'a ready / monitor / back-off read and why',
    points_hint: 'load-vs-readiness signals and any burnout drift' },
  drift: { role: 'personal trainer or coach',
    task: "Notice whether $who is staying engaged or quietly drifting (check-ins thinning, energy or motivation dropping), and what seems to help them stay on track.",
    read_hint: 'whether they are engaged or drifting, and why',
    points_hint: 'drift signals and what helps them re-engage' }
};

// A self-serve individual's own intentions: at most two trimmed, non-empty
// strings, each capped at 80 chars. Anything that isn't a string is dropped.
export function sanitizeGoals(raw) {
  const arr = Array.isArray(raw) ? raw : [];
  return arr
    .map(g => (typeof g === 'string' ? g.trim().slice(0, 80) : ''))
    .filter(Boolean)
    .slice(0, 2);
}

// Clamp a model's array of short bullet strings: strings only, trimmed,
// non-empty, capped in count and length. Shared by the AI read endpoints.
export function clampPoints(a, max = 4, maxLen = 240) {
  return Array.isArray(a)
    ? a.filter(x => typeof x === 'string' && x.trim()).slice(0, max).map(x => x.trim().slice(0, maxLen))
    : [];
}
