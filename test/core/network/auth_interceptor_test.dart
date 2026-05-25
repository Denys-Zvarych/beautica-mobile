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

// ---------------------------------------------------------------------------
// Helper — builds RequestOptions for a given path.
// ---------------------------------------------------------------------------

RequestOptions _opts(String path) => RequestOptions(
  path: path,
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
      'auth path (/auth/login) with authenticated state → no Authorization header',
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
        // /auth/login is in kAuthPaths → interceptor must skip token injection.
        final opts = _opts('/auth/login');

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
  });
}
