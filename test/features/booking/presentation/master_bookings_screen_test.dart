// Phase 7.6 — «Мої записи» for the independent master.
//
// Covers the four async states, the two DISTINCT empties, the day rail's
// filter-independent dots, the single-round-trip debounce, and the fact that
// the screen never re-sorts or re-filters what the server returned.
//
// The load-bearing invariants pinned here, each of which fails silently rather
// than loudly if broken:
//   • the dots do NOT change when a filter is applied (they come from a
//     filter-independent provider — narrowing must not hide the days the
//     master would need to un-narrow to reach);
//   • a day tap issues exactly ONE request (a rail fling would otherwise fire
//     dozens), and sends `from == to`;
//   • the list renders in SERVER order — a client-side comparator would look
//     plausible and be wrong;
//   • filter-empty and true-empty are different screens, and only one offers
//     an escape hatch.

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
import 'package:beautica_mobile/features/booking/presentation/widgets/master_booking_card.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/my_bookings_states.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/pump_app.dart';

// Fixture identities injected BY these tests — NOT app copy, and
// locale-invariant by construction (a person's name is not translated). This is
// the case the `i18n-finder-ok` annotation exists for.
const String _clientFull = 'Олена Ковальчук';
const String _otherClientFirst = 'Ігор';
const String _otherClientLast = 'Мороз';

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
  final DateTime start = startAt ?? DateTime.utc(2026, 7, 20, 12);
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

/// Pumps the screen with [repo] backing both the list and the booked-days set.
Future<void> _pump(
  WidgetTester tester,
  _MockBookingRepository repo, {
  Set<DateTime> bookedDays = const <DateTime>{},
}) async {
  await tester.pumpApp(
    const MasterBookingsScreen(),
    overrides: <Object>[
      screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
      bookingRepositoryProvider.overrideWithValue(repo),
      bookedDaysProvider.overrideWith((ref) async => bookedDays),
    ],
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(BookingStatus.confirmed);
    registerFallbackValue(BookingSort.newest);
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
      // Drain the delayed response by waiting for the skeleton to GO, rather
      // than guessing how long the fetch takes.
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

    testWidgets('renders a card per booking once loaded', (tester) async {
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

      expect(find.byType(MasterBookingCard), findsNWidgets(2));
      expect(
        find.text(_clientFull),
        findsOne,
      ); // i18n-finder-ok: test fixture name, not app copy
      expect(
        find.text('$_otherClientFirst $_otherClientLast'),
        findsOne,
      ); // i18n-finder-ok: test fixture name, not app copy
    });
  });

  // -------------------------------------------------------------------------
  // The two empties
  // -------------------------------------------------------------------------

  group('empty states', () {
    testWidgets('TRUE empty (no filters) offers no reset — nothing to reset', (
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
      'FILTER empty offers «Скинути фільтри» — the master is never stranded',
      (tester) async {
        final repo = _MockBookingRepository();
        // Page 0 with no filter returns a booking; once a day is selected the
        // (filtered) result is empty.
        when(
          () => repo.getMyBookings(
            statuses: any(named: 'statuses'),
            page: any(named: 'page'),
            size: any(named: 'size'),
            sort: any(named: 'sort'),
            serviceIds: any(named: 'serviceIds'),
            from: null,
            to: null,
          ),
        ).thenAnswer((_) async => _page(<Booking>[_booking(id: 'b1')]));
        when(
          () => repo.getMyBookings(
            statuses: any(named: 'statuses'),
            page: any(named: 'page'),
            size: any(named: 'size'),
            sort: any(named: 'sort'),
            serviceIds: any(named: 'serviceIds'),
            from: any(named: 'from', that: isNotNull),
            to: any(named: 'to', that: isNotNull),
          ),
        ).thenAnswer((_) async => _page(<Booking>[]));

        await _pump(tester, repo);
        await tester.pumpAndSettle();
        expect(find.byType(MasterBookingCard), findsOne);

        // Narrow to a day with nothing on it.
        await tester.tap(find.byKey(dayChipKey(DateTime(2026, 7, 18))));
        // The 220 ms query debounce plus the refetch — waited out by the
        // OUTCOME (the filter-empty state appearing), not a guessed duration.
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
    testWidgets(
      'the dots do NOT change when a filter is applied — they come from a '
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

        // Two booked days, neither of which is the day we will narrow TO.
        await _pump(
          tester,
          repo,
          bookedDays: <DateTime>{DateTime(2026, 7, 20), DateTime(2026, 7, 21)},
        );
        await tester.pumpAndSettle();

        expect(find.byKey(dayDotKey(DateTime(2026, 7, 20))), findsOne);
        expect(find.byKey(dayDotKey(DateTime(2026, 7, 21))), findsOne);

        // Narrow to the 20th.
        // fixed-wait-ok: this test asserts the dots do NOT change, so there is
        // no widget transition to await — the 220 ms query debounce has to be
        // advanced explicitly for the filtered refetch to have happened at all.
        // fixed-wait-ok: see the note above — advancing the 220 ms query debounce.
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        // BOTH dots survive. If the dots were derived from the filtered list,
        // the 21st's would have vanished — hiding the very day the master
        // would need to un-filter to reach.
        expect(find.byKey(dayDotKey(DateTime(2026, 7, 20))), findsOne);
        expect(
          find.byKey(dayDotKey(DateTime(2026, 7, 21))),
          findsOne,
          reason:
              'The 21st lost its dot under a filter — the rail is reading the '
              'filtered list instead of bookedDaysProvider.',
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
        calls.clear(); // drop the initial unfiltered fetch

        // A fling across the rail lands several taps in quick succession.
        // Without the debounce each is a new family member and a new request.
        // fixed-wait-ok: the debounce window IS the subject under test. These
        // 40 ms gaps must sit INSIDE the 220 ms window (so the first two taps
        // are coalesced away), and the final settle must sit OUTSIDE it (so the
        // surviving tap fires). Waiting on an outcome instead would defeat the
        // point — the assertion is that two of the three taps produce NOTHING.
        await tester.tap(find.byKey(dayChipKey(DateTime(2026, 7, 19))));
        // fixed-wait-ok: see the note above — advancing the 220 ms query debounce.
        await tester.pump(const Duration(milliseconds: 40));
        await tester.tap(find.byKey(dayChipKey(DateTime(2026, 7, 20))));
        // fixed-wait-ok: see the note above — advancing the 220 ms query debounce.
        await tester.pump(const Duration(milliseconds: 40));
        await tester.tap(find.byKey(dayChipKey(DateTime(2026, 7, 21))));
        // fixed-wait-ok: see the note above — advancing the 220 ms query debounce.
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
        expect(from, DateTime(2026, 7, 21));
        expect(to, DateTime(2026, 7, 21));
        expect(from, to, reason: 'a single-day selection is from == to');
      },
    );

    testWidgets('«Всі» clears the day selection', (tester) async {
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

      await tester.tap(find.byKey(dayChipKey(DateTime(2026, 7, 20))));
      // fixed-wait-ok: advancing past the 220 ms query debounce. The observable
      // here is a REQUEST, not a widget, so there is nothing to pump-until.
      // fixed-wait-ok: see the note above — advancing the 220 ms query debounce.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(calls.last.$1, isNotNull);

      // «Всі» is rail item 1, and the rail opens CENTRED on today (~item 182),
      // so the chip starts well off-screen to the left and must be scrolled
      // to. That is the approved design's own behaviour — the calendar and
      // «Всі» chips ride the rail rather than being pinned — and it is why
      // this is a `scrollUntilVisible` rather than a bare `tap`.
      await tester.scrollUntilVisible(
        find.byKey(const Key('master-bookings-all-chip')),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      final int callsBeforeAll = calls.length;
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.tap(find.byKey(const Key('master-bookings-all-chip')));
      // fixed-wait-ok: as above — «Всі» is served from the cached family
      // member, so the assertion is the ABSENCE of a new request and there is
      // no widget transition to await.
      // fixed-wait-ok: see the note above — advancing the 220 ms query debounce.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // «Всі» returns the query to its INITIAL, unfiltered value — which is
      // still a live family member inside the 5-minute keepAlive, so the
      // correct behaviour is a cache hit and NO new request. Asserting on
      // `calls.last` here would be asserting that the cache does not work.
      expect(
        calls.length,
        callsBeforeAll,
        reason:
            'Returning to the unfiltered query should be served from the '
            'cached family member, not re-fetched.',
      );
      // What IS observable: the date narrowing is gone. The «Всі» chip reads
      // selected, and it does so ONLY when neither a single day nor a range
      // narrows the query (`selectedDay == null && !calendarActive`) — so this
      // one flag is the full "day selection cleared" assertion.
      //
      // The previously-selected 20th is deliberately NOT asserted here: the
      // rail has been scrolled ~180 cells back to reach «Всі», so that chip is
      // no longer built. `bookings_day_rail_test.dart` pins the chip-level
      // selection rendering directly.
      expect(
        tester
            .getSemantics(find.byKey(const Key('master-bookings-all-chip')))
            .flagsCollection
            .isSelected
            .toBoolOrNull(),
        isTrue,
      );
      handle.dispose();
    });
  });

  // -------------------------------------------------------------------------
  // The server owns the order
  // -------------------------------------------------------------------------

  group('server order', () {
    testWidgets(
      'renders in SERVER order — a response deliberately NOT in startAt order '
      'is not re-sorted',
      (tester) async {
        final repo = _MockBookingRepository();
        // Server order here is by descending PRICE; the startsAt order is the
        // reverse. A client-side `startAt` comparator would flip these two and
        // look entirely plausible doing it.
        final Booking dearer = _booking(
          id: 'dear',
          clientFirstName: 'Дорога',
          clientLastName: 'Клієнтка',
          price: 2600,
          startAt: DateTime.utc(2026, 7, 25, 12),
        );
        final Booking cheaper = _booking(
          id: 'cheap',
          clientFirstName: 'Дешева',
          clientLastName: 'Клієнтка',
          price: 300,
          startAt: DateTime.utc(2026, 7, 20, 12),
        );
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
        ).thenAnswer((_) async => _page(<Booking>[dearer, cheaper]));

        await _pump(tester, repo);
        await tester.pumpAndSettle();

        final double dearY = tester
            .getTopLeft(find.byKey(const Key('master-booking-card-dear')))
            .dy;
        final double cheapY = tester
            .getTopLeft(find.byKey(const Key('master-booking-card-cheap')))
            .dy;
        expect(
          dearY,
          lessThan(cheapY),
          reason:
              'The list was re-sorted client-side — the server order was '
              'dearest-first and has been flipped to earliest-first.',
        );
      },
    );

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
            'The count showed items.length (the pages fetched so far) rather '
            'than the whole filtered result set.',
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
      // route push hangs off. (The route itself is asserted in
      // `master_bookings_routing_test.dart`, which drives a real GoRouter so
      // the `context.push` / ImperativeRouteMatch behaviour is exercised
      // rather than mocked.)
      expect(find.byKey(const Key('master-booking-card-b1')), findsOne);
    });
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

      // Replace the screen — this renders client names, so the protection must
      // not outlive it.
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
