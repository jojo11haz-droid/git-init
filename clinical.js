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

// "Did you do your exercises?" when the program lives in another app.
export const EXERCISE_STATUSES = ['yes', 'some', 'no'];
export function sanitizeExerciseStatus(v) { return EXERCISE_STATUSES.includes(v) ? v : null; }
// --- AI consent for check-in data ------------------------------------------
// The check-ins an AI may read for this client: none unless the client has AI
// summaries on now, and of those only check-ins sent while AI was on. Older
// rows (before the per-check-in flag existed) count only if the AI processed
// them at the time, or they carry no words at all (a score or body map only):
// a check-in typed while AI was off has its words stored as-is, so it stays out.
export function aiCheckInsFor(patient, checkIns) {
  if (!patient || !patient.ai_consent_enabled) return [];
  return (checkIns || []).filter(c => c.ai_consent === true || (c.ai_consent == null && (!!c.model_version || !c.raw_text)));
}

// --- Plan → check-ins ------------------------------------------------------
// Up to 3 short yes / partly / no questions the professional sets from their
// plan; asked in every check-in until they replace them.
export const PLAN_ANSWERS = ['yes', 'some', 'no'];
export function sanitizePlanQuestions(input) {
  const out = [];
  for (const it of Array.isArray(input) ? input : []) {
    const raw = typeof it === 'string' ? it : (it && typeof it.q === 'string' ? it.q : '');
    const q = raw.replace(/[\u0000-\u001F\u007F<>]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 140);
    if (!q || out.some(o => o.q.toLowerCase() === q.toLowerCase())) continue;
    const id = it && typeof it.id === 'string' && /^[a-z0-9]{4,12}$/.test(it.id) ? it.id : Math.random().toString(36).slice(2, 10).padEnd(8, '0');
    out.push({ id, q });
    if (out.length >= 3) break;
  }
  return out;
}
// The client's answers, kept only for questions currently set; the question
// text is stored with the answer so it still reads right after a change.
export function sanitizePlanAnswers(answers, questions) {
  const qs = Array.isArray(questions) ? questions : [];
  const out = [];
  for (const a of Array.isArray(answers) ? answers : []) {
    if (!a || typeof a.id !== 'string' || !PLAN_ANSWERS.includes(a.a)) continue;
    const q = qs.find(x => x && x.id === a.id);
    if (!q || out.some(o => o.id === a.id)) continue;
    out.push({ id: q.id, q: q.q, a: a.a });
  }
  return out;
}

// --- "Since last visit" ----------------------------------------------------
// Numbers for the chart note, worked out here rather than by an AI, so they
// are exact and can be shown even for a client who has AI off.
const areaName = key => areaLabel(key).toLowerCase();
export function visitStats({ checkIns, exercises, since, pain, lang, now }) {
  const fr = lang === 'fr';
  const t = now ? new Date(now).getTime() : Date.now();
  const startMs = since ? new Date(since).getTime() : t - 28 * 86400000;
  const fmtDay = d => new Date(d).toLocaleDateString(fr ? 'fr-CA' : 'en-CA', { month: 'short', day: 'numeric', timeZone: 'UTC' });
  const head = since ? (fr ? `Depuis la dernière visite (${fmtDay(since)})` : `Since last visit (${fmtDay(since)})`) : (fr ? '4 dernières semaines' : 'Last 4 weeks');
  const all = (checkIns || []).filter(c => c && c.submitted_at);
  const win = all.filter(c => new Date(c.submitted_at).getTime() > startMs).sort((a, b) => new Date(a.submitted_at) - new Date(b.submitted_at));
  const lines = [];
  if (!win.length) return { head, lines: [fr ? 'Aucun suivi pendant cette période.' : 'No check-ins in this period.'], count: 0 };
  lines.push(fr ? `${win.length} suivi${win.length > 1 ? 's' : ''}` : `${win.length} check-in${win.length > 1 ? 's' : ''}`);
  const word = pain ? (fr ? 'douleur' : 'pain') : (fr ? 'humeur' : 'mood');
  const sc = win.filter(c => c.mood_score != null).map(c => Number(c.mood_score));
  if (sc.length === 1) lines.push(`${word} ${sc[0]}/10`);
  else if (sc.length > 1) lines.push(`${word} ${sc[0]} → ${sc[sc.length - 1]}/10 (${fr ? 'écart' : 'range'} ${Math.min(...sc)}–${Math.max(...sc)})`);
  // Body areas marked, and which are new compared with the 4 weeks before.
  const keysIn = list => { const s = new Set(); list.forEach(c => { if (c.pain_map && typeof c.pain_map === 'object') Object.keys(c.pain_map).forEach(k => s.add(k)); }); return s; };
  const inWin = keysIn(win);
  if (inWin.size) {
    const before = keysIn(all.filter(c => { const x = new Date(c.submitted_at).getTime(); return x <= startMs && x > startMs - 28 * 86400000; }));
    const fresh = [...inWin].filter(k => !before.has(k));
    if (fr) lines.push(`${inWin.size} zone${inWin.size > 1 ? 's' : ''} marquée${inWin.size > 1 ? 's' : ''}${fresh.length ? ` (dont ${fresh.length} nouvelle${fresh.length > 1 ? 's' : ''})` : ''}`);
    else lines.push(`areas: ${[...inWin].slice(0, 5).map(k => areaName(k)).join(', ')}${fresh.length ? ` (new: ${fresh.slice(0, 3).map(k => areaName(k)).join(', ')})` : ''}`);
  }
  // Program completion: ticked in Between, or "did it?" for another app.
  const active = (exercises || []).filter(e => !e.archived_at);
  if (active.length) {
    const any = win.filter(c => Array.isArray(c.exercises_done) && c.exercises_done.length).length;
    const per = active.slice(0, 4).map(e => `${e.name} ${win.filter(c => Array.isArray(c.exercises_done) && c.exercises_done.includes(e.id)).length}/${win.length}`).join(', ');
    lines.push(fr ? `programme fait dans ${any} suivi${any > 1 ? 's' : ''} sur ${win.length} (${per})` : `program done in ${any} of ${win.length} check-ins (${per})`);
  }
  const ext = win.filter(c => c.exercise_status);
  if (ext.length) {
    const n = v => ext.filter(c => c.exercise_status === v).length;
    lines.push(fr ? `exercices (autre application) : oui ${n('yes')} · en partie ${n('some')} · non ${n('no')}` : `exercises (other app): yes ${n('yes')} · partly ${n('some')} · no ${n('no')}`);
  }
  // Answers to the professional's plan questions.
  const byQ = new Map();
  win.forEach(c => (Array.isArray(c.plan_answers) ? c.plan_answers : []).forEach(a => {
    if (!a || !a.id) return;
    const r = byQ.get(a.id) || { q: a.q, yes: 0, some: 0, no: 0 };
    if (PLAN_ANSWERS.includes(a.a)) r[a.a]++;
    byQ.set(a.id, r);
  }));
  byQ.forEach(r => lines.push(fr ? `« ${r.q} » : oui ${r.yes} · en partie ${r.some} · non ${r.no}` : `"${r.q}": yes ${r.yes} · partly ${r.some} · no ${r.no}`));
  return { head, lines, count: win.length };
}

// The name of that app, as the professional typed it (e.g. "Wibbi").
export function sanitizeAppName(v) {
  return typeof v === 'string' ? v.replace(/[\u0000-\u001F\u007F<>]/g, '').trim().slice(0, 40) : '';
}

// Clean one clinician-entered (or AI-suggested) exercise.
export function sanitizeExercise(raw) {
  if (!raw || typeof raw !== 'object') return null;
  const clip = (v, n) => (typeof v === 'string' ? v.replace(/\s+/g, ' ').trim().slice(0, n) : '');
  const name = clip(raw.name, 80);
  if (!name) return null;
  return { name, description: clip(raw.description, 400) || null, dosage: clip(raw.dosage, 120) || null };
}

// What the "between-session program" is called and holds, per profession:
// exercises for physical/training fields, practices (homework) for mental
// health, habits for nutrition, daily practices for recovery, strategies for
// schools. Drives labels, the AI suggestions and the chart note's plan line.
export function programKind({ accountType, discipline } = {}) {
  const d = discipline || '', a = accountType || '';
  if (PAIN_DISCIPLINES.includes(d) || d === 'sports' || a === 'trainer') return 'exercise';
  if (d === 'nutrition') return 'habit';
  if (a === 'mentor') return 'recovery';
  if (a === 'school') return 'school';
  return 'practice'; // psychotherapy, neuropsychology, anything else
}

// Chart-note format per profession: DAP (Data / Assessment / Plan) for the
// mental-health fields that chart that way, SOAP for physical and coaching.
export function noteFormat({ accountType, discipline } = {}) {
  const d = discipline || '', a = accountType || '';
  if (a === 'therapist' || a === 'mentor' || d === 'neuropsych' || (a === '' && d === '')) return 'dap';
  // Dietitians chart in ADIME (the Nutrition Care Process).
  if (d === 'nutrition') return 'adime';
  return 'soap';
}

// --- Time saved ---
// Conservative estimates (minutes) of the clinician work each Between action
// replaces, used for the "time saved" counter. Kept deliberately low so the
// number is believable; the dashboard labels it as an estimate.
export const TIME_SAVED_MINUTES = {
  note: 6,          // drafting a chart note from between-visit check-ins
  prep: 4,          // reviewing check-ins to prepare for a session
  encourage: 3,     // writing a between-session message
  digest: 5,        // a caseload summary instead of opening each file
  needs_email: 5,   // the morning "who needs me" triage
  program_item: 2,  // writing up one exercise / practice with its how-to
  program_review: 4, // reviewing a program against adherence and progress
  report: 15,       // a progress report / letter drafted from the history
  scribe: 12,       // a full session written up from the recording
  summary: 1        // a check-in already condensed instead of read raw
};

// Turn usage counts into the counter: rows with minutes, a total, and a
// friendly "1 h 25 min" string. Unknown kinds and zero counts are dropped.
export function timeSavedSummary(counts) {
  const items = [];
  let total = 0;
  for (const [kind, mins] of Object.entries(TIME_SAVED_MINUTES)) {
    const n = Math.max(0, Math.floor(Number((counts || {})[kind]) || 0));
    if (!n) continue;
    items.push({ kind, count: n, minutes: n * mins });
    total += n * mins;
  }
  const h = Math.floor(total / 60), m = total % 60;
  const label = h ? (m ? `${h} h ${m} min` : `${h} h`) : `${m} min`;
  return { items, totalMinutes: total, label };
}

// --- Program context: what the check-ins say, for AI program suggestions ---
// A plain read of the last few weeks (no AI): where it hurts, how much and
// which way it's going, how it feels, what they've been doing. Gives the AI
// its context, pre-fills the goal box, and raises a safety caution (tingling
// or numbness, severe pain, sharp pain getting worse) so the suggestions hold
// back on loading that area.
const SIDE = { l: 'left', r: 'right' };
const SENSATION_WORDS = { ache: 'aching', tight: 'tight', stiff: 'stiff', sharp: 'sharp', numb: 'tingling or numbness', throb: 'throbbing' };
export function areaLabel(key) {
  const part = String(key || '').split(':')[1] || String(key || '');
  const bits = part.split('_');
  const side = SIDE[bits[0]] && bits.length > 1 ? SIDE[bits.shift()] + ' ' : '';
  const words = bits.join(' ').replace(/\bknee cap\b/, 'kneecap').trim();
  const s = (side + words).trim();
  return s ? s.charAt(0).toUpperCase() + s.slice(1) : '';
}
export function programContext(checkIns, exercises, { pain = false, days = 28, now = Date.now() } = {}) {
  const cutoff = now - days * 86400000, weekAgo = now - 7 * 86400000;
  const recent = (checkIns || []).filter(c => c && c.submitted_at && new Date(c.submitted_at).getTime() >= cutoff)
    .slice().sort((a, b) => new Date(a.submitted_at) - new Date(b.submitted_at)); // oldest first
  const scores = recent.filter(c => Number.isFinite(c.mood_score)).map(c => c.mood_score);
  const avg = a => a.length ? Math.round(a.reduce((x, y) => x + y, 0) / a.length * 10) / 10 : null;
  const firstAvg = avg(scores.slice(0, 2)), lastAvg = avg(scores.slice(-2));
  const delta = (scores.length >= 3 && firstAvg != null && lastAvg != null) ? Math.round((lastAvg - firstAvg) * 10) / 10 : 0;
  // For pain, up is worse; for everything else, up is better.
  const trend = !delta || Math.abs(delta) < 1 ? 'steady' : ((pain ? delta > 0 : delta < 0) ? 'worse' : 'better');
  const areas = {};
  const sens = new Set();
  let severe = false;
  for (const c of recent) {
    const t = new Date(c.submitted_at).getTime();
    if (c.pain_map && typeof c.pain_map === 'object') {
      for (const [k, v] of Object.entries(c.pain_map)) {
        const lv = Number(v); if (!Number.isFinite(lv)) continue;
        const a = areas[k] || (areas[k] = { key: k, label: areaLabel(k), n: 0, max: 0, last: lv, sens: new Set() });
        a.n++; a.max = Math.max(a.max, lv); a.last = lv;
        if (pain && lv >= 8 && t >= weekAgo) { severe = true; a.severe = true; }
      }
    }
    if (c.pain_sensations && typeof c.pain_sensations === 'object') {
      for (const [k, v] of Object.entries(c.pain_sensations)) {
        if (!SENSATION_WORDS[v]) continue;
        sens.add(v); if (areas[k]) areas[k].sens.add(v);
      }
    }
    if (pain && Number.isFinite(c.mood_score) && c.mood_score >= 8 && t >= weekAgo) severe = true;
  }
  const top = Object.values(areas).sort((a, b) => b.n - a.n || b.max - a.max).slice(0, 3);
  const numb = sens.has('numb');
  const sharpWorse = sens.has('sharp') && trend === 'worse';
  const caution = pain && (numb || severe || sharpWorse)
    ? { reasons: [numb && 'tingling or numbness', severe && 'pain at 8/10 or more this week', sharpWorse && 'sharp pain that is getting worse'].filter(Boolean),
        // Only the areas behind the caution (all marked areas if it came from the overall score).
        areas: (function(){ const f = Object.values(areas).filter(a => a.sens.has('numb') || a.severe || (sharpWorse && a.sens.has('sharp'))).map(a => a.label); return f.length ? f : top.map(a => a.label); })() }
    : null;
  const exById = {}; for (const e of exercises || []) exById[e.id] = e;
  const adherence = (exercises || []).filter(e => !e.archived_at).map(e => ({
    name: e.name, dosage: e.dosage || '',
    done: recent.filter(c => Array.isArray(c.exercises_done) && c.exercises_done.includes(e.id)).length, of: recent.length
  }));
  // A short goal line the clinician can send as-is.
  let hint = '';
  if (pain && top.length) {
    const a = top[0];
    hint = `${a.label}, about ${Math.round(a.last)}/10` + (trend === 'worse' ? ', getting worse' : trend === 'better' ? ', easing' : '')
      + (a.sens.size ? ` (${[...a.sens].map(x => SENSATION_WORDS[x]).join(', ')})` : '');
  }
  const lines = [];
  if (recent.length) lines.push(`${recent.length} check-in(s) in the last ${days} days.`);
  if (scores.length) lines.push(`${pain ? 'Pain' : 'Score'} (1-10): from ${scores[0]} to ${scores[scores.length - 1]}, average ${avg(scores)}, ${pain ? 'max ' + Math.max(...scores) + ', ' : ''}trend ${trend}.`);
  for (const a of top) lines.push(`Area: ${a.label} — marked ${a.n} time(s), worst ${a.max}/10, latest ${a.last}/10${a.sens.size ? ', feels ' + [...a.sens].map(x => SENSATION_WORDS[x]).join(', ') : ''}.`);
  for (const ad of adherence) lines.push(`Already assigned: ${ad.name}${ad.dosage ? ' (' + ad.dosage + ')' : ''} — ticked in ${ad.done} of ${ad.of} check-ins.`);
  const said = recent.filter(c => c.summary_text).slice(-5).map(c => `- ${String(c.summary_text).trim().slice(0, 220)}`);
  if (said.length) lines.push('What they reported (most recent last):\n' + said.join('\n'));
  return { hint, caution, trend, checkIns: recent.length, text: lines.join('\n') };
}

// One AI program suggestion, cleaned: the client-facing parts (name, how-to,
// dose, pain rule) and the clinician-only parts (why it fits, harder, easier).
export function sanitizeSuggestion(raw) {
  const base = sanitizeExercise(raw);
  if (!base) return null;
  const clip = (v, n) => (typeof v === 'string' ? v.replace(/\s+/g, ' ').trim().slice(0, n) : '');
  return { ...base, dosage: clip(raw.dosage, 120) || null, pain_rule: clip(raw.pain_rule, 200) || null,
    why: clip(raw.why, 240) || null, harder: clip(raw.harder, 140) || null, easier: clip(raw.easier, 140) || null };
}
