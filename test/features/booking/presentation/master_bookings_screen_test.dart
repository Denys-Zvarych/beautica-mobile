// Phase 7.6 — «Мої записи» for the independent master.
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
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/features/booking/application/booked_days_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/master_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_day_rail.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_timeline_grid.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_booking_card.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/my_bookings_states.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/features/schedule/presentation/effective_schedule_notifier.dart';
import 'package:beautica_mobile/features/schedule/presentation/schedule_range.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/api_date.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:beautica_mobile/shared/widgets/velvet_bottom_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/booking_fixture_dates.dart';
import '../../../helpers/pump_app.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

// Fixture identities injected BY these tests — NOT app copy, and
// locale-invariant by construction (a person's name is not translated). This
// is the case the `i18n-finder-ok` annotation exists for.
const String _clientFull = 'Олена Ковальчук';
const String _otherClientFirst = 'Ігор';
const String _otherClientLast = 'Мороз';

/// Kyiv "today", derived through the EXACT SAME production function the
/// screen uses — never a literal. See the file header (LOW #334).
DateTime get _kyivToday => kyivToday(DateTime.now);

/// The days of [_kyivToday]'s own Mon→Sun week, EXCLUDING today itself.
///
/// The rail is a week pager now: it renders exactly the seven days of one
/// week, so a test day has to come from THIS week or it is simply not on
/// screen to tap. `railDayAt(_kyivToday, +n)` — how these tests used to pick
/// their days — silently walks off the visible page whenever the suite runs
/// late in the week, which would have made the rail tests pass or fail by
/// weekday. Excluding today keeps a tap on any of these a REAL selection
/// change (and therefore a real new fetch), which the debounce test's call
/// count depends on.
///
/// Always exactly six entries, on every weekday.
List<DateTime> get _otherDaysThisWeek {
  final DateTime monday = mondayOf(_kyivToday);
  return <DateTime>[for (int i = 0; i < 7; i++) railDayAt(monday, i)]
    ..removeWhere((DateTime d) => d == _kyivToday);
}

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
    ],
  );
  await tester.pumpRoutedApp(
    router,
    overrides: <Object>[
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
      'retry refetches the CURRENTLY selected day, not the landing day',
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

        // Landing day failed.
        expect(froms, <DateTime?>[_kyivToday]);

        // Move the rail to a DIFFERENT day; that day fails too.
        final DateTime otherDay = railDayAt(_kyivToday, 1);
        await tester.tap(find.byKey(dayChipKey(otherDay)));
        // fixed-wait-ok: advancing past the 220 ms day-select debounce.
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        expect(
          froms.last,
          otherDay,
          reason: 'fixture guard: the rail tap did not re-scope the query',
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
              'retry refetched ${froms.single} instead of the selected day '
              '$otherDay — onRetry is bound to a STALE query, so the '
              'error state can never clear on any day but the landing one.',
        );
        expect(froms.single, isNot(_kyivToday));
      },
    );

    testWidgets(
      'renders a card per booking INSIDE the timeline grid — no vertical '
      'list survives',
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

        expect(find.byType(BookingsTimelineGrid), findsOne);
        expect(
          find.byKey(const Key('master-bookings-list')),
          findsNothing,
          reason: 'the retired vertical card list must not resurface',
        );
        expect(find.byType(MasterBookingCard), findsNWidgets(2));
        expect(
          find.text(_clientFull),
          findsOne,
        ); // i18n-finder-ok: test fixture name, not app copy
        expect(
          find.text('$_otherClientFirst $_otherClientLast'),
          findsOne,
        ); // i18n-finder-ok: test fixture name, not app copy
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
    testWidgets('TRUE empty (no filters, an empty day) offers no reset', (
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
      ).thenAnswer((_) async => _page(<Booking>[]));

      await _pump(tester, repo);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('master-bookings-empty')), findsOne);
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
  // Day rail behaviour
  // -------------------------------------------------------------------------

  group('day rail', () {
    // MUTATION-COVERAGE NOTE — why this test exists
    // ------------------------------------------------------------------
    // `bookings_day_rail_test.dart` pins the rail's week ARITHMETIC in
    // isolation (unit-level: `mondayOf`, `railWeekIndex`), but never resolves
    // `_railController`'s `initialPage` — the ACTUAL production call site. A
    // pure arithmetic pin can pass while the real, rendered outcome is wrong
    // (or vice versa), because nothing anywhere else observes which week the
    // rail actually OPENS on.
    //
    // ⚠ CONTRACT CHANGED (week-pager rework, this session). This test used to
    // assert "today is the LEFTMOST chip", which was the retired
    // `_alignRailTodayFirst`'s design decision and is not expressible any
    // more: the rail now shows exactly one Mon→Sun week, so the leftmost chip
    // is that week's MONDAY, by construction, for every possible selection.
    // What survives — and is what that assertion was really protecting — is
    // that the rail opens on the week the master is actually working, with
    // today visibly on it, rather than parked at the start of its multi-year
    // span. An off-by-one in `railWeekIndex` lands the rail a full seven days
    // away, which this catches loudly.
    //
    // Geometry note (post-calendar-button-retirement, Phase 7.16):
    // `master-bookings-day-rail`'s key sits on the pager itself, which is the
    // ENTIRE rail — the calendar button that used to live beside it as a
    // `Row` sibling is gone outright, not merely un-pinned. Each week page
    // carries a SYMMETRIC horizontal `VelvetSpacing.lg` inset, so the week's
    // Monday lands at `railRect.left + VelvetSpacing.lg`.
    testWidgets(
      'the rail opens on the week CONTAINING today, Monday leftmost — not '
      'parked at the start of its span',
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

        await _pump(tester, repo);
        await tester.pumpAndSettle();

        final Rect railRect = tester.getRect(
          find.byKey(const Key('master-bookings-day-rail')),
        );

        // Real rendered geometry, not the controller's `page` — an index bug
        // could move the controller while leaving the ON-SCREEN result wrong
        // (or vice versa), so this asserts what the master actually sees.
        expect(
          find.byKey(dayChipKey(_kyivToday)),
          findsOne,
          reason:
              'today is not on the rail\'s opening page — the rail opened on '
              'the wrong week (or parked at the start of its span).',
        );

        final DateTime monday = mondayOf(_kyivToday);
        expect(
          tester.getRect(find.byKey(dayChipKey(monday))).left,
          closeTo(railRect.left + VelvetSpacing.lg, 1.5),
          reason:
              'the opening page\'s leftmost chip is not this week\'s Monday '
              'at the rail\'s leading inset — the rail came to rest between '
              'two weeks.',
        );
        // The whole week is there, both ends — a page that rendered a
        // partial week would still satisfy the two checks above.
        expect(find.byKey(dayChipKey(railDayAt(monday, 6))), findsOne);
        expect(
          find.byKey(dayChipKey(railDayAt(monday, -1))),
          findsNothing,
          reason:
              'the PREVIOUS week\'s Sunday is on screen — the rail is showing '
              'a mid-week span, which the week pager must make unreachable.',
        );
      },
    );

    testWidgets(
      'past weeks remain reachable by paging left — the opening page does '
      'not clamp the rail\'s past range',
      (tester) async {
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
        calls.clear(); // drop the initial (today) fetch

        // The Monday of the week BEFORE this one — one page turn back, and
        // outside the opening page by construction (not merely "far away",
        // which is what the retired continuous strip needed to defeat its
        // cache extent).
        final DateTime pastDay = railDayAt(mondayOf(_kyivToday), -7);

        await tester.fling(
          find.byKey(const Key('master-bookings-day-rail')),
          const Offset(400, 0),
          800,
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(dayChipKey(pastDay)),
          findsOne,
          reason:
              'the previous week did not become reachable by paging left — '
              'the opening page may have clamped the rail\'s range instead '
              'of only setting its resting position.',
        );

        // And genuinely tappable — not just present in the tree.
        await tester.tap(find.byKey(dayChipKey(pastDay)));
        // fixed-wait-ok: advancing past the 220 ms rail-tap debounce.
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        expect(
          calls.length,
          1,
          reason: 'tapping the scrolled-to past day did not issue a request.',
        );
        expect(calls.single.$1, pastDay);
        expect(calls.single.$2, pastDay);
      },
    );

    // ── The two pagers must not desync ────────────────────────────────────
    //
    // The panel now stacks TWO horizontal pagers: the rail's week pager and
    // the expanded grid's month pager. `bookings_discovery_view.dart`'s
    // `_selectDay` doc states the contract they hold between them — every
    // move that changes the month SELECTS, and `_selectImmediate` pages the
    // rail to the selected day's own week, so the label, the rail and the
    // query all stay derived from the one `_day`.
    //
    // The dangerous state is the one this test drives: page the MONTH, then
    // COLLAPSE. Nothing else in the suite exercises the handoff — the
    // rebuild-isolation suite pins the month step's own query/label effects
    // with the calendar left open, and never looks at the rail underneath it.
    // A regression that (say) relabelled without paging the rail would leave
    // the master looking at August over July's week with no chip selected,
    // and every other test would stay green.
    testWidgets(
      'paging the month and collapsing leaves the label AND the rail on the '
      'new month — the two pagers stay derived from one selected day',
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

        await _pump(tester, repo);
        await tester.pumpAndSettle();

        String label() => tester
            .widget<Text>(
              find.byKey(const Key('bookings-month-calendar-label')),
            )
            .data!;

        // The label is present while COLLAPSED — it always was — and must
        // still be present while OPEN, which is the whole user-facing
        // complaint this rework answers ("it disappears").
        final String labelCollapsed = label();

        await tester.tap(
          find.byKey(const Key('bookings-month-calendar-toggle')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('bookings-month-calendar-label')),
          findsOneWidget,
          reason:
              'the month+year label vanished when the calendar opened — the '
              'exact regression this rework exists to fix',
        );
        expect(label(), labelCollapsed);

        // A horizontal page turn on the grid — the only month-navigation
        // mechanism left. `fling`, not `drag`: PageScrollPhysics resolves the
        // turn from velocity.
        await tester.fling(
          find.byKey(const Key('bookings-month-calendar-grid')),
          const Offset(-300, 0),
          800,
        );
        // fixed-wait-ok: advancing past the 220 ms day-select debounce.
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        final String labelStepped = label();
        expect(
          labelStepped,
          isNot(labelCollapsed),
          reason:
              'fixture guard: the fling did not turn the month page at all, '
              'so nothing below is proven',
        );

        // Collapse back down. The rail is what the master now sees.
        await tester.tap(
          find.byKey(const Key('bookings-month-calendar-toggle')),
        );
        await tester.pumpAndSettle();

        expect(
          label(),
          labelStepped,
          reason:
              'collapsing reverted the label to the pre-step month — the '
              'label is being derived from something other than the '
              'selection',
        );

        final DateTime stepped = tester
            .widget<BookingsDayRail>(find.byType(BookingsDayRail))
            .selectedDay;
        expect(
          find.byKey(dayChipKey(stepped)),
          findsOneWidget,
          reason:
              'the rail is not showing the week containing the stepped-to '
              'day — the two pagers desynced, so the collapsed strip shows '
              'one month under another month\'s label',
        );
        expect(
          tester.getRect(find.byKey(dayChipKey(mondayOf(stepped)))).left,
          closeTo(
            tester
                    .getRect(find.byKey(const Key('master-bookings-day-rail')))
                    .left +
                VelvetSpacing.lg,
            1.5,
          ),
          reason:
              'the rail landed mid-week after the month step — animateToPage '
              'must settle on a whole week',
        );
      },
    );

    testWidgets(
      'the dots do NOT change when a day is selected — they come from a '
      'filter-independent provider',
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

        // From THIS week — the rail pages by week now, so a day outside it
        // is not on screen at all. See [_otherDaysThisWeek].
        final List<DateTime> week = _otherDaysThisWeek;
        final DateTime dayA = week[0];
        final DateTime dayB = week[1];

        // Two booked days, neither of which is the day we will narrow TO.
        await _pump(tester, repo, bookedDays: <DateTime>{dayA, dayB});
        await tester.pumpAndSettle();

        expect(find.byKey(dayDotKey(dayA)), findsOne);
        expect(find.byKey(dayDotKey(dayB)), findsOne);

        await tester.tap(find.byKey(dayChipKey(dayA)));
        // This test asserts the dots do NOT change, so there is no widget
        // transition to await — the 220 ms query debounce has to be
        // advanced explicitly for the filtered refetch to have happened at
        // all.
        // fixed-wait-ok: advancing the 220 ms query debounce.
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        // BOTH dots survive.
        expect(find.byKey(dayDotKey(dayA)), findsOne);
        expect(
          find.byKey(dayDotKey(dayB)),
          findsOne,
          reason:
              'A dot vanished under a day selection — the rail is reading a '
              'filtered set instead of bookedDaysProvider.',
        );
      },
    );

    testWidgets(
      'selecting a day sends from == to, and exactly ONE request (debounce)',
      (tester) async {
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
          return _page(<Booking>[_booking(id: 'b1')]);
        });

        await _pump(tester, repo);
        await tester.pumpAndSettle();
        calls.clear(); // drop the initial (landing-day) fetch

        // Three days of THIS week, none of them today — see
        // [_otherDaysThisWeek]. `day3` must be a genuine selection CHANGE or
        // the surviving tap would resolve to the family member already
        // resolved and fire no request at all, silently turning the call
        // count below into an assertion about nothing.
        final List<DateTime> week = _otherDaysThisWeek;
        final DateTime day1 = week[0];
        final DateTime day2 = week[1];
        final DateTime day3 = week[2];

        // A fling across the rail lands several taps in quick succession.
        // Without the debounce each is a new family member and a new
        // request. The debounce window IS the subject under test: these
        // 40 ms gaps must sit INSIDE the 220 ms window (so the first two
        // taps are coalesced away), and the final settle must sit OUTSIDE
        // it (so the surviving tap fires).
        await tester.tap(find.byKey(dayChipKey(day1)));
        // fixed-wait-ok: 40 ms gap, inside the 220 ms debounce window.
        await tester.pump(const Duration(milliseconds: 40));
        await tester.tap(find.byKey(dayChipKey(day2)));
        // fixed-wait-ok: 40 ms gap, inside the 220 ms debounce window.
        await tester.pump(const Duration(milliseconds: 40));
        await tester.tap(find.byKey(dayChipKey(day3)));
        // fixed-wait-ok: advancing past the 220 ms debounce so the surviving tap fires.
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        expect(
          calls.length,
          1,
          reason:
              'Three rapid chip taps issued ${calls.length} requests — the '
              'debounce is not holding.',
        );
        final (DateTime? from, DateTime? to) = calls.single;
        expect(from, day3);
        expect(to, day3);
        expect(from, to, reason: 'a single-day selection is from == to');
      },
    );
  });

  // -------------------------------------------------------------------------
  // The initial day is Kyiv "today"
  // -------------------------------------------------------------------------

  group('initial day', () {
    testWidgets('the landing fetch is scoped to Kyiv "today"', (tester) async {
      final repo = _MockBookingRepository();
      DateTime? capturedFrom;
      DateTime? capturedTo;
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
        capturedTo = i.namedArguments[#to] as DateTime?;
        return _page(<Booking>[]);
      });

      await _pump(tester, repo);
      await tester.pumpAndSettle();

      expect(capturedFrom, _kyivToday);
      expect(capturedTo, _kyivToday);
      // Today with no bookings on it STAYS the selected day — no auto-jump.
      final SemanticsHandle handle = tester.ensureSemantics();
      expect(
        tester
            .getSemantics(find.byKey(dayChipKey(_kyivToday)))
            .flagsCollection
            .isSelected
            .toBoolOrNull(),
        isTrue,
      );
      handle.dispose();
    });

    // mobile-qa (2026-07-22) — DE-SKIPPED VIA THE CLOCK SEAM.
    //
    // This guard used to carry `skip: !_hostObservesKyivSkew()`, i.e. it only
    // ran at an instant when the host's own calendar day happened to differ
    // from Kyiv's — roughly a 3h/24h window on a UTC runner, and never on a
    // Kyiv-time host. It was empirically confirmed to be SKIPPING. The
    // dedicated `TZ=Europe/Kyiv` CI step does not rescue it either: that step
    // runs `bookings_day_rail_test.dart` only, and under `TZ=Europe/Kyiv` the
    // skew is zero by construction, so the guard would skip there too. In
    // other words: the single test standing between this screen and a
    // host-local landing query was running approximately never.
    //
    // `bookings_discovery_view.dart` now reads `clockProvider` instead of
    // calling `DateTime.now()` directly, so "now" can be PINNED and the skew
    // manufactured on every run. No `skip:`.
    //
    // WHY A UTC-FLAGGED PINNED INSTANT IS THE RIGHT WITNESS: the injected
    // value is what a regressed `dateOnly(<clock>())` would read its
    // `.year/.month/.day` off. Pinning a UTC instant therefore makes the
    // naive reading resolve to the UTC calendar day on EVERY host — exactly
    // the CI runner's situation — instead of depending on the developer
    // machine's zone. The correct reading (`toBeauticaTime` first) resolves
    // to the NEXT day. The two are unconditionally different.
    testWidgets('DISTINGUISHES Kyiv "today" from a naive host reading', (
      tester,
    ) async {
      final DateTime fixedNow = _kyivSkewInstantUtc();
      final DateTime kyivDay = dateOnly(toBeauticaTime(fixedNow));
      final DateTime naiveDay = dateOnly(fixedNow);

      // Fixture guard — if these ever coincide the assertions below prove
      // nothing, and this must fail loudly rather than pass vacuously.
      expect(
        kyivDay,
        isNot(naiveDay),
        reason:
            'the pinned instant no longer straddles Kyiv midnight, so the '
            'Kyiv-vs-naive distinction is unobservable and every assertion '
            'below would pass for the wrong reason',
      );

      final repo = _MockBookingRepository();
      DateTime? capturedFrom;
      DateTime? capturedTo;
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
        capturedTo = i.namedArguments[#to] as DateTime?;
        return _page(<Booking>[]);
      });

      await _pump(tester, repo, clock: () => fixedNow);
      await tester.pumpAndSettle();

      expect(
        capturedFrom,
        kyivDay,
        reason:
            'The landing query did not land on the KYIV calendar day of the '
            'pinned instant. The screen must derive its opening day through '
            'toBeauticaTime, never off the raw clock value.',
      );
      expect(
        capturedFrom,
        isNot(naiveDay),
        reason:
            'The landing query matched the NAIVE (host/UTC) calendar day — '
            'toBeauticaTime has been dropped from the derivation.',
      );
      expect(capturedTo, kyivDay, reason: 'a single-day query is from == to');
    });
  });

  // -------------------------------------------------------------------------
  // Count
  // -------------------------------------------------------------------------

  group('count', () {
    testWidgets('the count reflects totalElements, not the loaded page', (
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
          <Booking>[_booking(id: 'b1'), _booking(id: 'b2')],
          totalPages: 6,
          totalElements: 57,
        ),
      );

      await _pump(tester, repo);
      await tester.pumpAndSettle();

      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(MasterBookingsScreen)),
      );
      expect(find.text(l10n.masterBookingsCount(57)), findsOne);
      expect(
        find.text(l10n.masterBookingsCount(2)),
        findsNothing,
        reason:
            'The count showed items.length (this page) rather than the '
            'server\'s totalElements.',
      );
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

        // ADDENDUM 9 (`bookings_timeline_grid.dart`): the timeline culls cards
        // planned more than 1.5 viewports below the scroll offset, replacing
        // them with an identically-sized placeholder. At this deliberately
        // tiny 375x667 viewport — shrunk further by the app bar and the nav
        // bar this test exists to stress — the day's last card falls past that
        // edge, which is the optimisation working as intended and not what
        // this case is about. Scroll the timeline to the bottom first, so the
        // assertion below stays about the card being REACHABLE rather than
        // about where the culling window happens to land on one device size.
        final ScrollableState timelineScroll = tester.state<ScrollableState>(
          find
              .descendant(
                of: find.byType(BookingsTimelineGrid),
                matching: find.byType(Scrollable),
              )
              .first,
        );

        // PIN THE REASON b5 IS ABSENT, NOT JUST THAT SCROLLING BRINGS IT BACK.
        // Scrolling first would otherwise let this case keep passing for the
        // WRONG reason — a card that stopped being built at all, or one lost
        // to a clip, also "appears" once you scroll to it. Asserting the
        // placeholder is present, and that it sits BELOW the fold, says
        // exactly what the ADDENDUM 9 window is supposed to have done: the
        // card is off-screen and deliberately deferred, not missing.
        final Finder culledB5 = find.byKey(
          const ValueKey<String>('timeline-card-culled-b5'),
        );
        expect(
          culledB5,
          findsOneWidget,
          reason:
              'b5 should be absent at rest ONLY because the culling window '
              'deferred it. If this fails, the card is missing for some other '
              'reason and the scroll below would mask it — do not "fix" this '
              'by deleting the assertion.',
        );
        expect(
          tester.getRect(culledB5).top,
          greaterThanOrEqualTo(
            tester.getRect(find.byType(BookingsTimelineGrid)).bottom - 0.5,
          ),
          reason:
              'b5 was culled while still inside the timeline viewport — a '
              'blank box on screen at 375x667. Culling must only ever defer '
              'what is already below the fold.',
        );

        timelineScroll.position.jumpTo(timelineScroll.position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        expect(
          find.byKey(const Key('master-booking-card-b5')),
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
            screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
            bookingRepositoryProvider.overrideWithValue(repo),
            bookedDaysProvider.overrideWith((ref) async => <DateTime>{}),
            effectiveScheduleProvider.overrideWith(
              () => _NoScheduleFake(_kyivToday),
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
}

/// A fake `effectiveScheduleProvider` resolving [date] to NO_SCHEDULE for
/// every requested range — drives the master booking timeline's gray
/// "no working hours" empty state (Phase 244).
class _NoScheduleFake extends EffectiveScheduleNotifier {
  _NoScheduleFake(this._date);
  final DateTime _date;

  @override
  Future<List<EffectiveDay>> build(ScheduleRange range) async => <EffectiveDay>[
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
