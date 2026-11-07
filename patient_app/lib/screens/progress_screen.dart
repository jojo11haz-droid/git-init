import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../body_map.dart';
import '../discipline.dart';
import '../strings.dart';
import '../theme.dart';

/// The patient's own recovery, seen — not a compliance checklist. For body
/// disciplines it shows where it hurt and how each sore spot has changed since
/// they started; for everyone it shows a gentle read on the last two weeks.
/// This is the thing an exercise-prescription tool structurally can't do.
class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

enum _Trend { cleared, easing, steady, flaring }

class _AreaTrend {
  _AreaTrend(this.key, this.first, this.now, this.trend);
  final String key;
  final int first, now;
  final _Trend trend;
}

class _ProgressScreenState extends State<ProgressScreen> {
  bool _loading = true;
  String? _error;
  List<CheckIn> _history = [];

  // Weekly AI reflection (Premium), generated on demand.
  String? _reflection;
  String? _reflectError;
  bool _reflecting = false;
  bool _reflectDone = false;

  // Intentions / goals (self-serve individuals).
  bool _goalsEditing = false;
  bool _goalsSaving = false;
  String? _goalsError;
  final _goal0 = TextEditingController();
  final _goal1 = TextEditingController();

  @override
  void dispose() {
    _goal0.dispose();
    _goal1.dispose();
    super.dispose();
  }

  Future<void> _saveGoals() async {
    final goals = [_goal0.text.trim(), _goal1.text.trim()]
        .where((g) => g.isNotEmpty)
        .take(2)
        .toList();
    setState(() {
      _goalsSaving = true;
      _goalsError = null;
    });
    try {
      await context.read<AppState>().saveGoals(goals);
      if (!mounted) return;
      setState(() {
        _goalsEditing = false;
        _goalsSaving = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _goalsError = e.toString();
        _goalsSaving = false;
      });
    }
  }

  Future<void> _reflect() async {
    setState(() {
      _reflecting = true;
      _reflectError = null;
    });
    try {
      final r = await context.read<AppState>().fetchWeeklyReflection();
      if (!mounted) return;
      setState(() {
        _reflection = r;
        _reflectDone = true;
        _reflecting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _reflectError = e.toString();
        _reflecting = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final h = await context.read<AppState>().fetchHistory();
      if (!mounted) return;
      setState(() {
        _history = h;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // Most recent check-in that recorded a pain map (the "now" figure).
  Map<String, int> get _latestPain {
    for (final c in _history) {
      final pm = c.painMap;
      if (pm != null && pm.isNotEmpty) return pm;
    }
    return const {};
  }

  // Sensations from the same (latest) check-in the pain map above came from,
  // so the recovery card can read muscle/joint/nerve alongside the figure.
  Map<String, String> get _latestSens {
    for (final c in _history) {
      final pm = c.painMap;
      if (pm != null && pm.isNotEmpty) return c.painSens ?? const {};
    }
    return const {};
  }

  // Each area's earliest recorded level — the baseline to measure against.
  Map<String, int> get _firstPain {
    final first = <String, int>{};
    for (final c in _history.reversed) {
      final pm = c.painMap;
      if (pm == null) continue;
      pm.forEach((k, v) => first.putIfAbsent(k, () => v));
    }
    return first;
  }

  List<_AreaTrend> _areaTrends() {
    final latest = _latestPain;
    final first = _firstPain;
    final keys = {...first.keys, ...latest.keys};
    final out = <_AreaTrend>[];
    for (final k in keys) {
      final f = first[k] ?? latest[k]!;
      final n = latest[k] ?? 0;
      final _Trend t;
      if (n == 0 && f > 0) {
        t = _Trend.cleared;
      } else if (n < f) {
        t = _Trend.easing;
      } else if (n > f) {
        t = _Trend.flaring;
      } else {
        t = _Trend.steady;
      }
      out.add(_AreaTrend(k, f, n, t));
    }
    out.sort((a, b) =>
        b.now != a.now ? b.now.compareTo(a.now) : a.key.compareTo(b.key));
    return out;
  }

  List<CheckIn> get _recent {
    final cutoff = DateTime.now().subtract(const Duration(days: 14));
    return _history.where((c) => c.submittedAt.isAfter(cutoff)).toList();
  }

  // Mood values oldest -> newest, last 12, for the trend line.
  List<int> get _moodSeries {
    final pts = _history
        .where((c) => c.mood != null)
        .map((c) => c.mood!)
        .toList()
        .reversed
        .toList();
    return pts.length > 12 ? pts.sublist(pts.length - 12) : pts;
  }

  // Distinct days with a check-in in the last 7 days.
  int get _daysActiveLast7 {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    final days = <String>{};
    for (final c in _history) {
      if (c.submittedAt.isAfter(cutoff)) {
        final d = c.submittedAt;
        days.add('${d.year}-${d.month}-${d.day}');
      }
    }
    return days.length;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>().s;
    final patient = context.read<AppState>().patient!;
    final profile = profileFor(patient);
    return Scaffold(
      appBar: AppBar(title: Text(s.myProgress)),
      body: SafeArea(child: _body(s, profile.isBody)),
    );
  }

  Widget _body(S s, bool isBody) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: BtwColors.moss));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (_history.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.insights_rounded, size: 44, color: BtwColors.moss),
              const SizedBox(height: 16),
              Text(s.progressEmptyTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(s.progressEmptyBody,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 14.5, height: 1.5, color: BtwColors.inkSoft)),
            ],
          ),
        ),
      );
    }

    final hasPainHistory = _firstPain.isNotEmpty;
    final pats = _computePatterns(s);
    final patient = context.read<AppState>().patient;
    final soloIndividual = patient != null && !patient.hasClinician;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      children: [
        Text(s.progressLede,
            style: const TextStyle(
                fontSize: 15.5, height: 1.5, color: BtwColors.inkSoft)),
        const SizedBox(height: 20),
        if (patient?.isPremium == true &&
            !patient!.hides('reflection')) ...[
          _reflectionCard(s),
          const SizedBox(height: 16),
        ],
        if (soloIndividual && !patient!.hides('goals')) ...[
          _goalsCard(s),
          const SizedBox(height: 16),
        ],
        if (pats.isNotEmpty) ...[
          _patternsCard(s, pats),
          const SizedBox(height: 16),
        ],
        if (soloIndividual) ...[
          _shareProButton(s),
          const SizedBox(height: 16),
        ],
        if (isBody && hasPainHistory) ...[
          _recoveryCard(s),
          const SizedBox(height: 16),
        ],
        if (_moodSeries.length >= 2) ...[
          _moodCard(s),
          const SizedBox(height: 16),
        ],
        _lastTwoWeeksCard(s),
      ],
    );
  }

  // Cheap, automatic insight from the person's own check-ins (mirrors the web):
  // a lower-mood weekday, a theme that tracks with lower days, and the
  // week-over-week trend. No AI, no server call.
  List<String> _computePatterns(S s) {
    final moods = _history.where((c) => c.mood != null).toList();
    if (moods.length < 5) return [];
    final out = <String>[];
    final wd = s.isFr
        ? ['dimanche', 'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi']
        : ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    final sum = List<double>.filled(7, 0);
    final cnt = List<int>.filled(7, 0);
    for (final c in moods) {
      final d = c.submittedAt.weekday % 7; // Dart: Mon=1..Sun=7 -> 0=Sun..6=Sat
      sum[d] += c.mood!.toDouble();
      cnt[d]++;
    }
    double? loA, hiA;
    int loD = -1;
    for (var i = 0; i < 7; i++) {
      if (cnt[i] >= 2) {
        final a = sum[i] / cnt[i];
        if (loA == null || a < loA) { loA = a; loD = i; }
        if (hiA == null || a > hiA) { hiA = a; }
      }
    }
    if (loA != null && hiA != null && loD >= 0 && (hiA - loA) >= 1.5) {
      out.add(s.patternWeekday(wd[loD]));
    }
    final overall =
        moods.map((c) => c.mood!).reduce((a, b) => a + b) / moods.length;
    final tagSum = <String, int>{};
    final tagCnt = <String, int>{};
    for (final c in moods) {
      for (final tg in c.tags) {
        tagSum[tg] = (tagSum[tg] ?? 0) + c.mood!;
        tagCnt[tg] = (tagCnt[tg] ?? 0) + 1;
      }
    }
    String? worst;
    double worstA = 999;
    tagCnt.forEach((tg, n) {
      if (n >= 3) {
        final a = tagSum[tg]! / n;
        if (a <= overall - 1 && a < worstA) { worstA = a; worst = tg; }
      }
    });
    if (worst != null) out.add(s.patternTheme(worst!));
    final now = DateTime.now();
    final thisW = moods
        .where((c) => c.submittedAt.isAfter(now.subtract(const Duration(days: 7))))
        .toList();
    final lastW = moods.where((c) {
      final t = c.submittedAt;
      return t.isBefore(now.subtract(const Duration(days: 7))) &&
          t.isAfter(now.subtract(const Duration(days: 14)));
    }).toList();
    if (thisW.length >= 2 && lastW.length >= 2) {
      final ta = thisW.map((c) => c.mood!).reduce((a, b) => a + b) / thisW.length;
      final la = lastW.map((c) => c.mood!).reduce((a, b) => a + b) / lastW.length;
      if (ta - la >= 1) {
        out.add(s.patternUp);
      } else if (la - ta >= 1) {
        out.add(s.patternDown);
      }
    }
    return out.take(3).toList();
  }

  Widget _patternsCard(S s, List<String> items) {
    return Container(
      padding: const EdgeInsets.fromLTRB(17, 15, 17, 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BtwColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.patternsTitle,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          ...items.map((x) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.only(top: 6, right: 10),
                      decoration: const BoxDecoration(
                          color: BtwColors.moss, shape: BoxShape.circle),
                    ),
                    Expanded(
                      child: Text(x,
                          style: const TextStyle(fontSize: 13.5, height: 1.5)),
                    ),
                  ],
                ),
              )),
          Text(s.patternsFoot,
              style: const TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: BtwColors.inkSoft,
                  height: 1.45)),
        ],
      ),
    );
  }

  String _fmtDate(DateTime d) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${m[d.month - 1]} ${d.day}, ${d.year}';
  }

  // A plain-language summary the individual can hand to a professional. Built
  // from their own data; copied to the clipboard, nothing is sent anywhere.
  String _buildProSummary(S s) {
    final f = s.isFr;
    final patient = context.read<AppState>().patient;
    final name = (patient?.displayName.trim().isNotEmpty == true)
        ? patient!.displayName
        : (f ? 'Cette personne' : 'This person');
    final ci = _history.toList()
      ..sort((a, b) => a.submittedAt.compareTo(b.submittedAt));
    final moods = ci.where((c) => c.mood != null).toList();
    final b = StringBuffer();
    b.writeln(f ? 'BETWEEN — RÉSUMÉ DES SUIVIS' : 'BETWEEN — CHECK-IN SUMMARY');
    b.writeln();
    if (ci.isNotEmpty) {
      final label = f ? 'Période : ' : 'Period: ';
      b.writeln('$label${_fmtDate(ci.first.submittedAt)} → ${_fmtDate(ci.last.submittedAt)}');
    }
    b.writeln('${f ? 'Suivis : ' : 'Check-ins: '}${ci.length}');
    if (moods.isNotEmpty) {
      final avg =
          moods.map((c) => c.mood!).reduce((a, b2) => a + b2) / moods.length;
      final label = f ? 'Humeur moyenne autoévaluée : ' : 'Average self-rated mood: ';
      b.writeln('$label${avg.toStringAsFixed(1)}/10');
      final now = DateTime.now();
      final tw = moods
          .where((c) => c.submittedAt.isAfter(now.subtract(const Duration(days: 7))))
          .toList();
      final lw = moods.where((c) {
        final t = c.submittedAt;
        return t.isBefore(now.subtract(const Duration(days: 7))) &&
            t.isAfter(now.subtract(const Duration(days: 14)));
      }).toList();
      if (tw.length >= 2 && lw.length >= 2) {
        final ta = tw.map((c) => c.mood!).reduce((a, b2) => a + b2) / tw.length;
        final la = lw.map((c) => c.mood!).reduce((a, b2) => a + b2) / lw.length;
        final dir = (ta - la >= 1)
            ? (f ? 'en hausse' : 'up')
            : (la - ta >= 1)
                ? (f ? 'en baisse' : 'down')
                : (f ? 'stable' : 'about the same');
        b.writeln((f ? 'Cette semaine vs la précédente : ' : 'This week vs last: ') + dir);
      }
    }
    final goals = patient?.goals ?? const [];
    if (goals.isNotEmpty) {
      b.writeln();
      b.writeln(f ? 'Intentions :' : 'Stated intentions:');
      for (final g in goals) {
        b.writeln('  • $g');
      }
    }
    final tc = <String, int>{};
    for (final c in moods) {
      for (final tg in c.tags) {
        tc[tg] = (tc[tg] ?? 0) + 1;
      }
    }
    final top = tc.keys.toList()..sort((a, b2) => tc[b2]! - tc[a]!);
    final topN = top.take(5).toList();
    if (topN.isNotEmpty) {
      b.writeln();
      b.writeln((f ? 'Thèmes les plus fréquents : ' : 'Most common themes: ') +
          topN.join(', '));
    }
    final pats = _computePatterns(s);
    if (pats.isNotEmpty) {
      b.writeln();
      b.writeln(f ? 'Tendances remarquées :' : 'Patterns noticed:');
      for (final p in pats) {
        b.writeln('  • $p');
      }
    }
    b.writeln();
    b.writeln(f
        ? 'Généré à partir des propres suivis de $name pour partage avec un professionnel. Autodéclaré; n\'est pas une évaluation clinique.'
        : "Generated from $name's own check-ins to share with a professional. Self-reported; not a clinical assessment.");
    return b.toString();
  }

  Widget _shareProButton(S s) {
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: () async {
          final txt = _buildProSummary(s);
          await Clipboard.setData(ClipboardData(text: txt));
          if (!mounted) return;
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(s.proCopied)));
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: BtwColors.moss,
          side: const BorderSide(color: BtwColors.line),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        ),
        icon: const Icon(Icons.ios_share, size: 16),
        label: Text(s.shareWithPro,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      ),
    );
  }

  Widget _goalField(TextEditingController c, String hint) {
    return TextField(
      controller: c,
      maxLength: 80,
      style: const TextStyle(fontSize: 14.5),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: BtwColors.inkSoft),
        counterText: '',
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        filled: true,
        fillColor: BtwColors.cream,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: const BorderSide(color: BtwColors.line)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: const BorderSide(color: BtwColors.line)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: const BorderSide(color: BtwColors.moss)),
      ),
    );
  }

  Widget _goalsCard(S s) {
    final goals = context.read<AppState>().patient?.goals ?? const [];
    final editing = _goalsEditing || goals.isEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(17, 15, 17, 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BtwColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(s.goalsTitle,
                  style:
                      const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const Spacer(),
              if (!editing)
                GestureDetector(
                  onTap: () {
                    _goal0.text = goals.isNotEmpty ? goals[0] : '';
                    _goal1.text = goals.length > 1 ? goals[1] : '';
                    setState(() => _goalsEditing = true);
                  },
                  child: Text(s.goalsEdit,
                      style: const TextStyle(
                          fontSize: 12.5,
                          color: BtwColors.moss,
                          decoration: TextDecoration.underline)),
                ),
            ],
          ),
          if (editing) ...[
            const SizedBox(height: 4),
            Text(s.goalsSub,
                style: const TextStyle(
                    fontSize: 12.5, color: BtwColors.inkSoft, height: 1.5)),
            const SizedBox(height: 12),
            _goalField(_goal0, s.goalHint1),
            const SizedBox(height: 8),
            _goalField(_goal1, s.goalHint2),
            const SizedBox(height: 11),
            Row(
              children: [
                ElevatedButton(
                  onPressed: _goalsSaving ? null : _saveGoals,
                  child: Text(_goalsSaving ? s.saving : s.goalsSave),
                ),
                if (goals.isNotEmpty) ...[
                  const SizedBox(width: 14),
                  GestureDetector(
                    onTap: () => setState(() => _goalsEditing = false),
                    child: Text(s.cancel,
                        style: const TextStyle(
                            fontSize: 12.5, color: BtwColors.inkSoft)),
                  ),
                ],
              ],
            ),
            if (_goalsError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_goalsError!,
                    style:
                        const TextStyle(fontSize: 12, color: BtwColors.clay)),
              ),
          ] else ...[
            const SizedBox(height: 8),
            ...goals.map((g) => Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        margin: const EdgeInsets.only(top: 4, right: 10),
                        decoration: BoxDecoration(
                          border: Border.all(color: BtwColors.moss, width: 2),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      Expanded(
                        child: Text(g,
                            style:
                                const TextStyle(fontSize: 14, height: 1.5)),
                      ),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }

  Widget _reflectionCard(S s) {
    Widget body;
    if (_reflecting) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: BtwColors.moss)),
      );
    } else if (_reflectError != null) {
      body = Text(_reflectError!,
          style: const TextStyle(
              fontSize: 13, height: 1.5, color: BtwColors.inkSoft));
    } else if (_reflection != null) {
      body = Text(_reflection!,
          style: const TextStyle(fontSize: 14, height: 1.6));
    } else if (_reflectDone) {
      body = Text(s.reflectNeedsData,
          style: const TextStyle(
              fontSize: 13, height: 1.5, color: BtwColors.inkSoft));
    } else {
      body = Text(s.reflectHint,
          style: const TextStyle(
              fontSize: 13, height: 1.5, color: BtwColors.inkSoft));
    }
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded,
                  size: 16, color: BtwColors.moss),
              const SizedBox(width: 8),
              Text(s.weeklyReflectionTitle,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 11),
          body,
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _reflecting ? null : _reflect,
              style: TextButton.styleFrom(
                backgroundColor: BtwColors.moss,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9)),
              ),
              child: Text(_reflectDone ? s.reflectAgain : s.reflectCta),
            ),
          ),
        ],
      ),
    );
  }

  Widget _moodCard(S s) {
    final series = _moodSeries;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardLabel(s.moodOverTime),
          const SizedBox(height: 14),
          SizedBox(
            height: 76,
            width: double.infinity,
            child: CustomPaint(painter: _SparklinePainter(series)),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(s.low,
                  style:
                      const TextStyle(fontSize: 11, color: BtwColors.inkSoft)),
              Text(s.high,
                  style:
                      const TextStyle(fontSize: 11, color: BtwColors.inkSoft)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _recoveryCard(S s) {
    final latest = _latestPain;
    final trends = _areaTrends();
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardLabel(s.yourRecovery),
          const SizedBox(height: 4),
          Text(s.recoverySub,
              style: const TextStyle(
                  fontSize: 13, height: 1.4, color: BtwColors.inkSoft)),
          const SizedBox(height: 16),
          if (latest.isEmpty)
            Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: BtwColors.moss, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(s.recoveryAllClear,
                      style: const TextStyle(
                          fontSize: 14.5, height: 1.4, color: BtwColors.ink)),
                ),
              ],
            )
          else ...[
            BodyMapView(map: latest),
            const SizedBox(height: 10),
            Text(painSummary(latest, _latestSens, s.isFr),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13, height: 1.4, color: BtwColors.inkSoft)),
          ],
          const SizedBox(height: 16),
          for (final a in trends) _trendRow(s, a),
        ],
      ),
    );
  }

  Widget _trendRow(S s, _AreaTrend a) {
    final Color bg, fg;
    final String label;
    switch (a.trend) {
      case _Trend.cleared:
        bg = BtwColors.mossLight;
        fg = BtwColors.moss;
        label = s.trendCleared;
        break;
      case _Trend.easing:
        bg = BtwColors.mossLight;
        fg = BtwColors.moss;
        label = s.trendEasing;
        break;
      case _Trend.flaring:
        bg = BtwColors.amberBg;
        fg = BtwColors.clay;
        label = s.trendFlaring;
        break;
      case _Trend.steady:
        bg = BtwColors.line;
        fg = BtwColors.inkSoft;
        label = s.trendSteady;
        break;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              regionLabel(a.key, s.isFr),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          Text('${s.wasLabel} ${a.first} · ${s.nowLabel} ${a.now}',
              style: const TextStyle(fontSize: 12.5, color: BtwColors.inkSoft)),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w700, color: fg)),
          ),
        ],
      ),
    );
  }

  Widget _lastTwoWeeksCard(S s) {
    final recent = _recent;
    final good = recent.where((c) => c.mood != null && c.mood! >= 7).length;
    final hard = recent.where((c) => c.mood != null && c.mood! <= 4).length;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardLabel(s.lastTwoWeeks),
          const SizedBox(height: 14),
          Row(
            children: [
              _stat(recent.length.toString(), s.checkInsLabel),
              _stat(good.toString(), s.goodDaysLabel),
              _stat(hard.toString(), s.harderDaysLabel),
            ],
          ),
          const SizedBox(height: 12),
          Text(s.checkedInDays(_daysActiveLast7),
              style: const TextStyle(
                  fontSize: 13, height: 1.4, color: BtwColors.inkSoft)),
        ],
      ),
    );
  }

  Widget _stat(String value, String label) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: BtwColors.mossLight,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w700, height: 1.1)),
            const SizedBox(height: 3),
            Text(label,
                style:
                    const TextStyle(fontSize: 11.5, color: BtwColors.inkSoft)),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: BtwColors.line),
      ),
      child: child,
    );
  }
}

/// A small line chart of mood values (1..10), oldest -> newest.
class _SparklinePainter extends CustomPainter {
  _SparklinePainter(this.values);
  final List<int> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    const pad = 6.0;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;
    double x(int i) => pad + w * (i / (values.length - 1));
    // Mood 1..10 -> y (10 at top). Clamp to the 1..10 range.
    double y(int v) {
      final t = ((v.clamp(1, 10)) - 1) / 9.0;
      return pad + h * (1 - t);
    }

    // Baseline.
    final base = Paint()
      ..color = BtwColors.line
      ..strokeWidth = 1;
    canvas.drawLine(
        Offset(pad, size.height - pad), Offset(size.width - pad, size.height - pad), base);

    final path = Path()..moveTo(x(0), y(values[0]));
    for (var i = 1; i < values.length; i++) {
      path.lineTo(x(i), y(values[i]));
    }
    final line = Paint()
      ..color = BtwColors.moss
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, line);

    final dot = Paint()..color = BtwColors.moss;
    for (var i = 0; i < values.length; i++) {
      canvas.drawCircle(Offset(x(i), y(values[i])), i == values.length - 1 ? 4 : 2.4, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) => old.values != values;
}

class _CardLabel extends StatelessWidget {
  const _CardLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 10.5,
        letterSpacing: 0.6,
        fontWeight: FontWeight.w700,
        color: BtwColors.moss,
      ),
    );
  }
}
