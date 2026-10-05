import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'strings.dart';

/// Between's palette — matched to the betweenpsych.com website so the app and
/// site look like one product: the brand blue ("moss"), the clay-red accent,
/// and the soft off-white "paper" background. (The CSS var names are kept.)
class BtwColors {
  static const cream = Color(0xFFF5F4F1); // site --paper (background)
  static const moss = Color(0xFF1E4C86); // site --moss (brand blue, primary)
  static const mossLight = Color(0xFFDDE6F2); // soft blue tint
  static const ink = Color(0xFF1A1E1C); // site --ink (text)
  static const inkSoft = Color(0xFF5A6169); // site --ink-soft (muted)
  static const line = Color(0xFFE4E3DD); // site --line (borders)
  static const clay = Color(0xFFC0392B); // site --clay (red accent)
  static const amber = Color(0xFFE7C3BC); // crisis card border (clay-rose)
  static const amberBg = Color(0xFFFBEFEC); // crisis card background
  static const amberInk = Color(0xFF7A2C20); // crisis card text
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: 'Roboto', // bundled — see pubspec.yaml
    colorScheme: ColorScheme.fromSeed(
      seedColor: BtwColors.moss,
      primary: BtwColors.moss,
      surface: BtwColors.cream,
    ),
    scaffoldBackgroundColor: BtwColors.cream,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: BtwColors.ink,
      displayColor: BtwColors.ink,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: BtwColors.cream,
      foregroundColor: BtwColors.ink,
      elevation: 0,
      centerTitle: false,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: BtwColors.moss,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(58),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: BtwColors.ink,
        minimumSize: const Size.fromHeight(58),
        side: const BorderSide(color: BtwColors.line, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: BtwColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: BtwColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: BtwColors.moss, width: 2),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: BtwColors.ink,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}

/// The Between lens logo — the same mark as the website and the app icon:
/// a rounded blue tile with two overlapping paper rings and a clay lens.
class LogoMark extends StatelessWidget {
  const LogoMark({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _LensLogoPainter()),
    );
  }
}

class _LensLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 64.0; // the brand mark is drawn in a 64-unit box
    final tile = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height), Radius.circular(14 * s));
    canvas.drawRRect(tile, Paint()..color = BtwColors.moss);
    final r = 13 * s;
    final lc = Offset(26 * s, 32 * s), rc = Offset(38 * s, 32 * s);
    // Clay lens = the overlap of the two circles (right disk clipped to left).
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: lc, radius: r)));
    canvas.drawCircle(rc, r, Paint()..color = BtwColors.clay);
    canvas.restore();
    // Paper ring outlines on top.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5 * s
      ..color = BtwColors.cream;
    canvas.drawCircle(lc, r, ring);
    canvas.drawCircle(rc, r, ring);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// The lens logo + "Between." wordmark, shared across screens — mirrors the
/// website header.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 30});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        LogoMark(size: size * 0.95),
        SizedBox(width: size * 0.32),
        Text.rich(
          TextSpan(children: [
            TextSpan(
              text: 'Between',
              style: TextStyle(
                fontSize: size,
                fontWeight: FontWeight.w700,
                color: BtwColors.ink,
                letterSpacing: -0.5,
              ),
            ),
            TextSpan(
              text: '.',
              style: TextStyle(
                fontSize: size,
                fontWeight: FontWeight.w700,
                color: BtwColors.clay,
              ),
            ),
          ]),
        ),
      ],
    );
  }
}

/// Crisis resources footer: quietly present on every core screen — findable,
/// not alarming. Between is not a crisis service and says so.
class CrisisFooter extends StatelessWidget {
  const CrisisFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>().s;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Text(
        s.crisisFooter,
        textAlign: TextAlign.center,
        style: const TextStyle(
            fontSize: 12.5, color: BtwColors.inkSoft, height: 1.5),
      ),
    );
  }
}

/// EN | FR language switch — a compact two-option segmented toggle.
class LanguageToggle extends StatelessWidget {
  const LanguageToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    Widget seg(String label, AppLang value) {
      final selected = state.lang == value;
      return GestureDetector(
        onTap: () => state.setLang(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? BtwColors.moss : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : BtwColors.inkSoft,
            ),
          ),
        ),
      );
    }

    return Semantics(
      label: 'Language / Langue',
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: BtwColors.line),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          seg('EN', AppLang.en),
          seg('FR', AppLang.fr),
        ]),
      ),
    );
  }
}

/// Prominent crisis card, shown immediately when the server flags risk.
class CrisisCard extends StatelessWidget {
  const CrisisCard({super.key, required this.crisis});

  final Map<String, dynamic> crisis;

  @override
  Widget build(BuildContext context) {
    final lines = (crisis['lines'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: BtwColors.amberBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: BtwColors.amber),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            (crisis['message'] as String?) ??
                'If you\'re in immediate danger, please reach out now.',
            style: const TextStyle(
                fontSize: 15.5, height: 1.5, color: BtwColors.amberInk),
          ),
          const SizedBox(height: 14),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line['number'] as String? ?? '',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: BtwColors.amberInk,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Text(
                        line['name'] as String? ?? '',
                        style: const TextStyle(
                            fontSize: 13.5, color: BtwColors.amberInk),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
