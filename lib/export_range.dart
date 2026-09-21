/// A window of time to export.
///
/// There are two kinds, on purpose. An `hours` window rolls back from now,
/// which is what a daily check-in wants: "the last 24 hours" returns last
/// night's sleep and nothing older. A `days` window covers whole local calendar
/// days ending today, which keeps every day's totals complete.
enum ExportRange {
  last24Hours('24 hours', hours: 24),
  last3Days('3 days', days: 3),
  last7Days('7 days', days: 7),
  last14Days('14 days', days: 14),
  last30Days('30 days', days: 30),
  last90Days('90 days', days: 90),
  lastYear('1 year', days: 365);

  const ExportRange(this.label, {this.hours, this.days});

  final String label;
  final int? hours;
  final int? days;

  bool get isRolling => hours != null;

  /// Health Connect caps reads at 30 days without the history permission.
  bool get needsHistory => (days ?? 0) > 30;

  /// The instants to query, relative to [now].
  ///
  /// Calendar windows are built from dates rather than by subtracting
  /// durations: a day is not always 24 hours, so subtracting `Duration(days:)`
  /// across a daylight-saving change lands an hour off midnight.
  ({DateTime start, DateTime end}) window(DateTime now) {
    if (hours case final h?) {
      return (start: now.subtract(Duration(hours: h)), end: now);
    }
    return (
      start: DateTime(now.year, now.month, now.day - (days! - 1)),
      end: DateTime(now.year, now.month, now.day + 1)
          .subtract(const Duration(microseconds: 1)),
    );
  }

  /// The range matching a day count saved by a build that stored ranges as a
  /// plain number, or null if that count is no longer offered.
  static ExportRange? fromLegacyDays(int days) {
    for (final r in values) {
      if (r.days == days) return r;
    }
    return null;
  }
}
