// Phase 7.6 — the «Мої записи» day rail: a horizontally scrolling past↔future
// strip of day chips, led by a calendar escape hatch.
//
// Phase 7.11 (D3/R6) — the «Всі» chip is RETIRED. `BookingsDayQuery` (Phase
// 7.9) has no all-days/range mode any more — the screen is always scoped to
// exactly one Kyiv calendar day — so a chip that cleared the date narrowing
// entirely no longer has a query it could resolve to. [selectedDay] is now
// non-nullable for the same reason: there is no "nothing selected" state to
// represent. The calendar button survives (jump to an arbitrary day, still
// useful past the ±180-day rail span) but its picked range collapses to a
// single day at the call site — see `bookings_discovery_view.dart`.
//
// Transcribed from `docs/signup-designs/SalonManagementDesign/lib/widgets/
// bookings_toolbar.dart` (`_DayRail`, `_DayChip`, `_CalendarButton`; the
// design's `_AllChip` is NOT transcribed post-7.11). The visual language is
// the design's verbatim: no chip background, selection carried by text
// colour alone, today underlined when unselected, a camel dot under any day
// that has bookings.
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
// The rail spans today ± 180 days = 361 day cells plus 1 lead item. A
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

/// Number of lead items before the first day cell: `[calendar]` alone.
///
/// Load-bearing: the screen's scroll-centring math offsets a day index by this
/// to reach its item index (the design's `final int itemIndex = 2 + dayIndex`
/// for `[calendar][Всі]`; with «Всі» retired (Phase 7.11) this is `1 +
/// dayIndex`). Changing it without changing that math silently centres the
/// rail off by however many lead items were added or removed.
const int kRailLeadItems = 1;

/// Height of the rail strip — the design's own 70dp.
///
/// A previous pass bumped this to 78 (and shrank [_dayChipCaptionGap] to 10)
/// because the app's `VelvetText` styles carried line-height multipliers the
/// preview's raw `TextStyle`s did not, overflowing the design's 70dp by 17dp.
/// The 2026-07-19 pass that shrank `VelvetText.railDayNumber` to 12.6sp (from
/// 18sp) freed exactly the vertical room that 8dp bump existed to cover, so
/// both are restored to the design's own values here.
const double _railHeight = 70;

/// Vertical gap between a day chip's weekday caption and its day number —
/// the design's own 16dp, restored alongside [_railHeight]; see its doc.
const double _dayChipCaptionGap = 16;

/// Returns the day [offset] days after [from], by CALENDAR arithmetic.
///
/// The DST-safe replacement for `from.add(Duration(days: offset))` — see the
/// file header for what breaks otherwise. Exposed (not private) so the screen
/// and the tests derive rail dates through the exact same function the rail
/// itself uses.
DateTime railDayAt(DateTime from, int offset) =>
    DateTime(from.year, from.month, from.day + offset);

/// The number of CALENDAR days between date-only [from] and [to] (positive
/// when [to] is after [from]), independent of any DST transition crossed in
/// between.
///
/// `to.difference(from).inDays` is NOT safe for this and must not be used in
/// its place: `DateTime.difference` subtracts the two values' absolute
/// instants, so a spring-forward transition crossed between [from] and [to]
/// shortens the elapsed wall-clock span by exactly the skipped hour (e.g.
/// 180 calendar days becomes `4319:00:00`, 179 days 23 hours), and
/// `Duration.inDays` truncates rather than rounds — silently returning ONE
/// DAY FEWER than the calendar actually spans. On a device in an
/// Europe/Kyiv-observing zone this is not a rare edge case: the ±180-day
/// rail span crosses at least one of the two yearly transitions (last Sunday
/// of March / October) for the large majority of the year.
///
/// This function counts by first re-anchoring both dates in UTC, which never
/// observes DST — every calendar day is uniformly 24 hours there, so the
/// subtraction is always exact.
///
/// Exposed (not private) so both `_centreRailOn` and its tests derive a day
/// count through the exact same function, mirroring [railDayAt]'s pattern.
int calendarDayCount(DateTime from, DateTime to) {
  final DateTime fromUtc = DateTime.utc(from.year, from.month, from.day);
  final DateTime toUtc = DateTime.utc(to.year, to.month, to.day);
  return toUtc.difference(fromUtc).inDays;
}

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
    required this.onSelectDay,
  });

  final ScrollController controller;

  /// The rail's first day — `today - kBookedDaysSpanDays`, date-only.
  final DateTime firstDay;

  /// Inclusive day count — `2 * kBookedDaysSpanDays + 1`.
  final int dayCount;

  final DateTime today;

  /// The single selected day. Always set — Phase 7.11 retired the «Всі» /
  /// null-day state; the screen is always scoped to exactly one Kyiv calendar
  /// day, including on first open (`dateOnly(toBeauticaTime(DateTime.now()))`
  /// — see `bookings_discovery_view.dart`).
  final DateTime selectedDay;

  /// Date-only days carrying at least one booking — `bookedDaysProvider`.
  ///
  /// A `Set` because this is a membership test run for every visible cell on
  /// every scroll frame. **Filter-independent by design**: the dots describe
  /// where the master's work is, not what the current filter matches, so they
  /// must not evaporate as the user narrows. See `booked_days_notifier.dart`.
  final Set<DateTime> bookedDays;

  /// Marks the calendar button as active. Phase 7.11 retired the range mode
  /// that used to drive this (`BookingsDayQuery` has no range); Phase 7.13
  /// repointed it at a real, reachable signal instead — the live screen
  /// passes `selectedDay != today`, so the button lights up whenever the
  /// master has jumped away from today (via a rail chip or the calendar jump)
  /// and goes quiet again the moment today is reselected. Kept as a
  /// widget-level flag (rather than hard-coded here) so the button's active
  /// visual stays independently testable.
  final bool calendarActive;

  final VoidCallback onOpenCalendar;
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
              // `d.isBefore(today)` is false for `d == today` by
              // construction — today is never "past" — but [_DayChip]
              // restates that precedence explicitly rather than leaning on
              // this call site alone. See its doc.
              isPast: d.isBefore(today),
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
///
/// A day strictly before [isPast]'s referent (today) reads muted — the
/// weekday caption and day number desaturate to [BrandColors.muted], the
/// established "receded" token in this palette (never a cold grey — see the
/// design system doc). Precedence, made explicit rather than left to fall
/// out of evaluation order:
///   * SELECTED beats past. A selected past day (the master browsing
///     history) must still read as selected — otherwise there is no visual
///     confirmation of what is currently open.
///   * TODAY is never past. [isPast] is `false` for `date == today` by the
///     caller's construction (`d.isBefore(today)`), so this falls out
///     naturally, but it is the reason [isToday]'s bold/underline treatment
///     never has to defend against [isPast] — the two are mutually
///     exclusive by definition, not by a runtime check here.
///
/// The has-bookings dot deliberately does NOT mute for past days — it stays
/// full [BrandColors.accent] regardless. The dot's whole job is to make the
/// rail scannable for "where is the work", and that is exactly as true
/// scrolling back through history as it is scrolling forward; muting it
/// would fight the ability to spot a past booked day at a glance.
class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.date,
    required this.weekday,
    required this.selected,
    required this.isToday,
    required this.isPast,
    required this.hasBookings,
    required this.onTap,
    required this.semanticLabel,
  });

  final DateTime date;
  final String weekday;
  final bool selected;
  final bool isToday;

  /// Whether [date] is strictly before today. Never `true` for today itself
  /// — see the class doc's precedence note.
  final bool isPast;
  final bool hasBookings;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    // Selection outranks pastness — see the class doc.
    final bool muted = isPast && !selected;
    final Color weekdayColor = selected
        ? BrandColors.accentDeep
        : muted
        ? BrandColors.muted
        : BrandColors.textSecondary;
    final Color numberColor = selected
        ? BrandColors.accent
        : muted
        ? BrandColors.muted
        : BrandColors.text;

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
              // dot appearing never reflows the column. Deliberately NOT
              // gated on `muted`/`isPast` — see the class doc: the dot stays
              // full accent on a past day so history remains scannable.
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
