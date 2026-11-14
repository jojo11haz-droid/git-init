import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// The person's own check-in reminder, kept on this phone. Days use
/// DateTime.weekday numbering (1 = Monday … 7 = Sunday).
class ReminderPrefs {
  ReminderPrefs({
    required this.enabled,
    required this.hour,
    required this.minute,
    required this.days,
  });

  final bool enabled;
  final int hour;
  final int minute;
  final Set<int> days;

  static ReminderPrefs get initial => ReminderPrefs(
      enabled: false,
      hour: 19,
      minute: 0,
      days: {1, 2, 3, 4, 5, 6, 7});

  ReminderPrefs copyWith(
          {bool? enabled, int? hour, int? minute, Set<int>? days}) =>
      ReminderPrefs(
        enabled: enabled ?? this.enabled,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        days: days ?? this.days,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'hour': hour,
        'minute': minute,
        'days': days.toList()..sort(),
      };

  static ReminderPrefs fromJson(Map<String, dynamic> j) => ReminderPrefs(
        enabled: j['enabled'] == true,
        hour: (j['hour'] as num?)?.toInt() ?? 19,
        minute: (j['minute'] as num?)?.toInt() ?? 0,
        days: ((j['days'] as List?) ?? const [1, 2, 3, 4, 5, 6, 7])
            .map((d) => (d as num).toInt())
            .where((d) => d >= 1 && d <= 7)
            .toSet(),
      );
}

/// Check-in reminders as notifications from the app itself: scheduled on the
/// phone, so they're free, work without a phone number, and tapping one opens
/// the app on its check-in box. Nothing about the person's health is in them.
class LocalReminders {
  LocalReminders._();
  static final LocalReminders instance = LocalReminders._();

  static const _storeKey = 'btw_local_reminder';
  static const _idBase = 7100; // one notification id per weekday
  final _plugin = FlutterLocalNotificationsPlugin();
  final _storage = const FlutterSecureStorage();
  bool _ready = false;

  /// Phones only; the web build has no scheduled notifications.
  bool get supported => !kIsWeb;

  Future<void> _init() async {
    if (_ready || !supported) return;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(_guessLocation());
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _plugin.initialize(settings);
    _ready = true;
  }

  // The timezone package needs a named zone so weekly reminders keep their
  // time across daylight saving. Pick the zone that matches this phone's
  // current offset and abbreviation, Canadian zones first.
  static tz.Location _guessLocation() {
    final now = DateTime.now();
    final off = now.timeZoneOffset.inMinutes;
    final abbr = now.timeZoneName;
    const preferred = [
      'America/Toronto', 'America/Vancouver', 'America/Edmonton',
      'America/Winnipeg', 'America/Regina', 'America/Halifax',
      'America/St_Johns', 'America/New_York', 'America/Chicago',
      'America/Denver', 'America/Los_Angeles', 'Europe/Paris',
      'Europe/London',
    ];
    bool fits(tz.Location l, bool needAbbr) {
      final t = tz.TZDateTime.from(now, l);
      return t.timeZoneOffset.inMinutes == off &&
          (!needAbbr || t.timeZoneName == abbr);
    }

    for (final needAbbr in [true, false]) {
      for (final n in preferred) {
        final l = tz.getLocation(n);
        if (fits(l, needAbbr)) return l;
      }
      for (final l in tz.timeZoneDatabase.locations.values) {
        if (fits(l, needAbbr)) return l;
      }
    }
    return tz.UTC;
  }

  Future<ReminderPrefs> load() async {
    try {
      final raw = await _storage.read(key: _storeKey);
      if (raw == null || raw.isEmpty) return ReminderPrefs.initial;
      return ReminderPrefs.fromJson(
          (jsonDecode(raw) as Map).cast<String, dynamic>());
    } catch (_) {
      return ReminderPrefs.initial;
    }
  }

  /// Asks the phone for permission to show notifications. True if allowed.
  Future<bool> requestPermission() async {
    if (!supported) return false;
    await _init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(
              alert: true, badge: false, sound: true) ??
          false;
    }
    return false;
  }

  /// Saves the choice and (re)schedules the week's notifications to match.
  Future<void> apply(ReminderPrefs p,
      {required String title,
      required String body,
      required String channelName}) async {
    await _storage.write(key: _storeKey, value: jsonEncode(p.toJson()));
    if (!supported) return;
    await _init();
    for (var d = 1; d <= 7; d++) {
      await _plugin.cancel(_idBase + d);
    }
    if (!p.enabled) return;
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'btw_checkin',
        channelName,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
      iOS: const DarwinNotificationDetails(),
    );
    final now = tz.TZDateTime.now(tz.local);
    for (final d in p.days) {
      tz.TZDateTime? at;
      for (var i = 0; i <= 7; i++) {
        final c = tz.TZDateTime(
            tz.local, now.year, now.month, now.day + i, p.hour, p.minute);
        if (c.weekday == d && c.isAfter(now)) {
          at = c;
          break;
        }
      }
      if (at == null) continue;
      await _plugin.zonedSchedule(
        _idBase + d,
        title,
        body,
        at,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }
  }
}
