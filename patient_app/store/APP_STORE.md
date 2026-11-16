# Between — App Store submission kit

Everything to paste into App Store Connect, in English and French, plus the
privacy answers, the notes for Apple's reviewer and a step-by-step checklist.
Character limits are Apple's; every field below fits.

---

## 1. Checklist (in order)

1. **Apple Developer Program** — enrol at developer.apple.com ($99 USD / year).
   Enrol as an organization if you have a registered business (shows the
   business name in the store); otherwise as an individual (shows your name).
2. **App ID** — in Certificates, Identifiers & Profiles, create the identifier
   `app.between.betweenPatient` and turn on the **HealthKit** capability.
3. **App Store Connect → New App** — platform iOS, name below, primary
   language English (Canada) or French (Canada), bundle ID above, SKU
   `between-patient-ios`.
4. **On a Mac with Xcode** — `cd patient_app && flutter build ipa`, then open
   `build/ios/archive/Runner.xcarchive` in Xcode → Distribute App → App Store
   Connect. (Signing: Xcode → Runner target → Signing & Capabilities → your
   team, automatic signing. HealthKit is already set in `Runner.entitlements`.)
5. **Fill the listing** (section 2) for English and add French as a second
   localization (section 3).
6. **Screenshots** — at least the 6.9" iPhone size (1320 × 2868 or
   1290 × 2796). Suggested five, from the iPhone simulator, in each language:
   check-in screen, body map, "your trends", messages from the professional,
   settings showing "Delete my account".
7. **App Privacy** (section 4) and **age rating** (section 6).
8. **App Review information** (section 5) — create a reviewer account first.
9. Submit. First review usually takes 1–3 days.

Prices in the app: the iPhone build shows no plans, prices or "Go Premium"
buttons (see `lib/store_rules.dart`). Premium is bought on the website and
works in the app (Apple rule 3.1.3(b)). Do **not** add In-App Purchases in
App Store Connect unless you later decide to sell inside the app.

---

## 2. Listing — English

**App name** (30): `Between: Check-ins`

**Subtitle** (30): `Between-session check-ins`

**Promotional text** (170):
Tell your professional how you're really doing between appointments, in under a minute, by voice or text. Private, in English and French.

**Keywords** (100, comma-separated, no spaces after commas):
`check-in,therapy,physio,mood,pain,journal,mental health,body map,recovery,wellness,tracker,clinic`

**Description** (4000):

Between is the one-minute check-in for the time between appointments.

When something happens — a hard night, a sore knee, a week that finally went well — open Between and say it, by voice or in a few words. If you see a professional who invited you, they see how you've been before your next visit, so the session starts from your real week instead of a fuzzy memory. If you use Between on your own, it's a private place to notice your own patterns.

CHECK IN YOUR WAY
• Talk or type, whichever is easier in the moment
• Rate how you feel, or how much it hurts, on a simple 1–10 scale
• Tap where it hurts on a body map, zoom in to the exact spot and say how it feels
• Add a photo of a sore area when it helps
• Tick off the exercises or practices your professional gave you
• Answer the quick questions they set from your plan

SEE YOUR OWN PATTERN
• Your trend over time and the themes that keep coming back
• Goals you keep in view, and notes to yourself for a harder day
• Gentle daily reminders, at the time you choose

PRIVATE BY DEFAULT
• AI summaries are off until you turn them on, and you can turn them off at any time
• Only you, and the professional who invited you, can see your check-ins
• Export your data or delete your account at any time from Settings
• Built with Canadian privacy law in mind, including Quebec's Law 25

FOR PEOPLE WHO SEE A PROFESSIONAL
Physiotherapists, psychotherapists, kinesiologists, osteopaths, occupational therapists, neuropsychologists, nutritionists, coaches, trainers, recovery programs and schools use Between with the people they help. Your professional sends you an invite; you sign in and start checking in.

APPLE HEALTH (OPTIONAL)
If you connect it, Between reads your sleep, steps, active energy, resting heart rate and mindful minutes so your check-ins show how you've been resting and moving. Between never writes to Apple Health and never uses this data for advertising.

NOT A CRISIS SERVICE
Between is not for emergencies. If a check-in sounds like a crisis, you'll see crisis lines right away. In Canada, call or text 988; in an emergency, call 911.

Available in English and French.

**What's New** (first version): `First release of Between for iPhone.`

**Support URL:** `https://betweenpsych.com/about`
**Marketing URL:** `https://betweenpsych.com`
**Privacy Policy URL:** `https://betweenpsych.com/privacy.html`

**Category:** Primary — Health & Fitness · Secondary — Medical

**Copyright:** `© 2026 Between`

---

## 3. Listing — French (Canada)

**Nom de l'app** (30) : `Between : suivis`

**Sous-titre** (30) : `Suivis entre les séances`

**Texte promotionnel** (170) :
Dites à votre professionnel comment vous allez vraiment entre les rendez-vous, en moins d'une minute, par la voix ou par écrit. Privé, en français et en anglais.

**Mots-clés** (100) :
`suivi,thérapie,physio,humeur,douleur,journal,santé mentale,carte du corps,rétablissement,bien-être`

**Description** (4000) :

Between, c'est le suivi d'une minute pour le temps entre les rendez-vous.

Quand quelque chose se passe — une nuit difficile, un genou qui fait mal, une semaine qui s'est enfin bien passée — ouvrez Between et dites-le, par la voix ou en quelques mots. Si vous voyez un professionnel qui vous a invité, il voit comment vous allez avant votre prochaine visite, et la séance part de votre vraie semaine plutôt que d'un souvenir flou. Si vous utilisez Between par vous-même, c'est un endroit privé pour remarquer vos propres tendances.

FAITES VOTRE SUIVI À VOTRE FAÇON
• Parlez ou écrivez, selon ce qui est le plus simple sur le moment
• Notez comment vous vous sentez, ou à quel point vous avez mal, sur une échelle de 1 à 10
• Touchez l'endroit douloureux sur une carte du corps, zoomez sur l'endroit exact et dites comment vous le ressentez
• Ajoutez une photo de la zone douloureuse au besoin
• Cochez les exercices ou les pratiques que votre professionnel vous a donnés
• Répondez aux courtes questions tirées de votre plan

VOYEZ VOTRE PROPRE TENDANCE
• Votre tendance dans le temps et les thèmes qui reviennent
• Des objectifs gardés en vue, et des mots pour vous-même pour un jour plus difficile
• De petits rappels quotidiens, à l'heure que vous choisissez

PRIVÉ PAR DÉFAUT
• Les résumés IA restent désactivés jusqu'à ce que vous les activiez, et vous pouvez les désactiver en tout temps
• Seuls vous et le professionnel qui vous a invité pouvez voir vos suivis
• Exportez vos données ou supprimez votre compte en tout temps dans les paramètres
• Conçu en tenant compte des lois canadiennes sur la vie privée, dont la Loi 25 du Québec

POUR LES PERSONNES QUI CONSULTENT
Physiothérapeutes, psychothérapeutes, kinésiologues, ostéopathes, ergothérapeutes, neuropsychologues, nutritionnistes, entraîneurs, programmes de rétablissement et écoles utilisent Between avec les personnes qu'ils aident. Votre professionnel vous envoie une invitation; vous vous connectez et commencez vos suivis.

APPLE SANTÉ (FACULTATIF)
Si vous la connectez, Between lit votre sommeil, vos pas, l'énergie active, la fréquence cardiaque au repos et les minutes de pleine conscience, pour que vos suivis montrent comment vous vous reposez et bougez. Between n'écrit jamais dans Apple Santé et n'utilise jamais ces données à des fins publicitaires.

PAS UN SERVICE DE CRISE
Between ne convient pas aux urgences. Si un suivi évoque une crise, vous verrez aussitôt les lignes d'aide. Au Canada, appelez ou textez le 988; en cas d'urgence, composez le 911.

Offert en français et en anglais.

**Nouveautés** : `Première version de Between pour iPhone.`

**URL d'assistance :** `https://betweenpsych.com/about?lang=fr`
**URL marketing :** `https://betweenpsych.com/fr`
**URL de la politique de confidentialité :** `https://betweenpsych.com/privacy.html?lang=fr`

---

## 4. App Privacy ("nutrition label") answers

**Do you or your third-party partners collect data from this app?** Yes.

For every type below: **Linked to the user: Yes · Used for tracking: No ·
Purpose: App Functionality** (nothing else — no advertising, no analytics,
no product personalization by third parties).

| Apple category | Data type | Why |
|---|---|---|
| Contact Info | Name | Account name shown to the person and their professional |
| Contact Info | Email Address | Sign-in, password reset, notifications |
| Contact Info | Phone Number | Only if they turn on text reminders (set on the website) |
| Health & Fitness | Health | Check-ins: mood or pain scores, body-map areas, how it feels; Apple Health sleep, resting heart rate, mindful minutes (optional) |
| Health & Fitness | Fitness | Apple Health steps and active energy (optional) |
| User Content | Audio Data | Voice check-ins |
| User Content | Photos or Videos | Optional photo of a sore area |
| User Content | Other User Content | Check-in text, answers, messages, notes to self, goals |
| Identifiers | User ID | Account identifier |

Not collected: Location, Contacts, Browsing/Search History, Purchases (paid
on the website, not in the app), Usage Data, Diagnostics, Sensitive Info
(Apple's category for race, religion, sexual orientation…), Financial Info.

**Tracking:** No — the app does not track people across other companies'
apps or websites and contains no advertising or analytics SDK.

---

## 5. App Review information (notes for the reviewer)

**Sign-in required:** Yes. Create a dedicated reviewer account before
submitting (do not reuse a real client): in your Between professional
dashboard, add a client named "App Review", accept the invite with a
throwaway address you control, send two or three check-ins and one message
so there's something to see. Put that email and password in the
**Sign-in information** fields — never in this file.

**Notes** (paste, then edit the account details):

> Between is a between-session check-in app. Most people are invited by a
> professional they already see (physiotherapist, psychotherapist,
> nutritionist, etc.); others use it on their own via "Start on your own".
> The demo account above is an invited client with sample check-ins.
>
> What to try: send a check-in by voice or text, tap the body map, open
> "Your trends", read the message from the professional.
>
> Account deletion: Settings → Delete my account (type DELETE to confirm).
>
> Purchases: there are no purchases in the iPhone app. Some people
> subscribe to Personal Premium on our website; the app simply unlocks
> those features for them (guideline 3.1.3(b)). The app shows no prices
> and no links to buy.
>
> Apple Health: optional, read-only (sleep, steps, active energy, resting
> heart rate, mindful minutes). Settings → Connect Apple Health. Data is
> shown with the person's check-ins and to their professional; it is never
> used for advertising and never sent to an AI.
>
> Not a medical device and not a crisis service: Between documents what
> people report; it does not diagnose or give treatment advice. If a
> check-in contains crisis language, the person sees crisis lines
> immediately (988 / 911 in Canada).
>
> AI: summaries of check-ins are off by default and only run after the
> person opts in; they can opt out at any time.

**Contact:** your name, phone and owner@betweenpsych.com.

---

## 6. Age rating questionnaire

Answer honestly in App Store Connect; expected answers:

- Medical or treatment-focused content: **Yes — infrequent/mild**
  (it's a check-in tool used alongside care, with no treatment advice)
- Mature/suggestive themes: **Infrequent/mild** (crisis resources mention
  suicide and self-harm)
- Violence, sexual content, profanity, gambling, contests, alcohol/drugs
  references: **None**
- Unrestricted web access: **No**
- User-generated content shared with other users: **No** (only with the
  person's own professional)
- Messaging/chat: **Yes** — with their own professional only

Apple computes the rating from these; expect **13+** (or 16+). Minors are
only invited by a professional or school with the consent the law requires.

---

## 7. After approval

- Turn on **phased release** for updates.
- Every new version needs a fresh build number: bump `version:` in
  `patient_app/pubspec.yaml` (e.g. `1.0.1+2`).
- Keep the reviewer account working; Apple re-uses it for every update.
