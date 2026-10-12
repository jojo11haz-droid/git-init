import 'package:flutter/material.dart';

import '../strings.dart';
import '../theme.dart';

/// One step of the spotlight tour. [targetKey] points at the widget to
/// highlight; when null (or not found), the card is shown centred.
class CoachStep {
  const CoachStep({this.targetKey, required this.title, required this.body});
  final GlobalKey? targetKey;
  final String title;
  final String body;
}

/// Starts the spotlight tour by inserting a full-screen overlay. The overlay
/// dims the screen, cuts a hole around each step's target, and shows a card
/// with Back/Next/Skip. Call from a widget that owns the target GlobalKeys.
void startCoachTour(
  BuildContext context, {
  required List<CoachStep> steps,
  required S strings,
  VoidCallback? onDone,
}) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _CoachTourOverlay(
      steps: steps,
      strings: strings,
      onFinish: () {
        entry.remove();
        if (onDone != null) onDone();
      },
    ),
  );
  overlay.insert(entry);
}

class _CoachTourOverlay extends StatefulWidget {
  const _CoachTourOverlay({
    required this.steps,
    required this.strings,
    required this.onFinish,
  });
  final List<CoachStep> steps;
  final S strings;
  final VoidCallback onFinish;

  @override
  State<_CoachTourOverlay> createState() => _CoachTourOverlayState();
}

class _CoachTourOverlayState extends State<_CoachTourOverlay> {
  int _i = 0;

  Rect? _targetRect(Size screen) {
    final key = widget.steps[_i].targetKey;
    if (key == null) return null;
    final ctx = key.currentContext;
    if (ctx == null) return null;
    final obj = ctx.findRenderObject();
    if (obj is! RenderBox || !obj.hasSize) return null;
    final topLeft = obj.localToGlobal(Offset.zero);
    final rect = topLeft & obj.size;
    // A padded hole, clamped to the screen.
    return Rect.fromLTRB(
      rect.left - 8,
      rect.top - 8,
      rect.right + 8,
      rect.bottom + 8,
    ).intersect(Offset.zero & screen);
  }

  void _next() {
    if (_i >= widget.steps.length - 1) {
      widget.onFinish();
    } else {
      setState(() => _i++);
    }
  }

  void _back() {
    if (_i > 0) setState(() => _i--);
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    final hole = _targetRect(screen);
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onFinish, // tap outside to skip
              child: CustomPaint(painter: _SpotlightPainter(hole: hole)),
            ),
          ),
          _positionedCard(screen, hole),
        ],
      ),
    );
  }

  Widget _positionedCard(Size screen, Rect? hole) {
    const maxW = 360.0;
    final cardW = (screen.width - 40) < maxW ? (screen.width - 40) : maxW;
    final card = _card(cardW);
    if (hole == null) return Center(child: card);
    final left = (hole.center.dx - cardW / 2)
        .clamp(20.0, screen.width - cardW - 20)
        .toDouble();
    final belowSpace = screen.height - hole.bottom;
    if (belowSpace > 200) {
      return Positioned(left: left, top: hole.bottom + 14, child: card);
    }
    // Not enough room below — anchor above the hole.
    return Positioned(
        left: left, bottom: screen.height - hole.top + 14, child: card);
  }

  Widget _card(double cardW) {
    final s = widget.strings;
    final step = widget.steps[_i];
    final last = _i >= widget.steps.length - 1;
    return GestureDetector(
      onTap: () {}, // swallow taps so they don't fall through to "skip"
      child: Container(
        width: cardW,
        padding: const EdgeInsets.fromLTRB(18, 15, 14, 13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.22),
                blurRadius: 30,
                offset: const Offset(0, 12)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(step.title,
                        style: const TextStyle(
                            fontSize: 17.5, fontWeight: FontWeight.w700)),
                  ),
                ),
                GestureDetector(
                  onTap: widget.onFinish,
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(Icons.close_rounded,
                        size: 20, color: BtwColors.inkSoft),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(step.body,
                style: const TextStyle(
                    fontSize: 14.5, height: 1.5, color: BtwColors.inkSoft)),
            const SizedBox(height: 14),
            Row(
              children: [
                for (var d = 0; d < widget.steps.length; d++)
                  Container(
                    margin: const EdgeInsets.only(right: 5),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: d == _i ? BtwColors.moss : BtwColors.line,
                      shape: BoxShape.circle,
                    ),
                  ),
                const Spacer(),
                if (_i > 0)
                  TextButton(
                    onPressed: _back,
                    child: Text(s.tourBack,
                        style: const TextStyle(color: BtwColors.inkSoft)),
                  ),
                const SizedBox(width: 2),
                FilledButton(
                  onPressed: _next,
                  child: Text(last ? s.onbDone : s.onbNext),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter({required this.hole});
  final Rect? hole;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    final scrim = Paint()..color = const Color(0x9E14161B); // ~62% dark
    if (hole == null) {
      canvas.drawRect(full, scrim);
      return;
    }
    canvas.saveLayer(full, Paint());
    canvas.drawRect(full, scrim);
    canvas.drawRRect(
      RRect.fromRectAndRadius(hole!, const Radius.circular(12)),
      Paint()..blendMode = BlendMode.clear,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter old) => old.hole != hole;
}
