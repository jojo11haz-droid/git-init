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
    if (enabled) {
      // Turning profiling ON is a consent moment — re-confirm, don't just flip.
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: BtwColors.cream,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Turn on AI summaries?'),
          content: const Text(
            'An AI model will analyze your check-ins to write summaries for '
            'your therapist and find patterns over time. This counts as '
            'profiling of your health information, and you can turn it off '
            'again at any time.',
            style: TextStyle(height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Not now',
                  style: TextStyle(color: BtwColors.inkSoft)),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('I consent',
                  style: TextStyle(color: BtwColors.moss)),
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: BtwColors.cream,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Delete my check-in history?'),
        content: const Text(
          'This removes all of your check-ins and summaries from your '
          'therapist\'s view and from the app. This can\'t be undone.',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child:
                const Text('Keep it', style: TextStyle(color: BtwColors.inkSoft)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete everything',
                style: TextStyle(color: BtwColors.clay)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await app.requestDeletion();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Your check-in history has been deleted.')));
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
    final patient = state.patient!;
    return Scaffold(
      appBar: AppBar(title: const Text('My data & settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _Section(
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('AI summaries & trends',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                        SizedBox(height: 4),
                        Text(
                          'When on, an AI model summarizes your check-ins for '
                          'your therapist. When off, they see exactly what you '
                          'wrote.',
                          style: TextStyle(
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
                title: const Text('What\'s on file about me',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                subtitle: const Text(
                  'Every check-in and summary your therapist can see.',
                  style: TextStyle(fontSize: 13, color: BtwColors.inkSoft),
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
                title: const Text('Request deletion of my history',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: BtwColors.clay)),
                subtitle: const Text(
                  'Removes all your check-ins and summaries. Your right, '
                  'anytime.',
                  style: TextStyle(fontSize: 13, color: BtwColors.inkSoft),
                ),
                onTap: _busy ? null : _requestDeletion,
              ),
            ),
            const SizedBox(height: 12),
            _Section(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Log out',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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
