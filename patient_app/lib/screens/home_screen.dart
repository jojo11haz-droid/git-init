import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme.dart';
import 'history_screen.dart';
import 'sent_screen.dart';
import 'settings_screen.dart';

const _quickTags = [
  'Sleep', 'Work', 'Conflict', 'Craving', 'Panic', 'Family', 'Win', 'Social',
];

/// The core loop: one calm screen, one main thing to do. Writing comes first;
/// mood and tags are a light optional step revealed afterwards — never a form
/// standing between the person and saying what happened.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _text = TextEditingController();
  final Set<String> _tags = {};
  double _mood = 5;
  bool _detailsOpen = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(() {
      // Reveal the optional mood/tags step once they've started writing.
      if (_text.text.trim().isNotEmpty && !_detailsOpen) {
        setState(() => _detailsOpen = true);
      }
    });
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty && _tags.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Say a little about what happened, or tap a tag first.')));
      return;
    }
    setState(() => _sending = true);
    try {
      final result = await context.read<AppState>().sendCheckIn(
            text: text.isEmpty ? null : text,
            mood: _mood.round(),
            tags: _tags.toList(),
          );
      if (!mounted) return;
      _text.clear();
      setState(() {
        _tags.clear();
        _mood = 5;
        _detailsOpen = false;
      });
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => SentScreen(result: result)),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final patient = context.watch<AppState>().patient!;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 16, 16, 0),
              child: Row(
                children: [
                  const Wordmark(size: 24),
                  const Spacer(),
                  IconButton(
                    tooltip: 'My history',
                    icon: const Icon(Icons.history_rounded,
                        color: BtwColors.inkSoft),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const HistoryScreen()),
                    ),
                  ),
                  IconButton(
                    tooltip: 'My data & settings',
                    icon: const Icon(Icons.tune_rounded,
                        color: BtwColors.inkSoft),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(28, 18, 28, 12),
                children: [
                  Text(
                    'Hi ${patient.firstName}.',
                    style: const TextStyle(
                        fontSize: 30, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'How are things right now? Take your time.',
                    style: TextStyle(
                        fontSize: 16.5,
                        color: BtwColors.inkSoft,
                        height: 1.5),
                  ),
                  const SizedBox(height: 22),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(color: BtwColors.line),
                    ),
                    padding: const EdgeInsets.all(6),
                    child: TextField(
                      controller: _text,
                      minLines: 5,
                      maxLines: 10,
                      maxLength: 4000,
                      style: const TextStyle(fontSize: 16.5, height: 1.5),
                      decoration: const InputDecoration(
                        hintText: 'Tell it like it happened…',
                        hintStyle: TextStyle(color: BtwColors.inkSoft),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        counterText: '',
                        contentPadding: EdgeInsets.all(16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Voice memos are coming soon — for now, typing it out works '
                    'just as well.',
                    style:
                        TextStyle(fontSize: 12.5, color: BtwColors.inkSoft),
                  ),
                  const SizedBox(height: 16),
                  // Optional, after writing — never a gate.
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 250),
                    crossFadeState: _detailsOpen
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    firstChild: TextButton(
                      onPressed: () => setState(() => _detailsOpen = true),
                      child: const Text('Add mood & tags (optional)',
                          style: TextStyle(color: BtwColors.moss)),
                    ),
                    secondChild: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Mood right now',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        Row(
                          children: [
                            const Text('Low',
                                style: TextStyle(
                                    fontSize: 12, color: BtwColors.inkSoft)),
                            Expanded(
                              child: Slider(
                                value: _mood,
                                min: 1,
                                max: 10,
                                divisions: 9,
                                activeColor: BtwColors.moss,
                                label: _mood.round().toString(),
                                onChanged: (v) => setState(() => _mood = v),
                              ),
                            ),
                            const Text('High',
                                style: TextStyle(
                                    fontSize: 12, color: BtwColors.inkSoft)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text('Anything that fits (optional)',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final tag in _quickTags)
                              FilterChip(
                                label: Text(tag),
                                selected: _tags.contains(tag),
                                color: WidgetStateProperty.resolveWith(
                                  (states) =>
                                      states.contains(WidgetState.selected)
                                          ? BtwColors.moss
                                          : Colors.white,
                                ),
                                checkmarkColor: Colors.white,
                                labelStyle: TextStyle(
                                  color: _tags.contains(tag)
                                      ? Colors.white
                                      : BtwColors.inkSoft,
                                ),
                                backgroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  side:
                                      const BorderSide(color: BtwColors.line),
                                ),
                                onSelected: (sel) => setState(() {
                                  sel ? _tags.add(tag) : _tags.remove(tag);
                                }),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: _sending ? null : _send,
                    child: Text(_sending ? 'Sending…' : 'Send to my therapist'),
                  ),
                ],
              ),
            ),
            const CrisisFooter(),
          ],
        ),
      ),
    );
  }
}
