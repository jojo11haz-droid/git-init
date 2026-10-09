import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme.dart';

/// A warm two-step intro shown once, right after a new account is created, so
/// the person knows what Between is before their first check-in.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next(int last) {
    if (_page >= last) {
      context.read<AppState>().finishOnboarding();
    } else {
      _controller.nextPage(
          duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>().s;
    final pages = <_Slide>[
      _Slide(Icons.edit_note_rounded, s.onbTitle1, s.onbBody1),
      _Slide(Icons.insights_rounded, s.onbTitle2, s.onbBody2),
      _Slide(Icons.lock_outline_rounded, s.onbTitle3, s.onbBody3),
    ];
    final last = pages.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: () => context.read<AppState>().finishOnboarding(),
                child: Text(s.skip,
                    style: const TextStyle(color: BtwColors.inkSoft)),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => _slideView(pages[i]),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < pages.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _page ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _page ? BtwColors.moss : BtwColors.line,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 20, 28, 20),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => _next(last),
                  child: Text(_page >= last ? s.onbStart : s.onbNext),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slideView(_Slide slide) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 20, 36, 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: const BoxDecoration(
                color: BtwColors.mossLight, shape: BoxShape.circle),
            child: Icon(slide.icon, size: 40, color: BtwColors.moss),
          ),
          const SizedBox(height: 28),
          Text(slide.title,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Text(slide.body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 16, height: 1.55, color: BtwColors.inkSoft)),
        ],
      ),
    );
  }
}

class _Slide {
  _Slide(this.icon, this.title, this.body);
  final IconData icon;
  final String title, body;
}
