/// Plain data classes the dashboard displays. They are platform-neutral:
/// the same objects are filled from Apple HealthKit or Google Health Connect.
library;

class DayValue {
  final DateTime day;
  final double value;
  const DayValue(this.day, this.value);
}

class HeartRatePoint {
  final DateTime time;
  final double bpm;
  const HeartRatePoint(this.time, this.bpm);
}

class SleepStage {
  final String name;
  final double hours;
  const SleepStage(this.name, this.hours);
}

class SleepSummary {
  final double totalAsleepHours;
  final List<SleepStage> stages;
  final String source;
  const SleepSummary({
    required this.totalAsleepHours,
    required this.stages,
    required this.source,
  });
}

class WorkoutItem {
  final String name;
  final DateTime start;
  final double minutes;
  final double? kcal;
  final double? miles;
  final String source;
  const WorkoutItem({
    required this.name,
    required this.start,
    required this.minutes,
    required this.kcal,
    required this.miles,
    required this.source,
  });
}

class DashboardData {
  final List<DayValue> weeklySteps;
  final double activeKcalToday;
  final List<HeartRatePoint> heartRateToday;
  final double? restingHeartRate;
  final SleepSummary? lastNightSleep;
  final List<WorkoutItem> workouts;
  final List<String> errors;
  final DateTime fetchedAt;

  const DashboardData({
    required this.weeklySteps,
    required this.activeKcalToday,
    required this.heartRateToday,
    required this.restingHeartRate,
    required this.lastNightSleep,
    required this.workouts,
    required this.errors,
    required this.fetchedAt,
  });

  double get stepsToday => weeklySteps.isEmpty ? 0 : weeklySteps.last.value;
  HeartRatePoint? get latestHeartRate =>
      heartRateToday.isEmpty ? null : heartRateToday.last;
}
