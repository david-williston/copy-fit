import 'package:copy_fit/export_range.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 9, 20, 8, 15);

  test('24 hours rolls back from now', () {
    final (:start, :end) = ExportRange.last24Hours.window(now);
    expect(end, now);
    expect(start, DateTime(2026, 9, 19, 8, 15));
    expect(ExportRange.last24Hours.isRolling, isTrue);
  });

  test('3 days covers whole calendar days ending tonight', () {
    final (:start, :end) = ExportRange.last3Days.window(now);
    expect(start, DateTime(2026, 9, 18), reason: 'midnight, two days back');
    expect(end, DateTime(2026, 9, 21).subtract(const Duration(microseconds: 1)));
    expect(ExportRange.last3Days.isRolling, isFalse);
  });

  test('calendar windows start at local midnight across daylight saving', () {
    // US daylight saving ends 1 November 2026. Subtracting Duration(days:)
    // across that change lands an hour off midnight; building from dates does
    // not. On a machine without daylight saving this passes either way.
    final (:start, end: _) =
        ExportRange.last3Days.window(DateTime(2026, 11, 3, 10));
    expect(start, DateTime(2026, 11, 1));
    expect((start.hour, start.minute), (0, 0));
  });

  test('only ranges past 30 days need the history permission', () {
    expect(
      [for (final r in ExportRange.values) if (r.needsHistory) r],
      [ExportRange.last90Days, ExportRange.lastYear],
    );
  });

  test('a day count saved by an older build maps to its range', () {
    expect(ExportRange.fromLegacyDays(90), ExportRange.last90Days);
    expect(ExportRange.fromLegacyDays(7), ExportRange.last7Days);
    expect(ExportRange.fromLegacyDays(5), isNull,
        reason: 'counts that are no longer offered fall back to the default');
  });
}
