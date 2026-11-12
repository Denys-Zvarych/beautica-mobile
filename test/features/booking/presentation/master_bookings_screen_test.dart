// Phase 7.6 — «Мої записи» for the independent master.
//
// Phase 485 — the screen is now the Mon–Sun WEEK view (`layout: week`): one
// week request per shown week, the week header (nav bar + strip) replaces the
// day rail, and the body is `WeekTimeGrid`. The day-rail invariants below
// that no longer apply to this screen live on with the salon board's day
// layout (`bookings_day_rail_test.dart`, the panel suites).
//
// Phase 7.11 — rewritten from the vertical-card-list era to the day-scoped
// timeline. The load-bearing invariants pinned here, each of which fails
// silently rather than loudly if broken:
//   • the body is the TIMELINE (`BookingsTimelineGrid`), not a vertical list
//     — no `Key('master-bookings-list')` survives anywhere;
//   • the dots do NOT change when a filter is applied (they come from a
//     filter-independent provider — narrowing must not hide the days the
//     master would need to un-narrow to reach);
//   • a day tap issues exactly ONE request (a rail fling would otherwise fire
//     dozens), and sends `from == to`;
//   • the initial day is KYIV "today", not host "today" — asserted against
//     the exact same derivation the production code uses
//     (`kyivToday(DateTime.now)`);
//   • filter-empty and true-empty are different screens, and only one offers
//     an escape hatch. `BookingsDayQuery.hasFilters` excludes the DAY (it is
//     navigation, not a filter) — so narrowing to an empty DAY with no
//     status/service filter active is the TRUE-empty state, not the
//     filter-empty one; only an actual status/service filter that matches
//     nothing produces the filter-empty state.
//   • `isTruncated` renders a persistent, visible notice.
//
// ## LOW #334 — no hardcoded calendar dates
//
// Every rail-day assertion below is expressed RELATIVE to the Kyiv "today"
// the screen itself derives (`railDayAt(_kyivToday, offset)`), never as a
// literal `DateTime(2026, 7, 20)`. A literal date is inside the rail's
// ±180-day span only as long as "today" stays within ~6 months of it — this
// suite would otherwise start silently failing the day that literal aged out
// of the span, with no visible cause. (Mirrors the S1 calendar pin's
// `futureConfirmed()` pattern elsewhere in this suite.)

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/booked_days_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/master_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_timeline_grid.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_booking_card.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/my_bookings_states.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/week_nav_bar.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/week_strip.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/week_time_grid.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_scope.dart';
import 'package:beautica_mobile/features/schedule/presentation/effective_schedule_notifier.dart';
import 'package:beautica_mobile/features/schedule/presentation/schedule_range.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:beautica_mobile/shared/formatters/api_date.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:beautica_mobile/shared/widgets/velvet_bottom_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/booking_fixture_dates.dart';
import '../../../helpers/pump_app.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/features/booking_links/presentation/booking_link_setup_hints_provider.dart';
import 'package:beautica_mobile/features/booking_links/presentation/master_nav_setup_hints_provider.dart';

// Fixture identities injected BY these tests — NOT app copy, and
// locale-invariant by construction (a person's name is not translated). This
// is the case the `i18n-finder-ok` annotation exists for.
const String _otherClientFirst = 'Ігор';
const String _otherClientLast = 'Мороз';

/// Kyiv "today", derived through the EXACT SAME production function the
/// screen uses — never a literal. See the file header (LOW #334).
DateTime get _kyivToday => kyivToday(DateTime.now);

/// Phase 485 — the screen fetches the Kyiv WEEK containing today.
DateTime get _weekMonday => kyivWeekStart(_kyivToday);

/// A genuine INSTANT at [hourUtc] on the SAME Kyiv calendar day [_kyivToday]
/// names.
///
/// [_kyivToday] is a DATE TOKEN — a host-local midnight `DateTime` whose
/// `.year`/`.month`/`.day` carry the Kyiv day (see
/// `lib/shared/time/kyiv_day.dart`'s header). `.toUtc()` on such a token is on
/// that header's ILLEGAL list: it reinterprets host-local midnight as if it
/// were already an instant, so `_kyivToday.toUtc().add(...)` — what these
/// fixtures used to do — yields a different Kyiv day depending on the host's
/// own `TZ`. From a WESTERN host (e.g. UTC-10) midnight local is 10:00Z, so
/// `+12h` lands at 22:00Z, already the NEXT Kyiv day, and every "today"
/// assertion below would then be asserting against a day the screen never
/// renders.
///
/// Reading only the token's calendar fields and rebuilding with `DateTime.utc`
/// is host-independent. Kyiv is UTC+2/+3, so any [hourUtc] in roughly 0..20
/// stays inside the same Kyiv civil day; the call sites use 8..13, which is
/// exactly the band CI (`TZ=UTC`) already exercised before this fix.
DateTime _kyivTodayAtUtc(int hourUtc) {
  final DateTime day = _kyivToday;
  return DateTime.utc(day.year, day.month, day.day, hourUtc);
}

/// A LATE-EVENING UTC instant whose Kyiv calendar day is the NEXT day — the
/// pinned "now" the Kyiv-vs-naive landing-query guard runs against.
///
/// 22:30 UTC is past Kyiv midnight in BOTH halves of the year (UTC+3 summer →
/// 01:30, UTC+2 winter → 00:30), so the skew this test needs exists on every
/// run rather than during a ~3h window per day. The date is derived from
/// `futureBookingStart()` rather than written as a literal — see
/// `test/helpers/booking_fixture_dates.dart` and
/// `scripts/forbid_stale_future_date_fixture.sh`.
DateTime _kyivSkewInstantUtc() {
  final DateTime base = futureBookingStart();
  return DateTime.utc(base.year, base.month, base.day, 22, 30);
}

class _MockBookingRepository extends Mock implements BookingRepository {}

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

Booking _booking({
  required String id,
  String clientFirstName = 'Олена',
  String clientLastName = 'Ковальчук',
  String serviceName = 'Манікюр з покриттям',
  double price = 650,
  BookingStatus status = BookingStatus.confirmed,
  DateTime? startAt,
}) {
  final DateTime start = startAt ?? _kyivTodayAtUtc(12);
  return Booking(
    id: id,
    masterId: 'm1',
    masterFirstName: 'Марія',
    masterLastName: 'Іванюк',
    masterType: 'INDEPENDENT_MASTER',
    clientId: 'c-$id',
    clientFirstName: clientFirstName,
    clientLastName: clientLastName,
    serviceId: 's1',
    serviceName: serviceName,
    durationMinutes: 90,
    price: price,
    startAt: start,
    endAt: start.add(const Duration(minutes: 90)),
    status: status,
    canReview: false,
  );
}

PageResponse<Booking> _page(
  List<Booking> items, {
  int page = 0,
  int totalPages = 1,
  int? totalElements,
}) => PageResponse<Booking>(
  items: items,
  page: page,
  totalPages: totalPages,
  totalElements: totalElements ?? items.length,
);

/// Phase 329 — the signed-in identity every test in this file assumes: an
/// `INDEPENDENT_MASTER` looking at their own «Мої записи».
///
/// `MasterBookingsScreen` now reads `bookingCreationEnabledProvider`, which
/// derives the (+) add-booking affordance from the SESSION through the STRICT
/// settled selector. Without an authenticated session that provider correctly
/// fails closed and the button is ABSENT — so the ONE harness whose test taps
/// «+» ([_pumpWithNavRoutes]) seeds a real session, rather than overriding the
/// capability provider itself (an override there would bypass the very role
/// mapping the screen now depends on — the `approvedCategoriesProvider`
/// footgun the backlog records).
///
/// DELIBERATELY NOT applied to [_pump]. `AuthNotifier.build` is `async`, so
/// any stub of it passes through one `AsyncLoading` frame before settling —
/// and `bookings_day_notifier.dart:493-500` watches the authenticated USER ID,
/// so that null → id transition legitimately re-fetches the day. In
/// production the router's auth guard has already settled the session before
/// this screen ever mounts, so no such second fetch exists there; inside a
/// fetch-COUNTING test it would be pure stub artifact. [_pump]'s tests never
/// touch the (+) button (it is the only affordance the capability gates), so
/// they keep their unauthenticated harness and their exact call counts.
const User _stubIndependentMaster = User(
  id: 'master-bookings-test-1',
  email: 'master@beautica.ua',
  role: UserRole.independentMaster,
  firstName: 'Олена',
  lastName: 'Майстер',
);

class _IndependentMasterAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.authenticated(
    user: _stubIndependentMaster,
    accessToken: 'tok',
  );
}

/// Pumps the screen with [repo] backing both the timeline and the booked-days
/// dot set.
///
/// A REAL `GoRouter`, not `pumpApp` — the filter sheet closes with
/// go_router's `context.pop(value)` extension (raw `Navigator.pop` is banned
/// in `lib/features`), which throws "No GoRouter found in context" under a
/// plain `MaterialApp`. Mirrors `master_bookings_filter_wiring_test.dart`'s
/// own `pump` helper.
Future<void> _pump(
  WidgetTester tester,
  _MockBookingRepository repo, {
  Set<DateTime> bookedDays = const <DateTime>{},
  // Pinned "now", injected through the production clock seam
  // (`bookings_discovery_view.dart`'s `initState`). `null` leaves the real
  // wall clock in place, which is what every pre-existing test here wants.
  DateTime Function()? clock,
  // Defaults to the PRODUCTION predicate [beauticaProviderRetry] so error
  // paths resolve as they do in the shipped app. Pass `(_, _) => null` to
  // DISABLE retry entirely, so an AsyncError settles and a fetch count stays
  // exact.
  Duration? Function(int retryCount, Object error)? retry =
      beauticaProviderRetry,
}) async {
  await tester.pumpRoutedApp(
    GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (BuildContext context, GoRouterState state) =>
              const MasterBookingsScreen(),
        ),
      ],
    ),
    retry: retry,
    overrides: <Object>[
      // Setup-hint dots (2026-10-30) are covered by
      // `velvet_bottom_nav_bar_setup_hints_test.dart`; pinned off here so the
      // real schedule/catalogue reads (5-min cache timers) never run.
      masterNavSetupHintsProvider.overrideWithValue(BookingLinkSetupHints.none),
      screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
      bookingRepositoryProvider.overrideWithValue(repo),
      bookedDaysProvider.overrideWith((ref) async => bookedDays),
      if (clock != null) clockProvider.overrideWithValue(clock),
    ],
  );
}

const Key _servicesMarker = Key('stub-services-screen');
const Key _scheduleMarker = Key('stub-schedule-screen');
const Key _profileMarker = Key('stub-profile-screen');
const Key _createBookingMarker = Key('stub-create-booking-screen');

/// Same as [_pump], plus stub destinations for every nav-tile route so
/// nav-tile taps that push them can be observed landing. Returns the
/// [GoRouter] so tests can assert `canPop()`/the mounted screen after a tap.
Future<GoRouter> _pumpWithNavRoutes(
  WidgetTester tester,
  _MockBookingRepository repo, {
  Set<DateTime> bookedDays = const <DateTime>{},
}) async {
  final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (BuildContext context, GoRouterState state) =>
            const MasterBookingsScreen(),
      ),
      GoRoute(
        path: RouteNames.services,
        builder: (BuildContext context, GoRouterState state) =>
            const Scaffold(body: SizedBox.shrink(key: _servicesMarker)),
      ),
      GoRoute(
        path: RouteNames.masterSchedule,
        builder: (BuildContext context, GoRouterState state) =>
            const Scaffold(body: SizedBox.shrink(key: _scheduleMarker)),
      ),
      GoRoute(
        path: RouteNames.masterProfile,
        builder: (BuildContext context, GoRouterState state) =>
            const Scaffold(body: SizedBox.shrink(key: _profileMarker)),
      ),
      // Phase 248 — the «+» add-booking affordance's real destination. A
      // top-level absolute-path stub (mirroring the three siblings above)
      // rather than nested under `/` the way production nests it under
      // `RouteNames.masterBookings`: `context.push` matches by LOCATION
      // string against the whole route tree, not by the pusher's own
      // position in it, so the absolute path is all a push needs to resolve.
      GoRoute(
        path: RouteNames.masterBookingNew,
        builder: (BuildContext context, GoRouterState state) =>
            const Scaffold(body: SizedBox.shrink(key: _createBookingMarker)),
      ),
    ],
  );
  await tester.pumpRoutedApp(
    router,
    overrides: <Object>[
      // Setup-hint dots (2026-10-30) are covered by
      // `velvet_bottom_nav_bar_setup_hints_test.dart`; pinned off here so the
      // real schedule/catalogue reads (5-min cache timers) never run.
      masterNavSetupHintsProvider.overrideWithValue(BookingLinkSetupHints.none),
      // Phase 329 — see [_IndependentMasterAuthNotifier].
      authProvider.overrideWith(_IndependentMasterAuthNotifier.new),
      screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
      bookingRepositoryProvider.overrideWithValue(repo),
      bookedDaysProvider.overrideWith((ref) async => bookedDays),
    ],
  );
  return router;
}

void main() {
  setUpAll(() {
    registerFallbackValue(BookingStatus.confirmed);
    registerFallbackValue(BookingSort.oldest);
    registerFallbackValue(<BookingStatus>[]);
  });

  // -------------------------------------------------------------------------
  // Async states
  // -------------------------------------------------------------------------

  group('async states', () {
    testWidgets('shows the skeleton while the first page loads', (
      tester,
    ) async {
      final repo = _MockBookingRepository();
      when(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          page: any(named: 'page'),
          size: any(named: 'size'),
          cancelToken: any(named: 'cancelToken'),
          sort: any(named: 'sort'),
          serviceIds: any(named: 'serviceIds'),
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).thenAnswer((_) async {
        await Future<void>.delayed(const Duration(seconds: 1));
        return _page(<Booking>[]);
      });

      await _pump(tester, repo);
      await tester.pump();

      expect(find.byType(BookingsSkeleton), findsOne);
      await tester.pumpUntilGone(find.byType(BookingsSkeleton));
    });

    testWidgets('shows the error state with a retry on failure', (
      tester,
    ) async {
      final repo = _MockBookingRepository();
      when(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          page: any(named: 'page'),
          size: any(named: 'size'),
          cancelToken: any(named: 'cancelToken'),
          sort: any(named: 'sort'),
          serviceIds: any(named: 'serviceIds'),
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).thenThrow(Exception('boom'));

      await _pump(tester, repo);
      await tester.pumpAndSettle();

      expect(find.byType(MyBookingsErrorState), findsOne);
    });

    // =====================================================================
    // mobile-qa (2026-07-22) — THE RETRY WAS NEVER TAPPED.
    //
    // The test above is named "…with a retry" but only asserts the error
    // WIDGET renders. `MyBookingsErrorState` takes `onRetry` as a plain
    // `VoidCallback`, so it renders identically whether the screen wires it
    // to `ref.invalidate(bookingsDayProvider(_liveQuery))`, to `() {}`, or —
    // the interesting failure — to a STALE query captured at first build.
    // None of those three is distinguishable without actually tapping it.
    //
    // Both tests below use sequential `verify(...).called(1)` (mirroring
    // `my_bookings_interactions_test.dart`'s retry case): mocktail's `verify`
    // CONSUMES the calls it matches, so the second `called(1)` counts only
    // what happened after the tap.
    // =====================================================================

    testWidgets('tapping retry re-issues the day fetch — the handler is '
        'wired, not a no-op', (tester) async {
      final repo = _MockBookingRepository();
      when(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          page: any(named: 'page'),
          size: any(named: 'size'),
          cancelToken: any(named: 'cancelToken'),
          sort: any(named: 'sort'),
          serviceIds: any(named: 'serviceIds'),
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).thenThrow(Exception('boom'));

      // Riverpod's default exponential-backoff retry would fire mid-settle
      // and make the fetch counts below non-deterministic.
      await _pump(tester, repo, retry: (_, _) => null);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('my_bookings_error_retry')), findsOne);

      // Consume the landing fetch.
      verify(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          page: any(named: 'page'),
          size: any(named: 'size'),
          cancelToken: any(named: 'cancelToken'),
          sort: any(named: 'sort'),
          serviceIds: any(named: 'serviceIds'),
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).called(1);

      await tester.tap(find.byKey(const Key('my_bookings_error_retry')));
      await tester.pumpAndSettle();

      verify(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          page: any(named: 'page'),
          size: any(named: 'size'),
          cancelToken: any(named: 'cancelToken'),
          sort: any(named: 'sort'),
          serviceIds: any(named: 'serviceIds'),
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).called(1);
    });

    testWidgets(
      'retry refetches the CURRENTLY shown week, not the landing week',
      (tester) async {
        // The failure this catches: `onRetry` closing over a query captured
        // once at first build (or over `widget.query`) rather than reading
        // the live `_liveQuery`. The master would tap «Спробувати ще раз» on
        // Thursday's failed timeline and silently re-request Monday's — the
        // error state would never clear, with no clue why.
        final repo = _MockBookingRepository();
        final List<DateTime?> froms = <DateTime?>[];
        when(
          () => repo.getMyBookings(
            statuses: any(named: 'statuses'),
            page: any(named: 'page'),
            size: any(named: 'size'),
            cancelToken: any(named: 'cancelToken'),
            sort: any(named: 'sort'),
            serviceIds: any(named: 'serviceIds'),
            from: any(named: 'from'),
            to: any(named: 'to'),
          ),
        ).thenAnswer((Invocation i) async {
          froms.add(i.namedArguments[#from] as DateTime?);
          throw Exception('boom');
        });

        await _pump(tester, repo, retry: (_, _) => null);
        await tester.pumpAndSettle();

        // Landing week failed.
        expect(froms, <DateTime?>[_weekMonday]);

        // Phase 485 — step to the NEXT week; that week fails too.
        final DateTime otherDay = kyivAddDays(_weekMonday, 7);
        await tester.tap(find.byKey(WeekStepButton.nextKey));
        await tester.pumpAndSettle();

        expect(
          froms.last,
          otherDay,
          reason: 'fixture guard: the week step did not re-scope the query',
        );
        froms.clear();

        expect(find.byKey(const Key('my_bookings_error_retry')), findsOne);
        await tester.tap(find.byKey(const Key('my_bookings_error_retry')));
        await tester.pumpAndSettle();

        expect(
          froms,
          isNotEmpty,
          reason: 'retry issued no request at all — the handler is inert',
        );
        expect(
          froms.single,
          otherDay,
          reason:
              'retry refetched ${froms.single} instead of the shown week '
              '$otherDay — onRetry is bound to a STALE query, so the '
              'error state can never clear on any day but the landing one.',
        );
        expect(froms.single, isNot(_weekMonday));
      },
    );

    testWidgets(
      'renders a card per booking INSIDE the week grid — no vertical list '
      'and no single-day timeline survive',
      (tester) async {
        final repo = _MockBookingRepository();
        when(
          () => repo.getMyBookings(
            statuses: any(named: 'statuses'),
            page: any(named: 'page'),
            size: any(named: 'size'),
            cancelToken: any(named: 'cancelToken'),
            sort: any(named: 'sort'),
            serviceIds: any(named: 'serviceIds'),
            from: any(named: 'from'),
            to: any(named: 'to'),
          ),
        ).thenAnswer(
          (_) async => _page(<Booking>[
            _booking(id: 'b1'),
            _booking(
              id: 'b2',
              clientFirstName: _otherClientFirst,
              clientLastName: _otherClientLast,
            ),
          ]),
        );

        await _pump(tester, repo);
        await tester.pumpAndSettle();

        expect(find.byType(WeekTimeGrid), findsOne);
        expect(find.byType(BookingsTimelineGrid), findsNothing);
        expect(
          find.byKey(const Key('master-bookings-list')),
          findsNothing,
          reason: 'the retired vertical card list must not resurface',
        );
        expect(find.byKey(WeekTimeGrid.cardKey('b1')), findsOne);
        expect(find.byKey(WeekTimeGrid.cardKey('b2')), findsOne);
        expect(find.byType(MasterBookingCard), findsNWidgets(2));
      },
    );

    testWidgets('a truncated day renders a persistent visible notice', (
      tester,
    ) async {
      final repo = _MockBookingRepository();
      when(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          page: any(named: 'page'),
          size: any(named: 'size'),
          cancelToken: any(named: 'cancelToken'),
          sort: any(named: 'sort'),
          serviceIds: any(named: 'serviceIds'),
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).thenAnswer(
        (_) async => _page(
          <Booking>[_booking(id: 'b1')],
          totalPages: 2,
          totalElements: 101,
        ),
      );

      await _pump(tester, repo);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('master-bookings-truncated-notice')),
        findsOne,
      );
    });
  });

  // -------------------------------------------------------------------------
  // The two empties
  // -------------------------------------------------------------------------

  group('empty states', () {
    // Phase 485 — an empty week keeps its grid (the master still sees the
    // shape of the week); only the filter-empty state replaces it.
    testWidgets('TRUE empty (no filters, an empty week) keeps the grid and '
        'offers no reset', (tester) async {
      final repo = _MockBookingRepository();
      when(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          page: any(named: 'page'),
          size: any(named: 'size'),
          cancelToken: any(named: 'cancelToken'),
          sort: any(named: 'sort'),
          serviceIds: any(named: 'serviceIds'),
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).thenAnswer((_) async => _page(<Booking>[]));

      await _pump(tester, repo);
      await tester.pumpAndSettle();

      expect(find.byType(WeekTimeGrid), findsOne);
      expect(find.byKey(const Key('master-bookings-no-results')), findsNothing);
      expect(
        find.byKey(const Key('master-bookings-clear-filters')),
        findsNothing,
        reason:
            'A reset button on the true-empty state offers to undo a filter '
            'the master never applied.',
      );
    });

    testWidgets(
      'FILTER empty (a status filter matches nothing) offers «Скинути '
      'фільтри» — the master is never stranded',
      (tester) async {
        final repo = _MockBookingRepository();
        // The DEFAULT view: one booking. A master-CHOSEN status filter:
        // nothing matches it.
        //
        // The discriminator was `isEmpty` vs `isNotEmpty` until 2026-08-13.
        // It cannot be any more: the default view now carries
        // `BookingStatus.visibleInDayListByDefault` on the wire (CANCELLED and
        // DECLINED are hidden without the master filtering, and
        // `GET /bookings/me` has no exclude parameter), so an empty status
        // list never reaches the repository from this screen and the landing
        // fetch matched the "filtered" stub instead — the empty page it
        // returned made the pre-filter `findsOne` below fail. Splitting on the
        // default SET keeps the test asserting the same thing it always did:
        // unfiltered shows work, a chosen filter that matches nothing offers
        // the escape hatch.
        when(
          () => repo.getMyBookings(
            statuses: any(
              named: 'statuses',
              that: unorderedEquals(BookingStatus.visibleInDayListByDefault),
            ),
            page: any(named: 'page'),
            size: any(named: 'size'),
            cancelToken: any(named: 'cancelToken'),
            sort: any(named: 'sort'),
            serviceIds: any(named: 'serviceIds'),
            from: any(named: 'from'),
            to: any(named: 'to'),
          ),
        ).thenAnswer((_) async => _page(<Booking>[_booking(id: 'b1')]));
        when(
          () => repo.getMyBookings(
            statuses: any(
              named: 'statuses',
              that: isNot(
                unorderedEquals(BookingStatus.visibleInDayListByDefault),
              ),
            ),
            page: any(named: 'page'),
            size: any(named: 'size'),
            cancelToken: any(named: 'cancelToken'),
            sort: any(named: 'sort'),
            serviceIds: any(named: 'serviceIds'),
            from: any(named: 'from'),
            to: any(named: 'to'),
          ),
        ).thenAnswer((_) async => _page(<Booking>[]));

        await _pump(tester, repo);
        await tester.pumpAndSettle();
        expect(find.byType(MasterBookingCard), findsOne);

        await tester.tap(
          find.byKey(const Key('master-bookings-filter-button')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('master-bookings-filter-status-confirmed')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('master-bookings-filter-apply')));
        await tester.pumpUntilFound(
          find.byKey(const Key('master-bookings-no-results')),
        );

        expect(find.byKey(const Key('master-bookings-no-results')), findsOne);
        expect(find.byKey(const Key('master-bookings-empty')), findsNothing);
        expect(
          find.byKey(const Key('master-bookings-clear-filters')),
          findsOne,
        );

        // The escape hatch actually restores the unfiltered list.
        await tester.tap(
          find.byKey(const Key('master-bookings-clear-filters')),
        );
        await tester.pumpUntilFound(find.byType(MasterBookingCard));
        expect(find.byType(MasterBookingCard), findsOne);
      },
    );
  });

  // -------------------------------------------------------------------------
  // The teammate filter section is NOT offered here
  // -------------------------------------------------------------------------

  group('teammate filter section — absent on a master\'s OWN list', () {
    // 2026-09-18 (mobile-qa LOW) — `bookings_discovery_view_reuse_test.dart`
    // already pins `BookingsDiscoveryView`'s own behaviour under BOTH values of
    // `showMasterFilter`, and `bookings_filter_sheet_test.dart` pins the
    // sheet's empty-roster rule. What nothing pinned was THIS SCREEN's half of
    // the contract: that `master_bookings_screen.dart` keeps the teammate
    // section switched off (`showMasterFilter: false`, no roster) — a single
    // master's own list has no teammates to filter by.
    //
    // Asserted on the RENDERED sheet rather than by reading
    // `BookingsDiscoveryView.showMasterFilter` off the element. A widget-field
    // read only restates the source line it is meant to guard, and would stay
    // green for a regression that reached the section by some OTHER route
    // (a roster handed straight to `BookingsFilterSheet.show`, say) — whereas
    // the section's own `Key` is downstream of every path that can produce it.
    //
    // Located by KEY, never by the section's Cyrillic label:
    // `scripts/forbid_cyrillic_finder.sh` bans a Cyrillic literal inside a
    // `find.text(...)` argument across `test/**`.
    testWidgets(
      'opening the filter sheet renders the status section but NO teammate '
      'section',
      (tester) async {
        final repo = _MockBookingRepository();
        when(
          () => repo.getMyBookings(
            statuses: any(named: 'statuses'),
            page: any(named: 'page'),
            size: any(named: 'size'),
            cancelToken: any(named: 'cancelToken'),
            sort: any(named: 'sort'),
            serviceIds: any(named: 'serviceIds'),
            from: any(named: 'from'),
            to: any(named: 'to'),
          ),
        ).thenAnswer((_) async => _page(<Booking>[_booking(id: 'b1')]));

        await _pump(tester, repo);
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('master-bookings-filter-button')),
        );
        await tester.pumpAndSettle();

        // POSITIVE CONTROL — the sheet genuinely opened and built its other
        // sections. Without these two, a regression that failed to open the
        // sheet at all would satisfy the absence assertion below vacuously,
        // which is exactly the failure mode this test exists to rule out.
        expect(
          find.byKey(const Key('master-bookings-filter-sheet')),
          findsOne,
          reason: 'the sheet is genuinely mounted',
        );
        expect(
          find.byKey(const Key('master-bookings-filter-section-status')),
          findsOne,
          reason:
              'the sheet rendered its sections — so an absent teammate '
              'section below means ABSENT, not "never built"',
        );

        expect(
          find.byKey(const Key('master-bookings-filter-section-master')),
          findsNothing,
          reason:
              'a single master filtering their own day has no teammates; '
              'this fails the moment `master_bookings_screen.dart` starts '
              'passing `showMasterFilter: true` WITH a roster, or hands the '
              'sheet a roster by any other route',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // Phase 485 — the week header (nav bar + strip) and the landing week.
  // The day rail's own behaviour stays pinned on the day layout (the salon
  // board) by `bookings_day_rail_test.dart` and the panel suites.
  // -------------------------------------------------------------------------

  group('week header', () {
    testWidgets('opens on the Kyiv week CONTAINING today — the strip shows '
        'Monday..Sunday of it and nothing outside', (tester) async {
      final repo = _MockBookingRepository();
      when(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          page: any(named: 'page'),
          size: any(named: 'size'),
          cancelToken: any(named: 'cancelToken'),
          sort: any(named: 'sort'),
          serviceIds: any(named: 'serviceIds'),
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).thenAnswer((_) async => _page(<Booking>[]));

      await _pump(tester, repo);
      await tester.pumpAndSettle();

      for (int i = 0; i < 7; i++) {
        expect(
          find.byKey(weekStripDayKey(kyivAddDays(_weekMonday, i))),
          findsOne,
        );
      }
      expect(
        find.byKey(weekStripDayKey(kyivAddDays(_weekMonday, -1))),
        findsNothing,
      );
      expect(
        find.byKey(WeekNavBar.todayKey),
        findsNothing,
        reason: '«Сьогодні» only shows off the current week',
      );
    });

    // MUTATION: made `_shiftWeek` ignore its delta → the from/to below stayed
    // on this week and this test failed. Restored.
    testWidgets('‹ reaches the previous week with ONE week request, and '
        '«Сьогодні» brings the current week back', (tester) async {
      final repo = _MockBookingRepository();
      final List<(DateTime?, DateTime?)> calls = <(DateTime?, DateTime?)>[];
      when(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          page: any(named: 'page'),
          size: any(named: 'size'),
          cancelToken: any(named: 'cancelToken'),
          sort: any(named: 'sort'),
          serviceIds: any(named: 'serviceIds'),
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).thenAnswer((Invocation i) async {
        calls.add((
          i.namedArguments[#from] as DateTime?,
          i.namedArguments[#to] as DateTime?,
        ));
        return _page(<Booking>[]);
      });

      await _pump(tester, repo);
      await tester.pumpAndSettle();
      calls.clear();

      await tester.tap(find.byKey(WeekStepButton.prevKey));
      await tester.pumpAndSettle();

      final DateTime prevMonday = kyivAddDays(_weekMonday, -7);
      expect(calls, hasLength(1));
      expect(calls.single.$1, prevMonday);
      expect(calls.single.$2, kyivAddDays(prevMonday, 6));
      expect(find.byKey(weekStripDayKey(prevMonday)), findsOne);

      await tester.tap(find.byKey(WeekNavBar.todayKey));
      await tester.pumpAndSettle();
      expect(find.byKey(weekStripDayKey(_weekMonday)), findsOne);
      expect(find.byKey(WeekNavBar.todayKey), findsNothing);
    });

    // D3 — a day inside the shown week reads the SAME week data.
    testWidgets('a strip tap issues NO request — the day is already in the '
        'loaded week', (tester) async {
      final repo = _MockBookingRepository();
      int calls = 0;
      when(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          page: any(named: 'page'),
          size: any(named: 'size'),
          cancelToken: any(named: 'cancelToken'),
          sort: any(named: 'sort'),
          serviceIds: any(named: 'serviceIds'),
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).thenAnswer((_) async {
        calls++;
        return _page(<Booking>[_booking(id: 'b1')]);
      });

      await _pump(tester, repo);
      await tester.pumpAndSettle();
      calls = 0;

      await tester.tap(
        find.byKey(weekStripDayKey(kyivAddDays(_weekMonday, 6))),
      );
      // fixed-wait-ok: crossing any debounce a regression might add.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(calls, 0);
    });

    // BOOK-71 — the strip counts live bookings only.
    testWidgets('the strip count excludes cancelled and declined bookings', (
      tester,
    ) async {
      final repo = _MockBookingRepository();
      when(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          page: any(named: 'page'),
          size: any(named: 'size'),
          cancelToken: any(named: 'cancelToken'),
          sort: any(named: 'sort'),
          serviceIds: any(named: 'serviceIds'),
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).thenAnswer(
        (_) async => _page(<Booking>[
          _booking(id: 'b1', startAt: _kyivTodayAtUtc(8)),
          _booking(id: 'b2', startAt: _kyivTodayAtUtc(10)),
          _booking(
            id: 'b3',
            startAt: _kyivTodayAtUtc(12),
            status: BookingStatus.cancelled,
          ),
        ]),
      );

      await _pump(tester, repo);
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(weekStripCountKey(_kyivToday))).data,
        '2',
      );
      // The cancelled booking is still ON the grid (struck through).
      expect(find.byKey(WeekTimeGrid.cardKey('b3')), findsOne);
    });

    // mobile-qa (2026-07-22) — the clock-seam guard, now for the WEEK: a
    // Sunday 22:30 UTC instant is already MONDAY in Kyiv, so a naive host
    // reading lands one whole week early. The pin is chosen so the two
    // weeks differ on every run.
    testWidgets('DISTINGUISHES the Kyiv week from a naive host reading', (
      tester,
    ) async {
      final DateTime base = _kyivSkewInstantUtc();
      final DateTime sunday = DateTime.utc(
        base.year,
        base.month,
        base.day + (DateTime.sunday - base.weekday),
        22,
        30,
      );
      final DateTime kyivWeek = kyivWeekStart(dateOnly(toBeauticaTime(sunday)));
      final DateTime naiveWeek = kyivWeekStart(dateOnly(sunday));
      expect(kyivWeek, isNot(naiveWeek), reason: 'fixture guard');

      final repo = _MockBookingRepository();
      DateTime? capturedFrom;
      when(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          page: any(named: 'page'),
          size: any(named: 'size'),
          cancelToken: any(named: 'cancelToken'),
          sort: any(named: 'sort'),
          serviceIds: any(named: 'serviceIds'),
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).thenAnswer((Invocation i) async {
        capturedFrom = i.namedArguments[#from] as DateTime?;
        return _page(<Booking>[]);
      });

      await _pump(tester, repo, clock: () => sunday);
      await tester.pumpAndSettle();

      expect(capturedFrom, kyivWeek);
      expect(capturedFrom, isNot(naiveWeek));
    });
  });

  // -------------------------------------------------------------------------
  // Nav wiring
  // -------------------------------------------------------------------------

  group('navigation', () {
    testWidgets('tapping a card pushes the master detail route', (
      tester,
    ) async {
      final repo = _MockBookingRepository();
      when(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          page: any(named: 'page'),
          size: any(named: 'size'),
          cancelToken: any(named: 'cancelToken'),
          sort: any(named: 'sort'),
          serviceIds: any(named: 'serviceIds'),
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).thenAnswer((_) async => _page(<Booking>[_booking(id: 'b1')]));

      await _pump(tester, repo);
      await tester.pumpAndSettle();

      // The card carries a tap target keyed by booking id — the seam the
      // route push hangs off. The route itself is asserted with `context
      // .push` (never `router.go`) in `master_bookings_routing_test.dart`,
      // which drives a real GoRouter so the `ImperativeRouteMatch` behaviour
      // is exercised rather than mocked.
      expect(find.byKey(const Key('master-booking-card-b1')), findsOne);
    });

    // Phase 248 — the header's «+» add-booking affordance. Used to show a
    // "coming soon" VelvetSnack (`_showAddComingSoon`); now pushes the real
    // Phase 247 wizard route. `canPop()` (not just the marker) is the
    // context.push proof here — `go` REPLACES the stack (`canPop` stays
    // false, exactly the assertion the `bottom nav` group's tile tests pin
    // for THEIR `go` calls just below), so a `push` is the only way this can
    // read `true`. The full round trip (fill client → pick service → pick
    // date/slot → confirm → done → pop → the new booking visible in the
    // refetched list) is proven end to end by
    // `integration_test/master_create_booking_test.dart`, not here — this
    // tier only proves the button is wired to a real push and the old snack
    // is gone.
    testWidgets(
      'tapping «+» pushes the Phase 247 wizard route (context.push, not '
      'router.go) and shows no coming-soon snack',
      (tester) async {
        final repo = _MockBookingRepository();
        when(
          () => repo.getMyBookings(
            statuses: any(named: 'statuses'),
            page: any(named: 'page'),
            size: any(named: 'size'),
            cancelToken: any(named: 'cancelToken'),
            sort: any(named: 'sort'),
            serviceIds: any(named: 'serviceIds'),
            from: any(named: 'from'),
            to: any(named: 'to'),
          ),
        ).thenAnswer((_) async => _page(<Booking>[]));

        final GoRouter router = await _pumpWithNavRoutes(tester, repo);
        await tester.pumpAndSettle();
        expect(router.canPop(), isFalse);

        await tester.tap(find.byKey(const Key('master-bookings-add')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(_createBookingMarker),
          findsOneWidget,
          reason:
              'the «+» must push RouteNames.masterBookingNew '
              '(/master/bookings/new), the Phase 247 wizard route',
        );
        expect(
          router.canPop(),
          isTrue,
          reason:
              'push (not go) — the wizard is ON TOP of the list, so the '
              'stack has something to pop back to. This is the assertion '
              'that actually distinguishes context.push from router.go: a '
              'go() replacing the stack would leave canPop() false even '
              'though the marker still matched.',
        );
        expect(
          find.byType(VelvetSnack),
          findsNothing,
          reason: 'the old "coming soon" placeholder snack must be gone',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // Phase 7.14 — the master bottom nav bar
  // -------------------------------------------------------------------------
  //
  // This screen was a dead end: reachable via nav tile 1, but rendering no
  // chrome of its own to get anywhere else. These tests pin (a) the bar
  // renders configured for tile 1 — not just present, since a copy-paste of
  // MasterProfileScreen's `activeIndex: 3` would still render *a* bar and
  // pass a bare `findsOneWidget`; (b) a non-active tile REPLACES the stack via
  // `context.go` (not `push` — see the group below for why go is safe here);
  // (c) the already-active tile is a no-op, so a stray tap never navigates at
  // all; (d) the bar coexists with the timeline without an overflow at a
  // small viewport.

  group('bottom nav', () {
    testWidgets(
      'renders VelvetBottomNavBar with «Мої записи» (index 1) selected — '
      'not just present',
      (tester) async {
        final repo = _MockBookingRepository();
        when(
          () => repo.getMyBookings(
            statuses: any(named: 'statuses'),
            page: any(named: 'page'),
            size: any(named: 'size'),
            cancelToken: any(named: 'cancelToken'),
            sort: any(named: 'sort'),
            serviceIds: any(named: 'serviceIds'),
            from: any(named: 'from'),
            to: any(named: 'to'),
          ),
        ).thenAnswer((_) async => _page(<Booking>[]));

        await _pumpWithNavRoutes(tester, repo);
        await tester.pumpAndSettle();

        expect(find.byType(VelvetBottomNavBar), findsOne);
        // MUTATION GUARD: asserts the actual configured index, not merely
        // that a bar exists — `activeIndex: 3` (MasterProfileScreen's own
        // value, an easy copy-paste slip) would still satisfy `findsOne`.
        expect(
          tester
              .widget<VelvetBottomNavBar>(find.byType(VelvetBottomNavBar))
              .activeIndex,
          1,
        );
        // Ground-truth from the rendered tile itself: tile 1 reports
        // `selected: true` via Semantics, tile 0 does not.
        final SemanticsHandle handle = tester.ensureSemantics();
        expect(
          tester
              .getSemantics(find.byKey(const Key('master-nav-tile-1')))
              .flagsCollection
              .isSelected
              .toBoolOrNull(),
          isTrue,
        );
        expect(
          tester
              .getSemantics(find.byKey(const Key('master-nav-tile-0')))
              .flagsCollection
              .isSelected
              .toBoolOrNull(),
          isFalse,
        );
        handle.dispose();
      },
    );

    // mobile-debugger fix — the nav bar's tile onTap moved from
    // `context.push` back to `context.go` (see `velvet_bottom_nav_bar.dart`'s
    // onTap comment and `profile_nav_bar_navigation_test.dart`'s file header
    // for the full history): `push` stacked a new tab route on every tap, so
    // hopping between tabs grew the back stack unboundedly. `go` replaces the
    // whole stack instead, so these tiles now REPLACE this screen rather than
    // stacking on top of it — `canPop()` is `false`, not `true`, after a tap.

    testWidgets(
      'tapping a NON-active tile (Послуги, tile 0) REPLACES the stack with '
      '/services — this screen unmounts, canPop is false',
      (tester) async {
        final repo = _MockBookingRepository();
        when(
          () => repo.getMyBookings(
            statuses: any(named: 'statuses'),
            page: any(named: 'page'),
            size: any(named: 'size'),
            cancelToken: any(named: 'cancelToken'),
            sort: any(named: 'sort'),
            serviceIds: any(named: 'serviceIds'),
            from: any(named: 'from'),
            to: any(named: 'to'),
          ),
        ).thenAnswer((_) async => _page(<Booking>[]));

        final GoRouter router = await _pumpWithNavRoutes(tester, repo);
        await tester.pumpAndSettle();
        expect(router.canPop(), isFalse);

        await tester.tap(find.byKey(const Key('master-nav-tile-0')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(_servicesMarker),
          findsOneWidget,
          reason: 'the Послуги tile must go(RouteNames.services)',
        );
        expect(
          find.byType(MasterBookingsScreen),
          findsNothing,
          reason:
              'go replaces the stack — this screen must be gone, not '
              'merely covered',
        );
        expect(
          router.canPop(),
          isFalse,
          reason:
              'go (not push) — the stack was replaced, nothing left to pop. '
              'A `true` here means the call reverted to context.push(), '
              'reintroducing the stack-growth bug this fixes.',
        );
      },
    );

    testWidgets(
      'tapping a NON-active tile (Графік, tile 2) REPLACES the stack with '
      '/schedule',
      (tester) async {
        final repo = _MockBookingRepository();
        when(
          () => repo.getMyBookings(
            statuses: any(named: 'statuses'),
            page: any(named: 'page'),
            size: any(named: 'size'),
            cancelToken: any(named: 'cancelToken'),
            sort: any(named: 'sort'),
            serviceIds: any(named: 'serviceIds'),
            from: any(named: 'from'),
            to: any(named: 'to'),
          ),
        ).thenAnswer((_) async => _page(<Booking>[]));

        final GoRouter router = await _pumpWithNavRoutes(tester, repo);
        await tester.pumpAndSettle();
        expect(router.canPop(), isFalse);

        await tester.tap(find.byKey(const Key('master-nav-tile-2')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(_scheduleMarker),
          findsOneWidget,
          reason: 'the Графік tile must go(RouteNames.masterSchedule)',
        );
        expect(
          router.canPop(),
          isFalse,
          reason: 'go (not push) — the stack was replaced, nothing left to pop',
        );
      },
    );

    testWidgets(
      'tapping a NON-active tile (Профіль, tile 3) REPLACES the stack with '
      '/master/profile — regression: this tile used to be hard-coded to a '
      'null route and silently did nothing',
      (tester) async {
        final repo = _MockBookingRepository();
        when(
          () => repo.getMyBookings(
            statuses: any(named: 'statuses'),
            page: any(named: 'page'),
            size: any(named: 'size'),
            cancelToken: any(named: 'cancelToken'),
            sort: any(named: 'sort'),
            serviceIds: any(named: 'serviceIds'),
            from: any(named: 'from'),
            to: any(named: 'to'),
          ),
        ).thenAnswer((_) async => _page(<Booking>[]));

        final GoRouter router = await _pumpWithNavRoutes(tester, repo);
        await tester.pumpAndSettle();
        expect(router.canPop(), isFalse);

        await tester.tap(find.byKey(const Key('master-nav-tile-3')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(_profileMarker),
          findsOneWidget,
          reason: 'the Профіль tile must go(RouteNames.masterProfile)',
        );
        expect(
          router.canPop(),
          isFalse,
          reason: 'go (not push) — the stack was replaced, nothing left to pop',
        );
      },
    );

    testWidgets(
      'tapping the ALREADY-ACTIVE tile (Мої записи, tile 1) is a no-op — no '
      'duplicate /master/bookings is pushed onto itself',
      (tester) async {
        final repo = _MockBookingRepository();
        when(
          () => repo.getMyBookings(
            statuses: any(named: 'statuses'),
            page: any(named: 'page'),
            size: any(named: 'size'),
            cancelToken: any(named: 'cancelToken'),
            sort: any(named: 'sort'),
            serviceIds: any(named: 'serviceIds'),
            from: any(named: 'from'),
            to: any(named: 'to'),
          ),
        ).thenAnswer((_) async => _page(<Booking>[]));

        final GoRouter router = await _pumpWithNavRoutes(tester, repo);
        await tester.pumpAndSettle();
        expect(router.canPop(), isFalse);

        await tester.tap(find.byKey(const Key('master-nav-tile-1')));
        await tester.pumpAndSettle();

        // MUTATION GUARD: if `activeIndex` were ever wrong (e.g. left at the
        // default / copied from another screen), tile 1 would no longer
        // resolve to a null route and WOULD attempt to push
        // `RouteNames.masterBookings` (`/master/bookings`) — a path this
        // test's minimal router never registers, so go_router would throw
        // and `tester.takeException()` would be non-null. A silently passing
        // `canPop() == false` alone could not distinguish "correctly a
        // no-op" from "navigation crashed before mutating the stack", so both
        // are asserted.
        expect(tester.takeException(), isNull);
        expect(
          router.canPop(),
          isFalse,
          reason:
              'the already-active tile must resolve to a null route — no '
              'push, so the back stack stays empty',
        );
        expect(
          find.byType(MasterBookingsScreen),
          findsOneWidget,
          reason: 'still on the same screen — no navigation occurred',
        );
      },
    );

    testWidgets(
      'the nav bar coexists with a full timeline at a small viewport — no '
      'overflow, the last card still renders',
      (tester) async {
        // iPhone SE-class viewport — the smallest common target, and the one
        // most likely to expose a clipped last card or a RenderFlex overflow
        // between the timeline's own xxl bottom padding and the added bar.
        tester.view.physicalSize = const Size(375, 667);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final repo = _MockBookingRepository();
        when(
          () => repo.getMyBookings(
            statuses: any(named: 'statuses'),
            page: any(named: 'page'),
            size: any(named: 'size'),
            cancelToken: any(named: 'cancelToken'),
            sort: any(named: 'sort'),
            serviceIds: any(named: 'serviceIds'),
            from: any(named: 'from'),
            to: any(named: 'to'),
          ),
        ).thenAnswer(
          (_) async => _page(<Booking>[
            for (int i = 0; i < 6; i++)
              _booking(id: 'b$i', startAt: _kyivTodayAtUtc(8 + i)),
          ]),
        );

        // installOverflowGuard() (wired into pumpRoutedApp) fails this test
        // automatically on any RenderFlex overflow — see pump_app.dart.
        await _pumpWithNavRoutes(tester, repo);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(VelvetBottomNavBar), findsOne);

        // Phase 485 — the week grid builds every card (no culling); scroll
        // its shared vertical view to the bottom and the last card is there.
        final ScrollableState timelineScroll = tester.state<ScrollableState>(
          find
              .descendant(
                of: find.byKey(WeekTimeGrid.verticalScrollKey),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        timelineScroll.position.jumpTo(timelineScroll.position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        expect(
          find.byKey(WeekTimeGrid.cardKey('b5')),
          findsOneWidget,
          reason: 'the last booking card must still be reachable in the tree',
        );
        // The bar itself must sit fully inside the stressed viewport height —
        // a real clip (as opposed to a caught RenderFlex overflow banner)
        // would otherwise slip past the guard silently.
        expect(
          tester.getRect(find.byType(VelvetBottomNavBar)).bottom,
          lessThanOrEqualTo(667),
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // Screen protection (SEC)
  // -------------------------------------------------------------------------

  group('screen protection', () {
    testWidgets('acquires on mount and releases on dispose', (tester) async {
      final repo = _MockBookingRepository();
      when(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          page: any(named: 'page'),
          size: any(named: 'size'),
          cancelToken: any(named: 'cancelToken'),
          sort: any(named: 'sort'),
          serviceIds: any(named: 'serviceIds'),
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).thenAnswer((_) async => _page(<Booking>[]));

      final _CountingScreenProtection protection = _CountingScreenProtection();
      await tester.pumpApp(
        const MasterBookingsScreen(),
        overrides: <Object>[
          // Setup-hint dots (2026-10-30) are covered by
          // `velvet_bottom_nav_bar_setup_hints_test.dart`; pinned off here so the
          // real schedule/catalogue reads (5-min cache timers) never run.
          masterNavSetupHintsProvider.overrideWithValue(
            BookingLinkSetupHints.none,
          ),
          screenProtectionProvider.overrideWithValue(protection),
          bookingRepositoryProvider.overrideWithValue(repo),
          bookedDaysProvider.overrideWith((ref) async => <DateTime>{}),
        ],
      );
      await tester.pumpAndSettle();

      expect(protection.acquires, 1);
      expect(protection.releases, 0);

      // Replace the screen — this renders client names, so the protection
      // must not outlive it.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      expect(protection.releases, 1);
    });
  });

  // -------------------------------------------------------------------------
  // Phase 244 — working-hours window: the "no working hours" gray-state CTA
  // -------------------------------------------------------------------------

  group('working-hours window CTA (Phase 244)', () {
    testWidgets(
      'the no-working-hours CTA navigates to /schedule?date=<the day it was '
      'showing>, and MasterScheduleScreen pre-selects that date',
      (tester) async {
        final repo = _MockBookingRepository();
        when(
          () => repo.getMyBookings(
            statuses: any(named: 'statuses'),
            page: any(named: 'page'),
            size: any(named: 'size'),
            cancelToken: any(named: 'cancelToken'),
            sort: any(named: 'sort'),
            serviceIds: any(named: 'serviceIds'),
            from: any(named: 'from'),
            to: any(named: 'to'),
          ),
        ).thenAnswer((_) async => _page(<Booking>[]));

        String? capturedDateQueryParam;
        final GoRouter router = GoRouter(
          initialLocation: '/',
          routes: <RouteBase>[
            GoRoute(
              path: '/',
              builder: (BuildContext context, GoRouterState state) =>
                  const MasterBookingsScreen(),
            ),
            GoRoute(
              path: RouteNames.masterSchedule,
              builder: (BuildContext context, GoRouterState state) {
                capturedDateQueryParam = state.uri.queryParameters['date'];
                return const Scaffold(
                  body: SizedBox.shrink(key: _scheduleMarker),
                );
              },
            ),
          ],
        );

        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[
            // Setup-hint dots (2026-10-30) are covered by
            // `velvet_bottom_nav_bar_setup_hints_test.dart`; pinned off here so the
            // real schedule/catalogue reads (5-min cache timers) never run.
            masterNavSetupHintsProvider.overrideWithValue(
              BookingLinkSetupHints.none,
            ),
            screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
            bookingRepositoryProvider.overrideWithValue(repo),
            bookedDaysProvider.overrideWith((ref) async => <DateTime>{}),
            effectiveScheduleProvider.overrideWith2(
              (_) => _NoScheduleFake(_kyivToday),
            ),
          ],
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('master-bookings-no-schedule')),
          findsOneWidget,
          reason:
              'fixture guard: the gray state must be showing before the '
              'CTA is tapped',
        );

        await tester.tap(
          find.byKey(const Key('master-bookings-no-schedule-cta')),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(_scheduleMarker), findsOneWidget);
        expect(
          capturedDateQueryParam,
          toApiDate(_kyivToday),
          reason:
              'the CTA must route to /schedule?date=<the day the gray state '
              'was showing>, formatted through toApiDate',
        );
      },
    );
  });

  // ---------------------------------------------------------------------
  // Haptic cue contract — month grid (mobile-qa, 2026-08-14)
  // ---------------------------------------------------------------------
  //
  // `_BookingsDiscoveryViewState._stepMonth` fires
  // `HapticFeedback.selectionClick()` unconditionally whenever it runs — the
  // guard against a spring-back / a programmatic resync lives one layer
  // down, in `BookingsMonthCalendarPanel._resolveMonthPage`'s `delta == 0`
  // early return (that method only calls `widget.onStepMonth` — which
  // reaches `_stepMonth` — on a genuine COMMITTED page turn; see that
  // method's own doc). So this group mounts the REAL `MasterBookingsScreen`
  // — not a recording stand-in the way
  // `bookings_pager_commit_threshold_test.dart`'s `_PanelHost.onStepMonth`
  // is — because only the real widget tree actually reaches the real
  // `HapticFeedback.selectionClick()` call.
  group('haptic cue contract — month grid', () {
    late List<MethodCall> platformCalls;

    setUp(() {
      platformCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (
            MethodCall call,
          ) async {
            platformCalls.add(call);
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    int selectionClicks() => platformCalls
        .where(
          (MethodCall c) =>
              c.method == 'HapticFeedback.vibrate' &&
              c.arguments == 'HapticFeedbackType.selectionClick',
        )
        .length;

    const Key gridKey = Key('bookings-month-calendar-grid');
    // Phase 485 — the week header's title IS the month toggle.
    const Key toggleKey = WeekNavBar.titleKey;

    /// The same paused-before-lift technique as
    /// `bookings_pager_commit_threshold_test.dart`'s `_pausedForwardDrag` —
    /// not re-derived here, see that file's header for why the exact timing
    /// (8 real 40ms-spaced samples, then a pump PAST `VelocityTracker`'s own
    /// 40ms "assume stopped" cutoff with no further sample before `up()`)
    /// matters and why a trailing run of zero-delta samples is NOT a
    /// substitute.
    Future<void> pausedForwardDrag(
      WidgetTester tester,
      Finder finder, {
      required double fraction,
    }) async {
      final double width = tester.getRect(finder).width;
      const int steps = 8;
      final double dx = -(width * fraction) / steps;
      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(finder),
      );
      Duration stamp = Duration.zero;
      for (int i = 0; i < steps; i++) {
        stamp += const Duration(milliseconds: 40);
        await gesture.moveBy(Offset(dx, 0), timeStamp: stamp);
        // fixed-wait-ok: advancing the pointer-sample clock in lockstep with
        // the synthetic move timestamps, not waiting on a condition.
        await tester.pump(const Duration(milliseconds: 40));
      }
      // fixed-wait-ok: advancing past VelocityTracker's own 40ms "assume
      // stopped" cutoff, not waiting on a condition.
      await tester.pump(const Duration(milliseconds: 60));
      await gesture.up();
    }

    _MockBookingRepository emptyRepo() {
      final repo = _MockBookingRepository();
      when(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          page: any(named: 'page'),
          size: any(named: 'size'),
          cancelToken: any(named: 'cancelToken'),
          sort: any(named: 'sort'),
          serviceIds: any(named: 'serviceIds'),
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).thenAnswer((_) async => _page(<Booking>[]));
      return repo;
    }

    testWidgets(
      'CASE 1 (positive control): a committed month page turn fires exactly '
      'one haptic — proves the mock is wired and the cue is genuinely '
      'reachable, so the negative-only cases below mean something',
      (tester) async {
        await _pump(tester, emptyRepo());
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(toggleKey));
        await tester.pumpAndSettle();

        // Same fling this file's own "paging the month and collapsing" test
        // above already proves lands a genuine month step.
        await tester.fling(find.byKey(gridKey), const Offset(-300, 0), 800);
        // fixed-wait-ok: advancing past the 220 ms day-select debounce.
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        expect(
          selectionClicks(),
          1,
          reason:
              'a committed month page turn must fire the haptic cue exactly '
              'once — 0 would mean either the cue regressed or the mock is '
              'not wired, either of which would make every negative test '
              'below pass for the wrong reason.',
        );
      },
    );

    testWidgets(
      'CASE 2: a spring-back (under-threshold paused release) on the month '
      'grid fires no haptic',
      (tester) async {
        await _pump(tester, emptyRepo());
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(toggleKey));
        await tester.pumpAndSettle();

        // Establish a real committed turn first — see the day-rail sibling
        // group's header (`bookings_day_rail_test.dart`) for why: it keeps
        // this test meaningful rather than accidentally exercising a
        // first-interaction edge case this test isn't about.
        await pausedForwardDrag(tester, find.byKey(gridKey), fraction: 0.30);
        // fixed-wait-ok: advancing past the 220 ms day-select debounce.
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
        final int afterCommit = selectionClicks();

        await pausedForwardDrag(tester, find.byKey(gridKey), fraction: 0.20);
        await tester.pumpAndSettle();

        expect(
          selectionClicks(),
          afterCommit,
          reason:
              'a spring-back on the month grid must never fire the haptic '
              'cue.',
        );
      },
    );

    testWidgets('CASE 3: a strip tap onto a day in ANOTHER month is navigation, '
        'never a haptic-worthy commit', (tester) async {
      // Kyiv "today" pinned to a Thursday whose Mon->Sun week crosses into
      // the next month (2026-07-30, week 07-27..08-02).
      // future-date-ok: the month-boundary-crossing week is a STRUCTURAL calendar property that no now-relative helper can guarantee, and the instant only reaches the widget through the injected `clock: () => fixedNow` seam (never a wall-clock read), so this fixture is deterministic and carries no `isPast` risk.
      final DateTime fixedNow = DateTime.utc(2026, 7, 30, 10);
      await _pump(tester, emptyRepo(), clock: () => fixedNow);
      await tester.pumpAndSettle();
      final int beforeTap = selectionClicks();

      await tester.tap(find.byKey(weekStripDayKey(DateTime(2026, 8, 1))));
      // fixed-wait-ok: crossing any debounce a regression might add.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(selectionClicks(), beforeTap);
    });
  });
}

/// A fake `effectiveScheduleProvider` resolving [date] to NO_SCHEDULE for
/// every requested range — drives the master booking timeline's gray
/// "no working hours" empty state (Phase 244).
class _NoScheduleFake extends EffectiveScheduleNotifier {
  _NoScheduleFake(this._date);
  final DateTime _date;

  @override
  Future<List<EffectiveDay>> build(
    ScheduleScope scope,
    ScheduleRange range,
  ) async => <EffectiveDay>[
    EffectiveDay(
      date: _date,
      source: EffectiveSource.noSchedule,
      intervals: const <WorkInterval>[],
    ),
  ];
}

class _CountingScreenProtection extends ScreenProtectionManager {
  int acquires = 0;
  int releases = 0;

  @override
  void acquire() => acquires++;

  @override
  void release() => releases++;
}
