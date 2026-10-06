import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../app_state.dart';
import '../body_map.dart';
import '../discipline.dart';
import '../recording_bytes.dart';
import '../theme.dart';
import 'history_screen.dart';
import 'sent_screen.dart';
import 'settings_screen.dart';

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
  Map<String, int> _painMap = {}; // "view:region" -> 1..10, physical disciplines
  Uint8List? _photoBytes; // optional sore-area photo, uploaded on send
  double _mood = 5;
  bool _detailsOpen = false;
  bool _sending = false;
  // "Write or speak" (free) vs. "Answer questions" (guided), mirroring the site.
  bool _questionsMode = false;
  List<TextEditingController> _answerCtrls = [];
  // "Can't decide?" options — let Between read mood/topic from the check-in.
  bool _moodEstimate = false; // true = let Between estimate the mood
  bool _topicAuto = false; // true = let Between pick the theme

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
    for (final c in _answerCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  /// Lazily size the per-question controllers to the discipline's prompts.
  void _ensureAnswerCtrls(int n) {
    if (_answerCtrls.length == n) return;
    for (final c in _answerCtrls) {
      c.dispose();
    }
    _answerCtrls = List.generate(n, (_) => TextEditingController());
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
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.read<AppState>().s.micOff)));
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
            content: Text(context.read<AppState>().s.recordFailed(e.toString()))));
      }
    }
  }

  String _fmtSeconds(int s) =>
      '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  Future<void> _pickPhoto() async {
    final s = context.read<AppState>().s;
    final messenger = ScaffoldMessenger.of(context);
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: BtwColors.cream,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined,
                  color: BtwColors.moss),
              title: Text(s.takePhoto),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            ListTile(
              leading:
                  const Icon(Icons.photo_library_outlined, color: BtwColors.moss),
              title: Text(s.chooseFromLibrary),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null) return;
    try {
      final file = await ImagePicker()
          .pickImage(source: source, maxWidth: 1600, imageQuality: 80);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() => _photoBytes = bytes); // re-encoded to JPEG by the picker
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _send() async {
    final app = context.read<AppState>();
    final s = app.s;
    final messenger = ScaffoldMessenger.of(context);
    if (_recording) await _toggleRecording(); // sending while recording = stop first
    final recording = _recordingResult;
    // In questions mode, stitch each answered prompt back into one check-in,
    // the same shape the server reads as a guided ("questions") entry.
    String text;
    String? inputMode;
    if (_questionsMode) {
      final effProfile = app.previewCategory != null
          ? profileByKey(app.previewCategory!)
          : profileFor(app.patient!);
      final qs = questionsFor(effProfile, s.isFr);
      final parts = <String>[];
      for (var i = 0; i < qs.length && i < _answerCtrls.length; i++) {
        final a = _answerCtrls[i].text.trim();
        if (a.isNotEmpty) parts.add('${qs[i]}\n$a');
      }
      text = parts.join('\n\n');
      inputMode = 'questions';
    } else {
      text = _text.text.trim();
    }
    if (text.isEmpty &&
        _tags.isEmpty &&
        recording == null &&
        _painMap.isEmpty &&
        _photoBytes == null) {
      messenger.showSnackBar(SnackBar(content: Text(s.saySomething)));
      return;
    }
    setState(() => _sending = true);
    try {
      String? audioUploadId;
      if (recording != null) {
        final bytes = await readRecordingBytes(recording);
        audioUploadId = await app.uploadAudio(bytes, _audioMime);
      }
      String? photoUploadId;
      if (_photoBytes != null) {
        photoUploadId = await app.uploadPhoto(_photoBytes!, 'image/jpeg');
      }
      final result = await app.sendCheckIn(
            text: text.isEmpty ? null : text,
            mood: _moodEstimate ? null : _mood.round(),
            tags: _topicAuto ? const <String>[] : _tags.toList(),
            audioUploadId: audioUploadId,
            photoUploadId: photoUploadId,
            painMap: _painMap.isEmpty ? null : _painMap,
            inputMode: inputMode,
          );
      if (!mounted) return;
      _text.clear();
      for (final c in _answerCtrls) {
        c.clear();
      }
      setState(() {
        _tags.clear();
        _painMap = {};
        _photoBytes = null;
        _mood = 5;
        _moodEstimate = false;
        _topicAuto = false;
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
    final state = context.watch<AppState>();
    final s = state.s;
    final patient = state.patient!;
    // Normally derived from the account; the Settings preview switcher can
    // override it so you can see any discipline's check-in.
    final profile = state.previewCategory != null
        ? profileByKey(state.previewCategory!)
        : profileFor(patient);
    final aiOn = patient.aiConsentEnabled; // "let Between decide" needs AI on
    _ensureAnswerCtrls(questionsFor(profile, s.isFr).length);
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
                    tooltip: s.myHistory,
                    icon: const Icon(Icons.history_rounded,
                        color: BtwColors.inkSoft),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const HistoryScreen()),
                    ),
                  ),
                  IconButton(
                    tooltip: s.myDataSettings,
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
                    s.hi(patient.firstName),
                    style: const TextStyle(
                        fontSize: 30, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    s.howAreThings,
                    style: const TextStyle(
                        fontSize: 16.5,
                        color: BtwColors.inkSoft,
                        height: 1.5),
                  ),
                  const SizedBox(height: 18),
                  // Write/speak vs. answer a few guided questions — the same
                  // choice the website offers, flavoured per discipline.
                  _ModeToggle(
                    questionsMode: _questionsMode,
                    writeLabel: s.writeOrSpeak,
                    questionsLabel: s.answerQuestions,
                    onChanged: (q) => setState(() => _questionsMode = q),
                  ),
                  const SizedBox(height: 16),
                  if (!_questionsMode) ...[
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
                      decoration: InputDecoration(
                        hintText: s.tellItHint,
                        hintStyle: const TextStyle(color: BtwColors.inkSoft),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        counterText: '',
                        contentPadding: const EdgeInsets.all(16),
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
                            semanticLabel:
                                _recording ? s.stopRecording : s.recordVoice,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _recording
                            ? Text(
                                s.recordingElapsed(_fmtSeconds(_recordSeconds)),
                                style: const TextStyle(
                                    fontSize: 13.5, color: BtwColors.clay),
                              )
                            : _recordingResult != null
                                ? Row(children: [
                                    const Icon(Icons.graphic_eq_rounded,
                                        size: 18, color: BtwColors.moss),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        s.voiceAttached(
                                            _fmtSeconds(_recordSeconds)),
                                        style: const TextStyle(
                                            fontSize: 13.5,
                                            color: BtwColors.moss),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: s.close,
                                      icon: const Icon(Icons.close_rounded,
                                          size: 18, color: BtwColors.inkSoft),
                                      onPressed: () => setState(() {
                                        _recordingResult = null;
                                        _recordSeconds = 0;
                                      }),
                                    ),
                                  ])
                                : Text(
                                    s.orRecord,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        color: BtwColors.inkSoft),
                                  ),
                      ),
                    ],
                  ),
                  ] else ...[
                    // Guided questions, tailored to the discipline.
                    for (var i = 0;
                        i < questionsFor(profile, s.isFr).length;
                        i++) ...[
                      Text(questionsFor(profile, s.isFr)[i],
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: BtwColors.line),
                        ),
                        padding: const EdgeInsets.all(4),
                        child: TextField(
                          controller: _answerCtrls[i],
                          minLines: 2,
                          maxLines: 6,
                          maxLength: 2000,
                          style: const TextStyle(fontSize: 15.5, height: 1.45),
                          decoration: InputDecoration(
                            hintText: s.yourAnswerHint,
                            hintStyle:
                                const TextStyle(color: BtwColors.inkSoft),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            counterText: '',
                            contentPadding: const EdgeInsets.all(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                  ],
                  const SizedBox(height: 16),
                  // Physical disciplines: a tap-where-it-hurts body map.
                  if (profile.isBody) ...[
                    Text(s.whereHurts,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    BodyMap(
                      isFr: s.isFr,
                      onChanged: (m) => _painMap = m,
                    ),
                    const SizedBox(height: 16),
                    // Optional photo of the sore area.
                    if (_photoBytes == null)
                      OutlinedButton.icon(
                        onPressed: _sending ? null : _pickPhoto,
                        icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                        label: Text(s.addSorePhoto),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: BtwColors.moss,
                          side: const BorderSide(color: BtwColors.line),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                      )
                    else
                      Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(
                              _photoBytes!,
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(s.photoAttached,
                                style: const TextStyle(
                                    fontSize: 13.5, color: BtwColors.moss)),
                          ),
                          IconButton(
                            tooltip: s.close,
                            icon: const Icon(Icons.close_rounded,
                                size: 18, color: BtwColors.inkSoft),
                            onPressed: () =>
                                setState(() => _photoBytes = null),
                          ),
                        ],
                      ),
                    const SizedBox(height: 20),
                  ],
                  // Optional, after writing — never a gate.
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 250),
                    crossFadeState: _detailsOpen
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    firstChild: TextButton(
                      onPressed: () => setState(() => _detailsOpen = true),
                      child: Text(s.addMoodTags,
                          style: const TextStyle(color: BtwColors.moss)),
                    ),
                    secondChild: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.moodRightNow,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        // "I'll set it / Let Between estimate" — only when AI
                        // summaries are on, since that's what reads it.
                        if (aiOn) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: _MiniToggle(
                              leftLabel: s.illSetIt,
                              rightLabel: s.letBetweenEstimate,
                              rightSelected: _moodEstimate,
                              onChanged: (v) =>
                                  setState(() => _moodEstimate = v),
                            ),
                          ),
                        ],
                        if (_moodEstimate)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Text(s.betweenWillReadMood,
                                style: const TextStyle(
                                    fontSize: 13,
                                    color: BtwColors.inkSoft,
                                    height: 1.4)),
                          )
                        else
                          Row(
                            children: [
                              Text(s.low,
                                  style: const TextStyle(
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
                              Text(s.high,
                                  style: const TextStyle(
                                      fontSize: 12, color: BtwColors.inkSoft)),
                            ],
                          ),
                        const SizedBox(height: 8),
                        Text(s.anythingFits,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        if (aiOn) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: _MiniToggle(
                              leftLabel: s.illPick,
                              rightLabel: s.notSureYet,
                              rightSelected: _topicAuto,
                              onChanged: (v) => setState(() {
                                _topicAuto = v;
                                if (v) _tags.clear();
                              }),
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        if (_topicAuto)
                          Text(s.betweenWillPickTopic,
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: BtwColors.inkSoft,
                                  height: 1.4))
                        else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final tag in profile.themes)
                              FilterChip(
                                label: Text(s.tagLabel(tag)),
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
                    child: Text(_sending
                        ? s.sending
                        : s.sendToProvider(profile.providerKey)),
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

/// A small two-option segmented control: write/speak vs. answer questions.
class _ModeToggle extends StatelessWidget {
  const _ModeToggle({
    required this.questionsMode,
    required this.writeLabel,
    required this.questionsLabel,
    required this.onChanged,
  });

  final bool questionsMode;
  final String writeLabel;
  final String questionsLabel;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: BtwColors.mossLight,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _seg(writeLabel, !questionsMode, () => onChanged(false)),
          _seg(questionsLabel, questionsMode, () => onChanged(true)),
        ],
      ),
    );
  }

  Widget _seg(String label, bool active, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: active ? BtwColors.moss : BtwColors.inkSoft,
            ),
          ),
        ),
      ),
    );
  }
}

/// A compact inline two-option switch, e.g. "I'll set it · Let Between
/// estimate", used for the "can't decide?" mood and topic options.
class _MiniToggle extends StatelessWidget {
  const _MiniToggle({
    required this.leftLabel,
    required this.rightLabel,
    required this.rightSelected,
    required this.onChanged,
  });

  final String leftLabel;
  final String rightLabel;
  final bool rightSelected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: BtwColors.mossLight,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _pill(leftLabel, !rightSelected, () => onChanged(false)),
          _pill(rightLabel, rightSelected, () => onChanged(true)),
        ],
      ),
    );
  }

  Widget _pill(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: active ? BtwColors.moss : BtwColors.inkSoft,
          ),
        ),
      ),
    );
  }
}
