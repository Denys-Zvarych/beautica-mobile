// Phase 075 (10.1) — pins the pre-runApp boot ORDER of lib/main.dart.
//
// Drives the real `main()` and observes it through the assert-only
// `StartupTrace.debugRecorder` seam (no production change). Slices must each
// be emitted exactly once, in order: timezones (before anything formats time),
// fonts, certPinning (fully finished BEFORE the ProviderContainer slice
// starts), container.
//
// Also pins that `AppConfig.assertSecureUrl` runs BEFORE the first slice (via
// the assert-only `AppConfig.debugOnAssertSecureUrl` hook), and that boot never touches
// the network: a recording `HttpOverrides` fails loudly if main() ever gains a
// startup HTTP call (even one a `catch` would swallow).
import 'dart:io';

import 'package:beautica_mobile/core/config/app_config.dart';
import 'package:beautica_mobile/core/perf/startup_trace.dart';
import 'package:beautica_mobile/main.dart' as app;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Event recorded by the `AppConfig.debugOnAssertSecureUrl` hook.
const String kAssertSecureUrlEvent = 'guard:assertSecureUrl';

const String _kNoNetworkMessage =
    'boot must not hit the network in this test, add an override';

void main() {
  final List<String> events = <String>[];

  setUp(() {
    events.clear();
    StartupTrace.debugRecorder = (String name, bool started) =>
        events.add('${started ? '+' : '-'}$name');
    AppConfig.debugOnAssertSecureUrl = () =>
        events.add('+$kAssertSecureUrlEvent');
    // No platform channels in the VM: stub splash/secure-storage/orientation.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_native_splash'),
          (_) async => null,
        );
  });
  tearDown(() {
    StartupTrace.debugRecorder = null;
    AppConfig.debugOnAssertSecureUrl = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_native_splash'),
          null,
        );
  });

  testWidgets('main() emits every boot slice exactly once: timezones, fonts, '
      'certPinning (finished) before container', (WidgetTester tester) async {
    final List<String> networkAttempts = <String>[];
    await tester.runAsync(() async {
      await HttpOverrides.runZoned(
        () => app.main(),
        createHttpClient: (SecurityContext? _) {
          networkAttempts.add('HttpClient created');
          throw StateError(_kNoNetworkMessage);
        },
      );
    });
    // Unmount the app so no provider timer outlives the test.
    await tester.pumpWidget(const SizedBox.shrink());

    expect(networkAttempts, isEmpty, reason: _kNoNetworkMessage);
    // The secure-URL guard must run before the first timed slice.
    expect(events.first, '+$kAssertSecureUrlEvent');
    expect(
      events.where((String e) => e.contains(kAssertSecureUrlEvent)).length,
      1,
    );
    expect(events.skip(1).toList(), <String>[
      '+boot:timezones',
      '-boot:timezones',
      '+boot:fonts',
      '-boot:fonts',
      '+boot:certPinning',
      '-boot:certPinning',
      '+boot:container',
      '-boot:container',
    ]);
  });
}
