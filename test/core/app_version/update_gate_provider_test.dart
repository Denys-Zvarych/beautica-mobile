// Phase 438 — updateGateProvider: compare matrix, fail-open, resume throttle,
// cold-start retry backoff (fakeAsync — pumpEventQueue fires no Timer).
//
// The real generated AppConfigApi runs over a Dio whose adapter is scripted
// per call, so decoding (incl. malformed bodies) is the production path. The
// clock is injected through clockProvider; resume is driven through the real
// binding's lifecycle dispatch.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/app_version/app_version_info.dart';
import 'package:beautica_mobile/core/app_version/update_gate_provider.dart';
import 'package:beautica_mobile/core/network/api_client_provider.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// One scripted reply: a JSON body + status, or a transport error.
final class _Reply {
  const _Reply.json(this.body, {this.status = 200}) : error = null;
  const _Reply.raw(String raw) : body = raw, status = 200, error = null;
  const _Reply.error(DioExceptionType this.error) : body = null, status = 0;

  final Object? body;
  final int status;
  final DioExceptionType? error;
}

final class _Adapter implements HttpClientAdapter {
  _Adapter(this.replies);

  final List<_Reply> replies;
  int calls = 0;

  /// When set, every reply waits for it (holds a request in flight).
  Completer<void>? hold;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    final Completer<void>? gate = hold;
    if (gate != null) await gate.future;
    final int index = calls - 1;
    final _Reply r =
        replies[index < replies.length ? index : replies.length - 1];
    final DioExceptionType? error = r.error;
    if (error != null) {
      throw DioException(requestOptions: options, type: error);
    }
    final Object? body = r.body;
    return ResponseBody.fromString(
      body is String ? body : jsonEncode(body),
      r.status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object?> _config(int min, {String? storeUrl, int? latest}) =>
    <String, Object?>{
      'success': true,
      'data': <String, Object?>{
        'android': <String, Object?>{
          'minVersionCode': min,
          'latestVersionCode': latest ?? min,
          'storeUrl':
              storeUrl ??
              'https://play.google.com/store/apps/details?id=com.beautica.app',
        },
      },
    };

PackageInfo _info(String build) => PackageInfo(
  appName: 'Beautica',
  packageName: 'com.beautica.app',
  version: '1.5.0',
  buildNumber: build,
);

final class _Harness {
  _Harness(List<_Reply> replies, {String build = '7', bool infoThrows = false})
    : adapter = _Adapter(replies) {
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://api.beautica.app'))
      ..httpClientAdapter = adapter;
    container = ProviderContainer(
      overrides: [
        appConfigApiProvider.overrideWithValue(
          AppConfigApi(dio, standardSerializers),
        ),
        appPackageInfoProvider.overrideWith(
          (_) async =>
              infoThrows ? throw StateError('no plugin') : _info(build),
        ),
        clockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(container.dispose);
  }

  final _Adapter adapter;
  late final ProviderContainer container;
  DateTime now = DateTime.utc(2026, 11, 7, 12);

  /// Mounts the provider (cold-start check) and lets it finish.
  Future<UpdateGateState> boot() async {
    container.listen(updateGateProvider, (_, _) {});
    await pumpEventQueue();
    return container.read(updateGateProvider);
  }

  UpdateGateState get state => container.read(updateGateProvider);
}

/// Background → foreground through the real binding dispatch (synchronous).
void _dispatchResume() {
  final TestWidgetsFlutterBinding binding = TestWidgetsFlutterBinding.instance;
  for (final AppLifecycleState s in <AppLifecycleState>[
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    binding.handleAppLifecycleStateChanged(s);
  }
}

Future<void> _resume() async {
  _dispatchResume();
  await pumpEventQueue();
}

class _NoopTransport implements Transport {
  @override
  Future<SentryId?> send(SentryEnvelope envelope) async =>
      const SentryId.empty();
}

/// Drains microtasks and zero-length timers inside fakeAsync.
void _settle(FakeAsync async) => async.elapse(Duration.zero);

const _Reply _timeout = _Reply.error(DioExceptionType.connectionTimeout);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  group('isUpdateRequired — the compare matrix (D1)', () {
    test('below → required', () {
      expect(isUpdateRequired(buildNumber: '7', minVersionCode: 8), isTrue);
    });
    test('equal → ok', () {
      expect(isUpdateRequired(buildNumber: '7', minVersionCode: 7), isFalse);
    });
    test('above → ok', () {
      expect(isUpdateRequired(buildNumber: '7', minVersionCode: 6), isFalse);
    });
    test('unparsable build never blocks', () {
      for (final String raw in <String>['', 'abc', '7a', '-1', '1.5']) {
        expect(
          isUpdateRequired(buildNumber: raw, minVersionCode: 1 << 30),
          isFalse,
          reason: 'build "$raw"',
        );
      }
    });
  });

  group('cold start', () {
    test('starts ok before any reply (never blocks the first frame)', () {
      final _Harness h = _Harness(<_Reply>[_Reply.json(_config(99))]);
      h.container.listen(updateGateProvider, (_, _) {});
      expect(h.state, const UpdateGateState.ok());
    });

    test(
      'build < min → required, carrying package, version and storeUrl',
      () async {
        final _Harness h = _Harness(<_Reply>[
          _Reply.json(_config(8, storeUrl: 'https://play.google.com/x')),
        ]);
        expect(
          await h.boot(),
          const UpdateGateState.required(
            packageName: 'com.beautica.app',
            installedVersion: '1.5.0',
            storeUrl: 'https://play.google.com/x',
          ),
        );
        expect(h.adapter.calls, 1);
      },
    );

    test('build == min → ok', () async {
      final _Harness h = _Harness(<_Reply>[_Reply.json(_config(7))]);
      expect(await h.boot(), const UpdateGateState.ok());
    });

    test('build > min → ok', () async {
      final _Harness h = _Harness(<_Reply>[_Reply.json(_config(0))]);
      expect(await h.boot(), const UpdateGateState.ok());
    });

    test('unparsable build + any min → ok', () async {
      final _Harness h = _Harness(<_Reply>[
        _Reply.json(_config(99)),
      ], build: 'dev');
      expect(await h.boot(), const UpdateGateState.ok());
    });
  });

  group('fail-open on every error class (D2)', () {
    final Map<String, _Reply> errors = <String, _Reply>{
      'receive timeout': const _Reply.error(DioExceptionType.receiveTimeout),
      'connect timeout': const _Reply.error(DioExceptionType.connectionTimeout),
      'no network': const _Reply.error(DioExceptionType.connectionError),
      '404 (backend without 437)': const _Reply.json(<String, Object?>{
        'success': false,
      }, status: 404),
      '429': const _Reply.json(<String, Object?>{
        'success': false,
      }, status: 429),
      '500': const _Reply.json(<String, Object?>{
        'success': false,
      }, status: 500),
      '503': const _Reply.json(<String, Object?>{
        'success': false,
      }, status: 503),
      'malformed JSON': const _Reply.raw('{not json'),
      'wrong shape': const _Reply.json(<String, Object?>{
        'success': true,
        'data': <String, Object?>{
          'android': <String, Object?>{'minVersionCode': 'lots'},
        },
      }),
      // `android` is a required field of the generated model, so `data: {}`
      // fails DECODE (the catch path), not the `android == null` branch.
      'required android missing → decode failure → fail-open':
          const _Reply.json(<String, Object?>{
            'success': true,
            'data': <String, Object?>{},
          }),
      'null data': const _Reply.json(<String, Object?>{'success': true}),
    };
    for (final MapEntry<String, _Reply> e in errors.entries) {
      test(e.key, () async {
        final _Harness h = _Harness(<_Reply>[e.value]);
        expect(await h.boot(), const UpdateGateState.ok());
        expect(h.adapter.calls, 1);
      });
    }

    test('PackageInfo failure → ok', () async {
      final _Harness h = _Harness(<_Reply>[
        _Reply.json(_config(99)),
      ], infoThrows: true);
      expect(await h.boot(), const UpdateGateState.ok());
    });

    test('a failed RE-check KEEPS the last successful "required" verdict '
        '(offline + background > 1 h cannot lift the gate)', () async {
      final _Harness h = _Harness(<_Reply>[
        _Reply.json(_config(8)),
        const _Reply.error(DioExceptionType.connectionError),
      ]);
      expect(await h.boot(), isA<UpdateGateRequired>());
      h.now = h.now.add(const Duration(hours: 2));
      await _resume();
      expect(h.adapter.calls, 2, reason: 'the re-check really ran');
      expect(h.state, isA<UpdateGateRequired>());
    });

    test('a 5xx / null-android RE-check also keeps the last verdict', () async {
      final _Harness h = _Harness(<_Reply>[
        _Reply.json(_config(8)),
        const _Reply.json(<String, Object?>{'success': false}, status: 503),
        const _Reply.json(<String, Object?>{
          'success': true,
          'data': <String, Object?>{'android': null},
        }),
      ]);
      expect(await h.boot(), isA<UpdateGateRequired>());
      h.now = h.now.add(const Duration(hours: 2));
      await _resume();
      expect(h.state, isA<UpdateGateRequired>());
      h.now = h.now.add(const Duration(hours: 2));
      await _resume();
      expect(h.adapter.calls, 3);
      expect(h.state, isA<UpdateGateRequired>());
    });

    test('a successful RE-check still lifts the gate (min lowered)', () async {
      final _Harness h = _Harness(<_Reply>[
        _Reply.json(_config(8)),
        _Reply.json(_config(7)),
      ]);
      expect(await h.boot(), isA<UpdateGateRequired>());
      h.now = h.now.add(const Duration(hours: 2));
      await _resume();
      expect(h.state, const UpdateGateState.ok());
    });
  });

  group('resume throttle (D3)', () {
    test('inside 1 h of the last success → no re-check', () async {
      final _Harness h = _Harness(<_Reply>[
        _Reply.json(_config(0)),
        _Reply.json(_config(99)),
      ]);
      await h.boot();
      h.now = h.now.add(const Duration(minutes: 59));
      await _resume();
      expect(h.adapter.calls, 1);
      expect(h.state, const UpdateGateState.ok());
    });

    test(
      'after 1 h → re-checks; a raised min blocks the running app',
      () async {
        final _Harness h = _Harness(<_Reply>[
          _Reply.json(_config(0)),
          _Reply.json(_config(8)),
        ]);
        await h.boot();
        h.now = h.now.add(const Duration(hours: 1));
        await _resume();
        expect(h.adapter.calls, 2);
        expect(h.state, isA<UpdateGateRequired>());
      },
    );

    test('the throttle counts from the last SUCCESS: a failed cold start '
        're-checks on the very next resume, which supersedes the pending '
        'retry', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness(<_Reply>[
          const _Reply.error(DioExceptionType.connectionError),
          _Reply.json(_config(8)),
        ]);
        h.container.listen(updateGateProvider, (_, _) {});
        _settle(async);
        expect(h.state, const UpdateGateState.ok());
        async.elapse(const Duration(seconds: 1));
        h.now = h.now.add(const Duration(seconds: 1));
        _dispatchResume();
        _settle(async);
        expect(h.adapter.calls, 2);
        expect(h.state, isA<UpdateGateRequired>());
        async.elapse(const Duration(minutes: 5));
        expect(h.adapter.calls, 2, reason: 'retry cancelled by the success');
      });
    });

    test('concurrent checks share one request', () async {
      final _Harness h = _Harness(<_Reply>[_Reply.json(_config(0))]);
      h.container.listen(updateGateProvider, (_, _) {});
      final UpdateGate gate = h.container.read(updateGateProvider.notifier);
      await Future.wait(<Future<void>>[gate.check(), gate.check()]);
      await pumpEventQueue();
      expect(h.adapter.calls, 1);
    });
  });

  group('cold-start retry backoff (3 s / 10 s / 30 s, cap 3)', () {
    test('a timed-out cold start retries after 3 s with NO resume: the gate '
        'blocks build 8 against min 9', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness(<_Reply>[
          _timeout,
          _Reply.json(_config(9)),
        ], build: '8');
        h.container.listen(updateGateProvider, (_, _) {});
        _settle(async);
        expect(h.adapter.calls, 1);
        expect(h.state, const UpdateGateState.ok(), reason: 'fail-open');
        async.elapse(const Duration(milliseconds: 2999));
        expect(h.adapter.calls, 1);
        async.elapse(const Duration(milliseconds: 1));
        _settle(async);
        expect(h.adapter.calls, 2);
        expect(h.state, isA<UpdateGateRequired>());
      });
    });

    test('retries follow 3 s, 10 s, 30 s and stop at the cap of 3', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness(<_Reply>[_timeout]);
        h.container.listen(updateGateProvider, (_, _) {});
        _settle(async);
        expect(h.adapter.calls, 1);
        async.elapse(const Duration(seconds: 3));
        expect(h.adapter.calls, 2);
        async.elapse(const Duration(milliseconds: 9999));
        expect(h.adapter.calls, 2);
        async.elapse(const Duration(milliseconds: 1));
        expect(h.adapter.calls, 3);
        async.elapse(const Duration(milliseconds: 29999));
        expect(h.adapter.calls, 3);
        async.elapse(const Duration(milliseconds: 1));
        expect(h.adapter.calls, 4);
        async.elapse(const Duration(hours: 1));
        expect(h.adapter.calls, 4, reason: 'cap reached');
        expect(h.state, const UpdateGateState.ok());
      });
    });

    test('retries stop after a success (no retry once a check succeeded)', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness(<_Reply>[
          _timeout,
          _Reply.json(_config(0)),
          _Reply.json(_config(99)),
        ]);
        h.container.listen(updateGateProvider, (_, _) {});
        _settle(async);
        async.elapse(const Duration(seconds: 3));
        expect(h.adapter.calls, 2);
        async.elapse(const Duration(hours: 1));
        expect(h.adapter.calls, 2);
        expect(h.state, const UpdateGateState.ok());
      });
    });

    test('a failed RE-check after a success never schedules a retry', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness(<_Reply>[
          _Reply.json(_config(8)),
          _timeout,
        ]);
        h.container.listen(updateGateProvider, (_, _) {});
        _settle(async);
        expect(h.state, isA<UpdateGateRequired>());
        h.now = h.now.add(const Duration(hours: 2));
        _dispatchResume();
        _settle(async);
        expect(h.adapter.calls, 2);
        async.elapse(const Duration(minutes: 5));
        expect(h.adapter.calls, 2);
        expect(h.state, isA<UpdateGateRequired>(), reason: 'last verdict');
      });
    });

    test('dispose cancels the pending retry timer', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness(<_Reply>[_timeout]);
        h.container.listen(updateGateProvider, (_, _) {});
        _settle(async);
        expect(h.adapter.calls, 1);
        expect(async.nonPeriodicTimerCount, 1, reason: 'the 3 s retry');
        h.container.dispose();
        // The timer itself is cancelled — not merely defused by the
        // `ref.mounted` guard in its callback (which alone kept calls at 1).
        expect(async.nonPeriodicTimerCount, 0);
        async.elapse(const Duration(minutes: 5));
        expect(h.adapter.calls, 1);
      });
    });

    test('a resume during a pending retry fetches once; when it fails the '
        'backoff continues without a double request', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness(<_Reply>[
          _timeout,
          _timeout,
          _Reply.json(_config(8)),
        ]);
        h.container.listen(updateGateProvider, (_, _) {});
        _settle(async);
        async.elapse(const Duration(seconds: 2));
        _dispatchResume();
        _settle(async);
        expect(h.adapter.calls, 2, reason: 'resume check, retry cancelled');
        // The 3 s mark of the cancelled cold-start retry passes silently.
        async.elapse(const Duration(seconds: 2));
        expect(h.adapter.calls, 2);
        // The resume's failure scheduled the next backoff step (10 s).
        async.elapse(const Duration(seconds: 8));
        _settle(async);
        expect(h.adapter.calls, 3);
        expect(h.state, isA<UpdateGateRequired>());
        async.elapse(const Duration(hours: 1));
        expect(h.adapter.calls, 3);
      });
    });
  });

  group('Sentry breadcrumb on a failed check', () {
    late List<Breadcrumb> crumbs;

    setUp(() async {
      crumbs = <Breadcrumb>[];
      await Sentry.init((SentryOptions o) {
        o
          ..dsn = 'https://public@o1.ingest.de.sentry.io/2'
          ..transport = _NoopTransport()
          ..beforeBreadcrumb = (Breadcrumb? b, Hint _) {
            if (b != null && b.category == 'update_gate') crumbs.add(b);
            return b;
          };
      });
    });
    tearDown(Sentry.close);

    test('a timed-out check leaves one update_gate breadcrumb carrying the '
        'error types only', () async {
      final _Harness h = _Harness(<_Reply>[_timeout]);

      await h.boot();

      expect(crumbs, hasLength(1));
      expect(crumbs.single.level, SentryLevel.warning);
      expect(crumbs.single.data, <String, dynamic>{
        'error_type': 'DioException',
        'dio_type': 'connectionTimeout',
      });
    });

    test('a successful check leaves no update_gate breadcrumb', () async {
      final _Harness h = _Harness(<_Reply>[_Reply.json(_config(0))]);

      await h.boot();

      expect(crumbs, isEmpty);
    });
  });

  group('parseBuildNumber — the D1 key', () {
    test(
      'plain decimal (incl. surrounding whitespace, leading zeros) parses',
      () {
        expect(parseBuildNumber('7'), 7);
        expect(parseBuildNumber(' 7 '), 7);
        expect(parseBuildNumber('007'), 7);
        expect(parseBuildNumber('0'), 0);
      },
    );
    test('negative, fractional, empty, text and int-overflow → null', () {
      for (final String raw in <String>[
        '',
        '   ',
        '-1',
        '1.5',
        '7a',
        '1.5.0+7',
        '99999999999999999999999',
      ]) {
        expect(parseBuildNumber(raw), isNull, reason: 'build "$raw"');
      }
    });
    test('an overflowing build number never blocks, even at the int max', () {
      expect(
        isUpdateRequired(
          buildNumber: '99999999999999999999999',
          minVersionCode: 0x7fffffffffffffff,
        ),
        isFalse,
      );
    });
    test('build 0: blocked by min 1, not by min 0', () {
      expect(isUpdateRequired(buildNumber: '0', minVersionCode: 1), isTrue);
      expect(isUpdateRequired(buildNumber: '0', minVersionCode: 0), isFalse);
    });
  });

  group('latestVersionCode is fetched but IGNORED (soft prompt is out)', () {
    test('build == min, latest far above → ok', () async {
      final _Harness h = _Harness(<_Reply>[
        _Reply.json(_config(7, latest: 99)),
      ]);
      expect(await h.boot(), const UpdateGateState.ok());
      expect(h.adapter.calls, 1);
    });
    test(
      'build < min, latest == build → still required (min decides)',
      () async {
        final _Harness h = _Harness(<_Reply>[
          _Reply.json(_config(8, latest: 7)),
        ]);
        expect(await h.boot(), isA<UpdateGateRequired>());
      },
    );
  });

  group('fail-open — more error classes (D2)', () {
    final Map<String, _Reply> errors = <String, _Reply>{
      '401': const _Reply.json(<String, Object?>{
        'success': false,
      }, status: 401),
      '403': const _Reply.json(<String, Object?>{
        'success': false,
      }, status: 403),
      'send timeout': const _Reply.error(DioExceptionType.sendTimeout),
      'bad certificate (pin mismatch)': const _Reply.error(
        DioExceptionType.badCertificate,
      ),
      'cancelled': const _Reply.error(DioExceptionType.cancel),
      'unknown transport error': const _Reply.error(DioExceptionType.unknown),
      'captive-portal HTML with 200': const _Reply.raw(
        '<html><body>Login to Wi-Fi</body></html>',
      ),
      'empty body': const _Reply.raw(''),
      'success:false with 200 and no data': const _Reply.json(<String, Object?>{
        'success': false,
      }),
      'android without minVersionCode': const _Reply.json(<String, Object?>{
        'success': true,
        'data': <String, Object?>{
          'android': <String, Object?>{
            'latestVersionCode': 99,
            'storeUrl': 'https://play.google.com/x',
          },
        },
      }),
      'android without storeUrl': const _Reply.json(<String, Object?>{
        'success': true,
        'data': <String, Object?>{
          'android': <String, Object?>{
            'minVersionCode': 99,
            'latestVersionCode': 99,
          },
        },
      }),
      'android is null': const _Reply.json(<String, Object?>{
        'success': true,
        'data': <String, Object?>{'android': null},
      }),
      'top-level JSON array': const _Reply.raw('[1,2,3]'),
    };
    for (final MapEntry<String, _Reply> e in errors.entries) {
      test(e.key, () async {
        final _Harness h = _Harness(<_Reply>[e.value]);
        expect(await h.boot(), const UpdateGateState.ok());
        expect(h.adapter.calls, 1);
      });
    }

    test('a 200 with a null data envelope (no android config) is not a '
        'success: the next resume re-checks at once', () async {
      final _Harness h = _Harness(<_Reply>[
        const _Reply.json(<String, Object?>{'success': true}),
        _Reply.json(_config(8)),
      ]);
      expect(await h.boot(), const UpdateGateState.ok());
      h.now = h.now.add(const Duration(minutes: 1));
      await _resume();
      expect(h.adapter.calls, 2);
      expect(h.state, isA<UpdateGateRequired>());
    });
  });

  group('resume throttle — boundaries (D3)', () {
    test('1 h minus 1 ms → no re-check; exactly 1 h → re-check', () async {
      final _Harness h = _Harness(<_Reply>[
        _Reply.json(_config(0)),
        _Reply.json(_config(0)),
      ]);
      await h.boot();
      final DateTime t0 = h.now;
      h.now = t0.add(
        kUpdateGateRecheckInterval - const Duration(milliseconds: 1),
      );
      await _resume();
      expect(h.adapter.calls, 1);
      h.now = t0.add(kUpdateGateRecheckInterval);
      await _resume();
      expect(h.adapter.calls, 2);
    });

    test('a wall clock moved BACKWARDS (negative elapsed) counts as stale: '
        'the resume re-checks', () async {
      final _Harness h = _Harness(<_Reply>[
        _Reply.json(_config(0)),
        _Reply.json(_config(8)),
      ]);
      await h.boot();
      h.now = h.now.subtract(const Duration(days: 1));
      await _resume();
      expect(h.adapter.calls, 2);
      expect(h.state, isA<UpdateGateRequired>());
    });

    test('the window restarts at each SUCCESS: a resume 30 min after a '
        'successful re-check does not check again', () async {
      final _Harness h = _Harness(<_Reply>[
        _Reply.json(_config(0)),
        _Reply.json(_config(0)),
        _Reply.json(_config(0)),
      ]);
      await h.boot();
      h.now = h.now.add(const Duration(hours: 2));
      await _resume();
      expect(h.adapter.calls, 2);
      h.now = h.now.add(const Duration(minutes: 30));
      await _resume();
      expect(h.adapter.calls, 2);
    });

    test('a FAILED re-check does not restart the window: the next resume '
        'checks again', () async {
      final _Harness h = _Harness(<_Reply>[
        _Reply.json(_config(0)),
        const _Reply.error(DioExceptionType.connectionError),
        _Reply.json(_config(0)),
      ]);
      await h.boot();
      h.now = h.now.add(const Duration(hours: 2));
      await _resume();
      expect(h.adapter.calls, 2);
      h.now = h.now.add(const Duration(minutes: 1));
      await _resume();
      expect(h.adapter.calls, 3);
    });

    test(
      'only a RESUME triggers a re-check (inactive / paused do not)',
      () async {
        final _Harness h = _Harness(<_Reply>[_Reply.json(_config(0))]);
        await h.boot();
        h.now = h.now.add(const Duration(hours: 2));
        final TestWidgetsFlutterBinding binding =
            TestWidgetsFlutterBinding.instance;
        for (final AppLifecycleState s in <AppLifecycleState>[
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
        ]) {
          binding.handleAppLifecycleStateChanged(s);
        }
        await pumpEventQueue();
        expect(h.adapter.calls, 1);
      },
    );
  });

  group('concurrent-check dedupe and lifecycle', () {
    test('a resume while the cold-start check is in flight shares the one '
        'request', () async {
      final _Harness h = _Harness(<_Reply>[_Reply.json(_config(8))]);
      final Completer<void> hold = Completer<void>();
      h.adapter.hold = hold;
      h.container.listen(updateGateProvider, (_, _) {});
      await pumpEventQueue();
      expect(h.adapter.calls, 1, reason: 'cold start is in flight');

      await _resume();
      unawaited(h.container.read(updateGateProvider.notifier).check());
      await pumpEventQueue();
      expect(h.adapter.calls, 1);

      hold.complete();
      await pumpEventQueue();
      expect(h.state, isA<UpdateGateRequired>());
    });

    test(
      'after a check completes, the next one issues a NEW request',
      () async {
        final _Harness h = _Harness(<_Reply>[
          _Reply.json(_config(0)),
          _Reply.json(_config(8)),
        ]);
        await h.boot();
        await h.container.read(updateGateProvider.notifier).check();
        expect(h.adapter.calls, 2);
        expect(h.state, isA<UpdateGateRequired>());
      },
    );

    test(
      'disposed mid-flight: the late reply is dropped without throwing',
      () async {
        final _Harness h = _Harness(<_Reply>[_Reply.json(_config(8))]);
        final Completer<void> hold = Completer<void>();
        h.adapter.hold = hold;
        h.container.listen(updateGateProvider, (_, _) {});
        await pumpEventQueue();
        final Future<void> pending = h.container
            .read(updateGateProvider.notifier)
            .check();

        h.container.dispose();
        hold.complete();

        await expectLater(pending, completes);
      },
    );

    test('after dispose the lifecycle listener is gone: a resume issues no '
        'request', () async {
      final _Harness h = _Harness(<_Reply>[_Reply.json(_config(0))]);
      await h.boot();
      h.container.dispose();
      h.now = h.now.add(const Duration(hours: 2));

      await _resume();

      expect(h.adapter.calls, 1);
    });
  });
}
