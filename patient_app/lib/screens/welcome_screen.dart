import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../app_state.dart';
import '../theme.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              const Center(child: Wordmark(size: 40)),
              const SizedBox(height: 16),
              const Text(
                'A quiet place to tell your therapist\nhow things really are, '
                'between sessions.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 16, height: 1.6, color: BtwColors.inkSoft),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                ),
                child: const Text('Log in'),
              ),
              const SizedBox(height: 14),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const InviteScreen()),
                ),
                child: const Text('I have an invite from my therapist'),
              ),
              const SizedBox(height: 8),
              const CrisisFooter(),
            ],
          ),
        ),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context
          .read<AppState>()
          .login(_email.text.trim(), _password.text);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error =
          'Couldn\'t reach Between right now. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Welcome back')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(28),
          children: [
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!,
                  style: const TextStyle(color: BtwColors.clay, fontSize: 14)),
            ],
            const SizedBox(height: 22),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(_busy ? 'Signing in…' : 'Log in'),
            ),
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: BtwColors.cream,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24)),
                    title: const Text('Forgot your password?'),
                    content: const Text(
                      'Ask your therapist to reset your app access — they can '
                      'do it from their dashboard in a few seconds. You\'ll '
                      'get a new invite code, and setting up again keeps all '
                      'your history.',
                      style: TextStyle(height: 1.5),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('Got it',
                            style: TextStyle(color: BtwColors.moss)),
                      ),
                    ],
                  ),
                ),
                child: const Text('Forgot your password?',
                    style:
                        TextStyle(fontSize: 13, color: BtwColors.inkSoft)),
              ),
            ),
            const SizedBox(height: 8),
            const CrisisFooter(),
          ],
        ),
      ),
    );
  }
}

/// Accept the therapist's invite: the code they shared becomes this
/// patient's own login. One-time use.
class InviteScreen extends StatefulWidget {
  const InviteScreen({super.key});

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  final _code = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  Future<void> _submit() async {
    final code = _code.text.trim();
    final email = _email.text.trim();
    if (code.isEmpty || email.isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Please fill in all three fields.');
      return;
    }
    if (_password.text.length < 10) {
      setState(
          () => _error = 'Your password needs to be at least 10 characters.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AppState>().acceptInvite(code, email, _password.text);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error =
          'Couldn\'t reach Between right now. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set up your account')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(28),
          children: [
            const Text(
              'Your therapist gave you a short invite code. Enter it here with '
              'the email and password you\'d like to use.',
              style: TextStyle(
                  fontSize: 15, height: 1.6, color: BtwColors.inkSoft),
            ),
            const SizedBox(height: 22),
            TextField(
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Invite code',
                hintText: 'e.g. QNY7-PKHQ',
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Choose a password',
                hintText: 'At least 10 characters',
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!,
                  style: const TextStyle(color: BtwColors.clay, fontSize: 14)),
            ],
            const SizedBox(height: 22),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(_busy ? 'Setting up…' : 'Continue'),
            ),
            const SizedBox(height: 20),
            const CrisisFooter(),
          ],
        ),
      ),
    );
  }
}
