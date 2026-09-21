import 'dart:convert';

import 'package:copy_fit/exporter.dart';
import 'package:copy_fit/metrics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';

HealthDataPoint point(
  HealthDataType type,
  HealthDataUnit unit,
  num value,
  DateTime from, [
  DateTime? to,
  String? uuid,
  String source = 'Test Tracker',
]) =>
    HealthDataPoint(
      // Health Connect gives a sleep stage its parent session's uuid, so tests
      // that care about parentage pass the two the same one.
      uuid: uuid ?? '$type-$from-$value',
      value: NumericHealthValue(numericValue: value),
      type: type,
      unit: unit,
      dateFrom: from,
      dateTo: to ?? from,
      sourcePlatform: HealthPlatformType.googleHealthConnect,
      sourceDeviceId: 'device',
      sourceId: 'com.example.tracker',
      sourceName: source,
    );

HealthDataPoint workout(
  DateTime from,
  DateTime to,
  HealthWorkoutActivityType activity,
) =>
    HealthDataPoint(
      uuid: 'w-$from',
      value: WorkoutHealthValue(
        workoutActivityType: activity,
        totalEnergyBurned: 410,
        totalDistance: 6800,
      ),
      type: HealthDataType.WORKOUT,
      unit: HealthDataUnit.NO_UNIT,
      dateFrom: from,
      dateTo: to,
      sourcePlatform: HealthPlatformType.googleHealthConnect,
      sourceDeviceId: 'device',
      sourceId: 'com.example.tracker',
      sourceName: 'Test Tracker',
    );

Map<String, dynamic> run(
  List<HealthDataPoint> points,
  List<Metric> metrics, {
  ExportFormat format = ExportFormat.dailySummary,
}) {
  final start = DateTime(2026, 9, 18);
  final end = DateTime(2026, 9, 20, 23, 59, 59);
  final result = Exporter(
    points: points,
    metrics: metrics,
    start: start,
    end: end,
    format: format,
  ).build();
  return jsonDecode(result.json) as Map<String, dynamic>;
}

void main() {
  final steps = metricByKey('steps');
  final hr = metricByKey('heart_rate');
  final weight = metricByKey('weight');
  final sleep = metricByKey('sleep');
  final rhr = metricByKey('resting_heart_rate');
  final workouts = metricByKey('workouts');

  test('cumulative metrics are summed per local day', () {
    final doc = run([
      point(HealthDataType.STEPS, HealthDataUnit.COUNT, 1000, DateTime(2026, 9, 18, 9)),
      point(HealthDataType.STEPS, HealthDataUnit.COUNT, 2500, DateTime(2026, 9, 18, 17)),
      point(HealthDataType.STEPS, HealthDataUnit.COUNT, 400, DateTime(2026, 9, 19, 8)),
    ], [steps]);

    final days = doc['days'] as List;
    expect(days, hasLength(2));
    expect(days[0]['date'], '2026-09-18');
    expect(days[0]['steps'], 3500);
    expect(days[1]['steps'], 400);
    expect(doc['units']['steps'], 'count');
  });

  test('instantaneous metrics report min/avg/max/n', () {
    final doc = run([
      point(HealthDataType.HEART_RATE, HealthDataUnit.BEATS_PER_MINUTE, 50, DateTime(2026, 9, 18, 3)),
      point(HealthDataType.HEART_RATE, HealthDataUnit.BEATS_PER_MINUTE, 70, DateTime(2026, 9, 18, 12)),
      point(HealthDataType.HEART_RATE, HealthDataUnit.BEATS_PER_MINUTE, 150, DateTime(2026, 9, 18, 18)),
    ], [hr]);

    expect(doc['days'][0]['heart_rate'], {'min': 50, 'avg': 90, 'max': 150, 'n': 3});
    expect(doc['units']['heart_rate'], 'bpm');
  });

  test('average metrics collapse to a single rounded number', () {
    final doc = run([
      point(HealthDataType.RESTING_HEART_RATE, HealthDataUnit.BEATS_PER_MINUTE, 51, DateTime(2026, 9, 18, 3)),
      point(HealthDataType.RESTING_HEART_RATE, HealthDataUnit.BEATS_PER_MINUTE, 54, DateTime(2026, 9, 18, 4)),
    ], [rhr]);

    expect(doc['days'][0]['resting_heart_rate'], 52.5);
  });

  test('body metrics take the last reading of the day', () {
    final doc = run([
      point(HealthDataType.WEIGHT, HealthDataUnit.KILOGRAM, 81.4, DateTime(2026, 9, 18, 7)),
      point(HealthDataType.WEIGHT, HealthDataUnit.KILOGRAM, 82.1, DateTime(2026, 9, 18, 21)),
    ], [weight]);

    expect(doc['days'][0]['weight'], 82.1);
    expect(doc['units']['weight'], 'kg');
  });

  test('a night crossing midnight stays on the wake-up date', () {
    // Asleep 23:00 on the 18th, awake 07:00 on the 19th. The deep stage ends
    // before midnight, so anchoring stages by their own end time would strand
    // it on the 18th.
    final bed = DateTime(2026, 9, 18, 23);
    final wake = DateTime(2026, 9, 19, 7);
    final doc = run([
      point(HealthDataType.SLEEP_SESSION, HealthDataUnit.MINUTE, 0, bed, wake),
      point(HealthDataType.SLEEP_DEEP, HealthDataUnit.MINUTE, 0, bed, bed.add(const Duration(minutes: 90))),
      point(HealthDataType.SLEEP_REM, HealthDataUnit.MINUTE, 0, bed.add(const Duration(minutes: 90)), bed.add(const Duration(minutes: 180))),
      point(HealthDataType.SLEEP_LIGHT, HealthDataUnit.MINUTE, 0, bed.add(const Duration(minutes: 180)), wake.subtract(const Duration(minutes: 15))),
      point(HealthDataType.SLEEP_AWAKE, HealthDataUnit.MINUTE, 0, wake.subtract(const Duration(minutes: 15)), wake),
    ], [sleep]);

    final days = doc['days'] as List;
    expect(days, hasLength(1), reason: 'the whole night lands on one date');
    expect(days[0]['date'], '2026-09-19');

    final s = days[0]['sleep'] as Map<String, dynamic>;
    expect(s['in_bed_min'], 480);
    expect(s['asleep_min'], 465, reason: 'deep + rem + light, excluding awake');
    expect(s['session_count'], 1);
    expect(s.containsKey('unassigned_stages'), isFalse,
        reason: 'every stage found its session');

    final main = s['main_sleep'] as Map<String, dynamic>;
    expect(main['start'], startsWith('2026-09-18T23:00:00'));
    expect(main['end'], startsWith('2026-09-19T07:00:00'));
    expect(main['deep_min'], 90);
    expect(main['rem_min'], 90);
    expect(main['light_min'], 285);
    expect(main['awake_min'], 15);
    expect(main['efficiency_pct'], 96.9);
  });

  test('a nap is kept separate from the main sleep', () {
    final bed = DateTime(2026, 9, 18, 23);
    final wake = DateTime(2026, 9, 19, 6);
    final napStart = DateTime(2026, 9, 19, 14);
    final napEnd = DateTime(2026, 9, 19, 14, 45);

    final doc = run([
      point(HealthDataType.SLEEP_SESSION, HealthDataUnit.MINUTE, 0, bed, wake),
      point(HealthDataType.SLEEP_LIGHT, HealthDataUnit.MINUTE, 0, bed, wake),
      point(HealthDataType.SLEEP_SESSION, HealthDataUnit.MINUTE, 0, napStart, napEnd),
      point(HealthDataType.SLEEP_LIGHT, HealthDataUnit.MINUTE, 0, napStart, napEnd),
    ], [sleep]);

    final s = doc['days'][0]['sleep'] as Map<String, dynamic>;
    expect(s['session_count'], 2);
    expect(s['asleep_min'], 465, reason: '420 overnight + 45 nap');
    expect(s['in_bed_min'], 465);

    final main = s['main_sleep'] as Map<String, dynamic>;
    expect(main['in_bed_min'], 420, reason: 'the longest session is the main one');
    expect(main['start'], startsWith('2026-09-18T23:00:00'));

    final naps = s['naps'] as List;
    expect(naps, hasLength(1));
    expect(naps[0]['in_bed_min'], 45);
    expect(naps[0]['start'], startsWith('2026-09-19T14:00:00'));
  });

  test('stages are attached to their own session, not the nearest one', () {
    final bed = DateTime(2026, 9, 18, 23);
    final wake = DateTime(2026, 9, 19, 6);
    final napStart = DateTime(2026, 9, 19, 14);
    final napEnd = DateTime(2026, 9, 19, 15);

    final doc = run([
      point(HealthDataType.SLEEP_SESSION, HealthDataUnit.MINUTE, 0, bed, wake),
      point(HealthDataType.SLEEP_DEEP, HealthDataUnit.MINUTE, 0, bed, bed.add(const Duration(minutes: 60))),
      point(HealthDataType.SLEEP_SESSION, HealthDataUnit.MINUTE, 0, napStart, napEnd),
      point(HealthDataType.SLEEP_REM, HealthDataUnit.MINUTE, 0, napStart, napEnd),
    ], [sleep]);

    final s = doc['days'][0]['sleep'] as Map<String, dynamic>;
    final main = s['main_sleep'] as Map<String, dynamic>;
    final nap = (s['naps'] as List).single as Map<String, dynamic>;

    expect(main['deep_min'], 60);
    expect(main.containsKey('rem_min'), isFalse, reason: "the nap's REM is not the night's");
    expect(nap['rem_min'], 60);
    expect(nap.containsKey('deep_min'), isFalse);
  });

  test('overlapping sessions keep their own stages', () {
    // Two sources both logging the same night, one session nested inside the
    // other. Matching by interval would hand the inner session's stages to the
    // outer one, because the outer contains them too.
    final outerStart = DateTime(2026, 9, 18, 23);
    final outerEnd = DateTime(2026, 9, 19, 6);
    final innerStart = DateTime(2026, 9, 18, 23, 30);
    final innerEnd = DateTime(2026, 9, 19, 5, 30);

    final doc = run([
      point(HealthDataType.SLEEP_SESSION, HealthDataUnit.MINUTE, 0,
          outerStart, outerEnd, 'session-outer', 'Fitbit'),
      point(HealthDataType.SLEEP_DEEP, HealthDataUnit.MINUTE, 0,
          outerStart, outerStart.add(const Duration(minutes: 90)),
          'session-outer', 'Fitbit'),
      point(HealthDataType.SLEEP_SESSION, HealthDataUnit.MINUTE, 0,
          innerStart, innerEnd, 'session-inner', 'Samsung Health'),
      point(HealthDataType.SLEEP_REM, HealthDataUnit.MINUTE, 0,
          DateTime(2026, 9, 19), DateTime(2026, 9, 19, 1),
          'session-inner', 'Samsung Health'),
    ], [sleep]);

    final s = doc['days'][0]['sleep'] as Map<String, dynamic>;
    expect(s['session_count'], 2);

    final main = s['main_sleep'] as Map<String, dynamic>;
    final nap = (s['naps'] as List).single as Map<String, dynamic>;

    expect(main['source'], 'Fitbit', reason: 'the longer session is the main one');
    expect(main['deep_min'], 90);
    expect(main.containsKey('rem_min'), isFalse,
        reason: "the inner session's REM must not be absorbed by the outer one");

    expect(nap['source'], 'Samsung Health');
    expect(nap['rem_min'], 60);
    expect(nap.containsKey('deep_min'), isFalse);
  });

  test('a stage whose session is missing falls back to its interval', () {
    // Health Connect can return a stage whose session began before the
    // queried window, leaving no uuid to match against.
    final bed = DateTime(2026, 9, 18, 23);
    final wake = DateTime(2026, 9, 19, 7);

    final doc = run([
      point(HealthDataType.SLEEP_SESSION, HealthDataUnit.MINUTE, 0, bed, wake,
          'session-1'),
      point(HealthDataType.SLEEP_DEEP, HealthDataUnit.MINUTE, 0, bed,
          bed.add(const Duration(minutes: 60)), 'some-other-uuid'),
    ], [sleep]);

    final s = doc['days'][0]['sleep'] as Map<String, dynamic>;
    expect((s['main_sleep'] as Map)['deep_min'], 60);
    expect(s.containsKey('unassigned_stages'), isFalse);
  });

  test('a session with no stage breakdown falls back to session length', () {
    final bed = DateTime(2026, 9, 18, 23);
    final wake = DateTime(2026, 9, 19, 6, 30);
    final doc = run([
      point(HealthDataType.SLEEP_SESSION, HealthDataUnit.MINUTE, 0, bed, wake),
    ], [sleep]);

    final s = doc['days'][0]['sleep'] as Map<String, dynamic>;
    expect(s['asleep_min'], 450);
    expect((s['main_sleep'] as Map)['stages_available'], false);
  });

  test('a stage with no session is kept, not dropped', () {
    // Reproduces a real export: a stray 5-minute awake stage that belonged to
    // no session at all.
    final doc = run([
      point(HealthDataType.SLEEP_AWAKE, HealthDataUnit.MINUTE, 0,
          DateTime(2026, 9, 18, 3), DateTime(2026, 9, 18, 3, 5)),
    ], [sleep]);

    final s = doc['days'][0]['sleep'] as Map<String, dynamic>;
    expect(s['session_count'], 0);
    expect(s['asleep_min'], 0);
    expect(s['unassigned_stages'], {'awake_min': 5});
  });

  test('workouts are listed with duration and activity type', () {
    final doc = run([
      workout(
        DateTime(2026, 9, 18, 6, 30),
        DateTime(2026, 9, 18, 7, 12),
        HealthWorkoutActivityType.RUNNING,
      ),
    ], [workouts]);

    final w = (doc['days'][0]['workouts'] as List).single as Map<String, dynamic>;
    expect(w['activity'], 'RUNNING');
    expect(w['duration_min'], 42);
    expect(w['energy_kcal'], 410);
    expect(w['distance_m'], 6800);
    expect(w['source'], 'Test Tracker');
  });

  test('days with no data at all are omitted', () {
    final doc = run([
      point(HealthDataType.STEPS, HealthDataUnit.COUNT, 100, DateTime(2026, 9, 20, 9)),
    ], [steps, hr, weight]);

    expect(doc['days'], hasLength(1));
    expect(doc['days'][0]['date'], '2026-09-20');
  });

  test('types that returned nothing are reported back to the UI', () {
    final result = Exporter(
      points: [point(HealthDataType.STEPS, HealthDataUnit.COUNT, 10, DateTime(2026, 9, 20))],
      metrics: [steps, hr],
      start: DateTime(2026, 9, 18),
      end: DateTime(2026, 9, 20, 23, 59),
      format: ExportFormat.dailySummary,
    ).build();

    expect(result.typesWithData, ['STEPS']);
    expect(result.typesWithoutData, ['HEART_RATE']);
    expect(result.dayCount, 1);
    expect(result.pointCount, 1);
  });

  test('raw format emits one trimmed object per reading, in time order', () {
    final doc = run([
      point(HealthDataType.STEPS, HealthDataUnit.COUNT, 5, DateTime(2026, 9, 19, 10)),
      point(HealthDataType.STEPS, HealthDataUnit.COUNT, 3, DateTime(2026, 9, 18, 10)),
    ], [steps], format: ExportFormat.rawPoints);

    final pts = doc['points'] as List;
    expect(pts, hasLength(2));
    expect(pts[0]['value'], 3);
    expect(pts[0]['type'], 'STEPS');
    expect(pts[0]['unit'], 'count');
    expect(pts[0]['source'], 'Test Tracker');
    expect(pts[0].containsKey('to'), isFalse, reason: 'instant readings omit "to"');
    expect(pts[1]['value'], 5);
    expect(doc.containsKey('days'), isFalse);
  });

  test('timestamps are local ISO 8601 with an offset', () {
    final doc = run([
      point(HealthDataType.STEPS, HealthDataUnit.COUNT, 5, DateTime(2026, 9, 19, 10, 30, 15)),
    ], [steps], format: ExportFormat.rawPoints);

    expect(
      doc['points'][0]['from'],
      matches(r'^2026-09-19T10:30:15[+-]\d{2}:\d{2}$'),
    );
  });
}
