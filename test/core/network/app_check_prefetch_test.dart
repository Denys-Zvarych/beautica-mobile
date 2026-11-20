// Phone-first hardening (AUTH-D27 d, perf P2) — the single-use App Check
// prefetch slot: a prefetched limited-use token goes to ONE send, the next
// send fetches fresh; a stale or empty prefetch falls back to on demand; no
// prefetch while Firebase is not up. The last group pins the PRODUCTION
// `dioProvider` wiring: its AppCheckInterceptor takes from the prefetch slot
// (the E2E tier cannot see it — FakeBackend installs its own interceptor).

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:beautica_mobile/core/config/app_check_config.dart';
import 'package:beautica_mobile/core/network/app_check_prefetch.dart';
import 'package:beautica_mobile/core/network/dio_provider.dart';
import 'package:beautica_mobile/core/network/refresh_dio_provider.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes/fake_auth_repository.dart';
import '../../helpers/fakes/fake_secure_storage.dart';

/// Answers 200 to everything and records each request's App Check header.
final class _HeaderAdapter implements HttpClientAdapter {
  final List<({String path, String? header})> seen =
      <({String path, String? header})>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seen.add((
      path: options.path,
      header: options.headers[kAppCheckHeader] as String?,
    ));
    return ResponseBody.fromString(
      jsonEncode(<String, dynamic>{'success': true, 'data': null}),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

final class _Fetcher {
  int calls = 0;
  final List<String?> results = <String?>[];

  Future<String?> call() async {
    calls++;
    return results.isEmpty ? 'tok-$calls' : results.removeAt(0);
  }
}

void main() {
  late _Fetcher fetcher;
  late DateTime now;
  late bool ready;

  AppCheckTokenPrefetcher build() => AppCheckTokenPrefetcher(
    fetch: fetcher.call,
    canPrefetch: () => ready,
    clock: () => now,
  );

  setUp(() {
    fetcher = _Fetcher();
    now = DateTime.utc(2026, 11, 19, 10);
    ready = true;
  });

  test(
    'the prefetched token is used once, then a fresh one is fetched',
    () async {
      final AppCheckTokenPrefetcher p = build()..prefetch();
      expect(fetcher.calls, 1, reason: 'prefetch starts the fetch at once');

      expect(await p.take(), 'tok-1');
      expect(fetcher.calls, 1, reason: 'the send used the prefetched token');

      expect(await p.take(), 'tok-2', reason: 'never reused across sends');
      expect(fetcher.calls, 2);
    },
  );

  test('a second prefetch while one is fresh starts nothing', () async {
    final AppCheckTokenPrefetcher p = build()
      ..prefetch()
      ..prefetch();
    expect(fetcher.calls, 1);
    expect(await p.take(), 'tok-1');
  });

  test('no prefetch → take fetches on demand', () async {
    final AppCheckTokenPrefetcher p = build();
    expect(await p.take(), 'tok-1');
    expect(fetcher.calls, 1);
  });

  test(
    'a prefetch older than the max age is dropped for a fresh fetch',
    () async {
      final AppCheckTokenPrefetcher p = build()..prefetch();
      now = now.add(kAppCheckPrefetchMaxAge);
      expect(await p.take(), 'tok-2');
      expect(fetcher.calls, 2);
      expect(await p.take(), 'tok-3', reason: 'the stale slot was emptied too');
    },
  );

  // Audit cycle 2 — an IN-FLIGHT prefetch's result is final: a null after it
  // spent its capped budget goes out as null (no second ~5 s fetch).
  test(
    'in-flight prefetch that returns null → null, no second fetch',
    () async {
      fetcher.results.addAll(<String?>[null, 'never-used']);
      final AppCheckTokenPrefetcher p = build()..prefetch();
      expect(await p.take(), isNull);
      expect(fetcher.calls, 1);
    },
  );

  test('an already-FAILED prefetch falls back to a fresh fetch', () async {
    fetcher.results.addAll(<String?>[null, 'late-tok']);
    final AppCheckTokenPrefetcher p = build()..prefetch();
    await pumpEventQueue(); // the prefetch completes (with no token)
    expect(await p.take(), 'late-tok');
    expect(fetcher.calls, 2);
  });

  test('an already-DONE prefetch token is used without a new fetch', () async {
    final AppCheckTokenPrefetcher p = build()..prefetch();
    await pumpEventQueue();
    expect(await p.take(), 'tok-1');
    expect(fetcher.calls, 1);
  });

  test('a pending prefetch is awaited, not duplicated', () async {
    final Completer<String?> slow = Completer<String?>();
    int calls = 0;
    final AppCheckTokenPrefetcher p = AppCheckTokenPrefetcher(
      fetch: () {
        calls++;
        return calls == 1 ? slow.future : Future<String?>.value('next');
      },
      canPrefetch: () => true,
      clock: () => now,
    )..prefetch();

    final Future<String?> taken = p.take();
    slow.complete('prefetched');
    expect(await taken, 'prefetched');
    expect(calls, 1);
  });

  test('Firebase not up → prefetch is a no-op (nothing to wait on)', () async {
    ready = false;
    final AppCheckTokenPrefetcher p = build()..prefetch();
    expect(fetcher.calls, 0);
    expect(await p.take(), 'tok-1');
  });

  test(
    'a throwing prefetch never escapes; once failed, take refetches',
    () async {
      int calls = 0;
      final AppCheckTokenPrefetcher p = AppCheckTokenPrefetcher(
        fetch: () async {
          calls++;
          if (calls == 1) throw StateError('sdk');
          return 'ok';
        },
        canPrefetch: () => true,
        clock: () => now,
      )..prefetch();
      await pumpEventQueue();
      expect(await p.take(), 'ok');
      expect(calls, 2);
    },
  );

  group('dioProvider wiring', () {
    test('the SMS send takes the prefetched token once; the next send '
        'fetches fresh; a non-App-Check path never consumes it', () async {
      final AppCheckTokenPrefetcher p = build();
      final ProviderContainer container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
          authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
          refreshDioProvider.overrideWith((_) => Dio()),
          appCheckTokenPrefetcherProvider.overrideWithValue(p),
        ],
      );
      addTearDown(container.dispose);
      final _HeaderAdapter adapter = _HeaderAdapter();
      final Dio dio = container.read(dioProvider)..httpClientAdapter = adapter;
      const String send = '/api/v1/auth/register/phone/otp/send';

      p.prefetch();
      await pumpEventQueue();
      expect(fetcher.calls, 1, reason: 'precondition: prefetched');

      await dio.post<dynamic>('/api/v1/auth/register/phone/otp/verify');
      await dio.post<dynamic>(send);
      await dio.post<dynamic>(send);

      expect(adapter.seen.map((r) => r.header), <String?>[
        null,
        'tok-1',
        'tok-2',
      ]);
      expect(fetcher.calls, 2, reason: 'one prefetch + one on-demand fetch');
    });
  });
}
