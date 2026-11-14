import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../reminders.dart';
import '../theme.dart';

/// Settings card: a daily check-in reminder from the app itself, at the time
/// and on the days the person picks.
class ReminderCard extends StatefulWidget {
  const ReminderCard({super.key});

  @override
  State<ReminderCard> createState() => _ReminderCardState();
}

class _ReminderCardState extends State<ReminderCard> {
  ReminderPrefs? _prefs;
  bool _busy = false;
  String? _note;

  @override
  void initState() {
    super.initState();
    LocalReminders.instance.load().then((p) {
      if (mounted) setState(() => _prefs = p);
    });
  }

  Future<void> _save(ReminderPrefs p) async {
    final s = context.read<AppState>().s;
    setState(() {
      _busy = true;
      _note = null;
    });
    try {
      if (p.enabled && !(_prefs?.enabled ?? false)) {
        final ok = await LocalReminders.instance.requestPermission();
        if (!ok) {
          if (mounted) {
            setState(() {
              _busy = false;
              _note = s.reminderDenied;
            });
          }
          return;
        }
      }
      await LocalReminders.instance.apply(p,
          title: s.reminderTitle,
          body: s.reminderBody,
          channelName: s.reminderChannel);
      if (!mounted) return;
      setState(() {
        _prefs = p;
        _busy = false;
        _note = p.enabled ? s.reminderSaved : null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _note = e.toString();
        });
      }
    }
  }

  Future<void> _pickTime() async {
    final p = _prefs;
    if (p == null) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: p.hour, minute: p.minute),
    );
    if (t == null || !mounted) return;
    await _save(p.copyWith(hour: t.hour, minute: t.minute));
  }

  Future<void> _turnOffTexts() async {
    setState(() => _busy = true);
    try {
      await context.read<AppState>().turnOffTextReminders();
    } catch (_) {
      // Offline: the note stays, they can try again.
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.s;
    final p = _prefs;
    if (!LocalReminders.instance.supported) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: BtwColors.line),
      ),
      child: p == null
          ? const SizedBox(height: 40)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.reminderCardTitle,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text(s.reminderCardSub,
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: BtwColors.inkSoft,
                                  height: 1.45)),
                        ],
                      ),
                    ),
                    Switch(
                      value: p.enabled,
                      activeThumbColor: BtwColors.moss,
                      onChanged:
                          _busy ? null : (v) => _save(p.copyWith(enabled: v)),
                    ),
                  ],
                ),
                if (p.enabled) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _pickTime,
                    icon: const Icon(Icons.schedule_rounded, size: 18),
                    label: Text(TimeOfDay(hour: p.hour, minute: p.minute)
                        .format(context)),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (var d = 1; d <= 7; d++)
                        FilterChip(
                          label: Text(s.weekdayShort(d)),
                          selected: p.days.contains(d),
                          showCheckmark: false,
                          selectedColor: BtwColors.mossLight,
                          onSelected: _busy
                              ? null
                              : (on) {
                                  final days = {...p.days};
                                  if (on) {
                                    days.add(d);
                                  } else if (days.length > 1) {
                                    days.remove(d);
                                  }
                                  _save(p.copyWith(days: days));
                                },
                        ),
                    ],
                  ),
                ],
                if (_note != null) ...[
                  const SizedBox(height: 10),
                  Text(_note!,
                      style: const TextStyle(
                          fontSize: 12.5, color: BtwColors.inkSoft, height: 1.4)),
                ],
                if (p.enabled && (app.patient?.textRemindersOn ?? false)) ...[
                  const SizedBox(height: 10),
                  Text(s.reminderAlsoTexts,
                      style: const TextStyle(
                          fontSize: 12.5, color: BtwColors.inkSoft, height: 1.4)),
                  TextButton(
                    onPressed: _busy ? null : _turnOffTexts,
                    child: Text(s.reminderTurnOffTexts),
                  ),
                ],
              ],
            ),
    );
  }
}
