// Phase 7.6 — the «Мої записи» day rail: a horizontally scrolling past↔future
// strip of day chips.
//
// Phase 7.11 (D3/R6) — the «Всі» chip is RETIRED. `BookingsDayQuery` (Phase
// 7.9) has no all-days/range mode any more — the screen is always scoped to
// exactly one Kyiv calendar day — so a chip that cleared the date narrowing
// entirely no longer has a query it could resolve to. [selectedDay] is now
// non-nullable for the same reason: there is no "nothing selected" state to
// represent.
//
// Phase 7.16 — the calendar escape hatch (`_CalendarButton`, opening
// `showBookingsDayPicker`) is RETIRED. Day selection is by scrolling the rail
// alone; the month switcher's prev/next and «Сьогодні»
// (`bookings_discovery_view.dart`'s `_MonthSwitcher`, added `bc08986`) already
// cover the long-distance jumps the button used to exist for, which made a
// second jump affordance redundant. `BookingsDayRail` no longer takes a
// `calendarActive`/`onOpenCalendar` pair, and the rail is a bare
// `ListView.builder` again — no pinned sibling.
//
// Transcribed from `docs/signup-designs/SalonManagementDesign/lib/widgets/
// bookings_toolbar.dart` (`_DayRail`, `_DayChip`; the design's `_AllChip` is
// NOT transcribed post-7.11, and `_CalendarButton` is not transcribed
// post-7.16). The visual language is the design's verbatim: no chip
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
// The rail spans today ± 180 days = 361 day cells. A `ListView.builder` with
// a fixed `itemExtent` builds only the visible window AND gives the screen's
// centring math an O(1) offset to jump to. Eagerly building 361 chips is
// exactly the jank `mobile-perf` flags.
//
// A day's offset from [firstDay] IS its `ListView.builder` item index — the
// list has never carried a lead item since Phase 7.11 retired the «Всі»
// chip, and Phase 7.16 removing the pinned calendar button (which lived
// OUTSIDE the list, as a `Row` sibling — see this file's history) changes
// nothing about that indexing.

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
        // Symmetric horizontal inset — restored now that the calendar button
        // (which used to own the leading `VelvetSpacing.lg` on its own
        // `Padding`, post-Phase-7.16-retirement) is gone. Without this the
        // first chip sits flush against the screen edge.
        padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
        itemExtent: kRailItemExtent,
        itemCount: dayCount,
        itemBuilder: (BuildContext context, int index) {
          // CALENDAR arithmetic — see the file header. No lead-item offset:
          // the list's own index IS the day offset now.
          final DateTime d = railDayAt(firstDay, index);
          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: _DayChip(
              // The FULL date, not the day-of-month. The rail spans 361
              // days, so a day number repeats up to 12 times — a
              // `…-chip-20` key would match January's 20th as readily as
              // July's, and `find.byKey` silently takes the first. That is
              // not merely a test-ergonomics problem: it made a
              // day-selection test assert against 2026-01-20 while believing
              // it had tapped 2026-07-20.
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

  /// Memoised weekday-caption styles, keyed by the resolved colour (mobile-perf
  /// LOW, 2026-07-22).
  ///
  /// [build] used to allocate two `TextStyle`s per chip on EVERY rail rebuild
  /// — and the rail rebuilds on every day selection, every `bookedDays`
  /// resolution and every scroll-driven `ListView` recycle. The permutation
  /// set is CLOSED and tiny: three weekday colours (`accentDeep` selected /
  /// `muted` past / `textSecondary` ordinary) and three number colours
  /// (`accent` / `muted` / `text`), so a keyed memo reaches its ceiling
  /// immediately and stops. Same pattern (and same reasoning) as
  /// `master_booking_card.dart`'s `TimelineStatusDot._decorationsByAccent`.
  ///
  /// Keyed by the RESOLVED colour rather than by the `selected`/`muted`
  /// booleans so it cannot drift from the resolution below if a token is
  /// remapped.
  static final Map<Color, TextStyle> _weekdayStyles = <Color, TextStyle>{};

  /// The day-number style memo. Keyed by `(colour, isToday && !selected)` —
  /// the today-but-unselected flag drives BOTH the weight step (w800 vs w700)
  /// and the accent underline, so it is part of the identity of the style,
  /// not an overlay on it. Six entries maximum (3 colours × 2 states).
  static final Map<(Color, bool), TextStyle> _numberStyles =
      <(Color, bool), TextStyle>{};

  /// The bound on both memos — 3 weekday colours, and 3 number colours × 2
  /// today-states. See [_weekdayStyleFor]'s assert.
  static const int _kWeekdayStyleCount = 3;
  static const int _kNumberStyleCount = 6;

  static TextStyle _weekdayStyleFor(Color color) {
    assert(
      _weekdayStyles.containsKey(color) ||
          _weekdayStyles.length < _kWeekdayStyleCount,
      '_DayChip._weekdayStyles grew past $_kWeekdayStyleCount entries — the '
      'weekday colour set is closed, so this means either a new state shipped '
      '(raise the bound) or a colour is being rebuilt per-instance, which '
      'would make this memo an unbounded leak instead of the fixed table it '
      'is meant to be.',
    );
    return _weekdayStyles.putIfAbsent(
      color,
      () => VelvetText.railWeekday.copyWith(color: color),
    );
  }

  static TextStyle _numberStyleFor(Color color, {required bool todayMark}) {
    assert(
      _numberStyles.containsKey((color, todayMark)) ||
          _numberStyles.length < _kNumberStyleCount,
      '_DayChip._numberStyles grew past $_kNumberStyleCount entries — see '
      '_weekdayStyleFor for why that bound is structural.',
    );
    return _numberStyles.putIfAbsent(
      (color, todayMark),
      () => VelvetText.railDayNumber.copyWith(
        color: color,
        fontWeight: todayMark ? FontWeight.w800 : FontWeight.w700,
        decoration: todayMark ? TextDecoration.underline : TextDecoration.none,
        decorationColor: BrandColors.accent,
        decorationThickness: 1.5,
      ),
    );
  }

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
              Text(weekday, style: _weekdayStyleFor(weekdayColor)),
              const SizedBox(height: _dayChipCaptionGap),
              Text(
                '${date.day}',
                style: _numberStyleFor(
                  numberColor,
                  todayMark: isToday && !selected,
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
