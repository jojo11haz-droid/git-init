import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb, compute;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart' show resolveApiUri;
import '../app_state.dart';
import '../body_map.dart';
import '../discipline.dart';
import '../recording_bytes.dart';
import '../strings.dart';
import '../theme.dart';
import 'coach_tour.dart';
import 'do_it_now_sheet.dart';
import 'documents_screen.dart';
import 'guide_screen.dart';
import 'history_screen.dart';
import 'progress_screen.dart';
import 'sent_screen.dart';
import 'settings_screen.dart';
import 'topics_screen.dart';

/// Shrink a photo before upload: scale the long edge to 1600px and re-encode as
/// JPEG, so a multi-MB phone photo becomes a few hundred KB. Keeps the backend
/// database (which stores photos as bytes) small. Top-level so it can run via
/// compute() off the UI thread; returns the original bytes on any failure or if
/// compression wouldn't help.
Uint8List _compressPhoto(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    final img.Image resized = (decoded.width > 1600 || decoded.height > 1600)
        ? (decoded.width >= decoded.height
            ? img.copyResize(decoded, width: 1600)
            : img.copyResize(decoded, height: 1600))
        : decoded;
    final out = Uint8List.fromList(img.encodeJpg(resized, quality: 82));
    return out.length < bytes.length ? out : bytes;
  } catch (_) {
    return bytes;
  }
}

/// The core loop: one calm screen, one main thing to do. Writing comes first;
/// mood and tags are a light optional step revealed afterwards — never a form
/// standing between the person and saying what happened.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver {
  final _text = TextEditingController();
  final Set<String> _tags = {};
  Map<String, int> _painMap = {}; // "view:region" -> 1..10, physical disciplines
  Map<String, String> _painSens = {}; // "view:region" -> sensation code
  List<HomeExercise> _exercises = []; // home program from the clinician
  List<ClinicianMessage> _messages = []; // notes from the professional + replies
  List<ClinicianMessage> get _proMessages =>
      _messages.where((m) => !m.fromClient).toList();
  bool _allMessages = false; // show earlier messages too
  final Set<String> _exDone = {}; // exercise ids ticked in this check-in
  String? _exStatus; // program in another app: 'yes' | 'some' | 'no'
  Uint8List? _photoBytes; // optional sore-area photo, uploaded on send
  double _mood = 5;
  bool _detailsOpen = false;
  bool _sending = false;
  // "Write or speak" (free) vs. "Answer questions" (guided), mirroring the site.
  bool _questionsMode = false;
  List<TextEditingController> _answerCtrls = [];
  // "Can't decide?" options — let Between read mood/topic from the check-in.
  bool _moodEstimate = false; // true = let Between estimate the mood / pain
  bool _painScale = false; // set each build from the discipline profile
  bool _topicAuto = false; // true = let Between pick the theme

  final _recorder = AudioRecorder();
  bool _recording = false;
  String? _recordingResult; // file path (mobile) or blob URL (web)
  int _recordSeconds = 0;
  Timer? _recordTimer;
  // Web records webm/opus via MediaRecorder; mobile records AAC in an m4a.
  String get _audioMime => kIsWeb ? 'audio/webm' : 'audio/mp4';

  // Spotlight-tour targets and guard.
  final _kComposer = GlobalKey();
  final _kProgress = GlobalKey();
  final _kHistory = GlobalKey();
  final _kHelp = GlobalKey();
  bool _tourActive = false;
  int _streak = 0;
  int _openTopics = 0; // things waiting for the next session

  @override
  void initState() {
    super.initState();
    _text.addListener(() {
      // Reveal the optional mood/tags step once they've started writing.
      if (_text.text.trim().isNotEmpty && !_detailsOpen) {
        setState(() => _detailsOpen = true);
      }
    });
    // Check-in streak for the habit chip — best-effort, never blocks the screen.
    _loadStreak();
    _loadExercises();
    _loadMessages();
    _loadTopics();
    // New messages from their professional show up when the app comes back
    // to the foreground (and on pull-to-refresh), not only on a fresh start.
    WidgetsBinding.instance.addObserver(this);
    // First run (after the intro): show the spotlight tour once.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final st = context.read<AppState>();
      if (!st.tourSeen && !st.showOnboarding) _startTour();
    });
  }

  // The checklist's title for the field (mirrors the website's wording).
  String _programTitle(S s, DisciplineProfile p) {
    switch (p.kind) {
      case CheckInKind.body:
        return s.homeExercises;
      case CheckInKind.nutrition:
        return s.habitsToPractise;
      case CheckInKind.recovery:
        return s.dailyPractices;
      case CheckInKind.school:
        return s.strategiesToPractise;
      case CheckInKind.mind:
      case CheckInKind.neuro:
        return s.practiceBetween;
    }
  }

  Widget _exerciseTile(HomeExercise e, S s) {
    final on = _exDone.contains(e.id);
    final desc = e.description;
    final dose = e.dosage;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => on ? _exDone.remove(e.id) : _exDone.add(e.id)),
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 8, 12, 10),
          decoration: BoxDecoration(
            color: on ? BtwColors.mossLight : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: on ? BtwColors.moss : BtwColors.line),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: on,
                activeColor: BtwColors.moss,
                visualDensity: VisualDensity.compact,
                onChanged: (v) => setState(
                    () => v == true ? _exDone.add(e.id) : _exDone.remove(e.id)),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(TextSpan(children: [
                        TextSpan(
                            text: e.name,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        if (dose != null && dose.isNotEmpty)
                          TextSpan(
                              text: '  $dose',
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: BtwColors.moss)),
                      ])),
                      if (desc != null && desc.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(desc,
                            style: const TextStyle(
                                fontSize: 12.5,
                                color: BtwColors.inkSoft,
                                height: 1.4)),
                      ],
                      // Open it with its how-to and a timer; Done ticks it.
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              visualDensity: VisualDensity.compact,
                              foregroundColor: BtwColors.moss),
                          icon: const Icon(Icons.play_circle_outline_rounded,
                              size: 18),
                          label: Text(s.doItNow),
                          onPressed: () async {
                            final done = await showDoItNow(context, e, s);
                            if (done && mounted) setState(() => _exDone.add(e.id));
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // The home exercise program, ticked off in the check-in. Best-effort.
  Future<void> _loadExercises() async {
    final app = context.read<AppState>();
    try {
      final list = await app.fetchExercises();
      if (!mounted) return;
      setState(() {
        _exercises = list;
        _exDone.removeWhere((id) => !list.any((e) => e.id == id));
      });
    } catch (_) {
      // No program (or offline): the checklist just stays hidden.
    }
  }

  // How many topics are waiting for the next session. Best-effort.
  Future<void> _loadTopics() async {
    final app = context.read<AppState>();
    if (!(app.patient?.hasClinician ?? false)) return;
    try {
      final list = await app.fetchTopics();
      if (!mounted) return;
      setState(() => _openTopics = list.where((t) => !t.discussed).length);
    } catch (_) {/* the tile just shows "Add a topic" */}
  }

  Widget _topicsTile(S s) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const TopicsScreen()),
        );
        if (!mounted) return;
        _loadTopics();
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: BtwColors.line),
        ),
        child: Row(
          children: [
            const Icon(Icons.forum_outlined, size: 20, color: BtwColors.moss),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.topicsTitle,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  Text(s.topicsWaiting(_openTopics),
                      style: const TextStyle(
                          fontSize: 12.5, color: BtwColors.inkSoft)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: BtwColors.inkSoft),
          ],
        ),
      ),
    );
  }

  Future<void> _loadMessages() async {
    final app = context.read<AppState>();
    try {
      final list = await app.fetchMessages();
      if (!mounted) return;
      setState(() => _messages = list);
      // Shown now, so mark them read (the professional sees "Read").
      if (list.any((m) => !m.fromClient && !m.isRead)) {
        await app.markMessagesRead();
      }
    } catch (_) {
      // No messages (or offline): the card just stays hidden.
    }
  }

  Widget _messageCard(ClinicianMessage m, S s, {bool canReply = false}) {
    final when = m.createdAt;
    final whenText = when == null
        ? ''
        : '${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: m.isRead ? BtwColors.line : BtwColors.moss,
            width: m.isRead ? 1 : 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                (m.isRead ? s.messageLabel : s.newMessage).toUpperCase(),
                style: const TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w600,
                    color: BtwColors.moss),
              ),
              const Spacer(),
              Text(whenText,
                  style:
                      const TextStyle(fontSize: 11.5, color: BtwColors.inkSoft)),
            ],
          ),
          const SizedBox(height: 6),
          Text(m.body, style: const TextStyle(fontSize: 15, height: 1.45)),
          for (final e in m.exercises) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: BoxDecoration(
                color: BtwColors.cream,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.dosage == null || e.dosage!.isEmpty
                        ? e.name
                        : '${e.name} · ${e.dosage}',
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                  if (e.description != null && e.description!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(e.description!,
                          style: const TextStyle(
                              fontSize: 12.5, color: BtwColors.inkSoft)),
                    ),
                ],
              ),
            ),
          ],
          // Their own replies to this message, oldest first.
          for (final r in _messages.reversed
              .where((x) => x.fromClient && x.replyTo == m.id)) ...[
            const SizedBox(height: 8),
            _replyBubble(r, s),
          ],
          if (canReply)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _openReply(m, s),
                icon: const Icon(Icons.reply_rounded, size: 18),
                label: Text(s.reply),
              ),
            ),
        ],
      ),
    );
  }

  Widget _replyBubble(ClinicianMessage r, S s) {
    final when = r.createdAt;
    final whenText = when == null
        ? ''
        : '${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: BtwColors.cream,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${s.you.toUpperCase()} · $whenText${r.isRead ? ' · ${s.seen}' : ''}',
            style: const TextStyle(
                fontSize: 10.5,
                letterSpacing: 0.5,
                fontWeight: FontWeight.w600,
                color: BtwColors.inkSoft),
          ),
          const SizedBox(height: 3),
          Text(r.body, style: const TextStyle(fontSize: 14, height: 1.4)),
        ],
      ),
    );
  }

  /// A sheet to write a reply to one of the professional's messages.
  Future<void> _openReply(ClinicianMessage m, S s) async {
    final app = context.read<AppState>();
    final result = await showModalBottomSheet<ReplyResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ReplySheet(app: app, replyTo: m.id, s: s),
    );
    if (result == null || !mounted) return;
    setState(() => _messages = [result.message, ..._messages]);
    if (result.showCrisis) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(s.replyCrisisTitle),
          content: Text(s.replyCrisisBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(s.ok),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _loadStreak() async {
    final app = context.read<AppState>();
    try {
      final items = await app.fetchHistory();
      if (!mounted) return;
      setState(() => _streak = _computeStreak(items));
    } catch (_) {
      // The streak is a nicety; a failed history fetch just hides the chip.
    }
  }

  // Consecutive calendar days with at least one check-in, with a one-day grace
  // so it doesn't reset the moment today's check-in isn't in yet.
  int _computeStreak(List<CheckIn> items) {
    if (items.isEmpty) return 0;
    final days = <String>{};
    for (final c in items) {
      final d = c.submittedAt;
      days.add('${d.year}-${d.month}-${d.day}');
    }
    String key(DateTime dt) => '${dt.year}-${dt.month}-${dt.day}';
    final now = DateTime.now();
    var cur = DateTime(now.year, now.month, now.day);
    if (!days.contains(key(cur))) {
      cur = cur.subtract(const Duration(days: 1));
      if (!days.contains(key(cur))) return 0;
    }
    var streak = 0;
    while (days.contains(key(cur))) {
      streak++;
      cur = cur.subtract(const Duration(days: 1));
    }
    return streak;
  }

  Widget _brandCard(Patient p) {
    final who = p.brandClinic.isNotEmpty ? p.brandClinic : (p.clinicianName ?? '');
    final logo = p.brandLogoUrl;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: BtwColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (logo != null || who.isNotEmpty)
            Row(
              children: [
                if (logo != null) ...[
                  ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxHeight: 40, maxWidth: 120),
                    child: Image.network(
                      resolveApiUri(logo).toString(),
                      fit: BoxFit.contain,
                      errorBuilder: (ctx, err, st) => const SizedBox.shrink(),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                if (who.isNotEmpty)
                  Expanded(
                    child: Text(who,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
          if (p.brandWelcome.isNotEmpty) ...[
            if (logo != null || who.isNotEmpty) const SizedBox(height: 10),
            Text(p.brandWelcome,
                style: const TextStyle(fontSize: 15, height: 1.5)),
          ],
        ],
      ),
    );
  }

  Widget _streakChip(S s) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 7, 15, 7),
        decoration: BoxDecoration(
          color: const Color(0xFFFBEEDD),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFFEAD9BE)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.local_fire_department,
                size: 18, color: Color(0xFFB8701F)),
            const SizedBox(width: 8),
            Text('$_streak',
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFB8701F))),
            const SizedBox(width: 6),
            Flexible(
              child: Text('${s.streakUnit(_streak)} · ${s.streakNote(_streak)}',
                  style: const TextStyle(
                      fontSize: 13, color: BtwColors.inkSoft)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launch(String uri) async {
    try {
      await launchUrl(Uri.parse(uri), mode: LaunchMode.externalApplication);
    } catch (_) {/* dialer/SMS not available on this device; ignore */}
  }

  // Standing support strip for a self-serve individual (no clinician to
  // notify): crisis resources always one tap away, framed calmly. Kept compact
  // (title + one row of buttons) so the check-in box below stays on the first
  // screen; the "not a crisis service" footer sits under the composer.
  Widget _supportCard(S s) {
    Widget btn(String label, String uri, {bool urgent = false}) {
      final text = Text(label,
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontWeight: FontWeight.w600, fontSize: 13, height: 1.2));
      final shape =
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(9));
      const pad = EdgeInsets.symmetric(horizontal: 6, vertical: 8);
      const minSize = Size(0, 44);
      // Equal columns; on a narrow phone a label wraps inside its button
      // instead of pushing a button onto a row of its own.
      return Expanded(
        child: urgent
            ? OutlinedButton(
                onPressed: () => _launch(uri),
                style: OutlinedButton.styleFrom(
                  foregroundColor: BtwColors.clay,
                  side: const BorderSide(color: BtwColors.clay),
                  padding: pad,
                  minimumSize: minSize,
                  shape: shape,
                ),
                child: text)
            : ElevatedButton(
                onPressed: () => _launch(uri),
                style: ElevatedButton.styleFrom(
                  backgroundColor: BtwColors.moss,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: pad,
                  minimumSize: minSize,
                  shape: shape,
                ),
                child: text),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: BtwColors.mossLight,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFC6D6EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.favorite_border, size: 17, color: BtwColors.moss),
              const SizedBox(width: 8),
              Flexible(
                child: Text(s.supportTitle,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: BtwColors.moss)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              btn(s.supportText988, 'sms:988'),
              const SizedBox(width: 6),
              btn(s.supportCall988, 'tel:988'),
              const SizedBox(width: 6),
              btn(s.supportEmergency, 'tel:911', urgent: true),
            ],
          ),
        ],
      ),
    );
  }

  List<CoachStep> _buildSteps(S s, String? providerKey) => [
        CoachStep(title: s.coachWelcomeTitle, body: s.coachWelcomeBody),
        CoachStep(
            targetKey: _kComposer,
            title: s.coachComposerTitle,
            body: s.coachComposerBody),
        CoachStep(
            targetKey: _kProgress,
            title: s.coachProgressTitle,
            body: s.coachProgressBody),
        CoachStep(
            targetKey: _kHistory,
            title: s.coachHistoryTitle,
            body: s.coachHistoryBody),
        CoachStep(
            targetKey: _kHelp,
            title: s.coachHelpTitle,
            body: s.coachHelpBody),
        CoachStep(
            title: s.coachDoneTitle, body: s.coachDoneBodyFor(providerKey)),
      ];

  void _startTour() {
    if (_tourActive) return;
    _tourActive = true;
    final app = context.read<AppState>();
    final s = app.s;
    // Who sees the check-ins (null = a solo account), for the last step.
    final providerKey =
        app.patient == null ? null : profileFor(app.patient!).providerKey;
    startCoachTour(
      context,
      strings: s,
      steps: _buildSteps(s, providerKey),
      onDone: () {
        _tourActive = false;
        if (mounted) context.read<AppState>().markTourSeen();
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadMessages();
      _loadExercises();
    }
  }

  Future<void> _refresh() async {
    await Future.wait([_loadMessages(), _loadExercises()]);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
        _exDone.isEmpty &&
        _exStatus == null &&
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
        // Shrink before upload so photos don't bloat the backend (it stores
        // them as bytes). Runs off the UI thread; falls back to the original.
        final toSend = await compute(_compressPhoto, _photoBytes!);
        photoUploadId = await app.uploadPhoto(toSend, 'image/jpeg');
      }
      final result = await app.sendCheckIn(
            text: text.isEmpty ? null : text,
            mood: _moodEstimate ? null : _mood.round(),
            tags: _topicAuto ? const <String>[] : _tags.toList(),
            audioUploadId: audioUploadId,
            photoUploadId: photoUploadId,
            painMap: _painMap.isEmpty ? null : _painMap,
            painSens: _painSens.isEmpty ? null : _painSens,
            inputMode: inputMode,
            painScale: _painScale,
            bodySex: _painMap.isEmpty ? null : bodyMapSex(),
            exercisesDone: _exDone.isEmpty ? null : _exDone.toList(),
            exerciseStatus:
                (app.patient?.exercisesExternal ?? false) ? _exStatus : null,
          );
      if (!mounted) return;
      _text.clear();
      for (final c in _answerCtrls) {
        c.clear();
      }
      setState(() {
        _tags.clear();
        _painMap = {};
        _painSens = {};
        _exDone.clear();
        _exStatus = null;
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
    // Replay requested from the Guide: start the tour after this frame.
    if (state.startTourRequested && !_tourActive) {
      state.clearTourRequest();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startTour();
      });
    }
    // Normally derived from the account; the Settings preview switcher can
    // override it so you can see any discipline's check-in.
    final profile = state.previewCategory != null
        ? profileByKey(state.previewCategory!)
        : profileFor(patient);
    final aiOn = patient.aiConsentEnabled; // "let Between decide" needs AI on
    // Physical rehab rates pain (high = worse), not mood (high = better).
    final painScale = profile.isPainScale;
    _painScale = painScale;
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
                    key: _kProgress,
                    tooltip: s.myProgress,
                    icon: const Icon(Icons.insights_rounded,
                        color: BtwColors.inkSoft),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ProgressScreen()),
                    ),
                  ),
                  IconButton(
                    key: _kHistory,
                    tooltip: s.myHistory,
                    icon: const Icon(Icons.history_rounded,
                        color: BtwColors.inkSoft),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const HistoryScreen()),
                    ),
                  ),
                  IconButton(
                    tooltip: s.documentsTooltip,
                    icon: const Icon(Icons.folder_outlined,
                        color: BtwColors.inkSoft),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const DocumentsScreen()),
                    ),
                  ),
                  IconButton(
                    key: _kHelp,
                    tooltip: s.guideTooltip,
                    icon: const Icon(Icons.help_outline_rounded,
                        color: BtwColors.inkSoft),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const GuideScreen()),
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
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(28, 18, 28, 12),
                children: [
                  // Their professional's welcome card (clinic, logo, note).
                  if (patient.hasBrand) ...[
                    _brandCard(patient),
                    const SizedBox(height: 18),
                  ],
                  // The latest message from their professional, on top.
                  if (_proMessages.isNotEmpty) ...[
                    for (final m in (_allMessages
                        ? _proMessages.take(10)
                        : _proMessages.take(1))) ...[
                      _messageCard(m, s, canReply: patient.hasClinician),
                      const SizedBox(height: 10),
                    ],
                    if (_proMessages.length > 1)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () =>
                              setState(() => _allMessages = !_allMessages),
                          child: Text(_allMessages
                              ? s.showOnlyLatest
                              : s.earlierMessages(_proMessages.length - 1)),
                        ),
                      ),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    s.hi(patient.firstName),
                    style: const TextStyle(
                        fontSize: 30, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    s.checkInQuestion(profile.providerKey),
                    style: const TextStyle(
                        fontSize: 16.5,
                        color: BtwColors.inkSoft,
                        height: 1.5),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    s.checkInWhoSees(profile.providerKey),
                    style: const TextStyle(
                        fontSize: 13.5, color: BtwColors.inkSoft, height: 1.45),
                  ),
                  if (_streak >= 1 && !patient.hides('streak')) ...[
                    const SizedBox(height: 14),
                    _streakChip(s),
                  ],
                  if (!patient.hasClinician) ...[
                    const SizedBox(height: 16),
                    _supportCard(s),
                  ],
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
                    key: _kComposer,
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
                  // Between-session program from the clinician (exercises,
                  // practices, habits…): tick what you did. Every profession.
                  // Program kept in another app: one yes / some / no question.
                  if (patient.exercisesExternal) ...[
                    Text(s.didYourExercises,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(s.exercisesInApp(patient.exercisesApp),
                        style: const TextStyle(
                            fontSize: 12.5, color: BtwColors.inkSoft)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final o in [
                          ['yes', s.exYes],
                          ['some', s.exSome],
                          ['no', s.exNo],
                        ])
                          ChoiceChip(
                            label: Text(o[1]),
                            selected: _exStatus == o[0],
                            onSelected: (on) =>
                                setState(() => _exStatus = on ? o[0] : null),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ] else if (_exercises.isNotEmpty) ...[
                    Text(_programTitle(s, profile),
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(s.tickWhatYouDid,
                        style: const TextStyle(
                            fontSize: 12.5, color: BtwColors.inkSoft)),
                    const SizedBox(height: 8),
                    for (final e in _exercises) _exerciseTile(e, s),
                    const SizedBox(height: 12),
                  ],
                  // Physical disciplines: a tap-where-it-hurts body map.
                  if (profile.isBody) ...[
                    Text(s.whereHurts,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    BodyMap(
                      isFr: s.isFr,
                      onChanged: (m) => _painMap = m,
                      onSensChanged: (m) => _painSens = m,
                      accountSex: patient.bodySex,
                      onSexChanged: (x) =>
                          context.read<AppState>().saveBodySex(x),
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
                        Text(painScale ? s.painRightNow : s.moodRightNow,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        // "I'll set it / Let Between estimate" — when AI
                        // summaries are on (it reads the note), or on the pain
                        // scale, where the body map's worst spot needs no AI.
                        if (aiOn || painScale) ...[
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
                            child: Text(
                                painScale
                                    ? s.betweenWillReadPain
                                    : s.betweenWillReadMood,
                                style: const TextStyle(
                                    fontSize: 13,
                                    color: BtwColors.inkSoft,
                                    height: 1.4)),
                          )
                        else
                          Row(
                            children: [
                              Text(painScale ? s.noPain : s.low,
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
                              Text(painScale ? s.severe : s.high,
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
                  // Below the check-in so the check-in stays first.
                  if (patient.hasClinician) ...[
                    const SizedBox(height: 18),
                    _topicsTile(s),
                  ],
                ],
              ),
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

/// Writing a reply to one of the professional's messages. Pops with the
/// [ReplyResult] once it's sent.
class _ReplySheet extends StatefulWidget {
  const _ReplySheet({required this.app, required this.replyTo, required this.s});
  final AppState app;
  final String replyTo;
  final S s;

  @override
  State<_ReplySheet> createState() => _ReplySheetState();
}

class _ReplySheetState extends State<_ReplySheet> {
  final _ctrl = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _ctrl.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final r = await widget.app.sendReply(body, replyTo: widget.replyTo);
      if (!mounted) return;
      Navigator.of(context).pop(r);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.replyTitle,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            maxLength: 1000,
            minLines: 3,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: s.replyHint,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
          Text(s.replyNote,
              style: const TextStyle(
                  fontSize: 12.5, height: 1.4, color: BtwColors.inkSoft)),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: const TextStyle(fontSize: 13, color: BtwColors.clay)),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              FilledButton(
                onPressed: _sending ? null : _send,
                child: Text(s.sendReply),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _sending ? null : () => Navigator.of(context).pop(),
                child: Text(s.cancel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
