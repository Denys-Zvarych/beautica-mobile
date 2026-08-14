// Phase 14.14 — Widget tests for MonthCalendar's generic day-availability
// gating.
//
// [MonthCalendar] itself stays generic (its `isAvailable` callback can
// express any policy) — see the widget's file header. These tests exercise
// that contract directly, independent of the real working-days data source
// wired up in `SlotDateScreen` (covered separately in `slot_picker_test.dart`
// and `working_days_notifier_test.dart`):
//   1. A day the caller marks available renders tappable and invokes
//      `onSelectDay` with the exact date.
//   2. A day the caller marks unavailable renders WITHOUT a tap handler
//      (no `GestureDetector`) and never invokes `onSelectDay`.

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/month_calendar.dart';
import 'package:beautica_mobile/shared/formatters/uk_calendar.dart';
import 'package:beautica_mobile/shared/widgets/calendar_grid.dart'
    show
        CalendarWeekRow,
        CalendarWeekendColumnBand,
        kCalendarMaxDensityDots,
        kCalendarRowHeight;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

void main() {
  final DateTime visibleMonth = DateTime(2026, 7);
  final DateTime today = DateTime(2026, 7, 1);

  testWidgets(
    'a day with isAvailable=true is tappable and reports the exact date',
    (tester) async {
      DateTime? selected;

      await tester.pumpApp(
        Scaffold(
          body: MonthCalendar(
            visibleMonth: visibleMonth,
            today: today,
            selected: null,
            isAvailable: (DateTime day) => day.day == 15,
            onSelectDay: (DateTime day) => selected = day,
            onPrevMonth: null,
            onNextMonth: null,
          ),
        ),
      );

      final Finder cell = find.byKey(const Key('booking-calendar-day-15'));
      expect(cell, findsOneWidget);
      expect(
        find.descendant(of: cell, matching: find.byType(GestureDetector)),
        findsOneWidget,
      );

      // `tapCalendarDay` rather than a blind `tap(cell)`: this fixture mounts
      // MonthCalendar in a bare Scaffold (no scroll view), so `ensureVisible`
      // is a no-op here — but the helper is the single uniform entry point for
      // every enabled-cell tap (scripts/forbid_blind_calendar_tap.sh), so the
      // day this fixture grows a scroll ancestor it does not silently rot.
      await tester.tapCalendarDay(15);
      await tester.pumpAndSettle();

      expect(selected, DateTime(2026, 7, 15));
    },
  );

  testWidgets(
    'a day with isAvailable=false renders without a tap handler and never '
    'invokes onSelectDay',
    (tester) async {
      bool tapped = false;

      await tester.pumpApp(
        Scaffold(
          body: MonthCalendar(
            visibleMonth: visibleMonth,
            today: today,
            selected: null,
            // Day 10 is the sole unavailable day (e.g. a non-working day
            // under the Phase 14.14 gate) — every other day in the month
            // stays available so the finder below is unambiguous.
            isAvailable: (DateTime day) => day.day != 10,
            onSelectDay: (_) => tapped = true,
            onPrevMonth: null,
            onNextMonth: null,
          ),
        ),
      );

      final Finder cell = find.byKey(const Key('booking-calendar-day-10'));
      expect(cell, findsOneWidget);

      // The disabled `_DayCell` branch renders a bare `Semantics` with no
      // `GestureDetector` child — mirrors the `info.onTap == null` path.
      expect(
        find.descendant(of: cell, matching: find.byType(GestureDetector)),
        findsNothing,
      );

      await tester.tap(cell, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(tapped, isFalse);
    },
  );

  group('CalendarWeekdayBar / day-grid column alignment (regression)', () {
    // BUG: `CalendarWeekdayBar` used to self-pad at `VelvetSpacing.md + 2`
    // (18dp/side, copied from `period_range_picker.dart`'s
    // `_weekdayHeaderBar()`) while `MonthCalendar.build()`'s own outer
    // `Padding` — the effective inset for `_MonthGrid` beneath it — uses
    // `VelvetSpacing.lg` (24dp/side). A 6dp/side mismatch doesn't move the
    // MIDDLE weekday column at all (its center sits on the shared midline
    // regardless of inset), but drifts the two EDGE columns (Monday/Sunday)
    // increasingly as width grows — a golden test of the widget alone would
    // just re-bless whatever the current render is, so this asserts the
    // actual geometric invariant: each header label's horizontal center must
    // coincide with its day-grid column's horizontal center.
    //
    // Pumps `CalendarWeekdayBar` directly above `MonthCalendar` in a bare
    // `Column`, mirroring `slot_picker_screen.dart`'s real (unwrapped)
    // composition of the two widgets — see that file's `build()` comment at
    // its `CalendarWeekdayBar` usage.
    Future<void> expectHeaderAlignsWithGrid(
      WidgetTester tester, {
      required double width,
    }) async {
      final DateTime visibleMonth = DateTime(2026, 7);
      final int leadingBlanks =
          DateTime(visibleMonth.year, visibleMonth.month, 1).weekday - 1;
      // Grid-cell index 7 starts the SECOND week row, which is guaranteed to
      // be fully populated (no blank leading cells) no matter which weekday
      // the 1st falls on (`leadingBlanks` is at most 6) — so column 0
      // (Monday) and column 6 (Sunday) of this row always resolve to real,
      // in-month day numbers. See `_MonthGrid.build()`'s `cellDays` list.
      final int mondayDay = 8 - leadingBlanks;
      final int sundayDay = 14 - leadingBlanks;

      await tester.pumpApp(
        Scaffold(
          body: Column(
            children: <Widget>[
              // `CalendarWeekdayBar` renders no horizontal padding of its own
              // (mobile-backlog D4/D5) — every caller wraps it in the same
              // inset its sibling grid uses, mirroring
              // `slot_picker_screen.dart`'s real (production) composition.
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
                child: CalendarWeekdayBar(),
              ),
              MonthCalendar(
                visibleMonth: visibleMonth,
                today: visibleMonth,
                selected: null,
                isAvailable: (_) => true,
                onSelectDay: (_) {},
                onPrevMonth: null,
                onNextMonth: null,
              ),
            ],
          ),
        ),
        width: width,
      );
      await tester.pumpAndSettle();

      // `CalendarWeekdayBar` renders `weekdayAbbrev` verbatim (a hardcoded
      // Monday-first lookup, not an `AppLocalizations` lookup — see
      // `shared/formatters/uk_calendar.dart`), so locating by that same
      // accessor (rather than a duplicated Cyrillic literal) tracks the
      // widget's real source of truth instead of coupling the test to a copy
      // of it.
      final double mondayHeaderX = tester
          .getCenter(find.text(weekdayAbbrev(1)))
          .dx;
      final double sundayHeaderX = tester
          .getCenter(find.text(weekdayAbbrev(7)))
          .dx;
      final double mondayGridX = tester
          .getCenter(find.byKey(Key('booking-calendar-day-$mondayDay')))
          .dx;
      final double sundayGridX = tester
          .getCenter(find.byKey(Key('booking-calendar-day-$sundayDay')))
          .dx;

      expect(
        mondayHeaderX,
        closeTo(mondayGridX, 1.5),
        reason:
            'Monday ("пн") weekday label must sit directly above the '
            'Monday day-number column at width=$width — a header/grid '
            'inset mismatch drifts the label off the column, worst at the '
            'edge columns',
      );
      expect(
        sundayHeaderX,
        closeTo(sundayGridX, 1.5),
        reason:
            'Sunday ("нд") weekday label must sit directly above the '
            'Sunday day-number column at width=$width',
      );
    }

    testWidgets(
      'weekday header aligns with day-grid edge columns at width=360',
      (tester) async {
        await expectHeaderAlignsWithGrid(tester, width: 360);
      },
    );

    testWidgets(
      'weekday header aligns with day-grid edge columns at width=414',
      (tester) async {
        await expectHeaderAlignsWithGrid(tester, width: 414);
      },
    );

    // mobile-backlog D4 regression: the COMPOSED configuration
    // (`composeWeekdayBar: true`, `showHeader: false`) is exactly what
    // `BookingsMonthCalendarPanel` uses for the expanded «Мої записи»
    // calendar — the surface the user reported «пн» rendering between the
    // 3rd and 4th of серпня on. Before the fix, `CalendarWeekdayBar` self-
    // padded by `VelvetSpacing.lg` AND was composed inside `MonthCalendar`'s
    // own `VelvetSpacing.lg` outer `Padding`, doubling the inset to 48dp/side
    // against the grid's single 24dp/side — this test pumps that exact
    // composition and would have failed before the fix.
    testWidgets(
      'composed weekday bar (composeWeekdayBar: true) aligns with the grid',
      (tester) async {
        final DateTime visibleMonth = DateTime(2026, 7);
        final int leadingBlanks =
            DateTime(visibleMonth.year, visibleMonth.month, 1).weekday - 1;
        final int mondayDay = 8 - leadingBlanks;
        final int sundayDay = 14 - leadingBlanks;

        await tester.pumpApp(
          Scaffold(
            body: MonthCalendar(
              visibleMonth: visibleMonth,
              today: visibleMonth,
              selected: null,
              isAvailable: (_) => true,
              onSelectDay: (_) {},
              composeWeekdayBar: true,
              showHeader: false,
            ),
          ),
          width: 360,
        );
        await tester.pumpAndSettle();

        final double mondayHeaderX = tester
            .getCenter(find.text(weekdayAbbrev(1)))
            .dx;
        final double sundayHeaderX = tester
            .getCenter(find.text(weekdayAbbrev(7)))
            .dx;
        final double mondayGridX = tester
            .getCenter(find.byKey(Key('booking-calendar-day-$mondayDay')))
            .dx;
        final double sundayGridX = tester
            .getCenter(find.byKey(Key('booking-calendar-day-$sundayDay')))
            .dx;

        expect(
          mondayHeaderX,
          closeTo(mondayGridX, 1.5),
          reason:
              'composed «пн» must sit directly above the Monday day-number '
              'column — a double-padded bar drifts it a half column right',
        );
        expect(sundayHeaderX, closeTo(sundayGridX, 1.5));
      },
    );
  });

  // mobile-backlog D1 regression: a day with fewer than the max 3 density
  // dots must still render its LIT dot(s) centered under the day number —
  // not left-aligned inside a fixed 3-slot row. Ground truth is
  // `tester.getCenter`, per the task brief: a golden cannot prove this.
  group('density-dot centering (D1)', () {
    Future<double> pumpAndGetLitDotCentroidX(
      WidgetTester tester, {
      required int bookingsOnDay15,
    }) async {
      final DateTime visibleMonth = DateTime(2026, 7);
      await tester.pumpApp(
        Scaffold(
          body: MonthCalendar(
            visibleMonth: visibleMonth,
            today: DateTime(2026, 7, 1),
            selected: null,
            isAvailable: (_) => true,
            onSelectDay: (_) {},
            onPrevMonth: null,
            onNextMonth: null,
            bookingCount: (DateTime d) => d.day == 15 ? bookingsOnDay15 : 0,
          ),
        ),
        width: 360,
      );
      await tester.pumpAndSettle();

      final Finder cell = find.byKey(const Key('booking-calendar-day-15'));
      final Finder dots = find.descendant(
        of: cell,
        matching: find.byWidgetPredicate((Widget w) {
          if (w is! Container) return false;
          final BoxDecoration? d = w.decoration as BoxDecoration?;
          return d?.shape == BoxShape.circle;
        }),
      );
      final int n = dots.evaluate().length;
      expect(n, bookingsOnDay15, reason: 'exactly the lit dots are laid out');
      double minX = double.infinity, maxX = -double.infinity;
      for (int i = 0; i < n; i++) {
        final Rect r = tester.getRect(dots.at(i));
        minX = minX < r.left ? minX : r.left;
        maxX = maxX > r.right ? maxX : r.right;
      }
      return (minX + maxX) / 2;
    }

    testWidgets('a single lit dot centers under the day number', (
      tester,
    ) async {
      // The tree must be pumped (inside `pumpAndGetLitDotCentroidX`) BEFORE
      // either finder resolves — both address the same already-mounted
      // widget.
      final double dotX = await pumpAndGetLitDotCentroidX(
        tester,
        bookingsOnDay15: 1,
      );
      final double numberX = tester
          .getCenter(
            find.descendant(
              of: find.byKey(const Key('booking-calendar-day-15')),
              matching: find.text('15'),
            ),
          )
          .dx;
      expect(
        dotX,
        closeTo(numberX, 0.5),
        reason:
            'a single booking must render its dot centered under the day '
            'number, not left-aligned inside a reserved 3-slot row',
      );
    });

    testWidgets('two lit dots center as a group under the day number', (
      tester,
    ) async {
      final double dotsX = await pumpAndGetLitDotCentroidX(
        tester,
        bookingsOnDay15: 2,
      );
      final double numberX = tester
          .getCenter(
            find.descendant(
              of: find.byKey(const Key('booking-calendar-day-15')),
              matching: find.text('15'),
            ),
          )
          .dx;
      expect(dotsX, closeTo(numberX, 0.5));
    });
  });

  // mobile-backlog D2 regression: a day that is BOTH "today" and selected
  // must not paint the today ring on top of the selected trough — selected
  // wins, the ring stands down.
  group('today ring vs. selection precedence (D2)', () {
    Finder badgeContainer(Finder cell) => find.descendant(
      of: cell,
      matching: find.byWidgetPredicate(
        (Widget w) =>
            w is Container &&
            w.constraints ==
                const BoxConstraints.tightFor(width: 38, height: 38),
      ),
    );

    testWidgets('today ring renders when today is NOT selected', (
      tester,
    ) async {
      final DateTime today = DateTime(2026, 7, 15);
      await tester.pumpApp(
        Scaffold(
          body: MonthCalendar(
            visibleMonth: today,
            today: today,
            selected: null,
            isAvailable: (_) => true,
            onSelectDay: (_) {},
            onPrevMonth: null,
            onNextMonth: null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final Finder cell = find.byKey(const Key('booking-calendar-day-15'));
      final Container badge = tester.widget<Container>(badgeContainer(cell));
      final BoxDecoration? deco = badge.decoration as BoxDecoration?;
      expect(deco?.shape, BoxShape.circle, reason: 'unselected today rings');
    });

    testWidgets(
      'today ring is SUPPRESSED when today is also selected (no double '
      'disc)',
      (tester) async {
        final DateTime today = DateTime(2026, 7, 15);
        await tester.pumpApp(
          Scaffold(
            body: MonthCalendar(
              visibleMonth: today,
              today: today,
              selected: today,
              isAvailable: (_) => true,
              onSelectDay: (_) {},
              onPrevMonth: null,
              onNextMonth: null,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final Finder cell = find.byKey(const Key('booking-calendar-day-15'));
        final Container badge = tester.widget<Container>(badgeContainer(cell));
        expect(
          badge.decoration,
          isNull,
          reason:
              'a selected today must not ALSO paint the ring — the trough '
              '+ bold number already carry the "picked" signal',
        );
      },
    );
  });

  // mobile-backlog D3 REVERSAL (this session, explicit user request): the
  // weekend cue moved from the day NUMBER to a whole-column tinted band
  // (`MonthCalendar.showWeekendColumnBand`, `CalendarWeekendColumnBand`) —
  // "put whole weekend columns into grey / other colour ... not grey day
  // numbers". A weekend day number now renders IDENTICALLY to an ordinary
  // day's — `BrandColors.weekendMuted` no longer appears on any day-number
  // `Text.style` in this widget, regardless of `showWeekendColumnBand`. The
  // band itself is a purely presentational rect this group also confirms is
  // painted when the caller opts in.
  group('weekend day-number muting REMOVED (D3 reversal)', () {
    testWidgets(
      'an available, unselected Sunday number renders the NORMAL colour, '
      'not weekendMuted',
      (tester) async {
        // 2026-07-05 is a Sunday.
        final DateTime visibleMonth = DateTime(2026, 7);
        await tester.pumpApp(
          Scaffold(
            body: MonthCalendar(
              visibleMonth: visibleMonth,
              today: DateTime(2026, 7, 1),
              selected: null,
              isAvailable: (_) => true,
              onSelectDay: (_) {},
              onPrevMonth: null,
              onNextMonth: null,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final Text number = tester.widget<Text>(
          find.descendant(
            of: find.byKey(const Key('booking-calendar-day-5')),
            matching: find.text('5'),
          ),
        );
        expect(
          number.style?.color,
          BrandColors.accentDeep,
          reason:
              'the weekend cue is now the column band, not a muted number — '
              'an available Sunday reads exactly like an available Monday',
        );
      },
    );

    testWidgets('a SELECTED Sunday number stays legible (never muted)', (
      tester,
    ) async {
      final DateTime visibleMonth = DateTime(2026, 7);
      final DateTime sunday = DateTime(2026, 7, 5);
      await tester.pumpApp(
        Scaffold(
          body: MonthCalendar(
            visibleMonth: visibleMonth,
            today: DateTime(2026, 7, 1),
            selected: sunday,
            isAvailable: (_) => true,
            onSelectDay: (_) {},
            onPrevMonth: null,
            onNextMonth: null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final Text number = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('booking-calendar-day-5')),
          matching: find.text('5'),
        ),
      );
      expect(
        number.style?.color,
        BrandColors.accentDeep,
        reason: 'selected always outranks any de-emphasizing cue',
      );
    });

    testWidgets('an unavailable, non-tappable Sunday number still reads faint '
        '(unavailable outranks weekend, which no longer has a number cue '
        'at all)', (tester) async {
      final DateTime visibleMonth = DateTime(2026, 7);
      await tester.pumpApp(
        Scaffold(
          body: MonthCalendar(
            visibleMonth: visibleMonth,
            today: DateTime(2026, 7, 1),
            selected: null,
            isAvailable: (_) => false,
            onSelectDay: (_) {},
            onPrevMonth: null,
            onNextMonth: null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final Text number = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('booking-calendar-day-5')),
          matching: find.text('5'),
        ),
      );
      expect(number.style?.color, BrandColors.faint);
    });

    testWidgets('showWeekendColumnBand: false (default) paints NO band — '
        'SlotDateScreen/MasterSchedulePage render unchanged', (tester) async {
      final DateTime visibleMonth = DateTime(2026, 7);
      await tester.pumpApp(
        Scaffold(
          body: MonthCalendar(
            visibleMonth: visibleMonth,
            today: DateTime(2026, 7, 1),
            selected: null,
            isAvailable: (_) => true,
            onSelectDay: (_) {},
            onPrevMonth: null,
            onNextMonth: null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CalendarWeekendColumnBand), findsNothing);
    });

    testWidgets(
      'showWeekendColumnBand: true paints a band with REAL vertical extent '
      '(regression guard: a `Row` only tightens the width of its `Expanded` '
      'children — the cross-axis height stays LOOSE by default, so an '
      'unconstrained `DecoratedBox` collapses to `constraints.smallest` == '
      'height 0 even though `Positioned.fill` sized the `Row` itself '
      'correctly; `findsOneWidget` alone stayed green through exactly that '
      'collapse in the shipped-then-reverted first version of this file — '
      'see `CalendarWeekendColumnBand`\'s `crossAxisAlignment: stretch`), '
      'spanning the weekday-caption row through the last week row, aligned '
      'to the 5/7 column boundary through the grid\'s own right edge',
      (tester) async {
        final DateTime visibleMonth = DateTime(2026, 7);
        await tester.pumpApp(
          Scaffold(
            body: MonthCalendar(
              visibleMonth: visibleMonth,
              today: DateTime(2026, 7, 1),
              selected: null,
              isAvailable: (_) => true,
              onSelectDay: (_) {},
              composeWeekdayBar: true,
              sixWeekRows: true,
              showHeader: false,
              showWeekendColumnBand: true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(CalendarWeekendColumnBand), findsOneWidget);

        // `CalendarWeekendColumnBand` ITSELF is the full-width `Row` (a
        // blank flex-5 segment plus the flex-2 tinted one) — its own Rect
        // spans the WHOLE grid width, not just the shaded columns. The
        // widget that actually paints the tint is the inner `DecoratedBox`
        // (the flex-2 child), so horizontal assertions must target THAT,
        // not the wrapping band widget.
        final Finder tintedFinder = find.descendant(
          of: find.byType(CalendarWeekendColumnBand),
          matching: find.byType(DecoratedBox),
        );
        expect(
          tintedFinder,
          findsOneWidget,
          reason:
              'exactly one painted segment — the Sat+Sun merged flex-2 '
              'block; the Mon-Fri flex-5 segment is a bare SizedBox.shrink() '
              'with no decoration',
        );

        final Rect band = tester.getRect(tintedFinder);
        final Rect weekdayBar = tester.getRect(find.byType(CalendarWeekdayBar));
        final Rect lastRow = tester.getRect(find.byType(CalendarWeekRow).last);

        // The exact height a correctly-stretched band must resolve to: the
        // composed weekday bar + the gap beneath it + all six week rows —
        // i.e. `weekdayBarAndGrid`'s own laid-out height inside the `Stack`
        // (NOT `kMonthCalendarExpandedHeight`, which additionally includes
        // the outer `VelvetSpacing.sm` top padding that sits OUTSIDE the
        // `Stack` this band is positioned within).
        const double expectedHeight =
            kMonthCalendarWeekdayBarHeight +
            VelvetSpacing.xs +
            kMonthCalendarSixRows * kMonthCalendarRowHeight;
        expect(
          band.height,
          closeTo(expectedHeight, 1.0),
          reason:
              'band height measured ${band.height}, expected '
              '$expectedHeight — a value near 0 here IS the invisible-band '
              'regression (mobile-build-verifier\'s pixel read-back found '
              'zero #F0DBC0 pixels in the golden for exactly this reason).',
        );
        expect(
          band.height,
          greaterThan(300),
          reason:
              'sanity floor independent of the exact constant above — the '
              'band must span all 6 week rows plus the caption row, not a '
              'single row or nothing',
        );

        // Vertically: the weekday bar's own top through the last week row's
        // own bottom — the FULL composed block, not a per-row stripe.
        //
        // `lastRow` is `CalendarWeekRow` itself, whose OWN height is the
        // fixed `kCalendarRowHeight` (44) — `_MonthGrid.build()` wraps every
        // row in an extra `Padding(vertical: 3)` on top of that (that's
        // where `kMonthCalendarRowHeight` (50) = `kCalendarRowHeight` (44) +
        // 2 * that padding comes from), so the row's true bottom edge sits
        // `rowVerticalPad` below `lastRow.bottom` — comparing straight to
        // `lastRow.bottom` would be off by exactly that padding on every run.
        const double rowVerticalPad =
            (kMonthCalendarRowHeight - kCalendarRowHeight) / 2;
        expect(band.top, closeTo(weekdayBar.top, 1.0));
        expect(band.bottom, closeTo(lastRow.bottom + rowVerticalPad, 1.0));

        // Horizontally: starts exactly at the 5/7 column boundary
        // (Saturday's left edge) and runs to the grid's own right edge
        // (Sunday's right edge) — never wider (overhanging the panel's own
        // padding) or narrower (a sliver instead of a full column).
        final double expectedLeft = lastRow.left + lastRow.width * 5 / 7;
        expect(band.left, closeTo(expectedLeft, 1.0));
        expect(band.right, closeTo(lastRow.right, 1.0));
      },
    );
  });

  // mobile-qa gap closure (2026-08-14): mobile-build-verifier found that the
  // golden fixture's `_today == selectedDay == 2026-07-15` is a Wednesday and
  // every `_bookedDays` entry is Thu/Fri, so no capture ever put a selected
  // pill, a today ring, or a density dot INSIDE the weekend band — the claim
  // that they "still read on top of the band" rested purely on `Stack` paint
  // order (band painted first, content painted second — see
  // `MonthCalendar.build`), with zero pixel or widget-level evidence that the
  // ordering argument actually holds. 2026-07-18 is a Saturday — every test
  // below deliberately lands a foreground state ON that column and asserts
  // BOTH that the usual foreground assertion still holds (the D2/D1 pins
  // above, replayed on a weekend column) AND that the cell sits inside the
  // band's own painted rect — i.e. the two are provably co-located, not just
  // assumed to be by source-reading the `Stack` child order.
  //
  // A pixel-level golden variant (`bookings_month_calendar_panel_golden_test
  // .dart`'s "weekend selected+today+booked" scenario) is the actual GROUND
  // TRUTH for non-occlusion — these widget tests pin the STATE WIRING (ring
  // suppressed, trough present, dot count correct) fast and deterministically,
  // but only a rendered pixel read-back can prove the band does not paint
  // OVER the foreground, which is exactly the class of bug
  // (`CalendarWeekendColumnBand` collapsing/covering) this feature already
  // shipped once — see that file for the pixel-level proof.
  group('foreground state ON the weekend band (gap closure)', () {
    // 2026-07-18 (Saturday) is column index 5 (0=Mon..6=Sun) — inside the
    // band's Sat+Sun flex-2 segment. Every sub-test below composes the SAME
    // configuration `BookingsMonthCalendarPanel` uses in production
    // (`composeWeekdayBar: true, sixWeekRows: true, showWeekendColumnBand:
    // true`) so the band this asserts against is the real production one, not
    // a hypothetical.
    const int kSaturday = 18;

    Future<Rect> pumpAndGetBandRect(WidgetTester tester) async {
      final Rect band = tester.getRect(
        find.descendant(
          of: find.byType(CalendarWeekendColumnBand),
          matching: find.byType(DecoratedBox),
        ),
      );
      return band;
    }

    Rect cellRect(WidgetTester tester, int day) =>
        tester.getRect(find.byKey(Key('booking-calendar-day-$day')));

    void expectInsideBand(Rect cell, Rect band, {required String reason}) {
      expect(
        cell.left,
        greaterThanOrEqualTo(band.left - 1.0),
        reason: '$reason — cell left edge fell outside the band',
      );
      expect(
        cell.right,
        lessThanOrEqualTo(band.right + 1.0),
        reason: '$reason — cell right edge fell outside the band',
      );
      // VERTICAL containment too — not just horizontal. A band that collapses
      // to height 0 (the exact bug this feature already shipped once, see
      // `CalendarWeekendColumnBand`'s `crossAxisAlignment: stretch` doc) keeps
      // its correct LEFT/RIGHT (the `Row`'s main-axis flex sizing is
      // unaffected by the cross-axis collapse), so a horizontal-only check
      // would stay green straight through that regression. Asserting the
      // cell's vertical span sits inside the band's is what actually makes
      // this assertion sensitive to that specific historical bug, not merely
      // a restatement of the existing height-focused D3 test.
      expect(
        cell.top,
        greaterThanOrEqualTo(band.top - 1.0),
        reason:
            '$reason — cell top edge fell outside the band (a height-0 band '
            'would fail here)',
      );
      expect(
        cell.bottom,
        lessThanOrEqualTo(band.bottom + 1.0),
        reason:
            '$reason — cell bottom edge fell outside the band (a height-0 '
            'band would fail here)',
      );
    }

    testWidgets(
      'a weekend day that is TODAY (not selected) still paints its today '
      'ring, and the cell sits inside the tinted band',
      (tester) async {
        final DateTime visibleMonth = DateTime(2026, 7);
        final DateTime saturday = DateTime(2026, 7, kSaturday);
        await tester.pumpApp(
          Scaffold(
            body: MonthCalendar(
              visibleMonth: visibleMonth,
              today: saturday,
              selected: null,
              isAvailable: (_) => true,
              onSelectDay: (_) {},
              composeWeekdayBar: true,
              sixWeekRows: true,
              showHeader: false,
              showWeekendColumnBand: true,
            ),
          ),
          width: 360,
        );
        await tester.pumpAndSettle();

        final Finder cell = find.byKey(
          const Key('booking-calendar-day-$kSaturday'),
        );
        final Finder badge = find.descendant(
          of: cell,
          matching: find.byWidgetPredicate(
            (Widget w) =>
                w is Container &&
                w.constraints ==
                    const BoxConstraints.tightFor(width: 38, height: 38),
          ),
        );
        final Container badgeWidget = tester.widget<Container>(badge);
        final BoxDecoration? deco = badgeWidget.decoration as BoxDecoration?;
        expect(
          deco?.shape,
          BoxShape.circle,
          reason: 'an unselected today must still ring on a weekend column',
        );

        final Rect band = await pumpAndGetBandRect(tester);
        expectInsideBand(
          cellRect(tester, kSaturday),
          band,
          reason: 'the ringed today cell must be co-located with the band',
        );
      },
    );

    testWidgets(
      'a weekend day that is SELECTED paints its trough + bold accentDeep '
      'number, and the cell sits inside the tinted band',
      (tester) async {
        final DateTime visibleMonth = DateTime(2026, 7);
        final DateTime saturday = DateTime(2026, 7, kSaturday);
        await tester.pumpApp(
          Scaffold(
            body: MonthCalendar(
              visibleMonth: visibleMonth,
              today: DateTime(2026, 7, 1),
              selected: saturday,
              isAvailable: (_) => true,
              onSelectDay: (_) {},
              composeWeekdayBar: true,
              sixWeekRows: true,
              showHeader: false,
              showWeekendColumnBand: true,
            ),
          ),
          width: 360,
        );
        await tester.pumpAndSettle();

        final Finder cell = find.byKey(
          const Key('booking-calendar-day-$kSaturday'),
        );

        // Selection trough — the recessed `NeumorphicInset` `CalendarWeekRow`
        // paints behind a selected run.
        expect(
          find.descendant(
            of: find.byType(CalendarWeekRow),
            matching: find.byType(NeumorphicInset),
          ),
          findsWidgets,
          reason:
              'a selected weekend day must still get the recessed selection '
              'trough behind it',
        );

        final Text number = tester.widget<Text>(
          find.descendant(of: cell, matching: find.text('$kSaturday')),
        );
        expect(number.style?.color, BrandColors.accentDeep);
        expect(number.style?.fontWeight, FontWeight.w700);

        final Rect band = await pumpAndGetBandRect(tester);
        expectInsideBand(
          cellRect(tester, kSaturday),
          band,
          reason: 'the selected cell must be co-located with the band',
        );
      },
    );

    testWidgets(
      'a weekend day with bookings paints its density dot(s), and the cell '
      'sits inside the tinted band',
      (tester) async {
        final DateTime visibleMonth = DateTime(2026, 7);
        await tester.pumpApp(
          Scaffold(
            body: MonthCalendar(
              visibleMonth: visibleMonth,
              today: DateTime(2026, 7, 1),
              selected: null,
              isAvailable: (_) => true,
              onSelectDay: (_) {},
              composeWeekdayBar: true,
              sixWeekRows: true,
              showHeader: false,
              showWeekendColumnBand: true,
              bookingCount: (DateTime d) => d.day == kSaturday ? 2 : 0,
            ),
          ),
          width: 360,
        );
        await tester.pumpAndSettle();

        final Finder cell = find.byKey(
          const Key('booking-calendar-day-$kSaturday'),
        );
        final Finder dots = find.descendant(
          of: cell,
          matching: find.byWidgetPredicate((Widget w) {
            if (w is! Container) return false;
            final BoxDecoration? d = w.decoration as BoxDecoration?;
            return d?.shape == BoxShape.circle &&
                w.constraints ==
                    const BoxConstraints.tightFor(width: 4, height: 4);
          }),
        );
        expect(
          dots.evaluate().length,
          2,
          reason: 'a booked weekend day must still render its density dots',
        );

        final Rect band = await pumpAndGetBandRect(tester);
        expectInsideBand(
          cellRect(tester, kSaturday),
          band,
          reason: 'the booked cell must be co-located with the band',
        );
      },
    );

    testWidgets(
      'the reported gap: a weekend day that is TODAY + SELECTED + BOOKED all '
      'at once renders the trough (ring suppressed, D2 precedence), bold '
      'number, and 3 density dots TOGETHER, inside the tinted band',
      (tester) async {
        final DateTime visibleMonth = DateTime(2026, 7);
        final DateTime saturday = DateTime(2026, 7, kSaturday);
        await tester.pumpApp(
          Scaffold(
            body: MonthCalendar(
              visibleMonth: visibleMonth,
              today: saturday,
              selected: saturday,
              isAvailable: (_) => true,
              onSelectDay: (_) {},
              composeWeekdayBar: true,
              sixWeekRows: true,
              showHeader: false,
              showWeekendColumnBand: true,
              bookingCount: (DateTime d) => d.day == kSaturday ? 5 : 0,
            ),
          ),
          width: 360,
        );
        await tester.pumpAndSettle();

        final Finder cell = find.byKey(
          const Key('booking-calendar-day-$kSaturday'),
        );

        // D2 precedence replayed on the weekend column: selected wins, the
        // ring stands down — this is the SAME cell that is also `today`.
        final Finder badge = find.descendant(
          of: cell,
          matching: find.byWidgetPredicate(
            (Widget w) =>
                w is Container &&
                w.constraints ==
                    const BoxConstraints.tightFor(width: 38, height: 38),
          ),
        );
        final Container badgeWidget = tester.widget<Container>(badge);
        expect(
          badgeWidget.decoration,
          isNull,
          reason:
              'selected must suppress the today ring on a weekend day too — '
              'no double disc',
        );

        final Text number = tester.widget<Text>(
          find.descendant(of: cell, matching: find.text('$kSaturday')),
        );
        expect(number.style?.color, BrandColors.accentDeep);
        expect(number.style?.fontWeight, FontWeight.w700);

        final Finder dots = find.descendant(
          of: cell,
          matching: find.byWidgetPredicate((Widget w) {
            if (w is! Container) return false;
            final BoxDecoration? d = w.decoration as BoxDecoration?;
            return d?.shape == BoxShape.circle &&
                w.constraints ==
                    const BoxConstraints.tightFor(width: 4, height: 4);
          }),
        );
        expect(
          dots.evaluate().length,
          kCalendarMaxDensityDots,
          reason: '5 bookings caps at kCalendarMaxDensityDots (3)',
        );

        final Rect band = await pumpAndGetBandRect(tester);
        expectInsideBand(
          cellRect(tester, kSaturday),
          band,
          reason:
              'the combined today+selected+booked cell must be co-located '
              'with the band — this is the exact scenario the golden fixture '
              '(_today Wed 2026-07-15) never exercised',
        );
      },
    );
  });

  group('showWeekendColumnBand constructor contract', () {
    test('showWeekendColumnBand: true without composeWeekdayBar/sixWeekRows '
        'throws — the band Stack sizes itself off the composed Column\'s '
        'height, which is undefined without both', () {
      expect(
        () => MonthCalendar(
          visibleMonth: DateTime(2026, 7),
          today: DateTime(2026, 7, 1),
          selected: null,
          isAvailable: (_) => true,
          onSelectDay: (_) {},
          showWeekendColumnBand: true,
          // composeWeekdayBar/sixWeekRows left at their `false` default.
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
