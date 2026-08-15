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
//
// ## Phase 7.13 — Дата retired
//
// The filter sheet's «Дата» section is gone (there is nothing left in
// `BookingsFilterSelection` for a picked date to be "discarded" FROM), so the
// old "a date picked in the FILTER SHEET is discarded" test is gone with it.
//
// ## Phase 7.16 — the calendar jump is retired too
//
// The rail's calendar button (and the `showBookingsDayPicker`/`_openCalendar`
// chain it drove) is gone outright — day selection is by scrolling the rail
// alone, with the month switcher and «Сьогодні» covering the long-distance
// jumps it used to exist for. The tests that used to drive that button
// (`a day picked in the calendar jump reaches the repository…`, `a rail
// debounce pending when the calendar opens is cancelled…`) and the
// `calendarActive` group are gone with it — there is no `calendarActive` /
// `onOpenCalendar` pair left on `BookingsDayRail` to test.

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
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_filter_sheet.dart';
import 'package:beautica_mobile/features/services/data/master_service_catalog_provider.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';

import '../../../helpers/booking_fixture_dates.dart';
import '../../../helpers/pump_app.dart';

class _MockBookingRepository extends Mock implements BookingRepository {}

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

/// Kyiv "today" — every landing query is scoped to this day (Phase 7.11).
DateTime get _kyivToday => kyivToday(DateTime.now);

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
  // Now-relative, never an absolute literal — see
  // `test/helpers/booking_fixture_dates.dart` for the time bomb this avoids.
  final DateTime start = futureBookingStart();
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
        cancelToken: any(named: 'cancelToken'),
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
    //
    // The landing STATUS assertion changed 2026-08-13 and is not a loosening:
    // it used to read `isEmpty` (send no `?status=` at all, let the server
    // return every status). The locked decision hides CANCELLED + DECLINED by
    // default, and `GET /bookings/me` has no "exclude" parameter, so the
    // default view names the other three ON THE WIRE. Asserted as the exact
    // wire strings, not as `BookingStatus.visibleInDayListByDefault` — a
    // typo'd or reordered constant must fail here rather than be compared
    // against itself.
    //
    // MUTATION: made `_rebuildQuery` build `BookingsDayQuery.of` (raw
    // `_statuses`, the master's own selection) instead of
    // `BookingsDayQuery.dayList` → this test failed on the status assertion.
    // Restored.
    testWidgets('opens on Kyiv "today", oldest-first, page 0 — and hides '
        'CANCELLED/DECLINED on the wire without the master filtering', (
      WidgetTester tester,
    ) async {
      await pump(tester);

      expect(calls, hasLength(1));
      expect(calls.single.page, 0);
      expect(
        calls.single.statuses.map((BookingStatus s) => s.wireValue).toSet(),
        <String>{'CONFIRMED', 'COMPLETED', 'NOT_COMPLETED'},
        reason:
            'the default day list shows live work only — NOT_COMPLETED stays '
            '(the master\'s own no-show record, feeding the two-sided client '
            'rating), CANCELLED/DECLINED are excluded server-side so they '
            'cannot eat the single un-paged size:100 budget',
      );
      expect(calls.single.serviceIds, isEmpty);
      expect(calls.single.from, _kyivToday);
      expect(calls.single.to, _kyivToday);
      expect(calls.single.sort, BookingSort.oldest);
      // Wire value as a LITERAL — a typo in the enum must fail here.
      expect(calls.single.sort!.wireValue, 'startsAt,asc');
    });

    // The subtle half of the 2026-08-13 decision: the default exclusion is a
    // WIRE concern only. It must not read back to the master as "you have a
    // filter on" — a funnel badge on a screen nobody filtered, plus the
    // «Немає записів за цим фільтром» copy on a genuinely free day, is how a
    // silently-narrowed list becomes a support ticket.
    //
    // The empty-state half of the same invariant (`_hasUserFilters`, not
    // `_liveQuery.hasFilters`) is pinned where empty pages are stubbed —
    // `master_bookings_screen_test.dart`'s "TRUE empty (no filters, an empty
    // day) offers no reset". This test owns the BADGE half; the `pump` stub
    // here returns two bookings, so an empty-state assertion would pass
    // vacuously.
    //
    // MUTATION: made `_activeFilterCount` read the resolved wire set
    // (`BookingStatus.dayListWireStatuses(_statuses)`) → this test failed (the
    // badge rendered "1"). Restored.
    testWidgets('the wire exclusion never reads back as an active filter — no '
        'badge on a screen the master never filtered', (
      WidgetTester tester,
    ) async {
      await pump(tester);

      // Fixture guard: the landing request really did carry three statuses,
      // so the absent badge below is the SEPARATION being asserted and not
      // just an unfiltered screen.
      expect(calls.single.statuses, hasLength(3));
      expect(
        find.byKey(const Key('master-bookings-filter-badge')),
        findsNothing,
        reason:
            'the badge counts the MASTER\'s decisions, not the wire — '
            'reading `BookingStatus.dayListWireStatuses` here would light '
            'the funnel up on a screen nobody filtered',
      );
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

    // The other half of the 2026-08-13 decision: hidden by default, but still
    // REACHABLE. Ticking «Скасовані» alone must send exactly the two hidden
    // statuses and nothing else — if the wire mapping folded the default set in
    // (union instead of replace) the master would get the whole day back
    // instead of the cancelled bookings they asked for.
    //
    // MUTATION: made `BookingStatus.dayListWireStatuses` return `selected ∪
    // visibleInDayListByDefault` → this test failed with all five statuses.
    // Restored.
    testWidgets('ticking «Скасовані» alone sends exactly CANCELLED + DECLINED '
        '— the default exclusion is REPLACED, not unioned', (
      WidgetTester tester,
    ) async {
      await pump(tester);
      calls.clear();

      await openFilters(tester);
      await tester.tap(
        find.byKey(const Key('master-bookings-filter-status-cancelled')),
      );
      await tester.pumpAndSettle();
      await applyFilters(tester);

      expect(
        calls.single.statuses.map((BookingStatus s) => s.wireValue).toSet(),
        <String>{'CANCELLED', 'DECLINED'},
      );
    });

    // mobile-security LOW (2026-08-13) — the MAXIMAL filter must be genuinely
    // UNFILTERED on the wire, not an inclusion list of the statuses this build
    // happens to know.
    //
    // 2026-08-15: the sheet's THREE groups no longer cover
    // `BookingStatus.filterable` — the `notCompleted` row was retired (nothing
    // in the app can SET that status; see `BookingStatusFilterGroup`'s
    // header) — so "select all" now means ticking `confirmed`/`completed`/
    // `cancelled` only. The invariant this test pins is unchanged: that must
    // STILL resolve to no `status` param at all, via
    // `BookingsDayQuery.dayList`'s `maximalStatuses` argument
    // (`bookings_discovery_view.dart:_rebuildQuery`), which now passes the
    // sheet's own (smaller) coverage instead of the domain's full
    // `filterable` default. Without that argument this test goes RED — see
    // `booking_status_test.dart`'s `maximal`-parameter group for the
    // mutation-verified proof at the domain tier.
    //
    // The backend ships before the client, so a status added server-side is
    // excluded by `status IN (...)` and is then unreachable through EVERY
    // filter combination — the silent drop `fromWire` exists to prevent,
    // re-introduced one layer lower. Sending NO `status` param is what makes
    // it reachable — and, as of 2026-08-15, is ALSO what keeps NOT_COMPLETED
    // (a status very much known to this build, just no longer independently
    // toggleable) from being silently excluded the moment the master ticks
    // every row still on offer.
    //
    // The badge assertion is the other half and is not decoration: the wire set
    // and the UI's notion of "a filter is on" are deliberately separate
    // (`_activeFilterCount` reads the master's RAW selection), so an empty wire
    // set must NOT silently retire the funnel the master needs to get back out.
    //
    // MUTATION: made `BookingStatus.dayListWireStatuses` return `selected`
    // verbatim for the all-of-`maximal` case → the wire assertion failed with
    // four statuses. Restored.
    //
    // MUTATION: reverted `_rebuildQuery`'s `maximalStatuses:` argument (back to
    // the domain's `filterable` default) → this test failed:
    //   Expected: empty
    //     Actual: Set:[BookingStatus.confirmed, BookingStatus.completed,
    //             BookingStatus.declined, BookingStatus.cancelled]
    // Restored.
    testWidgets(
      'ticking EVERY status group the sheet still offers sends NO status '
      'param at all — so NOT_COMPLETED (and any status this build has never '
      'heard of) stays reachable — while the funnel badge still reports an '
      'active filter',
      (WidgetTester tester) async {
        await pump(tester);
        calls.clear();

        await openFilters(tester);
        for (final String group in const <String>[
          'confirmed',
          'completed',
          'cancelled',
        ]) {
          await tester.tap(
            find.byKey(Key('master-bookings-filter-status-$group')),
          );
          await tester.pumpAndSettle();
        }
        await applyFilters(tester);

        expect(
          calls.single.statuses,
          isEmpty,
          reason:
              'the maximal filter must OMIT `status` entirely — an inclusion '
              'list here would make NOT_COMPLETED (and any future backend '
              'status) unreachable the moment the master ticks every row the '
              'sheet still shows',
        );
        expect(
          find.byKey(const Key('master-bookings-filter-badge')),
          findsOneWidget,
          reason:
              'the master DID make a choice — an empty WIRE set must not '
              'read back as "no filter" and hide the funnel they need to '
              'undo it',
        );
      },
    );

    // `sheetCoverage` below is computed by CALLING
    // `BookingStatusFilterGroup.values`, the exact same enum
    // `bookings_discovery_view.dart`'s `_rebuildQuery` reads — but that
    // derivation, on its own, does NOT make the `isEmpty` assertion below an
    // independent check: `dayListWireStatuses(X, maximal: X)` is `{}` for
    // ANY non-empty `X` (a set always `containsAll` itself), so that
    // assertion alone would stay GREEN even if `BookingStatusFilterGroup
    // .cancelled` silently lost `declined` from its own `statuses` — a real
    // regression (the «Скасовано» row would stop selecting DECLINED
    // bookings at all) that this test's own two assertions below cannot see
    // by construction, because BOTH sides of the `containsAll` compare
    // derive from the SAME (potentially broken) enum.
    //
    // mobile-qa (2026-08-15) — MUTATION: dropped `BookingStatus.declined`
    // from `BookingStatusFilterGroup.cancelled`'s `statuses`
    // (`bookings_filter_sheet.dart:99`) → this test's OWN two assertions
    // stayed GREEN (confirming the tautology above), while
    // `bookings_filter_sheet_test.dart`'s «Скасовано» selects BOTH… and
    // …server cap of 5… tests, and this file's own literal-wire-value
    // "ticking «Скасовані» alone…" test above, went RED. The LITERAL
    // equality assertion just below is the fix: it pins `sheetCoverage`'s
    // CONTENT against a hand-written expectation, independent of how the
    // enum derives it, so THIS test also fails on that exact mutation
    // instead of merely riding on coverage that happens to live in sibling
    // files. Restored.
    //
    // MUTATION: reverted the `maximal` parameter on
    // `BookingStatus.dayListWireStatuses` (hardcoded the containsAll check
    // back to `filterable`) → the `isEmpty` assertion failed:
    //   Expected: empty
    //     Actual: Set:[BookingStatus.confirmed, BookingStatus.completed,
    //             BookingStatus.declined, BookingStatus.cancelled]
    // — i.e. NOT_COMPLETED silently excluded from the wire the moment every
    // remaining row was ticked. Restored.
    test(
      'the sheet\'s own status coverage, resolved through '
      'dayListWireStatuses, still omits `status` entirely — NOT_COMPLETED '
      'is not in that coverage and must not become excludable because of it',
      () {
        final Set<BookingStatus> sheetCoverage = <BookingStatus>{
          for (final BookingStatusFilterGroup g
              in BookingStatusFilterGroup.values)
            ...g.statuses,
        };
        // LITERAL, independent of `sheetCoverage`'s own derivation — see the
        // comment above for why the `isEmpty` check further down cannot
        // stand in for this. A group silently losing (or gaining) a wire
        // status must fail HERE, not just in a sibling file.
        expect(
          sheetCoverage,
          <BookingStatus>{
            BookingStatus.confirmed,
            BookingStatus.completed,
            BookingStatus.cancelled,
            BookingStatus.declined,
          },
          reason:
              'the sheet\'s actual status coverage drifted from what this '
              'test — and `bookings_discovery_view.dart`\'s '
              '`_kMaximalFilterStatuses` — assume it is',
        );
        expect(
          sheetCoverage,
          isNot(contains(BookingStatus.notCompleted)),
          reason:
              'fixture guard — the whole regression only exists because the '
              'sheet can no longer select NOT_COMPLETED at all',
        );
        expect(
          BookingStatus.dayListWireStatuses(
            sheetCoverage,
            maximal: sheetCoverage,
          ),
          isEmpty,
        );
      },
    );

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
      // Scoped to the badge container itself — a bare `find.text('2')` also
      // matches any day-rail date number that happens to read "2" (a
      // date-dependent collision hit on 2026-07-21; see
      // `TimelineHourRuler`-scoping precedent for the same class of fix).
      expect(
        find.descendant(
          of: find.byKey(const Key('master-bookings-filter-badge')),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
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
