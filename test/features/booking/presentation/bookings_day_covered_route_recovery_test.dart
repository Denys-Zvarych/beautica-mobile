// THE STUCK-SKELETON LIFECYCLE REGRESSION (user-reported 2026-08-20).
//
// THE JOURNEY THIS REPRODUCES
// ---------------------------
// Master is on «Мої записи» → pushes the «Новий запис» wizard OVER it →
// submits a manual walk-in → pops back → opens that date. The date showed the
// loading skeleton indefinitely: no grid, no cards, no error, nothing in the
// backend log.
//
// WHY THE COVER IS THE WHOLE MECHANISM, NOT SET DRESSING
// ------------------------------------------------------
// The wizard is a full-screen route, so the day list underneath it is COVERED
// for the entire submit, and Riverpod 3 PAUSES a covered consumer's
// subscriptions. A paused listener does not make an element active
// (`element.dart`: `isActive => (listenerCount - pausedActiveSubscriptionCount)
// > 0`) and `scheduler.dart::_performRefresh` only flushes ACTIVE elements
// before clearing its queue unconditionally — so the refresh that
// `MasterCreateBookingNotifier.submit`'s
// `invalidateBookingViewsAfterBookingCreated` queues is DROPPED rather than
// run. Recovery is not scheduler-driven at all: it works only because
// `invalidateSelf()` left `_mustRecomputeState = true` and the RESUMED
// consumer's `ref.watch` recomputes on pop-back.
//
// A test that merely unmounted the list and remounted it would exercise none
// of that — it would rebuild from scratch and pass no matter what. So this
// file pushes a real opaque route and asserts through the pop.
//
// (The route pushed is a lightweight placeholder rather than the wizard
// widget itself. The pause is a property of an OPAQUE route covering the one
// below, not of which widget that route builds, and the wizard's own UI is
// already covered end to end by
// `master_create_booking_screen_test.dart` and
// `integration_test/master_create_booking_test.dart`. What is NOT a
// placeholder here is the write: the REAL `MasterCreateBookingNotifier
// .submit` runs, so the real repository call and the real fan-out
// invalidation are what the day list has to recover from.)
//
// WHAT IS ASSERTED, AND WHY IN THAT FORM
// --------------------------------------
//   • The day list reaches a DATA state — the new card rendered, skeleton
//     gone, error state absent — within a BOUNDED pump budget. Not "no
//     exception was thrown": the defect threw nothing.
//   • A genuine refetch happened after the pop (call count), so a pass cannot
//     come from a stale cache that was never invalidated.
//   • When the refetch keeps failing transiently, the list reaches a
//     TERMINAL, ACTIONABLE error inside the same budget instead of shimmering.
//     That is the arm that goes RED on the pre-fix ~38 s retry curve.
//
// `pumpAndSettle` IS UNUSABLE ON THE LOADING BRANCH.
// --------------------------------------------------
// `BookingsSkeleton` drives `AnimationController.repeat(reverse: true)`
// (`my_bookings_states.dart:57`), so a frame is permanently scheduled while
// the skeleton is up and `pumpAndSettle` can never observe quiescence — it
// pumps until the test's own timeout and takes the file down with it (the
// hazard `scripts/forbid_results_bare_pump_and_settle.sh` exists for). Every
// wait after a state change here is `pumpUntilFound`/`pumpUntilGone`.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/booked_days_notifier.dart';
import 'package:beautica_mobile/features/booking/application/master_create_booking_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/bookings_day_query.dart';
import 'package:beautica_mobile/features/booking/domain/create_master_booking_request.dart';
import 'package:beautica_mobile/features/booking/presentation/bookings_discovery_view.dart';
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

// ---------------------------------------------------------------------------
// Clock — ONE clock, pinned, shared by the fixtures and the widget.
//
// `BookingsDiscoveryView.initState` derives its opening day from
// `kyivToday(ref.read(clockProvider))` and IGNORES `query.day`, so the fixture
// booking must fall on that same Kyiv day. Deriving both from `_fixedNow`
// keeps the fixture clock and the app clock the SAME clock — mixing a
// `DateTime.now()` fixture with a pinned `clockProvider` is the recurring
// timezone defect in this repo, invisible on a Kyiv-zoned dev host.
// ---------------------------------------------------------------------------
final DateTime _fixedNow = futureBookingStart();
final DateTime _day = kyivToday(() => _fixedNow);

DateTime _kyivAtUtc(int hour) =>
    tz.TZDateTime(beauticaZone, _day.year, _day.month, _day.day, hour).toUtc();

const String _kWalkInId = 'walkin-1';

Booking _walkIn() {
  final DateTime start = _kyivAtUtc(11);
  return Booking(
    id: _kWalkInId,
    masterId: 'master-1',
    masterFirstName: 'Оля',
    masterLastName: 'Коваль',
    masterType: 'INDEPENDENT_MASTER',
    // A guest/STAFF row: no `clientId`, no `clientAvatarUrl`, no
    // `appointmentId` — the server fills the name from the OTP-verified
    // guest fields. This is exactly the shape the walk-in POST produces.
    clientFirstName: 'Ірина',
    clientLastName: 'Шевченко',
    serviceId: 'svc-1',
    serviceName: 'Манікюр',
    durationMinutes: 60,
    price: 500,
    startAt: start,
    endAt: start.add(const Duration(minutes: 60)),
    status: BookingStatus.confirmed,
    canReview: false,
  );
}

final CreateMasterBookingRequest _request = CreateMasterBookingRequest(
  masterServiceId: 'svc-1',
  startsAt: _kyivAtUtc(11),
  guest: const WalkInGuest(
    name: 'Ірина',
    surname: 'Шевченко',
    phone: '+380501234567',
  ),
);

GoRouter _router() => GoRouter(
  initialLocation: '/day',
  routes: <RouteBase>[
    GoRoute(
      path: '/day',
      builder: (BuildContext context, GoRouterState state) => Scaffold(
        body: BookingsDiscoveryView(
          query: BookingsDayQuery.of(day: _day),
          title: 'Мої записи',
          onBookingTap: (Booking _) {},
        ),
      ),
    ),
    // Opaque and full-screen — the only two properties that make the route
    // below it PAUSE rather than merely rebuild.
    GoRoute(
      path: '/wizard',
      builder: (BuildContext context, GoRouterState state) =>
          const Scaffold(body: SizedBox.expand(key: Key('fake-wizard'))),
    ),
  ],
);

void main() {
  setUpAll(() {
    initBeauticaTimeZones();
    registerFallbackValue(<BookingStatus>{});
    registerFallbackValue(BookingSort.oldest);
    registerFallbackValue(_request);
  });

  late _MockBookingRepository repo;
  late List<Booking> dayRows;
  late int dayFetches;
  late Object? failDayFetchWith;

  setUp(() {
    repo = _MockBookingRepository();
    dayRows = <Booking>[];
    dayFetches = 0;
    failDayFetchWith = null;

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
      // ASYNCHRONOUS failure, never a synchronous `thenThrow`: a sync throw
      // during `build()` bypasses Riverpod's retry machinery entirely, so the
      // error arm below would assert a state real users never reach that way.
    ).thenAnswer((_) async {
      dayFetches++;
      final Object? err = failDayFetchWith;
      if (err != null) throw err;
      return PageResponse<Booking>(
        items: List<Booking>.of(dayRows),
        page: 0,
        totalPages: 1,
        totalElements: dayRows.length,
      );
    });

    when(() => repo.createMasterBooking(any(), any())).thenAnswer((_) async {
      // The server-side effect the master is waiting to see reflected.
      dayRows = <Booking>[_walkIn()];
      return _walkIn();
    });
  });

  Future<ProviderContainer> pumpDayList(
    WidgetTester tester,
    GoRouter router,
  ) async {
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
    return ProviderScope.containerOf(
      tester.element(find.byType(BookingsDiscoveryView)),
      listen: false,
    );
  }

  testWidgets('after a walk-in is submitted from a route COVERING the day '
      'list, popping back reaches a DATA state carrying the new booking — '
      'never a stuck skeleton', (tester) async {
    final GoRouter router = _router();
    final ProviderContainer container = await pumpDayList(tester, router);

    expect(
      find.byKey(const Key('master-bookings-empty')),
      findsOneWidget,
      reason: 'sanity: the day starts empty, so the card below is NEW',
    );
    final int fetchesBeforeSubmit = dayFetches;

    // --- cover the day list -------------------------------------------------
    unawaited(router.push('/wizard'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('fake-wizard')), findsOneWidget);
    // `skipOffstage: false` is the assertion, not a convenience: once the
    // pushed route's transition completes the day list is OFFSTAGE — mounted
    // but not painted. That is precisely the covered/paused state the defect
    // needs. A default (onstage-only) finder here would report `findsNothing`
    // and read as "unmounted", which is the opposite conclusion.
    expect(
      find.byType(BookingsDiscoveryView, skipOffstage: false),
      findsOneWidget,
      reason:
          'the day list must still be MOUNTED (and therefore paused) — if the '
          'push unmounted it, the pop would rebuild from scratch and this '
          'whole test would prove nothing',
    );

    // --- the real write, through the real notifier ---------------------------
    // `MasterCreateBookingNotifier.build` is `Future<void>`, so the FIRST read
    // leaves the notifier in `AsyncLoading` — and `submit` NO-OPS on
    // `state.isLoading` (its double-submit guard). Settling the idle build
    // first is what makes the submit below actually run; without it this test
    // would silently assert nothing.
    await container.read(masterCreateBookingProvider.future);
    await container
        .read(masterCreateBookingProvider.notifier)
        .submit(masterId: 'master-1', request: _request);
    await tester.pump();

    expect(
      dayFetches,
      fetchesBeforeSubmit,
      reason:
          'the invalidation lands on a PAUSED consumer, so nothing refetches '
          'while the wizard is on top — this is the mechanism, not a bug',
    );

    // --- pop back ------------------------------------------------------------
    router.pop();
    await tester.pump();

    // Bounded, and never `pumpAndSettle`: the skeleton's repeating shimmer
    // means the loading branch NEVER reaches quiescence.
    await tester.pumpUntilFound(
      find.byKey(const Key('master-booking-card-$_kWalkInId')),
    );

    expect(
      find.byKey(const Key('master-bookings-skeleton')),
      findsNothing,
      reason: 'THE DEFECT: the skeleton must not still be up',
    );
    expect(find.byKey(const Key('my_bookings_error')), findsNothing);
    expect(find.byKey(const Key('master-bookings-empty')), findsNothing);
    expect(
      dayFetches,
      greaterThan(fetchesBeforeSubmit),
      reason:
          'the resumed consumer must have RE-FETCHED — a pass served from the '
          'pre-submit cache would be the same false green that let this ship',
    );
  });

  testWidgets('when the post-pop refetch keeps failing transiently, the day '
      'reaches a TERMINAL retryable error inside a bounded budget — not an '
      'indefinite skeleton', (tester) async {
    final GoRouter router = _router();
    final ProviderContainer container = await pumpDayList(tester, router);

    unawaited(router.push('/wizard'));
    await tester.pumpAndSettle();

    await container.read(masterCreateBookingProvider.future);
    await container
        .read(masterCreateBookingProvider.notifier)
        .submit(masterId: 'master-1', request: _request);
    await tester.pump();

    // Every attempt from here fails the way a flaky network does.
    failDayFetchWith = const NetworkFailure();
    final int fetchesBeforePop = dayFetches;

    router.pop();
    await tester.pump();

    // `pumpUntilFound`'s bounded budget IS the assertion. Before the retry
    // bound landed, `beauticaProviderRetry` handed this to
    // `ProviderContainer.defaultRetry`'s full curve — 10 attempts over ~38 s
    // — and `AsyncValue.when` routes `AsyncLoading(retrying: true)` to
    // `loading:`, so the error state would not exist to find inside this
    // window and this line would time out RED.
    await tester.pumpUntilFound(find.byKey(const Key('my_bookings_error')));

    expect(
      find.byKey(const Key('my_bookings_error_retry')),
      findsOneWidget,
      reason: 'a terminal error is only useful if the master can act on it',
    );
    expect(
      find.byKey(const Key('master-bookings-skeleton')),
      findsNothing,
      reason:
          'the skeleton and the error are mutually exclusive branches of the '
          'same `AsyncValue.when` — seeing the skeleton here IS the defect',
    );
    expect(
      dayFetches - fetchesBeforePop,
      2,
      reason:
          'one attempt plus ONE bounded re-attempt — the attempt COUNT, not '
          'the backoff curve, is what turned a bad network into a hang',
    );
  });
}
