// ITEM 1 (this track, mobile-debugger) — CONFIRMED reproducible
// `ProviderSubscription`-closed crash via
// `invalidateBookingViewsAfterProviderClose`, the SAME crash class
// `bookings_discovery_view_reschedule_pin_race_test.dart` pins for
// `invalidateBookingsDayAfterAppointmentItemReschedule`.
//
// THE OLD BUG THIS FILE PINS
// ----------------------------
// `invalidateBookingViewsAfterProviderClose` used to invalidate the WHOLE
// `bookingsDayProvider` family (`ref.invalidate(bookingsDayProvider);`, no
// query argument) after a provider decline/complete — see
// `booking_calendar_invalidation.dart`'s FIX B doc. That meant declining ANY
// booking, regardless of which day it belonged to, raced EVERY LRU-pinned
// day, not just the one the decline actually touched.
//
// REACHABLE IN TWO TAPS
// -----------------------
// View day D (pins D) → view day E (D becomes pinned-but-unwatched) → open a
// booking dated D from `MasterArchiveScreen` (which lists across every day,
// unlike the day-rail list) → decline it → rail-tap back to D.
//
// THIS FILE'S SCOPE: the mechanism, not the archive screen's own UI. Steps
// 1-2 (pin D, swap to E) drive the REAL `BookingsDiscoveryView` — identical
// setup to the reschedule sibling. Step 4 (the decline) calls the REAL
// `invalidateBookingViewsAfterProviderClose(ref, bookingId, affectedDate: D)`
// through a real `WidgetRef` on the covering route — the SAME extracted-
// function precedent the reschedule sibling and its own FIX A test use,
// rather than driving `MasterArchiveScreen`'s full row-tap → confirm-dialog →
// decline chain, which would duplicate that screen's own (already covered
// elsewhere) test surface for no additional proof of THIS mechanism.
//
// AFTER THE FIX: `affectedDate` scopes the invalidation to D's own
// `bookingsDayProvider` members, gated on `DayKeepAliveLru.contains` with an
// eager `ref.read` back when D was genuinely pinned — the exact idiom this
// track's other three fixes share.

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

// Same pinned-clock convention as the reschedule sibling — mixing a bare
// `DateTime.now()` fixture with a pinned `clockProvider` is the recurring
// timezone defect in this repo (invisible on a Kyiv-zoned dev host).
//
// FIXED, not `futureBookingStart()` (mobile-debugger, this track,
// 2026-08-24) — see `master_create_booking_pin_race_test.dart`'s identical
// note for the full mechanism: `futureBookingStart()` re-derives `_dayD`
// from the REAL host clock every run, so the rail's chip geometry — and
// therefore whether `reselectD`'s tap lands on-screen — silently varied by
// the calendar date the suite happened to run on. A fixed PAST literal needs
// no `// future-date-ok:`: [_dayD] is only used for CALENDAR identity here
// (this file's bookings never go through `BookingDisplayX.isPast`), never as
// an "upcoming" fixture.
final DateTime _fixedNow = DateTime.utc(2024, 3, 12, 9);
final DateTime _dayD = kyivToday(() => _fixedNow);
final DateTime _dayE = () {
  final DateTime monday = mondayOf(_dayD);
  return monday.isAtSameMomentAs(_dayD)
      ? monday.add(const Duration(days: 1))
      : monday;
}();

const String _bookingId = 'booking-on-d';

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
    // Opaque and full-screen — mirrors `MasterArchiveScreen` covering the day
    // list, and where this test performs the EXACT provider-close
    // invalidation via a real `WidgetRef`.
    GoRoute(
      path: '/archive',
      builder: (BuildContext context, GoRouterState state) => Scaffold(
        body: Consumer(
          builder: (BuildContext context, WidgetRef ref, _) => Center(
            child: TextButton(
              key: const Key('run-provider-close-invalidation'),
              onPressed: () => invalidateBookingViewsAfterProviderClose(
                ref,
                _bookingId,
                affectedDate: _dayD,
              ),
              child: const Text('decline'),
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

  /// Steps 1-2: pump the day list on D, tap over to E (D becomes
  /// pinned-but-unwatched via `DayKeepAliveLru`).
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

    await tester.tap(find.byKey(dayChipKey(_dayE)));
    // fixed-wait-ok: waits out the REAL 220ms rail-tap debounce timer.
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

  /// Step 6: re-tap D's rail chip and wait out the real debounce.
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
    'declining a booking dated D from a DIFFERENT (archive-shaped) route, '
    'while D is pinned-but-unwatched, then re-selecting D on the rail after '
    'popping back, throws NO FlutterError and reaches a data/empty state '
    'within a bounded pump budget',
    (tester) async {
      final GoRouter router = await pinD(tester);

      await expectKeepAlivePinRaceClosed(
        tester,
        router,
        coverRouteKey: '/archive',
        invalidate: () => tester.tap(
          find.byKey(const Key('run-provider-close-invalidation')),
        ),
        reestablishWatch: () => reselectD(tester),
        loadingFinder: find.byKey(const Key('master-bookings-skeleton')),
        resolvedFinder: find.byKey(const Key('master-bookings-empty')),
      );

      expect(find.byKey(const Key('my_bookings_error')), findsNothing);
    },
  );
}
