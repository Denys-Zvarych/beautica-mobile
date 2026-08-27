// FIX A regression (mobile-debugger, this session) — CONFIRMED, empirically
// reproduced crash: "Bad state: ProviderSubscription.read on a subscription
// that was closed" surfacing inside `bookings_discovery_view.dart`'s
// `Consumer` (`:872-877`), with a silent twin — the SAME throw absorbed by
// Flutter's per-`Element` error boundary, leaving the day's loading skeleton
// stuck forever instead of a visible red screen.
//
// USER SYMPTOM THIS REPRODUCES
// -----------------------------
// After rescheduling a walk-in booking to a day with no other bookings,
// opening that day's time grid sometimes shows a red error screen; more
// often the grid stays on skeleton placeholders forever.
//
// THE MECHANISM (see `booking_calendar_invalidation.dart`'s
// `invalidateBookingsDayAfterAppointmentItemReschedule` doc for the full
// citation-backed explanation)
// -----------------------------------------------------------------------
// `booking_confirm_screen.dart`'s per-item VISIT reschedule branch
// invalidates the NEW and OLD day's `bookingsDayProvider` family members.
// When the invalidated day is alive ONLY via `DayKeepAliveLru`'s bounded
// keepAlive — the master glanced at it earlier this session, then scrubbed
// the rail away ("pinned-but-unwatched") — a BARE `ref.invalidate` leaves
// the element's disposal racing whatever widget rebuild next `ref.watch`es
// the same query. This file drives that EXACT sequence through the real
// `BookingsDiscoveryView` + the real extracted invalidation function (never
// a hand-copied approximation of it, so this test cannot drift from
// production behaviour) and asserts the race is closed.
//
// THE RECIPE (spec'd by the investigation)
// -----------------------------------------
//   1. Pre-warm day D — visit it — so `DayKeepAliveLru` pins it.
//   2. Navigate away WITHIN `BookingsDiscoveryView` (tap a different rail
//      day) so D's `Consumer` subscription is closed — D is now
//      pinned-but-unwatched, exactly the LRU-only state the mechanism above
//      requires.
//   3. Cover `BookingsDiscoveryView` with an opaque route (mirrors
//      `bookings_day_covered_route_recovery_test.dart`'s precedent for why
//      the cover is the mechanism, not set dressing).
//   4. Run the EXACT scoped invalidation
//      `invalidateBookingsDayAfterAppointmentItemReschedule` performs for
//      `{D, oldDay}` — the same function `booking_confirm_screen.dart` calls,
//      via a real `WidgetRef`.
//   5. Pop back.
//   6. Tap day D's rail chip (`dayChipKey(D)`) again.
//   7. Assert NO `FlutterError` was thrown, and the day resolves to a
//      data/empty state within a BOUNDED pump budget — never
//      `pumpAndSettle` (the skeleton's repeating shimmer never settles).
//
// Both an immediate-tap and a double-tap timing are covered, since the
// investigation found fast-vs-slow tapping is NOT the deciding variable —
// only a multiplier on how many attempts hit the same race.
//
// ITEM 7 (this track) — steps 3-7 above are now the SHARED invariant tail
// `test/helpers/keepalive_pin_race_harness.dart`'s `expectKeepAlivePinRaceClosed`
// runs; this file keeps only steps 1-2 (`pinD`, below — pin D, swap to E) and
// step 6's family-specific action (`() => _reselectD(tester)`) as its own
// closures. Rewired onto the shared helper as proof the extraction is
// behaviour-preserving — both tests below are BYTE-IDENTICAL in what they
// assert, only the plumbing moved.

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

import '../../../helpers/keepalive_pin_race_harness.dart';
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

// ONE clock, pinned, shared by the fixtures and the widget — mixing a bare
// `DateTime.now()` fixture with a pinned `clockProvider` is the recurring
// timezone defect in this repo (invisible on a Kyiv-zoned dev host).
//
// FIXED, not `futureBookingStart()` (mobile-debugger, this track,
// 2026-08-24) — see `master_create_booking_pin_race_test.dart`'s identical
// note for the full mechanism: `futureBookingStart()` re-derives `_dayD`
// from the REAL host clock every run, so the rail's chip geometry — and
// therefore whether `reselectD`'s tap lands on-screen — silently varied by
// the calendar date the suite happened to run on (CI red on 2026-08-23, 2 of
// this file's 2 tests). A fixed PAST literal needs no `// future-date-ok:`:
// [_dayD] is only used for CALENDAR identity here (this file's bookings
// never go through `BookingDisplayX.isPast`), never as an "upcoming"
// fixture.
final DateTime _fixedNow = DateTime.utc(2024, 3, 12, 9);
final DateTime _dayD = kyivToday(() => _fixedNow);
// Guaranteed to share D's Monday-first rail week (unlike a bare `+1 day`,
// which silently crosses into the NEXT page whenever D lands on a Sunday —
// `mondayOf(D)` itself, unless D already IS that Monday, in which case the
// Tuesday right after it) — so no rail paging is needed to reach it, and the
// chip is always on the page already built.
final DateTime _dayE = () {
  final DateTime monday = mondayOf(_dayD);
  return monday.isAtSameMomentAs(_dayD)
      ? monday.add(const Duration(days: 1))
      : monday;
}();

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
    // Opaque and full-screen — mirrors the confirm screen's own route shape.
    // Also where this test performs the EXACT scoped invalidation, via a
    // real `WidgetRef` reached through a `Consumer`.
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
                    affectedDays: <DateTime>{_dayD, _dayE},
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

  setUp(() {
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

  /// Runs steps 1-2 of the recipe ONLY: pump the day list on D, tap over to
  /// E (D becomes pinned-but-unwatched). Step 3 (cover) now lives inside
  /// `expectKeepAlivePinRaceClosed` (ITEM 7 — ported onto the shared harness).
  Future<GoRouter> pinD(WidgetTester tester) async {
    final GoRouter router = _router();
    await tester.pumpRoutedApp(
      router,
      overrides: <Object>[
        screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
        bookingRepositoryProvider.overrideWithValue(repo),
        bookedDaysProvider.overrideWith((ref) async => <DateTime>{}),
        clockProvider.overrideWithValue(() => _fixedNow),
        authProvider.overrideWith(_StubAuth.new),
      ],
    );
    await tester.pumpUntilGone(
      find.byKey(const Key('master-bookings-skeleton')),
    );
    expect(
      find.byKey(const Key('master-bookings-empty')),
      findsOneWidget,
      reason: 'sanity: D loaded to an empty (not error/skeleton) state',
    );

    // --- switch the rail to E: D's Consumer subscription is now closed,
    // --- but D stays pinned via DayKeepAliveLru (≤3-slot budget, only one
    // --- slot used so far).
    await tester.tap(find.byKey(dayChipKey(_dayE)));
    // fixed-wait-ok: waits out the REAL 220ms rail-tap debounce timer
    // (`bookings_discovery_view.dart`'s `_dayDebounce`) before `_liveQuery`
    // switches to E — a time-based debounce, not a state change, so there is
    // nothing to `pumpUntilFound` against until it elapses.
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pumpUntilGone(
      find.byKey(const Key('master-bookings-skeleton')),
    );
    expect(
      find.byKey(const Key('master-bookings-empty')),
      findsOneWidget,
      reason: 'sanity: E loaded — D is now unwatched, not merely paused',
    );

    return router;
  }

  /// Step 6, family-specific: re-tap D's rail chip and wait out the real
  /// 220ms debounce.
  ///
  /// The leading `pump(300ms)` (mobile-debugger, this track, 2026-08-24) —
  /// see `master_create_booking_pin_race_test.dart`'s identical note for the
  /// full mechanism — settles the POP's own route transition (go_router's
  /// default `MaterialPage`, platform default 300ms) before touching
  /// anything: `expectKeepAlivePinRaceClosed`'s step 5 pops with exactly ONE
  /// zero-duration `pump()`, which left the day rail's `PageView` painted at
  /// a stale scroll offset when `tap()` computed the chip's hit-test centre.
  /// Safe here specifically: the day list shows E's already-resolved EMPTY
  /// state at this point, never a skeleton, so there is no repeating
  /// animation a longer pump could get stuck behind.
  Future<void> reselectD(WidgetTester tester) async {
    // fixed-wait-ok: waits out go_router's default MaterialPage pop
    // transition (platform default 300ms) so the day rail settles to its
    // real post-pop geometry before this tap computes a hit-test centre.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(dayChipKey(_dayD)));
    // fixed-wait-ok: waits out the same real 220ms rail-tap debounce.
    await tester.pump(const Duration(milliseconds: 260));
  }

  testWidgets(
    'invalidating a pinned-but-unwatched day, then re-selecting it on the '
    'rail after popping back, throws NO FlutterError and reaches a '
    'data/empty state within a bounded pump budget (immediate tap)',
    (tester) async {
      final GoRouter router = await pinD(tester);

      await expectKeepAlivePinRaceClosed(
        tester,
        router,
        coverRouteKey: '/confirm',
        invalidate: () =>
            tester.tap(find.byKey(const Key('run-reschedule-invalidation'))),
        reestablishWatch: () => reselectD(tester),
        loadingFinder: find.byKey(const Key('master-bookings-skeleton')),
        resolvedFinder: find.byKey(const Key('master-bookings-empty')),
      );

      expect(find.byKey(const Key('my_bookings_error')), findsNothing);
    },
  );

  testWidgets(
    'the same recipe survives a DOUBLE tap on the rail chip after popping '
    'back — fast tapping only multiplies attempts at the same race, it is '
    'not what causes it',
    (tester) async {
      final GoRouter router = await pinD(tester);

      await expectKeepAlivePinRaceClosed(
        tester,
        router,
        coverRouteKey: '/confirm',
        invalidate: () =>
            tester.tap(find.byKey(const Key('run-reschedule-invalidation'))),
        reestablishWatch: () async {
          // fixed-wait-ok: settles the pop's own route transition (go_router's
          // default MaterialPage, platform default 300ms) BEFORE either tap —
          // see `reselectD`'s doc above for why this is needed and safe here.
          // The "no settle BETWEEN the two taps" property this test exists
          // to prove is unaffected: this pump runs once, before both taps,
          // not between them.
          await tester.pump(const Duration(milliseconds: 300));
          // Two taps with no settle between them.
          await tester.tap(find.byKey(dayChipKey(_dayD)));
          // fixed-wait-ok: a deliberately UNSETTLED gap between the two taps
          // — shorter than the 220ms debounce on purpose, to prove the
          // SECOND tap (not a settled revisit) hits the same race.
          await tester.pump(const Duration(milliseconds: 20));
          await tester.tap(find.byKey(dayChipKey(_dayD)));
          // fixed-wait-ok: waits out the real 220ms rail-tap debounce.
          await tester.pump(const Duration(milliseconds: 260));
        },
        loadingFinder: find.byKey(const Key('master-bookings-skeleton')),
        resolvedFinder: find.byKey(const Key('master-bookings-empty')),
      );

      expect(find.byKey(const Key('my_bookings_error')), findsNothing);
    },
  );
}
