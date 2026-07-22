import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme.dart';

/// The patient's own history — every check-in on file, exactly what the
/// therapist can see. AI summaries are labeled, and each can be flagged as
/// inaccurate (the right to contest an automated output).
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<CheckIn>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().fetchHistory();
  }

  Future<void> _flag(CheckIn checkIn) async {
    try {
      await context.read<AppState>().flagInaccurate(checkIn.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Flagged. Your therapist will see this summary is marked as '
              'not accurate.')));
      setState(() => _future = context.read<AppState>().fetchHistory());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  String _when(DateTime t) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final hour12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final ampm = t.hour < 12 ? 'am' : 'pm';
    return '${months[t.month - 1]} ${t.day} · '
        '$hour12:${t.minute.toString().padLeft(2, '0')}$ampm';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My check-ins')),
      body: SafeArea(
        child: FutureBuilder<List<CheckIn>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text(snapshot.error.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: BtwColors.inkSoft)),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(
                  child: CircularProgressIndicator(color: BtwColors.moss));
            }
            final items = snapshot.data!;
            if (items.isEmpty) {
              return const Center(
                child: Text('No check-ins yet.',
                    style: TextStyle(color: BtwColors.inkSoft, fontSize: 15)),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final c = items[i];
                return Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: BtwColors.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(_when(c.submittedAt),
                              style: const TextStyle(
                                  fontSize: 12.5, color: BtwColors.inkSoft)),
                          const Spacer(),
                          if (c.mood != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 3),
                              decoration: BoxDecoration(
                                color: BtwColors.mossLight,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text('mood ${c.mood}/10',
                                  style: const TextStyle(
                                      fontSize: 12, color: BtwColors.moss)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(c.summary,
                          style:
                              const TextStyle(fontSize: 15, height: 1.5)),
                      if (c.tags.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final tag in c.tags)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 9, vertical: 3),
                                decoration: BoxDecoration(
                                  color: BtwColors.cream,
                                  borderRadius: BorderRadius.circular(12),
                                  border:
                                      Border.all(color: BtwColors.line),
                                ),
                                child: Text(tag,
                                    style: const TextStyle(
                                        fontSize: 11.5,
                                        color: BtwColors.inkSoft)),
                              ),
                          ],
                        ),
                      ],
                      if (c.isAiSummary) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Icon(Icons.auto_awesome,
                                size: 14, color: BtwColors.inkSoft),
                            const SizedBox(width: 5),
                            const Text('AI summary',
                                style: TextStyle(
                                    fontSize: 12, color: BtwColors.inkSoft)),
                            const Spacer(),
                            c.flaggedInaccurate
                                ? const Text('Flagged as not accurate',
                                    style: TextStyle(
                                        fontSize: 12, color: BtwColors.clay))
                                : TextButton(
                                    style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: const Size(0, 30),
                                    ),
                                    onPressed: () => _flag(c),
                                    child: const Text(
                                        'This isn\'t accurate',
                                        style: TextStyle(
                                            fontSize: 12.5,
                                            color: BtwColors.clay)),
                                  ),
                          ],
                        ),
                      ],
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
