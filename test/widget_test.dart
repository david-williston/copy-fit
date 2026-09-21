import 'package:copy_fit/main.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const channel = MethodChannel('flutter_health');

  /// Whether the stand-in Health Connect reports historical access as granted.
  var historyAuthorized = false;

  setUp(() {
    historyAuthorized = false;
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Copy Fit',
      packageName: 'com.davidwilliston.copy_fit',
      version: '1.1.1',
      buildNumber: '3',
      buildSignature: '',
    );
    // Stand in for Health Connect: report the SDK as available (native value 3)
    // so the UI reaches its normal ready state.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      return switch (call.method) {
        'getHealthConnectSdkStatus' => 3,
        'hasPermissions' => true,
        'isHealthDataHistoryAvailable' => true,
        'isHealthDataHistoryAuthorized' => historyAuthorized,
        _ => null,
      };
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('boots into a ready state with defaults selected', (tester) async {
    await tester.pumpWidget(const CopyFitApp());
    // Health().configure() never resolves off-device; let its timeout elapse.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    expect(find.text('Copy Fit'), findsOneWidget);
    expect(find.text('1.1.1'), findsOneWidget,
        reason: 'the version is shown beside the title');
    expect(find.text('Health Connect is ready.'), findsOneWidget);
    expect(find.text('30 days'), findsOneWidget);
    expect(find.text('Daily summary'), findsOneWidget);

    // The action button sits below the fold on a phone-sized screen.
    await tester.scrollUntilVisible(find.text('Read Health Connect'), 200);
    expect(find.text('Read Health Connect'), findsOneWidget);
  });

  testWidgets('a long range warns when historical access is missing', (tester) async {
    await tester.pumpWidget(const CopyFitApp());
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    await tester.tap(find.text('90 days'));
    await tester.pumpAndSettle();

    expect(find.textContaining('historical data'), findsOneWidget);
  });

  testWidgets('a settings change is persisted without needing a read', (tester) async {
    await tester.pumpWidget(const CopyFitApp());
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    await tester.tap(find.text('14 days'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('days'), 14,
        reason: 'the range is written as soon as it changes');

    await tester.tap(find.text('Raw points'));
    await tester.pumpAndSettle();
    expect(prefs.getString('format'), 'rawPoints');

    await tester.tap(find.text('Steps'));
    await tester.pumpAndSettle();
    expect(prefs.getStringList('metrics.v2'), contains('steps'));
  });

  testWidgets('no warning once historical access is already granted', (tester) async {
    historyAuthorized = true;

    await tester.pumpWidget(const CopyFitApp());
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    await tester.tap(find.text('90 days'));
    await tester.pumpAndSettle();

    // The permission is checked on launch, so the warning must not linger
    // until the first read.
    expect(find.textContaining('historical data'), findsNothing);
  });
}
