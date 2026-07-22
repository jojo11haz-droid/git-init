import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../app_state.dart';
import '../recording_bytes.dart';
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

  final _recorder = AudioRecorder();
  bool _recording = false;
  String? _recordingResult; // file path (mobile) or blob URL (web)
  int _recordSeconds = 0;
  Timer? _recordTimer;
  // Web records webm/opus via MediaRecorder; mobile records AAC in an m4a.
  String get _audioMime => kIsWeb ? 'audio/webm' : 'audio/mp4';

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

  @override
  void dispose() {
    _recordTimer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      _recordTimer?.cancel();
      final result = await _recorder.stop();
      setState(() {
        _recording = false;
        _recordingResult = result;
        _detailsOpen = true; // same optional step as after typing
      });
      return;
    }
    try {
      // On web, skip the hasPermission() pre-check: the browser enforces mic
      // permission inside start()'s getUserMedia anyway, and record_web's
      // permissions query has been seen to never resolve in some Chromium
      // environments. On mobile the pre-check is what triggers the OS prompt.
      if (!kIsWeb && !await _recorder.hasPermission()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Microphone access is off. You can type instead, or allow it in settings.')));
        }
        return;
      }
      String path = '';
      if (!kIsWeb) {
        final dir = await getTemporaryDirectory();
        path = '${dir.path}/between-checkin-${DateTime.now().millisecondsSinceEpoch}.m4a';
      }
      await _recorder.start(
        const RecordConfig(encoder: kIsWeb ? AudioEncoder.opus : AudioEncoder.aacLc),
        path: path,
      );
      setState(() {
        _recording = true;
        _recordingResult = null;
        _recordSeconds = 0;
      });
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _recordSeconds++);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Couldn\'t start recording — you can type instead. ($e)')));
      }
    }
  }

  String _fmtSeconds(int s) =>
      '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  Future<void> _send() async {
    final text = _text.text.trim();
    final app = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    if (_recording) await _toggleRecording(); // sending while recording = stop first
    final recording = _recordingResult;
    if (text.isEmpty && _tags.isEmpty && recording == null) {
      messenger.showSnackBar(const SnackBar(
          content: Text(
              'Say a little about what happened — record, type, or tap a tag.')));
      return;
    }
    setState(() => _sending = true);
    try {
      String? audioUploadId;
      if (recording != null) {
        final bytes = await readRecordingBytes(recording);
        audioUploadId = await app.uploadAudio(bytes, _audioMime);
      }
      final result = await app.sendCheckIn(
            text: text.isEmpty ? null : text,
            mood: _mood.round(),
            tags: _tags.toList(),
            audioUploadId: audioUploadId,
          );
      if (!mounted) return;
      _text.clear();
      setState(() {
        _tags.clear();
        _mood = 5;
        _detailsOpen = false;
        _recordingResult = null;
        _recordSeconds = 0;
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
                  const SizedBox(height: 12),
                  // Voice memo: record instead of (or as well as) typing.
                  Row(
                    children: [
                      SizedBox(
                        width: 54,
                        height: 54,
                        child: FilledButton(
                          onPressed: _sending ? null : _toggleRecording,
                          style: FilledButton.styleFrom(
                            shape: const CircleBorder(),
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(54, 54),
                            backgroundColor:
                                _recording ? BtwColors.clay : BtwColors.moss,
                          ),
                          child: Icon(
                            _recording
                                ? Icons.stop_rounded
                                : Icons.mic_rounded,
                            semanticLabel: _recording
                                ? 'Stop recording'
                                : 'Record a voice memo',
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _recording
                            ? Text(
                                'Recording… ${_fmtSeconds(_recordSeconds)} — tap to stop',
                                style: const TextStyle(
                                    fontSize: 13.5, color: BtwColors.clay),
                              )
                            : _recordingResult != null
                                ? Row(children: [
                                    const Icon(Icons.graphic_eq_rounded,
                                        size: 18, color: BtwColors.moss),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Voice memo attached (${_fmtSeconds(_recordSeconds)})',
                                      style: const TextStyle(
                                          fontSize: 13.5,
                                          color: BtwColors.moss),
                                    ),
                                    IconButton(
                                      tooltip: 'Remove recording',
                                      icon: const Icon(Icons.close_rounded,
                                          size: 18, color: BtwColors.inkSoft),
                                      onPressed: () => setState(() {
                                        _recordingResult = null;
                                        _recordSeconds = 0;
                                      }),
                                    ),
                                  ])
                                : const Text(
                                    'Or record a voice memo — whichever is '
                                    'easier right now.',
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: BtwColors.inkSoft),
                                  ),
                      ),
                    ],
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
