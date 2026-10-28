// Branch fix/login-unverified-403 QA — direct tests for the promoted shared
// [openExternalUri] helper (seven callers: four Instagram openers, guest
// tap-to-call, registration legal links, Account legal rows).
//
// Covered:
//   1. launches the exact URI with the default externalApplication mode;
//   2. forwards a caller-supplied mode;
//   3. launch reports false → error snack with the caller's message;
//   4. launch throws (PlatformException) → error snack, no escaped exception;
//   5. launch throws a non-platform error → error snack;
//   6. null URI → error snack, launcher never called;
//   7. success → no snack;
//   8. the caller unmounts while the launch is in flight → no snack, no
//      exception (the post-await `context.mounted` guard);
//   9. a thrown tel: PlatformException logs only its code — never the phone
//      number or the exception message;
//  10. a thrown non-platform error logs only its runtimeType.
//
// 9–10 capture the debug log line through the `@visibleForTesting`
// [debugOpenExternalUriLogSink] seam (`dart:developer`'s `log()` itself
// cannot be observed in-process).

import 'dart:async';

import 'package:beautica_mobile/core/network/logging_interceptor.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:beautica_mobile/shared/utils/open_external_uri.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../../helpers/pump_app.dart';
import '../../helpers/velvet_snack_matchers.dart';

class _MockUrlLauncher extends Mock
    with MockPlatformInterfaceMixin
    implements UrlLauncherPlatform {}

const String _err = 'open-failed-message';
const Key _btn = Key('open-external-uri-test-button');
final Uri _uri = Uri.parse('https://beautica.app/privacy');

/// One button that calls the helper exactly as a screen would.
Widget _host(Uri? uri, {LaunchMode? mode}) => Scaffold(
  body: Builder(
    builder: (BuildContext context) => TextButton(
      key: _btn,
      onPressed: () => mode == null
          ? openExternalUri(context, uri, errorMessage: _err)
          : openExternalUri(context, uri, errorMessage: _err, mode: mode),
      child: const SizedBox(width: 80, height: 48),
    ),
  ),
);

void main() {
  late _MockUrlLauncher launcher;
  late UrlLauncherPlatform original;
  late LogSink originalSink;
  late List<String> logged;

  setUpAll(() => registerFallbackValue(const LaunchOptions()));

  setUp(() {
    original = UrlLauncherPlatform.instance;
    launcher = _MockUrlLauncher();
    UrlLauncherPlatform.instance = launcher;
    originalSink = debugOpenExternalUriLogSink;
    logged = <String>[];
    debugOpenExternalUriLogSink =
        (String message, {String name = '', int level = 0, Object? error}) {
          logged.add('$message|$name|$level|${error ?? ''}');
        };
  });
  tearDown(() {
    UrlLauncherPlatform.instance = original;
    debugOpenExternalUriLogSink = originalSink;
  });

  Future<void> tapOpen(WidgetTester tester) async {
    await tester.tap(find.byKey(_btn));
    await pumpVelvetSnackIn(tester);
  }

  group('openExternalUri', () {
    testWidgets('1. launches the exact uri with externalApplication by '
        'default', (tester) async {
      when(
        () => launcher.launchUrl(any(), any()),
      ).thenAnswer((_) async => true);
      await tester.pumpApp(_host(_uri));

      await tapOpen(tester);

      final List<dynamic> captured = verify(
        () => launcher.launchUrl(captureAny(), captureAny()),
      ).captured;
      expect(captured, hasLength(2), reason: 'exactly one launch');
      expect(captured[0], 'https://beautica.app/privacy');
      expect(
        (captured[1] as LaunchOptions).mode,
        PreferredLaunchMode.externalApplication,
      );
    });

    testWidgets('2. forwards a caller-supplied launch mode', (tester) async {
      when(
        () => launcher.launchUrl(any(), any()),
      ).thenAnswer((_) async => true);
      await tester.pumpApp(_host(_uri, mode: LaunchMode.inAppBrowserView));

      await tapOpen(tester);

      final LaunchOptions options =
          verify(() => launcher.launchUrl(any(), captureAny())).captured.single
              as LaunchOptions;
      expect(options.mode, PreferredLaunchMode.inAppBrowserView);
    });

    testWidgets('3. a launch that reports false shows the error snack', (
      tester,
    ) async {
      when(
        () => launcher.launchUrl(any(), any()),
      ).thenAnswer((_) async => false);
      await tester.pumpApp(_host(_uri));

      await tapOpen(tester);

      expectVelvetSnack(_err, variant: VelvetSnackVariant.error);
      await pumpPastVelvetSnack(tester);
    });

    testWidgets('4. a launch throwing PlatformException shows the error snack '
        'and the exception never escapes', (tester) async {
      when(() => launcher.launchUrl(any(), any())).thenAnswer(
        (_) async => throw PlatformException(
          code: 'ACTIVITY_NOT_FOUND',
          message: 'No Activity found to handle tel:+380671234567',
        ),
      );
      await tester.pumpApp(_host(_uri));

      await tapOpen(tester);

      expect(tester.takeException(), isNull);
      expectVelvetSnack(_err, variant: VelvetSnackVariant.error);
      await pumpPastVelvetSnack(tester);
    });

    testWidgets('5. a launch throwing a non-platform error shows the error '
        'snack', (tester) async {
      when(
        () => launcher.launchUrl(any(), any()),
      ).thenAnswer((_) async => throw StateError('boom'));
      await tester.pumpApp(_host(_uri));

      await tapOpen(tester);

      expect(tester.takeException(), isNull);
      expectVelvetSnack(_err, variant: VelvetSnackVariant.error);
      await pumpPastVelvetSnack(tester);
    });

    testWidgets('6. a null uri shows the error snack without any launch', (
      tester,
    ) async {
      await tester.pumpApp(_host(null));

      await tapOpen(tester);

      verifyNever(() => launcher.launchUrl(any(), any()));
      expectVelvetSnack(_err, variant: VelvetSnackVariant.error);
      await pumpPastVelvetSnack(tester);
    });

    testWidgets('7. a successful launch shows no snack', (tester) async {
      when(
        () => launcher.launchUrl(any(), any()),
      ).thenAnswer((_) async => true);
      await tester.pumpApp(_host(_uri));

      await tapOpen(tester);

      expect(find.byType(VelvetSnack), findsNothing);
    });

    testWidgets('8. unmounting before a failed launch resolves shows no snack '
        'and throws nothing', (tester) async {
      final Completer<bool> pending = Completer<bool>();
      when(
        () => launcher.launchUrl(any(), any()),
      ).thenAnswer((_) => pending.future);
      await tester.pumpApp(_host(_uri));
      await tester.tap(find.byKey(_btn));
      await tester.pump();
      verify(() => launcher.launchUrl(any(), any())).called(1);

      // The caller's screen goes away while the OS launch is still pending.
      await tester.pumpApp(const Scaffold(body: SizedBox.shrink()));
      expect(find.byKey(_btn), findsNothing);
      pending.complete(false);
      await pumpVelvetSnackIn(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(VelvetSnack), findsNothing);
      expect(find.text(_err), findsNothing);
    });

    testWidgets('9. a thrown tel: PlatformException logs only its code — '
        'never the phone number or the message', (tester) async {
      when(() => launcher.launchUrl(any(), any())).thenAnswer(
        (_) async => throw PlatformException(
          code: 'ACTIVITY_NOT_FOUND',
          message: 'No Activity found to handle tel:+380501234567',
        ),
      );
      await tester.pumpApp(_host(Uri.parse('tel:+380501234567')));

      await tapOpen(tester);

      expect(logged, hasLength(1), reason: 'exactly one log line');
      final String line = logged.single;
      expect(line, contains('PlatformException(ACTIVITY_NOT_FOUND)'));
      expect(line, isNot(contains('380501234567')));
      expect(line, isNot(contains('No Activity')));
      expect(line, isNot(contains('tel:')));
      await pumpPastVelvetSnack(tester);
    });

    testWidgets('10. a thrown non-platform error logs only its runtimeType', (
      tester,
    ) async {
      when(
        () => launcher.launchUrl(any(), any()),
      ).thenAnswer((_) async => throw StateError('boom tel:+380501234567'));
      await tester.pumpApp(_host(Uri.parse('tel:+380501234567')));

      await tapOpen(tester);

      expect(logged, hasLength(1), reason: 'exactly one log line');
      final String line = logged.single;
      expect(line, contains('External URI launch threw: StateError|'));
      expect(line, isNot(contains('boom')));
      expect(line, isNot(contains('380501234567')));
      await pumpPastVelvetSnack(tester);
    });
  });
}
