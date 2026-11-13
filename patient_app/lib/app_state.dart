import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api.dart';
import 'discipline.dart';
import 'health_service.dart';
import 'strings.dart';

class Patient {
  Patient(this.raw);

  final Map<String, dynamic> raw;

  String get id => raw['id'] as String;
  String get displayName => (raw['display_name'] as String?) ?? '';
  String get firstName => displayName.trim().split(' ').first;
  bool get aiConsentEnabled => raw['ai_consent_enabled'] == true;
  bool get hasRecordedConsent => raw['consent_recorded_at'] != null;
  // The clinician who invited this patient, if any (null for solo accounts).
  String? get clinicianAccountType => raw['clinician_account_type'] as String?;
  String? get clinicianDiscipline => raw['clinician_discipline'] as String?;
  bool get isPremium => raw['is_premium'] == true;
  // A paid personal plan and where its subscription stands ('active',
  // 'trialing', 'canceling', 'past_due'…). Null for a client whose
  // professional covers them.
  String? get plan => raw['plan'] as String?;
  String? get subscriptionStatus => raw['subscription_status'] as String?;
  bool get hasLiveSubscription =>
      plan != null &&
      const {'active', 'trialing', 'past_due', 'unpaid'}
          .contains(subscriptionStatus);
  bool get subscriptionCanceling =>
      plan != null && subscriptionStatus == 'canceling';
  // The last payment failed: cancelling ends it at once, with nothing more charged.
  bool get subscriptionLapsed =>
      plan != null &&
      const {'past_due', 'unpaid'}.contains(subscriptionStatus);
  // The body map's Man / Woman figure, saved on the account ('m' / 'f').
  String? get bodySex => raw['body_sex'] as String?;
  bool get hasClinician => clinicianAccountType != null;
  // Their program lives in another exercise app (Wibbi, Physitrack…): the
  // check-in asks "did you do your exercises?" instead of listing them.
  bool get exercisesExternal => raw['exercises_external'] == true;
  String? get exercisesApp => raw['exercises_app'] as String?;
  // Their professional's branding: a welcome note (any plan) and, on the
  // professional's Premium plan, clinic name, logo and accent.
  Map<String, dynamic> get _brand =>
      ((raw['clinician_brand'] as Map?) ?? const {}).cast<String, dynamic>();
  String get brandWelcome => (_brand['welcome'] as String?) ?? '';
  String get brandClinic => (_brand['clinic'] as String?) ?? '';
  String? get brandLogoUrl => _brand['logo_url'] as String?;
  String? get clinicianName => raw['clinician_name'] as String?;
  bool get hasBrand =>
      brandWelcome.isNotEmpty || brandClinic.isNotEmpty || brandLogoUrl != null;
  // A Premium individual's own page preferences.
  Map<String, dynamic> get _prefs =>
      ((raw['prefs'] as Map?) ?? const {}).cast<String, dynamic>();
  String get ownAccent => (_prefs['accent'] as String?) ?? '';
  List<String> get hiddenSections =>
      ((_prefs['hide'] as List?) ?? const []).map((e) => e.toString()).toList();
  bool hides(String section) => hiddenSections.contains(section);
  // The accent in effect: the professional's, else their own.
  String? get accentKey {
    final b = _brand['accent'] as String?;
    if (b != null && b.isNotEmpty) return b;
    return ownAccent.isNotEmpty ? ownAccent : null;
  }
  // A self-serve individual's own intentions (up to two short lines).
  List<String> get goals =>
      ((raw['goals'] as List?) ?? const []).map((e) => e.toString()).toList();
  // Writing a future-self note is covered for clinician patients and Premium
  // individuals (mirrors the server's subscription gate). Reading is always on.
  bool get canWriteFutureNote => hasClinician || isPremium;
}

/// Before each field had its own check-in topics, the website saved some
/// recovery, nutrition and school topics under the therapy word they replaced
/// (a nutrition client tapping "Hydration" saved "Panic"). Those are read back
/// as what was tapped. Mirrors LEGACY_TAG_ALIAS in clinical.js / index.html.
const Map<String, Map<String, String>> kLegacyTagAlias = {
  'recovery': {'Work': 'Cravings', 'Craving': 'Cravings', 'Family': 'Triggers'},
  'nutrition': {
    'Work': 'Meals',
    'Conflict': 'Digestion',
    'Panic': 'Hydration',
    'Family': 'Energy',
    'Money': 'Snacking',
    'Loneliness': 'Stress',
    'Anger': 'Habits',
    'Craving': 'Cravings',
  },
  'schools': {'Work': 'School', 'Family': 'Home life'},
};

/// The field whose old topic words need mapping, from the clinician's account
/// type and discipline (null = none).
String? legacyTagField(String? accountType, String? discipline) {
  if (accountType == 'mentor') return 'recovery';
  if (accountType == 'school') return 'schools';
  if (accountType == 'coach' && discipline == 'nutrition') return 'nutrition';
  return null;
}

class CheckIn {
  CheckIn(this.raw, {this.tagField});

  final Map<String, dynamic> raw;

  /// See [kLegacyTagAlias]; null when the patient's field needs no mapping.
  final String? tagField;

  String get id => raw['id'] as String;
  int? get mood => raw['mood_score'] as int?;
  // One short follow-up question Between asked after this check-in, and the
  // patient's answer (both null when there was none).
  String? get followupQuestion => raw['followup_q'] as String?;
  // Program in another app: did they do their exercises ('yes'/'some'/'no').
  String? get exerciseStatus => raw['exercise_status'] as String?;
  String? get followupAnswer => raw['followup_a'] as String?;
  bool get moodInferred => raw['mood_inferred'] == true;
  List<String> get tags {
    final alias = kLegacyTagAlias[tagField] ?? const <String, String>{};
    // A set literal: same order, duplicates dropped (an old and a new spelling
    // of one topic collapse into one).
    return <String>{
      ...((raw['manual_tags'] as List?) ?? const [])
          .map((t) => alias[t.toString()] ?? t.toString()),
      ...((raw['auto_tags'] as List?) ?? const []).map((t) => t.toString()),
    }.toList();
  }
  String get summary =>
      (raw['summary_text'] as String?) ??
      (raw['raw_text'] as String?) ??
      (hasAudio ? 'Voice memo (no transcript yet).' : 'Check-in sent.');
  String? get rawText => raw['raw_text'] as String?;
  bool get hasPhoto => raw['photo_upload_id'] != null;
  bool get hasAudio => raw['audio_upload_id'] != null;
  bool get isAiSummary => raw['model_version'] != null;
  // Pain map for body disciplines: { "view:region": level 1..10 }, or null.
  Map<String, int>? get painMap {
    final pm = raw['pain_map'];
    if (pm is Map && pm.isNotEmpty) {
      final out = <String, int>{};
      pm.forEach((k, v) {
        if (v is num) out[k.toString()] = v.toInt();
      });
      return out.isEmpty ? null : out;
    }
    return null;
  }
  // Which body figure the pain map was drawn on: 'm' | 'f', or null (older).
  String? get bodySex {
    final v = raw['body_sex'];
    return (v == 'm' || v == 'f') ? v as String : null;
  }

  // How each sore spot feels: { "view:region": sensation code }, or null.
  Map<String, String>? get painSens {
    final ps = raw['pain_sensations'];
    if (ps is Map && ps.isNotEmpty) {
      final out = <String, String>{};
      ps.forEach((k, v) {
        if (v is String) out[k.toString()] = v;
      });
      return out.isEmpty ? null : out;
    }
    return null;
  }
  bool get riskFlag => raw['risk_flag'] == true;
  bool get flaggedInaccurate => raw['patient_flagged_inaccurate'] == true;
  DateTime get submittedAt =>
      DateTime.parse(raw['submitted_at'] as String).toLocal();
}

/// An intake document the patient shared, plus the AI starting summary that
/// Between prepared for the clinician (only present once ai_status == 'done').
/// One exercise in the patient's home program, assigned by their clinician.
class HomeExercise {
  HomeExercise(this.raw);
  final Map<String, dynamic> raw;
  String get id => raw['id'] as String;
  String get name => (raw['name'] as String?) ?? '';
  String? get description => raw['description'] as String?;
  String? get dosage => raw['dosage'] as String?;
}

/// A message from the client's professional, sent from the website, with any
/// exercises from their program attached.
class ClinicianMessage {
  ClinicianMessage(this.raw);
  final Map<String, dynamic> raw;
  String get id => raw['id'] as String;
  String get body => (raw['body'] as String?) ?? '';
  bool get isRead => raw['read_at'] != null;
  DateTime? get createdAt =>
      DateTime.tryParse((raw['created_at'] as String?) ?? '')?.toLocal();
  List<HomeExercise> get exercises => ((raw['exercises'] as List?) ?? const [])
      .map((e) => HomeExercise((e as Map).cast<String, dynamic>()))
      .toList();
}

class PatientDocument {
  PatientDocument(this.raw);

  final Map<String, dynamic> raw;

  String get id => raw['id'] as String;
  String? get filename => raw['filename'] as String?;
  String get kind => (raw['kind'] as String?) ?? 'image'; // 'pdf' | 'image'
  String get uploadedBy => (raw['uploaded_by'] as String?) ?? 'patient';
  String get aiStatus => (raw['ai_status'] as String?) ?? 'pending';
  String? get aiSummary => raw['ai_summary'] as String?;
  String? get primaryConcern {
    final f = raw['ai_fields'];
    return (f is Map) ? f['primary_concern'] as String? : null;
  }

  List<MapEntry<String, String>> get highlights {
    final f = raw['ai_fields'];
    if (f is Map && f['highlights'] is List) {
      return (f['highlights'] as List)
          .whereType<Map>()
          .where((h) => h['label'] is String && h['value'] is String)
          .map((h) =>
              MapEntry(h['label'] as String, h['value'] as String))
          .toList();
    }
    return const [];
  }
}

/// Result of sending a check-in: the stored row plus the crisis payload the
/// server attaches when risk language was detected. Crisis resources come
/// straight back in this response — they never wait on the therapist.
class SendResult {
  SendResult(this.checkIn, this.crisis);

  final CheckIn checkIn;
  final Map<String, dynamic>? crisis;
}

class AppState extends ChangeNotifier {
  AppState({ApiClient? api, FlutterSecureStorage? storage})
      : _api = api ?? ApiClient(),
        _storage = storage ?? const FlutterSecureStorage() {
    // Every request carries the app's language, so server messages match it.
    _api.langOf = () => langCode(lang);
  }

  static const _tokenKey = 'between_patient_token';
  static const _langKey = 'between_patient_lang';
  static const _healthKey = 'between_health_connected';
  static const _tourKey = 'between_tour_seen';

  final ApiClient _api;
  final FlutterSecureStorage _storage;
  final HealthService _health = HealthService();

  Patient? patient;
  // Who reads this person's check-ins (physio, coach, mentor…), or null when
  // they use Between on their own. Drives "your physio will see this" copy.
  String? get providerKey =>
      patient == null ? null : profileFor(patient!).providerKey;
  String? get _legacyTagField => legacyTagField(
      patient?.clinicianAccountType, patient?.clinicianDiscipline);
  bool restoring = true;

  /// Shown once, right after a brand-new account is created (signup or accepted
  /// invite), between consent and the home screen. Not shown to returning users.
  bool showOnboarding = false;
  void finishOnboarding() {
    showOnboarding = false;
    notifyListeners();
  }

  /// The home-screen spotlight tour shows once (tracked locally), and can be
  /// replayed from the Guide, which sets [startTourRequested] for the home
  /// screen to pick up.
  bool tourSeen = false;
  bool startTourRequested = false;
  Future<void> markTourSeen() async {
    tourSeen = true;
    try {
      await _storage.write(key: _tourKey, value: '1');
    } catch (_) {/* best effort */}
  }

  void requestTour() {
    startTourRequested = true;
    notifyListeners();
  }

  void clearTourRequest() {
    startTourRequested = false;
  }

  /// Whether the person has connected Apple Health (persisted locally).
  bool healthConnected = false;
  bool get healthSupported => _health.isSupported;

  /// Preview a different discipline's check-in (a testing aid). Null = use the
  /// account's real discipline. Not persisted — it resets on relaunch.
  String? previewCategory;
  void setPreviewCategory(String? key) {
    previewCategory = key;
    notifyListeners();
  }

  AppLang lang = detectInitialLang();
  S get s => S(lang);

  bool get signedIn => patient != null;

  Future<void> setLang(AppLang value) async {
    if (lang == value) return;
    lang = value;
    notifyListeners();
    try {
      await _storage.write(key: _langKey, value: langCode(value));
    } catch (_) {/* best effort */}
  }

  /// Try to restore a stored session on app launch.
  Future<void> restore() async {
    try {
      final storedLang = await _storage.read(key: _langKey);
      if (storedLang != null) lang = langFromCode(storedLang);
    } catch (_) {/* fall back to device language */}
    try {
      healthConnected = (await _storage.read(key: _healthKey)) == '1';
    } catch (_) {/* default off */}
    try {
      tourSeen = (await _storage.read(key: _tourKey)) == '1';
    } catch (_) {/* default: show the tour */}
    try {
      final token = await _storage.read(key: _tokenKey);
      if (token != null) {
        _api.token = token;
        final data = await _api.get('/api/patient/me');
        patient = Patient((data['patient'] as Map).cast<String, dynamic>());
      }
    } on ApiException catch (e) {
      if (e.status == 401) await _clearToken();
    } catch (_) {
      // Offline or server unreachable: stay signed out, keep the token for
      // next launch.
      _api.token = null;
    }
    restoring = false;
    notifyListeners();
    // If Health is already connected, quietly refresh in the background.
    if (patient != null && healthConnected) {
      unawaited(syncHealth());
    }
  }

  Future<void> _storeSession(Map<String, dynamic> data) async {
    _api.token = data['token'] as String;
    await _storage.write(key: _tokenKey, value: _api.token);
    patient = Patient((data['patient'] as Map).cast<String, dynamic>());
    notifyListeners();
    // Enrich with the full profile (clinician discipline/type, etc.), which
    // login/accept-invite/signup responses don't all carry — so the check-in
    // screen is tailored to the right discipline straight away. Best effort.
    try {
      final me = await _api.get('/api/patient/me');
      patient = Patient((me['patient'] as Map).cast<String, dynamic>());
      notifyListeners();
    } catch (_) {/* keep the session we already have */}
  }

  Future<void> _clearToken() async {
    _api.token = null;
    await _storage.delete(key: _tokenKey);
  }

  Future<void> login(String email, String password) async {
    final data = await _api.post(
      '/api/patient/login',
      {'email': email, 'password': password},
    );
    await _storeSession((data as Map).cast<String, dynamic>());
  }

  Future<void> acceptInvite(
      String inviteCode, String email, String password) async {
    final data = await _api.post('/api/patient/accept-invite', {
      'inviteCode': inviteCode,
      'email': email,
      'password': password,
    });
    showOnboarding = true; // brand-new account → show the intro once
    await _storeSession((data as Map).cast<String, dynamic>());
  }

  /// Self-serve signup — someone starting Between on their own, no therapist.
  /// plan:'free' creates a free-tier account (no in-app payment), matching the
  /// website's "use it on your own" path without Apple's IAP requirement.
  Future<void> signUpSolo(String name, String email, String password) async {
    final data = await _api.post('/api/patient/signup', {
      'name': name,
      'email': email,
      'password': password,
      'guardianAck': true,
      'plan': 'free',
    });
    showOnboarding = true; // brand-new account → show the intro once
    await _storeSession((data as Map).cast<String, dynamic>());
  }

  Future<void> logout() async {
    try {
      await _api.post('/api/patient/logout');
    } catch (_) {
      // Best effort — the local token is cleared regardless.
    }
    await _clearToken();
    patient = null;
    notifyListeners();
  }

  // Remember the body map's Man / Woman choice on the account (best-effort).
  Future<void> saveBodySex(String sex) async {
    if (patient?.bodySex == sex) return;
    try {
      final data = await _api.put('/api/patient/body-sex', {'sex': sex});
      patient = Patient(
          ((data as Map)['patient'] as Map).cast<String, dynamic>());
    } catch (_) {
      // Offline: the device still remembers it; it syncs on the next change.
    }
  }

  // Save a Premium individual's accent and hidden sections.
  Future<void> savePrefs(String accent, List<String> hide) async {
    final data = await _api.put('/api/patient/prefs', {
      'accent': accent == 'blue' ? '' : accent,
      'hide': hide,
    });
    patient = Patient(
        ((data as Map)['patient'] as Map).cast<String, dynamic>());
    notifyListeners();
  }

  // Save the individual's own intentions/goals (up to two short lines).
  Future<void> saveGoals(List<String> goals) async {
    final data = await _api.put('/api/patient/goals', {'goals': goals});
    patient = Patient(
        ((data as Map)['patient'] as Map).cast<String, dynamic>());
    notifyListeners();
  }

  /// Cancel the subscription at the end of the paid period (access stays
  /// until then), or undo a pending cancellation with [reactivate].
  Future<void> cancelSubscription({bool reactivate = false}) async {
    final data = await _api.post(
        '/api/patient/subscription/cancel', {'reactivate': reactivate});
    patient = Patient(
        ((data as Map)['patient'] as Map).cast<String, dynamic>());
    notifyListeners();
  }

  Future<void> recordConsent({required bool aiEnabled}) async {
    final data = await _api.post('/api/patient/consent', {'enabled': aiEnabled});
    patient = Patient(
        ((data as Map)['patient'] as Map).cast<String, dynamic>());
    notifyListeners();
  }

  /// Voice memo upload, per backend-spec.md: ask for a short-lived signed
  /// URL, then PUT the raw bytes there — audio never rides through the JSON
  /// API. Returns the audioUploadId to attach to a check-in.
  Future<String> uploadAudio(List<int> bytes, String mime) async {
    final grant = await _api.post('/api/patient/check-ins/audio-upload-url');
    final uploadUrl = (grant as Map)['uploadUrl'] as String;
    final result = await _api.putBytes(uploadUrl, bytes, mime);
    return (result as Map)['audioUploadId'] as String;
  }

  /// Photo of a sore area, same signed-URL dance as audio. Returns the
  /// photoUploadId to attach to a check-in.
  Future<String> uploadPhoto(List<int> bytes, String mime) async {
    final grant = await _api.post('/api/patient/check-ins/photo-upload-url');
    final uploadUrl = (grant as Map)['uploadUrl'] as String;
    final result = await _api.putBytes(uploadUrl, bytes, mime);
    return (result as Map)['photoUploadId'] as String;
  }

  // --- Intake documents (AI-reviewed) ---
  // The patient shares a document (a photo/scan of a referral, intake form, or
  // note). Between reviews it, when AI is on, and gives the clinician a starting
  // summary. Same signed-URL dance as photos, plus the filename via a header.
  Future<PatientDocument> uploadDocument(
      List<int> bytes, String mime, String filename) async {
    final grant = await _api.post('/api/patient/documents/upload-url');
    final uploadUrl = (grant as Map)['uploadUrl'] as String;
    final result = await _api.putBytes(uploadUrl, bytes, mime,
        headers: {'X-Filename': Uri.encodeComponent(filename)});
    return PatientDocument(
        ((result as Map)['document'] as Map).cast<String, dynamic>());
  }

  /// The home exercise program to tick off in a check-in (empty if none).
  Future<List<HomeExercise>> fetchExercises() async {
    final data = await _api.get('/api/patient/exercises');
    final list = ((data as Map)['exercises'] as List?) ?? const [];
    return list
        .map((e) => HomeExercise((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<List<ClinicianMessage>> fetchMessages() async {
    final data = await _api.get('/api/patient/messages');
    final list = ((data as Map)['messages'] as List?) ?? const [];
    return list
        .map((m) => ClinicianMessage((m as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<void> markMessagesRead() async {
    await _api.post('/api/patient/messages/read', <String, dynamic>{});
  }

  Future<List<PatientDocument>> fetchDocuments() async {
    final data = await _api.get('/api/patient/documents');
    final list = ((data as Map)['documents'] as List?) ?? const [];
    return list
        .map((d) => PatientDocument((d as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<void> deleteDocument(String id) async {
    await _api.delete('/api/patient/documents/$id');
  }

  // --- Apple Health ---
  // Connect asks HealthKit for read access, remembers the choice, and does a
  // first sync. Returns false if HealthKit is unavailable or access is denied.
  Future<bool> connectHealth() async {
    final granted = await _health.requestAuthorization();
    if (!granted) return false;
    healthConnected = true;
    try {
      await _storage.write(key: _healthKey, value: '1');
    } catch (_) {/* best effort */}
    notifyListeners();
    await syncHealth();
    return true;
  }

  Future<void> disconnectHealth() async {
    healthConnected = false;
    try {
      await _storage.delete(key: _healthKey);
    } catch (_) {/* best effort */}
    notifyListeners();
  }

  /// Read the last week from Apple Health and sync it to the server. Returns
  /// how many days were saved (0 if nothing to send or not connected).
  Future<int> syncHealth({int days = 7}) async {
    if (!healthConnected || patient == null) return 0;
    try {
      final data = await _health.readRecent(days: days);
      final payload = data.where((d) => d.hasAny).map((d) => d.toJson()).toList();
      if (payload.isEmpty) return 0;
      final res = await _api.post('/api/patient/health', {'days': payload});
      return ((res as Map)['saved'] as int?) ?? 0;
    } catch (e) {
      debugPrint('Health sync failed: $e');
      return 0;
    }
  }

  Future<SendResult> sendCheckIn({
    String? text,
    int? mood, // null = let Between estimate it (pain: body map's worst spot or AI; mood: AI)
    required List<String> tags,
    String? audioUploadId,
    String? photoUploadId,
    Map<String, int>? painMap,
    Map<String, String>? painSens,
    String? inputMode,
    bool painScale = false, // the score is pain (physical rehab), not mood
    String? bodySex, // 'm' | 'f': the figure the pain map was drawn on
    List<String>? exercisesDone, // home-program exercise ids ticked off
    String? exerciseStatus, // 'yes' | 'some' | 'no' (program in another app)
  }) async {
    final data = await _api.post('/api/patient/check-ins', {
      // Tells the server which scale a skipped score should be estimated on.
      'scoreKind': painScale ? 'pain' : 'mood',
      'text': text,
      if (mood != null) 'moodScore': mood,
      'manualTags': tags,
      'audioUploadId': audioUploadId,
      if (photoUploadId != null) 'photoUploadId': photoUploadId,
      if (painMap != null && painMap.isNotEmpty) 'painMap': painMap,
      if (painSens != null && painSens.isNotEmpty) 'painSens': painSens,
      // So the clinician sees the spots on the same figure.
      if (painMap != null && painMap.isNotEmpty && bodySex != null)
        'bodySex': bodySex,
      if (exercisesDone != null && exercisesDone.isNotEmpty)
        'exercisesDone': exercisesDone,
      if (exerciseStatus != null) 'exerciseStatus': exerciseStatus,
      if (inputMode != null) 'inputMode': inputMode,
    });
    final map = (data as Map).cast<String, dynamic>();
    return SendResult(
      CheckIn((map['checkIn'] as Map).cast<String, dynamic>(),
          tagField: _legacyTagField),
      (map['crisis'] as Map?)?.cast<String, dynamic>(),
    );
  }

  Future<List<CheckIn>> fetchHistory() async {
    final data = await _api.get('/api/patient/check-ins') as List;
    return data
        .map((row) => CheckIn((row as Map).cast<String, dynamic>(),
            tagField: _legacyTagField))
        .toList();
  }

  /// A warm AI reflection on the patient's own week (Premium). Returns the
  /// reflection text, or null when there aren't enough check-ins this week yet.
  Future<String?> fetchWeeklyReflection() async {
    final data = await _api.get('/api/patient/reflection');
    if (data is Map) {
      if (data['needsData'] == true) return null;
      final r = data['reflection'];
      if (r is String && r.trim().isNotEmpty) return r.trim();
    }
    return null;
  }

  /// The patient's own sore-area photo for a check-in (authed bytes).
  Future<Uint8List> fetchCheckInPhoto(String id) =>
      _api.getBytes('/api/patient/check-ins/$id/photo');

  /// Grace-period undo for a just-sent check-in.
  Future<void> undoCheckIn(String id) => _api.delete('/api/patient/check-ins/$id');

  /// Answer the follow-up question. Returns crisis resources if the answer
  /// raised a safety concern (it's screened like any check-in), else null.
  Future<Map<String, dynamic>?> answerFollowup(String id, String answer) async {
    final data =
        await _api.post('/api/patient/check-ins/$id/followup', {'answer': answer});
    final m = (data as Map).cast<String, dynamic>();
    return (m['crisis'] as Map?)?.cast<String, dynamic>();
  }

  /// Law 25 erasure request — soft-deletes the whole history.
  Future<void> requestDeletion() => _api.delete('/api/patient/check-ins');

  /// A portable copy of everything we hold for this patient — the same JSON
  /// the website's "Download my data" produces (profile + check-ins + future
  /// notes). Returned as a pretty-printed string the UI can share or copy.
  Future<String> buildDataExport() async {
    final results = await Future.wait<dynamic>([
      _api.get('/api/patient/me').catchError((_) => null),
      _api.get('/api/patient/check-ins').catchError((_) => const <dynamic>[]),
      _api.get('/api/patient/future-notes').catchError((_) => const <dynamic>[]),
    ]);
    final me = results[0];
    final profile = (me is Map && me['patient'] is Map) ? me['patient'] : null;
    final payload = <String, dynamic>{
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'account_type': 'patient',
      'profile': profile,
      'check_ins': results[1] is List ? results[1] : const <dynamic>[],
      'future_notes': results[2] is List ? results[2] : const <dynamic>[],
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  Future<void> flagInaccurate(String id) =>
      _api.post('/api/patient/check-ins/$id/flag-inaccurate');

  // --- Future-self notes ---
  // A private note the person leaves for a harder day; surfaced back to them
  // when a check-in's mood is low. Patient-scoped; never shown to a clinician.
  Future<List<Map<String, dynamic>>> fetchFutureNotes() async {
    final data = await _api.get('/api/patient/future-notes') as List;
    return data.map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  Future<void> createFutureNote(String body) =>
      _api.post('/api/patient/future-notes', {'body': body, 'kind': 'note'});

  Future<void> deleteFutureNote(String id) =>
      _api.delete('/api/patient/future-notes/$id');
}
