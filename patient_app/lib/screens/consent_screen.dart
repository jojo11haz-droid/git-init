import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme.dart';

/// Onboarding + consent. This gates everything: no check-in can be sent until
/// the patient has read this and made an explicit choice. The AI toggle is
/// OFF by default (privacy-by-default, Law 25), and turning it on is framed
/// honestly as profiling of health information.
class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key});

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  bool _aiEnabled = false; // defaulted OFF — never pre-checked
  bool _agreed = false;
  bool _busy = false;
  String? _error;

  Future<void> _continue() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AppState>().recordConsent(aiEnabled: _aiEnabled);
      // The gate in main.dart moves to the check-in screen on its own.
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = context.watch<AppState>().patient?.firstName ?? '';
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(28),
          children: [
            const SizedBox(height: 8),
            const Wordmark(),
            const SizedBox(height: 20),
            Text(
              'Before you start, $name — how Between uses your check-ins.',
              style: const TextStyle(
                  fontSize: 24, fontWeight: FontWeight.w700, height: 1.3),
            ),
            const SizedBox(height: 18),
            const _Bullet(
                'Your check-ins are shared with your therapist as short '
                'summaries — not always the raw recording.'),
            const _Bullet(
                'If you turn on AI summaries below, an AI model analyzes what '
                'you send to write the summary and to find patterns over time '
                '(mood, themes, timing). Under Quebec\'s privacy law (Law 25), '
                'this counts as "profiling" of your health information.'),
            const _Bullet(
                'You can leave it off and still send check-ins — they\'ll go '
                'to your therapist exactly as you wrote them, with no AI '
                'analysis.'),
            const _Bullet(
                'You can see everything the app has on file about you at any '
                'time, change this choice, and ask for your history to be '
                'deleted.'),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: BtwColors.line),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('AI summaries & trends',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                        SizedBox(height: 4),
                        Text('Off by default. Your choice, changeable anytime.',
                            style: TextStyle(
                                fontSize: 13, color: BtwColors.inkSoft)),
                      ],
                    ),
                  ),
                  Switch(
                    value: _aiEnabled,
                    activeThumbColor: BtwColors.moss,
                    onChanged: (v) => setState(() => _aiEnabled = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: BtwColors.amberBg,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: BtwColors.amber),
              ),
              child: const Text(
                'Between is not a crisis or emergency service. If you\'re in '
                'immediate danger or thinking about suicide, call or text 988 '
                '(Suicide Crisis Helpline) or call 911 — don\'t wait on this '
                'app.',
                style: TextStyle(
                    fontSize: 13.5, height: 1.5, color: BtwColors.amberInk),
              ),
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              value: _agreed,
              onChanged: (v) => setState(() => _agreed = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              activeColor: BtwColors.moss,
              title: const Text(
                'I understand how my check-ins are used and processed, and I '
                'consent to that use as described above.',
                style: TextStyle(fontSize: 14, height: 1.5),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(_error!,
                    style:
                        const TextStyle(color: BtwColors.clay, fontSize: 14)),
              ),
            FilledButton(
              onPressed: (_agreed && !_busy) ? _continue : null,
              child: Text(_busy ? 'Saving…' : 'Continue'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 7),
            child: Icon(Icons.circle, size: 7, color: BtwColors.moss),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 14.5, height: 1.55)),
          ),
        ],
      ),
    );
  }
}
