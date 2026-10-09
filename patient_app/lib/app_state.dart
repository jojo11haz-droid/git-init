import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api.dart';
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
  bool get hasClinician => clinicianAccountType != null;
  // Writing a future-self note is covered for clinician patients and Premium
  // individuals (mirrors the server's subscription gate). Reading is always on.
  bool get canWriteFutureNote => hasClinician || isPremium;
}

class CheckIn {
  CheckIn(this.raw);

  final Map<String, dynamic> raw;

  String get id => raw['id'] as String;
  int? get mood => raw['mood_score'] as int?;
  bool get moodInferred => raw['mood_inferred'] == true;
  List<String> get tags => [
        ...((raw['manual_tags'] as List?) ?? const []),
        ...((raw['auto_tags'] as List?) ?? const []),
      ].cast<String>().toSet().toList();
  String get summary =>
      (raw['summary_text'] as String?) ??
      (raw['raw_text'] as String?) ??
      (hasAudio ? 'Voice memo (no transcript yet).' : 'Check-in sent.');
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
  bool get riskFlag => raw['risk_flag'] == true;
  bool get flaggedInaccurate => raw['patient_flagged_inaccurate'] == true;
  DateTime get submittedAt =>
      DateTime.parse(raw['submitted_at'] as String).toLocal();
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
        _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'between_patient_token';
  static const _langKey = 'between_patient_lang';
  static const _healthKey = 'between_health_connected';

  final ApiClient _api;
  final FlutterSecureStorage _storage;
  final HealthService _health = HealthService();

  Patient? patient;
  bool restoring = true;

  /// Shown once, right after a brand-new account is created (signup or accepted
  /// invite), between consent and the home screen. Not shown to returning users.
  bool showOnboarding = false;
  void finishOnboarding() {
    showOnboarding = false;
    notifyListeners();
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
    int? mood, // null = let Between estimate it from the check-in (needs AI on)
    required List<String> tags,
    String? audioUploadId,
    String? photoUploadId,
    Map<String, int>? painMap,
    String? inputMode,
  }) async {
    final data = await _api.post('/api/patient/check-ins', {
      'text': text,
      if (mood != null) 'moodScore': mood,
      'manualTags': tags,
      'audioUploadId': audioUploadId,
      if (photoUploadId != null) 'photoUploadId': photoUploadId,
      if (painMap != null && painMap.isNotEmpty) 'painMap': painMap,
      if (inputMode != null) 'inputMode': inputMode,
    });
    final map = (data as Map).cast<String, dynamic>();
    return SendResult(
      CheckIn((map['checkIn'] as Map).cast<String, dynamic>()),
      (map['crisis'] as Map?)?.cast<String, dynamic>(),
    );
  }

  Future<List<CheckIn>> fetchHistory() async {
    final data = await _api.get('/api/patient/check-ins') as List;
    return data
        .map((row) => CheckIn((row as Map).cast<String, dynamic>()))
        .toList();
  }

  /// Grace-period undo for a just-sent check-in.
  Future<void> undoCheckIn(String id) => _api.delete('/api/patient/check-ins/$id');

  /// Law 25 erasure request — soft-deletes the whole history.
  Future<void> requestDeletion() => _api.delete('/api/patient/check-ins');

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
