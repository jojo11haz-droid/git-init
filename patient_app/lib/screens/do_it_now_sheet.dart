import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../strings.dart';
import '../theme.dart';

/// "Do it now": one practice or exercise with its how-to and a timer, the same
/// as on the website. A dose that names minutes ("5 min") counts down;
/// anything else counts up. Breathing practices get a slow in-and-out guide.
/// Returns true when the person taps Done, so the caller ticks it off.
Future<bool> showDoItNow(BuildContext context, HomeExercise e, S s) async {
  final done = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: BtwColors.cream,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _DoItNow(e: e, s: s),
  );
  return done == true;
}

class _DoItNow extends StatefulWidget {
  const _DoItNow({required this.e, required this.s});
  final HomeExercise e;
  final S s;

  @override
  State<_DoItNow> createState() => _DoItNowState();
}

class _DoItNowState extends State<_DoItNow> {
  Timer? _tick;
  Timer? _pace;
  int _total = 0; // seconds to count down from; 0 = count up
  int _left = 0;
  int _up = 0;
  bool _running = false;
  bool _inhale = false;
  bool _finished = false;

  bool get _breathing => RegExp(r'breath|respir', caseSensitive: false)
      .hasMatch('${widget.e.name} ${widget.e.description ?? ''}');

  @override
  void initState() {
    super.initState();
    final m = RegExp(r'(\d+(?:[.,]\d+)?)\s*(min|minute|mn)', caseSensitive: false)
        .firstMatch(widget.e.dosage ?? '');
    if (m != null) {
      final mins = double.tryParse(m.group(1)!.replaceAll(',', '.')) ?? 0;
      _total = (mins * 60).round();
    }
    _left = _total;
  }

  @override
  void dispose() {
    _tick?.cancel();
    _pace?.cancel();
    super.dispose();
  }

  String _fmt(int n) => '${n ~/ 60}:${(n % 60).toString().padLeft(2, '0')}';

  void _stop() {
    _tick?.cancel();
    _pace?.cancel();
    _tick = null;
    _pace = null;
    setState(() {
      _running = false;
      _inhale = false;
    });
  }

  void _toggle() {
    if (_running) {
      _stop();
      return;
    }
    if (_total > 0 && _left <= 0) _left = _total;
    setState(() {
      _running = true;
      _finished = false;
    });
    if (_breathing) {
      setState(() => _inhale = true);
      _pace = Timer.periodic(const Duration(seconds: 4), (_) {
        if (mounted) setState(() => _inhale = !_inhale);
      });
    }
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_total > 0) {
        setState(() => _left = _left > 0 ? _left - 1 : 0);
        if (_left == 0) {
          _stop();
          setState(() => _finished = true);
        }
      } else {
        setState(() => _up++);
      }
    });
  }

  void _reset() {
    _stop();
    setState(() {
      _left = _total;
      _up = 0;
      _finished = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final e = widget.e;
    final started = _total > 0 ? _left < _total : _up > 0;
    final dose = e.dosage;
    final how = e.description;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            22, 18, 22, 18 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(s.doItNow.toUpperCase(),
                style: const TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w600,
                    color: BtwColors.moss)),
            const SizedBox(height: 6),
            Text(e.name,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w700, color: BtwColors.ink)),
            if (dose != null && dose.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(dose,
                  style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: BtwColors.moss)),
            ],
            if (how != null && how.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(how,
                  style: const TextStyle(
                      fontSize: 15, height: 1.5, color: BtwColors.ink)),
            ],
            if (_breathing) ...[
              const SizedBox(height: 14),
              SizedBox(
                height: 130,
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(seconds: 4),
                    curve: Curves.easeInOut,
                    width: _inhale ? 118 : 70,
                    height: _inhale ? 118 : 70,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: BtwColors.mossLight,
                      shape: BoxShape.circle,
                      border: Border.all(color: BtwColors.moss, width: 2),
                    ),
                    child: Text(
                        _running ? (_inhale ? s.breatheIn : s.breatheOut) : '',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: BtwColors.moss)),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(_finished ? s.timeIsUp : _fmt(_total > 0 ? _left : _up),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.w600,
                    color: BtwColors.ink)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: _toggle,
                  child: Text(_running
                      ? s.timerPause
                      : (started ? s.timerResume : s.timerStart)),
                ),
                const SizedBox(width: 10),
                TextButton(onPressed: _reset, child: Text(s.timerReset)),
              ],
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () {
                _stop();
                Navigator.of(context).pop(true);
              },
              child: Text(s.doneTickIt),
            ),
          ],
        ),
      ),
    );
  }
}
