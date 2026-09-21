import 'package:health/health.dart';

/// How a day's worth of points for a metric collapses into a single JSON value.
enum Agg {
  /// Add every point together (steps, calories, distance).
  sum,

  /// Emit `{min, avg, max, n}` (heart rate, SpO2, glucose).
  stats,

  /// Emit the mean only (resting heart rate, BMR).
  average,

  /// Emit the chronologically last reading of the day (weight, height).
  latest,

  /// Roll all sleep stages into one `sleep` object.
  sleep,

  /// Emit a list of workout objects.
  workout,

  /// Emit a list of logged meals.
  nutrition,
}

/// One user-selectable metric. A metric may map to several Health Connect
/// record types (sleep stages, blood pressure) but produces one JSON key.
class Metric {
  const Metric({
    required this.key,
    required this.label,
    required this.group,
    required this.types,
    required this.agg,
    this.defaultOn = false,
  });

  /// The key this metric gets in the exported JSON.
  final String key;

  /// The name shown on the selection chip.
  final String label;

  /// Section heading in the picker.
  final String group;

  final List<HealthDataType> types;
  final Agg agg;
  final bool defaultOn;
}

const kGroupActivity = 'Activity';
const kGroupHeart = 'Heart';
const kGroupSleep = 'Sleep';
const kGroupBody = 'Body';
const kGroupVitals = 'Vitals';
const kGroupIntake = 'Intake';

/// Every metric the app can export, in display order.
const List<Metric> kMetrics = [
  // Activity
  Metric(
    key: 'steps',
    label: 'Steps',
    group: kGroupActivity,
    types: [HealthDataType.STEPS],
    agg: Agg.sum,
  ),
  Metric(
    key: 'distance',
    label: 'Distance',
    group: kGroupActivity,
    types: [HealthDataType.DISTANCE_DELTA],
    agg: Agg.sum,
  ),
  Metric(
    key: 'flights_climbed',
    label: 'Floors climbed',
    group: kGroupActivity,
    types: [HealthDataType.FLIGHTS_CLIMBED],
    agg: Agg.sum,
  ),
  Metric(
    key: 'active_energy',
    label: 'Active calories',
    group: kGroupActivity,
    types: [HealthDataType.ACTIVE_ENERGY_BURNED],
    agg: Agg.sum,
  ),
  Metric(
    key: 'total_energy',
    label: 'Total calories',
    group: kGroupActivity,
    types: [HealthDataType.TOTAL_CALORIES_BURNED],
    agg: Agg.sum,
  ),
  Metric(
    key: 'basal_metabolic_rate',
    label: 'BMR',
    group: kGroupActivity,
    types: [HealthDataType.BASAL_ENERGY_BURNED],
    agg: Agg.average,
  ),
  Metric(
    key: 'speed',
    label: 'Speed',
    group: kGroupActivity,
    types: [HealthDataType.SPEED],
    agg: Agg.stats,
  ),
  Metric(
    key: 'workouts',
    label: 'Workouts',
    group: kGroupActivity,
    types: [HealthDataType.WORKOUT],
    agg: Agg.workout,
  ),

  // Heart
  Metric(
    key: 'heart_rate',
    label: 'Heart rate',
    group: kGroupHeart,
    types: [HealthDataType.HEART_RATE],
    agg: Agg.stats,
  ),
  Metric(
    key: 'resting_heart_rate',
    label: 'Resting HR',
    group: kGroupHeart,
    types: [HealthDataType.RESTING_HEART_RATE],
    agg: Agg.average,
  ),
  Metric(
    key: 'hrv_rmssd',
    label: 'HRV (RMSSD)',
    group: kGroupHeart,
    types: [HealthDataType.HEART_RATE_VARIABILITY_RMSSD],
    agg: Agg.stats,
  ),

  // Sleep
  Metric(
    key: 'sleep',
    label: 'Sleep',
    group: kGroupSleep,
    types: [
      HealthDataType.SLEEP_SESSION,
      HealthDataType.SLEEP_DEEP,
      HealthDataType.SLEEP_REM,
      HealthDataType.SLEEP_LIGHT,
      HealthDataType.SLEEP_AWAKE,
      HealthDataType.SLEEP_AWAKE_IN_BED,
      HealthDataType.SLEEP_OUT_OF_BED,
      HealthDataType.SLEEP_UNKNOWN,
    ],
    agg: Agg.sleep,
    defaultOn: true,
  ),

  // Body
  Metric(
    key: 'weight',
    label: 'Weight',
    group: kGroupBody,
    types: [HealthDataType.WEIGHT],
    agg: Agg.latest,
  ),
  Metric(
    key: 'height',
    label: 'Height',
    group: kGroupBody,
    types: [HealthDataType.HEIGHT],
    agg: Agg.latest,
  ),
  Metric(
    key: 'body_fat_percentage',
    label: 'Body fat %',
    group: kGroupBody,
    types: [HealthDataType.BODY_FAT_PERCENTAGE],
    agg: Agg.latest,
  ),
  Metric(
    key: 'lean_body_mass',
    label: 'Lean mass',
    group: kGroupBody,
    types: [HealthDataType.LEAN_BODY_MASS],
    agg: Agg.latest,
  ),
  Metric(
    key: 'body_water_mass',
    label: 'Body water',
    group: kGroupBody,
    types: [HealthDataType.BODY_WATER_MASS],
    agg: Agg.latest,
  ),

  // Vitals
  Metric(
    key: 'blood_oxygen',
    label: 'Blood oxygen',
    group: kGroupVitals,
    types: [HealthDataType.BLOOD_OXYGEN],
    agg: Agg.stats,
  ),
  Metric(
    key: 'respiratory_rate',
    label: 'Respiratory rate',
    group: kGroupVitals,
    types: [HealthDataType.RESPIRATORY_RATE],
    agg: Agg.stats,
  ),
  Metric(
    key: 'body_temperature',
    label: 'Body temp',
    group: kGroupVitals,
    types: [HealthDataType.BODY_TEMPERATURE],
    agg: Agg.stats,
  ),
  Metric(
    key: 'skin_temperature',
    label: 'Skin temp',
    group: kGroupVitals,
    types: [HealthDataType.SKIN_TEMPERATURE],
    agg: Agg.stats,
  ),
  Metric(
    key: 'blood_pressure_systolic',
    label: 'BP systolic',
    group: kGroupVitals,
    types: [HealthDataType.BLOOD_PRESSURE_SYSTOLIC],
    agg: Agg.stats,
  ),
  Metric(
    key: 'blood_pressure_diastolic',
    label: 'BP diastolic',
    group: kGroupVitals,
    types: [HealthDataType.BLOOD_PRESSURE_DIASTOLIC],
    agg: Agg.stats,
  ),
  Metric(
    key: 'blood_glucose',
    label: 'Blood glucose',
    group: kGroupVitals,
    types: [HealthDataType.BLOOD_GLUCOSE],
    agg: Agg.stats,
  ),

  // Intake
  Metric(
    key: 'water',
    label: 'Water',
    group: kGroupIntake,
    types: [HealthDataType.WATER],
    agg: Agg.sum,
  ),
  Metric(
    key: 'nutrition',
    label: 'Nutrition',
    group: kGroupIntake,
    types: [HealthDataType.NUTRITION],
    agg: Agg.nutrition,
  ),
];

/// Groups in display order.
const List<String> kGroupOrder = [
  kGroupActivity,
  kGroupHeart,
  kGroupSleep,
  kGroupBody,
  kGroupVitals,
  kGroupIntake,
];

final Set<String> kDefaultMetricKeys = {
  for (final m in kMetrics)
    if (m.defaultOn) m.key,
};

Metric metricByKey(String key) => kMetrics.firstWhere((m) => m.key == key);
