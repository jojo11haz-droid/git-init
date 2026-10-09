import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../body_map.dart';
import '../theme.dart';

/// A single past check-in in full: summary, your own words, mood, tags, the
/// pain map and the sore-area photo. Opened by tapping a row in history.
class CheckInDetailScreen extends StatelessWidget {
  const CheckInDetailScreen({super.key, required this.checkIn});

  final CheckIn checkIn;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>().s;
    final c = checkIn;
    final painMap = c.painMap;
    final showRaw = c.isAiSummary &&
        c.rawText != null &&
        c.rawText!.trim().isNotEmpty &&
        c.rawText!.trim() != c.summary.trim();
    return Scaffold(
      appBar: AppBar(title: Text(s.checkInDetail)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                Text(_when(c.submittedAt, s.isFr),
                    style: const TextStyle(
                        fontSize: 13, color: BtwColors.inkSoft)),
                const Spacer(),
                if (c.mood != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: BtwColors.mossLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(s.mood(c.mood!),
                        style: const TextStyle(
                            fontSize: 12.5, color: BtwColors.moss)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (c.isAiSummary)
              Row(children: [
                const Icon(Icons.auto_awesome, size: 14, color: BtwColors.moss),
                const SizedBox(width: 5),
                Text(s.aiSummary,
                    style: const TextStyle(fontSize: 12, color: BtwColors.moss)),
              ]),
            const SizedBox(height: 8),
            Text(c.summary,
                style: const TextStyle(fontSize: 16.5, height: 1.55)),
            if (showRaw) ...[
              const SizedBox(height: 18),
              Text(s.yourWords.toUpperCase(),
                  style: const TextStyle(
                      fontSize: 10.5,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w700,
                      color: BtwColors.inkSoft)),
              const SizedBox(height: 6),
              Text(c.rawText!.trim(),
                  style: const TextStyle(
                      fontSize: 15, height: 1.5, color: BtwColors.inkSoft)),
            ],
            if (c.hasAudio) ...[
              const SizedBox(height: 14),
              Row(children: [
                const Icon(Icons.graphic_eq_rounded,
                    size: 16, color: BtwColors.moss),
                const SizedBox(width: 6),
                Text(s.voiceMemo,
                    style: const TextStyle(fontSize: 13, color: BtwColors.moss)),
              ]),
            ],
            if (c.tags.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final tag in c.tags)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: BtwColors.cream,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: BtwColors.line),
                      ),
                      child: Text(s.tagLabel(tag),
                          style: const TextStyle(
                              fontSize: 12, color: BtwColors.inkSoft)),
                    ),
                ],
              ),
            ],
            if (painMap != null) ...[
              const SizedBox(height: 22),
              Text(s.painMapLabel.toUpperCase(),
                  style: const TextStyle(
                      fontSize: 10.5,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w700,
                      color: BtwColors.moss)),
              const SizedBox(height: 12),
              BodyMapView(map: painMap),
            ],
            if (c.hasPhoto) ...[
              const SizedBox(height: 22),
              Text(s.photoLabel.toUpperCase(),
                  style: const TextStyle(
                      fontSize: 10.5,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w700,
                      color: BtwColors.moss)),
              const SizedBox(height: 12),
              _Photo(id: c.id),
            ],
          ],
        ),
      ),
    );
  }

  String _when(DateTime t, bool fr) {
    const monthsEn = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    const monthsFr = [
      'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
      'juill.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'
    ];
    final month = (fr ? monthsFr : monthsEn)[t.month - 1];
    final mm = t.minute.toString().padLeft(2, '0');
    if (fr) return '${t.day} $month · ${t.hour}:$mm';
    final hour12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final ampm = t.hour < 12 ? 'am' : 'pm';
    return '$month ${t.day} · $hour12:$mm$ampm';
  }
}

class _Photo extends StatefulWidget {
  const _Photo({required this.id});
  final String id;

  @override
  State<_Photo> createState() => _PhotoState();
}

class _PhotoState extends State<_Photo> {
  late final Future<Uint8List> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().fetchCheckInPhoto(widget.id);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: FutureBuilder<Uint8List>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return Container(
              height: 160,
              alignment: Alignment.center,
              color: BtwColors.cream,
              child: const CircularProgressIndicator(color: BtwColors.moss),
            );
          }
          if (snap.hasError || snap.data == null) {
            return Container(
              height: 80,
              alignment: Alignment.center,
              color: BtwColors.cream,
              child: Text(context.read<AppState>().s.photoUnavailable,
                  style: const TextStyle(
                      fontSize: 13, color: BtwColors.inkSoft)),
            );
          }
          return Image.memory(snap.data!, fit: BoxFit.cover,
              width: double.infinity);
        },
      ),
    );
  }
}
