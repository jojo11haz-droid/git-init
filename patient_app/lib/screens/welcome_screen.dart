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

    Widget step(IconData icon, String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                    color: BtwColors.mossLight, shape: BoxShape.circle),
                child: Icon(icon, size: 20, color: BtwColors.moss),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(body,
                        style: const TextStyle(
                            fontSize: 13.5,
                            height: 1.45,
                            color: BtwColors.inkSoft)),
                  ],
                ),
              ),
            ],
          ),
        );

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 16, 0),
                child: const LanguageToggle(),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(28, 6, 28, 8),
                children: [
                  const SizedBox(height: 14),
                  const Center(child: Wordmark(size: 34)),
                  const SizedBox(height: 18),
                  Text(
                    s.welcomeTagline,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 17, height: 1.55, color: BtwColors.inkSoft),
                  ),
                  const SizedBox(height: 28),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: BtwColors.line),
                    ),
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.howItWorks.toUpperCase(),
                            style: const TextStyle(
                                fontSize: 11.5,
                                letterSpacing: 0.6,
                                fontWeight: FontWeight.w700,
                                color: BtwColors.moss)),
                        const SizedBox(height: 14),
                        step(Icons.edit_note_rounded, s.stepCheckTitle,
                            s.stepCheckBody),
                        step(Icons.insights_rounded, s.stepPatternsTitle,
                            s.stepPatternsBody),
                        step(Icons.lock_outline_rounded, s.stepShareTitle,
                            s.stepShareBody),
                      ],
                    ),
                  ),
                  const SizedBox(height: 26),
                  FilledButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SignUpScreen()),
                    ),
                    child: Text(s.startOnYourOwn),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    ),
                    child: Text(s.logIn),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const InviteScreen()),
                    ),
                    child: Text(s.haveInvite,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 14, color: BtwColors.inkSoft)),
                  ),
                ],
              ),
            ),
            const CrisisFooter(),
          ],
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

/// Self-serve signup: someone starting Between on their own, no therapist.
/// Creates a free-tier account (no payment in-app).
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _ageOk = false;
  String? _error;
  bool _busy = false;

  Future<void> _submit() async {
    final s = context.read<AppState>().s;
    final name = _name.text.trim();
    final email = _email.text.trim();
    if (name.isEmpty || email.isEmpty || _password.text.isEmpty) {
      setState(() => _error = s.fillNameEmailPassword);
      return;
    }
    if (_password.text.length < 10) {
      setState(() => _error = s.passwordTooShort);
      return;
    }
    if (!_ageOk) {
      setState(() => _error = s.pleaseConfirmAge);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AppState>().signUpSolo(name, email, _password.text);
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
      appBar: AppBar(title: Text(s.soloTitle), actions: const [
        Padding(
            padding: EdgeInsets.only(right: 12),
            child: Center(child: LanguageToggle())),
      ]),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(28),
          children: [
            Text(s.soloIntro,
                style: const TextStyle(
                    fontSize: 15, height: 1.6, color: BtwColors.inkSoft)),
            const SizedBox(height: 22),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: s.yourName),
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
            const SizedBox(height: 10),
            CheckboxListTile(
              value: _ageOk,
              onChanged: (v) => setState(() => _ageOk = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              activeColor: BtwColors.moss,
              title: Text(s.ageConfirm,
                  style: const TextStyle(
                      fontSize: 13.5, height: 1.4, color: BtwColors.inkSoft)),
            ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(_error!,
                  style: const TextStyle(color: BtwColors.clay, fontSize: 14)),
            ],
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(_busy ? s.settingUp : s.createAccount),
            ),
            const SizedBox(height: 20),
            const CrisisFooter(),
          ],
        ),
      ),
    );
  }
}
