import 'app_state.dart';

/// What the check-in is flavoured for, derived from the patient's clinician.
/// Stage 1 uses this to pick the theme chips and the "send to …" wording per
/// category, mirroring betweenpsych.com. (The body pain map comes in stage 2.)
enum CheckInKind { mind, body, nutrition, recovery, neuro, school }

class DisciplineProfile {
  const DisciplineProfile(this.kind, this.themes, this.providerKey);

  final CheckInKind kind;
  final List<String> themes;

  /// Key for the person this check-in goes to (localised in strings), or null
  /// for a solo account with no clinician.
  final String? providerKey;

  bool get isBody => kind == CheckInKind.body;
}

const _mindThemes = [
  'Sleep', 'Work', 'Mood', 'Anxiety', 'Relationships', 'Family', 'Win', 'Social',
];
const _bodyThemes = [
  'Pain', 'Soreness', 'Mobility', 'Exercises', 'Sleep', 'Energy', 'Training', 'Win',
];
const _nutritionThemes = [
  'Energy', 'Cravings', 'Meals', 'Sleep', 'Digestion', 'Mood', 'Hydration', 'Win',
];
const _recoveryThemes = [
  'Cravings', 'Triggers', 'Mood', 'Sleep', 'Support', 'Stress', 'Social', 'Win',
];
const _neuroThemes = [
  'Focus', 'Memory', 'Fatigue', 'Mood', 'Sleep', 'Overwhelm', 'Headache', 'Win',
];
const _schoolThemes = [
  'Focus', 'Mood', 'Friends', 'Sleep', 'Stress', 'Energy', 'Win',
];

DisciplineProfile profileFor(Patient p) {
  final acct = p.clinicianAccountType; // therapist|coach|mentor|school|trainer|null
  final disc = p.clinicianDiscipline; // physio|kinesiology|osteo|occupational|neuropsych|nutrition|sports|null

  // Solo / self-serve: no clinician behind them.
  if (acct == null || acct.isEmpty) {
    return const DisciplineProfile(CheckInKind.mind, _mindThemes, null);
  }

  switch (acct) {
    case 'coach':
      switch (disc) {
        case 'nutrition':
          return const DisciplineProfile(
              CheckInKind.nutrition, _nutritionThemes, 'nutritionist');
        case 'neuropsych':
          return const DisciplineProfile(
              CheckInKind.neuro, _neuroThemes, 'neuropsychologist');
        case 'kinesiology':
          return const DisciplineProfile(
              CheckInKind.body, _bodyThemes, 'kinesiologist');
        case 'osteo':
          return const DisciplineProfile(
              CheckInKind.body, _bodyThemes, 'osteopath');
        case 'occupational':
          return const DisciplineProfile(
              CheckInKind.body, _bodyThemes, 'occupational therapist');
        case 'sports':
          return const DisciplineProfile(CheckInKind.body, _bodyThemes, 'coach');
        default: // physio
          return const DisciplineProfile(CheckInKind.body, _bodyThemes, 'physio');
      }
    case 'trainer':
      return const DisciplineProfile(CheckInKind.body, _bodyThemes, 'trainer');
    case 'mentor':
      return const DisciplineProfile(
          CheckInKind.recovery, _recoveryThemes, 'mentor');
    case 'school':
      return const DisciplineProfile(CheckInKind.school, _schoolThemes, 'teacher');
    case 'therapist':
    default:
      return const DisciplineProfile(CheckInKind.mind, _mindThemes, 'therapist');
  }
}
