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

/// A couple of profession-specific prompts for the "answer questions" mode,
/// mirroring betweenpsych.com's guided check-in. Returned as plain localised
/// strings; the home screen stitches the answers back into one check-in and
/// sends it with inputMode:'questions'. Body disciplines split into physical
/// rehab (physio/kinesiology/osteo/occupational) vs. training (coach/trainer).
List<String> questionsFor(DisciplineProfile p, bool isFr) {
  List<String> q(String en, String fr) => isFr ? [fr] : [en];
  switch (p.kind) {
    case CheckInKind.body:
      final training = p.providerKey == 'coach' || p.providerKey == 'trainer';
      if (training) {
        return [
          ...q('How did your training go since last time?',
              'Comment se sont passés vos entraînements depuis la dernière fois ?'),
          ...q('What felt tough or held you back?',
              'Qu\'est-ce qui a été dur ou vous a freiné ?'),
        ];
      }
      return [
        ...q('How has the pain been since last time?',
            'Comment va la douleur depuis la dernière fois ?'),
        ...q('How did your exercises go?',
            'Comment se sont passés vos exercices ?'),
      ];
    case CheckInKind.nutrition:
      return [
        ...q('How did eating go since last time?',
            'Comment s\'est passée l\'alimentation depuis la dernière fois ?'),
        ...q('What felt good or worked well?',
            'Qu\'est-ce qui a fait du bien ou a bien fonctionné ?'),
      ];
    case CheckInKind.recovery:
      return [
        ...q('How have the cravings or urges been?',
            'Comment ont été les envies ou les pulsions ?'),
        ...q('What helped you stay on track?',
            'Qu\'est-ce qui vous a aidé à rester sur la bonne voie ?'),
      ];
    case CheckInKind.neuro:
      return [
        ...q('How has your focus and memory been?',
            'Comment ont été votre concentration et votre mémoire ?'),
        ...q('What was tiring or hard to manage?',
            'Qu\'est-ce qui a été fatigant ou difficile à gérer ?'),
      ];
    case CheckInKind.school:
      return [
        ...q('How have things been at school?',
            'Comment ça s\'est passé à l\'école ?'),
        ...q('What went well or helped?',
            'Qu\'est-ce qui a bien été ou vous a aidé ?'),
      ];
    case CheckInKind.mind:
      return [
        ...q('What stood out this week?',
            'Qu\'est-ce qui vous a marqué cette semaine ?'),
        ...q('What helped, even a little?',
            'Qu\'est-ce qui a aidé, même un peu ?'),
      ];
  }
}

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

/// The full set of categories, for the in-app preview switcher. Each key maps
/// to the profile a real patient of that discipline would get, so previewing
/// shows exactly what that person's check-in looks like.
const List<String> kPreviewCategories = [
  'solo',
  'therapist',
  'physio',
  'kinesiology',
  'osteo',
  'occupational',
  'sports',
  'trainer',
  'nutrition',
  'recovery',
  'neuro',
  'school',
];

/// Human label for a preview category key (localised).
String previewCategoryLabel(String key, bool isFr) {
  const en = {
    'solo': 'On your own',
    'therapist': 'Therapy',
    'physio': 'Physiotherapy',
    'kinesiology': 'Kinesiology',
    'osteo': 'Osteopathy',
    'occupational': 'Occupational therapy',
    'sports': 'Sport psychology',
    'trainer': 'Fitness training',
    'nutrition': 'Nutrition',
    'recovery': 'Addiction & recovery',
    'neuro': 'Neuropsychology',
    'school': 'School',
  };
  const fr = {
    'solo': 'Par vous-même',
    'therapist': 'Thérapie',
    'physio': 'Physiothérapie',
    'kinesiology': 'Kinésiologie',
    'osteo': 'Ostéopathie',
    'occupational': 'Ergothérapie',
    'sports': 'Psychologie du sport',
    'trainer': 'Entraînement',
    'nutrition': 'Nutrition',
    'recovery': 'Dépendance et rétablissement',
    'neuro': 'Neuropsychologie',
    'school': 'École',
  };
  return (isFr ? fr : en)[key] ?? key;
}

/// Profile for a preview category key (mirrors profileFor's mappings).
DisciplineProfile profileByKey(String key) {
  switch (key) {
    case 'therapist':
      return const DisciplineProfile(CheckInKind.mind, _mindThemes, 'therapist');
    case 'physio':
      return const DisciplineProfile(CheckInKind.body, _bodyThemes, 'physio');
    case 'kinesiology':
      return const DisciplineProfile(
          CheckInKind.body, _bodyThemes, 'kinesiologist');
    case 'osteo':
      return const DisciplineProfile(CheckInKind.body, _bodyThemes, 'osteopath');
    case 'occupational':
      return const DisciplineProfile(
          CheckInKind.body, _bodyThemes, 'occupational therapist');
    case 'sports':
      return const DisciplineProfile(CheckInKind.body, _bodyThemes, 'coach');
    case 'trainer':
      return const DisciplineProfile(CheckInKind.body, _bodyThemes, 'trainer');
    case 'nutrition':
      return const DisciplineProfile(
          CheckInKind.nutrition, _nutritionThemes, 'nutritionist');
    case 'recovery':
      return const DisciplineProfile(
          CheckInKind.recovery, _recoveryThemes, 'mentor');
    case 'neuro':
      return const DisciplineProfile(
          CheckInKind.neuro, _neuroThemes, 'neuropsychologist');
    case 'school':
      return const DisciplineProfile(CheckInKind.school, _schoolThemes, 'teacher');
    case 'solo':
    default:
      return const DisciplineProfile(CheckInKind.mind, _mindThemes, null);
  }
}
