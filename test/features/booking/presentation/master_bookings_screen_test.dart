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
//     (`dateOnly(toBeauticaTime(DateTime.now()))`);
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
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/api_date.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:beautica_mobile/shared/widgets/velvet_bottom_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/pump_app.dart';

// Fixture identities injected BY these tests — NOT app copy, and
// locale-invariant by construction (a person's name is not translated). This
// is the case the `i18n-finder-ok` annotation exists for.
const String _clientFull = 'Олена Ковальчук';
const String _otherClientFirst = 'Ігор';
const String _otherClientLast = 'Мороз';

/// Kyiv "today", derived through the EXACT SAME production function the
/// screen uses — never a literal. See the file header (LOW #334).
DateTime get _kyivToday => dateOnly(toBeauticaTime(DateTime.now()));

/// Whether the host's local calendar day currently differs from Kyiv's —
/// mirrors `bookings_day_rail_test.dart`'s `_hostObservesTransition` skip
/// pattern for the DST guards. Dart has no clock-injection seam anywhere in
/// this codebase (`grep -rl package:clock` is empty), and the screen calls
/// `DateTime.now()` directly in `initState`, so the ONLY way to distinguish
/// "used Kyiv" from "used host-local" is to run at a moment the two actually
/// disagree — which does not hold for the whole day even on a non-Kyiv host.
bool _hostObservesKyivSkew() => dateOnly(DateTime.now()) != _kyivToday;

String _kyivSkewSuffix(bool observed) => observed
    ? ''
    : ' [SKIPPED on this host at this instant: local time '
          '${DateTime.now()} and Kyiv time currently name the same calendar '
          'day, so a regression to host-local "today" cannot be observed '
          'right now — covered whenever the host runs during the Kyiv/host '
          'skew window, e.g. on CI\'s UTC runner]';

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
  final DateTime start =
      startAt ?? _kyivToday.toUtc().add(const Duration(hours: 12));
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
    overrides: <Object>[
      screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
      bookingRepositoryProvider.overrideWithValue(repo),
      bookedDaysProvider.overrideWith((ref) async => bookedDays),
    ],
  );
}

const Key _servicesMarker = Key('stub-services-screen');

/// Same as [_pump], plus a stub `RouteNames.services` destination so nav-tile
/// taps that push it can be observed landing. Returns the [GoRouter] so tests
/// can assert `canPop()`/the mounted screen after a tap.
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
        // Unfiltered (the landing day): one booking. Any status filter:
        // nothing matches it.
        when(
          () => repo.getMyBookings(
            statuses: any(named: 'statuses', that: isEmpty),
            page: any(named: 'page'),
            size: any(named: 'size'),
            sort: any(named: 'sort'),
            serviceIds: any(named: 'serviceIds'),
            from: any(named: 'from'),
            to: any(named: 'to'),
          ),
        ).thenAnswer((_) async => _page(<Booking>[_booking(id: 'b1')]));
        when(
          () => repo.getMyBookings(
            statuses: any(named: 'statuses', that: isNotEmpty),
            page: any(named: 'page'),
            size: any(named: 'size'),
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
    // `bookings_day_rail_test.dart` has a plain `test()` (not `testWidgets`)
    // asserting `kRailLeadItems + dayIndex == 1 + dayIndex`. That assertion
    // is SELF-REFERENTIAL: it inlines `kRailLeadItems` on both sides of its
    // own comparison and never calls `BookingsDiscoveryView._centreRailOn`,
    // the ACTUAL production call site (`bookings_discovery_view.dart`'s
    // `final int itemIndex = kRailLeadItems + dayIndex;`). Proven by
    // mutation: hardcoding `_centreRailOn` to `2 + dayIndex` (the design's
    // retired two-lead-item formula, from before «Всі» was dropped) leaves
    // EVERY test in this file green — including that one — because nothing
    // anywhere actually observes the rail's post-open SCROLL POSITION.
    //
    // This test closes that gap by asserting the real, rendered outcome: the
    // initially selected day's chip must land centred in the rail's visible
    // viewport after the first frame. An off-by-one lead item shifts it by
    // exactly one `kRailItemExtent` (62dp) — comfortably outside the
    // tolerance below, which only has to absorb sub-pixel layout rounding.
    testWidgets(
      'the rail auto-centres the initially selected day in its viewport — '
      'an off-by-one lead-item offset would land it one full cell off',
      (tester) async {
        final repo = _MockBookingRepository();
        when(
          () => repo.getMyBookings(
            statuses: any(named: 'statuses'),
            page: any(named: 'page'),
            size: any(named: 'size'),
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
        final Offset chipCenter = tester.getCenter(
          find.byKey(dayChipKey(_kyivToday)),
        );

        expect(
          (chipCenter.dx - railRect.center.dx).abs(),
          lessThan(kRailItemExtent / 2),
          reason:
              'today\'s chip is not centred in the rail — the lead-item '
              'offset `_centreRailOn` uses to convert a day index into a '
              'scroll target has drifted from `kRailLeadItems`.',
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
            sort: any(named: 'sort'),
            serviceIds: any(named: 'serviceIds'),
            from: any(named: 'from'),
            to: any(named: 'to'),
          ),
        ).thenAnswer((_) async => _page(<Booking>[_booking(id: 'b1')]));

        final DateTime dayA = railDayAt(_kyivToday, 2);
        final DateTime dayB = railDayAt(_kyivToday, 3);

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

        final DateTime day1 = railDayAt(_kyivToday, 1);
        final DateTime day2 = railDayAt(_kyivToday, 2);
        final DateTime day3 = railDayAt(_kyivToday, 3);

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

    testWidgets('DISTINGUISHES Kyiv "today" from host "today"'
        '${_kyivSkewSuffix(_hostObservesKyivSkew())}', (tester) async {
      final repo = _MockBookingRepository();
      DateTime? capturedFrom;
      when(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          page: any(named: 'page'),
          size: any(named: 'size'),
          sort: any(named: 'sort'),
          serviceIds: any(named: 'serviceIds'),
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).thenAnswer((Invocation i) async {
        capturedFrom = i.namedArguments[#from] as DateTime?;
        return _page(<Booking>[]);
      });

      await _pump(tester, repo);
      await tester.pumpAndSettle();

      expect(
        capturedFrom,
        isNot(dateOnly(DateTime.now())),
        reason:
            'The landing query matched host "today" — the screen must use '
            'Kyiv "today" (toBeauticaTime), not DateTime.now() directly.',
      );
    }, skip: !_hostObservesKyivSkew());
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
  // pass a bare `findsOneWidget`; (b) a non-active tile still pushes; (c) the
  // already-active tile is a no-op, so a stray tap never stacks a duplicate
  // `/master/bookings` on top of itself; (d) the bar coexists with the
  // timeline without an overflow at a small viewport.

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

    testWidgets(
      'tapping a NON-active tile (Послуги, tile 0) pushes /services and '
      'leaves this screen poppable',
      (tester) async {
        final repo = _MockBookingRepository();
        when(
          () => repo.getMyBookings(
            statuses: any(named: 'statuses'),
            page: any(named: 'page'),
            size: any(named: 'size'),
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
          reason: 'the Послуги tile must push RouteNames.services',
        );
        expect(
          router.canPop(),
          isTrue,
          reason: 'push (not go) — the origin must stay on the back stack',
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
            sort: any(named: 'sort'),
            serviceIds: any(named: 'serviceIds'),
            from: any(named: 'from'),
            to: any(named: 'to'),
          ),
        ).thenAnswer(
          (_) async => _page(<Booking>[
            for (int i = 0; i < 6; i++)
              _booking(
                id: 'b$i',
                startAt: _kyivToday.toUtc().add(Duration(hours: 8 + i)),
              ),
          ]),
        );

        // installOverflowGuard() (wired into pumpRoutedApp) fails this test
        // automatically on any RenderFlex overflow — see pump_app.dart.
        await _pumpWithNavRoutes(tester, repo);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(VelvetBottomNavBar), findsOne);
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
}

class _CountingScreenProtection extends ScreenProtectionManager {
  int acquires = 0;
  int releases = 0;

  @override
  void acquire() => acquires++;

  @override
  void release() => releases++;
}
