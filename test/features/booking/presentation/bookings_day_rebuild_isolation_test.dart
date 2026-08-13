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
  // mobile-qa (2026-07-22) — THE MONTH-SWITCHER HALF OF THE SAME INVARIANT.
  // ===========================================================================
  //
  // The two tests above pin the PROVIDER→WIDGET direction (an emission must
  // not rebuild siblings). This group pins the opposite direction, added by
  // the mobile-perf HIGH fix that moved `_focusedMonth` from a `State` field
  // to a `ValueNotifier`: a WIDGET interaction that changes nothing but a
  // LABEL must not rebuild the timeline.
  //
  // Why it matters, in the fix's own words: `_prevMonth`/`_nextMonth`
  // deliberately move only the switcher's label and the rail's scroll
  // position — never `_day`, never `_liveQuery`. Before the fix they still
  // called `setState`, so every month step rebuilt `_Loaded` →
  // `BookingsTimelineGrid` → `assignLanes` + up to 100 `MasterBookingCard`s
  // (~212ms measured) on the exact frame `_centreRailOn` starts its 320ms
  // `animateTo` — stuttering the rail on its first frame.
  //
  // NOTHING OBSERVES THIS TODAY. A `setState` reinstated in `_prevMonth`
  // (the most natural "fix" for any future month-switcher bug) restores the
  // full 212ms rebuild with no test anywhere going red — the label still
  // updates, the rail still scrolls, the timeline still renders. Only widget
  // IDENTITY can tell the two apart.
  //
  // VACUOUS-ASSERTION TRAP (same as the LOW-4 block above): the witness must
  // be non-const at its real call site. `BookingsTimelineGrid(bookings:,
  // day:, onBookingTap:)` is constructed from runtime values inside
  // `_Loaded.build`, so `identical()` genuinely reflects a rebuild.

  group('month switcher does not rebuild the timeline', () {
    /// The month switcher's label `Text` — reached through the
    /// `ValueListenableBuilder<DateTime>` the perf fix introduced, so this
    /// never hard-codes a Cyrillic month name (the i18n-finder gate) and
    /// never depends on `monthNominative`'s exact formatting.
    String monthLabel(WidgetTester tester) => tester
        .widget<Text>(
          find
              .descendant(
                of: find.byType(ValueListenableBuilder<DateTime>),
                matching: find.byType(Text),
              )
              .first,
        )
        .data!;

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

    testWidgets(
      'stepping the month forward relabels the switcher WITHOUT rebuilding '
      'BookingsTimelineGrid — the ValueNotifier confines the rebuild to one '
      'Text',
      (tester) async {
        await pumpScreen(tester);

        final BookingsTimelineGrid before = grid(tester);
        final String labelBefore = monthLabel(tester);

        await tester.tap(find.byKey(const Key('master-bookings-month-next')));
        await tester.pumpAndSettle();

        // Fixture guard FIRST — if the tap did nothing, the identity
        // assertion below would pass for the wrong reason.
        expect(
          monthLabel(tester),
          isNot(labelBefore),
          reason:
              'the month step did not relabel the switcher at all, so the '
              'no-rebuild assertion proves nothing',
        );
        expect(
          identical(grid(tester), before),
          isTrue,
          reason:
              'BookingsTimelineGrid was reconstructed by a month step. A '
              'month step changes only the LABEL and the rail\'s scroll '
              'position — it must not setState the discovery view, or the '
              'whole timeline (assignLanes + up to 100 cards) rebuilds on '
              'the same frame the rail starts its 320ms animation.',
        );
      },
    );

    testWidgets('stepping BACK behaves the same way', (tester) async {
      await pumpScreen(tester);

      final BookingsTimelineGrid before = grid(tester);
      final String labelBefore = monthLabel(tester);

      await tester.tap(find.byKey(const Key('master-bookings-month-prev')));
      await tester.pumpAndSettle();

      expect(monthLabel(tester), isNot(labelBefore));
      expect(identical(grid(tester), before), isTrue);
    });

    // ── The contrast cases: interactions that MUST still rebuild ──────────
    //
    // Without these, the two tests above would be satisfied by a screen that
    // never rebuilds the timeline for anything — including a genuine day
    // change, which would be a far worse bug (a stale day's bookings under a
    // newly selected date).

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
      '«Сьогодні» DOES rebuild the timeline — it re-selects the day, unlike '
      'prev/next',
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
              'today (setState + a new query), not merely relabel like '
              'prev/next',
        );
      },
    );
  });
}
