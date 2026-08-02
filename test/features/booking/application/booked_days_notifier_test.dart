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

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/booked_days_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_day_rail.dart'
    show calendarDayCount;
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:timezone/timezone.dart' as tz;

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
///
/// [clock] optionally overrides `clockProvider` — used by the Kyiv-anchoring
/// regression group below to pin the device's "now" to an instant observed
/// from a specific device zone. `null` leaves the provider's own
/// [DateTime.now] default in place, matching production.
Future<({ProviderContainer container, _MutableAuthNotifier auth})>
_containerWithAuth(
  BookingRepository repo,
  AuthSession initialAuth, {
  DateTime Function()? clock,
}) async {
  final auth = _MutableAuthNotifier(initialAuth);
  final container = ProviderContainer(
    retry: beauticaProviderRetry,
    overrides: <Object>[
      bookingRepositoryProvider.overrideWithValue(repo),
      authProvider.overrideWith(() => auth),
      if (clock != null) clockProvider.overrideWithValue(clock),
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
        cancelToken: any(named: 'cancelToken'),
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
          cancelToken: any(named: 'cancelToken'),
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
          cancelToken: any(named: 'cancelToken'),
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

  group('bookedDaysProvider — failure path, ±180-day bounds, dateOnly '
      'normalisation, and CancelToken disposal', () {
    test('a failing fetch surfaces as an AsyncError carrying the mapped '
        'Failure — not just hasError', () async {
      when(
        () => repo.getMyBookedDays(
          from: any(named: 'from'),
          to: any(named: 'to'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((_) async => throw const NetworkFailure());

      final result = await _containerWithAuth(
        repo,
        const AuthSession.authenticated(user: _master1, accessToken: 'token-1'),
      );

      result.container.listen(bookedDaysProvider, (_, _) {});
      result.container.read(bookedDaysProvider);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final AsyncValue<Set<DateTime>> state = result.container.read(
        bookedDaysProvider,
      );
      expect(state.hasError, isTrue);
      expect(state.error, isA<NetworkFailure>());
    });

    test('requests the inclusive ±kBookedDaysSpanDays window at LOCAL '
        'MIDNIGHT via calendar arithmetic — the property a Duration-based '
        'offset violates across a Kyiv DST transition', () async {
      late DateTime capturedFrom;
      late DateTime capturedTo;
      when(
        () => repo.getMyBookedDays(
          from: any(named: 'from'),
          to: any(named: 'to'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((Invocation invocation) async {
        capturedFrom = invocation.namedArguments[#from] as DateTime;
        capturedTo = invocation.namedArguments[#to] as DateTime;
        return const <DateTime>[];
      });

      final result = await _containerWithAuth(
        repo,
        const AuthSession.authenticated(user: _master1, accessToken: 'token-1'),
      );
      await visit(result.container);

      // Kyiv-anchored (backlog :226): production now derives "today" via
      // kyivToday(ref.read(clockProvider)), which — since clockProvider is
      // NOT overridden in this test — resolves to kyivDayOf(DateTime.now()).
      // The oracle here must match that exactly, not the device's raw day,
      // or this assertion is host-TZ-dependent instead of a real pin (caught
      // by the TZ=Asia/Tokyo sweep, 2026-08-02).
      final DateTime today = kyivDayOf(DateTime.now());
      final DateTime expectedFrom = DateTime(
        today.year,
        today.month,
        today.day - kBookedDaysSpanDays,
      );
      final DateTime expectedTo = DateTime(
        today.year,
        today.month,
        today.day + kBookedDaysSpanDays,
      );

      // The exact calendar-arithmetic value.
      expect(capturedFrom, expectedFrom);
      expect(capturedTo, expectedTo);

      // LOCAL MIDNIGHT — `DateTime(y, m, d ± n)` always normalises to
      // midnight; `today.subtract(Duration(days: n))` does NOT when the
      // subtracted span crosses a DST transition (it lands on 23:00/01:00
      // instead). This assertion holds unconditionally for the calendar-
      // arithmetic implementation, on every day of the year, which is what
      // makes it the right thing to pin rather than the raw equality above
      // (which a `Duration`-based mutation could still coincidentally
      // satisfy if the mutant happened to land on midnight on a day no DST
      // boundary is crossed).
      expect(capturedFrom.hour, 0);
      expect(capturedFrom.minute, 0);
      expect(capturedFrom.second, 0);
      expect(capturedTo.hour, 0);
      expect(capturedTo.minute, 0);
      expect(capturedTo.second, 0);

      // Inclusive span is 2*180 = 361 days start-to-end minus one for the
      // fencepost — i.e. exactly `2 * kBookedDaysSpanDays` CALENDAR days
      // between `from` and `to`, comfortably under the backend's 366-day
      // cap. Counted with `calendarDayCount` (DST-safe, re-anchors in UTC)
      // — never `.difference().inDays`, which truncates across a Kyiv DST
      // transition and would silently read one day short.
      expect(
        calendarDayCount(capturedFrom, capturedTo),
        2 * kBookedDaysSpanDays,
      );

      // HONESTY NOTE on discriminating power: whether the midnight
      // assertions above actually go RED under a
      // `today.subtract(Duration(days: kBookedDaysSpanDays))` mutation
      // depends on whether TODAY's ±180-day window happens to cross a
      // Europe/Kyiv DST transition (last Sunday of March / October) — it is
      // not literally guaranteed for every possible "today" a future test
      // run could see. In practice the ±180-day (361-day) window is close
      // to a full calendar year, so it crosses at least one of the two
      // yearly transitions for the overwhelming majority of dates (see
      // `bookings_day_rail.dart`'s `calendarDayCount` doc for the identical
      // reasoning) — verified for the date this test was written against
      // (2026-07-22, whose ±180-day window spans 2026-01-23..2027-01-18 and
      // crosses both the 2026-03-29 and 2026-10-25 transitions). The
      // narrow band of dates where the window crosses neither transition is
      // the one case this test cannot discriminate for; there is no way to
      // close that gap without an injectable clock in production, which is
      // out of scope for a test-only change.
    });

    test(
      'the repository response\'s stray time-of-day components are '
      'normalised away via dateOnly, so a date-only key hits the Set',
      () async {
        // A stub REPOSITORY RESPONSE value (data flowing INTO the system
        // under test), not a device-clock anchor — the assertion only checks
        // that dateOnly() strips y/m/d, which is host-TZ-independent: a local
        // DateTime's own .year/.month/.day always echo back exactly what was
        // constructed, on any host TZ.
        // host-tz-ok: repository-response stub value, not a device-clock anchor
        stubBookedDays(<DateTime>[DateTime(2026, 7, 10, 13, 45, 30)]);
        final result = await _containerWithAuth(
          repo,
          const AuthSession.authenticated(
            user: _master1,
            accessToken: 'token-1',
          ),
        );

        final Set<DateTime> days = await result.container.read(
          bookedDaysProvider.future,
        );

        expect(days, <DateTime>{DateTime(2026, 7, 10)});
        expect(
          days.contains(DateTime(2026, 7, 10)),
          isTrue,
          reason: 'a date-only membership probe must hit the normalised key',
        );
        expect(
          // Same stub-response value as above (see the preceding
          // stubBookedDays call), re-probed to prove the RAW stray-time key
          // misses the Set.
          // host-tz-ok: repository-response stub value, not a device-clock anchor
          days.contains(DateTime(2026, 7, 10, 13, 45, 30)),
          isFalse,
          reason:
              'the Set key must be date-only — the raw stray-time value from '
              'the repo must not be what actually got stored',
        );
      },
    );

    test(
      'disposing the provider element cancels the in-flight request — '
      'ref.onDispose(cancelToken.cancel) (mobile-perf LOW, 2026-07-22)',
      () async {
        final Completer<List<DateTime>> gate = Completer<List<DateTime>>();
        CancelToken? capturedToken;
        when(
          () => repo.getMyBookedDays(
            from: any(named: 'from'),
            to: any(named: 'to'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer((Invocation invocation) {
          capturedToken =
              invocation.namedArguments[#cancelToken] as CancelToken?;
          return gate.future;
        });

        final result = await _containerWithAuth(
          repo,
          const AuthSession.authenticated(
            user: _master1,
            accessToken: 'token-1',
          ),
        );

        final ProviderSubscription<AsyncValue<Set<DateTime>>> sub = result
            .container
            .listen(bookedDaysProvider, (_, _) {});
        result.container.read(bookedDaysProvider);
        // Let the request actually reach the repo (the mock's `when` above)
        // before the element is disposed — the gate future never resolves, so
        // the fetch stays genuinely in flight throughout this test.
        await Future<void>.delayed(Duration.zero);

        expect(capturedToken, isNotNull);
        expect(
          capturedToken!.isCancelled,
          isFalse,
          reason: 'must not already be cancelled while genuinely in flight',
        );

        // Explicit disposal — NOT relying solely on `_containerWithAuth`'s own
        // `addTearDown`, since the assertion below must run AFTER disposal.
        // `ProviderContainer.dispose()` is documented safe to call more than
        // once ("Subsequent calls will be no-op"), so the `addTearDown`
        // registered inside `_containerWithAuth` firing again at test end is
        // harmless.
        sub.close();
        result.container.dispose();

        expect(
          capturedToken!.isCancelled,
          isTrue,
          reason:
              'ref.onDispose(cancelToken.cancel) must fire when the element '
              'is disposed, aborting the still-pending ±180-day sweep',
        );
      },
    );
  });

  group('bookedDaysProvider — Kyiv-anchored "today" (mobile-dev, 2026-08-02, '
      'backlog :226 clockProvider half)', () {
    test(
      'the fetched from/to window is anchored to the KYIV day, not the '
      "device's own calendar day, when the device sits in Asia/Tokyo",
      () async {
        initBeauticaTimeZones();

        // 2026-08-02 05:00 in Asia/Tokyo (UTC+9, no DST) is 2026-08-01
        // 20:00Z, which is 2026-08-01 23:00 Kyiv (EEST, +3) — a full Kyiv day
        // EARLIER than the device's own calendar day. `bookedDaysProvider`
        // must anchor its ±180-day window on the KYIV day (Aug 1), not the
        // device's (Aug 2) — the backend interprets `from`/`to` as Kyiv civil
        // days (`atStartOfDay(TimeZones.KYIV)`), so a device-day-anchored
        // window would silently request the wrong 361-day span.
        final tz.TZDateTime deviceInstant = tz.TZDateTime(
          tz.getLocation('Asia/Tokyo'),
          2026,
          8,
          2,
          5,
          0,
        );

        late DateTime capturedFrom;
        late DateTime capturedTo;
        when(
          () => repo.getMyBookedDays(
            from: any(named: 'from'),
            to: any(named: 'to'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer((Invocation invocation) async {
          capturedFrom = invocation.namedArguments[#from] as DateTime;
          capturedTo = invocation.namedArguments[#to] as DateTime;
          return const <DateTime>[];
        });

        final result = await _containerWithAuth(
          repo,
          const AuthSession.authenticated(
            user: _master1,
            accessToken: 'token-1',
          ),
          clock: () => deviceInstant,
        );
        await visit(result.container);

        final DateTime kyivToday = DateTime(2026, 8, 1);
        final DateTime deviceToday = DateTime(2026, 8, 2);

        expect(
          capturedFrom,
          DateTime(
            kyivToday.year,
            kyivToday.month,
            kyivToday.day - kBookedDaysSpanDays,
          ),
        );
        expect(
          capturedTo,
          DateTime(
            kyivToday.year,
            kyivToday.month,
            kyivToday.day + kBookedDaysSpanDays,
          ),
        );

        // Negative-space assertion: the DEVICE's own calendar day (Tokyo,
        // Aug 2) must never leak through as the anchor — this is the exact
        // shape of window a `dateOnly(DateTime.now())` regression would send.
        expect(
          capturedTo,
          isNot(
            DateTime(
              deviceToday.year,
              deviceToday.month,
              deviceToday.day + kBookedDaysSpanDays,
            ),
          ),
        );
      },
    );
  });
}
