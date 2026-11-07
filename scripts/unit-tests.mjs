// Unit tests for the pure, health-critical helpers in clinical.js — the logic
// that decides which discipline lens a clinician gets and that sanitises
// patient-entered input before it reaches the database or the AI. No server,
// no database: just the functions. Exits non-zero on the first failure so CI
// turns red.

import { signatureLens, SIGNATURE_LENS, sanitizeGoals, clampPoints, canonicalTags, tagField, LEGACY_TAG_ALIAS, needsAttention, sanitizeExercisesDone, sanitizeExercise, programKind, noteFormat, timeSavedSummary, TIME_SAVED_MINUTES, programContext, sanitizeSuggestion, areaLabel } from '../clinical.js';
import { readFileSync } from 'fs';

let failures = 0;
function eq(actual, expected, msg) {
  const a = JSON.stringify(actual), e = JSON.stringify(expected);
  if (a === e) { console.log('  ✓ ' + msg); }
  else { console.error(`  ✗ ${msg}\n      expected ${e}\n      got      ${a}`); failures++; }
}

console.log('signatureLens — discipline → lens');
eq(signatureLens('physio'), 'trajectory', 'physio → trajectory');
eq(signatureLens('kinesiology'), 'trajectory', 'kinesiology → trajectory');
eq(signatureLens('osteo'), 'trajectory', 'osteo → trajectory');
eq(signatureLens('occupational'), 'trajectory', 'occupational → trajectory');
eq(signatureLens('nutrition'), 'triggers', 'nutrition → triggers');
eq(signatureLens('recovery'), 'radar', 'recovery → radar');
eq(signatureLens('', 'mentor'), 'radar', 'mentor account → radar');
eq(signatureLens('sports'), 'readiness', 'sports → readiness');
eq(signatureLens('fitness'), 'drift', 'fitness → drift');
eq(signatureLens('', 'trainer'), 'drift', 'trainer account → drift');
eq(signatureLens('neuropsych'), 'cognitive', 'neuropsych → cognitive');
eq(signatureLens('therapy'), 'thread', 'therapy → thread');
eq(signatureLens('', 'therapist'), 'thread', 'therapist account → thread');
eq(signatureLens(null, null), 'thread', 'unknown → thread (default)');

console.log('signatureLens — every lens it returns has a spec');
for (const d of ['physio', 'nutrition', 'recovery', 'sports', 'fitness', 'neuropsych', 'therapy', '']) {
  const lens = signatureLens(d, '');
  const spec = SIGNATURE_LENS[lens];
  eq(!!(spec && spec.role && spec.task && spec.read_hint && spec.points_hint), true, `lens "${lens}" (from "${d}") has a full spec`);
}

console.log('sanitizeGoals — trims, caps, drops junk');
eq(sanitizeGoals(['  sleep by 11  ', 'walk daily']), ['sleep by 11', 'walk daily'], 'trims whitespace');
eq(sanitizeGoals(['a', 'b', 'c']), ['a', 'b'], 'keeps at most two');
eq(sanitizeGoals(['', '   ', 'real']), ['real'], 'drops empty / whitespace-only');
eq(sanitizeGoals(['keep', 123, null, { x: 1 }, 'also']), ['keep', 'also'], 'drops non-strings');
eq(sanitizeGoals('x'.repeat(100))[0] === undefined, true, 'non-array input → empty');
eq(sanitizeGoals(['x'.repeat(100)])[0].length, 80, 'caps each goal at 80 chars');
eq(sanitizeGoals(null), [], 'null → []');
eq(sanitizeGoals(undefined), [], 'undefined → []');

console.log('clampPoints — strings only, bounded count and length');
eq(clampPoints(['a', 'b', 'c', 'd', 'e']), ['a', 'b', 'c', 'd'], 'caps at four by default');
eq(clampPoints(['ok', '', '  ', 42, null, 'two']), ['ok', 'two'], 'drops empty and non-strings');
eq(clampPoints('not an array'), [], 'non-array → []');
eq(clampPoints(['y'.repeat(300)])[0].length, 240, 'caps each at 240 chars');
eq(clampPoints(['a', 'b', 'c'], 2), ['a', 'b'], 'respects a custom max');

console.log('canonicalTags — old relabelled topics read back as what was tapped');
eq(tagField({ accountType: 'coach', discipline: 'nutrition' }), 'nutrition', 'nutrition coach → nutrition');
eq(tagField({ accountType: 'mentor' }), 'recovery', 'mentor → recovery');
eq(tagField({ accountType: 'school' }), 'schools', 'school → schools');
eq(tagField({ accountType: 'coach', discipline: 'physio' }), null, 'physio → no remapping');
eq(tagField({ accountType: 'therapist' }), null, 'therapist → no remapping');
eq(tagField(), null, 'no context → no remapping');
eq(canonicalTags(['Panic', 'Anger', 'Sleep'], 'nutrition'), ['Hydration', 'Habits', 'Sleep'], 'nutrition: Panic → Hydration, Anger → Habits');
eq(canonicalTags(['Work', 'Meals'], 'nutrition'), ['Meals'], 'old and new spelling of a topic merge');
eq(canonicalTags(['Work', 'Craving', 'Family'], 'recovery'), ['Cravings', 'Triggers'], 'recovery: Work/Craving → Cravings, Family → Triggers');
eq(canonicalTags(['Work', 'Family', 'Craving'], 'schools'), ['School', 'Home life', 'Craving'], 'schools: Work → School, Family → Home life');
eq(canonicalTags(['Panic', 'Work'], null), ['Panic', 'Work'], 'other fields keep their tags as saved');
eq(canonicalTags(null, 'nutrition'), [], 'null → []');
eq(canonicalTags(['', 'Sleep', 'Sleep'], 'nutrition'), ['Sleep'], 'drops empties and duplicates');
// The client keeps its own copy of the alias table; they must not drift.
{
  const html = readFileSync(new URL('../public/index.html', import.meta.url), 'utf8');
  const m = html.match(/const LEGACY_TAG_ALIAS = (\{[\s\S]*?\n  \});/);
  let client = null;
  try { client = m && Function('return ' + m[1])(); } catch (e) {}
  eq(client, LEGACY_TAG_ALIAS, 'index.html LEGACY_TAG_ALIAS matches clinical.js');
}
// …and so does the patient app's (a Dart map literal, read as JSON).
{
  const dart = readFileSync(new URL('../patient_app/lib/app_state.dart', import.meta.url), 'utf8');
  const m = dart.match(/kLegacyTagAlias = (\{[\s\S]*?\n\});/);
  let app = null;
  try { app = m && JSON.parse(m[1].replace(/'/g, '"').replace(/,(\s*[}\]])/g, '$1')); } catch (e) {}
  eq(app, LEGACY_TAG_ALIAS, 'patient app kLegacyTagAlias matches clinical.js');
}

console.log('needsAttention — who needs the clinician today');
{
  const now = Date.parse('2026-11-10T12:00:00Z');
  const ago = (d) => new Date(now - d * 86400000).toISOString();
  const pts = [
    { id: 'a', display_name: 'Ann', check_in_count: 5, last_check_in_at: ago(1) },                       // pain up 3
    { id: 'b', display_name: 'Ben', check_in_count: 4, last_check_in_at: ago(1), has_recent_risk: true }, // risk
    { id: 'c', display_name: 'Cy', check_in_count: 3, last_check_in_at: ago(10) },                        // quiet
    { id: 'd', display_name: 'Di', check_in_count: 3, last_check_in_at: ago(1) },                         // steady → none
    { id: 'e', display_name: 'Ed', check_in_count: 2, last_check_in_at: ago(1), has_recent_nerve_flag: true },
    { id: 'f', display_name: 'Fi', check_in_count: 0, last_check_in_at: null },                           // never checked in → none
    { id: 'g', display_name: 'Gus', check_in_count: 9, last_check_in_at: ago(30), left_at: ago(5) }       // left → skipped
  ];
  const scores = { a: [7, 4, 4, 4], b: [5, 5], c: [4, 4], d: [5, 5, 6, 5], e: [3, 3] };
  const pain = needsAttention(pts, scores, { pain: true, now });
  eq(pain.map(x => x.id), ['b', 'e', 'a', 'c'], 'pain: order risk → nerve → worse → quiet; steady/new/left excluded');
  eq(pain.find(x => x.id === 'a').reasons[0].en, 'Pain up 3 points', 'pain: rise of 3 over baseline reads as worse');
  eq(pain.find(x => x.id === 'c').reasons[0].en, 'Quiet for 10 days', 'quiet after 7+ days');
  const mood = needsAttention(pts, { a: [3, 6, 6, 6] }, { pain: false, now });
  eq(mood.find(x => x.id === 'a').reasons[0].en, 'Down 3 points', 'mood: drop of 3 reads as worse');
  eq(needsAttention([{ id: 'h', display_name: 'H', check_in_count: 1, last_check_in_at: ago(0) }], { h: [9] }, { pain: true, now })[0].reasons[0].en, 'High pain (9/10)', 'pain: single high score flagged');
  eq(needsAttention([{ id: 'h', display_name: 'H', check_in_count: 1, last_check_in_at: ago(0) }], { h: [9] }, { pain: false, now }), [], 'mood: 9/10 is good, not flagged');
}

console.log('exercise sanitizers');
eq(sanitizeExercisesDone(['x', 'y', 'x', 'evil', 5], ['x', 'y']), ['x', 'y'], 'ticks limited to the program, de-duplicated');
eq(sanitizeExercisesDone('x', ['x']), null, 'non-array ignored');
eq(sanitizeExercisesDone([], ['x']), null, 'empty → null');
eq(sanitizeExercise({ name: '  Wall  squat ', description: 'Back on wall.', dosage: '3x10' }), { name: 'Wall squat', description: 'Back on wall.', dosage: '3x10' }, 'exercise trimmed');
eq(sanitizeExercise({ name: '   ' }), null, 'nameless exercise rejected');
eq(sanitizeExercise({ name: 'X'.repeat(200) }).name.length, 80, 'name capped at 80');

console.log('programKind / noteFormat — per profession');
eq(programKind({ accountType: 'coach', discipline: 'physio' }), 'exercise', 'physio → exercises');
eq(programKind({ accountType: 'coach', discipline: 'sports' }), 'exercise', 'sports coach → exercises');
eq(programKind({ accountType: 'trainer' }), 'exercise', 'trainer → exercises');
eq(programKind({ accountType: 'therapist' }), 'practice', 'psychotherapist → practices');
eq(programKind({ accountType: 'coach', discipline: 'neuropsych' }), 'practice', 'neuropsych → practices');
eq(programKind({ accountType: 'coach', discipline: 'nutrition' }), 'habit', 'nutrition → habits');
eq(programKind({ accountType: 'mentor' }), 'recovery', 'recovery mentor → daily practices');
eq(programKind({ accountType: 'school' }), 'school', 'school → strategies');
eq(noteFormat({ accountType: 'therapist' }), 'dap', 'psychotherapist → DAP note');
eq(noteFormat({ accountType: 'mentor' }), 'dap', 'recovery → DAP note');
eq(noteFormat({ accountType: 'coach', discipline: 'neuropsych' }), 'dap', 'neuropsych → DAP note');
eq(noteFormat({ accountType: 'coach', discipline: 'physio' }), 'soap', 'physio → SOAP note');
eq(noteFormat({ accountType: 'coach', discipline: 'nutrition' }), 'soap', 'nutrition → SOAP note');
eq(noteFormat({ accountType: 'trainer' }), 'soap', 'trainer → SOAP note');

console.log('timeSavedSummary — the time-saved counter');
eq(timeSavedSummary({ note: 3, summary: 10, prep: 0, bogus: 9 }), { items: [{ kind: 'note', count: 3, minutes: 18 }, { kind: 'summary', count: 10, minutes: 10 }], totalMinutes: 28, label: '28 min' }, 'counts → minutes; zero and unknown kinds dropped');
eq(timeSavedSummary({ note: 10, program_item: 5 }).label, '1 h 10 min', 'hours + minutes label');
eq(timeSavedSummary({ note: 10 }).label, '1 h', 'whole hours label');
eq(timeSavedSummary({}).totalMinutes, 0, 'nothing yet → 0');
eq(Object.values(TIME_SAVED_MINUTES).every(m => m > 0 && m <= 15), true, 'every estimate is conservative (1–15 min)');
eq(timeSavedSummary({ scribe: 2 }).totalMinutes, 24, 'a recorded session written up counts 12 min');

// --- program context (AI program suggestions) ---
{
  const NOW = Date.UTC(2026, 10, 7);
  const day = n => new Date(NOW - n * 86400000).toISOString();
  const knee = [
    { submitted_at: day(10), mood_score: 3, pain_map: { 'front:l_knee_cap': 3 } },
    { submitted_at: day(6), mood_score: 4, pain_map: { 'front:l_knee_cap': 4 } },
    { submitted_at: day(3), mood_score: 6, pain_map: { 'front:l_knee_cap': 6 }, pain_sensations: { 'front:l_knee_cap': 'sharp' }, exercises_done: ['e1'] },
    { submitted_at: day(1), mood_score: 6, pain_map: { 'front:l_knee_cap': 6, 'back:lower_back': 2 } },
    { submitted_at: day(40), mood_score: 9, pain_map: { 'front:r_wrist': 9 } }   // older than 4 weeks: ignored
  ];
  const c = programContext(knee, [{ id: 'e1', name: 'Wall squat', dosage: '3 x 10' }], { pain: true, now: NOW });
  eq(c.checkIns, 4, 'program context: only the last 4 weeks');
  eq(c.trend, 'worse', 'program context: pain rising reads as worse');
  eq(c.hint, 'Left kneecap, about 6/10, getting worse (sharp)', 'program context: goal hint from the most-marked area');
  eq(JSON.stringify(c.caution), JSON.stringify({ reasons: ['sharp pain that is getting worse'], areas: ['Left kneecap'] }), 'program context: sharp + worsening raises a caution for that area only');
  eq(/Wall squat \(3 x 10\) — ticked in 1 of 4/.test(c.text), true, 'program context: adherence in the AI summary');
  const numb = programContext([{ submitted_at: day(1), mood_score: 3, pain_map: { 'front:r_wrist': 3 }, pain_sensations: { 'front:r_wrist': 'numb' } }], [], { pain: true, now: NOW });
  eq(numb.caution && numb.caution.reasons[0], 'tingling or numbness', 'program context: tingling/numbness always raises a caution');
  const sev = programContext([{ submitted_at: day(2), mood_score: 8 }], [], { pain: true, now: NOW });
  eq(!!sev.caution, true, 'program context: 8/10 this week raises a caution');
  const mood = programContext([{ submitted_at: day(5), mood_score: 3 }, { submitted_at: day(3), mood_score: 5 }, { submitted_at: day(1), mood_score: 7 }], [], { pain: false, now: NOW });
  eq(mood.trend + '|' + (mood.caution === null) + '|' + mood.hint, 'better|true|', 'program context: mood rising is better, no caution or body hint');
  eq(areaLabel('back:lower_back'), 'Lower back', 'area label: plain anatomy');
  const sg = sanitizeSuggestion({ name: '  Step-downs ', description: 'Slow.', dosage: 'x'.repeat(200), pain_rule: 'Up to 3/10.', why: 'Stairs.', harder: 'Higher step', easier: 'Lower step', junk: 1 });
  eq(sg.name + '|' + sg.dosage.length + '|' + sg.pain_rule + '|' + ('junk' in sg), 'Step-downs|120|Up to 3/10.|false', 'suggestion: trimmed, capped, extra keys dropped');
}

if (failures) { console.error(`\nUnit tests: ${failures} failing.`); process.exit(1); }
console.log('\nAll unit tests passed.');
