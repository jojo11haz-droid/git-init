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

// Check-in topics per field. Before each field had its own topic set, the
// recovery, nutrition and school check-ins showed the therapy topics with new
// labels but SAVED the underlying word, e.g. a nutrition client tapping
// "Hydration" saved "Panic", and that reached the clinician's timeline and the
// AI prompts. Old check-ins are read back as the topic the person actually
// tapped, for the field they checked in under. Must stay in sync with
// LEGACY_TAG_ALIAS in public/index.html.
export const LEGACY_TAG_ALIAS = {
  recovery: { Work: 'Cravings', Craving: 'Cravings', Family: 'Triggers' },
  nutrition: { Work: 'Meals', Conflict: 'Digestion', Panic: 'Hydration', Family: 'Energy', Money: 'Snacking', Loneliness: 'Stress', Anger: 'Habits', Craving: 'Cravings' },
  schools: { Work: 'School', Family: 'Home life' }
};

// The field whose legacy topic labels apply, from the clinician's account
// type and discipline (null = no remapping).
export function tagField({ accountType, discipline } = {}) {
  if (accountType === 'mentor') return 'recovery';
  if (accountType === 'school') return 'schools';
  if (accountType === 'coach' && discipline === 'nutrition') return 'nutrition';
  return null;
}

// A check-in's manual tags as the person meant them: legacy words mapped for
// the field, duplicates dropped, order kept.
export function canonicalTags(tags, field) {
  const alias = LEGACY_TAG_ALIAS[field] || {};
  const out = [];
  for (const t of Array.isArray(tags) ? tags : []) {
    if (!t) continue;
    const v = alias[t] || t;
    if (!out.includes(v)) out.push(v);
  }
  return out;
}

// --- Hands-off "needs you" list ---
// Which patients actually need the clinician today, and why — the only list a
// busy clinician has to look at. Pure: works from listPatients() rows plus each
// patient's last few scores (newest first). Pain disciplines read the score
// the other way (higher = worse). Order: safety first, then nerve signs, then
// worsening, then gone quiet.
export const PAIN_DISCIPLINES = ['physio', 'kinesiology', 'osteo', 'occupational'];
export function needsAttention(patients, scoresByPatient, { pain = false, now = Date.now(), quietDays = 7 } = {}) {
  const out = [];
  for (const p of patients || []) {
    if (!p || p.left_at) continue;
    const reasons = [];
    if (p.has_recent_risk) reasons.push({ code: 'risk', en: 'Flagged for review', fr: 'Signalé pour révision' });
    if (p.has_recent_nerve_flag) reasons.push({ code: 'nerve', en: 'Reported tingling or numbness', fr: 'A signalé des picotements ou un engourdissement' });
    const s = ((scoresByPatient || {})[p.id] || []).filter(v => typeof v === 'number');
    if (s.length) {
      const latest = s[0];
      const prev = s.slice(1);
      const base = prev.length ? prev.reduce((a, b) => a + b, 0) / prev.length : null;
      const worse = base == null ? 0 : (pain ? latest - base : base - latest);
      if (worse >= 2) {
        const pts = Math.round(worse);
        reasons.push(pain
          ? { code: 'worse', en: `Pain up ${pts} points`, fr: `Douleur en hausse de ${pts} points` }
          : { code: 'worse', en: `Down ${pts} points`, fr: `En baisse de ${pts} points` });
      } else if (pain ? latest >= 8 : latest <= 3) {
        reasons.push(pain
          ? { code: 'high', en: `High pain (${latest}/10)`, fr: `Douleur élevée (${latest}/10)` }
          : { code: 'high', en: `Low score (${latest}/10)`, fr: `Score bas (${latest}/10)` });
      }
    }
    if ((p.check_in_count || 0) > 0 && p.last_check_in_at) {
      const days = Math.floor((now - new Date(p.last_check_in_at).getTime()) / 86400000);
      if (days >= quietDays) reasons.push({ code: 'quiet', en: `Quiet for ${days} days`, fr: `Silencieux depuis ${days} jours` });
    }
    if (reasons.length) out.push({ id: p.id, name: p.display_name || '', reasons });
  }
  const rank = { risk: 0, nerve: 1, worse: 2, high: 3, quiet: 4 };
  out.sort((a, b) => (rank[a.reasons[0].code] - rank[b.reasons[0].code]) || a.name.localeCompare(b.name));
  return out;
}

// Exercises a check-in may tick: only ids from the patient's active program,
// de-duplicated, capped.
export function sanitizeExercisesDone(raw, validIds) {
  if (!Array.isArray(raw)) return null;
  const ok = new Set(validIds || []);
  const out = [];
  for (const v of raw) { if (typeof v === 'string' && ok.has(v) && !out.includes(v)) out.push(v); if (out.length >= 30) break; }
  return out.length ? out : null;
}

// Clean one clinician-entered (or AI-suggested) exercise.
export function sanitizeExercise(raw) {
  if (!raw || typeof raw !== 'object') return null;
  const clip = (v, n) => (typeof v === 'string' ? v.replace(/\s+/g, ' ').trim().slice(0, n) : '');
  const name = clip(raw.name, 80);
  if (!name) return null;
  return { name, description: clip(raw.description, 400) || null, dosage: clip(raw.dosage, 80) || null };
}
