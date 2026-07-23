import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme.dart';

/// Confirmation after sending. If the server flagged risk, crisis resources
/// appear immediately and prominently — independent of any therapist alert.
/// Otherwise a quiet confirmation with a grace-period undo.
class SentScreen extends StatefulWidget {
  const SentScreen({super.key, required this.result});

  final SendResult result;

  @override
  State<SentScreen> createState() => _SentScreenState();
}

class _SentScreenState extends State<SentScreen> {
  bool _undoing = false;

  Future<void> _undo() async {
    setState(() => _undoing = true);
    try {
      await context.read<AppState>().undoCheckIn(widget.result.checkIn.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Check-in removed. Nothing was kept.')));
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
        setState(() => _undoing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final crisis = widget.result.crisis;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              if (crisis != null) ...[
                CrisisCard(crisis: crisis),
                const SizedBox(height: 24),
                const Text(
                  'Your check-in was sent and your therapist has been '
                  'notified — but please don\'t wait on anyone if you\'re in '
                  'danger right now.',
                  style: TextStyle(
                      fontSize: 15, height: 1.6, color: BtwColors.inkSoft),
                ),
              ] else ...[
                const Center(
                  child: CircleAvatar(
                    radius: 38,
                    backgroundColor: BtwColors.mossLight,
                    child: Icon(Icons.check_rounded,
                        size: 42, color: BtwColors.moss),
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'Sent.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Your therapist will see this before your next session. '
                  'That\'s it — nothing else you need to do.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 15.5, height: 1.6, color: BtwColors.inkSoft),
                ),
              ],
              const Spacer(),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
              // No quiet undo for risk-flagged check-ins — the safety record
              // stays (history deletion in settings still applies).
              if (crisis == null) ...[
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _undoing ? null : _undo,
                  child: Text(
                    _undoing
                        ? 'Removing…'
                        : 'Didn\'t mean to send it? Undo (15 min)',
                    style: const TextStyle(color: BtwColors.inkSoft),
                  ),
                ),
              ],
              const CrisisFooter(),
            ],
          ),
        ),
      ),
    );
  }
}
