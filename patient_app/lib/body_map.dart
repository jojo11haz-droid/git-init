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

// Smooth front/back body outline in the 100 x 198 map space, a man's and a
// woman's — identical to BTW_OUTLINE on the website (checked by
// scripts/app-tests.mjs). The head is drawn separately as an oval.
const _outline = <String, String>{
  'm': 'M45.6 24 C44.07 24.92 46.47 28.33 45.2 29.5 C43.93 30.67 40.7 30.45 38 31 C35.3 31.55 31.47 31.88 29 32.8 C26.53 33.72 24.57 34.63 23.2 36.5 C21.83 38.37 21.28 41.08 20.8 44 C20.32 46.92 20.47 50.67 20.3 54 C20.13 57.33 20.03 60.67 19.8 64 C19.57 67.33 19.1 70.67 18.9 74 C18.7 77.33 18.52 80.83 18.6 84 C18.68 87.17 19.4 90.5 19.4 93 C19.4 95.5 18.57 97.08 18.6 99 C18.63 100.92 18.8 103.07 19.6 104.5 C20.4 105.93 22.12 107.35 23.4 107.6 C24.68 107.85 26.3 107.27 27.3 106 C28.3 104.73 29.17 102.08 29.4 100 C29.63 97.92 28.67 96.17 28.7 93.5 C28.73 90.83 29.35 87.25 29.6 84 C29.85 80.75 29.98 77 30.2 74 C30.42 71 30.67 68.83 30.9 66 C31.13 63.17 31.38 59.83 31.6 57 C31.82 54.17 31.87 51.08 32.2 49 C32.53 46.92 32.97 44.33 33.6 44.5 C34.23 44.67 35.37 47.75 36 50 C36.63 52.25 37.07 55.33 37.4 58 C37.73 60.67 38.27 63.5 38 66 C37.73 68.5 36.37 70.67 35.8 73 C35.23 75.33 34.77 77.17 34.6 80 C34.43 82.83 34.67 86.33 34.8 90 C34.93 93.67 35.13 97.33 35.4 102 C35.67 106.67 36.1 113.67 36.4 118 C36.7 122.33 37.03 125 37.2 128 C37.37 131 37.45 133 37.4 136 C37.35 139 36.83 142 36.9 146 C36.97 150 37.42 155.67 37.8 160 C38.18 164.33 38.93 168.83 39.2 172 C39.47 175.17 39.83 176.83 39.4 179 C38.97 181.17 37.1 183.08 36.6 185 C36.1 186.92 35.92 189.17 36.4 190.5 C36.88 191.83 37.82 192.58 39.5 193 C41.18 193.42 44.98 193.5 46.5 193 C48.02 192.5 48.32 191.5 48.6 190 C48.88 188.5 48.37 186 48.2 184 C48.03 182 47.6 181.17 47.6 178 C47.6 174.83 48.07 169.67 48.2 165 C48.33 160.33 48.38 154.17 48.4 150 C48.42 145.83 48.27 143 48.3 140 C48.33 137 48.47 135.67 48.6 132 C48.73 128.33 48.97 123.33 49.1 118 C49.23 112.67 49.25 104.58 49.4 100 C49.55 95.42 49.8 90.5 50 90.5 C50.2 90.5 50.45 95.42 50.6 100 C50.75 104.58 50.77 112.67 50.9 118 C51.03 123.33 51.27 128.33 51.4 132 C51.53 135.67 51.67 137 51.7 140 C51.73 143 51.58 145.83 51.6 150 C51.62 154.17 51.67 160.33 51.8 165 C51.93 169.67 52.4 174.83 52.4 178 C52.4 181.17 51.97 182 51.8 184 C51.63 186 51.12 188.5 51.4 190 C51.68 191.5 51.98 192.5 53.5 193 C55.02 193.5 58.82 193.42 60.5 193 C62.18 192.58 63.12 191.83 63.6 190.5 C64.08 189.17 63.9 186.92 63.4 185 C62.9 183.08 61.03 181.17 60.6 179 C60.17 176.83 60.53 175.17 60.8 172 C61.07 168.83 61.82 164.33 62.2 160 C62.58 155.67 63.03 150 63.1 146 C63.17 142 62.65 139 62.6 136 C62.55 133 62.63 131 62.8 128 C62.97 125 63.3 122.33 63.6 118 C63.9 113.67 64.33 106.67 64.6 102 C64.87 97.33 65.07 93.67 65.2 90 C65.33 86.33 65.57 82.83 65.4 80 C65.23 77.17 64.77 75.33 64.2 73 C63.63 70.67 62.27 68.5 62 66 C61.73 63.5 62.27 60.67 62.6 58 C62.93 55.33 63.37 52.25 64 50 C64.63 47.75 65.77 44.67 66.4 44.5 C67.03 44.33 67.47 46.92 67.8 49 C68.13 51.08 68.18 54.17 68.4 57 C68.62 59.83 68.87 63.17 69.1 66 C69.33 68.83 69.58 71 69.8 74 C70.02 77 70.15 80.75 70.4 84 C70.65 87.25 71.27 90.83 71.3 93.5 C71.33 96.17 70.37 97.92 70.6 100 C70.83 102.08 71.7 104.73 72.7 106 C73.7 107.27 75.32 107.85 76.6 107.6 C77.88 107.35 79.6 105.93 80.4 104.5 C81.2 103.07 81.37 100.92 81.4 99 C81.43 97.08 80.6 95.5 80.6 93 C80.6 90.5 81.32 87.17 81.4 84 C81.48 80.83 81.3 77.33 81.1 74 C80.9 70.67 80.43 67.33 80.2 64 C79.97 60.67 79.87 57.33 79.7 54 C79.53 50.67 79.68 46.92 79.2 44 C78.72 41.08 78.17 38.37 76.8 36.5 C75.43 34.63 73.47 33.72 71 32.8 C68.53 31.88 64.7 31.55 62 31 C59.3 30.45 56.07 30.67 54.8 29.5 C53.53 28.33 55.93 24.92 54.4 24 C52.87 23.08 47.13 23.08 45.6 24 Z',
  'f': 'M46.3 24 C45.02 24.83 47.05 27.73 46 29 C44.95 30.27 42.23 30.8 40 31.6 C37.77 32.4 34.63 32.83 32.6 33.8 C30.57 34.77 28.93 35.7 27.8 37.4 C26.67 39.1 26.27 41.23 25.8 44 C25.33 46.77 25.27 50.67 25 54 C24.73 57.33 24.57 60.67 24.2 64 C23.83 67.33 23.17 70.67 22.8 74 C22.43 77.33 22.13 80.83 22 84 C21.87 87.17 22.22 90.5 22 93 C21.78 95.5 20.78 97.08 20.7 99 C20.62 100.92 20.87 103.1 21.5 104.5 C22.13 105.9 23.47 107.18 24.5 107.4 C25.53 107.62 26.88 107.03 27.7 105.8 C28.52 104.57 29.07 102.05 29.4 100 C29.73 97.95 29.48 96.17 29.7 93.5 C29.92 90.83 30.4 87.25 30.7 84 C31 80.75 31.22 77 31.5 74 C31.78 71 32.13 68.83 32.4 66 C32.67 63.17 32.92 59.67 33.1 57 C33.28 54.33 33.23 51.97 33.5 50 C33.77 48.03 34.35 45.53 34.7 45.2 C35.05 44.87 35.35 46.78 35.6 48 C35.85 49.22 35.9 51.08 36.2 52.5 C36.5 53.92 36.85 54.92 37.4 56.5 C37.95 58.08 39.13 60.33 39.5 62 C39.87 63.67 40.05 64.75 39.6 66.5 C39.15 68.25 37.83 70.42 36.8 72.5 C35.77 74.58 34.15 76.5 33.4 79 C32.65 81.5 32.35 84.25 32.3 87.5 C32.25 90.75 32.67 94.42 33.1 98.5 C33.53 102.58 34.33 107.75 34.9 112 C35.47 116.25 36.05 120.33 36.5 124 C36.95 127.67 37.45 130.5 37.6 134 C37.75 137.5 37.25 140.83 37.4 145 C37.55 149.17 38.08 154.67 38.5 159 C38.92 163.33 39.6 167.83 39.9 171 C40.2 174.17 40.58 175.75 40.3 178 C40.02 180.25 38.57 182.5 38.2 184.5 C37.83 186.5 37.68 188.65 38.1 190 C38.52 191.35 39.32 192.13 40.7 192.6 C42.08 193.07 45.15 193.23 46.4 192.8 C47.65 192.37 47.93 191.47 48.2 190 C48.47 188.53 48.1 186 48 184 C47.9 182 47.6 181.17 47.6 178 C47.6 174.83 47.92 169.67 48 165 C48.08 160.33 48.1 154.17 48.1 150 C48.1 145.83 47.95 143 48 140 C48.05 137 48.3 135.67 48.4 132 C48.5 128.33 48.48 123 48.6 118 C48.72 113 48.87 106.25 49.1 102 C49.33 97.75 49.7 92.5 50 92.5 C50.3 92.5 50.67 97.75 50.9 102 C51.13 106.25 51.28 113 51.4 118 C51.52 123 51.5 128.33 51.6 132 C51.7 135.67 51.95 137 52 140 C52.05 143 51.9 145.83 51.9 150 C51.9 154.17 51.92 160.33 52 165 C52.08 169.67 52.4 174.83 52.4 178 C52.4 181.17 52.1 182 52 184 C51.9 186 51.53 188.53 51.8 190 C52.07 191.47 52.35 192.37 53.6 192.8 C54.85 193.23 57.92 193.07 59.3 192.6 C60.68 192.13 61.48 191.35 61.9 190 C62.32 188.65 62.17 186.5 61.8 184.5 C61.43 182.5 59.98 180.25 59.7 178 C59.42 175.75 59.8 174.17 60.1 171 C60.4 167.83 61.08 163.33 61.5 159 C61.92 154.67 62.45 149.17 62.6 145 C62.75 140.83 62.25 137.5 62.4 134 C62.55 130.5 63.05 127.67 63.5 124 C63.95 120.33 64.53 116.25 65.1 112 C65.67 107.75 66.47 102.58 66.9 98.5 C67.33 94.42 67.75 90.75 67.7 87.5 C67.65 84.25 67.35 81.5 66.6 79 C65.85 76.5 64.23 74.58 63.2 72.5 C62.17 70.42 60.85 68.25 60.4 66.5 C59.95 64.75 60.13 63.67 60.5 62 C60.87 60.33 62.05 58.08 62.6 56.5 C63.15 54.92 63.5 53.92 63.8 52.5 C64.1 51.08 64.15 49.22 64.4 48 C64.65 46.78 64.95 44.87 65.3 45.2 C65.65 45.53 66.23 48.03 66.5 50 C66.77 51.97 66.72 54.33 66.9 57 C67.08 59.67 67.33 63.17 67.6 66 C67.87 68.83 68.22 71 68.5 74 C68.78 77 69 80.75 69.3 84 C69.6 87.25 70.08 90.83 70.3 93.5 C70.52 96.17 70.27 97.95 70.6 100 C70.93 102.05 71.48 104.57 72.3 105.8 C73.12 107.03 74.47 107.62 75.5 107.4 C76.53 107.18 77.87 105.9 78.5 104.5 C79.13 103.1 79.38 100.92 79.3 99 C79.22 97.08 78.22 95.5 78 93 C77.78 90.5 78.13 87.17 78 84 C77.87 80.83 77.57 77.33 77.2 74 C76.83 70.67 76.17 67.33 75.8 64 C75.43 60.67 75.27 57.33 75 54 C74.73 50.67 74.67 46.77 74.2 44 C73.73 41.23 73.33 39.1 72.2 37.4 C71.07 35.7 69.43 34.77 67.4 33.8 C65.37 32.83 62.23 32.4 60 31.6 C57.77 30.8 55.05 30.27 54 29 C52.95 27.73 54.98 24.83 53.7 24 C52.42 23.17 47.58 23.17 46.3 24 Z',
};
const _headRx = <String, double>{'m': 10.5, 'f': 10};
// The woman's hair, front and back — identical to BTW_HAIR on the website.
const _hairF = <String, String>{
  'front': 'M50 1.6 C57.4 1.6 61.8 6 61.8 13 C61.8 19.5 62.6 25 64 29.6 C61.4 31 58.8 30.6 57.4 29.2 C58.3 24 58.5 19 57.7 14 C56.2 9.6 53.2 8 50 8 C46.8 8 43.8 9.6 42.3 14 C41.5 19 41.7 24 42.6 29.2 C41.2 30.6 38.6 31 36 29.6 C37.4 25 38.2 19.5 38.2 13 C38.2 6 42.6 1.6 50 1.6 Z',
  'back': 'M50 1.6 C57.4 1.6 61.8 6 61.8 13 C61.8 19.5 62.6 25 64 29.6 C58.4 31.8 41.6 31.8 36 29.6 C37.4 25 38.2 19.5 38.2 13 C38.2 6 42.6 1.6 50 1.6 Z',
};
final _hairPaths = <String, Path>{};
Path _hair(String view) =>
    _hairPaths.putIfAbsent(view, () => _svgPath(_hairF[view]!));

final _outlinePaths = <String, Path>{};

/// Body silhouette (outline + head) for 'm' or 'f', parsed once.
Path _silhouette(bool female) {
  final k = female ? 'f' : 'm';
  return _outlinePaths.putIfAbsent(k, () {
    final p = _svgPath(_outline[k]!);
    p.addOval(Rect.fromCenter(
        center: const Offset(50, 15), width: _headRx[k]! * 2, height: 24));
    return p;
  });
}

/// Minimal SVG path reader for the outline (M, L, C and Z only).
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
    if (!mounted) return;
    if (res == null) {
      setState(() {}); // the Man / Woman switch may have changed in the sheet
      return;
    }
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
          const Spacer(),
          // Man / Woman: the figure's outline and the close-up photos.
          _sexBtn(false, widget.isFr ? 'Homme' : 'Man'),
          _sexBtn(true, widget.isFr ? 'Femme' : 'Woman'),
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
                  female: _female,
                  view: _view,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(_summary(),
            style: const TextStyle(fontSize: 13, color: BtwColors.inkSoft)),
        const SizedBox(height: 6),
        Text(
          widget.isFr
              ? 'Astuce : touchez un genou, une épaule, une cheville ou une main pour zoomer et choisir le point exact.'
              : 'Tip: tap a knee, shoulder, ankle or hand to zoom in and pick the exact spot.',
          style: const TextStyle(fontSize: 12, color: BtwColors.inkSoft),
        ),
      ],
    );
  }

  Widget _sexBtn(bool female, String label) {
    final sel = _female == female;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: GestureDetector(
        onTap: () => setState(() => _setFemale(female)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: sel ? BtwColors.moss : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: sel ? BtwColors.moss : BtwColors.line),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: sel ? Colors.white : BtwColors.inkSoft)),
        ),
      ),
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
          female: _BodyMapState._female,
          view: view,
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
      {required this.regions,
      required this.levels,
      required this.scale,
      this.female = false,
      this.view = 'front'});
  final List<_Region> regions;
  final Map<String, int> levels; // region id -> level, for the current view
  final double scale;
  final bool female; // a woman's outline instead of a man's
  final String view; // 'front' | 'back' — which way the hair falls

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(scale);
    final body = _silhouette(female);
    canvas.drawPath(body, Paint()..color = _bodyGrey);
    canvas.drawPath(
        body,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5
          ..color = const Color(0xFFB9BFCA));
    if (female) {
      canvas.drawPath(
          _hair(view == 'back' ? 'back' : 'front'),
          Paint()..color = const Color(0xFF9AA1AD));
    }
    // Pain colours are trimmed to the body so they read as body areas.
    canvas.clipPath(body);
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
      old.levels != levels ||
      old.regions != regions ||
      old.female != female ||
      old.view != view;
}
