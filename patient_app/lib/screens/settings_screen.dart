import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme.dart';
import 'history_screen.dart';

/// My data & settings: the patient's controls over their own information —
/// the AI toggle, the erasure request, and what's on file.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;

  Future<void> _toggleAi(bool enabled) async {
    final app = context.read<AppState>();
    final s = app.s;
    if (enabled) {
      // Turning profiling ON is a consent moment — re-confirm, don't just flip.
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: BtwColors.cream,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(s.turnOnAiTitle),
          content: Text(s.turnOnAiBody, style: const TextStyle(height: 1.5)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(s.notNow,
                  style: const TextStyle(color: BtwColors.inkSoft)),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(s.iConsent,
                  style: const TextStyle(color: BtwColors.moss)),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busy = true);
    try {
      await app.recordConsent(aiEnabled: enabled);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestDeletion() async {
    final app = context.read<AppState>();
    final s = app.s;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: BtwColors.cream,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(s.deleteHistoryTitle),
        content: Text(s.deleteHistoryBody, style: const TextStyle(height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.keepIt,
                style: const TextStyle(color: BtwColors.inkSoft)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(s.deleteEverything,
                style: const TextStyle(color: BtwColors.clay)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await app.requestDeletion();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.historyDeleted)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    await context.read<AppState>().logout();
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = state.s;
    final patient = state.patient!;
    return Scaffold(
      appBar: AppBar(title: Text(s.myDataSettings)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _Section(
              child: Row(
                children: [
                  Expanded(
                    child: Text(s.languageLabel,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                  const LanguageToggle(),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _Section(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.aiSummariesTrends,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(
                          s.aiSummariesDesc,
                          style: const TextStyle(
                              fontSize: 13,
                              color: BtwColors.inkSoft,
                              height: 1.45),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: patient.aiConsentEnabled,
                    activeThumbColor: BtwColors.moss,
                    onChanged: _busy ? null : _toggleAi,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _Section(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(s.whatsOnFile,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                subtitle: Text(
                  s.whatsOnFileDesc,
                  style:
                      const TextStyle(fontSize: 13, color: BtwColors.inkSoft),
                ),
                trailing: const Icon(Icons.chevron_right_rounded,
                    color: BtwColors.inkSoft),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HistoryScreen()),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _Section(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(s.requestDeletion,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: BtwColors.clay)),
                subtitle: Text(
                  s.requestDeletionDesc,
                  style:
                      const TextStyle(fontSize: 13, color: BtwColors.inkSoft),
                ),
                onTap: _busy ? null : _requestDeletion,
              ),
            ),
            const SizedBox(height: 12),
            _Section(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(s.logOut,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                subtitle: Text(
                  patient.raw['email'] as String? ?? '',
                  style: const TextStyle(
                      fontSize: 13, color: BtwColors.inkSoft),
                ),
                onTap: _logout,
              ),
            ),
            const SizedBox(height: 20),
            const CrisisFooter(),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: BtwColors.line),
      ),
      child: child,
    );
  }
}
