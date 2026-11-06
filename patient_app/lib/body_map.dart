import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
// Zoomed close-ups for the main rehab areas — mirrors BTW_DETAIL on the web
// (kept identical by scripts/app-tests.mjs). Tapping a knee, shoulder,
// ankle… opens a photo of just that part with a point on each precise spot
// ("inner side of the left knee"). A spot is stored as "view:part_sub"
// (e.g. "front:l_knee_cap") next to the plain whole-part key. Points are in
// percent of the square photo; photos show the LEFT part (midline to the
// right, so "inner" sits right) and are mirrored for the right part.

class _Dot {
  const _Dot(this.id, this.en, this.fr, this.x, this.y);
  final String id, en, fr;
  final double x, y; // percent of the photo
}

class _Detail {
  const _Detail({required this.sided, required this.img, required this.views});
  final bool sided;
  final Map<String, String> img; // view -> photo name in assets/body/
  final Map<String, List<_Dot>> views; // view -> tappable points
}

const _detail = <String, _Detail>{
  'knee': _Detail(
    sided: true,
    img: {'front': 'knee_front', 'back': 'knee_back'},
    views: {
      'front': [
        _Dot('above', 'above the kneecap', 'au-dessus de la rotule', 50, 26),
        _Dot('cap', 'kneecap', 'rotule', 49, 46),
        _Dot('below', 'below the kneecap', 'sous la rotule', 50, 70),
        _Dot('outer', 'outer side', 'côté externe', 32, 52),
        _Dot('inner', 'inner side', 'côté interne', 67, 52),
      ],
      'back': [
        _Dot('hollow', 'centre', 'centre', 50, 54),
        _Dot('outer', 'outer side', 'côté externe', 37, 50),
        _Dot('inner', 'inner side', 'côté interne', 63, 50),
        _Dot('calf', 'top of the calf', 'haut du mollet', 50, 80),
      ],
    },
  ),
  'shoulder': _Detail(
    sided: true,
    img: {'front': 'shoulder_front', 'back': 'shoulder_back'},
    views: {
      'front': [
        _Dot('top', 'top', 'dessus', 28, 23),
        _Dot('front', 'front', 'avant', 30, 40),
        _Dot('outer', 'outer side', 'côté externe', 11, 42),
        _Dot('collar', 'collarbone', 'clavicule', 60, 28),
        _Dot('armpit', 'armpit', 'aisselle', 37, 70),
      ],
      'back': [
        _Dot('top', 'top', 'dessus', 40, 12),
        _Dot('back', 'back', 'arrière', 22, 38),
        _Dot('blade', 'shoulder blade', 'omoplate', 66, 46),
        _Dot('outer', 'outer side', 'côté externe', 8, 46),
      ],
    },
  ),
  'neck': _Detail(
    sided: false,
    img: {'front': 'neck_front', 'back': 'neck_back'},
    views: {
      'front': [
        _Dot('front', 'front', 'avant', 50, 36),
        _Dot('left', 'left side', 'côté gauche', 35, 44),
        _Dot('right', 'right side', 'côté droit', 65, 44),
      ],
      'back': [
        _Dot('skull', 'base of the skull', 'base du crâne', 50, 21),
        _Dot('spine', 'spine', 'colonne', 50, 52),
        _Dot('left', 'left side', 'côté gauche', 37, 48),
        _Dot('right', 'right side', 'côté droit', 63, 48),
      ],
    },
  ),
  'lower_back': _Detail(
    sided: false,
    img: {'back': 'lower_back'},
    views: {
      'back': [
        _Dot('spine', 'spine', 'colonne', 50, 42),
        _Dot('left', 'left side', 'côté gauche', 29, 42),
        _Dot('right', 'right side', 'côté droit', 71, 42),
        _Dot('tailbone', 'tailbone', 'coccyx', 50, 88),
      ],
    },
  ),
  'hips': _Detail(
    sided: false,
    img: {'front': 'hips_front'},
    views: {
      'front': [
        _Dot('lhip', 'left hip', 'hanche gauche', 24, 44),
        _Dot('rhip', 'right hip', 'hanche droite', 76, 44),
        _Dot('lgroin', 'left groin', 'aine gauche', 41, 62),
        _Dot('rgroin', 'right groin', 'aine droite', 59, 62),
      ],
    },
  ),
  'glutes': _Detail(
    sided: false,
    img: {'back': 'glutes'},
    views: {
      'back': [
        _Dot('lbutt', 'left buttock', 'fesse gauche', 40, 58),
        _Dot('rbutt', 'right buttock', 'fesse droite', 60, 58),
        _Dot('louter', 'outside of the left hip', 'côté de la hanche gauche', 28, 46),
        _Dot('router', 'outside of the right hip', 'côté de la hanche droite', 72, 46),
        _Dot('tailbone', 'tailbone', 'coccyx', 50, 40),
      ],
    },
  ),
  'ankle': _Detail(
    sided: true,
    img: {'front': 'ankle_front', 'back': 'ankle_back'},
    views: {
      'front': [
        _Dot('outer', 'outer ankle bone', 'malléole externe', 28, 57),
        _Dot('inner', 'inner ankle bone', 'malléole interne', 71, 57),
        _Dot('front', 'front', 'avant', 50, 62),
      ],
      'back': [
        _Dot('outer', 'outer ankle bone', 'malléole externe', 33, 55),
        _Dot('inner', 'inner ankle bone', 'malléole interne', 67, 55),
        _Dot('achilles', 'Achilles tendon', 'tendon d’Achille', 50, 42),
      ],
    },
  ),
  'foot': _Detail(
    sided: true,
    img: {'front': 'foot_top'},
    views: {
      'front': [
        _Dot('top', 'top of the foot', 'dessus du pied', 48, 35),
        _Dot('arch', 'arch', 'voûte plantaire', 67, 55),
        _Dot('outer', 'outer edge', 'bord externe', 30, 62),
        _Dot('ball', 'ball of the foot', 'avant-pied', 52, 72),
        _Dot('toes', 'toes', 'orteils', 52, 89),
      ],
    },
  ),
  'heel': _Detail(
    sided: true,
    img: {'back': 'heel_back'},
    views: {
      'back': [
        _Dot('achilles', 'Achilles tendon', 'tendon d’Achille', 50, 25),
        _Dot('back', 'back of the heel', 'arrière du talon', 50, 62),
        _Dot('bottom', 'bottom of the heel', 'sous le talon', 50, 90),
      ],
    },
  ),
  'fore': _Detail(
    sided: true,
    img: {'front': 'fore_front', 'back': 'fore_back'},
    views: {
      'front': [
        _Dot('outer_elbow', 'outer elbow', 'coude, côté externe', 36, 12),
        _Dot('inner_elbow', 'inner elbow', 'coude, côté interne', 60, 12),
        _Dot('forearm', 'forearm muscles', 'muscles de l’avant-bras', 50, 42),
        _Dot('wrist', 'near the wrist', 'près du poignet', 50, 85),
      ],
      'back': [
        _Dot('point', 'point of the elbow', 'pointe du coude', 50, 8),
        _Dot('outer_elbow', 'outer elbow', 'coude, côté externe', 37, 16),
        _Dot('inner_elbow', 'inner elbow', 'coude, côté interne', 63, 16),
        _Dot('forearm', 'forearm muscles', 'muscles de l’avant-bras', 50, 46),
      ],
    },
  ),
  'hand': _Detail(
    sided: true,
    img: {'front': 'hand_palm', 'back': 'hand_back'},
    views: {
      'front': [
        _Dot('wrist', 'wrist', 'poignet', 50, 6),
        _Dot('thumb', 'thumb', 'pouce', 25, 48),
        _Dot('palm', 'palm', 'paume', 51, 38),
        _Dot('fingers', 'fingers', 'doigts', 50, 80),
      ],
      'back': [
        _Dot('wrist', 'wrist', 'poignet', 52, 6),
        _Dot('thumb', 'thumb', 'pouce', 26, 52),
        _Dot('back', 'back of the hand', 'dos de la main', 56, 38),
        _Dot('fingers', 'fingers', 'doigts', 58, 82),
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
  final bool flip; // right-side part: the left photo mirrored
  List<_Dot> get spots => detail.views[view] ?? const [];
  // Female photos are f_<name>.webp, framed like the male ones so the
  // points line up on both.
  String asset(bool female) =>
      'assets/body/${female ? 'f_' : ''}${detail.img[view]}.webp';
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
  // Close-up photo set: the patient's choice of a man's or a woman's body,
  // remembered on the device (same key as the website's localStorage).
  static bool _female = false;
  static const _sexKey = 'btw_body_sex';
  static const _store = FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _loadSex();
  }

  Future<void> _loadSex() async {
    try {
      final v = await _store.read(key: _sexKey);
      if (v != null && mounted) setState(() => _female = v == 'f');
    } catch (_) {}
  }

  void _setFemale(bool f) {
    _female = f;
    _saveSex(f);
  }

  Future<void> _saveSex(bool f) async {
    try {
      await _store.write(key: _sexKey, value: f ? 'f' : 'm');
    } catch (_) {}
  }
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

  static const double _zw = 200; // close-up photo size in the sheet

  // One tappable point on the close-up: brand blue until it has a level,
  // then that level's colour; the point being edited is bigger with a dark ring.
  static Widget _dot(int level, bool selected) {
    final size = selected ? 22.0 : 18.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: level > 0
            ? _fill[level]
            : BtwColors.moss.withValues(alpha: 0.88),
        border: Border.all(
            color: selected ? BtwColors.ink : Colors.white,
            width: selected ? 2.5 : 2),
        boxShadow: const [
          BoxShadow(color: Color(0x55000000), blurRadius: 3, offset: Offset(0, 1)),
        ],
      ),
    );
  }

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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          partName.isEmpty
                              ? partName
                              : partName[0].toUpperCase() +
                                  partName.substring(1),
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      ),
                      chip(isFr ? 'Homme' : 'Man', !_female,
                          () => setSheet(() => _setFemale(false))),
                      const SizedBox(width: 6),
                      chip(isFr ? 'Femme' : 'Woman', _female,
                          () => setSheet(() => _setFemale(true))),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isFr
                        ? 'Touchez le point exact (facultatif).'
                        : 'Tap the exact point (optional).',
                    style: const TextStyle(
                        fontSize: 13, color: BtwColors.inkSoft),
                  ),
                  const SizedBox(height: 10),
                  // Photo of the part with a point on each spot; a right-side
                  // part shows the left photo mirrored, points included.
                  Center(
                    child: Transform.flip(
                      flipX: zoom.flip,
                      child: SizedBox(
                        width: _zw,
                        height: _zw,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned.fill(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.asset(zoom.asset(_female),
                                    fit: BoxFit.cover),
                              ),
                            ),
                            for (final s in zoom.spots)
                              Positioned(
                                left: s.x * _zw / 100 - 17,
                                top: s.y * _zw / 100 - 17,
                                child: Semantics(
                                  button: true,
                                  selected: cur == s.id,
                                  label: isFr ? s.fr : s.en,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => setSheet(() => choose(s.id)),
                                    child: SizedBox(
                                      width: 34,
                                      height: 34,
                                      child: Center(
                                        child: _dot(spotLv[s.id] ?? 0,
                                            cur == s.id),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
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
  for (final s in _zoomFor(view, part)?.spots ?? const <_Dot>[]) {
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
