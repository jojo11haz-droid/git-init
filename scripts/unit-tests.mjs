// Unit tests for the pure, health-critical helpers in clinical.js — the logic
// that decides which discipline lens a clinician gets and that sanitises
// patient-entered input before it reaches the database or the AI. No server,
// no database: just the functions. Exits non-zero on the first failure so CI
// turns red.

import { signatureLens, SIGNATURE_LENS, sanitizeGoals, clampPoints, canonicalTags, tagField, LEGACY_TAG_ALIAS } from '../clinical.js';
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

if (failures) { console.error(`\nUnit tests: ${failures} failing.`); process.exit(1); }
console.log('\nAll unit tests passed.');
