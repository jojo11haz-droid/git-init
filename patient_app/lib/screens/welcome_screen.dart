import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../app_state.dart';
import '../theme.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>().s;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Align(
                alignment: Alignment.topRight,
                child: LanguageToggle(),
              ),
              const Spacer(),
              const Center(child: Wordmark(size: 40)),
              const SizedBox(height: 16),
              Text(
                s.welcomeTagline,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 16, height: 1.6, color: BtwColors.inkSoft),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                ),
                child: Text(s.logIn),
              ),
              const SizedBox(height: 14),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const InviteScreen()),
                ),
                child: Text(s.haveInvite, textAlign: TextAlign.center),
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
    final s = context.read<AppState>().s;
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
      setState(() => _error = s.offlineError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>().s;
    return Scaffold(
      appBar: AppBar(title: Text(s.welcomeBack), actions: const [
        Padding(padding: EdgeInsets.only(right: 12), child: Center(child: LanguageToggle())),
      ]),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(28),
          children: [
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: InputDecoration(labelText: s.email),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: InputDecoration(labelText: s.password),
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
              child: Text(_busy ? s.signingIn : s.logIn),
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
                    title: Text(s.forgotPassword),
                    content: Text(s.forgotPasswordBody,
                        style: const TextStyle(height: 1.5)),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: Text(s.gotIt,
                            style: const TextStyle(color: BtwColors.moss)),
                      ),
                    ],
                  ),
                ),
                child: Text(s.forgotPassword,
                    style:
                        const TextStyle(fontSize: 13, color: BtwColors.inkSoft)),
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
    final s = context.read<AppState>().s;
    final code = _code.text.trim();
    final email = _email.text.trim();
    if (code.isEmpty || email.isEmpty || _password.text.isEmpty) {
      setState(() => _error = s.fillAllThree);
      return;
    }
    if (_password.text.length < 10) {
      setState(() => _error = s.passwordTooShort);
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
      setState(() => _error = s.offlineError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>().s;
    return Scaffold(
      appBar: AppBar(title: Text(s.setUpAccount), actions: const [
        Padding(padding: EdgeInsets.only(right: 12), child: Center(child: LanguageToggle())),
      ]),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(28),
          children: [
            Text(s.inviteIntro,
                style: const TextStyle(
                    fontSize: 15, height: 1.6, color: BtwColors.inkSoft)),
            const SizedBox(height: 22),
            TextField(
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: s.inviteCode,
                hintText: 'ex. QNY7-PKHQ',
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: InputDecoration(labelText: s.email),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: InputDecoration(
                labelText: s.choosePassword,
                hintText: s.atLeast10,
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
              child: Text(_busy ? s.settingUp : s.continueBtn),
            ),
            const SizedBox(height: 20),
            const CrisisFooter(),
          ],
        ),
      ),
    );
  }
}
