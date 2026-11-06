import 'package:flutter/material.dart';

import 'theme.dart';

/// Tap-where-it-hurts body map for physical disciplines — mirrors the website.
/// Produces a pain map of { "view:region": level } with level 1..10, using the
/// same region ids and coordinate space (100 x 198) as betweenpsych.com, so the
/// clinician dashboard renders it identically.

// 0 = none, 1 = mild (green) … 10 = worst (red). Index 0 is transparent.
const _fill = <Color>[
  Colors.transparent,
  Color(0xFF7FB84F), Color(0xFF9CC63E), Color(0xFFC9D630), Color(0xFFEAC72E),
  Color(0xFFF0AE33), Color(0xFFEF8E38), Color(0xFFEA6F3B), Color(0xFFDE5238),
  Color(0xFFCF3B33), Color(0xFFC0392B),
];
const _bodyGrey = Color(0xFFD7DBE3);

/// How a sore spot feels, in words a patient actually uses — mirrors the web.
/// Each maps to the tissue an osteo/physio would think of, so the clinician
/// gets a muscle vs joint vs nerve read without the patient self-diagnosing.
class BtwSensation {
  const BtwSensation(this.code, this.en, this.fr, this.cat, {this.flag = false});
  final String code, en, fr, cat;
  final bool flag; // true for tingling/numb — the one worth a look before next visit
}

const btwSensations = <BtwSensation>[
  BtwSensation('ache', 'Aching', 'Courbatures', 'muscle'),
  BtwSensation('tight', 'Tight', 'Tendu', 'muscle'),
  BtwSensation('stiff', 'Stiff / locking', 'Raide / bloqué', 'joint'),
  BtwSensation('sharp', 'Sharp / shooting', 'Vif / fulgurant', 'nerve'),
  BtwSensation('numb', 'Tingling / numb', 'Picotements / engourdi', 'nerve',
      flag: true),
  BtwSensation('throb', 'Throbbing / hot', 'Lancinant / chaud', 'inflam'),
];

/// Localised label for a sensation code, or '' if unknown.
String sensationLabel(String code, bool isFr) {
  for (final s in btwSensations) {
    if (s.code == code) return isFr ? s.fr : s.en;
  }
  return '';
}

/// "Sore spots: lower back (7/10, sharp / shooting), left shin (5/10)." — shared
/// by the interactive map and the read-only detail view so both read the same.
String painSummary(Map<String, int> map, Map<String, String>? sens, bool isFr,
    {int max = 4}) {
  if (map.isEmpty) {
    return isFr ? 'Aucune zone douloureuse.' : 'No sore spots yet.';
  }
  final parts = map.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  final names = parts.take(max).map((e) {
    final label = regionLabel(e.key, isFr);
    final sc = sens?[e.key];
    final sl = (sc != null && sc.isNotEmpty)
        ? ', ${sensationLabel(sc, isFr).toLowerCase()}'
        : '';
    return '$label (${e.value}/10$sl)';
  }).join(', ');
  final more = parts.length > max ? ' …' : '';
  return (isFr ? 'Zones sensibles : ' : 'Sore spots: ') + names + more;
}

class _Region {
  const _Region(this.id, this.en, this.fr, this.x, this.y, this.w, this.h,
      {this.ellipse = false});
  final String id;
  final String en, fr;
  final double x, y, w, h;
  final bool ellipse;

  Rect get rect => Rect.fromLTWH(x, y, w, h);
  bool contains(Offset p) {
    if (!ellipse) return rect.contains(p);
    final cx = x + w / 2, cy = y + h / 2, rx = w / 2, ry = h / 2;
    final dx = (p.dx - cx) / rx, dy = (p.dy - cy) / ry;
    return dx * dx + dy * dy <= 1;
  }
}

// Ellipse from centre/radius → bounding rect.
_Region _ell(String id, String en, String fr, double cx, double cy, double rx,
        double ry) =>
    _Region(id, en, fr, cx - rx, cy - ry, rx * 2, ry * 2, ellipse: true);

// Arms/shoulders/hands/knees/ankles are shared by both views.
final _shared = <_Region>[
  _Region('l_arm', 'left arm', 'bras gauche', 21, 39, 11, 28),
  _Region('r_arm', 'right arm', 'bras droit', 68, 39, 11, 28),
  _Region('l_fore', 'left forearm', 'avant-bras gauche', 19, 65, 10, 31),
  _Region('r_fore', 'right forearm', 'avant-bras droit', 71, 65, 10, 31),
  _ell('l_shoulder', 'left shoulder', 'épaule gauche', 30, 35, 7.5, 6.5),
  _ell('r_shoulder', 'right shoulder', 'épaule droite', 70, 35, 7.5, 6.5),
  _ell('l_hand', 'left hand', 'main gauche', 24, 100, 5.5, 6.5),
  _ell('r_hand', 'right hand', 'main droite', 76, 100, 5.5, 6.5),
  _ell('l_knee', 'left knee', 'genou gauche', 42.5, 133, 6.5, 5.5),
  _ell('r_knee', 'right knee', 'genou droit', 57.5, 133, 6.5, 5.5),
  _ell('l_ankle', 'left ankle', 'cheville gauche', 42, 179, 5, 5),
  _ell('r_ankle', 'right ankle', 'cheville droite', 58, 179, 5, 5),
];

// Large regions first; smaller/overlapping ones (the shared extremities) go
// last so a tap on them wins over the big torso regions underneath.
final _front = <_Region>[
  _Region('neck', 'neck', 'cou', 45, 24, 10, 9),
  _Region('chest', 'chest', 'poitrine', 30, 32, 40, 20),
  _Region('abs', 'abs and core', 'abdominaux et tronc', 39, 50, 22, 22),
  _Region('hips', 'hips and groin', 'hanches et aine', 35, 71, 30, 15),
  _Region('l_thigh', 'left thigh', 'cuisse gauche', 36, 89, 13, 44),
  _Region('r_thigh', 'right thigh', 'cuisse droite', 51, 89, 13, 44),
  _Region('l_shin', 'left shin', 'tibia gauche', 38, 138, 10, 42),
  _Region('r_shin', 'right shin', 'tibia droit', 52, 138, 10, 42),
  _Region('l_foot', 'left foot', 'pied gauche', 36, 180, 12, 13),
  _Region('r_foot', 'right foot', 'pied droit', 52, 180, 12, 13),
  ..._shared,
];
final _back = <_Region>[
  _Region('neck', 'neck and nape', 'cou et nuque', 45, 24, 10, 9),
  _Region('upper_back', 'upper back', 'haut du dos', 30, 32, 40, 22),
  _Region('lower_back', 'lower back', 'bas du dos', 37, 52, 26, 20),
  _Region('glutes', 'glutes', 'fessiers', 35, 71, 30, 16),
  _Region('l_thigh', 'left hamstring', 'ischio-jambier gauche', 36, 89, 13, 44),
  _Region('r_thigh', 'right hamstring', 'ischio-jambier droit', 51, 89, 13, 44),
  _Region('l_calf', 'left calf', 'mollet gauche', 38, 138, 10, 42),
  _Region('r_calf', 'right calf', 'mollet droit', 52, 138, 10, 42),
  _Region('l_heel', 'left heel', 'talon gauche', 36, 180, 12, 13),
  _Region('r_heel', 'right heel', 'talon droit', 52, 180, 12, 13),
  ..._shared,
];

// The grey silhouette drawn under the regions.
final _baseRects = <Rect>[
  Rect.fromLTWH(45, 24, 10, 9), Rect.fromLTWH(28, 30, 44, 24),
  Rect.fromLTWH(35, 50, 30, 24), Rect.fromLTWH(34, 70, 32, 18),
  Rect.fromLTWH(21, 33, 11, 36), Rect.fromLTWH(68, 33, 11, 36),
  Rect.fromLTWH(19, 64, 10, 32), Rect.fromLTWH(71, 64, 10, 32),
  Rect.fromLTWH(35, 86, 14, 48), Rect.fromLTWH(51, 86, 14, 48),
  Rect.fromLTWH(37, 136, 11, 48), Rect.fromLTWH(52, 136, 11, 48),
  Rect.fromLTWH(36, 180, 12, 13), Rect.fromLTWH(52, 180, 12, 13),
];
final _baseOvals = <Rect>[
  Rect.fromCircle(center: const Offset(24, 100), radius: 6), // hands
  Rect.fromCircle(center: const Offset(76, 100), radius: 6),
];

// ---------------------------------------------------------------------------
// Zoomed close-ups for the main rehab areas — mirrors BTW_DETAIL on the web.
// Tapping a knee, shoulder, ankle… opens a drawing of just that part so the
// patient can pin the exact spot ("inner side of the left knee"). A sub-spot
// is stored as "view:part_sub" (e.g. "front:l_knee_cap") next to the plain
// whole-part key. Close-up space is 100 x 100; sided parts are drawn as the
// LEFT part (midline to the right, so "inner" sits right) and mirrored for
// the right part.

class _Detail {
  const _Detail({
    required this.sided,
    required this.outline,
    required this.art,
    required this.views,
  });
  final bool sided;
  final String outline; // SVG path (M/L/C/Z) of the part's silhouette
  final Map<String, String> art; // view -> light anatomy lines
  final Map<String, List<_Region>> views; // view -> tappable sub-spots
}

final _detail = <String, _Detail>{
  'knee': _Detail(
    sided: true,
    outline: 'M30 0 L70 0 C71 20 72 32 70 48 C69 60 66 72 64 100 L36 100 C34 72 31 60 30 48 C28 32 29 20 30 0 Z',
    art: {
      'front': 'M50 33 C57 33 61 39 61 45 C61 52 57 57 50 57 C43 57 39 52 39 45 C39 39 43 33 50 33 Z M46 58 L47 68 M54 58 L53 68 M40 4 C42 18 44 26 45 33 M60 4 C58 18 56 26 55 33',
      'back': 'M36 8 C38 24 40 34 42 40 M64 8 C62 24 60 34 58 40 M38 48 C46 52 54 52 62 48 M42 60 C40 72 40 86 44 98 M58 60 C60 72 60 86 56 98',
    },
    views: {
      'front': [
        _Region('above', 'above the kneecap', 'au-dessus de la rotule', 34, 6, 32, 20),
        _ell('cap', 'kneecap', 'rotule', 50, 45, 13, 14),
        _Region('below', 'below the kneecap', 'sous la rotule', 38, 64, 24, 20),
        _Region('outer', 'outer side', 'côté externe', 30, 30, 9, 34),
        _Region('inner', 'inner side', 'côté interne', 61, 30, 9, 34),
      ],
      'back': [
        _ell('hollow', 'centre', 'centre', 50, 46, 12, 16),
        _Region('outer', 'outer side', 'côté externe', 30, 28, 10, 36),
        _Region('inner', 'inner side', 'côté interne', 60, 28, 10, 36),
        _Region('calf', 'top of the calf', 'haut du mollet', 38, 70, 24, 24),
      ],
    },
  ),
  'shoulder': _Detail(
    sided: true,
    outline: 'M100 22 C80 20 60 17 42 21 C26 25 14 40 14 60 L14 100 L44 100 L46 78 C56 86 72 90 100 90 Z',
    art: {
      'front': 'M18 52 C24 36 40 30 56 33 C60 44 56 62 44 74 M58 37 C70 34 84 38 98 36 M64 46 C72 52 82 56 96 56',
      'back': 'M18 52 C24 36 40 30 56 33 C60 44 56 62 44 74 M60 44 L88 40 M62 40 L88 44 L82 80 Z',
    },
    views: {
      'front': [
        _Region('top', 'top', 'dessus', 30, 22, 32, 12),
        _ell('front', 'front', 'avant', 54, 54, 11, 12),
        _ell('outer', 'outer side', 'côté externe', 24, 58, 9, 15),
        _Region('collar', 'collarbone', 'clavicule', 68, 30, 28, 8),
        _ell('armpit', 'armpit', 'aisselle', 54, 80, 9, 6),
      ],
      'back': [
        _Region('top', 'top', 'dessus', 30, 22, 32, 12),
        _ell('back', 'back', 'arrière', 40, 56, 12, 13),
        _ell('blade', 'shoulder blade', 'omoplate', 77, 60, 11, 17),
        _ell('outer', 'outer side', 'côté externe', 22, 58, 8, 15),
      ],
    },
  ),
  'neck': _Detail(
    sided: false,
    outline: 'M30 0 L70 0 C68 30 68 60 74 100 L26 100 C32 60 32 30 30 0 Z',
    art: {
      'front': 'M36 10 L48 94 M64 10 L52 94 M46 44 C48 41 52 41 54 44',
      'back': 'M28 6 C40 14 60 14 72 6 M50 22 L50 30 M50 38 L50 46 M50 54 L50 62 M50 70 L50 78',
    },
    views: {
      'front': [
        _Region('front', 'front', 'avant', 42, 14, 16, 72),
        _Region('left', 'left side', 'côté gauche', 29, 14, 11, 72),
        _Region('right', 'right side', 'côté droit', 60, 14, 11, 72),
      ],
      'back': [
        _Region('skull', 'base of the skull', 'base du crâne', 32, 2, 36, 14),
        _Region('spine', 'spine', 'colonne', 44, 20, 12, 66),
        _Region('left', 'left side', 'côté gauche', 29, 20, 13, 66),
        _Region('right', 'right side', 'côté droit', 58, 20, 13, 66),
      ],
    },
  ),
  'lower_back': _Detail(
    sided: false,
    outline: 'M10 0 L90 0 C88 30 88 60 94 100 L6 100 C12 60 12 30 10 0 Z',
    art: {
      'back': 'M50 4 L50 78 M44 8 C40 30 40 50 44 70 M56 8 C60 30 60 50 56 70 M12 74 C30 66 70 66 88 74',
    },
    views: {
      'back': [
        _Region('spine', 'spine', 'colonne', 44, 8, 12, 68),
        _Region('left', 'left side', 'côté gauche', 12, 12, 30, 56),
        _Region('right', 'right side', 'côté droit', 58, 12, 30, 56),
        _ell('tailbone', 'tailbone', 'coccyx', 50, 86, 10, 8),
      ],
    },
  ),
  'hips': _Detail(
    sided: false,
    outline: 'M4 10 L96 10 C98 40 92 70 80 94 L20 94 C8 70 2 40 4 10 Z',
    art: {
      'front': 'M24 46 C30 60 40 72 48 86 M76 46 C70 60 60 72 52 86 M14 28 C20 24 26 26 30 30 M86 28 C80 24 74 26 70 30',
    },
    views: {
      'front': [
        _ell('lhip', 'left hip', 'hanche gauche', 20, 40, 13, 16),
        _ell('rhip', 'right hip', 'hanche droite', 80, 40, 13, 16),
        _ell('lgroin', 'left groin', 'aine gauche', 38, 68, 10, 12),
        _ell('rgroin', 'right groin', 'aine droite', 62, 68, 10, 12),
      ],
    },
  ),
  'glutes': _Detail(
    sided: false,
    outline: 'M4 10 L96 10 C100 40 98 74 90 94 L10 94 C2 74 0 40 4 10 Z',
    art: {
      'back': 'M50 30 L50 82 M16 80 C28 88 40 88 48 82 M52 82 C60 88 72 88 84 80 M10 24 C30 16 70 16 90 24',
    },
    views: {
      'back': [
        _ell('lbutt', 'left buttock', 'fesse gauche', 32, 54, 16, 22),
        _ell('rbutt', 'right buttock', 'fesse droite', 68, 54, 16, 22),
        _Region('louter', 'outside of the left hip', 'côté de la hanche gauche', 4, 30, 10, 40),
        _Region('router', 'outside of the right hip', 'côté de la hanche droite', 86, 30, 10, 40),
        _ell('tailbone', 'tailbone', 'coccyx', 50, 22, 7, 7),
      ],
    },
  ),
  'ankle': _Detail(
    sided: true,
    outline: 'M38 0 L62 0 C63 30 66 44 68 56 C72 70 74 84 74 100 L26 100 C26 84 28 70 32 56 C34 44 37 30 38 0 Z',
    art: {
      'front': 'M50 2 L50 36 M44 66 C46 80 46 90 44 98 M56 66 C54 80 54 90 56 98',
      'back': 'M46 0 L47 60 M54 0 L53 60 M36 88 C44 94 56 94 64 88',
    },
    views: {
      'front': [
        _ell('outer', 'outer ankle bone', 'malléole externe', 35, 52, 8, 10),
        _ell('inner', 'inner ankle bone', 'malléole interne', 65, 52, 8, 10),
        _Region('front', 'front', 'avant', 43, 38, 14, 26),
        _Region('achilles', 'Achilles tendon', 'tendon d’Achille', 43, 6, 14, 26),
      ],
      'back': [
        _ell('outer', 'outer ankle bone', 'malléole externe', 35, 52, 8, 10),
        _ell('inner', 'inner ankle bone', 'malléole interne', 65, 52, 8, 10),
        _Region('achilles', 'Achilles tendon', 'tendon d’Achille', 43, 10, 14, 52),
      ],
    },
  ),
  'foot': _Detail(
    sided: true,
    outline: 'M40 4 C52 2 62 4 64 14 C68 30 76 44 76 62 C76 80 72 94 58 96 L36 96 C26 94 24 80 26 62 C28 44 34 30 36 14 C36 8 38 5 40 4 Z',
    art: {
      'front': 'M38 78 L37 94 M46 78 L46 95 M54 78 L55 95 M63 76 L65 94 M44 16 C46 36 48 52 50 72',
    },
    views: {
      'front': [
        _Region('top', 'top of the foot', 'dessus du pied', 36, 10, 28, 32),
        _Region('arch', 'arch', 'voûte plantaire', 64, 38, 10, 30),
        _Region('outer', 'outer edge', 'bord externe', 26, 38, 10, 30),
        _Region('ball', 'ball of the foot', 'avant-pied', 36, 58, 28, 14),
        _Region('toes', 'toes', 'orteils', 30, 76, 40, 16),
      ],
    },
  ),
  'heel': _Detail(
    sided: true,
    outline: 'M34 0 L66 0 C67 20 68 32 70 44 C74 60 72 86 62 96 L38 96 C28 86 26 60 30 44 C32 32 33 20 34 0 Z',
    art: {
      'back': 'M46 0 L47 34 M54 0 L53 34 M34 66 C44 70 56 70 66 66',
    },
    views: {
      'back': [
        _Region('achilles', 'Achilles tendon', 'tendon d’Achille', 43, 4, 14, 26),
        _ell('back', 'back of the heel', 'arrière du talon', 50, 46, 17, 12),
        _ell('bottom', 'bottom of the heel', 'sous le talon', 50, 78, 18, 12),
      ],
    },
  ),
  'fore': _Detail(
    sided: true,
    outline: 'M30 0 L70 0 C70 20 68 30 66 50 C64 70 62 84 62 100 L38 100 C38 84 36 70 34 50 C32 30 30 20 30 0 Z',
    art: {
      'front': 'M34 20 C44 24 56 24 66 20 M44 28 C46 50 46 70 48 92 M58 30 C56 50 56 70 54 92',
      'back': 'M44 6 C46 2 54 2 56 6 M46 28 C47 50 48 70 50 94',
    },
    views: {
      'front': [
        _ell('outer_elbow', 'outer elbow', 'coude, côté externe', 36, 16, 8, 11),
        _ell('inner_elbow', 'inner elbow', 'coude, côté interne', 64, 16, 8, 11),
        _Region('forearm', 'forearm muscles', 'muscles de l’avant-bras', 38, 34, 24, 44),
        _Region('wrist', 'near the wrist', 'près du poignet', 38, 82, 24, 14),
      ],
      'back': [
        _ell('point', 'point of the elbow', 'pointe du coude', 50, 14, 11, 10),
        _ell('outer_elbow', 'outer elbow', 'coude, côté externe', 34, 22, 7, 10),
        _ell('inner_elbow', 'inner elbow', 'coude, côté interne', 66, 22, 7, 10),
        _Region('forearm', 'forearm muscles', 'muscles de l’avant-bras', 38, 38, 24, 48),
      ],
    },
  ),
  'hand': _Detail(
    sided: true,
    outline: 'M34 0 L66 0 L68 26 C70 40 72 56 70 66 L70 96 C70 99 40 99 40 96 L38 66 C34 62 30 58 25 52 C21 45 21 35 27 32 C31 31 34 37 36 42 L34 26 Z',
    art: {
      'front': 'M47 68 L47 97 M54 68 L54 98 M62 68 L62 97 M38 50 C48 44 60 44 70 48 M36 20 C46 22 56 22 66 20',
      'back': 'M47 68 L47 97 M54 68 L54 98 M62 68 L62 97 M44 26 L46 64 M52 24 L53 64 M60 26 L60 64',
    },
    views: {
      'front': [
        _Region('wrist', 'wrist', 'poignet', 32, 2, 36, 16),
        _ell('thumb', 'thumb', 'pouce', 31, 44, 7, 15),
        _ell('palm', 'palm', 'paume', 54, 44, 15, 15),
        _Region('fingers', 'fingers', 'doigts', 40, 66, 28, 30),
      ],
      'back': [
        _Region('wrist', 'wrist', 'poignet', 32, 2, 36, 16),
        _ell('thumb', 'thumb', 'pouce', 31, 44, 7, 15),
        _ell('back', 'back of the hand', 'dos de la main', 54, 44, 15, 15),
        _Region('fingers', 'fingers', 'doigts', 40, 66, 28, 30),
      ],
    },
  ),
};

/// The close-up for a main-figure part in a view, or null when it has none.
class _Zoom {
  const _Zoom(this.part, this.detail, this.view, this.flip);
  final String part; // e.g. 'l_knee'
  final _Detail detail;
  final String view;
  final bool flip; // right-side part: the left drawing mirrored
  List<_Region> get spots => detail.views[view] ?? const [];
  String get art => detail.art[view] ?? '';
}

_Zoom? _zoomFor(String view, String part) {
  if (view != 'front' && view != 'back') return null;
  final m = RegExp(r'^([lr])_(.+)$').firstMatch(part);
  final d = _detail[m != null ? m.group(2)! : part];
  if (d == null || (m != null) != d.sided || d.views[view] == null) return null;
  return _Zoom(part, d, view, m != null && m.group(1) == 'r');
}

/// Splits a stored region id into its main-figure part and sub-spot:
/// "l_knee_cap" -> ('l_knee', 'cap'); "l_knee" -> ('l_knee', null).
(String, String?) _splitSpot(String view, String id) {
  final bits = id.split('_');
  for (var n = 1; n < bits.length; n++) {
    final part = bits.sublist(0, n).join('_');
    final sub = bits.sublist(n).join('_');
    final z = _zoomFor(view, part);
    if (z != null && z.spots.any((s) => s.id == sub)) return (part, sub);
  }
  return (id, null);
}

/// Region id -> level for one view; a part shows its worst level whether it
/// was marked whole or at a precise spot.
Map<String, int> _levelsFor(Map<String, int> map, String view) {
  final out = <String, int>{};
  for (final e in map.entries) {
    final p = e.key.split(':');
    if (p.length < 2 || p[0] != view) continue;
    final part = _splitSpot(view, p[1]).$1;
    if (e.value > (out[part] ?? 0)) out[part] = e.value;
  }
  return out;
}

/// Minimal SVG path reader for the close-up drawings (M, L, C and Z only).
Path _svgPath(String d) {
  final path = Path();
  final tok = RegExp(r'[MLCZ]|-?\d+(?:\.\d+)?')
      .allMatches(d)
      .map((m) => m.group(0)!)
      .toList();
  var i = 0;
  var cmd = 'M';
  double n() => double.parse(tok[i++]);
  while (i < tok.length) {
    final t = tok[i];
    if (t == 'M' || t == 'L' || t == 'C' || t == 'Z') {
      cmd = t;
      i++;
      if (cmd == 'Z') path.close();
      continue;
    }
    if (cmd == 'M') {
      path.moveTo(n(), n());
      cmd = 'L';
    } else if (cmd == 'L') {
      path.lineTo(n(), n());
    } else if (cmd == 'C') {
      path.cubicTo(n(), n(), n(), n(), n(), n());
    } else {
      i++;
    }
  }
  return path;
}

/// Sub-spot under a tap in close-up space: the smallest spot containing it,
/// else the one whose edge is within a fingertip (4 units).
_Region? _pickSpot(List<_Region> spots, Offset p) {
  final inside = spots.where((s) => s.contains(p)).toList()
    ..sort((a, b) => (a.w * a.h).compareTo(b.w * b.h));
  if (inside.isNotEmpty) return inside.first;
  _Region? best;
  var bestD = double.infinity;
  for (final s in spots) {
    final dx = [s.x - p.dx, 0.0, p.dx - (s.x + s.w)].reduce((a, b) => a > b ? a : b);
    final dy = [s.y - p.dy, 0.0, p.dy - (s.y + s.h)].reduce((a, b) => a > b ? a : b);
    final d = dx * dx + dy * dy;
    if (d < bestD) {
      bestD = d;
      best = s;
    }
  }
  return bestD <= 16 ? best : null;
}

/// The zoomed drawing: silhouette, anatomy lines and the tappable spots,
/// each filled with its level; the spot being edited gets a dark ring.
class _ZoomPainter extends CustomPainter {
  _ZoomPainter(this.zoom, this.levels, this.selected);
  final _Zoom zoom;
  final Map<String, int> levels; // sub id -> level
  final String? selected; // sub id being edited (null = whole part)

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100);
    if (zoom.flip) {
      canvas.translate(100, 0);
      canvas.scale(-1, 1);
    }
    canvas.drawPath(_svgPath(zoom.detail.outline), Paint()..color = _bodyGrey);
    canvas.drawPath(
        _svgPath(zoom.art),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9
          ..strokeCap = StrokeCap.round
          ..color = BtwColors.inkSoft.withValues(alpha: 0.45));
    for (final s in zoom.spots) {
      final lv = levels[s.id] ?? 0;
      final fill = Paint()
        ..color = lv > 0 ? _fill[lv] : Colors.white.withValues(alpha: 0.45);
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s.id == selected ? 2 : 0.8
        ..color = s.id == selected
            ? BtwColors.ink
            : BtwColors.inkSoft.withValues(alpha: 0.5);
      if (s.ellipse) {
        canvas.drawOval(s.rect, fill);
        canvas.drawOval(s.rect, ring);
      } else {
        final rr = RRect.fromRectAndRadius(s.rect, const Radius.circular(4));
        canvas.drawRRect(rr, fill);
        canvas.drawRRect(rr, ring);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ZoomPainter old) =>
      old.levels != levels || old.selected != selected || old.zoom != zoom;
}

class BodyMap extends StatefulWidget {
  const BodyMap({
    super.key,
    required this.onChanged,
    this.onSensChanged,
    required this.isFr,
  });

  final ValueChanged<Map<String, int>> onChanged;
  final ValueChanged<Map<String, String>>? onSensChanged;
  final bool isFr;

  @override
  State<BodyMap> createState() => _BodyMapState();
}

class _PickResult {
  const _PickResult(this.key, this.level, this.sens, {this.moveFrom});
  final String key; // "view:region" or "view:region_sub"
  final int level;
  final String? sens;
  final String? moveFrom; // whole-part key whose level moved to a precise spot
}

class _BodyMapState extends State<BodyMap> {
  final Map<String, int> _map = {}; // "view:region" -> 1..10
  final Map<String, String> _sens = {}; // "view:region" -> sensation code
  String _view = 'front';
  static const double _w = 190; // on-screen width; height keeps 100:198 ratio

  List<_Region> get _regions => _view == 'front' ? _front : _back;

  Future<void> _tapAt(Offset local) async {
    final scale = _w / 100.0;
    final p = Offset(local.dx / scale, local.dy / scale);
    // Topmost region (extremities are last in the list, so search in reverse).
    _Region? hit;
    for (var i = _regions.length - 1; i >= 0; i--) {
      if (_regions[i].contains(p)) {
        hit = _regions[i];
        break;
      }
    }
    if (hit == null) return;
    final region = hit;
    final zoom = _zoomFor(_view, region.id);
    // Open on the whole part, or on its worst precise spot if it has one.
    String? sub;
    if (zoom != null && !_map.containsKey('$_view:${region.id}')) {
      var best = 0;
      for (final e in _map.entries) {
        final p = e.key.split(':');
        if (p.length < 2 || p[0] != _view) continue;
        final (part, s) = _splitSpot(_view, p[1]);
        if (part == region.id && s != null && e.value > best) {
          best = e.value;
          sub = s;
        }
      }
    }
    final res = await _pickLevel(region, zoom, sub);
    if (res == null || !mounted) return;
    final key = res.key;
    setState(() {
      final from = res.moveFrom;
      if (from != null) {
        _map.remove(from);
        _sens.remove(from);
      }
      if (res.level <= 0) {
        _map.remove(key);
        _sens.remove(key);
      } else {
        _map[key] = res.level;
        if (res.sens == null) {
          _sens.remove(key);
        } else {
          _sens[key] = res.sens!;
        }
      }
    });
    widget.onChanged(Map<String, int>.from(_map));
    widget.onSensChanged?.call(Map<String, String>.from(_sens));
  }

  static const double _zw = 150; // close-up drawing size in the sheet

  Future<_PickResult?> _pickLevel(
      _Region region, _Zoom? zoom, String? initialSub) {
    final isFr = widget.isFr;
    final whole = '$_view:${region.id}';
    String keyOf(String? id) => id == null ? whole : '${whole}_$id';
    String? sub = initialSub;
    int lvl = _map[keyOf(sub)] ?? 0;
    String? sc = _sens[keyOf(sub)];
    String? moveFrom;
    // Switch the spot being edited inside the sheet.
    void choose(String? next) {
      final nk = keyOf(next);
      if (next != null &&
          sub == null &&
          lvl > 0 &&
          (_map[whole] ?? 0) > 0 &&
          !_map.containsKey(nk)) {
        // Refining the whole part to one spot: carry its level and feel over.
        moveFrom = whole;
      } else {
        moveFrom = null;
        lvl = _map[nk] ?? 0;
        sc = _sens[nk];
      }
      sub = next;
    }

    String spotName(String? id) {
      if (id == null || zoom == null) return '';
      for (final s in zoom.spots) {
        if (s.id == id) return isFr ? s.fr : s.en;
      }
      return '';
    }

    Widget chip(String label, bool on, VoidCallback onTap) => GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            decoration: BoxDecoration(
              color: on ? BtwColors.moss : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: on ? BtwColors.moss : BtwColors.line),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: on ? Colors.white : BtwColors.ink,
              ),
            ),
          ),
        );

    return showModalBottomSheet<_PickResult>(
      context: context,
      backgroundColor: BtwColors.cream,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        final cur = sub;
        final current = _map[keyOf(cur)] ?? 0;
        final partName = isFr ? region.fr : region.en;
        final name = cur == null ? partName : '$partName · ${spotName(cur)}';
        // Levels drawn on the close-up, with the spot being edited live.
        final spotLv = <String, int>{};
        if (zoom != null) {
          for (final s in zoom.spots) {
            final v = _map[keyOf(s.id)] ?? 0;
            if (v > 0) spotLv[s.id] = v;
          }
          if (cur != null) {
            if (lvl > 0) {
              spotLv[cur] = lvl;
            } else {
              spotLv.remove(cur);
            }
          }
        }
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (zoom != null) ...[
                  Text(
                    partName.isEmpty
                        ? partName
                        : partName[0].toUpperCase() + partName.substring(1),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isFr
                        ? 'Touchez l’endroit exact (facultatif).'
                        : 'Tap the exact spot (optional).',
                    style: const TextStyle(
                        fontSize: 13, color: BtwColors.inkSoft),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: GestureDetector(
                      onTapDown: (d) {
                        var p = d.localPosition / (_zw / 100);
                        if (zoom.flip) p = Offset(100 - p.dx, p.dy);
                        final hitSpot = _pickSpot(zoom.spots, p);
                        if (hitSpot != null) {
                          setSheet(() => choose(hitSpot.id));
                        }
                      },
                      child: SizedBox(
                        width: _zw,
                        height: _zw,
                        child: CustomPaint(
                            painter: _ZoomPainter(zoom, spotLv, cur)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      chip(isFr ? 'Toute la zone' : 'Whole area', cur == null,
                          () => setSheet(() => choose(null))),
                      for (final s in zoom.spots)
                        chip(isFr ? s.fr : s.en, cur == s.id,
                            () => setSheet(() => choose(s.id))),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
                Text(
                  widget.isFr
                      ? 'Niveau de douleur — $name'
                      : 'Pain level — $name',
                  style:
                      const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.isFr
                      ? '0 = aucune, 10 = la pire'
                      : '0 = none, 10 = worst',
                  style:
                      const TextStyle(fontSize: 13, color: BtwColors.inkSoft),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i <= 10; i++)
                      GestureDetector(
                        onTap: () => setSheet(() => lvl = i),
                        child: Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: i == 0 ? Colors.white : _fill[i],
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: i == lvl ? BtwColors.ink : BtwColors.line,
                              width: i == lvl ? 2.2 : 1,
                            ),
                          ),
                          child: Text(
                            i == 0 ? '0' : '$i',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: i >= 5 ? Colors.white : BtwColors.ink,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                // Sensation quality: only once a level is set. Optional — the
                // patient says how it feels, we read muscle/joint/nerve from it.
                if (lvl > 0) ...[
                  const SizedBox(height: 20),
                  Text(
                    widget.isFr
                        ? 'Comment ça se sent ? (facultatif)'
                        : 'How does it feel? (optional)',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final s in btwSensations)
                        GestureDetector(
                          onTap: () => setSheet(
                              () => sc = (sc == s.code) ? null : s.code),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 9),
                            decoration: BoxDecoration(
                              color:
                                  sc == s.code ? BtwColors.moss : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: sc == s.code
                                      ? BtwColors.moss
                                      : BtwColors.line),
                            ),
                            child: Text(
                              widget.isFr ? s.fr : s.en,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: sc == s.code
                                    ? Colors.white
                                    : BtwColors.ink,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 22),
                Row(
                  children: [
                    if (current > 0)
                      TextButton(
                        onPressed: () => Navigator.of(ctx)
                            .pop(_PickResult(keyOf(cur), 0, null)),
                        child: Text(
                          widget.isFr ? 'Retirer' : 'Remove',
                          style: const TextStyle(
                              color: BtwColors.clay,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    const Spacer(),
                    ElevatedButton(
                      onPressed: () => Navigator.of(ctx).pop(_PickResult(
                          keyOf(cur), lvl, lvl > 0 ? sc : null,
                          moveFrom: lvl > 0 ? moveFrom : null)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: BtwColors.moss,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(widget.isFr ? 'OK' : 'Done'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  String _summary() => painSummary(_map, _sens, widget.isFr);

  Widget _viewBtn(String v, String label) {
    final sel = _view == v;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _view = v),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          decoration: BoxDecoration(
            color: sel ? BtwColors.moss : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: sel ? BtwColors.moss : BtwColors.line),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: sel ? Colors.white : BtwColors.inkSoft)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final h = _w * 198 / 100;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          _viewBtn('front', widget.isFr ? 'Avant' : 'Front'),
          _viewBtn('back', widget.isFr ? 'Arrière' : 'Back'),
        ]),
        const SizedBox(height: 12),
        Center(
          child: GestureDetector(
            onTapDown: (d) => _tapAt(d.localPosition),
            child: SizedBox(
              width: _w,
              height: h,
              child: CustomPaint(
                painter: _BodyPainter(
                  regions: _regions,
                  levels: _levelsFor(_map, _view),
                  scale: _w / 100.0,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(_summary(),
            style: const TextStyle(fontSize: 13, color: BtwColors.inkSoft)),
      ],
    );
  }
}

/// Read-only body figure(s) coloured by a pain map — reuses the same painter
/// and regions as the interactive map. Shows front and back side by side.
class BodyMapView extends StatelessWidget {
  const BodyMapView({super.key, required this.map, this.width = 108});

  final Map<String, int> map; // "view:region" -> level
  final double width;

  Widget _figure(String view, List<_Region> regions) {
    final h = width * 198 / 100;
    return SizedBox(
      width: width,
      height: h,
      child: CustomPaint(
        painter: _BodyPainter(
          regions: regions,
          levels: _levelsFor(map, view),
          scale: width / 100.0,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _figure('front', _front),
        const SizedBox(width: 22),
        _figure('back', _back),
      ],
    );
  }
}

/// Localised label for a "view:region" pain-map key (e.g. "front:lower_back"),
/// precise spots included: "front:l_knee_cap" -> "left knee · kneecap".
String regionLabel(String key, bool isFr) {
  final parts = key.split(':');
  final view = parts.length > 1 ? parts[0] : 'front';
  final id = parts.length > 1 ? parts[1] : key;
  final (part, sub) = _splitSpot(view, id);
  final list = view == 'back' ? [..._back, ..._front] : [..._front, ..._back];
  final r = list.firstWhere((x) => x.id == part,
      orElse: () => _Region(part, part, part, 0, 0, 0, 0));
  final base = isFr ? r.fr : r.en;
  if (sub == null) return base;
  for (final s in _zoomFor(view, part)?.spots ?? const <_Region>[]) {
    if (s.id == sub) return '$base · ${isFr ? s.fr : s.en}';
  }
  return base;
}

class _BodyPainter extends CustomPainter {
  _BodyPainter(
      {required this.regions, required this.levels, required this.scale});
  final List<_Region> regions;
  final Map<String, int> levels; // region id -> level, for the current view
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(scale);
    final grey = Paint()..color = _bodyGrey;
    for (final r in _baseRects) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(5)), grey);
    }
    for (final o in _baseOvals) {
      canvas.drawOval(o, grey);
    }
    // Head (taller oval).
    canvas.drawOval(
        Rect.fromCenter(center: const Offset(50, 15), width: 21, height: 24),
        grey);
    for (final reg in regions) {
      final lv = levels[reg.id] ?? 0;
      if (lv <= 0) continue;
      final paint = Paint()..color = _fill[lv];
      if (reg.ellipse) {
        canvas.drawOval(reg.rect, paint);
      } else {
        canvas.drawRRect(
            RRect.fromRectAndRadius(reg.rect, const Radius.circular(4)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BodyPainter old) =>
      old.levels != levels || old.regions != regions;
}
