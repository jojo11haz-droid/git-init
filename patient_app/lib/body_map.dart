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

class BodyMap extends StatefulWidget {
  const BodyMap({super.key, required this.onChanged, required this.isFr});

  final ValueChanged<Map<String, int>> onChanged;
  final bool isFr;

  @override
  State<BodyMap> createState() => _BodyMapState();
}

class _BodyMapState extends State<BodyMap> {
  final Map<String, int> _map = {}; // "view:region" -> 1..10
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
    final key = '$_view:${region.id}';
    final level = await _pickLevel(region, _map[key] ?? 0);
    if (level == null || !mounted) return;
    setState(() {
      if (level <= 0) {
        _map.remove(key);
      } else {
        _map[key] = level;
      }
    });
    widget.onChanged(Map<String, int>.from(_map));
  }

  Future<int?> _pickLevel(_Region region, int current) {
    final name = widget.isFr ? region.fr : region.en;
    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: BtwColors.cream,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.isFr ? 'Niveau de douleur — $name' : 'Pain level — $name',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                widget.isFr
                    ? '0 = aucune, 10 = la pire'
                    : '0 = none, 10 = worst',
                style: const TextStyle(fontSize: 13, color: BtwColors.inkSoft),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i <= 10; i++)
                    GestureDetector(
                      onTap: () => Navigator.of(ctx).pop(i),
                      child: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: i == 0 ? Colors.white : _fill[i],
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: i == current
                                ? BtwColors.ink
                                : BtwColors.line,
                            width: i == current ? 2.2 : 1,
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
            ],
          ),
        ),
      ),
    );
  }

  String _summary() {
    if (_map.isEmpty) {
      return widget.isFr ? 'Aucune zone douloureuse.' : 'No sore spots yet.';
    }
    final parts = _map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final names = parts.take(4).map((e) {
      final id = e.key.split(':')[1];
      final r = [..._front, ..._back].firstWhere((x) => x.id == id,
          orElse: () => _Region(id, id, id, 0, 0, 0, 0));
      return '${widget.isFr ? r.fr : r.en} (${e.value}/10)';
    }).join(', ');
    final more = parts.length > 4 ? ' …' : '';
    return (widget.isFr ? 'Zones sensibles : ' : 'Sore spots: ') + names + more;
  }

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
                  levels: {
                    for (final e in _map.entries)
                      if (e.key.startsWith('$_view:'))
                        e.key.split(':')[1]: e.value
                  },
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
          levels: {
            for (final e in map.entries)
              if (e.key.startsWith('$view:')) e.key.split(':')[1]: e.value
          },
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

/// Localised label for a "view:region" pain-map key (e.g. "front:lower_back").
String regionLabel(String key, bool isFr) {
  final parts = key.split(':');
  final id = parts.length > 1 ? parts[1] : key;
  final r = [..._front, ..._back]
      .firstWhere((x) => x.id == id, orElse: () => _Region(id, id, id, 0, 0, 0, 0));
  return isFr ? r.fr : r.en;
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
