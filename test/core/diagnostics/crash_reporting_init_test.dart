// Phase 410 (R.3 D3/D8) — initialising the real SDK with a fake transport.
//
// Proves: after init BOTH global handlers are Sentry's (FlutterError.onError
// catches the build/ErrorWidget errors, PlatformDispatcher.onError the async
// ones) and each still chains the handler that was there before; one
// FlutterError and one PlatformDispatcher error each produce exactly one
// SCRUBBED envelope; opting out produces zero.
import 'dart:convert';

import 'package:beautica_mobile/core/diagnostics/crash_reporting.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/request_id_interceptor.dart';
import 'package:beautica_mobile/core/storage/storage_keys.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../helpers/fakes/fake_diagnostics_store.dart';

const CrashReportingConfig _config = CrashReportingConfig(
  dsn: 'https://public@o1.ingest.de.sentry.io/2',
  env: 'staging',
  release: 'beautica-mobile@1.0.0+7',
);

class _FakeTransport implements Transport {
  final List<SentryEnvelope> envelopes = <SentryEnvelope>[];

  @override
  Future<SentryId?> send(SentryEnvelope envelope) async {
    envelopes.add(envelope);
    return SentryId.newId();
  }

  /// Decoded event payloads (sessions etc. filtered out).
  Future<List<Map<String, dynamic>>> events() async {
    final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
    for (final SentryEnvelope e in envelopes) {
      for (final SentryEnvelopeItem item in e.items) {
        if (item.header.type != 'event') continue;
        final List<int> bytes = await item.dataFactory();
        out.add(jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>);
      }
    }
    return out;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeTransport transport;
  late FakeDiagnosticsStore store;
  late FlutterExceptionHandler? originalFlutter;
  late ErrorCallback? originalPlatform;
  late List<Object> chainedFlutter;
  late List<Object> chainedPlatform;

  setUp(() {
    transport = _FakeTransport();
    store = FakeDiagnosticsStore();
    originalFlutter = FlutterError.onError;
    originalPlatform = PlatformDispatcher.instance.onError;
    chainedFlutter = <Object>[];
    chainedPlatform = <Object>[];
    // The "previous" handlers the SDK must chain to.
    FlutterError.onError = (FlutterErrorDetails d) =>
        chainedFlutter.add(d.exception);
    PlatformDispatcher.instance.onError = (Object e, StackTrace _) {
      chainedPlatform.add(e);
      return true;
    };
  });

  tearDown(() async {
    await CrashReporting.debugReset();
    FlutterError.onError = originalFlutter;
    PlatformDispatcher.instance.onError = originalPlatform;
  });

  Future<void> start() => startCrashReporting(
    _config,
    store: store,
    debugConfigure: (SentryFlutterOptions o) {
      o
        ..transport = transport
        ..autoInitializeNativeSdk = false
        ..enableAutoSessionTracking = false;
    },
  );

  test(
    'both global handlers are installed and chain the previous ones',
    () async {
      final FlutterExceptionHandler? before = FlutterError.onError;
      final ErrorCallback? platformBefore = PlatformDispatcher.instance.onError;
      await start();
      expect(CrashReporting.isRunning, isTrue);
      expect(FlutterError.onError, isNotNull);
      expect(FlutterError.onError, isNot(same(before)));
      expect(PlatformDispatcher.instance.onError, isNotNull);
      expect(PlatformDispatcher.instance.onError, isNot(same(platformBefore)));
    },
  );

  test('a FlutterError produces one scrubbed event and chains', () async {
    await start();
    FlutterError.onError!(
      FlutterErrorDetails(
        exception: StateError('build failed for canary@x.ua +380501112233'),
        stack: StackTrace.current,
        library: 'widgets library',
      ),
    );
    await pumpEventQueue(times: 200); // let the async capture land
    final List<Map<String, dynamic>> events = await transport.events();
    expect(events, hasLength(1));
    final String raw = jsonEncode(events.single);
    expect(raw, isNot(contains('canary@x.ua')));
    expect(raw, isNot(contains('380501112233')));
    expect(raw, contains('[email]'));
    expect(events.single['environment'], 'staging');
    expect(events.single['release'], 'beautica-mobile@1.0.0+7');
    expect(events.single['dist'], '7');
    final Map<String, dynamic> user =
        events.single['user'] as Map<String, dynamic>;
    expect(user.keys, <String>['id']);
    expect(user['id'], store.values[StorageKeys.diagnosticsInstallId]);
    expect(chainedFlutter, hasLength(1), reason: 'previous handler chained');
  });

  test(
    'a PlatformDispatcher error produces one scrubbed event and chains',
    () async {
      await start();
      PlatformDispatcher.instance.onError!(
        StateError('async boom code 482913'),
        StackTrace.current,
      );
      await pumpEventQueue(times: 200);
      final List<Map<String, dynamic>> events = await transport.events();
      expect(events, hasLength(1));
      expect(jsonEncode(events.single), isNot(contains('482913')));
      expect(chainedPlatform, hasLength(1), reason: 'previous handler chained');
    },
  );

  test('opted out at startup -> SDK not initialised, zero envelopes', () async {
    store.values[StorageKeys.diagnosticsEnabled] = 'false';
    await start();
    expect(CrashReporting.isConfigured, isTrue);
    expect(CrashReporting.isRunning, isFalse);
    await Sentry.captureException(StateError('x'));
    expect(transport.envelopes, isEmpty);
  });

  test('opt-out at runtime -> zero envelopes from that instant', () async {
    await start();
    await CrashReporting.applyOptIn(enabled: false, freshInstallId: null);
    expect(CrashReporting.isRunning, isFalse);
    await Sentry.captureException(StateError('after opt-out'));
    expect(await transport.events(), isEmpty);
  });

  test('beforeSend drops while opted out even with the SDK still up', () async {
    SentryFlutterOptions? captured;
    await startCrashReporting(
      _config,
      store: store,
      debugConfigure: (SentryFlutterOptions o) {
        o
          ..transport = transport
          ..autoInitializeNativeSdk = false
          ..enableAutoSessionTracking = false;
        captured = o;
      },
    );
    final BeforeSendCallback? beforeSend = captured?.beforeSend;
    expect(beforeSend, isNotNull);
    expect(await beforeSend!(SentryEvent(), Hint()), isNotNull);
    await CrashReporting.applyOptIn(enabled: false, freshInstallId: null);
    expect(await beforeSend(SentryEvent(), Hint()), isNull);
  });

  test('re-enabling re-initialises with the fresh install id', () async {
    await start();
    await CrashReporting.applyOptIn(enabled: false, freshInstallId: null);
    await CrashReporting.applyOptIn(enabled: true, freshInstallId: 'c' * 32);
    expect(CrashReporting.isRunning, isTrue);
    expect(CrashReporting.installId, 'c' * 32);
  });

  group('request_id tag (security audit 2026-11-05)', () {
    const String appId = '0123456789abcdef0123456789abcdef';

    DioException dioWith({required Object? sentId, String? echo}) {
      final RequestOptions o = RequestOptions(
        path: '/api/v1/bookings',
        headers: <String, dynamic>{kRequestIdHeader: ?sentId},
      );
      return DioException(
        requestOptions: o,
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(
          requestOptions: o,
          statusCode: 500,
          headers: Headers.fromMap(<String, List<String>>{
            if (echo != null) kRequestIdHeader: <String>[echo],
          }),
        ),
      );
    }

    Future<SentryEvent?> send(Object throwable) async {
      SentryFlutterOptions? captured;
      await startCrashReporting(
        _config,
        store: store,
        debugConfigure: (SentryFlutterOptions o) {
          o
            ..transport = transport
            ..autoInitializeNativeSdk = false
            ..enableAutoSessionTracking = false;
          captured = o;
        },
      );
      final BeforeSendCallback? beforeSend = captured?.beforeSend;
      expect(beforeSend, isNotNull);
      return beforeSend!(SentryEvent(throwable: throwable), Hint());
    }

    test('tags the APP-generated id, never the server echo', () async {
      final SentryEvent? out = await send(
        dioWith(sentId: appId, echo: 'srv-echo-+380501112233'),
      );
      expect(out?.tags?['request_id'], appId);
    });

    test('a Failure wrapping the DioException is tagged the same', () async {
      final SentryEvent? out = await send(
        ServerFailure(
          cause: dioWith(sentId: appId, echo: 'other-id-123'),
        ),
      );
      expect(out?.tags?['request_id'], appId);
    });

    test('a non-hex32 sent id is omitted', () async {
      final SentryEvent? out = await send(
        dioWith(sentId: 'not-our-format-+380501112233'),
      );
      expect(out, isNotNull);
      expect(out?.tags?.containsKey('request_id') ?? false, isFalse);
    });

    test('crashRequestIdTag: no HTTP cause -> null', () {
      expect(crashRequestIdTag(StateError('x')), isNull);
      expect(crashRequestIdTag(dioWith(sentId: null, echo: appId)), isNull);
      expect(crashRequestIdTag(dioWith(sentId: appId.toUpperCase())), isNull);
    });
  });

  test('tracesSampleRate is left unset (no tracing, D4)', () async {
    SentryFlutterOptions? captured;
    await startCrashReporting(
      _config,
      store: store,
      debugConfigure: (SentryFlutterOptions o) {
        o
          ..transport = transport
          ..autoInitializeNativeSdk = false
          ..enableAutoSessionTracking = false;
        captured = o;
      },
    );
    expect(captured?.tracesSampleRate, isNull);
    expect(captured?.isTracingEnabled(), isFalse);
  });
}
