// mobile-qa (2026-08-14) — visual-regression goldens for the «Мої записи»
// calendar panel, in BOTH resting states.
//
// WHY THIS EARNS A GOLDEN (against the project's ~10% "critical UI" policy)
// -------------------------------------------------------------------------
// The policy names calendar grids explicitly, and this rework is a pure
// RENDER change to one: a header was deleted from inside the grid and its
// month caption re-anchored 48dp higher into the panel's own top row; two
// chevron buttons were removed; and the collapsed rail's chips went from a
// fixed 62dp `itemExtent` to seven `Expanded` slots inside a
// `BoxFit.scaleDown` `FittedBox`. Nothing under `test/golden/` referenced
// `MonthCalendar`, `BookingsDayRail` or this panel before this file
// (mobile-build-verifier, same date).
//
// The numeric widget tier already pins the individual figures it knows to
// ask about — the Monday's `VelvetSpacing.lg` inset, the chip ordering, the
// expanded height constant, no-overflow at 320dp × 2.0. What it cannot state
// is the RELATIONSHIP between all of them at once: that the rail's seven
// columns line up with the grid's seven columns and with
// `CalendarWeekdayBar`'s seven captions (the stated reason the rail's inset
// was changed to match `MonthCalendar`'s), and that removing the header did
// not leave a band of dead space or shift the grid off its column grid. That
// is a whole-composition property, which is what a golden is for.
//
// ⚠ WHAT THIS FILE IS *NOT*. These PNGs were GENERATED from the current
// build, so they are self-referential: they are a forward tripwire against
// the NEXT unintended render change, and they are NOT acceptance evidence
// that the current rendering is correct. Acceptance for this rework is the
// user's own approval of the running app plus the numeric widget-tier pins;
// see mobile-backlog `feedback_golden_not_acceptance`. Do not cite a green
// run of this file as proof that a reported visual bug is absent, and never
// "fix" a visual bug by re-running `--update-goldens`.
//
// MATRIX — 3 cells per state, deliberately narrow:
//   • 360 × 1.0 — the reference phone, where the chip `FittedBox` is a no-op
//     (a 44.6dp slot against a 44dp column) so the design renders as drawn;
//   • 320 × 1.0 — the narrow-phone floor, where the slot is 38.9dp and the
//     fit genuinely engages;
//   • 320 × 1.3 — the floor at the accessibility scale the rest of the
//     golden matrix uses, i.e. the cell most likely to regress.
// 414 is skipped on purpose: it differs from 360 only in slot width, which
// is already a pure linear function of the width the other two cells bracket
// — a third PNG per state for no additional failure mode is exactly the
// golden bloat the ~10% policy exists to prevent.
//
// Alchemist runs in CI mode suite-wide (`test/flutter_test_config.dart`),
// which obscures text into coloured blocks. That is a FEATURE here: every
// property this file is about is geometric, and obscuring the glyphs makes
// the images byte-stable across runners and font revisions.

import 'package:alchemist/alchemist.dart' show PumpWidget;
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_day_rail.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_month_calendar_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/golden_pump.dart';

/// A fixed Wednesday, mid-month. The panel takes `today`/`selectedDay` as
/// plain inputs and reads no clock of its own, so this file needs no
/// `clockProvider` override and is immune to the mixed-clock trap (M15) by
/// construction — there is only one clock here, and it is a constant.
final DateTime _today = DateTime(2026, 7, 15);

/// Days carrying a booking, so BOTH the rail's dot and the grid's density dot
/// are exercised. Includes a day inside the visible week (the 16th) and days
/// elsewhere in the month, so the collapsed and expanded states each show at
/// least one.
final Set<DateTime> _bookedDays = <DateTime>{
  DateTime(2026, 7, 16),
  DateTime(2026, 7, 17),
  DateTime(2026, 7, 23),
  DateTime(2026, 7, 30),
};

const Key _toggleKey = Key('bookings-month-calendar-toggle');

/// Fixed heights for the two states — the panel is a `Stack` of `Positioned`
/// children and needs a bounded box. Generous enough that the timeline
/// stand-in's slot is never negative at either state.
const double _kCollapsedBox = 200;
const double _kExpandedBox = 520;

/// mobile-qa gap closure (2026-08-14) — a SATURDAY that is simultaneously
/// `today`, `selectedDay`, AND a booked day. `_today` above (2026-07-15) is a
/// Wednesday and every `_bookedDays` entry is Thu/Fri, so the main matrix
/// above NEVER put a today-ring, a selected-trough, or a density dot inside
/// the weekend column band — mobile-build-verifier flagged that the "the
/// foreground still reads on top of the band" claim rested purely on `Stack`
/// paint order (`MonthCalendar.build`: band painted first, content painted
/// second), with zero pixel evidence. This is the ground-truth check for
/// that: an actual rendered pixel read-back (see the PNG produced by this
/// scenario) is the only way to prove the band does not visually occlude the
/// foreground — a widget test can assert the STATE (ring suppressed, trough
/// present, dot count correct — see `month_calendar_test.dart`'s "foreground
/// state ON the weekend band" group) but cannot observe actual COMPOSITED
/// pixel colour, which is exactly the axis the original band-collapse defect
/// broke on.
final DateTime _todayWeekend = DateTime(2026, 7, 18);
final Set<DateTime> _bookedDaysWeekend = <DateTime>{_todayWeekend};

/// Owns the rail's `PageController` so the panel gets the same wiring the
/// real screen hands it.
class _PanelFixture extends StatefulWidget {
  const _PanelFixture({required this.height, this.today, this.bookedDays});

  final double height;

  /// `null` (the default) resolves to [_today], the main matrix's Wednesday
  /// fixture, inside [_PanelFixtureState] — a top-level `final` (not `const`)
  /// `DateTime`/`Set` cannot be a `const` constructor's default parameter
  /// value, so the null-and-resolve indirection is required, not stylistic.
  /// The weekend gap-closure scenario below passes [_todayWeekend] instead.
  final DateTime? today;
  final Set<DateTime>? bookedDays;

  @override
  State<_PanelFixture> createState() => _PanelFixtureState();
}

class _PanelFixtureState extends State<_PanelFixture> {
  DateTime get _effectiveToday => widget.today ?? _today;
  Set<DateTime> get _effectiveBookedDays => widget.bookedDays ?? _bookedDays;

  /// Derived exactly as `_BookingsDiscoveryViewState.initState` does, so the
  /// rail opens on `_effectiveToday`'s own Mon→Sun week.
  late final DateTime firstWeekStart = railDayAt(
    mondayOf(_effectiveToday),
    -kRailWeekLength * kBookingsDayRailWeekSpan,
  );

  late final PageController railController = PageController(
    initialPage: railWeekIndex(firstWeekStart, _effectiveToday),
  );

  @override
  void dispose() {
    railController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: BookingsMonthCalendarPanel(
        railController: railController,
        railFirstWeekStart: firstWeekStart,
        weekCount: kBookingsDayRailWeekSpan * 2 + 1,
        today: _effectiveToday,
        // selected == today, matching this file's original fixture's own
        // choice — the weekend scenario additionally wants `selected` to
        // land on the SAME weekend cell as `today` and the booking, so the
        // gap this file closes (today + selected + booked all on one
        // weekend cell) is actually exercised, not merely a weekend `today`
        // alone.
        selectedDay: _effectiveToday,
        bookedDays: _effectiveBookedDays,
        onSelectRailDay: (DateTime _) {},
        onSelectDay: (DateTime _) {},
        onStepMonth: (int _) {},
        // A flat block rather than the real timeline: this file is about the
        // CALENDAR's render, and a real timeline would drag its own booking
        // cards, ruler and gridlines into every cell — coupling these PNGs to
        // changes that have nothing to do with the panel.
        timeline: const ColoredBox(
          color: Color(0x11000000),
          child: SizedBox.expand(),
        ),
      ),
    );
  }
}

/// The default pump, plus a tap on the toggle so the panel settles fully
/// EXPANDED before capture. `pumpAndSettle` inside `goldenPumpWidget` has
/// already run, so the 280 ms open animation is the only thing left to
/// drain — and it is driven by a real `AnimationController`, so the settle
/// lands on exactly `_open.value == 1`, never a mid-drag fraction.
PumpWidget _expandedPump({required double width}) {
  final PumpWidget base = goldenPumpWidget(width: width);
  return (WidgetTester tester, Widget alchemistWidget) async {
    await base(tester, alchemistWidget);
    await tester.tap(find.byKey(_toggleKey));
    await tester.pumpAndSettle();
  };
}

void main() {
  // (width, textScale) — see the file header for why the matrix is these
  // three and not the full 3 × 2.
  const List<(double, double)> matrix = <(double, double)>[
    (360, 1.0),
    (320, 1.0),
    (320, 1.3),
  ];

  for (final (double width, double scale) in matrix) {
    final String suffix = widthScaleSuffix(width, scale);

    goldenTest(
      'bookings calendar panel — COLLAPSED ${width}dp x$scale',
      fileName: 'bookings_month_calendar_panel_collapsed_$suffix',
      constraints: BoxConstraints.tight(Size(width, _kCollapsedBox)),
      textScaleFactor: scale,
      pumpWidget: goldenPumpWidget(width: width),
      builder: () => const _PanelFixture(height: _kCollapsedBox),
    );

    goldenTest(
      'bookings calendar panel — EXPANDED ${width}dp x$scale',
      fileName: 'bookings_month_calendar_panel_expanded_$suffix',
      constraints: BoxConstraints.tight(Size(width, _kExpandedBox)),
      textScaleFactor: scale,
      pumpWidget: _expandedPump(width: width),
      builder: () => const _PanelFixture(height: _kExpandedBox),
    );
  }

  // mobile-qa gap closure (2026-08-14) — see [_todayWeekend]'s doc. ONE
  // width/scale cell (360dp x1.0, the reference phone, same cell the file
  // header calls out as "where the design renders as drawn") — not the full
  // 3-cell matrix: this scenario's only question is whether the foreground
  // (ring/trough/dot) is visually OCCLUDED by the band, which is a
  // composition property independent of the narrow-phone `FittedBox`
  // engagement the 320dp cells exist to probe (see the file header's matrix
  // rationale) — a second and third PNG here would be golden bloat for no
  // additional failure mode, exactly what the ~10% "critical UI only" policy
  // warns against.
  goldenTest(
    'bookings calendar panel — EXPANDED, weekend day is today+selected+'
    'booked (gap closure) 360dp x1.0',
    fileName: 'bookings_month_calendar_panel_expanded_weekend_selected_360_1x',
    constraints: BoxConstraints.tight(const Size(360, _kExpandedBox)),
    textScaleFactor: 1.0,
    pumpWidget: _expandedPump(width: 360),
    builder: () => _PanelFixture(
      height: _kExpandedBox,
      today: _todayWeekend,
      bookedDays: _bookedDaysWeekend,
    ),
  );
}
