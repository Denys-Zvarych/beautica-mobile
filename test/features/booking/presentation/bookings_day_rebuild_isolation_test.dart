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
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_filter_sheet.dart';
import 'package:beautica_mobile/shared/formatters/api_date.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';

import '../../../helpers/pump_app.dart';

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
    final DateTime kyivToday = dateOnly(toBeauticaTime(DateTime.now()));
    container.invalidate(
      bookingsDayProvider(BookingsDayQuery.of(day: kyivToday)),
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
}
