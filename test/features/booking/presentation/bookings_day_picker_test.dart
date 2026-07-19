// Phase 7.13 — `showBookingsDayPicker`, the day rail's single-day jump.
//
// Pins the regression this jump exists to prevent: the picker used to open
// scrolled to the ±180-day window's ORIGIN (`today − 180 days`), forcing the
// master to scroll roughly six months of day cells before reaching a day they
// could actually pick. `showBookingsDayPicker` now opens scrolled to the
// CURRENTLY SELECTED day instead — which, once the master has navigated away
// from today, is neither "today" nor "the window origin" (see the first
// group below, which deliberately separates all three).
//
// Also pins that a tap resolves the picker DIRECTLY with a date-only value —
// no `DateTimeRange`, no confirm CTA, one tap — and that dismissing changes
// nothing. Integration coverage for "selecting a day moves the rail and
// issues exactly one request" lives in `master_bookings_filter_wiring_test
// .dart`, which drives the real `BookingsDiscoveryView` end to end; this file
// is scoped to what `showBookingsDayPicker` can prove on its own.
//
// Every test here was mutation-verified — see the note per group.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_day_picker.dart';
import 'package:beautica_mobile/shared/widgets/period_range_picker.dart';

import '../../../helpers/pump_app.dart';

void main() {
  /// Whether [cell] is actually WITHIN the month list's viewport — not merely
  /// present in the tree. A `ListView` builds a cache extent beyond the
  /// viewport, so a cell can be found while sitting off-screen, which is
  /// precisely the shape of the bug this file pins (today's cell existed in
  /// the tree, six months of scroll away).
  bool isInViewport(WidgetTester tester, Finder cell) {
    final Finder list = find.byType(Scrollable).last;
    final Rect viewport = tester.getRect(list);
    final Rect r = tester.getRect(cell);
    return r.top >= viewport.top && r.bottom <= viewport.bottom;
  }

  /// Pumps a routed host with a button that opens the picker, capturing the
  /// resolved value into [onPicked]. `context.pop` inside the shared picker
  /// needs a real GoRouter above it.
  Future<void> pumpPicker(
    WidgetTester tester, {
    required DateTime today,
    required DateTime initialDay,
    required void Function(DateTime?) onPicked,
  }) async {
    await tester.pumpRoutedApp(
      GoRouter(
        initialLocation: '/',
        routes: <RouteBase>[
          GoRoute(
            path: '/',
            builder: (BuildContext context, GoRouterState state) => Scaffold(
              body: Builder(
                builder: (BuildContext inner) => TextButton(
                  key: const Key('open'),
                  onPressed: () async {
                    final DateTime? picked = await showBookingsDayPicker(
                      inner,
                      today: today,
                      initialDay: initialDay,
                    );
                    onPicked(picked);
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
  }

  // Kyiv "today" the screen would have captured, and a selection the master
  // has already navigated to — chosen as the MIDPOINT of the ±180-day
  // window's past half (today − 90 days), which is ~90 days from BOTH `today`
  // AND the window origin (`today − 180 days`). A viewport this size shows
  // roughly 1.5–2 months at once, so being 3 months from either boundary
  // reliably keeps both boundaries' cells off screen (and out of the
  // `ListView.builder`'s cache extent) — unlike a value merely "5.5 months
  // from today", which (with an 180-day/~6-month window) lands close enough
  // to the window origin that a regression to THAT origin can slip past the
  // viewport check below undetected. Independently reproduced during the
  // Phase 7.13 QA pass: with the previous `selectedDay` (2026-02-01, only 11
  // days from the window origin 2026-01-21), mutating `showBookingsDayPicker`
  // to scroll to the window origin instead of the selection left this test
  // GREEN — the exact "fixture never sits on the boundary it claims to test"
  // failure mode. All three anchors are mutually distinguishable now.
  final DateTime today = DateTime(2026, 7, 20);
  final DateTime selectedDay = DateTime(2026, 4, 21);
  // The ±180-day window's origin — `railDayAt(today, -kBookedDaysSpanDays)`
  // in production. Computed here as a literal (not by importing the rail's
  // helper) to keep this file's fixture self-contained and independent of
  // the production arithmetic it is meant to catch a regression to.
  final DateTime windowOrigin = DateTime(2026, 1, 21);

  group('opens on the CURRENTLY SELECTED day', () {
    // MUTATION: changed `initialScrollMonth`/`initialRange` in
    // `showBookingsDayPicker` to derive from `today` instead of `initialDay`
    // → this test failed (selectedDay's cell was off-screen, today's was
    // on-screen). Restored.
    testWidgets(
      "selectedDay's cell is on screen at open — not today's, and not the "
      'window origin (today − 180 days)',
      (WidgetTester tester) async {
        DateTime? picked;
        await pumpPicker(
          tester,
          today: today,
          initialDay: selectedDay,
          onPicked: (DateTime? d) => picked = d,
        );

        final Finder selectedCell = find.byKey(periodDayCellKey(selectedDay));
        expect(
          selectedCell,
          findsOneWidget,
          reason: 'selectedDay is inside the ±180-day window by construction',
        );
        expect(
          isInViewport(tester, selectedCell),
          isTrue,
          reason:
              'the jump must open ON the current selection — opening at the '
              'window origin or at today forces the same six-month scroll '
              'this jump exists to prevent',
        );

        // today and selectedDay are ~90 days apart — a `ListView.builder`
        // only materialises cells near the viewport (plus its cache extent),
        // so today's cell is not even IN THE TREE unless the picker actually
        // scrolled there instead of to selectedDay.
        expect(
          find.byKey(periodDayCellKey(today)),
          findsNothing,
          reason:
              "if today's cell exists at all here, the picker scrolled to "
              'today instead of to the actual selection',
        );

        // …and the SAME check against the window's own origin — the actual
        // regression this jump exists to prevent ("opened six months in the
        // past"). `selectedDay` is deliberately ~90 days from `windowOrigin`
        // too (see the fixture comment above), so a regression to the
        // origin is caught HERE, not just a regression to `today`.
        expect(
          find.byKey(periodDayCellKey(windowOrigin)),
          findsNothing,
          reason:
              "if the window origin's cell exists at all here, the picker "
              'scrolled to the ±180-day window start instead of to the '
              'actual selection — the exact six-month-scroll bug this jump '
              'exists to prevent',
        );

        // No day was tapped — nothing resolved yet.
        expect(picked, isNull);
      },
    );
  });

  group('a tap resolves a date-only day, immediately', () {
    // NOT mutation-verifiable via this widget flow, reported per the mutation
    // rule rather than shipped as if it were proof: removing the
    // `dateOnly(picked.start)` belt-and-braces wrap in `showBookingsDayPicker`
    // does NOT fail this test. Every day cell `PeriodRangePicker` renders is
    // constructed as `DateTime(month.year, month.month, day)` — already
    // date-only — so `picked.start` is date-only before the wrap ever runs,
    // and the wrap is unreachable dead-code insurance from THIS caller alone.
    // The assertions below still pin the CONTRACT (a date-only value is what
    // callers get), which is what actually matters to `bookings_discovery
    // _view.dart` and `BookingsDayQuery.of`.
    testWidgets('the resolved day carries no time-of-day component', (
      WidgetTester tester,
    ) async {
      DateTime? picked;
      await pumpPicker(
        tester,
        today: today,
        initialDay: selectedDay,
        onPicked: (DateTime? d) => picked = d,
      );

      // selectedDay's own cell is already on screen (pinned above) — tap it
      // directly rather than scrolling to a different day.
      await tester.tap(find.byKey(periodDayCellKey(selectedDay)));
      await tester.pumpAndSettle();

      expect(picked, selectedDay);
      expect(picked!.hour, 0);
      expect(picked!.minute, 0);
      expect(picked!.second, 0);
    });

    // MUTATION: dropped `mode: PeriodRangePickerMode.single` from
    // `showBookingsDayPicker`'s call to `showPeriodRangePicker` (falling back
    // to the default `range` mode) → this test failed: the tap only set a
    // half-open `_start` and the picker stayed open with `btn-range-picker
    // -save` rendered (inert), rather than resolving on the one tap. Restored.
    testWidgets('one tap both selects and resolves — no confirm CTA exists', (
      WidgetTester tester,
    ) async {
      DateTime? picked;
      bool resolved = false;
      await pumpPicker(
        tester,
        today: today,
        initialDay: selectedDay,
        onPicked: (DateTime? d) {
          picked = d;
          resolved = true;
        },
      );

      // Single mode never renders the range CTA — there is nothing left for
      // it to confirm.
      expect(find.byKey(const Key('btn-range-picker-save')), findsNothing);

      final DateTime target = DateTime(2026, 4, 23);
      await tester.tap(find.byKey(periodDayCellKey(target)));
      await tester.pumpAndSettle();

      expect(resolved, isTrue, reason: 'the single tap must resolve alone');
      expect(picked, target);
    });
  });

  group('dismissing changes nothing', () {
    // MUTATION: made the picker's back button pop `DateTime.now()` instead of
    // nothing → this test failed. Restored.
    testWidgets('tapping back resolves null', (WidgetTester tester) async {
      DateTime? picked;
      bool resolved = false;
      await pumpPicker(
        tester,
        today: today,
        initialDay: selectedDay,
        onPicked: (DateTime? d) {
          picked = d;
          resolved = true;
        },
      );

      await tester.tap(find.byKey(const Key('btn-range-picker-back')));
      await tester.pumpAndSettle();

      expect(resolved, isTrue, reason: 'dismissing still resolves the Future');
      expect(picked, isNull);
    });
  });
}
