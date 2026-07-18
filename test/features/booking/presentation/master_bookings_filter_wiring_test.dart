// Phase 7.7 — the seam between the filter sheet and the QUERY.
//
// `bookings_filter_sheet_test.dart` pins what the sheet RESOLVES WITH. This
// file pins what the screen does with that value — a genuinely separate
// failure surface: a sheet can resolve perfectly while the screen overwrites
// the filters or (the nastiest one) mutates `_query` without going through
// `_setQuery`.
//
// Phase 7.8 retired sorting, so the sort groups are gone. What survives is the
// landing query's ordering assertion, which now pins the FIXED sort
// `MasterBookingsNotifier` sends.
//
// Assertions are made on the arguments the REPOSITORY receives, not on the
// screen's private state. That is the only observation point that proves the
// whole chain — sheet → `MasterBookingsQuery.of` → provider family → repo —
// actually carried the value to the wire.
//
// Every test mutation-verified; mutations recorded per group.
//
// Host-zone note: the only dates asserted here are explicit
// `DateTime(y, m, d)` literals fed through the stubbed picker, and
// `toApiDate` reads `.year/.month/.day` off the local value with no zone
// conversion. Identical under TZ=UTC and TZ=Europe/Kyiv.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/booking/application/booked_days_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/master_bookings_screen.dart';
import 'package:beautica_mobile/features/services/data/master_service_catalog_provider.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';

import 'package:beautica_mobile/shared/widgets/period_range_picker.dart';

import '../../../helpers/pump_app.dart';

class _MockBookingRepository extends Mock implements BookingRepository {}

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

/// One recorded `getMyBookings` call — every parameter this phase can change.
typedef _Call = ({
  int page,
  List<BookingStatus> statuses,
  List<String> serviceIds,
  DateTime? from,
  DateTime? to,
  BookingSort? sort,
});

MasterService _service(String id, String name) => MasterService(
  id: id,
  serviceDefId: 'def-$id',
  name: name,
  durationMinutes: 60,
);

final List<MasterService> _catalogue = <MasterService>[
  _service('svc-a', 'Манікюр з покриттям'),
  _service('svc-b', 'Педикюр'),
];

Booking _booking(String id) {
  final DateTime start = DateTime.utc(2026, 7, 20, 12);
  return Booking(
    id: id,
    masterId: 'm1',
    masterFirstName: 'Марія',
    masterLastName: 'Іванюк',
    masterType: 'INDEPENDENT_MASTER',
    clientId: 'c-$id',
    clientFirstName: 'Олена',
    clientLastName: 'Ковальчук',
    serviceId: 'svc-a',
    serviceName: 'Манікюр з покриттям',
    durationMinutes: 90,
    price: 650,
    startAt: start,
    endAt: start.add(const Duration(minutes: 90)),
    status: BookingStatus.confirmed,
    canReview: false,
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(BookingStatus.confirmed);
    registerFallbackValue(BookingSort.newest);
    registerFallbackValue(<BookingStatus>[]);
  });

  late _MockBookingRepository repo;
  late List<_Call> calls;

  setUp(() {
    repo = _MockBookingRepository();
    calls = <_Call>[];
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
        page: i.namedArguments[#page] as int,
        statuses: (i.namedArguments[#statuses] as Iterable<BookingStatus>)
            .toList(),
        serviceIds:
            (i.namedArguments[#serviceIds] as Iterable<String>?)?.toList() ??
            <String>[],
        from: i.namedArguments[#from] as DateTime?,
        to: i.namedArguments[#to] as DateTime?,
        sort: i.namedArguments[#sort] as BookingSort?,
      ));
      return PageResponse<Booking>(
        items: <Booking>[_booking('b1'), _booking('b2')],
        page: 0,
        totalPages: 1,
        totalElements: 2,
      );
    });
  });

  /// Pumps the screen under a REAL GoRouter.
  ///
  /// Not `pumpApp`: every one of this phase's sheets closes with the go_router
  /// `context.pop(value)` extension (raw `Navigator.pop` is banned in
  /// `lib/features`), and that throws "No GoRouter found in context" under a
  /// plain `MaterialApp`. A router-less harness therefore cannot exercise a
  /// single sheet-resolution path — and would have made every assertion below
  /// unreachable rather than merely failing.
  Future<void> pump(WidgetTester tester) async {
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
        bookedDaysProvider.overrideWith((ref) async => <DateTime>{}),
        // The service-filter option universe. Overridden DIRECTLY rather than
        // via `serviceRepositoryProvider` so no real Dio is reachable from this
        // tree (that omission is what leaks a 15s connect-timeout Timer).
        masterServiceCatalogProvider.overrideWith((ref) async => _catalogue),
      ],
    );
    await tester.pumpAndSettle();
  }

  Future<void> openFilters(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('master-bookings-filter-button')));
    await tester.pumpAndSettle();
  }

  Future<void> applyFilters(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('master-bookings-filter-apply')));
    await tester.pumpAndSettle();
  }

  group('the landing query', () {
    // MUTATION: changed `MasterBookingsNotifier`'s `_fixedSort` to
    // `BookingSort.oldest` → this test failed on both the enum and the
    // wireValue assertion. Restored.
    testWidgets('opens unfiltered, newest-first, page 0', (
      WidgetTester tester,
    ) async {
      await pump(tester);

      expect(calls, hasLength(1));
      expect(calls.single.page, 0);
      expect(calls.single.statuses, isEmpty);
      expect(calls.single.serviceIds, isEmpty);
      expect(calls.single.from, isNull);
      expect(calls.single.to, isNull);
      expect(calls.single.sort, BookingSort.newest);
      // Wire value as a LITERAL — a typo in the enum must fail here.
      expect(calls.single.sort!.wireValue, 'startsAt,desc');
    });
  });

  group('filters → query', () {
    // MUTATION: made `_applyFilters` pass `applied.statuses` as the
    // `serviceIds` and vice versa → this test failed. Restored.
    testWidgets('a multi-select status filter reaches the repository', (
      WidgetTester tester,
    ) async {
      await pump(tester);
      calls.clear();

      await openFilters(tester);
      await tester.tap(
        find.byKey(const Key('master-bookings-filter-status-confirmed')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('master-bookings-filter-status-cancelled')),
      );
      await tester.pumpAndSettle();
      await applyFilters(tester);

      expect(
        calls,
        hasLength(1),
        reason: 'the whole filter session is ONE request, not one per checkbox',
      );
      // «Скасовано» carries BOTH wire statuses; wire strings as literals.
      expect(
        calls.single.statuses.map((BookingStatus s) => s.wireValue).toSet(),
        <String>{'CONFIRMED', 'CANCELLED', 'DECLINED'},
      );
      expect(calls.single.page, 0);
    });

    // MUTATION: made `_applyFilters` drop `applied.serviceIds` → this test
    // failed. Restored.
    testWidgets(
      'a service filter reaches the repository as MasterService ids',
      (WidgetTester tester) async {
        await pump(tester);
        calls.clear();

        await openFilters(tester);
        final Finder row = find.byKey(
          const Key('master-bookings-filter-service-svc-b'),
        );
        await tester.scrollUntilVisible(
          row,
          80,
          scrollable: find
              .descendant(
                of: find.byKey(const Key('master-bookings-filter-sheet')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.tap(row);
        await tester.pumpAndSettle();
        await applyFilters(tester);

        expect(calls.single.serviceIds, <String>['svc-b']);
      },
    );

    // MUTATION: made `_openCalendar` ignore the picked range (return early
    // after the null check) → this test failed. Restored.
    //
    // MUTATION: made `_openCalendar` write `bounds.from` to BOTH ends → the
    // `to` assertion failed. Restored.
    //
    // This drives the REAL calendar through the rail's calendar button — the
    // whole `_openCalendar` → `showBookingsDateRangePicker` →
    // `normaliseBookingRange` → `MasterBookingsQuery.of` chain — because the
    // date bounds are the one parameter where an intermediate step
    // (a zone conversion, a `Duration(days:)` walk) can silently shift the
    // value by a day.
    testWidgets('a range picked in the calendar reaches the repository', (
      WidgetTester tester,
    ) async {
      await pump(tester);
      calls.clear();

      // The rail auto-centres on today at open, which scrolls its leading
      // calendar cell off the left edge — scroll BACK (negative delta) to
      // reach it.
      await tester.scrollUntilVisible(
        find.byKey(const Key('master-bookings-calendar-button')),
        -400,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('master-bookings-day-rail')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('master-bookings-calendar-button')),
      );
      await tester.pumpAndSettle();

      // The picker's window is anchored on the screen's captured "today", so
      // the two days are expressed relative to it rather than as literals.
      final DateTime today = DateTime.now();
      final DateTime start = DateTime(today.year, today.month, today.day);
      final DateTime end = DateTime(today.year, today.month, today.day + 4);

      for (final DateTime d in <DateTime>[start, end]) {
        final Finder cell = find.byKey(periodDayCellKey(d));
        await tester.scrollUntilVisible(
          cell,
          300,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.ensureVisible(cell);
        await tester.pumpAndSettle();
        await tester.tap(cell);
        await tester.pumpAndSettle();
      }

      await tester.tap(find.byKey(const Key('btn-range-picker-save')));
      await tester.pumpAndSettle();

      expect(calls, hasLength(1));
      expect(calls.single.from, start);
      expect(calls.single.to, end);
      // Date-only on both ends — an instant would make every tap a fresh
      // provider-family member.
      expect(calls.single.from!.hour, 0);
      expect(calls.single.from!.minute, 0);
    });
  });

  group('the header badge', () {
    // MUTATION: made `_activeFilterCount` return a constant 0 → this test
    // failed. Restored.
    //
    // This is the affordance that makes the filter-empty state legible: with no
    // badge, a filtered-to-nothing list is indistinguishable from "you have no
    // bookings", which is the top support question for this screen.
    testWidgets('reflects the REAL number of active filter groups', (
      WidgetTester tester,
    ) async {
      await pump(tester);
      expect(
        find.byKey(const Key('master-bookings-filter-badge')),
        findsNothing,
      );

      await openFilters(tester);
      await tester.tap(
        find.byKey(const Key('master-bookings-filter-status-completed')),
      );
      await tester.pumpAndSettle();
      final Finder svc = find.byKey(
        const Key('master-bookings-filter-service-svc-a'),
      );
      await tester.scrollUntilVisible(
        svc,
        80,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('master-bookings-filter-sheet')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(svc);
      await tester.pumpAndSettle();
      await applyFilters(tester);

      expect(
        find.byKey(const Key('master-bookings-filter-badge')),
        findsOneWidget,
      );
      expect(find.text('2'), findsOneWidget);
    });

    // MUTATION: made `_clearAllFilters` preserve the statuses → this test
    // failed. Restored.
    testWidgets('«Скинути фільтри» inside the sheet clears it back to nothing', (
      WidgetTester tester,
    ) async {
      await pump(tester);

      await openFilters(tester);
      await tester.tap(
        find.byKey(const Key('master-bookings-filter-status-completed')),
      );
      await tester.pumpAndSettle();
      await applyFilters(tester);
      expect(
        find.byKey(const Key('master-bookings-filter-badge')),
        findsOneWidget,
      );
      calls.clear();

      await openFilters(tester);
      await tester.tap(find.byKey(const Key('master-bookings-filter-reset')));
      await tester.pumpAndSettle();
      await applyFilters(tester);

      // NO new request — and that absence is the assertion, not a weakness.
      //
      // `MasterBookingsQuery` is the provider family KEY. A cleared query is
      // `==`-equal to the landing one only if EVERY field went back: a stray
      // status, a leftover serviceId, a surviving date bound or a changed sort
      // would each mint a different key, a different family member, and a
      // fresh fetch. So "the landing member was reused" is a stronger
      // statement about the whole query than inspecting one call's arguments.
      expect(
        calls,
        isEmpty,
        reason:
            'clearing must land back on the LANDING query — a cache hit on the '
            'existing family member, not a new one',
      );
      expect(
        find.byKey(const Key('master-bookings-filter-badge')),
        findsNothing,
      );
    });
  });

  group('no client-side re-sort', () {
    // MUTATION: added `..sort((a, b) => a.startAt.compareTo(b.startAt))` to
    // `_BookingsList`'s items → this test failed. Removed again.
    //
    // The server owns the order (backend 26.3). A client-side comparator would
    // silently defeat the sort the master just picked AND reshuffle
    // already-viewed rows on every load-more. Pinned by handing back a page
    // whose order DISAGREES with `startsAt` and asserting it renders verbatim.
    testWidgets(
      'renders the page in SERVER order even when it fights startsAt',
      (WidgetTester tester) async {
        final Booking later = _booking(
          'later',
        ).copyWith(startAt: DateTime.utc(2026, 8, 30, 9), price: 2000);
        final Booking earlier = _booking(
          'earlier',
        ).copyWith(startAt: DateTime.utc(2026, 7, 1, 9), price: 100);
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
          // A priceDesc response: expensive first, which is the OPPOSITE of both
          // startsAt orderings.
        ).thenAnswer(
          (_) async => PageResponse<Booking>(
            items: <Booking>[later, earlier],
            page: 0,
            totalPages: 1,
            totalElements: 2,
          ),
        );

        await pump(tester);

        // Compare the two cards' vertical positions: server order must survive.
        final double firstY = tester
            .getTopLeft(find.byKey(const Key('master-booking-card-later')))
            .dy;
        final double secondY = tester
            .getTopLeft(find.byKey(const Key('master-booking-card-earlier')))
            .dy;
        expect(
          firstY,
          lessThan(secondY),
          reason:
              'the expensive/later booking came FIRST from the server and must '
              'stay first — any client-side comparator would swap these',
        );
      },
    );
  });
}
