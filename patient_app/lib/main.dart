import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'screens/consent_screen.dart';
import 'screens/home_screen.dart';
import 'screens/welcome_screen.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Build the semantics tree from launch: screen-reader users get a working
  // app immediately (and UI tests can drive it through ARIA).
  SemanticsBinding.instance.ensureSemantics();
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState()..restore(),
      child: const BetweenPatientApp(),
    ),
  );
}

class BetweenPatientApp extends StatelessWidget {
  const BetweenPatientApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Between',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const _Gate(),
    );
  }
}

/// Routes by auth state: signed out → welcome; signed in without recorded
/// consent → onboarding/consent (gates everything); otherwise → check-in.
class _Gate extends StatelessWidget {
  const _Gate();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (state.restoring) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: BtwColors.moss)),
      );
    }
    if (!state.signedIn) return const WelcomeScreen();
    if (!state.patient!.hasRecordedConsent) return const ConsentScreen();
    return const HomeScreen();
  }
}
