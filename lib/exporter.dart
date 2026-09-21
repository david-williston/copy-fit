import 'dart:convert';

import 'package:health/health.dart';

import 'metrics.dart';

/// The two shapes the app can produce.
enum ExportFormat {
  /// One object per calendar day with metrics rolled up. Compact enough to
  /// paste into a chat.
  dailySummary,

  /// Every individual reading, trimmed to the fields that carry meaning.
  rawPoints,
}

/// Local-time ISO 8601 with a timezone offset, seconds resolution:
/// `2026-09-19T07:14:32-04:00`.
String isoLocal(DateTime dt) {
  final l = dt.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  final off = l.timeZoneOffset;
  final sign = off.isNegative ? '-' : '+';
  final abs = off.abs();
  return '${l.year.toString().padLeft(4, '0')}-${two(l.month)}-${two(l.day)}'
      'T${two(l.hour)}:${two(l.minute)}:${two(l.second)}'
      '$sign${two(abs.inHours)}:${two(abs.inMinutes.remainder(60))}';
}

/// `2026-09-19` in local time.
String isoDate(DateTime dt) {
  final l = dt.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.year.toString().padLeft(4, '0')}-${two(l.month)}-${two(l.day)}';
}

/// Trims trailing noise from computed averages without turning ints into
/// `8421.0`, which wastes tokens and reads badly.
num _round(num v, [int places = 2]) {
  if (v is int) return v;
  final r = double.parse(v.toStringAsFixed(places));
  return r == r.roundToDouble() ? r.round() : r;
}

num? _numeric(HealthValue v) =>
    v is NumericHealthValue ? v.numericValue : null;

/// A unit label that reads well in JSON: `KILOGRAM` -> `kg`.
String _unitLabel(HealthDataUnit u) {
  const map = {
    HealthDataUnit.COUNT: 'count',
    HealthDataUnit.METER: 'm',
    HealthDataUnit.KILOGRAM: 'kg',
    HealthDataUnit.KILOCALORIE: 'kcal',
    HealthDataUnit.BEATS_PER_MINUTE: 'bpm',
    HealthDataUnit.MILLISECOND: 'ms',
    HealthDataUnit.MINUTE: 'min',
    HealthDataUnit.SECOND: 's',
    HealthDataUnit.PERCENT: '%',
    HealthDataUnit.LITER: 'L',
    HealthDataUnit.MILLILITER: 'mL',
    HealthDataUnit.DEGREE_CELSIUS: 'degC',
    HealthDataUnit.DEGREE_FAHRENHEIT: 'degF',
    HealthDataUnit.MILLIMETER_OF_MERCURY: 'mmHg',
    HealthDataUnit.MILLIGRAM_PER_DECILITER: 'mg/dL',
    HealthDataUnit.MILLIMOLES_PER_LITER: 'mmol/L',
    HealthDataUnit.RESPIRATIONS_PER_MINUTE: 'breaths/min',
    HealthDataUnit.METER_PER_SECOND: 'm/s',
    HealthDataUnit.GRAM: 'g',
    HealthDataUnit.POUND: 'lb',
    HealthDataUnit.CENTIMETER: 'cm',
    HealthDataUnit.INCH: 'in',
    HealthDataUnit.FOOT: 'ft',
    HealthDataUnit.MILE: 'mi',
    HealthDataUnit.HOUR: 'h',
    HealthDataUnit.JOULE: 'J',
    HealthDataUnit.HERTZ: 'Hz',
    HealthDataUnit.NO_UNIT: '',
  };
  return map[u] ?? u.name.toLowerCase();
}

/// Sleep points carry the stage in their [HealthDataType]; this is the key each
/// stage contributes to the per-day `sleep` object.
const Map<HealthDataType, String> _sleepStageKeys = {
  HealthDataType.SLEEP_SESSION: 'in_bed_min',
  HealthDataType.SLEEP_DEEP: 'deep_min',
  HealthDataType.SLEEP_REM: 'rem_min',
  HealthDataType.SLEEP_LIGHT: 'light_min',
  HealthDataType.SLEEP_AWAKE: 'awake_min',
  HealthDataType.SLEEP_AWAKE_IN_BED: 'awake_in_bed_min',
  HealthDataType.SLEEP_OUT_OF_BED: 'out_of_bed_min',
  HealthDataType.SLEEP_UNKNOWN: 'unknown_min',
};

/// The stages that add up to actual sleep, as opposed to time in bed.
const Set<String> _asleepStageKeys = {'deep_min', 'rem_min', 'light_min'};

/// The result of one read, ready to show and copy.
class ExportResult {
  ExportResult({
    required this.json,
    required this.pointCount,
    required this.dayCount,
    required this.typesWithData,
    required this.typesWithoutData,
  });

  final String json;
  final int pointCount;
  final int dayCount;
  final List<String> typesWithData;
  final List<String> typesWithoutData;

  int get byteSize => utf8.encode(json).length;

  /// Rough token estimate. ~4 bytes per token holds up well for dense JSON and
  /// is only ever used to warn about context size.
  int get approxTokens => (byteSize / 4).round();
}

/// Turns raw Health Connect points into the JSON the user pastes into a chat.
class Exporter {
  Exporter({
    required this.points,
    required this.metrics,
    required this.start,
    required this.end,
    required this.format,
    this.rolling = false,
    this.includeSources = true,
  });

  final List<HealthDataPoint> points;
  final List<Metric> metrics;
  final DateTime start;
  final DateTime end;
  final ExportFormat format;

  /// True when [start]..[end] rolls back from now rather than covering whole
  /// calendar days, so the first and last day in the output may be partial.
  final bool rolling;

  /// Whether each value carries the app that recorded it (Fitbit, Samsung...).
  /// Useful context for a coach, but it roughly doubles raw-point size.
  final bool includeSources;

  ExportResult build() {
    final present = points.map((p) => p.type.name).toSet();
    final requested = <String>{for (final m in metrics) ...m.types.map((t) => t.name)};

    final body = format == ExportFormat.dailySummary
        ? _buildSummary()
        : _buildRaw();

    final doc = <String, dynamic>{
      'export': {
        'source': 'Android Health Connect',
        'app': 'copy-fit',
        'generated_at': isoLocal(DateTime.now()),
        'timezone': DateTime.now().timeZoneName,
        'utc_offset_minutes': DateTime.now().timeZoneOffset.inMinutes,
        // A rolling window starts mid-day, so dates alone would misstate it.
        'range': rolling
            ? {
                'from': isoLocal(start),
                'to': isoLocal(end),
                'hours': end.difference(start).inHours,
              }
            : {'start': isoDate(start), 'end': isoDate(end)},
        'format': format == ExportFormat.dailySummary ? 'daily_summary' : 'raw_points',
        if (format == ExportFormat.dailySummary)
          'notes': [
            'Days are local calendar days. A day is omitted entirely if it had no data.',
            'Sleep is filed under the date the session ENDED (the wake-up date), '
                'so a night that crosses midnight stays on one day.',
            'Every other metric is filed under the date its reading started.',
            'sleep.main_sleep is the longest session of that day; sleep.naps holds '
                'every other session, each with its own start and end.',
            'sleep.asleep_min and sleep.in_bed_min are totals across all sessions '
                'that day, so a night plus a nap add up.',
            'Within a session, asleep_min counts deep + rem + light and excludes '
                'awake; in_bed_min is the full session length.',
            'stages_available: false means the source logged a session but no stage '
                'breakdown, so asleep_min falls back to the session length.',
            'sleep.unassigned_stages holds stage time that belonged to no session; '
                'it is excluded from asleep_min and is usually a source quirk.',
            'Units are given per metric in the "units" object.',
            if (rolling)
              'This is a rolling window, not whole days. The first and last '
                  'days may be partial, so their totals can understate a full '
                  'day. Sleep is unaffected: a session is included whole or not '
                  'at all.',
          ],
      },
      ...body,
    };

    final json = const JsonEncoder.withIndent('  ').convert(doc);
    final days = (body['days'] as List?)?.length ?? 0;

    return ExportResult(
      json: json,
      pointCount: points.length,
      dayCount: days,
      typesWithData: (present.toList()..sort()),
      typesWithoutData: (requested.difference(present).toList()..sort()),
    );
  }

  // ---------------------------------------------------------------- raw

  Map<String, dynamic> _buildRaw() {
    final sorted = [...points]..sort((a, b) => a.dateFrom.compareTo(b.dateFrom));
    return {
      'points': [
        for (final p in sorted)
          <String, dynamic>{
            'type': p.type.name,
            'from': isoLocal(p.dateFrom),
            if (p.dateTo != p.dateFrom) 'to': isoLocal(p.dateTo),
            'value': _rawValue(p),
            'unit': _unitLabel(p.unit),
            if (includeSources) 'source': p.sourceName,
            if (p.recordingMethod != RecordingMethod.unknown)
              'recorded': p.recordingMethod.name,
          },
      ],
    };
  }

  dynamic _rawValue(HealthDataPoint p) {
    final v = p.value;
    if (v is NumericHealthValue) return _round(v.numericValue, 3);
    if (v is WorkoutHealthValue) return _workoutValue(v);
    if (v is NutritionHealthValue) return _nutritionValue(v);
    return v.toJson();
  }

  // ------------------------------------------------------------ summary

  Map<String, dynamic> _buildSummary() {
    // date -> metric key -> points
    final byDay = <String, Map<String, List<HealthDataPoint>>>{};
    final units = <String, String>{};

    // Map every requested Health Connect type back to the metric that asked
    // for it, so a point knows which JSON key it belongs under.
    final typeToMetric = <HealthDataType, Metric>{
      for (final m in metrics)
        for (final t in m.types) t: m,
    };

    // Sleep cannot be bucketed point by point: a stage only means something
    // relative to the session it belongs to, so it is collected whole and
    // resolved separately below.
    final sleepPoints = <HealthDataPoint>[];

    for (final p in points) {
      final metric = typeToMetric[p.type];
      if (metric == null) continue;

      if (metric.agg == Agg.sleep) {
        sleepPoints.add(p);
        continue;
      }

      final day = isoDate(p.dateFrom);
      byDay.putIfAbsent(day, () => {}).putIfAbsent(metric.key, () => []).add(p);

      final label = _unitLabel(p.unit);
      if (label.isNotEmpty) units.putIfAbsent(metric.key, () => label);
    }

    final sleepMetric =
        metrics.where((m) => m.agg == Agg.sleep).cast<Metric?>().firstWhere(
              (m) => true,
              orElse: () => null,
            );
    final sleepByDay =
        sleepMetric == null ? const <String, Map<String, dynamic>>{} : _buildSleep(sleepPoints);

    final dates = <String>{...byDay.keys, ...sleepByDay.keys}.toList()..sort();
    final days = <Map<String, dynamic>>[];

    for (final date in dates) {
      final entry = <String, dynamic>{'date': date};
      final perMetric = byDay[date] ?? const {};

      // Walk `metrics` rather than the map so key order is stable and matches
      // the order shown in the picker.
      for (final m in metrics) {
        if (m.agg == Agg.sleep) {
          final sleep = sleepByDay[date];
          if (sleep != null) entry[m.key] = sleep;
          continue;
        }
        final pts = perMetric[m.key];
        if (pts == null || pts.isEmpty) continue;
        final value = _aggregate(m, pts);
        if (value != null) entry[m.key] = value;
      }

      if (entry.length > 1) days.add(entry);
    }

    return {
      'units': {
        ...units,
        if (sleepByDay.isNotEmpty) 'sleep': 'min',
      },
      'days': days,
    };
  }

  /// Some sources round stage edges a little past the session boundary.
  static const _stageSlop = Duration(minutes: 2);

  /// Index of the session whose interval contains [stage], or -1. Only used
  /// when a stage arrives without a matching session uuid.
  static int _sessionContaining(
    HealthDataPoint stage,
    List<HealthDataPoint> sessions,
  ) {
    for (var i = 0; i < sessions.length; i++) {
      final s = sessions[i];
      if (!stage.dateFrom.isBefore(s.dateFrom.subtract(_stageSlop)) &&
          !stage.dateTo.isAfter(s.dateTo.add(_stageSlop))) {
        return i;
      }
    }
    return -1;
  }

  /// Resolves raw sleep points into one object per wake date.
  ///
  /// Sessions are the unit that matters. Each stage is attached to the session
  /// that contains it, and the whole session is then filed under the date it
  /// ended — so a night that crosses midnight stays intact instead of
  /// scattering its pre-midnight stages onto the previous day.
  Map<String, Map<String, dynamic>> _buildSleep(List<HealthDataPoint> pts) {
    final sessions = [
      for (final p in pts)
        if (p.type == HealthDataType.SLEEP_SESSION) p,
    ]..sort((a, b) => a.dateFrom.compareTo(b.dateFrom));

    final stages = [
      for (final p in pts)
        if (p.type != HealthDataType.SLEEP_SESSION) p,
    ];

    // Each stage carries its parent session's uuid, so the real parentage
    // survives the trip from Health Connect and does not need to be guessed.
    final sessionByUuid = <String, int>{
      for (var i = 0; i < sessions.length; i++) sessions[i].uuid: i,
    };

    final stagesFor = <int, List<HealthDataPoint>>{};
    final orphans = <HealthDataPoint>[];

    for (final stage in stages) {
      var owner = sessionByUuid[stage.uuid] ?? -1;

      // A stage can outlive its session in the results when the session began
      // before the queried window. Fall back to the interval in that case.
      if (owner < 0) owner = _sessionContaining(stage, sessions);

      if (owner >= 0) {
        stagesFor.putIfAbsent(owner, () => []).add(stage);
      } else {
        orphans.add(stage);
      }
    }

    final perDay = <String, List<Map<String, dynamic>>>{};
    for (var i = 0; i < sessions.length; i++) {
      final s = sessions[i];
      perDay
          .putIfAbsent(isoDate(s.dateTo), () => [])
          .add(_sessionObject(s, stagesFor[i] ?? const []));
    }

    // Stages with no session are kept rather than dropped, so the numbers
    // still add up and an odd source is visible instead of silently lost.
    final orphansByDay = <String, Map<String, num>>{};
    for (final o in orphans) {
      final key = _sleepStageKeys[o.type];
      if (key == null) continue;
      final mins = o.dateTo.difference(o.dateFrom).inSeconds / 60;
      final day = orphansByDay.putIfAbsent(isoDate(o.dateTo), () => {});
      day[key] = (day[key] ?? 0) + mins;
    }

    final out = <String, Map<String, dynamic>>{};
    for (final date in {...perDay.keys, ...orphansByDay.keys}) {
      final daySessions = [...?perDay[date]]
        ..sort((a, b) =>
            (b['in_bed_min'] as num).compareTo(a['in_bed_min'] as num));

      num asleep = 0;
      num inBed = 0;
      for (final s in daySessions) {
        asleep += s['asleep_min'] as num;
        inBed += s['in_bed_min'] as num;
      }

      final loose = orphansByDay[date];
      final naps = daySessions.skip(1).toList()
        ..sort((a, b) => (a['start'] as String).compareTo(b['start'] as String));

      out[date] = {
        'asleep_min': _round(asleep, 1),
        'in_bed_min': _round(inBed, 1),
        if (inBed > 0) 'efficiency_pct': _round(asleep / inBed * 100, 1),
        'session_count': daySessions.length,
        if (daySessions.isNotEmpty) 'main_sleep': daySessions.first,
        if (naps.isNotEmpty) 'naps': naps,
        if (loose != null)
          'unassigned_stages': {
            for (final e in loose.entries) e.key: _round(e.value, 1),
          },
      };
    }
    return out;
  }

  /// One sleep session, with its own start and end preserved.
  Map<String, dynamic> _sessionObject(
    HealthDataPoint session,
    List<HealthDataPoint> stages,
  ) {
    final byStage = <String, num>{};
    for (final st in stages) {
      final key = _sleepStageKeys[st.type];
      if (key == null) continue;
      byStage[key] =
          (byStage[key] ?? 0) + st.dateTo.difference(st.dateFrom).inSeconds / 60;
    }

    final inBed = session.dateTo.difference(session.dateFrom).inSeconds / 60;

    num asleep = 0;
    var haveStages = false;
    for (final k in _asleepStageKeys) {
      if (byStage.containsKey(k)) {
        asleep += byStage[k]!;
        haveStages = true;
      }
    }
    // Without a stage breakdown the best available estimate is the session
    // itself, which is what a source that reports sleep but not architecture
    // is actually telling us.
    if (!haveStages) asleep = inBed;

    return {
      'start': isoLocal(session.dateFrom),
      'end': isoLocal(session.dateTo),
      'in_bed_min': _round(inBed, 1),
      'asleep_min': _round(asleep, 1),
      if (inBed > 0) 'efficiency_pct': _round(asleep / inBed * 100, 1),
      if (!haveStages) 'stages_available': false,
      for (final e in byStage.entries) e.key: _round(e.value, 1),
      if (includeSources) 'source': session.sourceName,
    };
  }

  dynamic _aggregate(Metric m, List<HealthDataPoint> pts) {
    switch (m.agg) {
      case Agg.sum:
        num total = 0;
        var seen = false;
        for (final p in pts) {
          final n = _numeric(p.value);
          if (n == null) continue;
          total += n;
          seen = true;
        }
        return seen ? _round(total) : null;

      case Agg.stats:
        final values = [for (final p in pts) ?_numeric(p.value)];
        if (values.isEmpty) return null;
        values.sort();
        final sum = values.fold<num>(0, (a, b) => a + b);
        return {
          'min': _round(values.first),
          'avg': _round(sum / values.length),
          'max': _round(values.last),
          'n': values.length,
        };

      case Agg.average:
        final values = [for (final p in pts) ?_numeric(p.value)];
        if (values.isEmpty) return null;
        return _round(values.fold<num>(0, (a, b) => a + b) / values.length);

      case Agg.latest:
        final sorted = [...pts]..sort((a, b) => a.dateTo.compareTo(b.dateTo));
        for (final p in sorted.reversed) {
          final n = _numeric(p.value);
          if (n != null) return _round(n);
        }
        return null;

      case Agg.sleep:
        // Resolved in _buildSleep, which needs every session at once.
        return null;

      case Agg.workout:
        final sorted = [...pts]..sort((a, b) => a.dateFrom.compareTo(b.dateFrom));
        final out = [
          for (final p in sorted)
            if (p.value case final WorkoutHealthValue w)
              {
                ..._workoutValue(w),
                'start': isoLocal(p.dateFrom),
                'duration_min': _round(
                  p.dateTo.difference(p.dateFrom).inSeconds / 60,
                  1,
                ),
                if (includeSources) 'source': p.sourceName,
              },
        ];
        return out.isEmpty ? null : out;

      case Agg.nutrition:
        final sorted = [...pts]..sort((a, b) => a.dateFrom.compareTo(b.dateFrom));
        final out = [
          for (final p in sorted)
            if (p.value case final NutritionHealthValue n)
              {
                'time': isoLocal(p.dateFrom),
                ..._nutritionValue(n),
              },
        ];
        return out.isEmpty ? null : out;
    }
  }

  Map<String, dynamic> _workoutValue(WorkoutHealthValue w) => {
        'activity': w.workoutActivityType.name,
        if (w.totalEnergyBurned != null) 'energy_kcal': w.totalEnergyBurned,
        if (w.totalDistance != null) 'distance_m': w.totalDistance,
        if (w.totalSteps != null) 'steps': w.totalSteps,
      };

  Map<String, dynamic> _nutritionValue(NutritionHealthValue n) => {
        if (n.name != null) 'name': n.name,
        if (n.mealType != null) 'meal': n.mealType,
        if (n.calories != null) 'calories_kcal': _round(n.calories!),
        if (n.protein != null) 'protein_g': _round(n.protein!),
        if (n.carbs != null) 'carbs_g': _round(n.carbs!),
        if (n.fat != null) 'fat_g': _round(n.fat!),
        if (n.fiber != null) 'fiber_g': _round(n.fiber!),
        if (n.sugar != null) 'sugar_g': _round(n.sugar!),
        if (n.sodium != null) 'sodium_mg': _round(n.sodium!),
        if (n.water != null) 'water_l': _round(n.water!),
      };
}
