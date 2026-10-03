import 'dart:io' show Platform;
import 'dart:math';

import 'package:health/health.dart';
import 'package:permission_handler/permission_handler.dart';

import 'models.dart';

/// The only file that talks to the health platform.
///
/// The `health` package routes every call to Apple HealthKit on iOS and to
/// Google Health Connect on Android, so the rest of the app never needs to
/// know which platform it is running on.
class HealthService {
  final Health _health = Health();
  bool _configured = false;

  bool get isIOS => Platform.isIOS;
  String get platformName => isIOS ? 'Apple Health' : 'Health Connect';
  String get platformDetail =>
      isIOS ? 'Apple HealthKit on iPhone' : 'Google Health Connect on Android';

  // ---------------------------------------------------------------------------
  // Data types and permissions
  // ---------------------------------------------------------------------------

  /// Types written by the "test the connection" buttons.
  static const _writableTypes = {HealthDataType.STEPS, HealthDataType.HEART_RATE};

  static const _asleepTypes = {
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_REM,
  };

  List<HealthDataType> get _sleepTypes => [
        HealthDataType.SLEEP_ASLEEP,
        HealthDataType.SLEEP_LIGHT,
        HealthDataType.SLEEP_DEEP,
        HealthDataType.SLEEP_REM,
        HealthDataType.SLEEP_AWAKE,
        if (isIOS) HealthDataType.SLEEP_IN_BED,
        if (!isIOS) HealthDataType.SLEEP_SESSION,
      ];

  /// Everything the app asks permission for, filtered to what this platform supports.
  List<HealthDataType> get _types {
    final types = <HealthDataType>[
      HealthDataType.STEPS,
      HealthDataType.HEART_RATE,
      HealthDataType.RESTING_HEART_RATE,
      HealthDataType.ACTIVE_ENERGY_BURNED,
      HealthDataType.WORKOUT,
      ..._sleepTypes,
      // On Android, reading a workout also reads the distance and calories
      // recorded during it, so those permissions are needed too.
      if (!isIOS) HealthDataType.DISTANCE_DELTA,
      if (!isIOS) HealthDataType.TOTAL_CALORIES_BURNED,
    ];
    return types.where(_health.isDataTypeAvailable).toList();
  }

  List<HealthDataAccess> get _permissions => _types
      .map((t) => _writableTypes.contains(t)
          ? HealthDataAccess.READ_WRITE
          : HealthDataAccess.READ)
      .toList();

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  // ---------------------------------------------------------------------------
  // Connecting
  // ---------------------------------------------------------------------------

  /// Always true on iOS. On Android, false if Health Connect isn't installed.
  Future<bool> isAvailable() async {
    await _ensureConfigured();
    return _health.isHealthConnectAvailable();
  }

  /// Opens the Play Store page for Health Connect (Android only).
  Future<void> installHealthConnect() => _health.installHealthConnect();

  /// Shows the platform's own permission screen.
  ///
  /// Note: on iOS this returns true once the sheet has been answered, even if
  /// the user switched categories off. For privacy, HealthKit never reveals
  /// denied read access; those types just come back empty.
  Future<bool> connect() async {
    await _ensureConfigured();
    if (!isIOS) {
      // Android needs this runtime permission before step data can be read.
      await Permission.activityRecognition.request();
    }
    return _health.requestAuthorization(_types, permissions: _permissions);
  }

  // ---------------------------------------------------------------------------
  // Reading
  // ---------------------------------------------------------------------------

  /// Loads everything the dashboard shows. Each section is loaded on its own,
  /// so a problem with one data type doesn't blank the whole screen.
  Future<DashboardData> loadDashboard() async {
    await _ensureConfigured();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final errors = <String>[];

    Future<T?> attempt<T>(String label, Future<T> Function() task) async {
      try {
        return await task();
      } catch (e) {
        errors.add('$label: $e');
        return null;
      }
    }

    final weeklySteps = await attempt('Steps', () => _weeklySteps(today, now));
    final activeKcal = await attempt('Active energy', () => _activeEnergy(today, now));
    final heartRate = await attempt('Heart rate', () => _heartRateToday(today, now));
    final resting = await attempt('Resting heart rate', () => _restingHeartRate(now));
    final sleep = await attempt('Sleep', () => _lastNightSleep(today, now));
    final workouts = await attempt('Workouts', () => _recentWorkouts(now));

    return DashboardData(
      weeklySteps: weeklySteps ?? const [],
      activeKcalToday: activeKcal ?? 0,
      heartRateToday: heartRate ?? const [],
      restingHeartRate: resting,
      lastNightSleep: sleep,
      workouts: workouts ?? const [],
      errors: errors,
      fetchedAt: now,
    );
  }

  /// Daily step totals for the last 7 days. The platform aggregates these,
  /// so steps counted by both phone and watch are not double-counted.
  Future<List<DayValue>> _weeklySteps(DateTime today, DateTime now) async {
    final days = <DayValue>[];
    for (var i = 6; i >= 0; i--) {
      final start = DateTime(today.year, today.month, today.day - i);
      final end = i == 0 ? now : DateTime(today.year, today.month, today.day - i + 1);
      final steps = await _health.getTotalStepsInInterval(start, end);
      days.add(DayValue(start, (steps ?? 0).toDouble()));
    }
    return days;
  }

  /// Active energy today. Phone and watch can both record it, so we take the
  /// single source with the highest total rather than adding them together.
  Future<double> _activeEnergy(DateTime today, DateTime now) async {
    final points = await _read([HealthDataType.ACTIVE_ENERGY_BURNED], today, now);
    final bySource = <String, double>{};
    for (final p in points) {
      bySource[p.sourceName] = (bySource[p.sourceName] ?? 0) + _numeric(p);
    }
    return bySource.values.fold<double>(0, (a, b) => max(a, b));
  }

  Future<List<HeartRatePoint>> _heartRateToday(DateTime today, DateTime now) async {
    final points = await _read([HealthDataType.HEART_RATE], today, now);
    return points
        .map((p) => HeartRatePoint(p.dateFrom, _numeric(p)))
        .where((p) => p.bpm > 0)
        .toList()
      ..sort((a, b) => a.time.compareTo(b.time));
  }

  Future<double?> _restingHeartRate(DateTime now) async {
    final points = await _read(
        [HealthDataType.RESTING_HEART_RATE], now.subtract(const Duration(days: 7)), now);
    if (points.isEmpty) return null;
    points.sort((a, b) => b.dateFrom.compareTo(a.dateFrom));
    return _numeric(points.first);
  }

  /// Sleep from 6 pm yesterday until now. Several apps/devices can record the
  /// same night, so we show the single source that recorded the most sleep.
  Future<SleepSummary?> _lastNightSleep(DateTime today, DateTime now) async {
    final start = today.subtract(const Duration(hours: 6));
    final types = _sleepTypes.where(_health.isDataTypeAvailable).toList();
    final points = await _read(types, start, now);
    if (points.isEmpty) return null;

    final bySource = <String, List<HealthDataPoint>>{};
    for (final p in points) {
      bySource.putIfAbsent(p.sourceName, () => []).add(p);
    }

    double asleepHours(List<HealthDataPoint> group) => group
        .where((p) => _asleepTypes.contains(p.type))
        .fold<double>(0, (sum, p) => sum + _hours(p));

    double recordedHours(List<HealthDataPoint> group) =>
        group.fold<double>(0, (sum, p) => sum + _hours(p));

    final best = bySource.entries.reduce((a, b) {
      final diff = asleepHours(a.value) - asleepHours(b.value);
      if (diff != 0) return diff > 0 ? a : b;
      return recordedHours(a.value) >= recordedHours(b.value) ? a : b;
    });

    final totals = <String, double>{};
    for (final p in best.value) {
      final name = _sleepStageName(p.type);
      totals[name] = (totals[name] ?? 0) + _hours(p);
    }

    const order = ['Deep', 'Core', 'Light', 'REM', 'Asleep', 'Awake', 'In bed', 'Sleep session'];
    final stages = [
      for (final name in order)
        if (totals.containsKey(name)) SleepStage(name, totals[name]!),
    ];

    // Some Android apps record a sleep session without stages.
    var asleep = asleepHours(best.value);
    if (asleep == 0) asleep = totals['Sleep session'] ?? 0;

    return SleepSummary(totalAsleepHours: asleep, stages: stages, source: best.key);
  }

  Future<List<WorkoutItem>> _recentWorkouts(DateTime now) async {
    final points =
        await _read([HealthDataType.WORKOUT], now.subtract(const Duration(days: 30)), now);
    final items = <WorkoutItem>[];
    for (final p in points) {
      final value = p.value;
      if (value is! WorkoutHealthValue) continue;
      items.add(WorkoutItem(
        name: _prettyName(value.workoutActivityType.name),
        start: p.dateFrom,
        minutes: p.dateTo.difference(p.dateFrom).inSeconds / 60,
        kcal: value.totalEnergyBurned?.toDouble(),
        miles: value.totalDistance == null ? null : value.totalDistance! / 1609.344,
        source: p.sourceName,
      ));
    }
    items.sort((a, b) => b.start.compareTo(a.start));
    return items.take(20).toList();
  }

  // ---------------------------------------------------------------------------
  // Writing test data (real writes through HealthKit / Health Connect)
  // ---------------------------------------------------------------------------

  Future<bool> writeTestSteps() async {
    await _ensureConfigured();
    final now = DateTime.now();
    return _health.writeHealthData(
      value: 500,
      type: HealthDataType.STEPS,
      startTime: now.subtract(const Duration(minutes: 10)),
      endTime: now,
    );
  }

  Future<bool> writeTestHeartRate() async {
    await _ensureConfigured();
    final now = DateTime.now();
    final bpm = 60 + Random().nextInt(36);
    return _health.writeHealthData(
      value: bpm.toDouble(),
      type: HealthDataType.HEART_RATE,
      startTime: now.subtract(const Duration(minutes: 1)),
      endTime: now,
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Future<List<HealthDataPoint>> _read(
      List<HealthDataType> types, DateTime start, DateTime end) async {
    final points =
        await _health.getHealthDataFromTypes(types: types, startTime: start, endTime: end);
    return _health.removeDuplicates(points);
  }

  double _numeric(HealthDataPoint p) {
    final value = p.value;
    return value is NumericHealthValue ? value.numericValue.toDouble() : 0;
  }

  double _hours(HealthDataPoint p) => p.dateTo.difference(p.dateFrom).inSeconds / 3600;

  String _sleepStageName(HealthDataType type) {
    switch (type) {
      case HealthDataType.SLEEP_DEEP:
        return 'Deep';
      case HealthDataType.SLEEP_LIGHT:
        return isIOS ? 'Core' : 'Light'; // Apple calls light sleep "Core"
      case HealthDataType.SLEEP_REM:
        return 'REM';
      case HealthDataType.SLEEP_ASLEEP:
        return 'Asleep';
      case HealthDataType.SLEEP_AWAKE:
        return 'Awake';
      case HealthDataType.SLEEP_IN_BED:
        return 'In bed';
      case HealthDataType.SLEEP_SESSION:
        return 'Sleep session';
      default:
        return 'Other';
    }
  }

  /// "TRADITIONAL_STRENGTH_TRAINING" -> "Traditional Strength Training"
  String _prettyName(String raw) => raw
      .split('_')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0] + w.substring(1).toLowerCase())
      .join(' ');
}
