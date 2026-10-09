import 'dart:ui' show PlatformDispatcher;

/// Language the patient app is shown in. English and Quebec French.
enum AppLang { en, fr }

/// Default to the device/browser language when we haven't stored a choice yet.
AppLang detectInitialLang() {
  final code = PlatformDispatcher.instance.locale.languageCode.toLowerCase();
  return code == 'fr' ? AppLang.fr : AppLang.en;
}

String langCode(AppLang l) => l == AppLang.fr ? 'fr' : 'en';
AppLang langFromCode(String? c) => c == 'fr' ? AppLang.fr : AppLang.en;

/// All user-facing patient-app strings, in both languages. `_(en, fr)` picks
/// the right one for the current language. French uses a warm, informal tone
/// ("tu") to match the app's calm, personal voice.
class S {
  const S(this.lang);
  final AppLang lang;

  bool get isFr => lang == AppLang.fr;
  String _(String en, String fr) => isFr ? fr : en;

  // Shared
  String get logIn => _('Log in', 'Connexion');
  String get continueBtn => _('Continue', 'Continuer');
  String get cancel => _('Cancel', 'Annuler');
  String get done => _('Done', 'Terminé');
  String get close => _('Close', 'Fermer');
  String get email => _('Email', 'Courriel');
  String get password => _('Password', 'Mot de passe');
  String get offlineError => _(
      'Couldn\'t reach Between right now. Check your connection and try again.',
      'Impossible de joindre Between pour le moment. Vérifie ta connexion et réessaie.');
  String get crisisFooter => _(
      'Between is not a crisis service. If you\'re in immediate danger or thinking about suicide, call or text 988, or call 911.',
      'Between n\'est pas un service de crise. Si tu es en danger immédiat ou que tu penses au suicide, appelle ou texte le 988, ou compose le 911.');

  // Welcome
  String get welcomeTagline => _(
      'A quiet place to check in on how you\'re\nreally doing — on your own, or with a pro.',
      'Un endroit tranquille pour faire le point sur\ncomment tu vas vraiment — seul, ou avec un pro.');
  String get startOnYourOwn => _('Start on your own', 'Commence par toi-même');
  String get howItWorks => _('How it works', 'Comment ça marche');
  String get stepCheckTitle => _('Check in, your way', 'Fais le point, à ta façon');
  String get stepCheckBody => _(
      'A quick note, a voice memo, or a few taps — whenever something comes up.',
      'Une note rapide, un mémo vocal ou quelques touches — quand quelque chose survient.');
  String get stepPatternsTitle => _('See your patterns', 'Vois tes tendances');
  String get stepPatternsBody => _(
      'Your mood and themes take shape over time, so you can spot what helps.',
      'Ton humeur et tes thèmes se dessinent avec le temps, pour repérer ce qui aide.');
  String get stepShareTitle => _('On your own, or with a pro', 'Seul, ou avec un pro');
  String get stepShareBody => _(
      'Keep it private, or share it with a professional who\'s helping you.',
      'Garde-le privé, ou partage-le avec un professionnel qui t\'accompagne.');
  String get haveInvite =>
      _('I have an invite from my therapist', 'J\'ai une invitation de mon thérapeute');

  // Solo (self-serve) signup
  String get soloTitle => _('Create your account', 'Crée ton compte');
  String get soloIntro => _(
      'Use Between on your own to check in on how you\'re doing and watch your own patterns over time. It\'s free to start.',
      'Utilise Between par toi-même pour faire le point et suivre tes tendances au fil du temps. C\'est gratuit pour commencer.');
  String get yourName => _('Your name', 'Ton nom');
  String get ageConfirm => _(
      'I\'m 18 or older — or a parent or guardian agrees to my using Between.',
      'J\'ai 18 ans ou plus — ou un parent ou tuteur accepte que j\'utilise Between.');
  String get pleaseConfirmAge => _(
      'Please confirm the box above to continue.',
      'Confirme la case ci-dessus pour continuer.');
  String get fillNameEmailPassword => _(
      'Please fill in your name, email, and password.',
      'Remplis ton nom, ton courriel et ton mot de passe.');
  String get createAccount => _('Create account', 'Créer le compte');
  String get languageLabel => _('Language', 'Langue');

  // Login
  String get welcomeBack => _('Welcome back', 'Bon retour');
  String get signingIn => _('Signing in…', 'Connexion…');
  String get forgotPassword => _('Forgot your password?', 'Mot de passe oublié?');
  String get forgotPasswordBody => _(
      'Ask your therapist to reset your app access — they can do it from their dashboard in a few seconds. You\'ll get a new invite code, and setting up again keeps all your history.',
      'Demande à ton thérapeute de réinitialiser ton accès — il peut le faire depuis son tableau de bord en quelques secondes. Tu recevras un nouveau code d\'invitation, et tout ton historique est conservé.');
  String get gotIt => _('Got it', 'Compris');
  String get enterEmailPassword =>
      _('Enter your email and password.', 'Entre ton courriel et ton mot de passe.');

  // Invite / set up account
  String get setUpAccount => _('Set up your account', 'Crée ton compte');
  String get inviteIntro => _(
      'Your therapist gave you a short invite code. Enter it here with the email and password you\'d like to use.',
      'Ton thérapeute t\'a donné un court code d\'invitation. Entre-le ici avec le courriel et le mot de passe que tu veux utiliser.');
  String get inviteCode => _('Invite code', 'Code d\'invitation');
  String get choosePassword => _('Choose a password', 'Choisis un mot de passe');
  String get atLeast10 => _('At least 10 characters', 'Au moins 10 caractères');
  String get fillAllThree =>
      _('Please fill in all three fields.', 'Remplis les trois champs, s\'il te plaît.');
  String get passwordTooShort => _(
      'Your password needs to be at least 10 characters.',
      'Ton mot de passe doit contenir au moins 10 caractères.');
  String get settingUp => _('Setting up…', 'Création…');

  // Consent
  String consentTitle(String name) => _(
      'Before you start, $name — how Between uses your check-ins.',
      'Avant de commencer, $name — comment Between utilise tes nouvelles.');
  String get consentBullet1 => _(
      'Your check-ins are shared with your therapist as short summaries — not always the raw recording.',
      'Tes nouvelles sont partagées avec ton thérapeute sous forme de courts résumés — pas toujours l\'enregistrement brut.');
  String get consentBullet2 => _(
      'If you turn on AI summaries below, an AI model analyzes what you send to write the summary and to find patterns over time (mood, themes, timing). Under Quebec\'s privacy law (Law 25), this counts as "profiling" of your health information.',
      'Si tu actives les résumés par IA ci-dessous, un modèle d\'IA analyse ce que tu envoies pour rédiger le résumé et repérer des tendances dans le temps (humeur, thèmes, moments). Selon la loi québécoise sur la vie privée (loi 25), cela constitue du « profilage » de tes renseignements de santé.');
  String get consentBullet3 => _(
      'You can leave it off and still send check-ins — they\'ll go to your therapist exactly as you wrote them, with no AI analysis.',
      'Tu peux le laisser désactivé et envoyer quand même tes nouvelles — elles iront à ton thérapeute exactement comme tu les as écrites, sans analyse par IA.');
  String get consentBullet4 => _(
      'You can see everything the app has on file about you at any time, change this choice, and ask for your history to be deleted.',
      'Tu peux voir en tout temps tout ce que l\'application conserve à ton sujet, changer ce choix et demander la suppression de ton historique.');
  String get aiSummariesTrends => _('AI summaries & trends', 'Résumés par IA et tendances');
  String get offByDefault =>
      _('Off by default. Your choice, changeable anytime.', 'Désactivé par défaut. Ton choix, modifiable en tout temps.');
  String get consentCrisis => _(
      'Between is not a crisis or emergency service. If you\'re in immediate danger or thinking about suicide, call or text 988 (Suicide Crisis Helpline) or call 911 — don\'t wait on this app.',
      'Between n\'est pas un service de crise ou d\'urgence. Si tu es en danger immédiat ou que tu penses au suicide, appelle ou texte le 988 (Ligne d\'aide en cas de crise suicidaire) ou compose le 911 — n\'attends pas après cette application.');
  String get consentAgree => _(
      'I understand how my check-ins are used and processed, and I consent to that use as described above.',
      'Je comprends comment mes nouvelles sont utilisées et traitées, et je consens à cette utilisation telle que décrite ci-dessus.');
  String get saving => _('Saving…', 'Enregistrement…');

  // Home / check-in
  String get myHistory => _('My history', 'Mon historique');
  String get myDataSettings => _('My data & settings', 'Mes données et réglages');
  String hi(String name) => _('Hi $name.', 'Salut $name.');
  String get howAreThings =>
      _('How are things right now? Take your time.', 'Comment ça va, là, maintenant? Prends ton temps.');
  String get tellItHint => _('Tell it like it happened…', 'Raconte comme ça s\'est passé…');
  String get recordVoice => _('Record a voice memo', 'Enregistrer une note vocale');
  String get stopRecording => _('Stop recording', 'Arrêter l\'enregistrement');
  String recordingElapsed(String t) =>
      _('Recording… $t — tap to stop', 'Enregistrement… $t — touche pour arrêter');
  String voiceAttached(String t) =>
      _('Voice memo attached ($t)', 'Note vocale jointe ($t)');
  String get orRecord => _(
      'Or record a voice memo — whichever is easier right now.',
      'Ou enregistre une note vocale — ce qui est le plus simple pour toi.');
  String get micOff => _(
      'Microphone access is off. You can type instead, or allow it in settings.',
      'L\'accès au micro est désactivé. Tu peux écrire à la place, ou l\'autoriser dans les réglages.');
  String recordFailed(String e) => _(
      'Couldn\'t start recording — you can type instead. ($e)',
      'Impossible de démarrer l\'enregistrement — tu peux écrire à la place. ($e)');
  String get saySomething => _(
      'Say a little about what happened — record, type, or tap a tag.',
      'Dis un mot sur ce qui s\'est passé — enregistre, écris ou touche une étiquette.');
  String get addMoodTags => _('Add mood & tags (optional)', 'Ajouter humeur et étiquettes (facultatif)');
  String get moodRightNow => _('Mood right now', 'Humeur en ce moment');
  String get illSetIt => _('I\'ll set it', 'Je la règle');
  String get letBetweenEstimate =>
      _('Let Between estimate', 'Between l\'estime');
  String get betweenWillReadMood => _(
      'Between will read your mood from your check-in.',
      'Between estimera votre humeur à partir de votre suivi.');
  String get illPick => _('I\'ll pick', 'Je choisis');
  String get notSureYet => _('Not sure yet', 'Pas encore sûr');
  String get betweenWillPickTopic => _(
      'No problem — Between will pick the theme from your check-in.',
      'Pas de souci — Between choisira le thème à partir de votre suivi.');
  String get whereHurts =>
      _('Where does it hurt or feel sore?', 'Où avez-vous mal ou des courbatures?');
  String get addSorePhoto =>
      _('Add a photo of the sore area', 'Ajouter une photo de la zone douloureuse');
  String get photoAttached => _('Photo attached', 'Photo jointe');
  String get takePhoto => _('Take a photo', 'Prendre une photo');
  String get chooseFromLibrary =>
      _('Choose from library', 'Choisir dans la galerie');
  String get writeOrSpeak => _('Write or speak', 'Écrire ou parler');
  String get answerQuestions => _('Answer questions', 'Répondre aux questions');
  String get yourAnswerHint => _('Your answer…', 'Votre réponse…');
  String get low => _('Low', 'Bas');
  String get high => _('High', 'Élevé');
  String get anythingFits => _('Anything that fits (optional)', 'Ce qui te correspond (facultatif)');
  String get sendToTherapist => _('Send to my therapist', 'Envoyer à mon thérapeute');
  // Per-discipline send label. providerKey null = a solo account (no clinician).
  String sendToProvider(String? providerKey) {
    if (providerKey == null) return _('Save check-in', 'Enregistrer le suivi');
    const en = {
      'therapist': 'therapist',
      'physio': 'physio',
      'kinesiologist': 'kinesiologist',
      'osteopath': 'osteopath',
      'occupational therapist': 'occupational therapist',
      'coach': 'coach',
      'trainer': 'trainer',
      'nutritionist': 'nutritionist',
      'neuropsychologist': 'neuropsychologist',
      'mentor': 'mentor',
      'teacher': 'teacher',
    };
    const fr = {
      'therapist': 'thérapeute',
      'physio': 'physio',
      'kinesiologist': 'kinésiologue',
      'osteopath': 'ostéopathe',
      'occupational therapist': 'ergothérapeute',
      'coach': 'coach',
      'trainer': 'entraîneur',
      'nutritionist': 'nutritionniste',
      'neuropsychologist': 'neuropsychologue',
      'mentor': 'mentor',
      'teacher': 'enseignant',
    };
    return _('Send to my ${en[providerKey] ?? 'provider'}',
        'Envoyer à mon ${fr[providerKey] ?? 'intervenant'}');
  }
  String get sending => _('Sending…', 'Envoi…');

  // Sent
  String get sent => _('Sent.', 'Envoyé.');
  String get sentReassure => _(
      'Your therapist will see this before your next session. That\'s it — nothing else you need to do.',
      'Ton thérapeute le verra avant ta prochaine séance. C\'est tout — tu n\'as rien d\'autre à faire.');
  String get sentCrisisNote => _(
      'Your check-in was sent and your therapist has been notified — but please don\'t wait on anyone if you\'re in danger right now.',
      'Tes nouvelles ont été envoyées et ton thérapeute a été avisé — mais n\'attends après personne si tu es en danger maintenant.');
  String get undo => _('Didn\'t mean to send it? Undo (15 min)', 'Envoyé par erreur? Annuler (15 min)');
  // My progress / recovery-over-time view
  String get myProgress => _('My progress', 'Mes progrès');
  String get progressLede => _(
      'A picture of how you\'ve been — the part a checklist can\'t show you.',
      'Un portrait de comment vous allez — ce qu\'une simple liste ne peut pas montrer.');
  String get yourRecovery => _('Your recovery', 'Votre rétablissement');
  String get recoverySub => _(
      'Where it hurt, and how each spot has changed since you started.',
      'Où ça faisait mal, et comment chaque zone a changé depuis le début.');
  String get recoveryAllClear => _(
      'No sore spots in your latest check-in — nice work.',
      'Aucune zone sensible dans votre dernier suivi — beau travail.');
  String get trendCleared => _('cleared', 'disparue');
  String get trendEasing => _('easing', 'en amélioration');
  String get trendSteady => _('about the same', 'stable');
  String get trendFlaring => _('flaring', 'en hausse');
  String get wasLabel => _('was', 'était');
  String get nowLabel => _('now', 'maintenant');
  // First-run onboarding
  String get skip => _('Skip', 'Passer');
  String get onbNext => _('Next', 'Suivant');
  String get onbStart => _('Start my first check-in', 'Faire mon premier suivi');
  String get onbTitle1 => _('Check in, your way', 'Un suivi, à votre façon');
  String get onbBody1 => _(
      'Write a line, record a quick voice memo, or tap where it hurts. Thirty seconds, whenever something comes up.',
      'Écrivez un mot, enregistrez un court mémo vocal ou touchez où ça fait mal. Trente secondes, dès que quelque chose survient.');
  String get onbTitle2 => _('Watch your patterns', 'Voyez vos tendances');
  String get onbBody2 => _(
      'Between gathers your check-ins into a clear picture over time — your mood, your sore spots, your recovery.',
      'Between rassemble vos suivis en un portrait clair au fil du temps — votre humeur, vos zones sensibles, votre rétablissement.');
  String get onbTitle3 => _('Private by default', 'Privé par défaut');
  String get onbBody3 => _(
      'Your check-ins are yours. Shared only with the person supporting you, and only if you have one. You can delete everything anytime.',
      'Vos suivis vous appartiennent. Partagés seulement avec la personne qui vous accompagne, et seulement si vous en avez une. Vous pouvez tout supprimer en tout temps.');
  // A note to your future self
  String get futureNoteTitle =>
      _('A note to your future self', 'Un mot à votre futur vous');
  String get futureNoteIntro => _(
      'Leave yourself something kind for a harder day. Between shows it back to you after a low check-in.',
      'Laissez-vous un mot bienveillant pour une journée difficile. Between vous le remontre après un suivi plus bas.');
  String get futureNoteHint =>
      _('Write a few words…', 'Écrivez quelques mots…');
  String get saveNote => _('Save note', 'Enregistrer le mot');
  String get futureNotePremium => _(
      'Writing a note is part of Premium. You can still read any note you\'ve already saved.',
      'Écrire un mot fait partie de Premium. Vous pouvez quand même relire les mots déjà enregistrés.');
  String get futureNoteEmpty =>
      _('No notes yet.', 'Aucun mot pour l\'instant.');
  String get noteSaved => _('Saved.', 'Enregistré.');
  String get delete => _('Delete', 'Supprimer');
  String get aNoteYouLeft => _(
      'A note you left yourself', 'Un mot que vous vous êtes laissé');
  String get moodOverTime => _('Mood over time', 'Humeur au fil du temps');
  String checkedInDays(int n) => isFr
      ? 'Suivi fait $n ${n == 1 ? 'jour' : 'jours'} sur les 7 derniers.'
      : 'Checked in on $n of the last 7 days.';
  String get lastTwoWeeks => _('Your last two weeks', 'Vos deux dernières semaines');
  String get checkInsLabel => _('Check-ins', 'Suivis');
  String get goodDaysLabel => _('Good days', 'Bonnes journées');
  String get harderDaysLabel => _('Harder days', 'Journées difficiles');
  String get progressEmptyTitle =>
      _('Your progress will show here', 'Vos progrès apparaîtront ici');
  String get progressEmptyBody => _(
      'Send a few check-ins and you\'ll see your patterns — and for body check-ins, how your sore spots change over time.',
      'Envoyez quelques suivis et vous verrez vos tendances — et pour les suivis du corps, comment vos zones sensibles évoluent avec le temps.');
  String get aiSummaryLabel => _('AI summary', 'Résumé IA');
  String get aiReadMood =>
      _('Between read your mood as', 'Between a estimé votre humeur à');
  String get aiSummaryNote => _(
      'This short summary is what your clinician sees — not the raw text.',
      'Ce court résumé est ce que voit votre intervenant — pas le texte brut.');
  String get removing => _('Removing…', 'Suppression…');
  String get removed =>
      _('Check-in removed. Nothing was kept.', 'Nouvelle supprimée. Rien n\'a été conservé.');

  // History
  String get myCheckIns => _('My check-ins', 'Mes nouvelles');
  String get noCheckIns => _('No check-ins yet.', 'Aucune nouvelle pour l\'instant.');
  String mood(Object v) => _('mood $v/10', 'humeur $v/10');
  String get aiSummary => _('AI summary', 'Résumé par IA');
  String get notAccurate => _('This isn\'t accurate', 'Ce n\'est pas exact');
  String get flaggedInaccurate =>
      _('Flagged as not accurate', 'Signalé comme non exact');
  String get flaggedSnack => _(
      'Flagged. Your therapist will see this summary is marked as not accurate.',
      'Signalé. Ton thérapeute verra que ce résumé est marqué comme non exact.');
  String get voiceMemo => _('Voice memo', 'Note vocale');

  // Settings
  String get aiSummariesDesc => _(
      'When on, an AI model summarizes your check-ins for your therapist. When off, they see exactly what you wrote.',
      'Quand c\'est activé, un modèle d\'IA résume tes nouvelles pour ton thérapeute. Quand c\'est désactivé, il voit exactement ce que tu as écrit.');
  String get visitWebsite => _('betweenpsych.com', 'betweenpsych.com');
  String get previewCategory =>
      _('Preview a category', 'Aperçu d\'une catégorie');
  String get previewCategoryDesc => _(
      'See what the check-in looks like for each profession. Just for trying things out — it doesn\'t change your account.',
      'Voyez à quoi ressemble le suivi pour chaque profession. Juste pour essayer — ça ne change pas votre compte.');
  String get previewDefault =>
      _('My account (default)', 'Mon compte (par défaut)');
  String get groupOnYourOwn => _('On your own', 'Par vous-même');
  String get groupWithProfessional =>
      _('With a professional', 'Avec un professionnel');
  String get viewHomepage => _('View the welcome screen', 'Voir l\'écran d\'accueil');
  String get viewHomepageDesc =>
      _('The Between home / landing page.', 'La page d\'accueil de Between.');
  String get appleHealth => _('Apple Health', 'Apple Santé');
  String get appleHealthDesc => _(
      'Connect Apple Health so your sleep and activity show alongside your check-ins. Between only reads — it never writes back.',
      'Connecte Apple Santé pour que ton sommeil et ton activité apparaissent avec tes suivis. Between ne fait que lire — il n\'écrit jamais rien.');
  String get healthConnected =>
      _('Apple Health connected.', 'Apple Santé connecté.');
  String get healthUnavailable => _(
      'Apple Health isn\'t available or access was declined.',
      'Apple Santé n\'est pas disponible ou l\'accès a été refusé.');
  String get turnOnAiTitle => _('Turn on AI summaries?', 'Activer les résumés par IA?');
  String get turnOnAiBody => _(
      'An AI model will analyze your check-ins to write summaries for your therapist and find patterns over time. This counts as profiling of your health information, and you can turn it off again at any time.',
      'Un modèle d\'IA analysera tes nouvelles pour rédiger des résumés destinés à ton thérapeute et repérer des tendances dans le temps. Cela constitue du profilage de tes renseignements de santé, et tu peux le désactiver en tout temps.');
  String get notNow => _('Not now', 'Pas maintenant');
  String get iConsent => _('I consent', 'Je consens');
  String get whatsOnFile => _('What\'s on file about me', 'Ce qui est conservé à mon sujet');
  String get whatsOnFileDesc => _(
      'Every check-in and summary your therapist can see.',
      'Chaque nouvelle et résumé que ton thérapeute peut voir.');
  String get requestDeletion => _('Request deletion of my history', 'Demander la suppression de mon historique');
  String get requestDeletionDesc => _(
      'Removes all your check-ins and summaries. Your right, anytime.',
      'Supprime toutes tes nouvelles et résumés. Ton droit, en tout temps.');
  String get deleteHistoryTitle =>
      _('Delete my check-in history?', 'Supprimer mon historique de nouvelles?');
  String get deleteHistoryBody => _(
      'This removes all of your check-ins and summaries from your therapist\'s view and from the app. This can\'t be undone.',
      'Cela supprime toutes tes nouvelles et résumés de la vue de ton thérapeute et de l\'application. Cette action est irréversible.');
  String get keepIt => _('Keep it', 'Garder');
  String get deleteEverything => _('Delete everything', 'Tout supprimer');
  String get historyDeleted => _(
      'Your check-in history has been deleted.',
      'Ton historique de nouvelles a été supprimé.');
  String get logOut => _('Log out', 'Déconnexion');

  // Tags: shown translated, but the value sent to the server stays the English
  // key so the therapist dashboard (English) stays consistent.
  String tagLabel(String key) {
    if (!isFr) return key;
    switch (key) {
      case 'Sleep': return 'Sommeil';
      case 'Work': return 'Travail';
      case 'Conflict': return 'Conflit';
      case 'Craving': return 'Envie';
      case 'Cravings': return 'Envies';
      case 'Panic': return 'Panique';
      case 'Family': return 'Famille';
      case 'Win': return 'Réussite';
      case 'Social': return 'Social';
      case 'Mood': return 'Humeur';
      case 'Anxiety': return 'Anxiété';
      case 'Relationships': return 'Relations';
      case 'Pain': return 'Douleur';
      case 'Soreness': return 'Courbatures';
      case 'Mobility': return 'Mobilité';
      case 'Exercises': return 'Exercices';
      case 'Energy': return 'Énergie';
      case 'Training': return 'Entraînement';
      case 'Meals': return 'Repas';
      case 'Digestion': return 'Digestion';
      case 'Hydration': return 'Hydratation';
      case 'Triggers': return 'Déclencheurs';
      case 'Support': return 'Soutien';
      case 'Stress': return 'Stress';
      case 'Focus': return 'Concentration';
      case 'Memory': return 'Mémoire';
      case 'Fatigue': return 'Fatigue';
      case 'Overwhelm': return 'Débordement';
      case 'Headache': return 'Maux de tête';
      case 'Friends': return 'Amis';
      default: return key;
    }
  }
}
