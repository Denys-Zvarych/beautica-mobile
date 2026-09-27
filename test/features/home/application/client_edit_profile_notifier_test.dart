// mobile-qa (2026-09-01) — unit tests for [clientEditProfileProvider]
// (`lib/features/home/application/client_edit_profile_notifier.dart`).
//
// WHY THIS FILE EXISTS
// --------------------
// Until now this provider had NO test file at all — `test/features/home/
// application/` held only `client_profile_provider_test.dart` and
// `next_appointment_provider_test.dart`. That was tolerable while it was
// "the thing the three client edit screens seed their fields from". It stopped
// being tolerable in Phase 21.14, for two compounding reasons:
//
//   1. It is `@Riverpod(keepAlive: true)` and it caches a whole [User] —
//      email, phone number, first/last name, bio, Instagram handle. That is
//      PII, held in a cache that by definition is never disposed on
//      navigation. "A logout / session swap evicts the previous user's
//      profile" is therefore a real security invariant of this object, and it
//      was entirely unpinned (mobile-security MEDIUM).
//   2. Phase 21.14 promoted it from a client-only read to the IDENTITY read
//      behind `ownerOwnProfileProvider` — the SALON_OWNER's own «Профіль»
//      tab now renders name/phone/Instagram straight out of this cache. So a
//      stale entry is no longer a wrong value on an edit form the user is
//      about to overwrite; it is another account's contact details rendered
//      as the signed-in owner's.
//
// WHAT IS PINNED, AND WHY EACH ONE IS NEEDED
// ------------------------------------------
// The `.select(authUserIdOrNull)` narrowing (2026-08-31 perf fix, promoted to
// the shared selector at `auth_notifier.dart:63` on 2026-09-01) is a
// two-sided contract, and only ONE side is a perf property:
//
//   • a silent token refresh (same user, new accessToken) must be INERT —
//     otherwise `refresh_interceptor.dart` refetches `GET /users/me` on every
//     rotation and drags `ownerOwnProfileProvider` (and its uncached
//     `GET /masters/{id}/services`) with it;
//   • a genuine IDENTITY change must STILL rebuild — this is the security
//     side. A `.select` that collapsed too far (returning a constant, or
//     folding `Unauthenticated` onto the previous id) would pass the first
//     assertion alone while serving user A's profile to user B.
//
// The pair mirrors `test/features/master/presentation/master_profile_notifier
// _test.dart`'s own "build() — narrowed authProvider watch" group, deliberately
// and to the letter: the two providers now carry the identical narrowing for
// the identical reason, so a reader who has seen one recognises the other, and
// a future change to the shared selector has to face the same two assertions
// on both sides of it.
//
// TERMINAL-ERROR DISCIPLINE (`asyncvalue_haserror_retrying` trap): every
// error-state assertion below checks `isA<AsyncError<User>>()` and NOT merely
// `hasError`. Riverpod emits `AsyncLoading(error: …, retrying: true)` while a
// retry is pending — runtime type `AsyncLoading`, but `hasError == true` and
// `error` populated — so a `hasError`-only assertion cannot tell the terminal
// error apart from the mid-retry loading state and can be satisfied by a state
// the user never actually lands on.
//
// Pure Dart — no widget tree. Fresh `ProviderContainer` per test, disposed via
// `addTearDown` (M1 hygiene).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/home/application/client_edit_profile_notifier.dart';
import 'package:beautica_mobile/features/home/data/client_profile_repository.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class _MockClientProfileRepository extends Mock
    implements ClientProfileRepository {}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const String _userId = 'user-42';
const String _otherUserId = 'user-99';

const User _sessionUser = User(
  id: _userId,
  email: 'client@beautica.ua',
  role: UserRole.client,
  firstName: 'Дмитро',
  lastName: 'Клієнт',
);

/// What `GET /users/me` answers for [_sessionUser]. Carries the PII fields the
/// eviction assertions below are actually about — a fixture that only had an
/// id could not tell "served the wrong profile" apart from "served nothing".
const User _profile = User(
  id: _userId,
  email: 'client@beautica.ua',
  role: UserRole.client,
  firstName: 'Дмитро',
  lastName: 'Клієнт',
  phoneNumber: '+380 97 111 11 11',
  instagram: '@dmytro',
);

/// A DIFFERENT account signing in on the same device.
const User _otherSessionUser = User(
  id: _otherUserId,
  email: 'other@beautica.ua',
  role: UserRole.client,
  firstName: 'Оксана',
  lastName: 'Інша',
);

const User _otherProfile = User(
  id: _otherUserId,
  email: 'other@beautica.ua',
  role: UserRole.client,
  firstName: 'Оксана',
  lastName: 'Інша',
  phoneNumber: '+380 50 222 22 22',
  instagram: '@oksana',
);

// ---------------------------------------------------------------------------
// Stub AuthNotifiers — resolve without touching platform channels
// ---------------------------------------------------------------------------

class _StubAuthAuthenticated extends AuthNotifier {
  @override
  Future<AuthSession> build() => Future.value(
    const AuthSession.authenticated(user: _sessionUser, accessToken: 'tok'),
  );
}

class _StubAuthUnauthenticated extends AuthNotifier {
  @override
  Future<AuthSession> build() =>
      Future.value(const AuthSession.unauthenticated());
}

// ---------------------------------------------------------------------------
// Container factory
// ---------------------------------------------------------------------------

ProviderContainer _makeContainer({
  required AuthNotifier Function() authFactory,
  required ClientProfileRepository repo,
  // Defaults to [beauticaProviderRetry] — the predicate `main.dart` installs
  // on the production root scope — so error paths resolve exactly as they do
  // in the app. Pass `(_, _) => null` when a test asserts the TERMINAL error
  // for a TRANSIENT failure, which the production policy would otherwise park
  // in `AsyncLoading(retrying: true)` for ~38 s.
  Duration? Function(int retryCount, Object error)? retry =
      beauticaProviderRetry,
}) {
  final container = ProviderContainer(
    retry: retry,
    overrides: [
      authProvider.overrideWith(authFactory),
      secureStorageProvider.overrideWithValue(FakeSecureStorage()),
      authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
      clientProfileRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  late _MockClientProfileRepository repo;

  setUp(() {
    repo = _MockClientProfileRepository();
  });

  /// Keeps the keepAlive provider SUBSCRIBED for the life of the test.
  ///
  /// Without a listener a dependency change schedules no rebuild at all, so a
  /// "did/did not refetch" assertion would be measuring the absence of a
  /// subscriber rather than the `.select` narrowing. In the app a screen is
  /// always watching this; this listener is that screen.
  void subscribe(ProviderContainer container) {
    final sub = container.listen(clientEditProfileProvider, (_, _) {});
    addTearDown(sub.close);
  }

  // ── 1. build() — happy path ─────────────────────────────────────────────
  group('build()', () {
    test('returns the User from GET /users/me when the session is '
        'Authenticated', () async {
      when(() => repo.getMyProfile()).thenAnswer((_) async => _profile);

      final container = _makeContainer(
        authFactory: _StubAuthAuthenticated.new,
        repo: repo,
      );
      // Settle authProvider first so the session is Authenticated before
      // build() reads it — otherwise the cold-start AsyncLoading (whose
      // `.value` is null) resolves the selector to null and the first build
      // throws Unauthorized before the session ever lands.
      await container.read(authProvider.future);
      subscribe(container);

      final User user = await container.read(clientEditProfileProvider.future);

      expect(user.id, _userId);
      expect(user.phoneNumber, '+380 97 111 11 11');
      expect(user.instagram, '@dmytro');
      verify(() => repo.getMyProfile()).called(1);
    });

    test('emits a TERMINAL AsyncError(UnauthorizedFailure) when the session '
        'is Unauthenticated — and never calls GET /users/me', () async {
      final container = _makeContainer(
        authFactory: _StubAuthUnauthenticated.new,
        repo: repo,
        // The assertion is about the FIRST attempt's terminal state; the
        // production predicate does not retry an UnauthorizedFailure anyway,
        // but pinning it here keeps the assertion independent of that policy.
        retry: (_, _) => null,
      );
      await container.read(authProvider.future);

      expect(
        authUserIdOrNull(container.read(authProvider)),
        isNull,
        reason:
            'the shared selector is what build() actually reads — an '
            'Unauthenticated session must resolve it to null, which is the '
            'trigger for the UnauthorizedFailure below.',
      );

      subscribe(container);
      await pumpEventQueue();

      final AsyncValue<User> state = container.read(clientEditProfileProvider);
      expect(
        state,
        isA<AsyncError<User>>(),
        reason:
            'the TERMINAL state, not merely `hasError` — an '
            'AsyncLoading(retrying: true) also reports hasError and would '
            'satisfy a weaker assertion mid-retry.',
      );
      expect((state as AsyncError<User>).error, isA<UnauthorizedFailure>());
      verifyNever(() => repo.getMyProfile());
    });
  });

  // ── 2. The narrowed authProvider watch — the two-sided contract ─────────
  group('build() — narrowed authProvider watch (.select(authUserIdOrNull))', () {
    test('a silent token refresh (same user id, NEW accessToken) does NOT '
        'refetch GET /users/me', () async {
      when(() => repo.getMyProfile()).thenAnswer((_) async => _profile);

      final container = _makeContainer(
        authFactory: _StubAuthAuthenticated.new,
        repo: repo,
      );
      await container.read(authProvider.future);
      subscribe(container);
      await container.read(clientEditProfileProvider.future);
      verify(() => repo.getMyProfile()).called(1);

      // Exactly what `refresh_interceptor.dart` does after a 401 → refresh:
      // re-emit Authenticated carrying the SAME user with a rotated token.
      container.read(authProvider.notifier).setAccessToken('tok-rotated-2');
      await pumpEventQueue();

      verifyNever(() => repo.getMyProfile());
      expect(
        container.read(authProvider).value,
        isA<Authenticated>().having(
          (Authenticated a) => a.accessToken,
          'accessToken',
          'tok-rotated-2',
        ),
        reason:
            'sanity: the session really did re-emit with a new token, so the '
            'no-refetch assertion above is about the .select narrowing and '
            'not about setAccessToken having silently no-opped.',
      );
      expect(
        container.read(clientEditProfileProvider).value,
        _profile,
        reason:
            'and the cached profile is still served — an inert re-emission '
            'must not blank the cache either.',
      );
    });

    test('a real identity change (DIFFERENT user id) DOES refetch, and the '
        'previous user\'s PII is replaced', () async {
      when(() => repo.getMyProfile()).thenAnswer((_) async => _profile);

      final container = _makeContainer(
        authFactory: _StubAuthAuthenticated.new,
        repo: repo,
      );
      await container.read(authProvider.future);
      subscribe(container);
      expect(await container.read(clientEditProfileProvider.future), _profile);
      // Consumes the landing call so the post-swap `.called(1)` below counts
      // ONLY the refetch (mocktail's verify resets the recorded calls).
      verify(() => repo.getMyProfile()).called(1);

      // A different account on the same device — the ONE change that must
      // still invalidate this keepAlive cache.
      when(() => repo.getMyProfile()).thenAnswer((_) async => _otherProfile);
      container.read(authProvider.notifier).state = const AsyncData(
        AuthSession.authenticated(user: _otherSessionUser, accessToken: 'tok'),
      );
      await pumpEventQueue();

      final User served = await container.read(
        clientEditProfileProvider.future,
      );
      expect(
        served,
        _otherProfile,
        reason:
            'THE SECURITY SIDE of the narrowing. This provider is keepAlive '
            'and holds email / phone / Instagram; a selector that collapsed '
            'too far would keep serving user $_userId\'s contact details to '
            'user $_otherUserId.',
      );
      expect(served.phoneNumber, isNot(_profile.phoneNumber));
      expect(served.instagram, isNot(_profile.instagram));
      verify(() => repo.getMyProfile()).called(1);
    });

    test('LOGOUT evicts the previous user\'s cached profile: the provider '
        'errors rather than serving it', () async {
      when(() => repo.getMyProfile()).thenAnswer((_) async => _profile);

      final container = _makeContainer(
        authFactory: _StubAuthAuthenticated.new,
        repo: repo,
        retry: (_, _) => null,
      );
      await container.read(authProvider.future);
      subscribe(container);
      expect(await container.read(clientEditProfileProvider.future), _profile);
      // Consumes the landing call so the `verifyNever` below is genuinely
      // about the post-logout rebuild and not about this first fetch.
      verify(() => repo.getMyProfile()).called(1);

      // The session ends. `authUserIdOrNull` flips from the user id to null,
      // which is the same rebuild trigger the un-narrowed watch had.
      container.read(authProvider.notifier).state = const AsyncData(
        AuthSession.unauthenticated(),
      );
      await pumpEventQueue();

      expect(
        authUserIdOrNull(container.read(authProvider)),
        isNull,
        reason: 'sanity: the session really did end.',
      );

      final AsyncValue<User> state = container.read(clientEditProfileProvider);
      expect(
        state,
        isA<AsyncError<User>>(),
        reason:
            'a keepAlive cache holding another account\'s email / phone / '
            'Instagram must go to a TERMINAL error on logout. `isA<AsyncError>` '
            'and not `hasError`: AsyncLoading(retrying: true) satisfies '
            'hasError too.',
      );
      expect((state as AsyncError<User>).error, isA<UnauthorizedFailure>());

      // `.future` is what `ownerOwnProfileProvider` awaits — it must THROW,
      // not resolve to the signed-out user's profile. Asserting only on
      // `state.value` would be unsound here: Riverpod 3 retains `.value`
      // across an invalidate/rebuild by design, so a retained value is not by
      // itself proof of a leak — what the consumer actually receives is.
      await expectLater(
        container.read(clientEditProfileProvider.future),
        throwsA(isA<UnauthorizedFailure>()),
        reason:
            'the PII eviction invariant, stated the way a CONSUMER sees it: '
            'ownerOwnProfileProvider awaits this future and renders whatever '
            'it yields as the signed-in identity.',
      );
      verifyNever(() => repo.getMyProfile());
    });
  });
}
