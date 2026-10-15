import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../strings.dart';
import '../theme.dart';

/// The individual pricing page from betweenpsych.com, brought into the app as a
/// showcase. Subscriptions are purchased and managed on the website — the app
/// stays free-to-use in-app (no in-app payment, matching the signup flow), so
/// the CTA opens the web pricing page where checkout happens securely.
const String kIndividualPricingUrl = 'https://betweenpsych.com/individual';

Future<void> _openPricing() async {
  try {
    await launchUrl(Uri.parse(kIndividualPricingUrl),
        mode: LaunchMode.externalApplication);
  } catch (_) {/* no browser available — nothing we can do */}
}

class PlansScreen extends StatelessWidget {
  const PlansScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.s;
    final signedIn = app.signedIn;
    final isPremium = app.patient?.isPremium ?? false;

    return Scaffold(
      appBar: AppBar(title: Text(s.plansTitle), actions: const [
        Padding(
            padding: EdgeInsets.only(right: 12),
            child: Center(child: LanguageToggle())),
      ]),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 10),
          children: [
            Text(s.plansHeroTitle,
                style: const TextStyle(
                    fontSize: 24,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                    color: BtwColors.ink)),
            const SizedBox(height: 8),
            Text(s.plansHeroBody,
                style: const TextStyle(
                    fontSize: 14.5, height: 1.5, color: BtwColors.inkSoft)),
            const SizedBox(height: 16),
            if (signedIn) _StatusChip(isPremium: isPremium, s: s),
            const SizedBox(height: 10),
            _PlanCard(
              tier: s.planPersonalTier,
              name: s.planPersonalName,
              price: '\$14.99',
              unit: s.perMonthCad,
              trial: s.trial3,
              bullets: s.personalBullets,
              featured: false,
            ),
            const SizedBox(height: 14),
            _PlanCard(
              tier: s.planPremiumTier,
              name: s.planPremiumName,
              price: '\$24.99',
              unit: s.perMonthCad,
              trial: s.trial3,
              bullets: s.premiumBullets,
              featured: true,
            ),
            const SizedBox(height: 14),
            Text(s.annualNote,
                style: const TextStyle(
                    fontSize: 12.5, height: 1.45, color: BtwColors.inkSoft)),
            const SizedBox(height: 20),
            if (!isPremium)
              FilledButton.icon(
                onPressed: _openPricing,
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: Text(s.subscribeOnWeb),
              ),
            if (!isPremium) const SizedBox(height: 10),
            if (!isPremium)
              Text(s.managedOnWeb,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 12, height: 1.45, color: BtwColors.inkSoft)),
            const SizedBox(height: 18),
            const CrisisFooter(),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.isPremium, required this.s});
  final bool isPremium;
  final S s;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: isPremium ? BtwColors.mossLight : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: BtwColors.line),
      ),
      child: Row(
        children: [
          Icon(isPremium ? Icons.star_rounded : Icons.check_circle_outline_rounded,
              size: 18, color: BtwColors.moss),
          const SizedBox(width: 10),
          Expanded(
            child: Text(isPremium ? s.currentPlanPremium : s.currentPlanFree,
                style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: BtwColors.ink)),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.tier,
    required this.name,
    required this.price,
    required this.unit,
    required this.trial,
    required this.bullets,
    required this.featured,
  });

  final String tier, name, price, unit, trial;
  final List<String> bullets;
  final bool featured;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: featured ? BtwColors.moss : BtwColors.line,
            width: featured ? 1.6 : 1),
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(tier.toUpperCase(),
                  style: const TextStyle(
                      fontSize: 11.5,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w700,
                      color: BtwColors.moss)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: BtwColors.mossLight,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(trial,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: BtwColors.moss)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(name,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: BtwColors.ink)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(price,
                  style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: BtwColors.ink)),
              const SizedBox(width: 7),
              Text(unit,
                  style: const TextStyle(
                      fontSize: 12.5, color: BtwColors.inkSoft)),
            ],
          ),
          const SizedBox(height: 12),
          for (final b in bullets)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(Icons.check_rounded,
                        size: 16, color: BtwColors.moss),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(b,
                        style: const TextStyle(
                            fontSize: 13.5,
                            height: 1.4,
                            color: BtwColors.ink)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
