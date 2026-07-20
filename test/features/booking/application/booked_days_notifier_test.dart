// mobile-security HIGH (2026-07-20) — regression coverage for
// `bookedDaysProvider`'s session-boundary PII fix.
//
// Before this fix, `bookedDaysProvider` was a `keepAlive()` singleton with a
// 30-minute TTL and ZERO `ref.watch` calls tying it to the authenticated
// identity — exactly the shape `bookingsDayProvider` had before its own
// mobile-security HIGH fix (2026-07-19, see
// `bookings_day_notifier_test.dart`'s "session-boundary PII" group, which
// this file mirrors for the day-rail's dot set). On a shared device: Master A
// opens «Мої записи», logs out; Master B logs in within the 30-minute TTL and
// sees A's booked-day dots rendered on first paint — no loading state, no
// refetch.
//
// Fixed by `build()` now `ref.watch`ing `authProvider.select((s) => ...id)`,
// so an identity change (logout, or a different account logging in) forces a
// fresh fetch through Riverpod's ordinary `invalidateSelf()` cascade — the
// SAME mechanism `bookingsDayProvider` relies on, verified against Riverpod's
// own disposal internals in that provider's file header. Unlike
// `bookingsDayProvider`, this provider is not a family with an external LRU
// to separately sweep at logout — the watch alone is the whole fix; see
// `booked_days_notifier.dart`'s file header for why an explicit
// `AuthNotifier.logout`-side `ref.invalidate` call was considered and
// rejected.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/booked_days_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';

class _MockBookingRepository extends Mock implements BookingRepository {}

// ---------------------------------------------------------------------------
// Auth stub — mirrors `bookings_day_notifier_test.dart`'s
// `_MutableAuthNotifier` exactly, for the same reason: lets a test flip the
// SETTLED session after `build()`, deterministically, without a live
// SecureStorage/AuthRepository.
// ---------------------------------------------------------------------------

const User _master1 = User(
  id: 'master-1',
  email: 'master1@beautica.ua',
  role: UserRole.independentMaster,
  firstName: 'Оля',
  lastName: 'Коваль',
);

const User _master2 = User(
  id: 'master-2',
  email: 'master2@beautica.ua',
  role: UserRole.independentMaster,
  firstName: 'Ірина',
  lastName: 'Бондар',
);

class _MutableAuthNotifier extends AuthNotifier {
  _MutableAuthNotifier(this._initial);

  final AuthSession _initial;

  @override
  Future<AuthSession> build() async => _initial;

  void setSession(AuthSession session) =>
      state = AsyncData<AuthSession>(session);
}

/// Builds a container with the auth graph stubbed, [authProvider] already
/// SETTLED before returning — see `bookings_day_notifier_test.dart`'s
/// identical helper for why settling first is load-bearing: `build()` now
/// `ref.watch`es `authProvider.select(...)`, so reading `bookedDaysProvider`
/// while `authProvider` is still `AsyncLoading` would observe a `null`
/// selected id, then rebuild a SECOND time the instant `_initial` resolves.
Future<({ProviderContainer container, _MutableAuthNotifier auth})>
_containerWithAuth(BookingRepository repo, AuthSession initialAuth) async {
  final auth = _MutableAuthNotifier(initialAuth);
  final container = ProviderContainer(
    overrides: <Object>[
      bookingRepositoryProvider.overrideWithValue(repo),
      authProvider.overrideWith(() => auth),
    ].cast(),
  );
  addTearDown(container.dispose);
  await container.read(authProvider.future);
  return (container: container, auth: auth);
}

void main() {
  late _MockBookingRepository repo;

  setUp(() {
    repo = _MockBookingRepository();
  });

  void stubBookedDays(List<DateTime> days) {
    when(
      () => repo.getMyBookedDays(
        from: any(named: 'from'),
        to: any(named: 'to'),
      ),
    ).thenAnswer((_) async => days);
  }

  /// Watches, awaits, and releases the listener — mirrors
  /// `bookings_day_notifier_test.dart`'s `visit` helper (same
  /// `Timer(Duration.zero)` reasoning: a bare `await` on an already-resolved
  /// Future is not enough to let Riverpod's scheduler run its
  /// eviction/disposal check).
  Future<void> visit(ProviderContainer container) async {
    final ProviderSubscription<AsyncValue<Set<DateTime>>> sub = container
        .listen(bookedDaysProvider, (_, _) {});
    await container.read(bookedDaysProvider.future);
    sub.close();
    await Future<void>.delayed(Duration.zero);
  }

  group('bookedDaysProvider — session-boundary PII (mobile-security HIGH, '
      '2026-07-20)', () {
    test('a logout followed by a different account logging in forces a '
        'FRESH fetch — the previous account\'s booked days are never served '
        'to the next account (HIGH regression guard)', () async {
      stubBookedDays(<DateTime>[DateTime(2026, 7, 10)]);
      final result = await _containerWithAuth(
        repo,
        const AuthSession.authenticated(user: _master1, accessToken: 'token-1'),
      );

      // master-1 opens «Мої записи» — one fetch, pinned by the 30-minute
      // keepAlive TTL.
      await visit(result.container);

      // Logout: the session settles to Unauthenticated, exactly like
      // `AuthNotifier.logout` sets `state = AsyncData(unauthenticated())`.
      result.auth.setSession(const AuthSession.unauthenticated());
      // A different account logs in.
      stubBookedDays(<DateTime>[DateTime(2026, 7, 15)]);
      result.auth.setSession(
        const AuthSession.authenticated(user: _master2, accessToken: 'token-2'),
      );

      // master-2 opens the SAME screen. If the cached singleton (the missing
      // watch) were still being served, this would issue NO second request
      // and master-2 would see master-1's dots with no loading state — the
      // HIGH this test guards.
      final Set<DateTime> master2Days = await result.container.read(
        bookedDaysProvider.future,
      );

      verify(
        () => repo.getMyBookedDays(
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).called(2);
      expect(master2Days, <DateTime>{DateTime(2026, 7, 15)});
      expect(
        master2Days.contains(DateTime(2026, 7, 10)),
        isFalse,
        reason: "master-1's booked day must not leak into master-2's set",
      );
    });

    test('a silent token refresh for the SAME account does NOT evict the '
        'cache — proves the authProvider watch is narrowed to the user id, '
        'not the whole session', () async {
      stubBookedDays(<DateTime>[DateTime(2026, 7, 10)]);
      final result = await _containerWithAuth(
        repo,
        const AuthSession.authenticated(user: _master1, accessToken: 'token-1'),
      );

      await visit(result.container);

      // A silent refresh (`AuthNotifier.setAccessToken`'s production
      // behaviour): SAME user, a NEW accessToken.
      result.auth.setSession(
        const AuthSession.authenticated(
          user: _master1,
          accessToken: 'token-1-refreshed',
        ),
      );

      await visit(result.container);

      verify(
        () => repo.getMyBookedDays(
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).called(1);
    });

    test('an ACTIVELY WATCHED listener at the moment of logout is '
        'force-refetched, not left serving the previous account\'s '
        'AsyncData (the realistic "master is looking at the rail when the '
        'session ends" scenario)', () async {
      stubBookedDays(<DateTime>[DateTime(2026, 7, 10)]);
      final result = await _containerWithAuth(
        repo,
        const AuthSession.authenticated(user: _master1, accessToken: 'token-1'),
      );

      final ProviderSubscription<AsyncValue<Set<DateTime>>> sub = result
          .container
          .listen(bookedDaysProvider, (_, _) {});
      await result.container.read(bookedDaysProvider.future);
      expect(result.container.read(bookedDaysProvider).value, <DateTime>{
        DateTime(2026, 7, 10),
      });

      stubBookedDays(<DateTime>[DateTime(2026, 7, 22)]);
      result.auth.setSession(const AuthSession.unauthenticated());
      result.auth.setSession(
        const AuthSession.authenticated(user: _master2, accessToken: 'token-2'),
      );

      // The listener never closed — this is `invalidateSelf()`'s "actively
      // watched" branch, which queues a REFRESH on the next scheduler turn
      // rather than a disposal.
      await Future<void>.delayed(Duration.zero);
      await result.container.read(bookedDaysProvider.future);

      expect(
        result.container.read(bookedDaysProvider).value,
        <DateTime>{DateTime(2026, 7, 22)},
        reason:
            'the still-mounted listener must observe master-2\'s days, not '
            'master-1\'s stale AsyncData',
      );
      sub.close();
    });
  });
}
