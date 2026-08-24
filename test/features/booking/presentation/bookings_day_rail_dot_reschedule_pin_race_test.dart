// mobile-qa fix (this track) — closes a gap `mobile-perf` raised against the
// `bookedDaysProvider` invalidation the mobile-debugger fix added to
// `invalidateBookingsDayAfterAppointmentItemReschedule`
// (`booking_calendar_invalidation.dart:524`).
//
// THE GAP
// -------
// `booking_calendar_invalidation_test.dart`'s own new test for that call
// proves the refetch fires — but ONLY under a LIVE, unpaused subscription
// held throughout. That is not this call path's actual shape: on the real
// path (`booking_confirm_screen.dart:312` invalidates, then
// `pushReplacement`s to the success screen), the `Consumer` that watches
// `bookedDaysProvider` — `bookings_discovery_view.dart:1037` — sits further
// down the navigation stack, COVERED and therefore PAUSED (Riverpod 3 treats
// a paused consumer as zero active listeners for `mayNeedDispose`).
// `booked_days_notifier.dart`'s own file header confirms the consequence:
// `invalidateSelf()` "queues either disposal (no active listener) or a
// rebuild (an active one)" — so on THIS call path the provider is DROPPED,
// not eagerly refetched, and the fresh fetch only lands once the master
// actually resumes the rail. Neither existing test proves the dot survives
// THAT trip: the unit test never covers the screen, and
// `bookings_day_rail_test.dart` only proves "given fresh data, render the
// dot" — it never drives an invalidation through a paused/resumed provider
// at all.
//
// WHY NOT `keepalive_pin_race_harness.dart`
// -------------------------------------------
// Reuse was considered first (REUSE-FIRST). The shared harness's contract
// (`expectKeepAlivePinRaceClosed`) is built around a family member keyed by
// `DayKeepAliveLru` — it needs a [loadingFinder] (a skeleton) that is
// present going in and must disappear, plus a same-shape "swap to a
// different key" step to make the ORIGINAL key pinned-but-unwatched before
// the cover. `bookedDaysProvider` is a filter-independent SINGLETON with no
// per-key skeleton of its own (`bookings_discovery_view.dart:1037-1039`
// falls back to `.value ?? const <DateTime>{}` — the dot set only ever goes
// stale-then-fresh, never through a distinct loading widget the rail
// renders), and it is paused by merely covering the WHOLE screen, not by a
// same-screen rail-tap swap. Forcing this shape through the harness's
// [loadingFinder]/[reestablishWatch] contract would mean passing a finder
// that never matches anything just to satisfy the signature — decoration,
// not reuse. The cover/invalidate/pop steps below are the same STRUCTURE as
// the harness (and as `bookings_discovery_view_reschedule_pin_race_test
// .dart`, which already covers the SAME call site for the `bookingsDayProvider`
// family half of this fan-out), just without forking the helper function
// itself.
//
// THE RECIPE
// ----------
//   1. Pump `BookingsDiscoveryView` on day D — `bookedDaysProvider` starts
//      empty, so D's rail chip carries NO dot (sanity).
//   2. Cover with an opaque route (mirrors the real confirm → success
//      transition) — the screen's `Consumer` is now paused.
//   3. Run the EXACT production invalidation,
//      `invalidateBookingsDayAfterAppointmentItemReschedule(ref,
//      affectedDays: {D})`, through a real `WidgetRef` on the covering
//      route — same extracted-function precedent every sibling in this
//      track uses.
//   4. Pop back — the `Consumer` resumes.
//   5. Assert the dot APPEARS on D within a bounded pump budget (never
//      `pumpAndSettle`).
//
// MUTATION-VERIFIED: with `ref.invalidate(bookedDaysProvider);` deleted from
// `invalidateBookingsDayAfterAppointmentItemReschedule`, this test times out
// waiting for the dot (see the qa audit for the exact failure text) —
// confirming it is load-bearing for the paused-path shape, not just the
// live-subscriber shape the unit test already pins.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/booked_days_notifier.dart';
import 'package:beautica_mobile/features/booking/application/booking_calendar_invalidation.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/bookings_day_query.dart';
import 'package:beautica_mobile/features/booking/presentation/bookings_discovery_view.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_day_rail.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';

import '../../../helpers/booking_fixture_dates.dart';
import '../../../helpers/pump_app.dart';

class _MockBookingRepository extends Mock implements BookingRepository {}

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

class _StubAuth extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.authenticated(
    user: User(
      id: 'master-1',
      email: 'master1@beautica.ua',
      role: UserRole.independentMaster,
    ),
    accessToken: 't',
  );
}

// ONE clock, pinned, shared by the fixture and the widget — mixing a bare
// `DateTime.now()` fixture with a pinned `clockProvider` is the recurring
// timezone defect in this repo (invisible on a Kyiv-zoned dev host).
final DateTime _fixedNow = futureBookingStart();
final DateTime _dayD = kyivToday(() => _fixedNow);

GoRouter _router() => GoRouter(
  initialLocation: '/day',
  routes: <RouteBase>[
    GoRoute(
      path: '/day',
      builder: (BuildContext context, GoRouterState state) => Scaffold(
        body: BookingsDiscoveryView(
          query: BookingsDayQuery.of(day: _dayD),
          title: 'Мої записи',
          onBookingTap: (Booking _) {},
        ),
      ),
    ),
    // Opaque and full-screen — mirrors `booking_confirm_screen.dart`'s own
    // route shape (a `pushReplacement` onto the success screen covers the
    // SAME way a `push` does for the purposes of Riverpod's offstage-pause).
    // Also where this test performs the EXACT scoped invalidation, through a
    // real `WidgetRef`.
    GoRoute(
      path: '/confirm',
      builder: (BuildContext context, GoRouterState state) => Scaffold(
        body: Consumer(
          builder: (BuildContext context, WidgetRef ref, _) => Center(
            child: TextButton(
              key: const Key('run-reschedule-invalidation'),
              onPressed: () =>
                  invalidateBookingsDayAfterAppointmentItemReschedule(
                    ref,
                    affectedDays: <DateTime>{_dayD},
                  ),
              child: const Text('invalidate'),
            ),
          ),
        ),
      ),
    ),
  ],
);

void main() {
  setUpAll(() {
    initBeauticaTimeZones();
    registerFallbackValue(<BookingStatus>{});
    registerFallbackValue(BookingSort.oldest);
  });

  late _MockBookingRepository repo;
  late int bookedDaysFetches;

  setUp(() {
    bookedDaysFetches = 0;
    repo = _MockBookingRepository();
    when(
      () => repo.getMyBookings(
        statuses: any(named: 'statuses'),
        serviceIds: any(named: 'serviceIds'),
        from: any(named: 'from'),
        to: any(named: 'to'),
        sort: any(named: 'sort'),
        page: any(named: 'page'),
        size: any(named: 'size'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer(
      (_) async => const PageResponse<Booking>(
        items: <Booking>[],
        page: 0,
        totalPages: 1,
        totalElements: 0,
      ),
    );
  });

  testWidgets(
    'a per-item VISIT reschedule invalidated while the day rail is COVERED '
    '(paused) still shows D\'s dot once the rail is RESUMED — the '
    'invalidate -> pause -> pop-back -> resume -> refetch -> dot-rendered '
    'chain the unit test\'s live-subscriber shape does not cover',
    (tester) async {
      final GoRouter router = _router();
      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[
          screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
          bookingRepositoryProvider.overrideWithValue(repo),
          // First fetch (the rail's own initial watch, before any
          // reschedule) returns D with NO booking. Every subsequent fetch —
          // reached only via the resumed rail refetching after invalidation
          // — returns D as booked. Mirrors the real shape: a walk-in
          // reschedule ONTO D is the thing that puts D in the set.
          bookedDaysProvider.overrideWith((ref) async {
            bookedDaysFetches++;
            return bookedDaysFetches == 1
                ? const <DateTime>{}
                : <DateTime>{_dayD};
          }),
          clockProvider.overrideWithValue(() => _fixedNow),
          authProvider.overrideWith(_StubAuth.new),
        ],
      );
      await tester.pumpUntilGone(
        find.byKey(const Key('master-bookings-skeleton')),
      );
      expect(
        find.byKey(dayDotKey(_dayD)),
        findsNothing,
        reason:
            'sanity: D starts with no dot — matches the reported "day '
            'has only 1 booking and it just moved onto it" starting state',
      );

      // --- cover: the rail's Consumer is now paused ------------------------
      unawaited(router.push('/confirm'));
      await tester.pumpAndSettle();

      // --- the EXACT production invalidation, through a real WidgetRef ----
      await tester.tap(find.byKey(const Key('run-reschedule-invalidation')));
      await tester.pump();

      // --- pop back: the Consumer resumes ----------------------------------
      router.pop();
      await tester.pump();

      // --- bounded budget, NEVER pumpAndSettle — the dot only appears once
      // --- the resumed provider's refetch completes.
      await tester.pumpUntilFound(find.byKey(dayDotKey(_dayD)));

      expect(
        find.byKey(dayDotKey(_dayD)),
        findsOneWidget,
        reason:
            'the day rail must show D\'s dot again once resumed — a stale '
            'dot here IS the user-reported "no dot when the day has only 1 '
            'booking and it\'s a manual booking" defect',
      );
      expect(
        bookedDaysFetches,
        greaterThanOrEqualTo(2),
        reason:
            'the resumed rail must have actually refetched, not merely '
            'kept rendering the first (stale) value',
      );
    },
  );
}
