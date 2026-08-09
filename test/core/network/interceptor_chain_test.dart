// CHAIN-LEVEL regression tests for the Dio interceptor chain (2026-08-07).
//
// WHY THIS TIER EXISTS
// --------------------
// `refresh_interceptor_test.dart` calls `RefreshInterceptor.onError(...)`
// DIRECTLY. That proves the interceptor's internal branching, but it can never
// prove the interceptor is REACHED — it hand-delivers the error the chain was
// supposed to deliver. The shipped defect was exactly that gap:
// `ErrorMapperInterceptor` ends the error flow with `handler.reject(...)`
// (`error_mapper_interceptor.dart:50`), which sets `InterceptorResultType
// .reject`; dio's `errorInterceptorWrapper` (`dio_mixin.dart` ~:453-460)
// forwards to the NEXT error interceptor only for `next` /
// `rejectCallFollowing`. With the mapper positioned first, `RefreshInterceptor
// .onError` was unreachable for EVERY endpoint in the app — silent 401 refresh
// and logout-on-refresh-failure were both dead code — and 127 green tests in
// `test/core/network/` said nothing about it.
//
// So these tests wire the REAL `dioProvider` (production interceptor list,
// production order) to a scripted `HttpClientAdapter` and drive it through the
// public `Dio` API. Nothing here constructs an interceptor by hand: a mutation
// to the `d.interceptors.addAll([...])` order in `dio_provider.dart` is what
// these tests are designed to catch, so they must read that list, not a copy.
//
// MUTATION-PROVEN (2026-08-07, measured — see the QA report):
//   • swap RefreshInterceptor/ErrorMapperInterceptor back  -> 4 RED
//   • delete the kAuthPaths / kPublicPathPrefixes guard    -> 3 RED
//   • re-widen the logout catch to cover the replay        -> 1 RED
//   • restore setAccessToken's AsyncLoading no-op          -> 3 RED
//   • drop the coldStartAccessToken in-place update        -> 3 RED
//   • plant coldStartAccessToken unconditionally           -> 1 RED
// The last three are the cold-start group below. NONE of the 138 + 491
// pre-existing tests in `test/core/network/` + `test/features/auth/` noticed
// any of them — the second measured instance of this blind spot.
//
// TRANSPORT-LEVEL COUNTING IS DELIBERATE. `Dio.fetch` rebuilds the FULL request
// flow, so a replay re-enters the whole chain. Asserting only on the final
// state cannot distinguish "refreshed and replayed once" from "never refreshed"
// when both end in the same `Failure`. Every test therefore pins
// `transportCalls`, and the scripted adapter throws on an unscripted call so an
// extra round-trip can never pass silently.
//
// TOKEN VALUES ARE TEXTUALLY DISTINCT ON PURPOSE. The cold-start session
// settles on `stale-access`; the interceptor's refresh returns `new-access`.
// Asserting the Authorization header CHANGED between attempt 1 and attempt 2 is
// what makes the replay assertion load-bearing — a shared fixture value would
// let a chain that never re-attached the token pass.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/dio_provider.dart';
import 'package:beautica_mobile/core/network/error_mapper_interceptor.dart';
import 'package:beautica_mobile/core/network/refresh_dio_provider.dart';
import 'package:beautica_mobile/core/network/refresh_interceptor.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/auth_tokens.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/fakes/fake_auth_repository.dart';
import '../../helpers/fakes/fake_secure_storage.dart';

// ---------------------------------------------------------------------------
// Constants — an authenticated route that is in NEITHER kAuthPaths nor
// kPublicPathPrefixes, so the 401-refresh path is genuinely in scope for it.
// ---------------------------------------------------------------------------

const String kProtectedPath = '/api/v1/independent-masters/me';
const String kLoginPath = '/api/v1/auth/login';
const String kRefreshPath = '/api/v1/auth/refresh';
const String kPublicLocationsPath = '/api/v1/locations/oblasts';

const String kStaleAccess = 'stale-access';
const String kNewAccess = 'new-access';

// ---------------------------------------------------------------------------
// Mocks / fakes
// ---------------------------------------------------------------------------

class _MockDio extends Mock implements Dio {}

/// A single canned HTTP reply for the scripted transport.
final class _Reply {
  const _Reply(this.status, [this.body]);

  final int status;
  final Map<String, dynamic>? body;
}

/// Case-insensitive header lookup.
///
/// Dio normalises header key casing in some code paths and not others; reading
/// `headers['Authorization']` directly would make these assertions depend on
/// that detail rather than on the interceptor behaviour under test.
String? _header(RequestOptions options, String name) {
  final String wanted = name.toLowerCase();
  for (final MapEntry<String, dynamic> e in options.headers.entries) {
    if (e.key.toLowerCase() == wanted) return e.value?.toString();
  }
  return null;
}

/// [HttpClientAdapter] that replays a fixed script of HTTP replies and records
/// what the chain actually put on the wire.
///
/// Throws a [StateError] when called more times than the script allows, so an
/// unexpected extra round-trip (a retry loop, a duplicate replay) fails loudly
/// instead of silently reusing the last reply.
final class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this._script, {this.responder});

  final List<_Reply> _script;

  /// Optional TOKEN-AWARE mode. When set, the reply is computed from the
  /// request instead of read off [_script] — which is what lets a test model a
  /// real server that actually validates the Bearer it is handed, rather than
  /// one that returns 200 to anything. Without this, a replay carrying a stale
  /// token still gets a 200 from the fixture and the "session survives"
  /// assertion passes for the wrong reason (measured: it stayed GREEN under the
  /// stale-bearer mutation until this mode was added).
  final _Reply Function(RequestOptions options)? responder;

  /// `RequestOptions.path` of every request that reached the transport.
  final List<String> paths = <String>[];

  /// `Authorization` header value per attempt, snapshotted at transport time.
  final List<String?> authHeaders = <String?>[];

  /// `X-No-Retry` header value per attempt, snapshotted at transport time.
  final List<String?> noRetryHeaders = <String?>[];

  int get calls => paths.length;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final int index = calls;
    paths.add(options.path);
    // Snapshot the STRING value now. RefreshInterceptor mutates the same
    // RequestOptions.headers map in place before the replay, so holding the map
    // would collapse both attempts onto the post-refresh value.
    authHeaders.add(_header(options, 'authorization'));
    noRetryHeaders.add(_header(options, 'x-no-retry'));

    final _Reply reply;
    if (responder != null) {
      reply = responder!(options);
    } else {
      if (index >= _script.length) {
        throw StateError(
          'Transport called ${index + 1} times but the script has only '
          '${_script.length} replies. paths=$paths',
        );
      }
      reply = _script[index];
    }
    return ResponseBody.fromString(
      jsonEncode(reply.body ?? const <String, dynamic>{}),
      reply.status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

/// Retry policy pinned to "never".
///
/// Deliberate per the repo trap: `beauticaProviderRetry` treats a 5xx
/// [ServerFailure] as transient, so a provider that errors can park in
/// `AsyncLoading(retrying: true)` and re-issue work behind the test's back —
/// which would make `transportCalls` non-deterministic. No provider in this
/// harness is expected to error, so pinning to no-retry costs nothing and
/// removes the whole class of flake.
Duration? _noRetry(int retryCount, Object error) => null;

final class _Chain {
  _Chain({
    required this.container,
    required this.dio,
    required this.adapter,
    required this.storage,
    required this.repo,
    required this.refreshDio,
  });

  final ProviderContainer container;
  final Dio dio;
  final _ScriptedAdapter adapter;
  final FakeSecureStorage storage;
  final FakeAuthRepository repo;
  final _MockDio refreshDio;

  int get transportCalls => adapter.calls;

  int get logoutCalls => repo.logoutCallCount;

  /// Number of `POST /auth/refresh` round-trips the interceptor issued.
  ///
  /// mocktail's `verify(...).callCount` FAILS (rather than returning 0) when
  /// there are no matching calls, so the zero case has its own assertion —
  /// [expectNoRefresh] — per the repo's `verifyNever` convention.
  int get refreshCalls => verify(
    () => refreshDio.post<Map<String, dynamic>>(
      kRefreshPath,
      data: any(named: 'data'),
    ),
  ).callCount;

  /// Asserts the interceptor never attempted a silent token refresh.
  void expectNoRefresh() => verifyNever(
    () => refreshDio.post<Map<String, dynamic>>(
      kRefreshPath,
      data: any(named: 'data'),
    ),
  );
}

/// Boots the REAL production Dio (via [dioProvider]) over a scripted transport,
/// with an already-settled `Authenticated` session holding [kStaleAccess].
Future<_Chain> _bootAuthenticated(List<_Reply> script) async {
  final FakeSecureStorage storage = FakeSecureStorage();
  await storage.writeRefreshToken('stored-refresh');

  final FakeAuthRepository repo = FakeAuthRepository()
    ..refreshResult = const AuthTokens(
      accessToken: kStaleAccess,
      refreshToken: 'stored-refresh',
    );

  final _MockDio refreshDio = _MockDio();

  final ProviderContainer container = ProviderContainer(
    retry: _noRetry,
    overrides: [
      secureStorageProvider.overrideWith((_) => storage),
      authRepositoryProvider.overrideWith((_) => repo),
      // RefreshInterceptor issues POST /auth/refresh on this interceptor-free
      // Dio. Mocking it keeps the refresh round-trip off the scripted transport
      // so `transportCalls` counts ONLY the app's own request + its replay.
      refreshDioProvider.overrideWith((_) => refreshDio),
    ],
  );
  addTearDown(container.dispose);

  // The production interceptor list, in production order. Not a reconstruction.
  final Dio dio = container.read(dioProvider);
  final _ScriptedAdapter adapter = _ScriptedAdapter(script);
  dio.httpClientAdapter = adapter;

  final AuthSession session = await container.read(authProvider.future);
  expect(
    session,
    isA<Authenticated>(),
    reason: 'harness precondition: the chain must run under a live session',
  );

  return _Chain(
    container: container,
    dio: dio,
    adapter: adapter,
    storage: storage,
    repo: repo,
    refreshDio: refreshDio,
  );
}

/// A [_Chain] whose `authProvider` is deliberately PARKED in [AsyncLoading],
/// mid-`build()`, with the cold-start sentinel populated.
final class _ColdStartChain {
  _ColdStartChain({
    required this.chain,
    required this.meGate,
    required this.sessionFuture,
  });

  final _Chain chain;

  /// Completing this releases `repo.me()` and lets cold-start `build()` settle.
  final Completer<void> meGate;

  /// The in-flight `authProvider.future`. Deliberately NOT awaited while the
  /// window is open — awaiting it is what closes the window.
  final Future<AuthSession> sessionFuture;

  AuthNotifier get notifier => chain.container.read(authProvider.notifier);
}

/// Boots the REAL production Dio over a scripted transport with `authProvider`
/// held OPEN in its cold-start window: `build()` has rotated the refresh token
/// (so `coldStartAccessToken == kStaleAccess`) and is parked awaiting
/// `repo.me()`, which never returns until [_ColdStartChain.meGate] completes.
///
/// This is the window the shipped MEDIUM lived in: `state.value` is `null`, so
/// [AuthInterceptor] derives every Bearer header from `lastKnownAccessToken` —
/// which resolves through `coldStartAccessToken` FIRST.
Future<_ColdStartChain> _bootColdStartWindow(
  List<_Reply> script, {
  _Reply Function(RequestOptions options)? responder,
}) async {
  final FakeSecureStorage storage = FakeSecureStorage();
  await storage.writeRefreshToken('stored-refresh');

  final Completer<void> meGate = Completer<void>();
  final FakeAuthRepository repo = FakeAuthRepository()
    ..refreshResult = const AuthTokens(
      accessToken: kStaleAccess,
      refreshToken: 'stored-refresh',
    )
    ..meDelay = meGate.future;

  final _MockDio refreshDio = _MockDio();

  final ProviderContainer container = ProviderContainer(
    retry: _noRetry,
    overrides: [
      secureStorageProvider.overrideWith((_) => storage),
      authRepositoryProvider.overrideWith((_) => repo),
      refreshDioProvider.overrideWith((_) => refreshDio),
    ],
  );
  addTearDown(() {
    // Release the gate before disposing so the parked build() cannot outlive
    // the container and surface as an unhandled async error.
    if (!meGate.isCompleted) meGate.complete();
    container.dispose();
  });

  final Dio dio = container.read(dioProvider);
  final _ScriptedAdapter adapter = _ScriptedAdapter(
    script,
    responder: responder,
  );
  dio.httpClientAdapter = adapter;

  // Start build() WITHOUT awaiting it, then drain the event queue so build()
  // gets past storage.readRefreshToken + repo.refresh + storage.write and
  // parks inside repo.me(). ignore() suppresses the "unhandled future error"
  // bookkeeping for the window in which nothing is listening yet.
  final Future<AuthSession> sessionFuture = container.read(authProvider.future);
  sessionFuture.ignore();
  await pumpEventQueue();

  // Harness precondition — assert the window is GENUINELY open. Without this
  // the test could silently drift onto the settled path (where the fix is not
  // exercised at all) and keep passing for the wrong reason.
  expect(
    repo.meCallCount,
    1,
    reason: 'build() must be parked inside repo.me()',
  );
  final AsyncValue<AuthSession> state = container.read(authProvider);
  expect(
    state.isLoading,
    isTrue,
    reason: 'harness precondition: authProvider must still be AsyncLoading',
  );
  expect(
    state.value,
    isNull,
    reason:
        'harness precondition: an AsyncData here means the cold-start window '
        'already closed and this test no longer covers the regression',
  );
  expect(
    container.read(authProvider.notifier).coldStartAccessToken,
    kStaleAccess,
    reason: 'the stale sentinel is what used to shadow the refreshed token',
  );

  return _ColdStartChain(
    chain: _Chain(
      container: container,
      dio: dio,
      adapter: adapter,
      storage: storage,
      repo: repo,
      refreshDio: refreshDio,
    ),
    meGate: meGate,
    sessionFuture: sessionFuture,
  );
}

void _stubRefreshSucceeds(_MockDio refreshDio) {
  when(
    () => refreshDio.post<Map<String, dynamic>>(
      kRefreshPath,
      data: any(named: 'data'),
    ),
  ).thenAnswer(
    (_) async => Response<Map<String, dynamic>>(
      requestOptions: RequestOptions(path: kRefreshPath),
      statusCode: 200,
      data: <String, dynamic>{
        'data': <String, dynamic>{
          'accessToken': kNewAccess,
          'refreshToken': 'new-refresh',
        },
      },
    ),
  );
}

void _stubRefreshFails(_MockDio refreshDio) {
  when(
    () => refreshDio.post<Map<String, dynamic>>(
      kRefreshPath,
      data: any(named: 'data'),
    ),
  ).thenAnswer(
    // ASYNC throw, not `thenThrow`. A Dio-backed refresh always fails
    // asynchronously; a synchronous throw would model a shape the transport
    // cannot produce.
    (_) async => throw DioException(
      requestOptions: RequestOptions(path: kRefreshPath),
      type: DioExceptionType.connectionError,
      message: 'Network unreachable',
    ),
  );
}

/// Runs [body], asserts it threw a [DioException] carrying a typed [Failure]
/// (i.e. [ErrorMapperInterceptor] was still reached) and returns that failure.
Future<Failure> _expectMappedFailure(Future<void> Function() body) async {
  Object? thrown;
  try {
    await body();
  } catch (e) {
    thrown = e;
  }
  expect(thrown, isA<DioException>(), reason: 'caller must see a DioException');
  final Object? error = (thrown! as DioException).error;
  expect(
    error,
    isA<Failure>(),
    reason:
        'ErrorMapperInterceptor must still run BEHIND RefreshInterceptor — a '
        'raw DioException here means the mapper was skipped',
  );
  return error! as Failure;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    registerFallbackValue(RequestOptions(path: '/'));
    registerFallbackValue(
      Response<dynamic>(requestOptions: RequestOptions(path: '/')),
    );
    registerFallbackValue(
      DioException(requestOptions: RequestOptions(path: '/')),
    );
  });

  // -------------------------------------------------------------------------
  // Structural — the ordering invariant stated in dio_provider.dart's header.
  // -------------------------------------------------------------------------
  group('dioProvider interceptor order', () {
    test(
      'RefreshInterceptor is registered BEFORE ErrorMapperInterceptor',
      () async {
        final _Chain chain = await _bootAuthenticated(<_Reply>[]);
        final List<Interceptor> list = chain.dio.interceptors.toList();

        final int refreshAt = list.indexWhere((i) => i is RefreshInterceptor);
        final int mapperAt = list.indexWhere(
          (i) => i is ErrorMapperInterceptor,
        );

        expect(refreshAt, isNonNegative, reason: 'RefreshInterceptor missing');
        expect(
          mapperAt,
          isNonNegative,
          reason: 'ErrorMapperInterceptor missing',
        );
        expect(
          refreshAt,
          lessThan(mapperAt),
          reason:
              'ErrorMapperInterceptor ends the error flow with handler.reject, '
              'so anything registered behind it is unreachable',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // 1. Reachability — the headline test. RED against the pre-fix order.
  // -------------------------------------------------------------------------
  group('401 on an authenticated endpoint', () {
    test('reaches RefreshInterceptor, refreshes, replays with the new bearer, '
        'and the caller sees the replayed success', () async {
      final _Chain chain = await _bootAuthenticated(<_Reply>[
        const _Reply(401),
        const _Reply(200, <String, dynamic>{'displayName': 'Olena'}),
      ]);
      _stubRefreshSucceeds(chain.refreshDio);

      final Response<dynamic> res = await chain.dio.get<dynamic>(
        kProtectedPath,
      );

      // Measured on the fixed chain: refreshRan=true, transportCalls=2,
      // status=200. On the broken order this was refreshRan=false,
      // transportCalls=1, and the call threw UnauthorizedFailure.
      expect(chain.refreshCalls, 1, reason: 'refresh must have run');
      expect(chain.transportCalls, 2, reason: 'original + replay');
      expect(res.statusCode, 200);
      expect((res.data as Map<String, dynamic>)['displayName'], 'Olena');

      // The replay must carry a DIFFERENT, newer bearer — not the same one
      // that just 401'd.
      expect(chain.adapter.authHeaders, <String?>[
        'Bearer $kStaleAccess',
        'Bearer $kNewAccess',
      ]);
      expect(
        chain.adapter.authHeaders[0],
        isNot(chain.adapter.authHeaders[1]),
        reason: 'the replay must not re-send the token that already failed',
      );

      // Loop guard is stamped on the replay only.
      expect(chain.adapter.noRetryHeaders, <String?>[null, 'true']);

      // A successful refresh must never touch the session.
      expect(chain.logoutCalls, 0);
    });

    test('a 401 on the replay does not loop and does not log out', () async {
      final _Chain chain = await _bootAuthenticated(<_Reply>[
        const _Reply(401),
        const _Reply(401),
      ]);
      _stubRefreshSucceeds(chain.refreshDio);

      final Failure failure = await _expectMappedFailure(
        () => chain.dio.get<dynamic>(kProtectedPath),
      );

      expect(failure, isA<UnauthorizedFailure>());
      // X-No-Retry stopped the second round: exactly two transport calls, one
      // refresh. A third call would have thrown StateError from the adapter.
      expect(chain.transportCalls, 2);
      expect(chain.refreshCalls, 1);
      // The refresh SUCCEEDED — a 401 on the replay is the resource's answer,
      // not a dead session.
      expect(chain.logoutCalls, 0);
    });
  });

  // -------------------------------------------------------------------------
  // 2. Refresh failure -> logout (and the mapper still runs behind).
  // -------------------------------------------------------------------------
  group('refresh failure', () {
    test(
      'logs out exactly once and the caller receives UnauthorizedFailure',
      () async {
        final _Chain chain = await _bootAuthenticated(<_Reply>[
          const _Reply(401),
        ]);
        _stubRefreshFails(chain.refreshDio);

        final Failure failure = await _expectMappedFailure(
          () => chain.dio.get<dynamic>(kProtectedPath),
        );

        // Measured: logoutCalls=1, thrownError=UnauthorizedFailure.
        expect(chain.logoutCalls, 1);
        expect(failure, isA<UnauthorizedFailure>());
        expect(chain.refreshCalls, 1);
        expect(
          chain.transportCalls,
          1,
          reason: 'no replay after a dead refresh',
        );
      },
    );

    test('wipes the refresh token from secure storage', () async {
      final _Chain chain = await _bootAuthenticated(<_Reply>[
        const _Reply(401),
      ]);
      _stubRefreshFails(chain.refreshDio);

      await _expectMappedFailure(() => chain.dio.get<dynamic>(kProtectedPath));

      // M5 — the whole point of the dead branch: a dead session AND its refresh
      // token must be gone.
      expect(await chain.storage.readRefreshToken(), isNull);
      expect(chain.container.read(authProvider).value, isA<Unauthenticated>());
    });
  });

  // -------------------------------------------------------------------------
  // 3. Unauthenticated endpoints must never burn a refresh or kill a session.
  // -------------------------------------------------------------------------
  group('unauthenticated endpoints', () {
    test(
      'a 401 from POST /auth/login does not refresh and does not log out',
      () async {
        final _Chain chain = await _bootAuthenticated(<_Reply>[
          const _Reply(401, <String, dynamic>{
            'success': false,
            'data': <String, dynamic>{'code': 'EMAIL_NOT_VERIFIED'},
          }),
        ]);
        _stubRefreshSucceeds(chain.refreshDio);

        final Failure failure = await _expectMappedFailure(
          () => chain.dio.post<dynamic>(
            kLoginPath,
            data: <String, dynamic>{'email': 'a@b.c', 'password': 'pw'},
          ),
        );

        // Measured: refreshRan=false, logoutCalls=0,
        // thrownError=UnauthorizedFailure.
        chain.expectNoRefresh();
        expect(chain.logoutCalls, 0);
        expect(chain.transportCalls, 1);
        expect(failure, isA<UnauthorizedFailure>());
        // The mapper's typed sub-code survives the trip past RefreshInterceptor.
        expect((failure as UnauthorizedFailure).emailNotVerified, isTrue);
        // And the live session is untouched.
        expect(chain.container.read(authProvider).value, isA<Authenticated>());
      },
    );

    test('a 401 from a kPublicPathPrefixes route does not refresh', () async {
      final _Chain chain = await _bootAuthenticated(<_Reply>[
        const _Reply(401),
      ]);
      _stubRefreshSucceeds(chain.refreshDio);

      final Failure failure = await _expectMappedFailure(
        () => chain.dio.get<dynamic>(kPublicLocationsPath),
      );

      expect(failure, isA<UnauthorizedFailure>());
      chain.expectNoRefresh();
      expect(chain.logoutCalls, 0);
      expect(chain.transportCalls, 1);
      expect(chain.container.read(authProvider).value, isA<Authenticated>());
    });

    test('a 401 from /auth/refresh itself does not re-enter refresh', () async {
      final _Chain chain = await _bootAuthenticated(<_Reply>[
        const _Reply(401),
      ]);
      _stubRefreshSucceeds(chain.refreshDio);

      final Failure failure = await _expectMappedFailure(
        () => chain.dio.post<dynamic>(
          kRefreshPath,
          data: <String, dynamic>{'refreshToken': 'stored-refresh'},
        ),
      );

      expect(failure, isA<UnauthorizedFailure>());
      // No recursion: the refresh Dio was never asked to refresh a refresh.
      chain.expectNoRefresh();
      expect(chain.transportCalls, 1);
      expect(chain.logoutCalls, 0);
    });
  });

  // -------------------------------------------------------------------------
  // 4. Replay failure must not be mistaken for a dead session.
  // -------------------------------------------------------------------------
  group('replay failure after a successful refresh', () {
    test(
      'does not log out and surfaces the REPLAY error, not the stale 401',
      () async {
        final _Chain chain = await _bootAuthenticated(<_Reply>[
          const _Reply(401),
          const _Reply(500, <String, dynamic>{'message': 'boom'}),
        ]);
        _stubRefreshSucceeds(chain.refreshDio);

        final Failure failure = await _expectMappedFailure(
          () => chain.dio.get<dynamic>(kProtectedPath),
        );

        // The replay's own 500 — NOT the UnauthorizedFailure the original 401
        // would have mapped to. Distinguishing the two is the whole assertion.
        expect(failure, isA<ServerFailure>());
        expect((failure as ServerFailure).statusCode, 500);
        // A transient 5xx that happens to follow a token expiry must never
        // sign the user out.
        expect(chain.logoutCalls, 0);
        expect(chain.container.read(authProvider).value, isA<Authenticated>());
        expect(chain.refreshCalls, 1);
        expect(chain.transportCalls, 2);
      },
    );
  });

  // -------------------------------------------------------------------------
  // 4b. COLD-START WINDOW — the stale-bearer replay regression.
  //
  // Raised MEDIUM by mobile-qa on 2026-08-07 and fixed at the token WRITE
  // (`AuthNotifier.setAccessToken`), not at the replay. `setAccessToken` used
  // to early-return unless the settled state was already `Authenticated`, so a
  // refresh completing while `build()` still held the provider in AsyncLoading
  // DISCARDED the new token; `_dio.fetch` then re-entered `AuthInterceptor`,
  // which re-derived the header from the stale `coldStartAccessToken` and
  // replayed the exact token that had just 401'd. `X-No-Retry` stopped the
  // second round, and cold-start `build()` read the resulting failure as a dead
  // session — a false "session expired" for a user holding valid credentials.
  //
  // Measured with the throwaway probe (state.value=null in BOTH runs, i.e. the
  // window genuinely open):
  //   before: authHeaders=[Bearer stale-access, Bearer stale-access]
  //   after:  authHeaders=[Bearer stale-access, Bearer new-access]
  //
  // MUTATION-PROVEN (2026-08-07, measured):
  //   • restore the AsyncLoading early-return in setAccessToken -> 3 RED here
  //   • update only _lastKnownAccessToken, not the sentinel      -> 3 RED here
  //   • plant the sentinel unconditionally                       -> 1 RED here
  // The third probe exists because "no sentinel planted" is a NEGATIVE
  // assertion (M14) and would otherwise be indistinguishable from a vacuous
  // pass; it is the only one of the four that goes red for it.
  // Pre-existing tests noticing any of the three: 0 of 138 + 491. That is the
  // whole reason this group exists.
  // -------------------------------------------------------------------------
  group('401 during the cold-start window (authProvider still AsyncLoading)', () {
    test(
      'the replay carries the REFRESHED bearer, not the stale cold-start one',
      () async {
        final _ColdStartChain cold = await _bootColdStartWindow(<_Reply>[
          const _Reply(401),
          const _Reply(200, <String, dynamic>{'displayName': 'Olena'}),
        ]);
        _stubRefreshSucceeds(cold.chain.refreshDio);

        final Response<dynamic> res = await cold.chain.dio.get<dynamic>(
          kProtectedPath,
        );

        // Still mid-build: this run really did exercise the window, and not a
        // session that settled behind the test's back while the 401 flew.
        expect(
          cold.chain.container.read(authProvider).value,
          isNull,
          reason: 'the window must still be open at assertion time',
        );

        // THE HEADLINE. Per-attempt header sequence, not just the outcome:
        // attempt 1 carries the token that 401s, attempt 2 must carry the one
        // the refresh just minted.
        expect(cold.chain.adapter.authHeaders, <String?>[
          'Bearer $kStaleAccess',
          'Bearer $kNewAccess',
        ]);
        expect(
          cold.chain.adapter.authHeaders[0],
          isNot(cold.chain.adapter.authHeaders[1]),
          reason:
              'the replay re-derives its Bearer from lastKnownAccessToken; if '
              'setAccessToken did not write durably it re-sends the token that '
              'already failed',
        );

        expect(cold.chain.refreshCalls, 1);
        expect(cold.chain.transportCalls, 2, reason: 'original + replay');
        expect(res.statusCode, 200);
        expect((res.data as Map<String, dynamic>)['displayName'], 'Olena');
        expect(cold.chain.adapter.noRetryHeaders, <String?>[null, 'true']);
      },
    );

    test('the session SURVIVES — no false "session expired", storage intact, '
        'logout never called', () async {
      // TOKEN-AWARE transport: this server 401s ANY request that is not
      // carrying the current token, exactly as the real backend does. That is
      // what makes this test load-bearing — against a fixture that answers 200
      // unconditionally, a replay on the stale token still "succeeds" and this
      // assertion passes for the wrong reason (measured: GREEN under the
      // stale-bearer mutation before this responder was introduced).
      final _ColdStartChain cold = await _bootColdStartWindow(
        const <_Reply>[],
        responder: (RequestOptions options) =>
            _header(options, 'authorization') == 'Bearer $kNewAccess'
            ? const _Reply(200, <String, dynamic>{'displayName': 'Olena'})
            : const _Reply(401),
      );
      _stubRefreshSucceeds(cold.chain.refreshDio);

      // The user-visible consequence: the request COMPLETES. Under the bug the
      // replay re-sent the stale token, the server 401'd it again, `X-No-Retry`
      // stopped the round, and the caller got an `UnauthorizedFailure` — the
      // false "session expired" bounce.
      final Response<dynamic> res = await cold.chain.dio.get<dynamic>(
        kProtectedPath,
      );
      expect(res.statusCode, 200);
      expect(cold.chain.transportCalls, 2, reason: 'original + one replay');

      // This is what the bug actually COST the user, pinned directly rather
      // than inferred from the header assertion above.
      expect(cold.chain.logoutCalls, 0, reason: 'no logout during the window');
      expect(
        await cold.chain.storage.readRefreshToken(),
        'new-refresh',
        reason: 'the rotated refresh token must survive, not be wiped',
      );

      // Release repo.me() and let cold start finish: it must settle on a live
      // session, not bounce the user to /login.
      cold.meGate.complete();
      final AuthSession session = await cold.sessionFuture;

      expect(session, isA<Authenticated>());
      expect(
        cold.chain.container.read(authProvider).value,
        isA<Authenticated>(),
      );
      expect(cold.chain.logoutCalls, 0);
      expect(await cold.chain.storage.readRefreshToken(), isNotNull);
    });

    test('the cold-start sentinel is refreshed IN PLACE, so it cannot shadow '
        'the new token', () async {
      final _ColdStartChain cold = await _bootColdStartWindow(<_Reply>[
        const _Reply(401),
        const _Reply(200, <String, dynamic>{'displayName': 'Olena'}),
      ]);
      _stubRefreshSucceeds(cold.chain.refreshDio);

      await cold.chain.dio.get<dynamic>(kProtectedPath);

      // `lastKnownAccessToken` resolves coldStartAccessToken BEFORE
      // _lastKnownAccessToken, so writing only the private field would leave
      // the stale sentinel winning. Both halves are asserted: the sentinel
      // itself, and the getter every interceptor actually reads.
      expect(
        cold.notifier.coldStartAccessToken,
        kNewAccess,
        reason: 'a live sentinel must be updated in place, never left stale',
      );
      expect(cold.notifier.lastKnownAccessToken, kNewAccess);
    });

    test('a settled session gets NO sentinel planted by setAccessToken', () async {
      // The other half of the sentinel rule, and the subtle one: the sentinel
      // is OWNED by whichever flow set it and cleared in that flow's `finally`.
      // Planting one here when none is live would leak a token nobody is
      // responsible for clearing — and `lastKnownAccessToken` prefers it over
      // the settled session, so a stale leak would outlive the session it came
      // from.
      final _Chain chain = await _bootAuthenticated(<_Reply>[
        const _Reply(401),
        const _Reply(200, <String, dynamic>{'displayName': 'Olena'}),
      ]);
      _stubRefreshSucceeds(chain.refreshDio);

      final AuthNotifier notifier = chain.container.read(authProvider.notifier);
      expect(
        notifier.coldStartAccessToken,
        isNull,
        reason: 'precondition: build() cleared the sentinel in its finally',
      );

      await chain.dio.get<dynamic>(kProtectedPath);

      expect(
        notifier.coldStartAccessToken,
        isNull,
        reason:
            'setAccessToken must refresh a LIVE sentinel, never create one; a '
            'planted sentinel has no owner to clear it',
      );
      // The settled path still applies the token — via the Riverpod state.
      expect(notifier.lastKnownAccessToken, kNewAccess);
      expect(
        (chain.container.read(authProvider).value! as Authenticated)
            .accessToken,
        kNewAccess,
      );
    });
  });

  // -------------------------------------------------------------------------
  // 5. Non-401 traffic passes through untouched and still reaches the mapper.
  // -------------------------------------------------------------------------
  group('non-401 errors', () {
    test('a 404 is mapped to NotFoundFailure without any refresh', () async {
      final _Chain chain = await _bootAuthenticated(<_Reply>[
        const _Reply(404),
      ]);
      _stubRefreshSucceeds(chain.refreshDio);

      final Failure failure = await _expectMappedFailure(
        () => chain.dio.get<dynamic>(kProtectedPath),
      );

      expect(failure, isA<NotFoundFailure>());
      chain.expectNoRefresh();
      expect(chain.logoutCalls, 0);
      expect(chain.transportCalls, 1);
    });

    test('a 400 is mapped to ValidationFailure without any refresh', () async {
      final _Chain chain = await _bootAuthenticated(<_Reply>[
        const _Reply(400, <String, dynamic>{
          'errors': <String, dynamic>{'displayName': 'must not be blank'},
        }),
      ]);
      _stubRefreshSucceeds(chain.refreshDio);

      final Failure failure = await _expectMappedFailure(
        () => chain.dio.get<dynamic>(kProtectedPath),
      );

      expect(failure, isA<ValidationFailure>());
      expect(
        (failure as ValidationFailure).fieldErrors['displayName'],
        'must not be blank',
      );
      chain.expectNoRefresh();
      expect(chain.transportCalls, 1);
    });
  });
}
