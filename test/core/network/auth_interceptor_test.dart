// Tests for AuthInterceptor — Bearer token injection path.
//
// AuthInterceptor reads _ref.read(authProvider).value and:
//   - Authenticated + non-auth path → injects Authorization: Bearer <token>.
//   - Unauthenticated → no header added.
//   - Auth path (in kAuthPaths) + Authenticated → no header added.
//   - Loading state (authProvider.value == null) → no header added.
//
// To inject a real [Ref] into the interceptor without Riverpod codegen, we use
// a plain [ProviderContainer] and capture the [Ref] from a keepAlive [Provider]
// that returns its own ref. This mirrors the approach in refresh_interceptor_test
// but without the @riverpod annotation so that no build_runner pass is needed
// for this test file.

import 'package:beautica_mobile/core/network/auth_interceptor.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/auth_tokens.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/fakes/fake_auth_repository.dart';
import '../../helpers/fakes/fake_secure_storage.dart';

// ---------------------------------------------------------------------------
// Ref-capture provider (no codegen — hand-written keepAlive Provider).
//
// This is the only place in the test suite where a hand-written Provider is
// intentionally used. The @riverpod pattern cannot be used here without
// running build_runner; keeping this test self-contained is more important
// than codegen consistency in a test-only file. The production codebase
// is unaffected.
// ---------------------------------------------------------------------------

/// A keepAlive [Provider] whose sole purpose is to expose its [Ref] so
/// [AuthInterceptor] can be constructed with a real [Ref] in tests.
final _refCaptureProvider = Provider<Ref>((ref) => ref, name: 'authTestRef');

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockRequestHandler extends Mock implements RequestInterceptorHandler {}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _fakeUser = User(
  id: 'u1',
  email: 'test@example.com',
  role: UserRole.independentMaster,
  firstName: 'Test',
  lastName: 'User',
);

const _fakeAccessToken = 'test-access-jwt';

/// Rotated token pair returned by the cold-start refresh in
/// [_makeColdStartContainer]. Its [AuthTokens.accessToken] is what the real
/// notifier stores in `_lastKnownAccessToken` and what the interceptor must
/// recover during the delete-flow mid-rebuild race (B1).
const _rotatedTokens = AuthTokens(
  accessToken: 'rotated-access-jwt',
  refreshToken: 'rotated-refresh-jwt',
);

// ---------------------------------------------------------------------------
// Helper — builds RequestOptions for a given path.
// ---------------------------------------------------------------------------

RequestOptions _opts(String path) => RequestOptions(
  path: path,
  baseUrl: 'https://api.beautica.test',
  headers: <String, dynamic>{},
);

/// Builds DELETE [RequestOptions] for [path] — mirrors the real delete call
/// (`ServiceRepository.deactivate` → DELETE /api/v1/services/{serviceDefId}).
RequestOptions _serviceDeleteOpts(String path) => RequestOptions(
  path: path,
  method: 'DELETE',
  baseUrl: 'https://api.beautica.test',
  headers: <String, dynamic>{},
);

// ---------------------------------------------------------------------------
// AuthNotifier stubs
// ---------------------------------------------------------------------------

/// Notifier that holds a fixed [AsyncValue<AuthSession>] for testing.
class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(this._fixed);

  final AsyncValue<AuthSession> _fixed;

  @override
  Future<AuthSession> build() async {
    state = _fixed;
    return _fixed.value ?? const AuthSession.unauthenticated();
  }
}

// ---------------------------------------------------------------------------
// Container factory
// ---------------------------------------------------------------------------

/// Creates a [ProviderContainer] with [authProvider] overridden by a fixed
/// [AsyncValue<AuthSession>] stub notifier.
ProviderContainer _makeContainer(AsyncValue<AuthSession> authState) {
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith(() => _FixedAuthNotifier(authState)),
      authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
      secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Creates a [ProviderContainer] backed by the REAL [AuthNotifier] driven
/// through its cold-start restore flow ([FakeAuthRepository] returns
/// [rotatedTokens] from refresh + [_fakeUser] from me).
///
/// Unlike [_makeContainer]'s [_FixedAuthNotifier] stub, this exercises the real
/// notifier so its private `_lastKnownAccessToken` session-lifetime fallback is
/// genuinely populated — the exact field [AuthInterceptor]'s else-branch reads
/// during the delete-flow mid-rebuild race (auth_notifier Test 2b).
Future<({ProviderContainer container, AuthNotifier notifier})>
_makeColdStartContainer() async {
  final storage = FakeSecureStorage();
  await storage.writeRefreshToken('stored-refresh');
  final repo = FakeAuthRepository()
    ..refreshResult = _rotatedTokens
    ..meResult = _fakeUser;

  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWith((_) => repo),
      secureStorageProvider.overrideWith((_) => storage),
    ],
  );
  addTearDown(container.dispose);

  // Drive the cold-start restore to completion so the settled Authenticated
  // session populates `_lastKnownAccessToken`.
  await container.read(authProvider.future);
  final notifier = container.read(authProvider.notifier);
  return (container: container, notifier: notifier);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    registerFallbackValue(RequestOptions(path: '/'));
  });

  group('AuthInterceptor', () {
    // -----------------------------------------------------------------------
    // Test 1 — Authenticated state → Authorization header added
    // -----------------------------------------------------------------------
    test(
      'authenticated state → Authorization: Bearer header appended',
      () async {
        const authState = AsyncData<AuthSession>(
          AuthSession.authenticated(
            user: _fakeUser,
            accessToken: _fakeAccessToken,
          ),
        );

        final container = _makeContainer(authState);
        // Allow the authProvider to settle so state.value is non-null.
        await container.read(authProvider.future);

        final ref = container.read(_refCaptureProvider);
        final interceptor = AuthInterceptor(ref);
        final handler = MockRequestHandler();
        final opts = _opts('/master/profile');

        interceptor.onRequest(opts, handler);

        expect(
          opts.headers['Authorization'],
          equals('Bearer $_fakeAccessToken'),
        );
        verify(() => handler.next(opts)).called(1);
      },
    );

    // -----------------------------------------------------------------------
    // Test 2 — Unauthenticated state → no Authorization header
    // -----------------------------------------------------------------------
    test('unauthenticated state → no Authorization header added', () async {
      const authState = AsyncData<AuthSession>(AuthSession.unauthenticated());

      final container = _makeContainer(authState);
      await container.read(authProvider.future);

      final ref = container.read(_refCaptureProvider);
      final interceptor = AuthInterceptor(ref);
      final handler = MockRequestHandler();
      final opts = _opts('/master/profile');

      interceptor.onRequest(opts, handler);

      expect(opts.headers.containsKey('Authorization'), isFalse);
      verify(() => handler.next(opts)).called(1);
    });

    // -----------------------------------------------------------------------
    // Test 3 — Auth path with Authenticated state → no Authorization header
    // -----------------------------------------------------------------------
    test(
      'auth path (/api/v1/auth/login) with authenticated state → no Authorization header',
      () async {
        const authState = AsyncData<AuthSession>(
          AuthSession.authenticated(
            user: _fakeUser,
            accessToken: _fakeAccessToken,
          ),
        );

        final container = _makeContainer(authState);
        await container.read(authProvider.future);

        final ref = container.read(_refCaptureProvider);
        final interceptor = AuthInterceptor(ref);
        final handler = MockRequestHandler();
        // /api/v1/auth/login is in kAuthPaths → interceptor must skip token
        // injection. The full /api/v1/ prefix is required since AppConfig.baseUrl
        // no longer carries the /api/v1 segment (see auth_paths.dart).
        final opts = _opts('/api/v1/auth/login');

        interceptor.onRequest(opts, handler);

        expect(opts.headers.containsKey('Authorization'), isFalse);
        verify(() => handler.next(opts)).called(1);
      },
    );

    // -----------------------------------------------------------------------
    // Test 4 — Loading state (authProvider.value is null) → no Authorization header
    // -----------------------------------------------------------------------
    test('loading state (value == null) → no Authorization header', () async {
      // AsyncLoading has a null value — interceptor must not inject a token.
      // Use a fresh container without awaiting the future (notifier never resolves
      // from AsyncLoading because _FixedAuthNotifier sets state = AsyncLoading
      // then immediately returns; Riverpod resolves it but we check the intercept
      // logic before the state settles by reading the Ref directly).
      //
      // Simpler: use an Unauthenticated state with no access token — the branch
      // guard `state is Authenticated` covers both Loading and Unauthenticated.
      // For a true null-value test, override state after build completes.
      const authState = AsyncData<AuthSession>(AuthSession.unauthenticated());

      final container = _makeContainer(authState);
      await container.read(authProvider.future);

      // Manually push AsyncLoading into the notifier state to simulate a
      // mid-flight loading state (e.g. during a login call).
      container
              .read(authProvider.notifier)
              // ignore: invalid_use_of_protected_member
              .state =
          const AsyncLoading<AuthSession>();

      final ref = container.read(_refCaptureProvider);
      final interceptor = AuthInterceptor(ref);
      final handler = MockRequestHandler();
      final opts = _opts('/master/profile');

      interceptor.onRequest(opts, handler);

      // Loading → value is null → no token injected.
      expect(opts.headers.containsKey('Authorization'), isFalse);
      verify(() => handler.next(opts)).called(1);
    });

    // -----------------------------------------------------------------------
    // Test 5 — Loading state WITH coldStartAccessToken set → Bearer header injected
    //
    // HIGH-1 regression guard (mobile-security 2026-05-24):
    //
    // During cold-start, authProvider is in AsyncLoading while build() awaits
    // repo.me(). To prevent a 401 → RefreshInterceptor loop on /users/me, the
    // notifier writes the freshly-rotated access token to its plain
    // [coldStartAccessToken] field. AuthInterceptor's else-branch
    // (auth_interceptor.dart:51-59) MUST pick this up and inject the Bearer
    // header even though [authProvider.value] is still null.
    //
    // Without this test, deleting the else-branch would leave Tests 1–4 green
    // (Test 4 only covers `AsyncLoading + coldStartAccessToken == null`).
    // -----------------------------------------------------------------------
    test('loading state with coldStartAccessToken set → '
        'Bearer header injected (HIGH-1 cold-start fallback)', () async {
      // Start from a settled state so the notifier exists; then push the
      // notifier into AsyncLoading and set the sentinel field — exactly the
      // condition AuthInterceptor sees on the cold-start /users/me call.
      const authState = AsyncData<AuthSession>(AuthSession.unauthenticated());

      final container = _makeContainer(authState);
      await container.read(authProvider.future);

      // Push the notifier back into AsyncLoading and seed the sentinel with
      // the rotated access token (the value AuthNotifier.build() writes
      // before awaiting repo.me()).
      const coldToken = 'cold-token';
      final notifier = container.read(authProvider.notifier);
      notifier.coldStartAccessToken = coldToken;
      // ignore: invalid_use_of_protected_member
      notifier.state = const AsyncLoading<AuthSession>();

      final ref = container.read(_refCaptureProvider);
      final interceptor = AuthInterceptor(ref);
      final handler = MockRequestHandler();
      // /users/me is NOT in kAuthPaths — interceptor must reach the else-branch
      // and inject the cold-start access token.
      final opts = _opts('/users/me');

      interceptor.onRequest(opts, handler);

      expect(
        opts.headers['Authorization'],
        equals('Bearer $coldToken'),
        reason:
            'During cold-start AsyncLoading, AuthInterceptor must fall back '
            'to coldStartAccessToken and attach the Bearer header so '
            '/users/me does not 401 and trigger a redundant refresh loop.',
      );
      verify(() => handler.next(opts)).called(1);
    });

    // -----------------------------------------------------------------------
    // Test 6 — mid-rebuild AsyncLoading race on a DELETE → Bearer header from
    //          _lastKnownAccessToken (delete-service false-401 regression)
    //
    // HIGH regression guard (closes the original false-401 delete bug):
    //
    // The delete flow invalidates masterProfileProvider, which
    // serviceRepositoryProvider watches; while that rebuild runs, a watcher of
    // authProvider is momentarily in AsyncLoading with the cold-start sentinel
    // already cleared (`coldStartAccessToken == null`) — exactly the state
    // proven by auth_notifier Test 2b. AuthInterceptor's else-branch MUST fall
    // back to `lastKnownAccessToken` (→ `_lastKnownAccessToken`) so the
    // in-flight DELETE /api/v1/services/{serviceDefId} still carries the Bearer
    // token rather than being sent tokenless (which the backend correctly
    // answers with a false 401, "Сесія завершилась").
    //
    // The path/method below mirror production exactly:
    //   ServiceRepository.deactivate → DELETE /api/v1/services/{serviceDefId}
    //   (service_repository.dart deactivateServiceDefinition).
    // -----------------------------------------------------------------------
    test(
      'mid-rebuild AsyncLoading race → DELETE /api/v1/services/{id} carries '
      'Bearer header from _lastKnownAccessToken (delete false-401 regression)',
      () async {
        final (:container, :notifier) = await _makeColdStartContainer();

        // Settled Authenticated → `_lastKnownAccessToken` now holds the rotated
        // access token. Push the notifier into the mid-rebuild race state:
        // AsyncLoading, with coldStartAccessToken already null (its settled
        // value) — so the only recoverable token is `_lastKnownAccessToken`.
        expect(
          notifier.coldStartAccessToken,
          isNull,
          reason:
              'cold-start sentinel is cleared once build() settles — the race '
              'must be recovered via _lastKnownAccessToken, not the sentinel',
        );
        // ignore: invalid_use_of_protected_member
        notifier.state = const AsyncLoading<AuthSession>();

        final ref = container.read(_refCaptureProvider);
        final interceptor = AuthInterceptor(ref);
        final handler = MockRequestHandler();

        // DELETE on the real deactivate path — keyed on the service-definition
        // id. `_makeServiceDeleteOpts` produces a DELETE RequestOptions so the
        // exact seam (else-branch on a DELETE) is exercised.
        final opts = _serviceDeleteOpts('/api/v1/services/def-123');

        interceptor.onRequest(opts, handler);

        expect(
          opts.method,
          equals('DELETE'),
          reason:
              'the regression is specific to the DELETE delete-service call',
        );
        expect(
          opts.headers['Authorization'],
          equals('Bearer ${_rotatedTokens.accessToken}'),
          reason:
              'during the delete-flow mid-rebuild AsyncLoading window, the '
              'interceptor must recover the last-known access token so the '
              'DELETE is not sent tokenless and rejected with a false 401',
        );
        verify(() => handler.next(opts)).called(1);
      },
    );

    // -----------------------------------------------------------------------
    // Test 7 — public discovery search endpoints → NO Authorization header
    //
    // SECURITY HIGH regression guard (mobile-security 2026-06-18, Phase 13.2):
    //
    // The discovery search repository (HttpSearchRepository) calls the public
    // endpoints
    //   GET /api/v1/search/masters
    //   GET /api/v1/search/salons
    // over the authenticated Dio. Because `/api/v1/search/` was MISSING from
    // kPublicPathPrefixes, an authenticated user's Bearer JWT was attached to
    // these public reads — leaking the token to an endpoint that does not need
    // it (same class of bug as the /api/v1/locations/ fix on 2026-05-31).
    //
    // The fix adds '/api/v1/search/' to kPublicPathPrefixes so AuthInterceptor's
    // prefix-skip branch (auth_interceptor.dart:49-52) short-circuits before the
    // token-injection block. This test pumps both search paths through the
    // interceptor while genuinely AUTHENTICATED and asserts NO Authorization
    // header — and contrasts a normal authenticated endpoint that DOES still
    // receive the token, proving the skip is scoped to the search prefix only.
    //
    // PRE-FIX expectation: FAILS — both search requests carry
    //   Authorization: Bearer test-access-jwt.
    // POST-FIX expectation: PASSES.
    // -----------------------------------------------------------------------
    test(
      'public search endpoints (/api/v1/search/masters & /salons) carry NO '
      'Authorization header even when authenticated (HIGH token-leak fix)',
      () async {
        const authState = AsyncData<AuthSession>(
          AuthSession.authenticated(
            user: _fakeUser,
            accessToken: _fakeAccessToken,
          ),
        );

        final container = _makeContainer(authState);
        await container.read(authProvider.future);

        final ref = container.read(_refCaptureProvider);
        final interceptor = AuthInterceptor(ref);

        // GET /api/v1/search/masters — public discovery read.
        final mastersHandler = MockRequestHandler();
        final mastersOpts = _opts('/api/v1/search/masters');
        interceptor.onRequest(mastersOpts, mastersHandler);

        expect(
          mastersOpts.headers.containsKey('Authorization'),
          isFalse,
          reason:
              '/api/v1/search/masters is a public discovery endpoint — the '
              'authenticated Bearer JWT must NOT be attached (add '
              "'/api/v1/search/' to kPublicPathPrefixes).",
        );
        verify(() => mastersHandler.next(mastersOpts)).called(1);

        // GET /api/v1/search/salons — public discovery read.
        final salonsHandler = MockRequestHandler();
        final salonsOpts = _opts('/api/v1/search/salons');
        interceptor.onRequest(salonsOpts, salonsHandler);

        expect(
          salonsOpts.headers.containsKey('Authorization'),
          isFalse,
          reason:
              '/api/v1/search/salons is a public discovery endpoint — the '
              'authenticated Bearer JWT must NOT be attached.',
        );
        verify(() => salonsHandler.next(salonsOpts)).called(1);

        // Contrast: a normal authenticated endpoint STILL receives the token, so
        // the search-prefix skip has not over-broadened token suppression.
        final authedHandler = MockRequestHandler();
        final authedOpts = _opts('/master/profile');
        interceptor.onRequest(authedOpts, authedHandler);

        expect(
          authedOpts.headers['Authorization'],
          equals('Bearer $_fakeAccessToken'),
          reason:
              'a normal authenticated endpoint must continue to receive the '
              'Bearer token — the public-prefix skip must be scoped to search.',
        );
        verify(() => authedHandler.next(authedOpts)).called(1);
      },
    );
  });
}
