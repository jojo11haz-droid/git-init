import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

/// A single day's health snapshot, shaped to match the server's
/// POST /api/patient/health payload.
class HealthDay {
  HealthDay(this.day);

  final String day; // YYYY-MM-DD
  int? sleepMinutes;
  int? steps;
  int? activeEnergy; // kcal
  int? restingHr; // bpm
  int? mindfulMinutes;

  Map<String, dynamic> toJson() => {
        'day': day,
        if (sleepMinutes != null) 'sleepMinutes': sleepMinutes,
        if (steps != null) 'steps': steps,
        if (activeEnergy != null) 'activeEnergy': activeEnergy,
        if (restingHr != null) 'restingHr': restingHr,
        if (mindfulMinutes != null) 'mindfulMinutes': mindfulMinutes,
      };

  bool get hasAny =>
      sleepMinutes != null ||
      steps != null ||
      activeEnergy != null ||
      restingHr != null ||
      mindfulMinutes != null;
}

/// Reads Apple Health (HealthKit) on the device and turns it into daily
/// snapshots. Everything is wrapped so a device without HealthKit — or an app
/// built without the paid-account HealthKit capability — simply reports "not
/// available" instead of crashing.
class HealthService {
  final Health _health = Health();

  static const List<HealthDataType> _types = [
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.STEPS,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.RESTING_HEART_RATE,
    HealthDataType.MINDFULNESS,
  ];

  /// HealthKit only exists on iOS. On anything else the feature is hidden.
  bool get isSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Ask the OS for read access. Returns false (never throws) when HealthKit
  /// is unavailable or the person declines.
  Future<bool> requestAuthorization() async {
    if (!isSupported) return false;
    try {
      await _health.configure();
      final granted = await _health.requestAuthorization(
        _types,
        permissions: List.filled(_types.length, HealthDataAccess.READ),
      );
      return granted;
    } catch (e) {
      debugPrint('Health authorization failed: $e');
      return false;
    }
  }

  /// Read the last [days] days and fold the raw samples into per-day snapshots.
  /// Returns an empty list if nothing could be read.
  Future<List<HealthDay>> readRecent({int days = 7}) async {
    if (!isSupported) return [];
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: days - 1));
    final Map<String, HealthDay> byDay = {};
    HealthDay dayFor(DateTime d) {
      final key =
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      return byDay.putIfAbsent(key, () => HealthDay(key));
    }

    // Running sums/counts so we can average heart rate at the end.
    final Map<String, int> hrSum = {};
    final Map<String, int> hrCount = {};

    try {
      await _health.configure();
      final points = await _health.getHealthDataFromTypes(
        startTime: start,
        endTime: now,
        types: _types,
      );
      final deduped = _health.removeDuplicates(points);
      for (final p in deduped) {
        final num value =
            p.value is NumericHealthValue ? (p.value as NumericHealthValue).numericValue : 0;
        final minutes = p.dateTo.difference(p.dateFrom).inMinutes;
        switch (p.type) {
          case HealthDataType.SLEEP_ASLEEP:
            // Attribute a sleep block to the day it ended (the morning).
            final d = dayFor(p.dateTo);
            d.sleepMinutes = (d.sleepMinutes ?? 0) + minutes;
            break;
          case HealthDataType.ACTIVE_ENERGY_BURNED:
            final d = dayFor(p.dateFrom);
            d.activeEnergy = (d.activeEnergy ?? 0) + value.round();
            break;
          case HealthDataType.MINDFULNESS:
            final d = dayFor(p.dateFrom);
            d.mindfulMinutes = (d.mindfulMinutes ?? 0) + minutes;
            break;
          case HealthDataType.RESTING_HEART_RATE:
            final key = dayFor(p.dateFrom).day;
            hrSum[key] = (hrSum[key] ?? 0) + value.round();
            hrCount[key] = (hrCount[key] ?? 0) + 1;
            break;
          default:
            break;
        }
      }
    } catch (e) {
      debugPrint('Health read failed: $e');
    }

    // Steps have a dedicated total API that handles overlapping sources.
    try {
      for (int i = 0; i < days; i++) {
        final dayStart = DateTime(start.year, start.month, start.day)
            .add(Duration(days: i));
        final dayEnd = dayStart.add(const Duration(days: 1));
        if (dayStart.isAfter(now)) break;
        final steps = await _health.getTotalStepsInInterval(dayStart, dayEnd);
        if (steps != null && steps > 0) dayFor(dayStart).steps = steps;
      }
    } catch (e) {
      debugPrint('Health steps read failed: $e');
    }

    // Fold averaged resting heart rate back in.
    hrSum.forEach((key, sum) {
      final count = hrCount[key] ?? 0;
      if (count > 0) byDay[key]?.restingHr = (sum / count).round();
    });

    final out = byDay.values.where((d) => d.hasAny).toList()
      ..sort((a, b) => b.day.compareTo(a.day));
    return out;
  }
}
