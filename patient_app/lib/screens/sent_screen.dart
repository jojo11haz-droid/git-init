import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../strings.dart';
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
    final s = context.read<AppState>().s;
    setState(() => _undoing = true);
    try {
      await context.read<AppState>().undoCheckIn(widget.result.checkIn.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.removed)));
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
    final s = context.watch<AppState>().s;
    final crisis = widget.result.crisis;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 24),
                      if (crisis != null) ...[
                        CrisisCard(crisis: crisis),
                        const SizedBox(height: 24),
                        Text(
                          s.sentCrisisNote,
                          style: const TextStyle(
                              fontSize: 15,
                              height: 1.6,
                              color: BtwColors.inkSoft),
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
                        Text(
                          s.sent,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 28, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          s.sentReassure,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 15.5,
                              height: 1.6,
                              color: BtwColors.inkSoft),
                        ),
                        // The AI summary the server just produced (only when
                        // the patient has AI consent on, so model_version is
                        // set). Mirrors the "AI summary" card on the website.
                        if (widget.result.checkIn.isAiSummary) ...[
                          const SizedBox(height: 24),
                          _AiSummaryCard(
                              checkIn: widget.result.checkIn, s: s),
                        ],
                      ],
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(s.done),
              ),
              // No quiet undo for risk-flagged check-ins — the safety record
              // stays (history deletion in settings still applies).
              if (crisis == null) ...[
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _undoing ? null : _undo,
                  child: Text(
                    _undoing ? s.removing : s.undo,
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

/// The AI summary of a just-sent check-in, laid out like the website's
/// "AI summary" card: a quiet mono label, the neutral summary, the mood
/// Between read, and the theme tags it picked up.
class _AiSummaryCard extends StatelessWidget {
  const _AiSummaryCard({required this.checkIn, required this.s});

  final CheckIn checkIn;
  final S s;

  @override
  Widget build(BuildContext context) {
    final tags = checkIn.tags;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: BtwColors.mossLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BtwColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded,
                  size: 14, color: BtwColors.moss),
              const SizedBox(width: 6),
              Text(
                s.aiSummaryLabel.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w700,
                  color: BtwColors.moss,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            checkIn.summary,
            style: const TextStyle(
                fontSize: 14.5, height: 1.5, color: BtwColors.ink),
          ),
          if (checkIn.moodInferred && checkIn.mood != null) ...[
            const SizedBox(height: 10),
            Text(
              '${s.aiReadMood} ${checkIn.mood}/10',
              style: const TextStyle(
                  fontSize: 12.5, color: BtwColors.inkSoft),
            ),
          ],
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in tags)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: BtwColors.line),
                    ),
                    child: Text(
                      s.tagLabel(t),
                      style: const TextStyle(
                          fontSize: 12, color: BtwColors.inkSoft),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Text(
            s.aiSummaryNote,
            style: const TextStyle(
                fontSize: 11.5, height: 1.4, color: BtwColors.inkSoft),
          ),
        ],
      ),
    );
  }
}
