// Phase 7.6 — the three perf fixes on `MasterBookingsScreen` that had NO
// regression test at all (mobile-qa, G1 of the Phase 7.2/7.6 audit).
//
// WHY THIS FILE EXISTS
// --------------------
// `master_bookings_screen_test.dart` covers the four async states, the two
// empties, the rail, server order, navigation and screen protection. It does
// not touch the scroll path, so all three of these were one line from
// regressing with the whole suite green:
//
//   1. THE PREFETCH LATCH (`_onListScroll`, `master_bookings_screen.dart:277`).
//      `loadMore()` is idempotent, so deleting the latch is INVISIBLE to any
//      behavioural assertion — the list still pages correctly. What it costs is
//      a `Future` allocation plus a provider-container lookup per scroll frame,
//      i.e. 120/s at 120Hz for as long as the master rests near the end. The
//      only way to pin it is to count CALLS across a drag, which is what the
//      first two tests do.
//
//   2. THE `_setQuery` RE-ARM (`:215-220`). This one is NOT merely a cost
//      regression — it is a correctness bug, and the nastiest kind. Drop
//      `_nearEnd = false` from `_setQuery` and a latch left `true` by the
//      landing list SUPPRESSES the first legitimate `loadMore` on the newly
//      filtered (shorter) list. The master narrows to a day, scrolls to the
//      bottom, and page 2 never loads — silently, with no error anywhere.
//
//   3. CONSUMER REBUILD SCOPING (perf P1, `:343` + `:387`). Neither provider is
//      watched at screen scope. Hoisting `ref.watch(masterBookingsProvider(…))`
//      back into `build()` changes NOTHING observable — same pixels, same
//      behaviour — while rebuilding `_Header` and re-running the rail's
//      `itemBuilder` for its whole visible window TWICE per page during a
//      paginating fling. Pinned here by WIDGET IDENTITY: if the screen's
//      `build()` re-ran, the rail and the header carry fresh widget instances.
//
// The list is deliberately sized so `maxScrollExtent` comfortably exceeds the
// 400px prefetch threshold — otherwise the list opens ALREADY inside the zone
// and "retreated out and re-entered" is unreachable, which would make the
// re-arm tests vacuous.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/booking/application/booked_days_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/application/master_bookings_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/master_bookings_query.dart';
import 'package:beautica_mobile/features/booking/presentation/master_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_day_rail.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

import '../../../helpers/pump_app.dart';

class _MockBookingRepository extends Mock implements BookingRepository {}

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

/// Counts `loadMore()` INVOCATIONS, not repository calls.
///
/// This distinction is the whole test. `loadMore()` no-ops when a fetch is
/// already in flight (`isLoadingMore`), and it sets that flag SYNCHRONOUSLY
/// before its first await — so deleting the latch entirely still produces
/// exactly ONE `getMyBookings` call per page. A repo-call count therefore
/// cannot see the latch at all: the first version of this test passed with the
/// latch deleted. What the latch actually saves is the per-frame invocation
/// (a `Future` allocation + a provider-container lookup on the scroll hot
/// path), and that is only observable here.
class _CountingNotifier extends MasterBookingsNotifier {
  int loadMoreInvocations = 0;

  @override
  Future<void> loadMore() {
    loadMoreInvocations++;
    return super.loadMore();
  }
}

/// One recorded `getMyBookings` call — enough to tell a page-0 (query change)
/// call from a page-N (load-more) one, and to tell which query it belonged to.
typedef _Call = ({int page, DateTime? from, DateTime? to});

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
    serviceId: 's1',
    serviceName: 'Манікюр з покриттям',
    durationMinutes: 90,
    price: 650,
    startAt: start,
    endAt: start.add(const Duration(minutes: 90)),
    status: BookingStatus.confirmed,
    canReview: false,
  );
}

List<Booking> _bookings(String prefix, int count) => <Booking>[
  for (int i = 0; i < count; i++) _booking('$prefix-$i'),
];

/// A page that always reports MORE — every `loadMore` is answerable, so a
/// missing call can never be excused by an exhausted stream.
PageResponse<Booking> _endlessPage(List<Booking> items, int page) =>
    PageResponse<Booking>(
      items: items,
      page: page,
      totalPages: 50,
      totalElements: 500,
    );

void main() {
  setUpAll(() {
    registerFallbackValue(BookingStatus.confirmed);
    registerFallbackValue(BookingSort.newest);
    registerFallbackValue(<BookingStatus>[]);
  });

  late _MockBookingRepository repo;
  late List<_Call> calls;

  /// When set, every page > 0 response is held PENDING forever.
  ///
  /// This is load-bearing, not a convenience. If the load-more resolves during
  /// the drag, the appended page pushes `maxScrollExtent` out by ~1900px, the
  /// remaining drag steps land OUTSIDE the prefetch zone, and
  /// `_onListScroll`'s retreat branch clears `_nearEnd` all by itself. That
  /// silently defeats both regressions under test:
  ///
  ///   • the per-frame-invocation count collapses back to ~1 even with the
  ///     latch deleted, and
  ///   • the latch is already false by the time the query changes, so a
  ///     missing `_setQuery` re-arm has nothing to leave stale.
  ///
  /// An earlier version of this file did resolve the page, and BOTH mutations
  /// (latch deleted, re-arm deleted) passed. Holding the page keeps the list
  /// height — and therefore the latch — where the test put it.
  late bool holdLoadMore;

  setUp(() {
    repo = _MockBookingRepository();
    calls = <_Call>[];
    holdLoadMore = false;
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
    ).thenAnswer((Invocation i) {
      final int page = i.namedArguments[#page] as int;
      final DateTime? from = i.namedArguments[#from] as DateTime?;
      calls.add((
        page: page,
        from: from,
        to: i.namedArguments[#to] as DateTime?,
      ));
      if (holdLoadMore && page > 0) {
        return Completer<PageResponse<Booking>>().future;
      }
      // A DATE-NARROWED query returns a SHORT page — short enough that the
      // filtered list opens ALREADY inside the prefetch zone. That is the shape
      // that makes the `_setQuery` re-arm load-bearing: with a tall filtered
      // list, `_onListScroll`'s retreat branch resets `_nearEnd` on the way
      // down and masks a missing re-arm entirely.
      return Future<PageResponse<Booking>>.value(
        _endlessPage(_bookings('p\$page', from == null ? 12 : 4), page),
      );
    });
  });

  late _CountingNotifier landingNotifier;

  Future<void> pump(WidgetTester tester) async {
    landingNotifier = _CountingNotifier();
    await tester.pumpApp(
      const MasterBookingsScreen(),
      overrides: <Object>[
        screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
        bookingRepositoryProvider.overrideWithValue(repo),
        bookedDaysProvider.overrideWith((ref) async => <DateTime>{}),
        // Only the LANDING (undated) family member is instrumented — the
        // screen's own `MasterBookingsQuery.of()` initial value. Date-narrowed
        // members keep the real notifier.
        masterBookingsProvider(
          MasterBookingsQuery.of(),
        ).overrideWith(() => landingNotifier),
      ],
    );
    await tester.pumpAndSettle();
  }

  final Finder list = find.byKey(const Key('master-bookings-list'));

  ScrollPosition positionOf(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(of: list, matching: find.byType(Scrollable)),
      )
      .position;

  /// Scrolls the list to `maxScrollExtent - [fromEnd]` px in ONE gesture made
  /// of many pointer moves, so the scroll listener runs many times.
  Future<void> dragTo(WidgetTester tester, {required double fromEnd}) async {
    final ScrollPosition p = positionOf(tester);
    final double target = (p.maxScrollExtent - fromEnd).clamp(
      0.0,
      p.maxScrollExtent,
    );
    final double delta = target - p.pixels;
    if (delta == 0) return;

    // A manual pointer gesture rather than `tester.drag`: `drag` synthesises a
    // handful of moves, and the latch test needs MANY frames spent inside the
    // zone to be meaningful.
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(list),
    );
    const int steps = 24;
    for (int i = 0; i < steps; i++) {
      await gesture.moveBy(Offset(0, -delta / steps));
      await tester.pump();
    }
    await gesture.up();
    // NOT `pumpAndSettle`: when [holdLoadMore] is set the footer's
    // `MyBookingsLoadMoreSpinner` animates forever, so settling never
    // terminates. A bounded pump is enough — every resolved fetch in this file
    // completes on a microtask.
    // fixed-wait-ok: advancing frames past a deliberately-never-resolving
    // load-more; there is no completion event to await by construction.
    for (int i = 0; i < 12; i++) {
      // fixed-wait-ok: the load-more never resolves (see [holdLoadMore]).
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  int loadMoreCalls() => calls.where((_Call c) => c.page > 0).length;

  // -------------------------------------------------------------------------
  // 1. The latch itself
  // -------------------------------------------------------------------------

  group('prefetch latch (_onListScroll)', () {
    testWidgets('the list opens OUTSIDE the prefetch zone — guard for the '
        'tests below, which are vacuous otherwise', (tester) async {
      await pump(tester);

      final ScrollPosition p = positionOf(tester);
      expect(
        p.maxScrollExtent,
        greaterThan(400),
        reason:
            'the fixture must produce a list taller than the 400px prefetch '
            'threshold, or "retreated out of the zone" is unreachable and '
            'every re-arm assertion below passes for the wrong reason',
      );
      expect(loadMoreCalls(), 0, reason: 'nothing has scrolled yet');
    });

    testWidgets('crossing into the prefetch zone INVOKES loadMore exactly '
        'ONCE, not once per scroll frame', (tester) async {
      holdLoadMore = true; // see [holdLoadMore] — without it this cannot fail
      await pump(tester);

      // Get INSIDE the zone first; the crossing itself is the previous test's
      // subject. What this test measures is what happens while the master then
      // RESTS there, which is the case the latch exists for.
      await dragTo(tester, fromEnd: 200);

      // DWELL: small back-and-forth moves that never leave the prefetch zone.
      // With the latch, `_onListScroll` returns early every time and loadMore
      // is invoked ZERO more times. Without it, every one of these frames
      // allocates a Future and does a provider-container lookup.
      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(list),
      );
      // Break the touch slop FIRST. Without this the ±6px jiggle below never
      // reaches the scroll position at all and the loop produces zero
      // notifications — the dwell would silently measure nothing.
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump();

      // Count how many times the scroll position actually notified — this is
      // the SAME notification stream `_onListScroll` is subscribed to, so it is
      // the honest denominator for "invocations per scroll frame".
      int notifications = 0;
      positionOf(tester).addListener(() => notifications++);
      landingNotifier.loadMoreInvocations = 0;

      for (int i = 0; i < 24; i++) {
        await gesture.moveBy(Offset(0, i.isEven ? -6 : 6));
        await tester.pump();
      }
      await gesture.up();
      // fixed-wait-ok: the load-more is deliberately never resolved (see
      // [holdLoadMore]), so there is no completion event to await.
      for (int i = 0; i < 4; i++) {
        // fixed-wait-ok: the load-more never resolves (see [holdLoadMore]).
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(
        notifications,
        greaterThan(15),
        reason:
            'fixture guard: the dwell must produce many scroll notifications, '
            'or "once per frame" and "once per crossing" are '
            'indistinguishable and this test proves nothing',
      );
      expect(
        positionOf(tester).pixels,
        greaterThan(positionOf(tester).maxScrollExtent - 400),
        reason:
            'fixture guard: the dwell must stay INSIDE the prefetch zone — if '
            'it wandered out, the retreat branch legitimately re-arms and the '
            'assertion below measures nothing',
      );
      expect(
        landingNotifier.loadMoreInvocations,
        // Not literally 0: appending the load-more spinner grows
        // `maxScrollExtent`, which can briefly push the position back out of
        // the zone and legitimately re-arm the latch once. The discriminator is
        // the ORDER OF MAGNITUDE — measured, this is 1 with the latch and 24
        // (one per notification) without it.
        lessThanOrEqualTo(2),
        reason:
            'loadMore() was invoked ${landingNotifier.loadMoreInvocations} '
            'times across $notifications scroll notifications spent RESTING '
            'inside the prefetch zone — the _nearEnd latch is not holding, so '
            'the prefetch fires per frame (120/s at 120Hz). Note the '
            'REPOSITORY call count stays at 1 either way — loadMore no-ops '
            'while a fetch is in flight — which is exactly why this assertion '
            'counts invocations instead.',
      );
    });

    testWidgets('retreating out of the zone RE-ARMS the latch — the next '
        'page can still be prefetched', (tester) async {
      await pump(tester);
      landingNotifier.loadMoreInvocations = 0;
      calls.clear();

      await dragTo(tester, fromEnd: 100);
      expect(loadMoreCalls(), 1, reason: 'guard: the first crossing fetched');

      // Scroll back up, well clear of the threshold, then return.
      await dragTo(tester, fromEnd: 1200);
      await dragTo(tester, fromEnd: 100);

      expect(
        loadMoreCalls(),
        2,
        reason:
            'the latch never re-armed on retreat — it degraded into a one-shot '
            'and the list would stop paging after page 1',
      );
      expect(
        landingNotifier.loadMoreInvocations,
        2,
        reason:
            'two crossings must produce exactly two invocations — more means '
            'the latch is not holding WITHIN a crossing',
      );
    });
  });

  // -------------------------------------------------------------------------
  // 2. The _setQuery re-arm — the correctness one
  // -------------------------------------------------------------------------

  group('_setQuery re-arms the prefetch latch', () {
    testWidgets('a latch left true by the landing list does NOT suppress the '
        'first loadMore on a newly filtered list', (tester) async {
      holdLoadMore = true; // see [holdLoadMore] — without it this cannot fail
      await pump(tester);

      // Latch it: scroll into the zone on the UNFILTERED list and stay there.
      await dragTo(tester, fromEnd: 100);
      expect(
        calls.where((_Call c) => c.page > 0 && c.from == null),
        hasLength(1),
        reason: 'guard: the unfiltered list must have latched _nearEnd = true',
      );

      // Narrow to a rail day WITHOUT scrolling back out of the zone first.
      final DateTime day = DateTime(2026, 7, 21);
      await tester.tap(find.byKey(dayChipKey(day)));
      // fixed-wait-ok: advancing the screen's 220 ms day-tap debounce — the
      // filtered fetch does not start until it elapses.
      // fixed-wait-ok: advancing past the 220 ms day-tap debounce.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      calls.clear();

      // The filtered list is SHORT — it opens already inside the prefetch zone
      // (`maxScrollExtent < 400`). This is what makes the missing re-arm
      // reachable: `_onListScroll`'s retreat branch never runs on this list, so
      // nothing else can clear a stale `_nearEnd`. On a TALL filtered list the
      // retreat branch resets the latch on the way down and the bug is masked —
      // an earlier version of this test used a tall list and passed with the
      // re-arm deleted.
      final ScrollPosition filtered = positionOf(tester);
      expect(
        filtered.maxScrollExtent,
        lessThan(400),
        reason:
            'fixture guard: the filtered list must open INSIDE the prefetch '
            'zone, otherwise the retreat branch masks the regression under '
            'test and this assertion passes for the wrong reason',
      );
      expect(
        filtered.maxScrollExtent,
        greaterThan(0),
        reason:
            'fixture guard: it must still be scrollable, or no scroll '
            'notification is produced at all',
      );

      // Scroll the NEW list to its end.
      await dragTo(tester, fromEnd: 0);

      final List<_Call> filteredLoadMores = calls
          .where((_Call c) => c.page > 0)
          .toList();
      expect(
        filteredLoadMores,
        hasLength(1),
        reason:
            'the filtered list never asked for page 1 — `_setQuery` did not '
            'reset `_nearEnd`, so the stale latch from the previous (longer) '
            'list is silently swallowing the first prefetch. The master '
            'reaches the bottom of the day and page 2 never arrives.',
      );
      expect(
        filteredLoadMores.single.from,
        day,
        reason: 'the load-more must belong to the NARROWED query',
      );
      expect(filteredLoadMores.single.to, day);
    });
  });

  // -------------------------------------------------------------------------
  // 3. Consumer rebuild scoping (perf P1)
  // -------------------------------------------------------------------------

  group('Consumer rebuild scoping (perf P1)', () {
    testWidgets('a masterBookingsProvider emission rebuilds NEITHER the '
        'header NOR the day rail', (tester) async {
      await pump(tester);

      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(MasterBookingsScreen)),
      );
      // i18n-finder-ok: the header carries no Key of its own (it is a private
      // widget); its title is the only stable handle on the Text instance whose
      // identity is the subject here. The ASSERTION is identity, not copy.
      final Finder headerText = find.text(l10n.masterBookingsTitle);

      final BookingsDayRail railBefore = tester.widget<BookingsDayRail>(
        find.byType(BookingsDayRail),
      );
      final Text headerBefore = tester.widget<Text>(headerText);

      // Force list emissions WITHOUT touching the query — a query change goes
      // through `setState` and would legally rebuild everything, which would
      // make this assertion meaningless. A load-more toggles `isLoadingMore`
      // false→true→false: TWO emissions, the exact pair a paginating fling
      // produces, and it never calls `setState`.
      await dragTo(tester, fromEnd: 100);
      expect(
        loadMoreCalls(),
        greaterThan(0),
        reason: 'guard: a list emission must actually have occurred',
      );

      final BookingsDayRail railAfter = tester.widget<BookingsDayRail>(
        find.byType(BookingsDayRail),
      );
      final Text headerAfter = tester.widget<Text>(headerText);

      expect(
        identical(railBefore, railAfter),
        isTrue,
        reason:
            'the day rail was reconstructed by a LIST emission — '
            '`masterBookingsProvider` is being watched at screen scope again '
            '(perf P1), so every page toggle re-runs the rail itemBuilder for '
            'its whole visible window',
      );
      expect(
        identical(headerBefore, headerAfter),
        isTrue,
        reason:
            'the header was reconstructed by a LIST emission — same root cause '
            'as the rail above',
      );
    });
  });
}
