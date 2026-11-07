import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme.dart';
import 'plans_screen.dart';

/// A Premium individual's own page: accent colour and which sections show.
/// Saved on the account, so the website follows the same choices.
class PersonalizeScreen extends StatefulWidget {
  const PersonalizeScreen({super.key});

  @override
  State<PersonalizeScreen> createState() => _PersonalizeScreenState();
}

class _PersonalizeScreenState extends State<PersonalizeScreen> {
  String _accent = 'blue';
  final Set<String> _hide = {};
  bool _saving = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    final p = context.read<AppState>().patient;
    if (p != null) {
      if (p.ownAccent.isNotEmpty) _accent = p.ownAccent;
      _hide.addAll(p.hiddenSections);
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _status = null;
    });
    final s = context.read<AppState>().s;
    try {
      await context.read<AppState>().savePrefs(_accent, _hide.toList());
      if (mounted) setState(() => _status = s.savedLabel);
    } catch (e) {
      if (mounted) setState(() => _status = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = state.s;
    final premium = state.patient?.isPremium ?? false;
    final rows = <List<String>>[
      ['streak', s.showStreak],
      ['reflection', s.showReflection],
      ['goals', s.showGoals],
    ];
    return Scaffold(
      appBar: AppBar(title: Text(s.personalize)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(premium ? s.personalizeLede : s.personalizeLocked,
                style: const TextStyle(
                    fontSize: 15, height: 1.5, color: BtwColors.inkSoft)),
            const SizedBox(height: 20),
            Text(s.colourLabel,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final e in kAccents.entries)
                  Semantics(
                    label: s.accentName(e.key),
                    selected: _accent == e.key,
                    button: true,
                    child: GestureDetector(
                      onTap: premium
                          ? () => setState(() => _accent = e.key)
                          : null,
                      child: Opacity(
                        opacity: premium ? 1 : 0.45,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: e.value,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _accent == e.key
                                  ? BtwColors.ink
                                  : Colors.white,
                              width: 3,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Text(s.onMyPage,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600)),
            for (final r in rows)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(r[1]),
                value: !_hide.contains(r[0]),
                onChanged: premium
                    ? (on) => setState(() {
                          if (on) {
                            _hide.remove(r[0]);
                          } else {
                            _hide.add(r[0]);
                          }
                        })
                    : null,
              ),
            const SizedBox(height: 20),
            if (premium)
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(s.saveBtn),
              )
            else
              FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PlansScreen()),
                ),
                child: Text(s.seePremium),
              ),
            if (_status != null) ...[
              const SizedBox(height: 10),
              Text(_status!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: BtwColors.inkSoft)),
            ],
          ],
        ),
      ),
    );
  }
}
