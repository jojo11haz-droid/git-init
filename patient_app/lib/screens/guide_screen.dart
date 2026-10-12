import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme.dart';
import 'onboarding_screen.dart';

/// "How to use Between" — a plain, scrollable how-to for the person checking in,
/// mirroring the Guide on the website. Reachable anytime from the home screen,
/// and offers to replay the first-run intro.
class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>().s;
    final steps = <String>[
      s.guideStep1,
      s.guideStep2,
      s.guideStep3,
      s.guideStep4,
      s.guideStep5,
      s.guideStep6,
    ];
    return Scaffold(
      appBar: AppBar(title: Text(s.guideTitle), actions: const [
        Padding(
            padding: EdgeInsets.only(right: 12),
            child: Center(child: LanguageToggle())),
      ]),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          children: [
            Text(s.guideSub,
                style: const TextStyle(
                    fontSize: 15.5, height: 1.55, color: BtwColors.inkSoft)),
            const SizedBox(height: 24),
            for (var i = 0; i < steps.length; i++) ...[
              _Step(n: i + 1, text: steps[i]),
              if (i != steps.length - 1) const SizedBox(height: 16),
            ],
            const SizedBox(height: 26),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: BtwColors.cream,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: BtwColors.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.guideGoodTitle,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(s.guideGoodBody,
                      style: const TextStyle(
                          fontSize: 13.5,
                          height: 1.55,
                          color: BtwColors.inkSoft)),
                ],
              ),
            ),
            const SizedBox(height: 22),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const OnboardingScreen(replay: true)),
              ),
              icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
              label: Text(s.guideReplayIntro),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.text});
  final int n;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration:
              const BoxDecoration(color: BtwColors.moss, shape: BoxShape.circle),
          child: Text('$n',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(text,
                style: const TextStyle(fontSize: 15, height: 1.5)),
          ),
        ),
      ],
    );
  }
}
