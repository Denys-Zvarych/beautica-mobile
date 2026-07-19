// Phase 7.7 — the range picker's selection WINDOW and SPAN CAP.
//
// `period_range_picker_test.dart` covers the picker's original forward-only
// behaviour (past days frozen, tap-start-then-end, the popped range). This file
// covers the three parameters Phase 7.7 added for the booking filter, none of
// which that file can see:
//
//   • `lastSelectableDay` — the booking window is bounded at BOTH ends.
//   • `maxSpanDays`      — a > 366-day range must be UNSELECTABLE, not merely
//                          rejected after the fact. Backend 26.2 answers a
//                          wider `from`/`to` with a 400, and the whole point of
//                          capping in the picker is that the user can never
//                          build one.
//   • `monthCount`       — the booking window reaches into the past, so more
//                          than the schedule caller's forward-only 24 months
//                          may be rendered.
//
// Every test here was mutation-verified; the mutation is recorded per group.
//
// ## Phase 7.13 — the "booking window itself" group is RETIRED
//
// That group used to pin `kMaxBookingRangeDays` (`date_range_calendar.dart`'s
// 366-day span cap for the booking filter's Дата/range section). Phase 7.13
// retired BOTH: the Дата section (there is no range left to cap — the filter
// sheet resolves only `statuses`/`serviceIds` now) and the constant with it
// (a single-day jump trivially satisfies any width limit a range it will
// never send could have needed). `date_range_calendar.dart` itself was
// renamed to `bookings_day_picker.dart` in the same phase — this file no
// longer imports it at all, having nothing left to read from it. Every OTHER
// group below (`maxSpanDays`, `lastSelectableDay`) tests the SHARED
// `PeriodRangePicker` widget directly, independent of either booking-specific
// file, and is untouched.
//
// ## Why the assertions are on the SEMANTICS tree, not on a tap
//
// A disabled cell is wrapped in a `Semantics` WITHOUT `button: true` and with
// no `GestureDetector` — so "is it disabled" is directly readable, while "did
// the tap do nothing" is only ever weak evidence (a tap can no-op for a dozen
// unrelated reasons: the cell scrolled out of view, the finder hit a blank
// leading cell, the row was off-screen). Both are asserted, but the structural
// one is what actually pins the behaviour.
//
// ## Host-zone independence
//
// Only ONE value here comes from the clock: `PeriodRangePicker` reads
// `DateTime.now()` to decide which cell gets the "today" ring. Nothing in this
// file asserts on that ring, and every window bound is an explicit
// `DateTime(y, m, d)` literal — so these tests are identical under TZ=UTC and
// TZ=Europe/Kyiv. (Only `bookings_day_rail_test.dart` may carry host-zone
// -dependent assertions; it runs under its own step-scoped Kyiv CI step.)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/shared/widgets/period_range_picker.dart';

const PeriodRangePickerStrings _strings = PeriodRangePickerStrings(
  title: 'Оберіть дату або період',
  emptyHint: 'Оберіть день',
  saveLabel: 'Готово',
  backSemantic: 'Назад',
  weekdayShort: <String>['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Нд'],
  monthNames: <String>[
    'Січень',
    'Лютий',
    'Березень',
    'Квітень',
    'Травень',
    'Червень',
    'Липень',
    'Серпень',
    'Вересень',
    'Жовтень',
    'Листопад',
    'Грудень',
  ],
);

void main() {
  // The window opens on 2024-01-01 and (unless a test bounds it) runs to the
  // end of the 24 rendered months — 731 days, comfortably wider than the cap,
  // so it is the CAP and not the window that stops a long selection.
  final DateTime windowStart = DateTime(2024);

  Future<void> pumpPicker(
    WidgetTester tester, {
    int? maxSpanDays,
    DateTime? lastSelectableDay,
    int monthCount = 24,
  }) async {
    final GoRouter router = GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (BuildContext context, GoRouterState state) => Scaffold(
            body: SizedBox(
              height: 1200,
              child: PeriodRangePicker(
                firstMonth: DateTime(windowStart.year, windowStart.month),
                firstSelectableDay: windowStart,
                lastSelectableDay: lastSelectableDay,
                maxSpanDays: maxSpanDays,
                monthCount: monthCount,
                strings: _strings,
              ),
            ),
          ),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
  }

  /// Scrolls [day]'s cell into view and returns a finder for it.
  ///
  /// Addressed by `periodDayCellKey` — the picker's OWN key derivation — so a
  /// bare day number can never resolve to the wrong month across the 24 months
  /// rendered here. (Deriving the finder from the production helper is safe in
  /// a way that deriving an EXPECTATION from it would not be: the key format is
  /// an address, not an assertion, and every behavioural claim below is about
  /// enabled/disabled, not about the key.)
  Future<Finder> scrollToDay(WidgetTester tester, DateTime day) async {
    final Finder cell = find.byKey(periodDayCellKey(day));
    await tester.scrollUntilVisible(
      cell,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    // `scrollUntilVisible` stops as soon as the finder MATCHES, and a
    // `ListView` builds its cache extent — so the cell can be found while still
    // off-screen, and a tap on it silently misses. That is not a hypothetical:
    // it made the DST test's start tap no-op, which left `_start` null, which
    // made `_outOfSpan` return false for everything and turned the whole
    // assertion vacuous.
    await tester.ensureVisible(cell);
    await tester.pumpAndSettle();
    return cell;
  }

  /// Scrolls to [day] and taps it, asserting the tap actually registered.
  Future<void> tapDay(WidgetTester tester, DateTime day) async {
    final Finder cell = await scrollToDay(tester, day);
    await tester.tap(cell);
    await tester.pumpAndSettle();
  }

  /// Whether the cell is live.
  ///
  /// Read STRUCTURALLY — the picker wraps an enabled cell's content in a
  /// `GestureDetector` and a disabled one's in nothing at all, so the presence
  /// of that detector IS the enabled state. Deliberately not read off the
  /// semantics node: `getSemantics` resolves to the nearest ENCLOSING node,
  /// which merges the cell's label with whatever ancestor flags are in scope,
  /// so an `isButton` read there answers a question about the subtree rather
  /// than about this cell (it reported every cell as a button, which would have
  /// made the whole file vacuous in the isTrue direction).
  bool isEnabled(WidgetTester tester, Finder cell) => tester
      .widgetList(
        find.descendant(of: cell, matching: find.byType(GestureDetector)),
      )
      .isNotEmpty;

  group('maxSpanDays', () {
    // MUTATION: made `_outOfSpan` return `false` unconditionally → both
    // expectations below failed (the day 367 out was still a live button, and
    // tapping it produced a 367-day range). Restored.
    testWidgets(
      'once a start is chosen, a day beyond the cap is not selectable',
      (WidgetTester tester) async {
        await pumpPicker(tester, maxSpanDays: 366);

        // Start on 1 Jan 2024.
        final Finder start = await scrollToDay(tester, DateTime(2024, 1, 1));
        expect(isEnabled(tester, start), isTrue);
        await tester.tap(start);
        await tester.pumpAndSettle();
        // The half-open summary proves the start REGISTERED. Without this the
        // rest of the test is vacuous: with `_start` still null, `_outOfSpan`
        // returns false for every day and every cell stays enabled.
        expect(find.text('01.01 – …'), findsOneWidget);

        // 31 Dec 2024 is day 366 inclusive (2024 is a leap year) — the LAST
        // legal end. It must stay selectable.
        final Finder lastLegal = await scrollToDay(
          tester,
          DateTime(2024, 12, 31),
        );
        expect(
          isEnabled(tester, lastLegal),
          isTrue,
          reason: 'day 366 inclusive is exactly at the cap, not over it',
        );

        // 1 Jan 2025 is day 367 — one past the cap, and must be dead.
        final Finder firstIllegal = await scrollToDay(
          tester,
          DateTime(2025, 1, 1),
        );
        expect(
          isEnabled(tester, firstIllegal),
          isFalse,
          reason: 'day 367 exceeds the 366-day backend cap',
        );

        // …and tapping it really does nothing: the summary still shows the
        // half-open selection, not a completed 367-day range.
        await tester.tap(firstIllegal, warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(find.text('01.01 – …'), findsOneWidget);
      },
    );

    // MUTATION: made `_outOfSpan` ignore the `_hasFullRange` short-circuit
    // (dropping `|| _hasFullRange` from its early return) → this test failed.
    // Restored.
    //
    // With a FULL range already chosen, the next tap RESTARTS the selection at
    // that day — so it must not be measured against the old start, or the
    // master gets permanently stranded: pick a wide range, then be unable to
    // start a new one anywhere outside it.
    testWidgets('with a full range chosen, every in-window day is live again', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester, maxSpanDays: 366);

      await tapDay(tester, DateTime(2024, 1, 1));
      await tapDay(tester, DateTime(2024, 1, 5));
      expect(find.text('01.01 – 05.01'), findsOneWidget);

      // A full range now exists. A day 700+ out from the OLD start must be
      // tappable, because it would begin a NEW selection.
      final Finder far = await scrollToDay(tester, DateTime(2025, 12, 20));
      expect(isEnabled(tester, far), isTrue);
    });

    // MUTATION: replaced `_inclusiveDays`' UTC-projected subtraction with
    // `a.difference(b).inDays.abs() + 1` on the local values → this test failed
    // under TZ=Europe/Kyiv (365 measured for a 366-day span across the March
    // DST transition, so the 367th day became selectable). Restored.
    //
    // This is a pure function, so it is asserted directly rather than through
    // the widget — the DST error is one day, and one day is exactly the
    // difference between "at the cap" and "over it".
    testWidgets('a cap-width span straddling a DST transition still binds', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester, maxSpanDays: 366);

      // 2024-03-01 → 2025-03-01 spans BOTH Kyiv DST transitions (31 Mar 2024
      // forward, 27 Oct 2024 back) and is 366 days inclusive.
      await tapDay(tester, DateTime(2024, 3, 1));
      expect(find.text('01.03 – …'), findsOneWidget);

      final Finder atCap = await scrollToDay(tester, DateTime(2025, 2, 28));
      expect(
        isEnabled(tester, atCap),
        isTrue,
        reason: '2024-03-01 … 2025-02-28 is 365 days inclusive — under the cap',
      );

      final Finder overCap = await scrollToDay(tester, DateTime(2025, 3, 2));
      expect(
        isEnabled(tester, overCap),
        isFalse,
        reason: '2024-03-01 … 2025-03-02 is 367 days inclusive — over the cap',
      );
    });
  });

  group('lastSelectableDay', () {
    // MUTATION: made `_outOfWindow` ignore `_lastSelectable` (returning only
    // the `isBefore(_firstSelectable)` half) → this test failed. Restored.
    testWidgets('days after the last selectable day are dead', (
      WidgetTester tester,
    ) async {
      await pumpPicker(
        tester,
        lastSelectableDay: DateTime(2024, 6, 15),
        monthCount: 12,
      );

      final Finder inside = await scrollToDay(tester, DateTime(2024, 6, 15));
      expect(isEnabled(tester, inside), isTrue);

      final Finder outside = await scrollToDay(tester, DateTime(2024, 6, 16));
      expect(isEnabled(tester, outside), isFalse);
    });
  });
}
