import 'package:flutter/material.dart';
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      children: [
        Text(s.progressLede,
            style: const TextStyle(
                fontSize: 15.5, height: 1.5, color: BtwColors.inkSoft)),
        const SizedBox(height: 20),
        if (isBody && hasPainHistory) ...[
          _recoveryCard(s),
          const SizedBox(height: 16),
        ],
        _lastTwoWeeksCard(s),
      ],
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
          else
            BodyMapView(map: latest),
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
