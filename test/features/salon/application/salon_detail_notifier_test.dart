// mobile-qa re-audit (cycle 2, 2026-09-05) — unit tests for the NEW
// [salonDetail] provider (`salon_detail_notifier.dart`), which the Phase 21.16
// fix pass added with no test file of its own.
//
// WHAT THIS PROVIDER CLAIMS, AND WHY EACH CLAIM NEEDS A PIN
// ---------------------------------------------------------------------------
// It exists to be a NARROWING. `AdminOwnProfileScreen`'s stand-alone path used
// to watch `salonManagementProfileProvider`, which fires TWO requests —
// `GET /salons/{id}` AND `GET /salons/{id}/staff`, the latter being the
// management-scoped, UNMASKED staff-contacts roster the screen destructures
// away unread (a wasted round trip AND a data-minimisation miss). So:
//
//   1. exactly ONE repository call, and `getSalonStaff` NEVER — the reason the
//      provider was written. `admin_own_profile_screen_test.dart` pins this at
//      the SCREEN level via build logs; this pins the provider itself, which
//      is what any future consumer inherits.
//   2. a repository failure surfaces as a terminal `AsyncError` rather than a
//      swallowed null (the screen renders an ABSENT card for it, and can only
//      do that if the error actually arrives).
//   3. the `ref.watch(authProvider.select(authUserIdOrNull))` auth-boundary
//      eviction is a PAIR, and a test for either half alone is worthless: a
//      `.select` that returned a constant would pass "a token refresh does not
//      refetch" while silently disabling the cross-account eviction the watch
//      exists for. Both halves are pinned below.
//
// Strategy mirrors `salon_management_profile_notifier_test.dart` — the sibling
// this provider was carved out of: a fresh `ProviderContainer` per test
// (`addTearDown`), `authProvider` / `authRepositoryProvider` /
// `secureStorageProvider` stubbed so no real auth or Keystore I/O happens,
// `salonRepositoryProvider` overridden with a mocktail mock. Pure Dart, no
// widget tree.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_detail_notifier.dart';
import 'package:beautica_mobile/features/salon/data/salon_repository.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';

class _MockSalonRepository extends Mock implements SalonRepository {}

const String _kSalonId = 'salon-admin-1';

/// Carries a NON-DEFAULT name so the happy-path assertion actually MOVES — a
/// fixture equal to whatever a broken mapping would produce could not fail.
const Salon _salon = Salon(id: _kSalonId, name: 'Салон «Вельвет»');

const User _stubAdmin = User(
  id: 'u-admin-1',
  email: 'admin@beautica.test',
  role: UserRole.salonAdmin,
  salonId: _kSalonId,
);

/// Settles to [_stubAdmin], and lets a test push a NEW session afterwards —
/// needed by the narrowed-watch pair, which must distinguish a token-only
/// re-emission from a real identity change. `state =` is only reachable from
/// inside an [AsyncNotifier] subclass, hence a stub rather than an external
/// poke.
class _ControllableAuth extends AuthNotifier {
  @override
  Future<AuthSession> build() => Future.value(
    const AuthSession.authenticated(user: _stubAdmin, accessToken: 'tok'),
  );

  void emit(AuthSession session) => state = AsyncData<AuthSession>(session);
}

void main() {
  late _MockSalonRepository repo;
  late _ControllableAuth auth;

  setUp(() {
    repo = _MockSalonRepository();
    auth = _ControllableAuth();
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      // No retry curve — an error must stay terminal for the assertion rather
      // than re-entering AsyncLoading behind it.
      retry: (_, _) => null,
      overrides: [
        authProvider.overrideWith(() => auth),
        secureStorageProvider.overrideWithValue(FakeSecureStorage()),
        authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
        salonRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('build()', () {
    test('resolves the salon through getSalonById and makes NO staff-roster '
        'call — the narrowing this provider exists for', () async {
      when(() => repo.getSalonById(_kSalonId)).thenAnswer((_) async => _salon);

      final container = makeContainer();
      // Settle the session FIRST. `build()` watches
      // `authProvider.select(authUserIdOrNull)`, so a first build racing an
      // unresolved session sees `null` and is legitimately rebuilt the moment
      // the identity arrives — two calls, for a reason that has nothing to do
      // with the assertion below.
      await container.read(authProvider.future);
      // Keep the family element subscribed for the whole read. It is
      // `autoDispose`, so an unlistened `.future` read is torn down mid-build
      // ("disposed during loading state") and the test fails for a reason that
      // has nothing to do with the provider's behaviour.
      final sub = container.listen(salonDetailProvider(_kSalonId), (_, _) {});
      addTearDown(sub.close);
      final Salon result = await container.read(
        salonDetailProvider(_kSalonId).future,
      );

      expect(result.id, _kSalonId);
      expect(
        result.name,
        'Салон «Вельвет»',
        reason:
            'a specific loaded value, not merely "something resolved" — this '
            'is the field the affiliation card renders.',
      );
      verify(() => repo.getSalonById(_kSalonId)).called(1);
      verifyNever(() => repo.getSalonStaff(any()));
      verifyNever(() => repo.getSalonMasters(any()));
    });

    test('a repository failure surfaces as a terminal AsyncError', () async {
      // Thrown from an `async` body, never synchronously: a Dio-backed
      // repository always fails asynchronously, and a sync throw during a
      // provider build bypasses Riverpod's retry machinery entirely — an error
      // state real users never reach that way.
      when(
        () => repo.getSalonById(_kSalonId),
      ).thenAnswer((_) async => throw const ServerFailure());

      final container = makeContainer();
      await container.read(authProvider.future);
      // `onError` swallowed: the subscription exists only to keep the
      // autoDispose element alive across the read (see the happy path above);
      // the error itself is asserted below, not here.
      final sub = container.listen(
        salonDetailProvider(_kSalonId),
        (_, _) {},
        onError: (Object _, StackTrace _) {},
      );
      addTearDown(sub.close);
      await expectLater(
        container.read(salonDetailProvider(_kSalonId).future),
        throwsA(isA<ServerFailure>()),
      );

      expect(
        container.read(salonDetailProvider(_kSalonId)),
        isA<AsyncError<Salon>>(),
        reason:
            'the terminal error SUBTYPE, never just `hasError` — a mid-retry '
            'AsyncLoading reports hasError == true too and could not be told '
            'apart by that check alone.',
      );
    });
  });

  // ── the narrowed authProvider watch ──────────────────────────────────────
  // The pair. Either half alone is satisfiable by a broken `.select`: one that
  // returns a constant passes the token-refresh test while silently disabling
  // the cross-account eviction; one that watches the WHOLE session passes the
  // identity-change test while refetching on every silent token rotation.
  group('build() — narrowed authProvider watch', () {
    test('a silent token refresh (same user id, new accessToken) does NOT '
        'refetch the salon', () async {
      when(() => repo.getSalonById(_kSalonId)).thenAnswer((_) async => _salon);

      final container = makeContainer();
      await container.read(authProvider.future);
      // Keep the family element subscribed — an unlistened autoDispose
      // provider would be torn down and prove nothing either way.
      final sub = container.listen(salonDetailProvider(_kSalonId), (_, _) {});
      addTearDown(sub.close);
      await container.read(salonDetailProvider(_kSalonId).future);
      verify(() => repo.getSalonById(_kSalonId)).called(1);

      // Exactly what `refresh_interceptor.dart` does after a 401 → refresh.
      container.read(authProvider.notifier).setAccessToken('tok-rotated-2');
      await pumpEventQueue();

      verifyNever(() => repo.getSalonById(any()));
      expect(
        container.read(authProvider).value,
        isA<Authenticated>()
            .having(
              (Authenticated a) => a.accessToken,
              'accessToken',
              'tok-rotated-2',
            )
            .having((Authenticated a) => a.user.id, 'user.id', _stubAdmin.id),
        reason:
            'sanity: the session really did re-emit, with a NEW token and the '
            'SAME user — so the no-refetch assertion above is about the '
            '.select narrowing, not about setAccessToken having no-opped.',
      );
    });

    test('a real identity change (different user id) DOES refetch — the '
        'cross-account eviction', () async {
      when(() => repo.getSalonById(_kSalonId)).thenAnswer((_) async => _salon);

      final container = makeContainer();
      await container.read(authProvider.future);
      final sub = container.listen(salonDetailProvider(_kSalonId), (_, _) {});
      addTearDown(sub.close);
      await container.read(salonDetailProvider(_kSalonId).future);
      verify(() => repo.getSalonById(_kSalonId)).called(1);

      // A different account on the same device, no app restart — the ONE
      // change that must still tear the cached salon down.
      auth.emit(
        const AuthSession.authenticated(
          user: User(
            id: 'u-admin-2',
            email: 'other-admin@beautica.test',
            role: UserRole.salonAdmin,
            salonId: _kSalonId,
          ),
          accessToken: 'tok',
        ),
      );
      await pumpEventQueue();
      await container.read(salonDetailProvider(_kSalonId).future);

      verify(() => repo.getSalonById(_kSalonId)).called(1);
    });
  });
}
