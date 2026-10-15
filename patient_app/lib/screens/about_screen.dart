import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme.dart';
import 'plans_screen.dart';
import 'welcome_screen.dart';

/// "Why Between" — the marketing story from betweenpsych.com, brought into the
/// app: what you get, common questions, and a route to the plans. Patient-facing
/// (the clinician side of the site has no place here).
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>().s;
    final fr = s.isFr;

    final features = <List<dynamic>>[
      [Icons.bolt_rounded, s.featCheckTitle, s.featCheckBody],
      [Icons.insights_rounded, s.featTrendsTitle, s.featTrendsBody],
      [Icons.lock_outline_rounded, s.featPrivacyTitle, s.featPrivacyBody],
      [Icons.notifications_none_rounded, s.featRemindersTitle, s.featRemindersBody],
      [Icons.favorite_border_rounded, s.featCrisisTitle, s.featCrisisBody],
    ];

    // Individual-relevant FAQ, matching the website's facts and tone.
    final faqs = fr
        ? const [
            [
              'Ai-je besoin d\'un thérapeute?',
              'Non. Vous pouvez utiliser Between seul comme journal privé. Si vous avez un professionnel, il peut vous inviter et voir un court résumé — seulement avec votre consentement.'
            ],
            [
              'Mes données sont-elles privées?',
              'Vos entrées vous appartiennent. L\'analyse par IA est optionnelle et désactivée par défaut. Vous pouvez exporter ou supprimer vos données à tout moment.'
            ],
            [
              'Où mes données sont-elles stockées?',
              'Between fonctionne sur une infrastructure infonuagique tierce (actuellement Render) et peut stocker des données aux États-Unis. Les transferts hors du Québec sont traités dans le respect de la Loi 25.'
            ],
            [
              'Que se passe-t-il après l\'essai?',
              'Vous ajoutez une carte pour commencer l\'essai gratuit, mais rien n\'est facturé pendant celui-ci. On vous rappelle avant la fin et vous pouvez annuler quand vous voulez.'
            ],
            [
              'Puis-je annuler?',
              'Oui, quand vous voulez, depuis betweenpsych.com. Vous gardez l\'accès jusqu\'à la fin de la période payée.'
            ],
            [
              'Est-ce un service de crise?',
              'Non. Between n\'est pas un service d\'urgence. Les ressources de crise sont toujours à portée dans l\'app, et en cas de danger immédiat, composez le 911 ou le 988.'
            ],
          ]
        : const [
            [
              'Do I need a therapist?',
              'No. You can use Between on your own as a private journal. If you do have a professional, they can invite you and see a short summary — only with your consent.'
            ],
            [
              'Is my data private?',
              'Your entries are yours. AI analysis is optional and off by default. You can export or delete your data anytime.'
            ],
            [
              'Where is my data stored?',
              'Between runs on third-party cloud infrastructure (currently Render) and may store data in the United States. Transfers outside Quebec are handled with Quebec\'s Law 25 in mind.'
            ],
            [
              'What happens after my trial?',
              'You add a card to start the free trial, but nothing is charged during it. We remind you before it ends, and you can cancel anytime before then.'
            ],
            [
              'Can I cancel?',
              'Yes, anytime, from betweenpsych.com. You keep access until the end of the period you\'ve paid for.'
            ],
            [
              'Is this a crisis service?',
              'No. Between is not an emergency service. Crisis resources are always one tap away in the app, and if you\'re in immediate danger, call 911 or 988.'
            ],
          ];

    return Scaffold(
      appBar: AppBar(title: Text(s.aboutTitle), actions: const [
        Padding(
            padding: EdgeInsets.only(right: 12),
            child: Center(child: LanguageToggle())),
      ]),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 10),
          children: [
            const Center(child: Wordmark(size: 28)),
            const SizedBox(height: 14),
            Text(s.welcomeTagline,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 15.5, height: 1.5, color: BtwColors.inkSoft)),
            const SizedBox(height: 24),
            Text(s.featuresHead.toUpperCase(),
                style: const TextStyle(
                    fontSize: 11.5,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w700,
                    color: BtwColors.moss)),
            const SizedBox(height: 12),
            for (final f in features)
              _Feature(
                  icon: f[0] as IconData,
                  title: f[1] as String,
                  body: f[2] as String),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: BtwColors.mossLight,
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.goPremium,
                      style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: BtwColors.moss)),
                  const SizedBox(height: 4),
                  Text(s.plansHeroBody,
                      style: const TextStyle(
                          fontSize: 13, height: 1.45, color: BtwColors.inkSoft)),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const PlansScreen()),
                      ),
                      style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 6)),
                      child: Text(s.seePlans,
                          style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: BtwColors.moss)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(s.faqHead.toUpperCase(),
                style: const TextStyle(
                    fontSize: 11.5,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w700,
                    color: BtwColors.moss)),
            const SizedBox(height: 6),
            for (final q in faqs) _Faq(question: q[0], answer: q[1]),
            const SizedBox(height: 18),
            Text(s.trustLine,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 11.5, height: 1.4, color: BtwColors.inkSoft)),
            const SizedBox(height: 6),
            Center(child: WebsiteLink(label: s.visitWebsite)),
            const SizedBox(height: 10),
            const CrisisFooter(),
          ],
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title, body;

  @override
  Widget build(BuildContext context) {
    return Padding(
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
                        fontSize: 13.5, height: 1.45, color: BtwColors.inkSoft)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Faq extends StatelessWidget {
  const _Faq({required this.question, required this.answer});
  final String question, answer;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        iconColor: BtwColors.moss,
        collapsedIconColor: BtwColors.inkSoft,
        title: Text(question,
            style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: BtwColors.ink)),
        children: [
          Text(answer,
              style: const TextStyle(
                  fontSize: 13.5, height: 1.5, color: BtwColors.inkSoft)),
        ],
      ),
    );
  }
}
