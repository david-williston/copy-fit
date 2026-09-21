import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

import 'metrics.dart';

/// Whether the device can talk to Health Connect at all.
enum ConnectState { checking, unavailable, updateRequired, ready }

class PermissionOutcome {
  const PermissionOutcome({required this.granted, required this.historyGranted});

  /// True when Health Connect reports every requested read permission granted.
  final bool granted;

  /// True when the app may also read data older than 30 days.
  final bool historyGranted;
}

/// Thin wrapper over the `health` plugin, so the UI never touches it directly.
class HealthService {
  final Health _health = Health();
  var _configured = false;

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    try {
      // configure() only resolves a device id. It must never hold up the UI, so
      // a failure or a stall is treated the same as success.
      await _health.configure().timeout(const Duration(seconds: 5));
    } catch (_) {
      // Ignored on purpose.
    }
    _configured = true;
  }

  Future<ConnectState> checkAvailability() async {
    await _ensureConfigured();
    try {
      final status = await _health.getHealthConnectSdkStatus();
      return switch (status) {
        HealthConnectSdkStatus.sdkAvailable => ConnectState.ready,
        HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired =>
          ConnectState.updateRequired,
        _ => ConnectState.unavailable,
      };
    } catch (_) {
      return ConnectState.unavailable;
    }
  }

  /// Sends the user to the Play Store listing for Health Connect.
  Future<void> openInstall() async {
    await _ensureConfigured();
    await _health.installHealthConnect();
  }

  List<HealthDataType> typesFor(Iterable<Metric> metrics) =>
      [for (final m in metrics) ...m.types];

  /// Makes sure the app may read [metrics], prompting only when something is
  /// actually missing — re-requesting every time would throw the user into the
  /// Health Connect permission screen on every single export.
  ///
  /// [needHistory] asks for the separate historical-data permission, without
  /// which Health Connect silently caps every read at the last 30 days.
  Future<PermissionOutcome> ensurePermissions(
    List<Metric> metrics, {
    required bool needHistory,
  }) async {
    await _ensureConfigured();
    final types = typesFor(metrics);
    if (types.isEmpty) {
      return const PermissionOutcome(granted: true, historyGranted: false);
    }

    var granted = await _health.hasPermissions(types) ?? false;
    if (!granted) {
      granted = await _health.requestAuthorization(
        types,
        permissions: [for (final _ in types) HealthDataAccess.READ],
      );
    }

    return PermissionOutcome(
      granted: granted,
      historyGranted: await _ensureHistory(needHistory),
    );
  }

  /// Whether the app may already read data older than 30 days.
  ///
  /// Never prompts. This exists so the UI can show the real state on launch
  /// instead of assuming the worst until the first read.
  Future<bool> isHistoryAuthorized() async {
    await _ensureConfigured();
    return _ensureHistory(false);
  }

  Future<bool> _ensureHistory(bool request) async {
    try {
      if (!await _health.isHealthDataHistoryAvailable()) return false;
      if (await _health.isHealthDataHistoryAuthorized()) return true;
      if (!request) return false;
      return await _health.requestHealthDataHistoryAuthorization();
    } catch (_) {
      // Older Health Connect builds do not expose the history permission;
      // reads then simply cap at 30 days, which the UI already warns about.
      return false;
    }
  }

  /// Reads every type separately — both so one failure cannot abort the export,
  /// and so the result can say which type produced what.
  Future<ReadReport> read({
    required List<Metric> metrics,
    required DateTime start,
    required DateTime end,
    void Function(String label)? onProgress,
  }) async {
    await _ensureConfigured();
    final points = <HealthDataPoint>[];
    final diagnostics = <TypeDiagnostic>[];

    for (final m in metrics) {
      onProgress?.call(m.label);

      for (final type in m.types) {
        bool? permitted;
        try {
          permitted = await _health.hasPermissions([type]);
        } catch (_) {
          // Leave it unknown rather than claiming denial.
        }

        try {
          final result = await _health.getHealthDataFromTypes(
            types: [type],
            startTime: start,
            endTime: end,
          );
          points.addAll(result);
          diagnostics.add(TypeDiagnostic(
            type: type,
            metricKey: m.key,
            count: result.length,
            permitted: permitted,
            earliest: result.isEmpty
                ? null
                : result
                    .map((p) => p.dateFrom)
                    .reduce((a, b) => a.isBefore(b) ? a : b),
            latest: result.isEmpty
                ? null
                : result
                    .map((p) => p.dateTo)
                    .reduce((a, b) => a.isAfter(b) ? a : b),
            sources: {for (final p in result) p.sourceName},
          ));
        } catch (e) {
          diagnostics.add(TypeDiagnostic(
            type: type,
            metricKey: m.key,
            count: 0,
            permitted: permitted,
            error: '$e',
          ));
        }
      }
    }

    return ReadReport(points: points, diagnostics: diagnostics);
  }
}

/// What one Health Connect data type returned.
class TypeDiagnostic {
  const TypeDiagnostic({
    required this.type,
    required this.metricKey,
    required this.count,
    this.permitted,
    this.error,
    this.earliest,
    this.latest,
    this.sources = const {},
  });

  final HealthDataType type;
  final String metricKey;
  final int count;

  /// Null when Health Connect would not say.
  final bool? permitted;

  final String? error;
  final DateTime? earliest;
  final DateTime? latest;
  final Set<String> sources;

  /// The likeliest explanation for an empty result, in plain words.
  String get verdict {
    if (error != null) return 'failed: $error';
    if (count > 0) return '$count from ${sources.join(", ")}';
    if (permitted == false) return 'no permission granted';
    return 'permission granted, but no app has written this data';
  }
}

class ReadReport {
  const ReadReport({required this.points, required this.diagnostics});

  final List<HealthDataPoint> points;
  final List<TypeDiagnostic> diagnostics;

  bool get anyDenied => diagnostics.any((d) => d.permitted == false);
  bool get anyFailed => diagnostics.any((d) => d.error != null);

  /// The oldest reading seen anywhere, which is how a silent 30-day cap shows
  /// itself when a longer range was requested.
  DateTime? get earliestPoint {
    final all = [for (final d in diagnostics) ?d.earliest];
    if (all.isEmpty) return null;
    return all.reduce((a, b) => a.isBefore(b) ? a : b);
  }

  /// Mirrors the Diagnostics card into the debug console, where it is far
  /// easier to read and copy than on the phone. Debug builds only.
  void debugDump() {
    if (!kDebugMode) return;
    debugPrint('=== copy-fit read report: ${points.length} points ===');
    for (final d in diagnostics) {
      final range = d.earliest == null
          ? ''
          : '  [${d.earliest!.toIso8601String().split("T").first}'
              ' -> ${d.latest!.toIso8601String().split("T").first}]';
      debugPrint('  ${d.type.name.padRight(28)} ${d.verdict}$range');
    }
    debugPrint('=== end report ===');
  }
}
