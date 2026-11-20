// Per-field page copy, in English and French. The server writes it into each
// field page's HTML (between <!--FIELD_COPY--> markers in index.html) so every
// URL — /physio, /fr/nutrition, … — carries its own readable content without
// needing JavaScript, instead of 23 near-identical pages Google folds into one.
// The SPA asks /api/field-copy for the same block when the visitor switches
// field or language. Keep claims in line with what the product actually does.

const ORDER = ['/therapy', '/physio', '/kinesiology', '/osteopathy', '/occupational-therapy', '/neuropsychology', '/nutrition', '/sports', '/fitness', '/addiction', '/schools', '/individual'];

const NAMES = {
  '/therapy': ['Psychotherapy', 'Psychothérapie'],
  '/physio': ['Physiotherapy', 'Physiothérapie'],
  '/kinesiology': ['Kinesiology', 'Kinésiologie'],
  '/osteopathy': ['Osteopathy', 'Ostéopathie'],
  '/occupational-therapy': ['Occupational therapy', 'Ergothérapie'],
  '/neuropsychology': ['Neuropsychology', 'Neuropsychologie'],
  '/nutrition': ['Nutrition', 'Nutrition'],
  '/sports': ['Sports teams', 'Équipes sportives'],
  '/fitness': ['Personal training', 'Entraînement personnel'],
  '/addiction': ['Addiction & recovery', 'Dépendances et rétablissement'],
  '/schools': ['Schools', 'Écoles'],
  '/individual': ['For yourself', 'Pour vous-même']
};

// Each field page: heading, intro, 4 points [title, text], 3 questions [q, a].
const FIELDS = {
  '/therapy': {
    en: { h: 'Between for psychotherapists',
      intro: 'What clients go through between sessions rarely makes it into the room intact. With Between they send a short note when something happens, by voice or text, and you open the next session already knowing their week: the mood trend, the themes that keep returning and what they want to talk about.',
      points: [['A pattern, not a recap', 'Mood on a 1–10 scale, recurring themes like sleep, work or conflict, and a short read of the thread running through their weeks.'],
        ['Who needs you today', 'Only the clients with a safety flag, a worsening trend or a long silence, with the reason, so nothing slips between sessions.'],
        ['DAP notes in minutes', 'A DAP note drafted from their check-ins and your own dictated or recorded words. You check it, edit it and copy it to your chart.'],
        ['Between-session practice', 'Assign practices and ask about the plan in each check-in: “Did you try the breathing pause?” Their answers appear in your next note.']],
      faq: [['Is Between a crisis service?', 'No. Between is a documentation tool. If a check-in sounds like a crisis, the client sees crisis lines right away, and you are never on call through Between.'],
        ['Does the AI read my clients’ check-ins?', 'Only if the client turns AI summaries on, and they can turn them off at any time. Without it, nothing they write is sent to an AI.'],
        ['Does it replace my notes software?', 'No. Between drafts the note; you save it as a PDF or Word file or copy it into the charting system you already use.']] },
    fr: { h: 'Between pour les psychothérapeutes',
      intro: 'Ce que vivent vos clients entre les séances arrive rarement intact dans votre bureau. Avec Between, ils envoient une courte note dès que quelque chose se passe, par la voix ou par écrit, et vous commencez la séance en connaissant déjà leur semaine : la tendance de l’humeur, les thèmes qui reviennent et ce dont ils veulent parler.',
      points: [['Une tendance, pas un résumé', 'L’humeur sur une échelle de 1 à 10, les thèmes récurrents comme le sommeil, le travail ou les conflits, et une courte lecture du fil qui traverse leurs semaines.'],
        ['Qui a besoin de vous aujourd’hui', 'Seulement les clients avec un signalement, une tendance qui se détériore ou un long silence, avec la raison, pour que rien ne passe entre les mailles.'],
        ['Des notes DAP en quelques minutes', 'Une note DAP rédigée à partir de leurs suivis et de vos propres mots, dictés ou enregistrés. Vous la vérifiez, l’ajustez et la copiez au dossier.'],
        ['La pratique entre les séances', 'Assignez des pratiques et faites le point sur le plan à chaque suivi : « Avez-vous essayé la pause respiration? » Les réponses figurent dans votre prochaine note.']],
      faq: [['Between est-il un service de crise?', 'Non. Between est un outil de documentation. Si un suivi évoque une crise, le client voit aussitôt les lignes d’aide, et vous n’êtes jamais de garde par l’entremise de Between.'],
        ['L’IA lit-elle les suivis de mes clients?', 'Seulement si le client active les résumés IA, et il peut les désactiver en tout temps. Sinon, rien de ce qu’il écrit n’est envoyé à une IA.'],
        ['Est-ce que ça remplace mon logiciel de dossiers?', 'Non. Between rédige la note; vous l’enregistrez en PDF ou en Word, ou la copiez dans le logiciel que vous utilisez déjà.']] }
  },
  '/physio': {
    en: { h: 'Between for physiotherapists',
      intro: 'Patients forget how the knee felt on Tuesday. Between lets them mark where it hurts on a body map between visits, say how it feels and tick off their home exercises, so you start the appointment with the pain trend and adherence in front of you.',
      points: [['Pain on a body map', 'Tap the area, zoom in to the exact spot and choose how it feels: aching, sharp, stiff, tingling. Front and back, man or woman figure.'],
        ['Home exercise adherence', 'Assign exercises with dose and how-to; patients tick what they did. Already use Wibbi or Physitrack? Keep it, and Between asks whether they did them.'],
        ['SOAP notes from the visit', 'S and O come from their check-ins, with exact figures since the last visit; dictate or record your findings, assessment and plan into the same note.'],
        ['A safety hold built in', 'When check-ins report tingling or severe or worsening sharp pain, exercise suggestions stay gentle and flag an in-person check first.']],
      faq: [['What do patients need to install?', 'Nothing: check-ins work in the browser on any phone. An app for iPhone and Android is on the way.'],
        ['Can the plan follow them home?', 'Yes. From your plan, Between suggests up to three yes / partly / no questions, such as “Did you do your step-ups?”, asked in every check-in until you change them.'],
        ['Is it built for Quebec?', 'Yes: the whole product is in French and English, and it is designed with Quebec’s Law 25 in mind, with a signed clinic data agreement.']] },
    fr: { h: 'Between pour les physiothérapeutes',
      intro: 'Les patients oublient comment allait leur genou mardi dernier. Between leur permet d’indiquer où ils ont mal sur une carte du corps entre les visites, de dire comment ils le ressentent et de cocher leurs exercices à domicile; vous commencez le rendez-vous avec l’évolution de la douleur et l’assiduité sous les yeux.',
      points: [['La douleur sur une carte du corps', 'Touchez la zone, zoomez sur l’endroit exact et choisissez la sensation : douleur sourde, vive, raideur, picotements. Devant et dos, silhouette homme ou femme.'],
        ['L’assiduité aux exercices', 'Assignez des exercices avec la dose et les consignes; la personne coche ce qui a été fait. Vous utilisez déjà Wibbi ou Physitrack? Gardez-les, Between demande simplement s’ils ont été faits.'],
        ['Des notes SOAP de la visite', 'Le S et le O viennent des suivis, avec les chiffres exacts depuis la dernière visite; dictez ou enregistrez vos constats, votre évaluation et votre plan dans la même note.'],
        ['Une prudence intégrée', 'Si les suivis rapportent des picotements ou une douleur vive forte ou qui s’aggrave, les suggestions d’exercices restent douces et proposent d’abord une vérification en personne.']],
      faq: [['Que doivent installer les patients?', 'Rien : les suivis fonctionnent dans le navigateur de n’importe quel téléphone. Une application iPhone et Android s’en vient.'],
        ['Le plan peut-il les suivre à la maison?', 'Oui. À partir de votre plan, Between suggère jusqu’à trois questions oui / en partie / non, comme « Avez-vous fait vos montées de marche? », posées à chaque suivi jusqu’à ce que vous les changiez.'],
        ['Est-ce pensé pour le Québec?', 'Oui : tout le produit est en français et en anglais, conçu en tenant compte de la Loi 25, avec une entente de données signée pour la clinique.']] }
  },
  '/kinesiology': {
    en: { h: 'Between for kinesiologists',
      intro: 'Progress in kinesiology happens between sessions, in the workouts clients do on their own. Between shows you how movement, pain and the program actually went since you last saw them, so each session builds on real data instead of memory.',
      points: [['Movement and pain between sessions', 'Clients note how training felt and mark sore spots on a body map, with a pain score that builds into a trend.'],
        ['The program, ticked off', 'Exercises with dose and how-to; clients tick what they did, and you see completion per exercise over the weeks.'],
        ['Program review in one tap', 'Between suggests what to progress, ease off, add or drop, based on what they actually did. Nothing changes until you apply it.'],
        ['SOAP notes and reports', 'A SOAP note from their check-ins and your own words, plus progress reports and letters drafted from the whole history.']],
      faq: [['Can I use it with clients I see rarely?', 'Yes. The longer the gap between sessions, the more the check-ins help: you see the whole stretch at a glance.'],
        ['What if the client already uses another exercise app?', 'Keep it. Between can simply ask “Did you do your exercises?” in each check-in, yes / partly / no.'],
        ['Is there a free trial?', 'Yes, 14 days, with nothing to unwind if you stop: export or delete your data whenever you want.']] },
    fr: { h: 'Between pour les kinésiologues',
      intro: 'En kinésiologie, les progrès se font entre les séances, dans les entraînements que vos clients font seuls. Between vous montre comment le mouvement, la douleur et le programme se sont réellement passés depuis la dernière fois, pour que chaque séance repose sur des données plutôt que sur des souvenirs.',
      points: [['Mouvement et douleur entre les séances', 'Les clients notent comment l’entraînement s’est passé et indiquent les zones douloureuses sur une carte du corps, avec un score de douleur qui forme une tendance.'],
        ['Le programme, coché', 'Des exercices avec la dose et les consignes; le client coche ce qu’il a fait, et vous voyez l’assiduité par exercice au fil des semaines.'],
        ['La révision du programme en un geste', 'Between suggère quoi faire progresser, alléger, ajouter ou retirer, selon ce qui a vraiment été fait. Rien ne change avant que vous l’appliquiez.'],
        ['Notes SOAP et rapports', 'Une note SOAP tirée des suivis et de vos propres mots, ainsi que des rapports d’évolution et des lettres rédigés à partir de tout l’historique.']],
      faq: [['Est-ce utile pour des clients que je vois rarement?', 'Oui. Plus l’intervalle est long, plus les suivis aident : vous voyez toute la période d’un coup d’œil.'],
        ['Et si le client utilise déjà une autre application d’exercices?', 'Il la garde. Between peut simplement demander « Avez-vous fait vos exercices? » à chaque suivi : oui, en partie ou non.'],
        ['Y a-t-il un essai gratuit?', 'Oui, 14 jours, sans rien à défaire si vous arrêtez : exportez ou supprimez vos données quand vous voulez.']] }
  },
  '/osteopathy': {
    en: { h: 'Between for osteopaths',
      intro: 'Between treatments, your clients notice what eased, what flared up and what set it off. Between captures that on a body map as it happens, so at the next appointment you see how they responded to treatment instead of relying on a vague recollection.',
      points: [['How they responded to treatment', 'Pain scores and marked areas after each treatment, with a trend that shows whether things are settling.'],
        ['Where it hurts, precisely', 'A detailed body map with close-ups of the neck, shoulders, lower back, hips and more, and how each spot feels.'],
        ['Advice they actually follow', 'Give stretches or self-care advice and ask about them in each check-in; you see what they did and what helped.'],
        ['Notes and letters ready to go', 'A SOAP note from their check-ins and your dictated findings, and letters to a doctor or insurer drafted from the history.']],
      faq: [['How long does a check-in take?', 'Under a minute: tap where it hurts, choose a score, add a few words or a voice memo if they like.'],
        ['Do I have to reply to check-ins?', 'No. Summaries wait for the next appointment, and a short morning email lists only the clients who need you.'],
        ['Where is the data stored?', 'In the United States, with Render and Neon; every provider is listed publicly, and clients can export or delete their data.']] },
    fr: { h: 'Between pour les ostéopathes',
      intro: 'Entre les traitements, vos clients remarquent ce qui s’est apaisé, ce qui s’est réveillé et ce qui l’a déclenché. Between le saisit sur une carte du corps au moment où ça se passe; au rendez-vous suivant, vous voyez comment ils ont réagi au traitement plutôt que de compter sur un souvenir flou.',
      points: [['La réaction au traitement', 'Les scores de douleur et les zones marquées après chaque traitement, avec une tendance qui montre si les choses se calment.'],
        ['Où ça fait mal, précisément', 'Une carte du corps détaillée avec gros plans du cou, des épaules, du bas du dos, des hanches et plus, et la sensation de chaque endroit.'],
        ['Des conseils vraiment suivis', 'Donnez des étirements ou des conseils d’autosoins et faites le point à chaque suivi; vous voyez ce qui a été fait et ce qui a aidé.'],
        ['Notes et lettres prêtes', 'Une note SOAP tirée des suivis et de vos constats dictés, et des lettres à un médecin ou à un assureur rédigées à partir de l’historique.']],
      faq: [['Combien de temps prend un suivi?', 'Moins d’une minute : toucher l’endroit douloureux, choisir un score, ajouter quelques mots ou une note vocale au besoin.'],
        ['Dois-je répondre aux suivis?', 'Non. Les résumés attendent le prochain rendez-vous, et un court courriel le matin liste seulement les clients qui ont besoin de vous.'],
        ['Où les données sont-elles conservées?', 'Aux États-Unis, chez Render et Neon; chaque fournisseur est listé publiquement, et les clients peuvent exporter ou supprimer leurs données.']] }
  },
  '/occupational-therapy': {
    en: { h: 'Between for occupational therapists',
      intro: 'Occupational therapy is about daily life, and daily life happens between visits. Between lets clients tell you how getting dressed, cooking, working or getting around went this week, with a body map for pain, so you plan the next session around what really happened.',
      points: [['Daily activities, in their words', 'Clients note what was easier or harder this week, by voice or text, with quick topics for the activities that matter to them.'],
        ['Pain and fatigue tracked', 'A body map and a score that build a trend across visits, so changes in function are easy to see.'],
        ['Strategies they can follow', 'Assign strategies or exercises with how-to and ask about them in each check-in; completion shows next to the trend.'],
        ['SOAP notes and reports', 'A SOAP note from their check-ins and your own words, and progress reports for insurers, employers or schools drafted from the history.']],
      faq: [['Does it work for clients who don’t like typing?', 'Yes. They can record a voice memo, answer guided questions or simply tap a score and a few topics.'],
        ['Can I write to a client between visits?', 'Yes: send a short message with strategies or exercises attached, and see when it has been read.'],
        ['Is it available in French?', 'Yes, for you and your clients, including reminders, emails and the chart notes.']] },
    fr: { h: 'Between pour les ergothérapeutes',
      intro: 'L’ergothérapie porte sur la vie de tous les jours, et la vie de tous les jours se passe entre les visites. Between permet à vos clients de vous dire comment se sont passés l’habillage, la cuisine, le travail ou les déplacements cette semaine, avec une carte du corps pour la douleur; vous planifiez la séance suivante selon ce qui s’est vraiment passé.',
      points: [['Les activités quotidiennes, dans leurs mots', 'Les clients notent ce qui a été plus facile ou plus difficile, par la voix ou par écrit, avec des sujets rapides pour les activités qui comptent pour eux.'],
        ['Douleur et fatigue suivies', 'Une carte du corps et un score qui forment une tendance d’une visite à l’autre, pour voir facilement les changements de fonctionnement.'],
        ['Des stratégies à suivre', 'Assignez des stratégies ou des exercices avec les consignes et faites le point à chaque suivi; l’assiduité s’affiche à côté de la tendance.'],
        ['Notes SOAP et rapports', 'Une note SOAP tirée des suivis et de vos propres mots, et des rapports d’évolution pour les assureurs, les employeurs ou les écoles, rédigés à partir de l’historique.']],
      faq: [['Est-ce utile pour les clients qui n’aiment pas écrire?', 'Oui. Ils peuvent enregistrer une note vocale, répondre à des questions guidées ou simplement choisir un score et quelques sujets.'],
        ['Puis-je écrire à un client entre les visites?', 'Oui : envoyez un court message avec des stratégies ou des exercices joints, et voyez quand il a été lu.'],
        ['Est-ce offert en français?', 'Oui, pour vous et vos clients, y compris les rappels, les courriels et les notes au dossier.']] }
  },
  '/neuropsychology': {
    en: { h: 'Between for neuropsychologists',
      intro: 'Between assessments and sessions, your clients notice when focus slips, memory lapses pile up or mental fatigue sets in. Between gives them a quick way to record it as it happens, so you see the pattern over weeks instead of a single snapshot on the day you meet.',
      points: [['Cognitive symptoms over time', 'Check-ins on focus, memory, mental fatigue and mood, with topics and a score that build into a trend you can bring to feedback sessions.'],
        ['Easy for clients with fatigue', 'Under a minute, by voice or text, with optional guided questions and daily reminders at the time they choose.'],
        ['DAP notes and reports', 'A DAP note from their check-ins and your own words, plus progress reports and letters to a doctor or school drafted from the history.'],
        ['Strategies between sessions', 'Assign compensatory strategies and ask about them in each check-in, so you know what was used and what helped.']],
      faq: [['Is this an assessment tool?', 'No. Between collects what clients report between visits and never diagnoses; your clinical judgment always decides.'],
        ['Can a relative help with check-ins?', 'Clients send their own check-ins; for a minor, the consent required by your order is obtained before inviting them.'],
        ['Who can see the data?', 'Only you, as the professional who invited the client, and the client. Nothing is shared across a clinic.']] },
    fr: { h: 'Between pour les neuropsychologues',
      intro: 'Entre les évaluations et les séances, vos clients remarquent quand la concentration flanche, quand les oublis s’accumulent ou quand la fatigue mentale s’installe. Between leur donne une façon rapide de le noter sur le moment; vous voyez la tendance sur plusieurs semaines plutôt qu’un seul instantané le jour du rendez-vous.',
      points: [['Les symptômes cognitifs dans le temps', 'Des suivis sur la concentration, la mémoire, la fatigue mentale et l’humeur, avec des sujets et un score qui forment une tendance utile lors des rencontres de rétroaction.'],
        ['Simple malgré la fatigue', 'Moins d’une minute, par la voix ou par écrit, avec des questions guidées au besoin et des rappels quotidiens à l’heure choisie.'],
        ['Notes DAP et rapports', 'Une note DAP tirée des suivis et de vos propres mots, ainsi que des rapports d’évolution et des lettres à un médecin ou à une école, rédigés à partir de l’historique.'],
        ['Des stratégies entre les séances', 'Assignez des stratégies compensatoires et faites le point à chaque suivi, pour savoir ce qui a été utilisé et ce qui a aidé.']],
      faq: [['Est-ce un outil d’évaluation?', 'Non. Between recueille ce que les clients rapportent entre les visites et ne pose jamais de diagnostic; votre jugement clinique décide toujours.'],
        ['Un proche peut-il aider aux suivis?', 'Les clients envoient leurs propres suivis; pour un mineur, le consentement exigé par votre ordre est obtenu avant l’invitation.'],
        ['Qui peut voir les données?', 'Seulement vous, le professionnel qui a invité le client, et le client. Rien n’est partagé dans la clinique.']] }
  },
  '/nutrition': {
    en: { h: 'Between for nutritionists',
      intro: 'Food choices happen at 9 p.m. in the kitchen, not in your office. Between lets clients tell you about energy, cravings, meals and what got in the way as it happens, so the next session starts from their real week and the plan can adapt.',
      points: [['Energy, cravings and meals', 'Quick topics made for nutrition — meals, snacking, hydration, digestion, energy — plus a score and a few words or a voice memo.'],
        ['Habits to practise', 'Set habits like “water with each meal” and ask about them in each check-in; you see what stuck and what didn’t.'],
        ['ADIME notes', 'An ADIME note drafted from their check-ins and your own words, with placeholders for your nutrition diagnosis and intervention.'],
        ['The trigger map', 'A short read of what tends to come before harder days — stress, sleep, skipped meals — from their own check-ins.']],
      faq: [['Do clients have to log every meal?', 'No. Between is not a food diary: a check-in takes under a minute and covers what mattered, when it mattered.'],
        ['Does it give nutrition advice?', 'No. Between documents what clients report; the advice and the plan stay yours.'],
        ['Can I keep my own charting software?', 'Yes. Copy the note, or save it as PDF or Word, into whatever you already use.']] },
    fr: { h: 'Between pour les nutritionnistes',
      intro: 'Les choix alimentaires se font à 21 h dans la cuisine, pas dans votre bureau. Between permet à vos clients de vous parler de leur énergie, de leurs envies, de leurs repas et de ce qui a nui au moment où ça se passe; la séance suivante part de leur vraie semaine et le plan peut s’ajuster.',
      points: [['Énergie, envies et repas', 'Des sujets rapides pensés pour la nutrition — repas, grignotage, hydratation, digestion, énergie — avec un score et quelques mots ou une note vocale.'],
        ['Des habitudes à pratiquer', 'Fixez des habitudes comme « de l’eau à chaque repas » et faites le point à chaque suivi; vous voyez ce qui tient et ce qui ne tient pas.'],
        ['Des notes ADIME', 'Une note ADIME rédigée à partir des suivis et de vos propres mots, avec des espaces pour votre diagnostic nutritionnel et votre intervention.'],
        ['La carte des déclencheurs', 'Une courte lecture de ce qui précède souvent les journées plus difficiles — stress, sommeil, repas sautés — à partir de leurs propres suivis.']],
      faq: [['Les clients doivent-ils noter chaque repas?', 'Non. Between n’est pas un journal alimentaire : un suivi prend moins d’une minute et porte sur ce qui comptait, au moment où ça comptait.'],
        ['Est-ce que Between donne des conseils nutritionnels?', 'Non. Between documente ce que rapportent les clients; les conseils et le plan restent les vôtres.'],
        ['Puis-je garder mon logiciel de dossiers?', 'Oui. Copiez la note, ou enregistrez-la en PDF ou en Word, dans ce que vous utilisez déjà.']] }
  },
  '/sports': {
    en: { h: 'Between for sports teams and coaches',
      intro: 'How a player slept, how sore they are and how they are feeling about the season rarely reaches the coach before practice. Between gives every player a quick check-in between practices, games and tournaments, so you see who is ready, who is sore and who needs a word.',
      points: [['Readiness at a glance', 'Players check in on energy, soreness, sleep and mood; you see the whole team and who needs attention first.'],
        ['Soreness on a body map', 'Players mark sore spots on a body map with how they feel, so small knocks are visible before they become injuries.'],
        ['Training they follow', 'Assign mobility or recovery work and ask about it in each check-in; completion shows per player.'],
        ['Messages to players', 'Send a short note with exercises attached; players read it on their check-in page.']],
      faq: [['Does it work for youth teams?', 'Yes, with the appropriate consent: for players under 14 in Quebec, a parent or guardian must agree before they are invited.'],
        ['Can players see each other’s check-ins?', 'No. Each player sees only their own, and only the coach who invited them sees theirs.'],
        ['Do players need an app?', 'No, it works in the browser on any phone, with daily reminders at a time each player picks.']] },
    fr: { h: 'Between pour les équipes sportives et les entraîneurs',
      intro: 'Comment une ou un athlète a dormi, à quel point ça fait mal et comment se vit la saison se rend rarement au personnel d’entraînement avant la pratique. Between donne à chaque athlète un suivi rapide entre les pratiques, les matchs et les tournois; vous voyez qui est en forme, qui a mal et à qui parler.',
      points: [['La forme de l’équipe d’un coup d’œil', 'Les athlètes font le point sur leur énergie, leurs courbatures, leur sommeil et leur humeur; vous voyez toute l’équipe et qui a besoin d’attention en premier.'],
        ['Les courbatures sur une carte du corps', 'Les athlètes indiquent les zones douloureuses et leur sensation, pour voir les petits bobos avant qu’ils deviennent des blessures.'],
        ['Un entraînement suivi', 'Assignez de la mobilité ou de la récupération et faites le point à chaque suivi; l’assiduité s’affiche pour chaque athlète.'],
        ['Des messages aux athlètes', 'Envoyez un court mot avec des exercices joints; les athlètes le lisent sur leur page de suivi.']],
      faq: [['Est-ce utile pour les équipes de jeunes?', 'Oui, avec le consentement approprié : au Québec, pour une ou un athlète de moins de 14 ans, un parent ou tuteur doit accepter avant l’invitation.'],
        ['Les athlètes voient-ils les suivis des autres?', 'Non. Chaque athlète ne voit que les siens, et seule la personne qui a envoyé l’invitation les voit aussi.'],
        ['Les athlètes ont-ils besoin d’une application?', 'Non, ça fonctionne dans le navigateur de n’importe quel téléphone, avec des rappels quotidiens à l’heure choisie par chaque athlète.']] }
  },
  '/fitness': {
    en: { h: 'Between for personal trainers',
      intro: 'Clients drift between sessions: a missed workout turns into a missed week. Between gives them a one-minute check-in between workouts, so you see energy, soreness and what they actually did, and can step in before they fall off.',
      points: [['Who is drifting', 'A list of clients who have gone quiet or whose energy is dropping, so you reach out at the right time.'],
        ['Workouts, ticked off', 'Assign workouts with sets and reps; clients tick what they did, and you see completion per exercise.'],
        ['Soreness on a body map', 'Clients mark sore spots and how they feel, so you can adjust the next session.'],
        ['Program suggestions', 'Between suggests what to progress or ease off based on what they did and how they felt. You approve every change.']],
      faq: [['Is it only for clinics?', 'No. Independent trainers use it on their own; studios can put the whole team on one plan.'],
        ['Will clients find it a chore?', 'A check-in takes under a minute, with reminders at the time they choose, and they see their own progress build.'],
        ['Can I try it first?', 'Yes, there is a 14-day free trial, and you can cancel anytime.']] },
    fr: { h: 'Between pour les entraîneurs personnels',
      intro: 'Entre les séances, les clients décrochent : un entraînement manqué devient une semaine manquée. Between leur offre un suivi d’une minute entre les entraînements; vous voyez leur énergie, leurs courbatures et ce qu’ils ont vraiment fait, et vous intervenez avant qu’ils abandonnent.',
      points: [['Qui décroche', 'La liste des clients silencieux ou dont l’énergie baisse, pour les relancer au bon moment.'],
        ['Les entraînements, cochés', 'Assignez des entraînements avec séries et répétitions; le client coche ce qu’il a fait, et vous voyez l’assiduité par exercice.'],
        ['Les courbatures sur une carte du corps', 'Les clients indiquent les zones douloureuses et leur sensation, pour ajuster la séance suivante.'],
        ['Des suggestions de programme', 'Between suggère quoi faire progresser ou alléger selon ce qui a été fait et ressenti. Vous approuvez chaque changement.']],
      faq: [['Est-ce seulement pour les cliniques?', 'Non. Les entraîneurs indépendants l’utilisent seuls; les studios peuvent réunir toute l’équipe dans un seul forfait.'],
        ['Les clients vont-ils trouver ça lourd?', 'Un suivi prend moins d’une minute, avec des rappels à l’heure choisie, et ils voient leurs propres progrès se construire.'],
        ['Puis-je l’essayer d’abord?', 'Oui, avec un essai gratuit de 14 jours, et vous pouvez annuler en tout temps.']] }
  },
  '/addiction': {
    en: { h: 'Between for recovery programs',
      intro: 'The hardest moments in recovery rarely happen during a meeting. Between gives members a private, one-minute check-in between meetings, so mentors see cravings, triggers and mood building up, and members always have crisis lines one tap away.',
      points: [['An early-warning view', 'Cravings, triggers and mood over time, with a list of who has gone quiet or is struggling, so mentors can reach out first.'],
        ['Daily recovery practices', 'Set practices like “call your support person” and ask about them in each check-in; members see their own streaks.'],
        ['Crisis lines, always', 'If a check-in sounds like a crisis, the member sees crisis resources right away. They never wait on anyone.'],
        ['Notes for the program', 'A DAP note from check-ins and the mentor’s own words, plus summaries for the team.']],
      faq: [['Is Between a crisis or monitoring service?', 'No. Nobody watches check-ins in real time; crisis resources are shown to the member directly, and mentors are never on call through it.'],
        ['Is it confidential?', 'Each member’s check-ins are visible only to the mentor who invited them. AI summaries stay off until the member turns them on.'],
        ['Can members delete what they wrote?', 'Yes. Members can export or delete their own check-ins at any time, and leaving the program removes their data.']] },
    fr: { h: 'Between pour les programmes de rétablissement',
      intro: 'Les moments les plus difficiles du rétablissement arrivent rarement pendant une rencontre. Between offre aux participants un suivi privé d’une minute entre les rencontres; les mentors voient les envies, les déclencheurs et l’humeur qui montent, et les participants ont toujours les lignes de crise à portée de main.',
      points: [['Une vue d’alerte précoce', 'Les envies, les déclencheurs et l’humeur dans le temps, avec la liste de ceux qui se sont tus ou qui ont du mal, pour que les mentors fassent le premier pas.'],
        ['Des pratiques quotidiennes', 'Fixez des pratiques comme « appeler votre personne de soutien » et faites le point à chaque suivi; les participants voient leurs propres séries.'],
        ['Les lignes de crise, toujours', 'Si un suivi évoque une crise, le participant voit aussitôt les ressources d’aide. Il n’attend jamais personne.'],
        ['Des notes pour le programme', 'Une note DAP tirée des suivis et des mots du mentor, ainsi que des résumés pour l’équipe.']],
      faq: [['Between est-il un service de crise ou de surveillance?', 'Non. Personne ne surveille les suivis en temps réel; les ressources de crise sont affichées directement au participant, et les mentors ne sont jamais de garde par son entremise.'],
        ['Est-ce confidentiel?', 'Les suivis de chaque participant ne sont visibles que par le mentor qui l’a invité. Les résumés IA restent désactivés jusqu’à ce que le participant les active.'],
        ['Les participants peuvent-ils supprimer ce qu’ils ont écrit?', 'Oui. Ils peuvent exporter ou supprimer leurs propres suivis en tout temps, et quitter le programme efface leurs données.']] }
  },
  '/schools': {
    en: { h: 'Between for schools',
      intro: 'Counsellors, psychoeducators and school staff see students for a few minutes a week; the rest of the week is invisible. Between gives students a short, private check-in between meetings, so staff see who is struggling and what keeps coming up.',
      points: [['Who needs a check-in today', 'Students with a worrying trend, a safety flag or a long silence come first, with the reason.'],
        ['Made for students', 'Topics like school, home life and how they are feeling, voice or text, in under a minute, in French or English.'],
        ['Strategies to practise', 'Assign strategies like breaking homework into steps and ask about them in each check-in.'],
        ['A school data agreement', 'A written agreement ready to sign, covering roles, consent for minors, safeguards and deletion.']],
      faq: [['What about consent for minors?', 'The school obtains any parental or guardian consent required before inviting a student; in Quebec, for students under 14, a parent or guardian must agree.'],
        ['Can other staff see a student’s check-ins?', 'No. Only the staff member who invited the student sees them; nothing is shared across the school by default.'],
        ['Is it a crisis service?', 'No. Students who write something worrying see crisis resources right away, and the school keeps its own safeguarding procedures.']] },
    fr: { h: 'Between pour les écoles',
      intro: 'Les conseillers, psychoéducateurs et autres intervenants voient les élèves quelques minutes par semaine; le reste de la semaine reste invisible. Between offre aux élèves un suivi court et privé entre les rencontres; le personnel voit qui a du mal et ce qui revient souvent.',
      points: [['Qui voir aujourd’hui', 'Les élèves dont la tendance inquiète, qui ont un signalement ou un long silence passent en premier, avec la raison.'],
        ['Pensé pour les élèves', 'Des sujets comme l’école, la maison et comment ils se sentent, par la voix ou par écrit, en moins d’une minute, en français ou en anglais.'],
        ['Des stratégies à pratiquer', 'Assignez des stratégies comme découper ses devoirs en étapes et faites le point à chaque suivi.'],
        ['Une entente sur les données scolaires', 'Une entente écrite prête à signer, qui couvre les rôles, le consentement des mineurs, les mesures de protection et la suppression.']],
      faq: [['Et le consentement des mineurs?', 'L’école obtient tout consentement parental requis avant d’inviter un élève; au Québec, pour les élèves de moins de 14 ans, un parent ou tuteur doit accepter.'],
        ['Les autres intervenants voient-ils les suivis?', 'Non. Seul l’intervenant qui a invité l’élève les voit; rien n’est partagé dans l’école par défaut.'],
        ['Est-ce un service de crise?', 'Non. L’élève qui écrit quelque chose d’inquiétant voit aussitôt les ressources d’aide, et l’école garde ses propres procédures de protection.']] }
  },
  '/individual': {
    en: { h: 'Between, just for you',
      intro: 'Not everyone has a professional to talk to, and not every week needs one. Between gives you a private place to check in with yourself in under a minute, by voice or text, and turns those check-ins into a mood trend and the themes that keep returning.',
      points: [['Your mood, over time', 'A 1–10 score and a few words; Between builds the trend and shows what tends to come with your harder days.'],
        ['Mind, body, sport or eating', 'Choose what you want to track. For body and sport, mark where it hurts on a body map.'],
        ['Goals and notes to yourself', 'Keep up to two short intentions in view, and write words for a harder day that come back when you need them.'],
        ['Bring it to a professional', 'If you start seeing someone, share a clean summary of your weeks instead of starting from scratch.']],
      faq: [['Is it free?', 'Yes, with a weekly number of check-ins. Personal Premium adds unlimited check-ins, advanced stats, question packs and a weekly reflection.'],
        ['Who can see my check-ins?', 'Only you. Nobody else has access, and you can export or delete everything at any time.'],
        ['Is it therapy?', 'No, and it is not a crisis service. If a check-in sounds like a crisis, you see crisis lines right away.']] },
    fr: { h: 'Between, juste pour vous',
      intro: 'Tout le monde n’a pas quelqu’un à qui parler, et toutes les semaines n’en ont pas besoin. Between vous offre un endroit privé pour faire le point avec vous-même en moins d’une minute, par la voix ou par écrit, et transforme ces suivis en une tendance de l’humeur et en thèmes qui reviennent.',
      points: [['Votre humeur dans le temps', 'Un score de 1 à 10 et quelques mots; Between trace la tendance et montre ce qui accompagne souvent vos journées plus difficiles.'],
        ['Esprit, corps, sport ou alimentation', 'Choisissez ce que vous voulez suivre. Pour le corps et le sport, indiquez où ça fait mal sur une carte du corps.'],
        ['Objectifs et mots pour vous-même', 'Gardez jusqu’à deux courtes intentions en vue, et écrivez des mots pour un jour difficile, qui reviennent au bon moment.'],
        ['À apporter à une professionnelle ou un professionnel', 'Si vous commencez à consulter, partagez un résumé clair de vos semaines au lieu de repartir de zéro.']],
      faq: [['Est-ce gratuit?', 'Oui, avec un nombre de suivis par semaine. Personnel Premium ajoute les suivis illimités, des statistiques avancées, des ensembles de questions et une réflexion de la semaine.'],
        ['Qui peut voir mes suivis?', 'Seulement vous. Personne d’autre n’y a accès, et vous pouvez tout exporter ou supprimer en tout temps.'],
        ['Est-ce une thérapie?', 'Non, et ce n’est pas un service de crise. Si un suivi évoque une crise, vous voyez aussitôt les lignes d’aide.']] }
  }
};

const esc = s => String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const urlFor = (path, fr) => (fr ? '/fr' : '') + (path === '/therapy' ? (fr ? '' : '/') : path);

// Normalise any field URL ("/fr/physio", "/therapy", "/") to its key.
export function fieldKey(path) {
  const p = String(path || '/').replace(/\/+$/, '').replace(/^\/fr(?=\/|$)/, '') || '/';
  return FIELDS[p] ? p : '/';
}

// The HTML block for one page ('/' = the home overview).
export function fieldCopyHtml(path, lang) {
  const fr = lang === 'fr', L = fr ? 'fr' : 'en', key = fieldKey(path);
  const others = ORDER.filter(p => p !== key);
  const linkList = list => '<ul class="btw-fieldcopy-links">' + list.map(p => `<li><a href="${urlFor(p, fr)}">${esc(NAMES[p][fr ? 1 : 0])}</a></li>`).join('') + '</ul>';
  // The home page is just the "Who's it for?" chooser: no long overview below it.
  if (key === '/') return '';
  const C = FIELDS[key][L];
  return `<div class="btw-section-label">${esc(NAMES[key][fr ? 1 : 0])}</div><h2>${esc(C.h)}</h2><p class="btw-fieldcopy-intro">${esc(C.intro)}</p>`
    + '<div class="btw-fieldcopy-points">' + C.points.map(([t, d]) => `<div class="btw-fieldcopy-point"><h3>${esc(t)}</h3><p>${esc(d)}</p></div>`).join('') + '</div>'
    + `<h3 class="btw-fieldcopy-faqh">${fr ? 'Questions fréquentes' : 'Common questions'}</h3>`
    + '<div class="btw-fieldcopy-faq">' + C.faq.map(([q, a]) => `<details><summary>${esc(q)}</summary><p>${esc(a)}</p></details>`).join('') + '</div>'
    + `<p class="btw-fieldcopy-otherh">${fr ? 'Between pour d’autres domaines' : 'Between for other fields'}</p>` + linkList(others);
}

// FAQPage structured data for a field page (none for the home overview).
export function fieldFaqJsonLd(path, lang) {
  const key = fieldKey(path);
  if (key === '/') return '';
  const C = FIELDS[key][lang === 'fr' ? 'fr' : 'en'];
  const data = { '@context': 'https://schema.org', '@type': 'FAQPage', inLanguage: lang === 'fr' ? 'fr-CA' : 'en-CA',
    mainEntity: C.faq.map(([q, a]) => ({ '@type': 'Question', name: q, acceptedAnswer: { '@type': 'Answer', text: a } })) };
  return '<script type="application/ld+json" id="btwFieldFaq">' + JSON.stringify(data).replace(/</g, '\\u003c') + '</script>';
}

export const FIELD_COPY_KEYS = Object.keys(FIELDS);
