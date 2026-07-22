import 'package:flutter/material.dart';

/// Between's patient-side palette: same moss green as the therapist web app
/// so the brand is recognizable, but on a warmer cream — the softer sibling.
class BtwColors {
  static const cream = Color(0xFFFBF6EF);
  static const moss = Color(0xFF4C6B58);
  static const mossLight = Color(0xFFDCE6DE);
  static const ink = Color(0xFF1F2D28);
  static const inkSoft = Color(0xFF5B6B62);
  static const line = Color(0xFFE6DFD3);
  static const clay = Color(0xFFB5654F);
  static const amber = Color(0xFFC97A2C);
  static const amberBg = Color(0xFFFBEEDD);
  static const amberInk = Color(0xFF7A4A19);
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

/// The "Between." wordmark, shared across screens.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 30});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
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
            color: BtwColors.moss,
          ),
        ),
      ]),
    );
  }
}

/// Crisis resources footer: quietly present on every core screen — findable,
/// not alarming. Between is not a crisis service and says so.
class CrisisFooter extends StatelessWidget {
  const CrisisFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Text(
        'Between is not a crisis service. If you\'re in immediate danger or '
        'thinking about suicide, call or text 988, or call 911.',
        textAlign: TextAlign.center,
        style: const TextStyle(
            fontSize: 12.5, color: BtwColors.inkSoft, height: 1.5),
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
