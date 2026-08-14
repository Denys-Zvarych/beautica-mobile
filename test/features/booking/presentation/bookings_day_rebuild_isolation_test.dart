// Phase 7.9 — bookingsDayProvider: Consumer-scoping regression guard.
//
// This is a PORT of the single surviving case from the retired
// `master_bookings_prefetch_latch_test.dart` ('a masterBookingsProvider
// emission rebuilds NEITHER the header NOR the day rail', ~:470). The other
// four cases in that file tested the paging prefetch latch, which died with
// paging itself (Phase 7.9 retired both `masterBookingsProvider` and its
// `loadMore`) — they were deleted with the file.
//
// WHY THIS IS A SYNTHETIC HARNESS, NOT THE REAL SCREEN
// ------------------------------------------------------
// Phase 7.9 is explicitly "No UI — 7.10 builds the widgets, 7.11 renders
// them" (see the phase doc header). There is therefore no production
// `presentation/` widget yet that watches `bookingsDayProvider` for a test to
// drive — `master_bookings_screen.dart` still watches the RETIRED provider
// and does not even compile until Phase 7.11 rewrites it. Porting the
// original case VERBATIM (pumping `MasterBookingsScreen`) is impossible in
// this phase.
//
// What is ported is the PATTERN, applied to the new provider: a minimal
// two-widget tree shaped exactly like the real screen will be (a header that
// does not watch the day provider, and a nested `Consumer` that does),
// demonstrating the Riverpod discipline the real screen MUST follow — watch
// `bookingsDayProvider` only in the narrowest `Consumer`, never at the
// widget's own top-level `build()` — or every emission needlessly rebuilds
// sibling widgets (this is exactly perf P1 from the retired screen's own
// header, restated for the new provider).
//
// LOW-4 (7.9/7.10/7.11 consolidated audit) added the screen-level version
// this section used to call for — see the bottom of this file. It pumps the
// real `MasterBookingsScreen` and proves the same invariant against
// `BookingsFilterButton`/`BookingsDayRail` identity. The synthetic harness
// above is kept: it isolates the Riverpod-scoping PATTERN from every other
// thing that could rebuild the real screen, so a failure here still points
// straight at Consumer scoping rather than requiring the reader to rule out
// everything else the real screen also does.
//
// Forcing a SECOND emission for one query needs a trigger — this phase's
// notifier has no `refresh()`/`loadMore()` (single fetch, see
// `bookings_day_notifier.dart`), so [_ReemittingNotifier] stands in for
// whatever future event (a pull-to-refresh, an invalidate-triggered reload)
// causes a real emission later. The trigger mechanism is deliberately
// irrelevant here; only the rebuild-scoping CONSEQUENCE of an emission is
// under test.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/booking/application/booked_days_notifier.dart';
import 'package:beautica_mobile/features/booking/application/bookings_day_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/bookings_day_query.dart';
import 'package:beautica_mobile/features/booking/domain/bookings_day_state.dart';
import 'package:beautica_mobile/features/booking/presentation/master_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_day_rail.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_timeline_grid.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_filter_sheet.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';

import '../../../helpers/clock_instant.dart';
import '../../../helpers/pump_app.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

class _MockBookingRepository extends Mock implements BookingRepository {}

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

/// A notifier that can be told to re-emit its CURRENT value a second time.
/// See the file header for why this stand-in exists.
class _ReemittingNotifier extends BookingsDayNotifier {
  void reemit() {
    final BookingsDayState? current = state.value;
    if (current == null) return;
    // Riverpod skips notifying listeners when the newly-assigned state is
    // `==` to the previous one (the "seamless" optimisation), so an
    // untouched `copyWith()` would silently no-op here. Toggling a field the
    // rendered `_Body` text does not read (`isTruncated`) forces a REAL,
    // observable emission without changing what the body conceptually shows
    // — exactly the property this test needs: a provider emission that
    // carries no header-relevant information whatsoever must still not
    // rebuild the header.
    state = AsyncData<BookingsDayState>(
      current.copyWith(isTruncated: !current.isTruncated),
    );
  }
}

/// Stand-in for the real screen's header: reads NOTHING from
/// `bookingsDayProvider`. Its widget IDENTITY across an emission is the
/// assertion.
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    // Deliberately NOT `const Text(...)` — a const Text literal is
    // compile-time canonicalised, so `identical()` on it would stay true no
    // matter how many times `build()` actually ran, making the assertion
    // below vacuous. Interpolating a stable value keeps the RENDERED content
    // identical across runs while still allocating a fresh widget instance
    // every `build()` call, so identity genuinely reflects whether this
    // widget was rebuilt.
    // ignore: prefer_const_constructors — const would canonicalise this Text and defeat the identity assertion below (see the comment above).
    return Text('Мої записи${''}', key: const Key('rebuild-isolation-header'));
  }
}

/// Stand-in for the real screen's list body — the ONLY widget that watches
/// `bookingsDayProvider`, scoped via a nested `Consumer` exactly as the real
/// screen must (perf P1).
class _Body extends StatelessWidget {
  const _Body({required this.query});

  final BookingsDayQuery query;

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (BuildContext context, WidgetRef ref, Widget? _) {
        final AsyncValue<BookingsDayState> async = ref.watch(
          bookingsDayProvider(query),
        );
        return Text(
          'items: ${async.value?.items.length ?? 0}',
          key: const Key('rebuild-isolation-body'),
        );
      },
    );
  }
}

/// The synthetic screen: [_Header] then [_Body] in a `Column`.
/// `ref.watch(bookingsDayProvider(...))` lives ONLY inside [_Body]'s nested
/// `Consumer`, never in this widget's own `build()` — the shape the real
/// Phase 7.10/7.11 screen must replicate.
class _Screen extends StatelessWidget {
  const _Screen({required this.query});

  final BookingsDayQuery query;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        const _Header(),
        _Body(query: query),
      ],
    );
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(<BookingStatus>{});
  });

  testWidgets(
    'a bookingsDayProvider emission rebuilds the body but NOT the header — '
    'Consumer scoping, not a screen-level ref.watch',
    (tester) async {
      final _MockBookingRepository repo = _MockBookingRepository();
      final BookingsDayQuery query = BookingsDayQuery.of(
        day: DateTime(2026, 7, 20),
      );
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

      final _ReemittingNotifier notifier = _ReemittingNotifier();

      await tester.pumpWidget(
        ProviderScope(
          retry: beauticaProviderRetry,
          overrides: [
            bookingRepositoryProvider.overrideWithValue(repo),
            bookingsDayProvider(query).overrideWith(() => notifier),
          ],
          child: MaterialApp(home: _Screen(query: query)),
        ),
      );
      await tester.pumpAndSettle();

      final Text headerBefore = tester.widget<Text>(
        find.byKey(const Key('rebuild-isolation-header')),
      );
      final Text bodyBefore = tester.widget<Text>(
        find.byKey(const Key('rebuild-isolation-body')),
      );

      notifier.reemit();
      await tester.pump();

      final Text headerAfter = tester.widget<Text>(
        find.byKey(const Key('rebuild-isolation-header')),
      );
      final Text bodyAfter = tester.widget<Text>(
        find.byKey(const Key('rebuild-isolation-body')),
      );

      expect(
        identical(headerBefore, headerAfter),
        isTrue,
        reason:
            'the header was reconstructed by a bookingsDayProvider emission — '
            'the provider must only be watched inside the Consumer scoped to '
            'the body, never at the screen\'s own build()',
      );
      expect(
        identical(bodyBefore, bodyAfter),
        isFalse,
        reason:
            'fixture guard: the body itself must actually have rebuilt, or '
            'the emission never happened and the header assertion above '
            'passes for the wrong reason',
      );
    },
  );

  // ===========================================================================
  // LOW-4 (7.9/7.10/7.11 consolidated audit) — the SCREEN-LEVEL version this
  // file's own header called for.
  // ===========================================================================
  //
  // The test above proves the PATTERN on a synthetic two-widget harness. It
  // never pumps `BookingsDiscoveryView`/`MasterBookingsScreen`, so a future
  // refactor that hoists `ref.watch(bookingsDayProvider(...))` out of the
  // narrow `Consumer` in `bookings_discovery_view.dart` and into
  // `_BookingsDiscoveryViewState.build()` would regress rebuild scope on the
  // REAL screen with nothing here to catch it. This test pumps the real
  // `MasterBookingsScreen` instead.
  //
  // VACUOUS-ASSERTION TRAP: a `const` widget is canonicalised at compile
  // time, so an `identical()` check across rebuilds passes even when the
  // widget genuinely rebuilt (a test in this very chain was already found
  // vacuous for exactly this reason — see the DST-bug postmortem). Both
  // witnesses below are constructed NON-const at their real call sites in
  // `bookings_discovery_view.dart` (`BookingsFilterButton(activeCount:
  // ..., onTap: ...)` inside `_Header`; `BookingsDayRail(controller: ...,
  // ...)` inside its own `Consumer`) — every field is a runtime value, so
  // `identical()` genuinely reflects whether the enclosing ancestor rebuilt.
  testWidgets('the PRODUCTION widget tree: a bookingsDayProvider emission on '
      'MasterBookingsScreen rebuilds neither the header filter button nor the '
      'day rail', (tester) async {
    final _MockBookingRepository repo = _MockBookingRepository();
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

    await tester.pumpApp(
      const MasterBookingsScreen(),
      overrides: <Object>[
        screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
        bookingRepositoryProvider.overrideWithValue(repo),
        bookedDaysProvider.overrideWith((ref) async => <DateTime>{}),
      ],
    );
    await tester.pumpAndSettle();

    final BookingsFilterButton headerWitnessBefore = tester
        .widget<BookingsFilterButton>(find.byType(BookingsFilterButton));
    final BookingsDayRail railWitnessBefore = tester.widget<BookingsDayRail>(
      find.byType(BookingsDayRail),
    );

    // Force a genuine SECOND `bookingsDayProvider` emission with no
    // `setState()` anywhere in `_BookingsDiscoveryViewState` — mirrors
    // what a future pull-to-refresh or cache-eviction would trigger.
    // Reached via the SAME `ProviderScope` `pumpApp` built (not a bespoke
    // `ProviderContainer`), so this exercises the real production tree.
    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(BookingsDayRail)),
      listen: false,
    );
    final DateTime today = kyivToday(DateTime.now);
    // The statuses are NOT decoration — `bookingsDayProvider` is a family and
    // this must name the member the screen is actually watching. Since
    // 2026-08-13 the landing query carries
    // `BookingStatus.visibleInDayListByDefault` (CANCELLED/DECLINED hidden by
    // default), so an empty-status query here invalidates a member nobody
    // listens to: no second fetch fires and the `.called(2)` fixture guard
    // below catches it rather than letting the identity assertions pass
    // vacuously — which is precisely the job that guard exists for.
    container.invalidate(
      bookingsDayProvider(
        BookingsDayQuery.of(
          day: today,
          statuses: BookingStatus.visibleInDayListByDefault,
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    // Fixture guard — proves the emission genuinely happened (a second
    // fetch fired), so the identity assertions below cannot pass vacuously
    // because nothing was actually invalidated.
    verify(
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
    ).called(2);

    final BookingsFilterButton headerWitnessAfter = tester
        .widget<BookingsFilterButton>(find.byType(BookingsFilterButton));
    final BookingsDayRail railWitnessAfter = tester.widget<BookingsDayRail>(
      find.byType(BookingsDayRail),
    );

    expect(
      identical(headerWitnessBefore, headerWitnessAfter),
      isTrue,
      reason:
          'the header rebuilt on a bookingsDayProvider emission on the '
          'REAL screen — a ref.watch(bookingsDayProvider(...)) call must '
          'have leaked out of the narrow Consumer in '
          'bookings_discovery_view.dart into '
          '_BookingsDiscoveryViewState.build()',
    );
    expect(
      identical(railWitnessBefore, railWitnessAfter),
      isTrue,
      reason:
          'the day rail rebuilt on a bookingsDayProvider emission on the '
          'REAL screen — same regression as the header case above.',
    );
  });

  // ===========================================================================
  // Варіант D port — THE MONTH-SWITCHER INVARIANT REVERSED (locked decision).
  // ===========================================================================
  //
  // The two tests above pin the PROVIDER→WIDGET direction (an emission must
  // not rebuild siblings). This group used to pin the opposite direction,
  // added by a mobile-perf HIGH fix that moved a retired `_focusedMonth`
  // field to a `ValueNotifier` so that stepping the month rebuilt only its
  // label. That fix existed because `_prevMonth`/`_nextMonth` deliberately
  // moved ONLY the switcher's label and the rail's scroll position — never
  // `_day`, never `_liveQuery` — which was itself the production BUG the
  // Варіант D port (`bookings_month_calendar_panel.dart`) fixes: a month step
  // that relabels without reselecting left the rail/label showing one month
  // while the list below kept showing a day from another. The port's locked
  // contract is "month stepping selects" (same day-of-month, clamped) — so a
  // genuine query change, and therefore a timeline rebuild, is now the
  // CORRECT behaviour on every month step, not a regression to guard against.
  //
  // The isolation invariant this file is otherwise about — a DRAG frame or
  // the panel's 280ms open/close settle animation must not rebuild the
  // timeline — is preserved a different way now: the `AnimationController`
  // driving the expand/collapse fraction lives entirely inside
  // `BookingsMonthCalendarPanel`'s own `State`, so it never calls `setState`
  // on `MasterBookingsScreen`/`BookingsDiscoveryView` at all. There is
  // nothing to pin here at the widget-tree level for that half any more —
  // the isolation now falls out of ordinary widget-subtree boundaries rather
  // than a hand-rolled `ValueNotifier`.
  //
  // VACUOUS-ASSERTION TRAP (same as the LOW-4 block above): the witness must
  // be non-const at its real call site. `BookingsTimelineGrid(bookings:,
  // day:, onBookingTap:)` is constructed from runtime values inside
  // `_Loaded.build`, so `identical()` genuinely reflects a rebuild.

  group('month step (Варіант D calendar) rebuilds the timeline', () {
    /// The visible month+year label `Text`.
    ///
    /// ⚠ REPOINTED (this session). This used to read the FIRST `Text` inside
    /// `bookings-month-calendar-grid`, because `_TopRow` dropped its own
    /// label from the tree once the calendar opened (`if (t < 0.45)`) and
    /// `MonthCalendar`'s `_MonthHeader` carried the month name from then on.
    /// Both halves of that are gone: the top-row label is now PERMANENT and
    /// `MonthCalendar` is composed with `showHeader: false`, so the month
    /// name exists exactly once on screen, in one place, in every state. The
    /// grid's first `Text` today is `CalendarWeekdayBar`'s "пн", which never
    /// changes and would have quietly defanged every fixture guard below.
    ///
    /// Reached by key (never a hard-coded Cyrillic month name — the
    /// i18n-finder gate) so it never depends on `monthNominative`'s exact
    /// formatting.
    String monthLabel(WidgetTester tester) => tester
        .widget<Text>(find.byKey(const Key('bookings-month-calendar-label')))
        .data!;

    /// Expands the calendar (the month pager is unreachable while collapsed —
    /// `IgnorePointer(ignoring: t < 0.5)`) and waits out the 280ms open
    /// animation.
    Future<void> expandCalendar(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('bookings-month-calendar-toggle')));
      await tester.pumpAndSettle();
    }

    /// Turns the month pager one page.
    ///
    /// ⚠ REPLACES a `tap(Key('booking-calendar-next-month'))`. The grid's
    /// ‹ › chevrons are retired outright (locked requirement: "don't add any
    /// new buttons" — and the two that existed went with them), so a
    /// horizontal page turn is the ONLY month-navigation mechanism left. The
    /// CONTRACT under test is unchanged and deliberately so: a month step
    /// still SELECTS (same day-of-month, clamped), it is just reached by a
    /// different gesture.
    ///
    /// `fling`, not `drag`: `PageScrollPhysics` resolves a page turn from
    /// velocity, and a slow drag of less than half a viewport settles BACK to
    /// the page it started on — which would make every assertion below fail
    /// for a reason that has nothing to do with the code under test.
    Future<void> pageMonth(
      WidgetTester tester, {
      required int direction,
    }) async {
      await tester.fling(
        find.byKey(const Key('bookings-month-calendar-grid')),
        Offset(-300.0 * direction, 0),
        800,
      );
      await tester.pumpAndSettle();
    }

    Future<_MockBookingRepository> pumpScreen(WidgetTester tester) async {
      final _MockBookingRepository repo = _MockBookingRepository();
      final DateTime today = kyivToday(DateTime.now);
      // `today` is a DATE TOKEN, not an instant (see
      // `lib/shared/time/kyiv_day.dart`'s header): `.toUtc()` on it is on the
      // ILLEGAL list precisely because it reinterprets host-local midnight as
      // though it were already an instant. The old
      // `today.toUtc().add(12h)` happened to land inside the right Kyiv day
      // from Kyiv/UTC/Tokyo, but under a WESTERN host zone (e.g. UTC-10) it
      // rolls a day forward — midnight local is 10:00Z, +12h = 22:00Z, which
      // is already the NEXT Kyiv day. `asClockInstant` reads only the token's
      // calendar fields and returns noon UTC on that day, which is 14:00-15:00
      // Kyiv from any host.
      final DateTime start = asClockInstant(today);
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
        (_) async => PageResponse<Booking>(
          items: <Booking>[
            Booking(
              id: 'b1',
              masterId: 'm1',
              masterFirstName: 'Марія',
              masterLastName: 'Іванюк',
              masterType: 'INDEPENDENT_MASTER',
              clientId: 'c1',
              clientFirstName: 'Олена',
              clientLastName: 'Ковальчук',
              serviceId: 's1',
              serviceName: 'Манікюр',
              durationMinutes: 60,
              price: 650,
              startAt: start,
              endAt: start.add(const Duration(minutes: 60)),
              status: BookingStatus.confirmed,
              canReview: false,
            ),
          ],
          page: 0,
          totalPages: 1,
          totalElements: 1,
        ),
      );

      await tester.pumpApp(
        const MasterBookingsScreen(),
        // `height: 700` — RE-BENCHMARKED (mobile-qa, 2026-08-13; see
        // `bookings_month_calendar_short_device_test.dart` for the full
        // probe). This group is the only one in the file that EXPANDS
        // `BookingsMonthCalendarPanel` to its 380dp grid.
        //
        // FORMER RATIONALE (was 2400, now stale — kept for the record):
        // this used to exist because the timeline sat in a `Column`
        // `Expanded` sibling of the panel, so expanding the panel on the
        // default 800×600 test surface (an unrealistically short landscape
        // window vs. any real portrait phone this app targets) squeezed
        // that `Expanded` down to a few px and tripped the Phase 17.2
        // overflow guard. The mobile-perf HIGH fix in
        // `bookings_discovery_view.dart` (finding #2 — the panel's
        // live-changing height forcing the timeline to relayout on every
        // drag/settle frame) removed that coupling entirely: the timeline
        // is now a `Positioned` in a `Stack`, given a FIXED slot sized to
        // the panel's COLLAPSED height
        // (`kBookingsMonthCalendarPanelCollapsedHeight`), and the expanding
        // panel draws OVER it rather than shrinking it — so expansion no
        // longer touches the timeline's layout at all, on any surface size.
        // `height: 2400` was kept anyway at the time, undocumented as pure
        // margin rather than a re-derived requirement.
        //
        // THE RE-BENCHMARK: the expanded panel's rendered bottom edge sits
        // at a FIXED ~496dp from the screen top regardless of viewport (a
        // `Positioned(top, left, right)` with no `bottom`/`height` shrink-
        // wraps to its child) — so it can never overflow-ERROR at any
        // height, only silently CLIP once the viewport falls below
        // ~580–600dp (`Stack`'s default `Clip.hardEdge`). 700dp clears that
        // boundary with 126dp to spare — comfortably inside the realistic
        // phone range (iPhone SE's 667dp logical height is the shortest
        // this app targets) rather than an arbitrary 2400dp multiple of it.
        height: 700,
        overrides: <Object>[
          screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
          bookingRepositoryProvider.overrideWithValue(repo),
          bookedDaysProvider.overrideWith((ref) async => <DateTime>{}),
        ],
      );
      await tester.pumpAndSettle();
      return repo;
    }

    BookingsTimelineGrid grid(WidgetTester tester) =>
        tester.widget<BookingsTimelineGrid>(find.byType(BookingsTimelineGrid));

    /// The `isFalse` widget-IDENTITY check below is satisfied by ANY host
    /// `setState`, not only a genuine query change: `_Loaded` (and the
    /// `BookingsTimelineGrid` it constructs) is rebuilt by every
    /// `_BookingsDiscoveryViewState.build()` pass, because `Consumer`
    /// re-invokes its `builder` whenever its own element rebuilds — which
    /// happens on ANY ancestor `setState`, whether or not the WATCHED
    /// `bookingsDayProvider` family member actually changed.
    ///
    /// MUTATION-TESTED (mobile-qa gap-3, 2026-08-13): temporarily making
    /// `_stepMonth` move `_day` (so the label visibly changes, satisfying the
    /// fixture guard) WITHOUT calling `_rebuildQuery()` — i.e. reintroducing
    /// exactly the "relabel without reselect" bug this port exists to fix —
    /// left EVERY assertion in both tests below GREEN, including the
    /// `isFalse` one. Widget identity alone cannot tell "a real day change
    /// that correctly re-fetched" apart from "some unrelated rebuild left the
    /// OLD day's data on screen under a NEW label".
    ///
    /// The fetch COUNT is what actually discriminates the two: a genuine day
    /// change always rebuilds `_liveQuery` into a NEW `bookingsDayProvider`
    /// family member, and Riverpod always issues a fresh fetch for a family
    /// member it has not resolved before. The mutated version left
    /// `_liveQuery` (and therefore the family member, and therefore this
    /// count) unchanged — so asserting the count catches what the identity
    /// check alone could not. Restored to the real implementation after the
    /// probe; see `bookings_discovery_view.dart`'s `_stepMonth` (unchanged by
    /// this audit) and the mobile-qa report for the full before/after run.
    /// `calls` is the count of NEW fetches since the last [expectFetchCount]
    /// on this [repo] — mocktail's `verify(...).called(n)` only counts calls
    /// not already claimed by an earlier `verify` on the same mock (each
    /// match is marked `verified` and excluded from the next check), so this
    /// is an INCREMENTAL count, not a running total. Each test below calls
    /// this once for the landing fetch (`1`) and once more for the ONE new
    /// fetch a genuine month step must cause (`1` again, not `2`).
    void expectFetchCount(_MockBookingRepository repo, int calls) {
      verify(
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
      ).called(calls);
    }

    testWidgets('PAGING the month forward relabels the calendar AND rebuilds '
        'BookingsTimelineGrid — the port\'s locked "month step selects" '
        'contract, now reached by swipe instead of a chevron', (tester) async {
      final _MockBookingRepository repo = await pumpScreen(tester);
      await expandCalendar(tester);
      // The landing fetch — exactly one call before any interaction.
      expectFetchCount(repo, 1);

      final BookingsTimelineGrid before = grid(tester);
      final String labelBefore = monthLabel(tester);

      await pageMonth(tester, direction: 1);
      // A resolved month step funnels through `_selectImmediate`, which
      // does not itself debounce, but the surrounding `pumpAndSettle`
      // below covers both the query round trip and any animation.
      // fixed-wait-ok: advancing past the 220 ms day-select debounce
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Fixture guard FIRST — if the tap did nothing, the rebuild
      // assertion below would pass for the wrong reason.
      expect(
        monthLabel(tester),
        isNot(labelBefore),
        reason:
            'the month step did not relabel the calendar at all, so the '
            'rebuild assertion proves nothing',
      );
      expect(
        identical(grid(tester), before),
        isFalse,
        reason:
            'BookingsTimelineGrid was NOT reconstructed by a month step. '
            'Under the Варіант D port, stepping the month SELECTS (same '
            'day-of-month, clamped) — this is the fix for the original '
            'bug where the switcher relabelled while the list stayed on '
            'a stale day, so a genuine query change (and therefore a '
            'rebuild) is required here, not forbidden.',
      );
      // The DISCRIMINATING assertion — see expectFetchCount's doc. Exactly
      // ONE NEW real fetch must have fired since the landing-fetch check
      // above (mocktail's `verify(...).called(n)` only counts calls not
      // already claimed by an earlier `verify` on the same mock — see that
      // doc); the identity check alone cannot tell this apart from a
      // cosmetic rebuild that left the query unchanged.
      expectFetchCount(repo, 1);
    });

    testWidgets('paging BACK behaves the same way', (tester) async {
      final _MockBookingRepository repo = await pumpScreen(tester);
      await expandCalendar(tester);
      expectFetchCount(repo, 1);

      final BookingsTimelineGrid before = grid(tester);
      final String labelBefore = monthLabel(tester);

      await pageMonth(tester, direction: -1);
      // fixed-wait-ok: see the forward-step test above.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(monthLabel(tester), isNot(labelBefore));
      expect(identical(grid(tester), before), isFalse);
      expectFetchCount(repo, 1);
    });

    // ── Further contrast cases: interactions that MUST still rebuild ──────
    //
    // Without these, the two tests above would prove nothing distinctive —
    // a screen that rebuilds the timeline on EVERY frame would also satisfy
    // them. These pin that a plain rail-day selection and «Сьогодні» still
    // rebuild too, exactly as before this port.

    testWidgets(
      'selecting a DIFFERENT rail day DOES rebuild the timeline — the '
      'no-rebuild rule is scoped to the month step, not blanket',
      (tester) async {
        await pumpScreen(tester);

        final BookingsTimelineGrid before = grid(tester);
        final DateTime today = kyivToday(DateTime.now);

        await tester.tap(find.byKey(dayChipKey(railDayAt(today, 1))));
        // fixed-wait-ok: advancing past the 220 ms day-select debounce.
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        expect(
          identical(grid(tester), before),
          isFalse,
          reason:
              'the timeline did NOT rebuild after the selected day changed — '
              'the screen is now showing one day\'s bookings under another '
              'day\'s heading',
        );
      },
    );

    testWidgets(
      '«Сьогодні» DOES rebuild the timeline — it re-selects the day',
      (tester) async {
        await pumpScreen(tester);
        final DateTime today = kyivToday(DateTime.now);

        // Move off today first, so «Сьогодні» has a real selection change to
        // make rather than resolving to the day already shown.
        await tester.tap(find.byKey(dayChipKey(railDayAt(today, 2))));
        // fixed-wait-ok: advancing past the 220 ms day-select debounce.
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        final BookingsTimelineGrid before = grid(tester);

        await tester.tap(find.byKey(const Key('master-bookings-today')));
        await tester.pumpAndSettle();

        expect(
          identical(grid(tester), before),
          isFalse,
          reason:
              '«Сьогодні» left the timeline untouched — it must re-select '
              'today (setState + a new query)',
        );
      },
    );
  });
}
