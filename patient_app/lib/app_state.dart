import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api.dart';

class Patient {
  Patient(this.raw);

  final Map<String, dynamic> raw;

  String get id => raw['id'] as String;
  String get displayName => (raw['display_name'] as String?) ?? '';
  String get firstName => displayName.trim().split(' ').first;
  bool get aiConsentEnabled => raw['ai_consent_enabled'] == true;
  bool get hasRecordedConsent => raw['consent_recorded_at'] != null;
}

class CheckIn {
  CheckIn(this.raw);

  final Map<String, dynamic> raw;

  String get id => raw['id'] as String;
  int? get mood => raw['mood_score'] as int?;
  List<String> get tags => [
        ...((raw['manual_tags'] as List?) ?? const []),
        ...((raw['auto_tags'] as List?) ?? const []),
      ].cast<String>().toSet().toList();
  String get summary =>
      (raw['summary_text'] as String?) ??
      (raw['raw_text'] as String?) ??
      'Check-in sent.';
  bool get isAiSummary => raw['model_version'] != null;
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

  final ApiClient _api;
  final FlutterSecureStorage _storage;

  Patient? patient;
  bool restoring = true;

  bool get signedIn => patient != null;

  /// Try to restore a stored session on app launch.
  Future<void> restore() async {
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
  }

  Future<void> _storeSession(Map<String, dynamic> data) async {
    _api.token = data['token'] as String;
    await _storage.write(key: _tokenKey, value: _api.token);
    patient = Patient((data['patient'] as Map).cast<String, dynamic>());
    notifyListeners();
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

  Future<SendResult> sendCheckIn({
    String? text,
    required int mood,
    required List<String> tags,
  }) async {
    final data = await _api.post('/api/patient/check-ins', {
      'text': text,
      'moodScore': mood,
      'manualTags': tags,
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
}
