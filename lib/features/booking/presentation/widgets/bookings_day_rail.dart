// Phase 7.6 — the «Мої записи» day rail: a horizontally scrolling past↔future
// strip of day chips, led by a calendar escape hatch and an «Всі» chip.
//
// Transcribed from `docs/signup-designs/SalonManagementDesign/lib/widgets/
// bookings_toolbar.dart` (`_DayRail`, `_DayChip`, `_AllChip`,
// `_CalendarButton`). The visual language is the design's verbatim: no chip
// background, selection carried by text colour alone, today underlined when
// unselected, a camel dot under any day that has bookings.
//
// ## ⚠ CALENDAR arithmetic, never `Duration(days: n)` — this WILL bite
//
// Every date in this file is derived with `DateTime(y, m, d + n)`, which
// normalises an out-of-range day component against the CALENDAR and always
// lands on local midnight. The design uses `firstDay.add(Duration(days: i))`,
// and that is the one line of it deliberately NOT transcribed.
//
// `DateTime.add` adds an absolute 24-hour block. Across a Europe/Kyiv DST
// transition — the last Sunday of March and of October — a chain of them
// lands on 01:00 or 23:00 instead of 00:00. `bookedDaysProvider` returns a
// `Set<DateTime>` of local midnights, so `contains()` on a 23:00 value MISSES:
// the dot silently vanishes for a day, twice a year, with no error and no
// crash. The same skew would then flow into the query bounds via `toApiDate`,
// filtering the list to the wrong day.
//
// `bookings_day_rail_test.dart` pins both transitions.
//
// ## Lazily built — 361 chips is not a `ListView(children: [...])`
//
// The rail spans today ± 180 days = 361 day cells plus 2 lead items. A
// `ListView.builder` with a fixed `itemExtent` builds only the visible window
// AND gives the screen's centring math an O(1) offset to jump to. Eagerly
// building 363 chips is exactly the jank `mobile-perf` flags.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/api_date.dart';

/// Width of one rail cell, including its trailing gap — the design's
/// `_railExtent`. The screen's centring math multiplies by this, so it must
/// stay in sync with the `ListView.builder`'s `itemExtent`.
const double kRailItemExtent = 62;

/// Number of lead items before the first day cell: `[calendar]` then `[Всі]`.
///
/// Load-bearing: the screen's scroll-centring math offsets a day index by this
/// to reach its item index (the design's `final int itemIndex = 2 + dayIndex`).
/// Changing it without changing that math silently centres the rail two cells
/// off.
const int kRailLeadItems = 2;

/// Height of the rail strip. See [BookingsDayRail.build] for why this is 78
/// rather than the design's 70.
const double _railHeight = 78;

/// Vertical gap between a day chip's weekday caption and its day number.
///
/// The design uses 16; 10 here for the same reason the strip is 78 tall — the
/// app's real type is taller than the preview's, and the chip must not
/// overflow. Kept generous enough that the weekday still reads as a caption
/// ABOVE the number rather than crowding it.
const double _dayChipCaptionGap = 10;

/// Returns the day [offset] days after [from], by CALENDAR arithmetic.
///
/// The DST-safe replacement for `from.add(Duration(days: offset))` — see the
/// file header for what breaks otherwise. Exposed (not private) so the screen
/// and the tests derive rail dates through the exact same function the rail
/// itself uses.
DateTime railDayAt(DateTime from, int offset) =>
    DateTime(from.year, from.month, from.day + offset);

/// Memoised weekday abbreviations, keyed by the [AppLocalizations] instance
/// they came from (perf P4).
///
/// The seven captions are fixed for a locale, but they were rebuilt into a
/// fresh `List<String>` on every rail `build()`. `AppLocalizations` is a
/// per-locale singleton, so identity is a sound cache key AND a correct
/// invalidation signal: switching locale hands `build` a different instance
/// and the list is recomputed. One list is retained, not one per locale ever
/// seen — a new key replaces the entry rather than growing a map.
List<String>? _weekdayShortCache;
AppLocalizations? _weekdayShortCacheKey;

List<String> _weekdayShorts(AppLocalizations l10n) {
  final List<String>? cached = _weekdayShortCache;
  if (cached != null && identical(_weekdayShortCacheKey, l10n)) return cached;
  final List<String> built = List<String>.unmodifiable(<String>[
    l10n.weekdayShortMon,
    l10n.weekdayShortTue,
    l10n.weekdayShortWed,
    l10n.weekdayShortThu,
    l10n.weekdayShortFri,
    l10n.weekdayShortSat,
    l10n.weekdayShortSun,
  ]);
  _weekdayShortCache = built;
  _weekdayShortCacheKey = l10n;
  return built;
}

/// Widget key for the day cell representing [day].
///
/// Keyed by the FULL date rather than the day-of-month: the rail spans 361
/// days, so a bare day number repeats up to a dozen times and `find.byKey`
/// would silently resolve to whichever month came first. Exposed so tests
/// address a cell through the same derivation the rail uses, instead of
/// re-spelling the key format and drifting from it.
Key dayChipKey(DateTime day) =>
    Key('master-bookings-day-chip-${toApiDate(day)}');

/// Widget key for the has-bookings dot on [day]. Present only when the day
/// carries a booking, so `findsNothing` is a meaningful assertion.
Key dayDotKey(DateTime day) => Key('master-bookings-day-dot-${toApiDate(day)}');

/// The horizontally scrolling day strip.
class BookingsDayRail extends StatelessWidget {
  const BookingsDayRail({
    super.key,
    required this.controller,
    required this.firstDay,
    required this.dayCount,
    required this.today,
    required this.selectedDay,
    required this.bookedDays,
    required this.calendarActive,
    required this.onOpenCalendar,
    required this.onSelectAll,
    required this.onSelectDay,
  });

  final ScrollController controller;

  /// The rail's first day — `today - kBookedDaysSpanDays`, date-only.
  final DateTime firstDay;

  /// Inclusive day count — `2 * kBookedDaysSpanDays + 1`.
  final int dayCount;

  final DateTime today;

  /// The single selected day, or `null` for «Всі» / range mode. Per the
  /// design, a range SUPERSEDES the rail's single-day selection, so the screen
  /// passes `null` here whenever a range is active.
  final DateTime? selectedDay;

  /// Date-only days carrying at least one booking — `bookedDaysProvider`.
  ///
  /// A `Set` because this is a membership test run for every visible cell on
  /// every scroll frame. **Filter-independent by design**: the dots describe
  /// where the master's work is, not what the current filter matches, so they
  /// must not evaporate as the user narrows. See `booked_days_notifier.dart`.
  final Set<DateTime> bookedDays;

  /// Whether a multi-day range is active — marks the calendar button.
  final bool calendarActive;

  final VoidCallback onOpenCalendar;
  final VoidCallback onSelectAll;
  final ValueChanged<DateTime> onSelectDay;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<String> weekdayShort = _weekdayShorts(l10n);

    return SizedBox(
      // The design's strip is 70dp. It is 78 here because the app's
      // `VelvetText` styles carry line-height multipliers the preview's raw
      // `TextStyle`s did not, so the same three-element column measures ~8dp
      // taller and overflowed the design's height by 17dp under the Phase 17.2
      // overflow guard. The chip's INTERNAL rhythm is unchanged; only the
      // container grew to fit the real type.
      height: _railHeight,
      child: ListView.builder(
        key: const Key('master-bookings-day-rail'),
        controller: controller,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
        itemExtent: kRailItemExtent,
        itemCount: kRailLeadItems + dayCount,
        itemBuilder: (BuildContext context, int index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(right: 10),
              child: _CalendarButton(
                active: calendarActive,
                onTap: onOpenCalendar,
                semanticLabel: l10n.masterBookingsCalendarSemantics,
              ),
            );
          }
          if (index == 1) {
            return Padding(
              padding: const EdgeInsets.only(right: 10),
              child: _AllChip(
                // «Всі» is selected only when nothing narrows the dates at
                // all — neither a single day nor a range.
                selected: selectedDay == null && !calendarActive,
                onTap: onSelectAll,
                label: l10n.masterBookingsAllDays,
                semanticLabel: l10n.masterBookingsAllDaysSemantics,
              ),
            );
          }
          // CALENDAR arithmetic — see the file header.
          final DateTime d = railDayAt(firstDay, index - kRailLeadItems);
          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: _DayChip(
              // The FULL date, not the day-of-month. The rail spans 361 days,
              // so a day number repeats up to 12 times — a `…-chip-20` key
              // would match January's 20th as readily as July's, and
              // `find.byKey` silently takes the first. That is not merely a
              // test-ergonomics problem: it made a day-selection test assert
              // against 2026-01-20 while believing it had tapped 2026-07-20.
              date: d,
              weekday: weekdayShort[d.weekday - 1],
              selected: selectedDay == d,
              isToday: d == today,
              hasBookings: bookedDays.contains(d),
              onTap: () => onSelectDay(d),
              semanticLabel: l10n.masterBookingsDaySemantics(
                weekdayShort[d.weekday - 1],
                d.day,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One day cell. No background decoration — selection is text colour only;
/// today (unselected) gets an accent underline; a camel dot marks bookings.
class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.date,
    required this.weekday,
    required this.selected,
    required this.isToday,
    required this.hasBookings,
    required this.onTap,
    required this.semanticLabel,
  });

  final DateTime date;
  final String weekday;
  final bool selected;
  final bool isToday;
  final bool hasBookings;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final Color weekdayColor = selected
        ? BrandColors.accentDeep
        : BrandColors.textSecondary;
    final Color numberColor = selected ? BrandColors.accent : BrandColors.text;

    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      child: GestureDetector(
        key: dayChipKey(date),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 44,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                weekday,
                style: VelvetText.railWeekday.copyWith(color: weekdayColor),
              ),
              const SizedBox(height: _dayChipCaptionGap),
              Text(
                '${date.day}',
                style: VelvetText.railDayNumber.copyWith(
                  color: numberColor,
                  fontWeight: (isToday && !selected)
                      ? FontWeight.w800
                      : FontWeight.w700,
                  decoration: (isToday && !selected)
                      ? TextDecoration.underline
                      : TextDecoration.none,
                  decorationColor: BrandColors.accent,
                  decorationThickness: 1.5,
                ),
              ),
              const SizedBox(height: 4),
              // Always laid out — transparent when there is no booking — so a
              // dot appearing never reflows the column.
              Container(
                key: hasBookings ? dayDotKey(date) : null,
                height: 5,
                width: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hasBookings ? BrandColors.accent : Colors.transparent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The «Всі» control — clears the date narrowing entirely.
class _AllChip extends StatelessWidget {
  const _AllChip({
    required this.selected,
    required this.onTap,
    required this.label,
    required this.semanticLabel,
  });

  final bool selected;
  final VoidCallback onTap;
  final String label;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      child: GestureDetector(
        key: const Key('master-bookings-all-chip'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 44,
          child: Center(
            child: Text(
              label,
              style: VelvetText.railAllChip.copyWith(
                fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                color: selected ? BrandColors.accentDeep : BrandColors.text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The calendar escape hatch. Phase 7.7 owns the picker it opens; this phase
/// owns the button and the `active` state it reflects.
class _CalendarButton extends StatelessWidget {
  const _CalendarButton({
    required this.active,
    required this.onTap,
    required this.semanticLabel,
  });

  final bool active;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        key: const Key('master-bookings-calendar-button'),
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 52,
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: BrandColors.base,
                    borderRadius: BorderRadius.circular(VelvetRadii.field + 2),
                    // `borderedButton`, NOT `extrudedButton`: the extruded
                    // pair's offset near-white light shadow pokes past the
                    // rounded corner under Impeller and renders as a white
                    // wedge (resolved 34db74f). The hairline border below is
                    // what defines the shape instead.
                    boxShadow: VelvetShadows.borderedButton,
                    border: Border.all(
                      color: active
                          ? BrandColors.accent
                          : BrandColors.accent.withValues(alpha: 0.18),
                      width: active ? 1.5 : 1,
                    ),
                  ),
                  child: Icon(
                    Icons.calendar_month_rounded,
                    color: active
                        ? BrandColors.accentDeep
                        : BrandColors.textSecondary,
                    size: 22,
                  ),
                ),
              ),
              if (active)
                const Positioned(top: 8, right: 8, child: _AccentDot()),
            ],
          ),
        ),
      ),
    );
  }
}

/// The recurring 8dp camel indicator dot.
class _AccentDot extends StatelessWidget {
  const _AccentDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 8,
      width: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: BrandColors.accent,
        border: Border.all(color: BrandColors.base, width: 1.5),
      ),
    );
  }
}
