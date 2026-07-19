// Phase 7.7 — the seam between the filter sheet and the QUERY.
//
// Phase 7.11 — rewritten for `BookingsDayQuery` (Phase 7.9): there is no
// paging, no user-chosen sort, and no date RANGE any more — one Kyiv day,
// always `from == to`. What survives from 7.7/7.8 is the shape of the
// concern this file exists for: a sheet can resolve perfectly while the
// screen still fails to carry the value to the wire (or carries the WRONG
// half of a swapped pair) — a genuinely separate failure surface from
// `bookings_filter_sheet_test.dart`, which only pins what the sheet resolves
// WITH.
//
// Assertions are made on the arguments the REPOSITORY receives, not on the
// view's private state — the only observation point that proves the whole
// chain (sheet → `BookingsDayQuery.of` → provider family → repo) actually
// carried the value to the wire.
//
// Every test mutation-verified; mutations recorded per group.
//
// Host-zone note: the only dates asserted here are either the screen's own
// captured Kyiv "today" or explicit `DateTime(y, m, d)` literals fed through
// the stubbed picker, and `toApiDate` reads `.year/.month/.day` off the local
// value with no zone conversion. Identical under TZ=UTC and TZ=Europe/Kyiv.

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
import 'package:beautica_mobile/shared/formatters/api_date.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';

import 'package:beautica_mobile/shared/widgets/period_range_picker.dart';

import '../../../helpers/pump_app.dart';

class _MockBookingRepository extends Mock implements BookingRepository {}

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

/// Kyiv "today" — every landing query is scoped to this day (Phase 7.11).
DateTime get _kyivToday => dateOnly(toBeauticaTime(DateTime.now()));

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
    registerFallbackValue(BookingSort.oldest);
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
  /// plain `MaterialApp`.
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
    // MUTATION: changed `BookingsDayNotifier`'s fixed sort to
    // `BookingSort.newest` → this test failed on both the enum and the
    // wireValue assertion. Restored.
    testWidgets('opens on Kyiv "today", oldest-first, page 0', (
      WidgetTester tester,
    ) async {
      await pump(tester);

      expect(calls, hasLength(1));
      expect(calls.single.page, 0);
      expect(calls.single.statuses, isEmpty);
      expect(calls.single.serviceIds, isEmpty);
      expect(calls.single.from, _kyivToday);
      expect(calls.single.to, _kyivToday);
      expect(calls.single.sort, BookingSort.oldest);
      // Wire value as a LITERAL — a typo in the enum must fail here.
      expect(calls.single.sort!.wireValue, 'startsAt,asc');
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
      // The day is untouched by a status/service filter.
      expect(calls.single.from, _kyivToday);
      expect(calls.single.to, _kyivToday);
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

    // MUTATION: made `_applyFilters` fold `applied.from`/`applied.to` onto
    // the live query (reinstating the retired range concept) → this test
    // failed because the day silently drifted off Kyiv-today. Restored:
    // the sheet's «Дата» picks are discarded, by design — see
    // `bookings_discovery_view.dart`'s `_applyFilters` doc.
    testWidgets(
      'a date picked in the FILTER SHEET is discarded — day narrowing is the '
      'RAIL\'s job only',
      (WidgetTester tester) async {
        await pump(tester);
        calls.clear();

        await openFilters(tester);
        await tester.tap(find.byKey(const Key('master-bookings-filter-date')));
        await tester.pumpAndSettle();

        final DateTime pickDay = DateTime(
          _kyivToday.year,
          _kyivToday.month,
          _kyivToday.day + 5,
        );
        for (final DateTime d in <DateTime>[pickDay, pickDay]) {
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
        await applyFilters(tester);

        // Nothing about the live query actually CHANGED (statuses/serviceIds
        // are still empty, the day is still Kyiv-today) — so this is not
        // merely "the wire arguments still say today", it is that NO new
        // fetch fires at all: applying resolves to a query `==` the one
        // already resolved, which is the strongest possible proof the picked
        // date never reached `BookingsDayQuery.of`.
        expect(
          calls,
          isEmpty,
          reason:
              'the filter sheet\'s date picker must NOT move the live day — '
              'only the rail (and its calendar button) may. A request here '
              'would mean the picked date reached the query after all.',
        );
      },
    );

    // MUTATION: made `_openCalendar` ignore the picked value (return early
    // after the null check) → this test failed. Restored.
    //
    // MUTATION: made `_openCalendar` collapse to `bounds.to` instead of
    // `bounds.from` → the assertion failed. Restored.
    //
    // This drives the REAL calendar through the rail's calendar button — the
    // whole `_openCalendar` → `showBookingsDateRangePicker` →
    // `normaliseBookingRange` → `BookingsDayQuery.of` chain. A genuine RANGE
    // picked in the calendar collapses to its START day — `BookingsDayQuery`
    // (Phase 7.9) has no range to express any more.
    testWidgets(
      'a range picked in the calendar collapses to its START day on the wire',
      (WidgetTester tester) async {
        await pump(tester);
        calls.clear();

        // The rail auto-centres on Kyiv-today at open, which scrolls its
        // leading calendar cell off the left edge — scroll BACK (negative
        // delta) to reach it.
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

        // Deliberately NOT today — the current `_day` already IS Kyiv-today,
        // so a picked start equal to it would fire no request at all (an
        // unchanged query is a cache hit, not a fetch — see the sibling test
        // above). The start must actually differ for this test to observe
        // anything.
        final DateTime start = DateTime(
          _kyivToday.year,
          _kyivToday.month,
          _kyivToday.day + 2,
        );
        final DateTime end = DateTime(
          _kyivToday.year,
          _kyivToday.month,
          _kyivToday.day + 6,
        );

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
        // The screen debounces the resolved day the same way a rail tap
        // does — `_openCalendar` funnels through `_selectDay`.
        // fixed-wait-ok: advancing past the 220 ms day-selection debounce.
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        expect(calls, hasLength(1));
        expect(calls.single.from, start);
        expect(
          calls.single.to,
          start,
          reason:
              'from == to always — a picked RANGE collapses to its start '
              'day, it does not reintroduce a range on the wire',
        );
        expect(calls.single.from!.hour, 0);
        expect(calls.single.from!.minute, 0);
      },
    );
  });

  group('the header badge', () {
    // MUTATION: made `_activeFilterCount` return a constant 0 → this test
    // failed. Restored.
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
    //
    // MEDIUM-2 (7.9/7.10/7.11 consolidated audit) note: `bookingsDayProvider`
    // now holds a BOUNDED keepAlive cache (`_DayKeepAliveLru`, capacity 3 —
    // see `bookings_day_notifier.dart`'s header), not the plain autoDispose
    // this test used to assume. This test's own sequence — the unfiltered
    // landing fetch, then ONE filtered query — touches only 2 distinct
    // family members, comfortably inside that cap, so the unfiltered landing
    // member is NEVER evicted. Clearing back to it is therefore a CACHE HIT,
    // not a fresh fetch: `calls` stays EMPTY. This is precisely the
    // round-trip MEDIUM-2 exists to make cheap again — the retired screen's
    // 5-minute keepAlive gave it for free; 7.9's plain autoDispose regressed
    // it (this test used to assert the regressed behaviour, `hasLength(1)`,
    // as if it were correct); the bounded cache restores it. See
    // `bookings_day_notifier_test.dart`'s "bounded keepAlive cache" group
    // for the eviction-side guarantees (a 4th distinct day) this test does
    // not cover.
    testWidgets('«Скинути фільтри» inside the sheet clears it back to the '
        'unfiltered landing state — served from the bounded cache, no '
        'redundant fetch', (WidgetTester tester) async {
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

      expect(
        calls,
        isEmpty,
        reason:
            'clearing back to the unfiltered landing day re-issued a '
            'request — the bounded keepAlive cache (MEDIUM-2) should have '
            'served it from the still-alive unfiltered family member '
            'instead',
      );
      expect(
        find.byKey(const Key('master-bookings-filter-badge')),
        findsNothing,
      );
    });
  });
}
