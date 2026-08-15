// Calendar grid primitives shared by EVERY month-grid calendar surface in
// the app — the weekday header bar, the 7-column week row (with its
// contiguous-selection recessed trough), and the single day cell.
//
// Extracted from `features/booking/presentation/widgets/month_calendar.dart`
// (mobile-backlog D5, this session): before this file existed,
// `shared/widgets/period_range_picker.dart` reimplemented ~250 lines of the
// same weekday-bar / week-row / day-cell logic as a forked copy, which is why
// it never received the D1–D4 fixes landing alongside this file — a fix to
// `month_calendar.dart` alone could never reach it. Both callers now compose
// these primitives instead, so a future fix here lands on every calendar at
// once.
//
// `BookingsDayRail._DayChip` (`bookings_day_rail.dart`) is a HORIZONTAL day
// CHIP, not a grid cell — different shape, legitimately not built from
// [CalendarDayCell] — but it shares [isWeekendWeekday] with everything below
// so the weekend-muting rule (D3) cannot drift between it and the grid
// surfaces.
//
// ## D1 — density-dot centering
//
// [CalendarDayCell]'s dot row renders EXACTLY the lit dot count (never a
// fixed N-slot row padded with transparent fillers) so the group of visible
// dots is centered by the same `Column(crossAxisAlignment: center)` machinery
// that already centers the day-number badge — see the class doc for the
// measured before/after.
//
// ## D2 — today ring vs. selected trough
//
// A day can be BOTH "today" (a ring) and part of a selected run (a recessed
// [NeumorphicInset] trough painted behind the row by [CalendarWeekRow]). Two
// discs at the same radius read as mud. SELECTED WINS: [CalendarDayCell]
// only paints the today ring when the cell is NOT selected — the trough plus
// the bold number weight already carries the "this one is picked" signal on
// its own.
//
// ## D3 — weekend muting precedence
//
// Exactly one function, [calendarDayIsDeemphasized], encodes "selected always
// outranks a de-emphasizing state (weekend, past, disabled/unavailable)" —
// every calendar surface (and the day rail) calls through it rather than
// re-deriving the same precedence independently.
//
// ## D4 — one inset per surface
//
// [CalendarWeekdayBar] applies NO horizontal padding of its own — every
// caller wraps it in the SAME `EdgeInsets.symmetric(horizontal: …)` its
// sibling grid uses, so the two can never drift apart the way they did
// before (`month_calendar.dart`'s composed-bar double-padding bug).

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/shared/formatters/uk_calendar.dart';

/// Every week-grid row (and the header bar) shares this height — a 44dp cell
/// band, unchanged from the pre-consolidation widgets.
const double kCalendarRowHeight = 44;

/// The day-number badge's fixed square face.
const double kCalendarDayBadgeSize = 38;

/// Cap on rendered density dots — [CalendarDayCell.dots] above this is a
/// caller bug, not a value this widget clamps.
const int kCalendarMaxDensityDots = 3;

/// The has-bookings dot color every calendar surface uses at full strength —
/// [CalendarDayCell]'s own default [CalendarDayCell.litDotColor], and
/// `BookingsDayRail._DayChip`'s single dot (which stays a separate widget —
/// a horizontal chip, not a grid cell — but must not drift from this one
/// constant; see this file's header).
const Color kCalendarDotColor = BrandColors.accent;

/// Whether Dart's 1(Mon)…7(Sun) [weekday] falls on a Saturday or Sunday.
///
/// The single source every calendar surface (and [BookingsDayRail]'s day
/// chip) reads for the D3 weekend-mute rule — never re-derive `weekday == 6
/// || weekday == 7` independently.
bool isWeekendWeekday(int weekday) =>
    weekday == DateTime.saturday || weekday == DateTime.sunday;

/// Precedence for every de-emphasized (muted/faint) calendar day state,
/// encoded once so it cannot drift between calendar surfaces: a SELECTED day
/// is never allowed to read muted, no matter how many de-emphasizing
/// conditions also apply to it.
///
/// [deemphasize] is the surface's own "this should read muted" condition —
/// callers OR together whichever of weekend / past / unavailable apply to
/// them; this function only ever answers the one question of whether
/// [selected] overrides that.
bool calendarDayIsDeemphasized({
  required bool selected,
  required bool deemphasize,
}) => deemphasize && !selected;

/// A contiguous run of selected columns within one week row (inclusive
/// column indices, `0`..`6`).
typedef CalendarSelectedRun = (int start, int end);

/// Derives the contiguous selected-column runs of a 7-wide week row from a
/// per-column selected flag — the single implementation [CalendarWeekRow]'s
/// two callers (the month grid, the range picker) both used to hand-roll
/// identically.
List<CalendarSelectedRun> computeSelectedRuns(List<bool> selectedByColumn) {
  assert(
    selectedByColumn.length == 7,
    'a week row always has exactly 7 columns',
  );
  final List<CalendarSelectedRun> runs = <CalendarSelectedRun>[];
  int? start;
  for (int c = 0; c < 7; c++) {
    if (selectedByColumn[c] && start == null) {
      start = c;
    } else if (!selectedByColumn[c] && start != null) {
      runs.add((start, c - 1));
      start = null;
    }
  }
  if (start != null) {
    runs.add((start, 6));
  }
  return runs;
}

/// The pinned Monday-first weekday header row — «пн вт ср чт пт сб нд» — used
/// above every month grid in the app.
///
/// Renders NO horizontal padding itself (see the file header's D4 note) — the
/// caller wraps it in whatever horizontal inset its own sibling grid uses.
/// Saturday/Sunday captions render [BrandColors.weekendMuted]; the other five
/// render [BrandColors.textSecondary] — see the file header's D3 note for why
/// [VelvetText.label11]'s own built-in color (`muted`) is overridden here
/// rather than left as the "normal" tone: without an explicit split every
/// caption read identically muted and the weekend cue could never exist.
/// [BrandColors.weekendMuted], not [BrandColors.muted]: this bar's captions
/// are always-visible, non-interactive but ACTIVE (part of an operable
/// grid's header) text, so WCAG 1.4.3's "inactive component" exemption does
/// not cover them — [BrandColors.muted] fails AA (2.69:1 on
/// [BrandColors.base]); [BrandColors.weekendMuted] clears it (5.07:1). See
/// [BrandColors.weekendMuted]'s own doc.
class CalendarWeekdayBar extends StatelessWidget {
  const CalendarWeekdayBar({super.key, this.labels});

  /// Overrides the seven Monday-first captions. `null` (the default) uses
  /// [weekdayAbbrev]'s hard-coded lowercase vocabulary («пн»…«нд») — every
  /// caller except [PeriodRangePicker]. [PeriodRangePicker]'s own
  /// `PeriodRangePickerStrings.weekdayShort` resolves through
  /// `AppLocalizations` instead («Пн»…«Нд», capitalized) — a pre-existing
  /// copy difference this consolidation does not change — so it passes its
  /// own list through here rather than silently switching caption text.
  /// Column geometry, weekend muting (D3) and the shared inset contract are
  /// identical either way: those are keyed by column INDEX, never by the
  /// label string.
  final List<String>? labels;

  /// Hoisted — the seven default captions are fixed for the (hard-coded,
  /// Monday-first) vocabulary this bar uses and were being rebuilt into a
  /// fresh `List<String>` on every `build()`.
  static final List<String> _weekdayLabels = List<String>.unmodifiable(<String>[
    for (int day = 1; day <= 7; day++) weekdayAbbrev(day),
  ]);

  @override
  Widget build(BuildContext context) {
    final List<String> effective = labels ?? _weekdayLabels;
    assert(
      effective.length == 7,
      'CalendarWeekdayBar always renders exactly 7 columns',
    );
    return Row(
      children: <Widget>[
        for (int i = 0; i < effective.length; i++)
          Expanded(
            child: Center(
              child: Text(
                effective[i],
                style: VelvetText.label11.copyWith(
                  color: isWeekendWeekday(i + 1)
                      ? BrandColors.weekendMuted
                      : BrandColors.textSecondary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// One week's row: an optional recessed "selection trough" layer (painted
/// behind, one per contiguous run of selected columns) plus the row of 7 day
/// cells on top. Shared by every month-grid calendar surface.
class CalendarWeekRow extends StatelessWidget {
  const CalendarWeekRow({
    super.key,
    required this.cells,
    this.selectedRuns = const <CalendarSelectedRun>[],
  }) : assert(cells.length == 7, 'a week row always has exactly 7 columns');

  /// Exactly 7 day cells, Monday through Sunday.
  final List<Widget> cells;

  /// Contiguous selected-column runs to draw a recessed trough behind — see
  /// [computeSelectedRuns].
  final List<CalendarSelectedRun> selectedRuns;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kCalendarRowHeight,
      child: Stack(
        children: <Widget>[
          for (final CalendarSelectedRun run in selectedRuns)
            Positioned.fill(
              child: Row(
                children: <Widget>[
                  for (int c = 0; c < 7; c++)
                    Expanded(
                      child: c < run.$1 || c > run.$2
                          ? const SizedBox.shrink()
                          : const Padding(
                              padding: EdgeInsets.symmetric(vertical: 3),
                              child: NeumorphicInset(
                                radius: 12,
                                child: SizedBox.expand(),
                              ),
                            ),
                    ),
                ],
              ),
            ),
          Row(
            children: <Widget>[
              for (final Widget cell in cells) Expanded(child: cell),
            ],
          ),
        ],
      ),
    );
  }
}

/// One day cell: a centered day-number badge, an optional "today" ring, and
/// an optional row of density dots beneath it. Shared by every month-grid
/// calendar surface — see the file header for the D1/D2 fixes this consolidation
/// carries.
///
/// All coloring/weight/label decisions are resolved by the CALLER (each
/// surface's own availability/selection semantics differ too much to force
/// into one shared enum) — this widget owns only the shared PAINT geometry,
/// the today-ring-vs-selected precedence, the dot-centering fix, and the
/// tap/semantics wiring.
class CalendarDayCell extends StatelessWidget {
  const CalendarDayCell({
    super.key,
    required this.cellKey,
    required this.day,
    required this.numberStyle,
    required this.isToday,
    required this.hasSelectionTrough,
    required this.semanticsSelected,
    required this.ringColor,
    required this.semanticsLabel,
    required this.onTap,
    this.dots,
    this.litDotColor = kCalendarDotColor,
  });

  /// `null` renders a blank (leading/trailing) cell.
  final int? day;

  /// Widget key for the day cell — `null` only makes sense for a blank cell.
  final Key? cellKey;

  /// The fully-resolved day-number style — colour AND weight — for this
  /// cell. mobile-perf MEDIUM (calendar-consolidation audit): this used to
  /// be a `Color numberColor` + `FontWeight fontWeight` pair that [build]
  /// resolved into a `TextStyle` via `.copyWith(...)` on every build, one
  /// allocation per non-blank cell per rebuild. A single pre-resolved style
  /// lets each caller own its own hoisting strategy — [PeriodRangePicker]'s
  /// `_DayCell` restores its pre-consolidation `static final` table (perf
  /// P5); `MonthCalendar`'s `_dayCell` resolves inline, same as before this
  /// widget existed (never hoisted there either, so this is neutral for it).
  final TextStyle numberStyle;

  final bool isToday;

  /// Whether [CalendarWeekRow] already paints a selected-run trough (or an
  /// equivalent "picked" treatment) behind this cell — see the file header's
  /// D2 note. Suppresses the today ring so the two never stack. Distinct from
  /// [semanticsSelected]: a range picker's IN-BETWEEN day sits under the same
  /// trough as its endpoints (so the ring must stand down for it too) but is
  /// not itself an accessibility "selected" node the way an endpoint is.
  final bool hasSelectionTrough;

  /// Accessibility `Semantics.selected` value — the caller's OWN definition
  /// of "selected" (which may be narrower than [hasSelectionTrough], e.g. a
  /// range picker's endpoints only).
  final bool semanticsSelected;

  final Color ringColor;
  final String semanticsLabel;
  final VoidCallback? onTap;

  /// Number of lit density dots to render (`0`..[kCalendarMaxDensityDots]),
  /// or `null` to render no dot row at all — the day-number badge is then the
  /// cell's full content, exactly as before density dots existed.
  final int? dots;

  /// Color every lit dot renders in. Ignored when [dots] is `null`.
  final Color litDotColor;

  @override
  Widget build(BuildContext context) {
    final int? d = day;
    if (d == null) {
      return const SizedBox(height: kCalendarRowHeight);
    }

    final Widget number = Text('$d', style: numberStyle);

    // D2 fix — see the file header. A trough/selected cell already reads as
    // "picked"; painting the ring on top of it as well is the mud the user
    // reported.
    final bool showTodayRing = isToday && !hasSelectionTrough;
    final BoxDecoration? ring = showTodayRing
        ? BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: ringColor, width: 1.8),
          )
        : null;

    final Widget badge = Container(
      height: kCalendarDayBadgeSize,
      width: kCalendarDayBadgeSize,
      alignment: Alignment.center,
      decoration: ring,
      child: number,
    );

    final int? dotCount = dots;
    final Widget content = dotCount == null
        ? badge
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              badge,
              const SizedBox(height: 2),
              SizedBox(
                height: 4,
                // D1 fix — see the file header. Only the LIT dots are laid
                // out (never a fixed 3-slot row padded with transparent
                // fillers), so `Column`'s own centering places the group of
                // visible dots on the SAME axis as the badge above it at
                // every dot count, not only when all 3 slots are lit.
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    for (int i = 0; i < dotCount; i++) ...<Widget>[
                      if (i > 0) const SizedBox(width: 2.5),
                      Container(
                        height: 4,
                        width: 4,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: litDotColor,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );

    final Widget centered = SizedBox(
      height: kCalendarRowHeight,
      child: Center(child: content),
    );

    final VoidCallback? tap = onTap;
    if (tap == null) {
      return Semantics(key: cellKey, label: semanticsLabel, child: centered);
    }
    return Semantics(
      key: cellKey,
      button: true,
      selected: semanticsSelected,
      label: semanticsLabel,
      child: GestureDetector(
        onTap: tap,
        behavior: HitTestBehavior.opaque,
        child: centered,
      ),
    );
  }
}
