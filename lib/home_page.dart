import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'exporter.dart';
import 'health_service.dart';
import 'metrics.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Bumped when the default selection changes, so a saved set from an older
  // build does not mask the new default.
  static const _prefMetrics = 'metrics.v2';
  static const _prefDays = 'days';
  static const _prefFormat = 'format';
  static const _prefSources = 'sources';

  final _service = HealthService();

  ConnectState _connect = ConnectState.checking;
  Set<String> _selected = {...kDefaultMetricKeys};
  int _days = 30;
  ExportFormat _format = ExportFormat.dailySummary;
  bool _includeSources = true;
  bool _historyGranted = false;
  DateTime? _lastStart;

  bool _busy = false;
  String _busyLabel = '';
  ExportResult? _result;
  ReadReport? _report;
  String? _error;

  @override
  void initState() {
    super.initState();
    _restore();
    _refreshAvailability();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      final saved = prefs.getStringList(_prefMetrics);
      if (saved != null && saved.isNotEmpty) {
        // Drop keys from an older build that no longer exist.
        _selected = saved.where((k) => kMetrics.any((m) => m.key == k)).toSet();
      }
      _days = prefs.getInt(_prefDays) ?? _days;
      _includeSources = prefs.getBool(_prefSources) ?? _includeSources;
      final fmt = prefs.getString(_prefFormat);
      if (fmt != null) {
        _format = ExportFormat.values.firstWhere(
          (f) => f.name == fmt,
          orElse: () => ExportFormat.dailySummary,
        );
      }
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefMetrics, _selected.toList());
    await prefs.setInt(_prefDays, _days);
    await prefs.setString(_prefFormat, _format.name);
    await prefs.setBool(_prefSources, _includeSources);
  }

  /// Applies a settings change and writes it straight to disk. Persisting only
  /// after a successful read loses any choice made before closing the app.
  void _updateSetting(VoidCallback change) {
    setState(change);
    _save();
  }

  Future<void> _refreshAvailability() async {
    final state = await _service.checkAvailability();
    // Ask up front, so the historical-access warning reflects what is actually
    // granted rather than staying on until the first read.
    final history =
        state == ConnectState.ready ? await _service.isHistoryAuthorized() : false;
    if (!mounted) return;
    setState(() {
      _connect = state;
      _historyGranted = history;
    });
  }

  List<Metric> get _selectedMetrics =>
      [for (final m in kMetrics) if (_selected.contains(m.key)) m];

  // --------------------------------------------------------------- actions

  Future<void> _run() async {
    final metrics = _selectedMetrics;
    if (metrics.isEmpty) {
      setState(() => _error = 'Pick at least one metric.');
      return;
    }

    setState(() {
      _busy = true;
      _busyLabel = 'Requesting permission';
      _error = null;
      _result = null;
      _report = null;
    });

    try {
      final outcome = await _service.ensurePermissions(
        metrics,
        needHistory: _days > 30,
      );
      _historyGranted = outcome.historyGranted;

      if (!outcome.granted) {
        setState(() {
          _busy = false;
          _error = 'Health Connect denied access. Grant the permissions in '
              'Health Connect > App permissions > Copy Fit, then try again.';
        });
        return;
      }

      // Whole local days: midnight at the start of the window through now.
      final now = DateTime.now();
      final endOfToday = DateTime(now.year, now.month, now.day)
          .add(const Duration(days: 1))
          .subtract(const Duration(microseconds: 1));
      final start = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: _days - 1));

      _lastStart = start;
      final report = await _service.read(
        metrics: metrics,
        start: start,
        end: endOfToday,
        onProgress: (label) {
          if (mounted) setState(() => _busyLabel = 'Reading $label');
        },
      );

      report.debugDump();

      if (!mounted) return;
      setState(() => _busyLabel = 'Building JSON');

      final result = Exporter(
        points: report.points,
        metrics: metrics,
        start: start,
        end: endOfToday,
        format: _format,
        includeSources: _includeSources,
      ).build();

      setState(() {
        _busy = false;
        _result = result;
        _report = report;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  Future<void> _copy() async {
    final json = _result?.json;
    if (json == null) return;
    await Clipboard.setData(ClipboardData(text: json));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('JSON copied — paste it into ChatGPT')),
    );
  }

  Future<void> _share() async {
    final result = _result;
    if (result == null) return;
    final stamp = isoDate(DateTime.now());
    await SharePlus.instance.share(
      ShareParams(text: result.json, subject: 'Health export $stamp'),
    );
  }

  // ----------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Copy Fit'),
        actions: [
          IconButton(
            tooltip: 'Recheck Health Connect',
            onPressed: _refreshAvailability,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            _ConnectBanner(
              state: _connect,
              onInstall: () async {
                await _service.openInstall();
                await _refreshAvailability();
              },
            ),
            const SizedBox(height: 16),
            _sectionLabel('Range'),
            _rangePicker(),
            if (_days > 30 && !_historyGranted) ...[
              const SizedBox(height: 8),
              _hint(
                'Ranges past 30 days need the "historical data" permission. '
                'If the export comes back short, grant it in Health Connect.',
              ),
            ],
            const SizedBox(height: 20),
            _sectionLabel('Format'),
            _formatPicker(),
            const SizedBox(height: 4),
            _hint(_format == ExportFormat.dailySummary
                ? 'One line per day. Small enough to paste into a chat.'
                : 'Every individual reading. Accurate but can run to megabytes.'),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _includeSources,
              onChanged: (v) => _updateSetting(() => _includeSources = v),
              title: const Text('Include recording app'),
              subtitle: const Text('Tags values with Fitbit, Samsung Health, etc.'),
            ),
            const SizedBox(height: 12),
            _sectionLabel('Data'),
            ..._metricGroups(),
            const SizedBox(height: 24),
            if (_error != null) ...[
              _ErrorCard(message: _error!),
              const SizedBox(height: 16),
            ],
            FilledButton.icon(
              onPressed: _busy || _connect != ConnectState.ready ? null : _run,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download),
              label: Text(_busy ? _busyLabel : 'Read Health Connect'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
            if (_result != null) ...[
              const SizedBox(height: 24),
              _ResultCard(result: _result!, format: _format),
            ],
            if (_report != null) ...[
              const SizedBox(height: 16),
              _DiagnosticsCard(
                report: _report!,
                requestedStart: _lastStart,
                historyGranted: _historyGranted,
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: _result == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: _copy,
                        icon: const Icon(Icons.copy_all),
                        label: const Text('Copy JSON'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _share,
                        icon: const Icon(Icons.ios_share),
                        label: const Text('Share'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
      );

  Widget _hint(String text) => Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      );

  Widget _rangePicker() {
    const options = {7: '7 days', 14: '14 days', 30: '30 days', 90: '90 days', 365: '1 year'};
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final e in options.entries)
          ChoiceChip(
            label: Text(e.value),
            selected: _days == e.key,
            onSelected: (_) => _updateSetting(() => _days = e.key),
          ),
      ],
    );
  }

  Widget _formatPicker() => SegmentedButton<ExportFormat>(
        segments: const [
          ButtonSegment(
            value: ExportFormat.dailySummary,
            label: Text('Daily summary'),
            icon: Icon(Icons.calendar_view_day),
          ),
          ButtonSegment(
            value: ExportFormat.rawPoints,
            label: Text('Raw points'),
            icon: Icon(Icons.scatter_plot),
          ),
        ],
        selected: {_format},
        onSelectionChanged: (s) => _updateSetting(() => _format = s.first),
      );

  List<Widget> _metricGroups() {
    final widgets = <Widget>[];
    for (final group in kGroupOrder) {
      final metrics = kMetrics.where((m) => m.group == group).toList();
      if (metrics.isEmpty) continue;
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Text(
          group,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
      ));
      widgets.add(Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final m in metrics)
            FilterChip(
              label: Text(m.label),
              selected: _selected.contains(m.key),
              onSelected: (on) => _updateSetting(() {
                on ? _selected.add(m.key) : _selected.remove(m.key);
              }),
            ),
        ],
      ));
    }
    return widgets;
  }
}

class _ConnectBanner extends StatelessWidget {
  const _ConnectBanner({required this.state, required this.onInstall});

  final ConnectState state;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final (IconData icon, String text, bool action) = switch (state) {
      ConnectState.checking => (Icons.hourglass_empty, 'Checking Health Connect…', false),
      ConnectState.ready => (Icons.check_circle, 'Health Connect is ready.', false),
      ConnectState.updateRequired => (
          Icons.system_update,
          'Health Connect needs an update before it can be used.',
          true
        ),
      ConnectState.unavailable => (
          Icons.error_outline,
          'Health Connect is not available on this device.',
          true
        ),
    };

    final good = state == ConnectState.ready;
    final bg = good ? scheme.secondaryContainer : scheme.errorContainer;
    final fg = good ? scheme.onSecondaryContainer : scheme.onErrorContainer;

    return Card(
      margin: EdgeInsets.zero,
      color: state == ConnectState.checking ? scheme.surfaceContainerHighest : bg,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: state == ConnectState.checking ? null : fg),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: state == ConnectState.checking ? null : fg,
                ),
              ),
            ),
            if (action)
              TextButton(
                onPressed: onInstall,
                child: Text(
                  state == ConnectState.updateRequired ? 'Update' : 'Install',
                  style: TextStyle(color: fg, fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result, required this.format});

  final ExportResult result;
  final ExportFormat format;

  String get _size {
    final b = result.byteSize;
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get _tokens {
    final t = result.approxTokens;
    return t < 1000 ? '~$t tokens' : '~${(t / 1000).toStringAsFixed(1)}k tokens';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final heavy = result.approxTokens > 100000;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _Pill(label: '${result.pointCount} readings'),
                if (format == ExportFormat.dailySummary)
                  _Pill(label: '${result.dayCount} days'),
                _Pill(label: _size),
                _Pill(label: _tokens, warn: heavy),
              ],
            ),
            if (heavy) ...[
              const SizedBox(height: 10),
              Text(
                'This is large for a chat message. Try "Daily summary", a '
                'shorter range, or fewer metrics.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.error),
              ),
            ],
            if (result.pointCount == 0) ...[
              const SizedBox(height: 10),
              Text(
                'No readings came back. Either nothing is syncing into Health '
                'Connect for these metrics, or the permissions were not granted.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (result.typesWithoutData.isNotEmpty) ...[
              const SizedBox(height: 12),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text(
                  '${result.typesWithoutData.length} requested types had no data',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      result.typesWithoutData.join(', '),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              height: 280,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  result.json,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, this.warn = false});

  final String label;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: warn ? scheme.errorContainer : scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: warn ? scheme.onErrorContainer : scheme.onSecondaryContainer,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// Explains a disappointing export: what each Health Connect type returned,
/// whether it was permitted, and whether the range came back truncated.
class _DiagnosticsCard extends StatelessWidget {
  const _DiagnosticsCard({
    required this.report,
    required this.requestedStart,
    required this.historyGranted,
  });

  final ReadReport report;
  final DateTime? requestedStart;
  final bool historyGranted;

  /// Health Connect silently caps reads at 30 days without the history
  /// permission. If the oldest reading lands well after the requested start,
  /// that cap is the likeliest explanation.
  bool get _looksTruncated {
    final start = requestedStart;
    final earliest = report.earliestPoint;
    if (start == null || earliest == null || historyGranted) return false;
    return earliest.difference(start).inDays > 2 &&
        DateTime.now().difference(earliest).inDays < 33;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    final mono = small?.copyWith(fontFamily: 'monospace', fontSize: 11);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.biotech, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Diagnostics',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 12),

            _Note(
              ok: historyGranted,
              text: historyGranted
                  ? 'Historical access granted — reads are not capped at 30 days.'
                  : 'No historical access. Health Connect will cap every read at '
                      'the last 30 days, whatever range you pick.',
            ),
            if (_looksTruncated)
              _Note(
                ok: false,
                text: 'The oldest reading is well inside the range you asked '
                    'for. That is what a 30-day cap looks like.',
              ),
            if (report.anyDenied)
              const _Note(
                ok: false,
                text: 'Some types were denied. Open Health Connect > App '
                    'permissions > Copy Fit and enable them there.',
              ),
            if (report.anyFailed)
              const _Note(
                ok: false,
                text: 'Some reads threw an error — see the per-type list below.',
              ),

            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),

            for (final d in report.diagnostics)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      d.count > 0
                          ? Icons.check_circle
                          : d.permitted == false || d.error != null
                              ? Icons.cancel
                              : Icons.remove_circle_outline,
                      size: 14,
                      color: d.count > 0
                          ? scheme.primary
                          : d.permitted == false || d.error != null
                              ? scheme.error
                              : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(d.type.name, style: mono),
                          Text(
                            d.verdict,
                            style: small?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          if (d.earliest case final e?)
                            Text(
                              '${isoDate(e)} → ${isoDate(d.latest!)}',
                              style: small?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.ok, required this.text});

  final bool ok;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.warning_amber,
            size: 15,
            color: ok ? scheme.primary : scheme.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: ok ? scheme.onSurface : scheme.error,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
