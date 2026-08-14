// Phase 14.1 — MonthCalendar: the single-month date picker (Step 2a).
//
// Transcribed verbatim (tokens, layout, shadows) from
// `docs/signup-designs/BookingSlotPicker/lib/widgets/month_calendar.dart`,
// styled like the master schedule's period-range picker: one month grid on
// the bare taupe base, a month+year header flanked by ‹/› paging chevrons, a
// pinned weekday bar, a recessed trough for the chosen day, and a camel ring
// for "today".
//
// DEVIATION from the preview's placeholder data: the preview additionally
// greys out Sundays and two hard-coded "fully booked" days to demonstrate the
// unavailable-day face — [MonthCalendar] itself never fabricates that; it
// stays generic (its [isAvailable] callback can express any policy) and
// defers entirely to the caller.
//
// Phase 14.14 UPDATE (day-availability gating, formerly a documented gap
// here): the backend now exposes a real per-day signal —
// `GET /masters/{masterId}/working-days?from=&to=`, wrapped by
// `SlotRepository.getWorkingDays` and resolved by the family-keyed
// `workingDaysProvider` (`application/working_days_notifier.dart`, keyed by
// `WorkingDaysQuery` = masterId + bounded date range). The caller
// (`SlotDateScreen`) derives its [isAvailable] callback from that provider's
// resolved data for the currently-visible month, re-deriving it whenever the
// visible month changes: a day is available iff it is not in the past AND
// the fetched working-days set marks it `working: true`. A day absent from
// the resolved set (should not normally happen — the query always spans the
// full visible month) is treated conservatively as NOT working rather than
// defaulting to tappable. Fully-booked-but-working days are a SEPARATE
// signal (Phase 14.15's zero-slots empty state on the time screen) — a
// `working: true` day can still resolve to zero bookable slots once chosen,
// and still renders as tappable here; that case is handled one screen later,
// not by greying out the day cell.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/uk_calendar.dart';
import 'package:beautica_mobile/shared/widgets/calendar_grid.dart';

// Re-exported so every existing `import '.../month_calendar.dart'` call site
// that references `CalendarWeekdayBar` keeps working unchanged — the widget
// itself now lives in `shared/widgets/calendar_grid.dart` (mobile-backlog
// D5): a `shared/` primitive other calendar surfaces (`PeriodRangePicker`)
// also compose, which a booking-feature `presentation/` file could never be,
// per the cross-feature import rule.
export 'package:beautica_mobile/shared/widgets/calendar_grid.dart'
    show CalendarWeekdayBar;

/// Height of [CalendarWeekdayBar] when composed inside [MonthCalendar]
/// (see [MonthCalendar.composeWeekdayBar]).
const double kMonthCalendarWeekdayBarHeight = 20;

/// [_MonthHeader]'s fixed height — matches `_MonthChevron`'s own 40×40 face,
/// which is the row's cross-axis size.
const double kMonthCalendarHeaderHeight = 40;

/// Week rows the grid renders when [MonthCalendar.sixWeekRows] is `true`
/// (see that field's doc for why a FIXED row count matters there).
const int kMonthCalendarSixRows = 6;

/// One week row's total height: the 44dp cell band ([CalendarDayCell]) plus
/// 3dp of vertical padding on each side ([_MonthGrid.build]).
const double kMonthCalendarRowHeight = 50;

/// [MonthCalendar]'s total laid-out height in the exact configuration
/// `BookingsMonthCalendarPanel` composes it with — [MonthCalendar
/// .composeWeekdayBar] and [MonthCalendar.sixWeekRows] both `true`,
/// [MonthCalendar.showHeader] `false` — i.e. the drag-interpolated expanded
/// resting height that panel needs: top pad ([VelvetSpacing.sm]) + weekday bar
/// ([kMonthCalendarWeekdayBarHeight]) + gap ([VelvetSpacing.xs]) + six rows
/// ([kMonthCalendarRowHeight] each). Meaningless for the default
/// `composeWeekdayBar: false` / `showHeader: true` configuration both
/// pre-existing callers use.
///
/// This USED to include [kMonthCalendarHeaderHeight] + a [VelvetSpacing.sm]
/// gap (380dp total). The bookings panel no longer renders a per-month header
/// at all — the month+year label now lives permanently in the panel's own
/// `_TopRow` and months change by horizontal paging, so the grid's own header
/// (and its ‹ › chevrons) would have been a second, redundant readout of the
/// same value. Dropping it reclaims 48dp of expanded height, which is 48dp
/// more short-device headroom (see
/// `bookings_month_calendar_short_device_test.dart`'s probe table).
const double kMonthCalendarExpandedHeight =
    VelvetSpacing.sm +
    kMonthCalendarWeekdayBarHeight +
    VelvetSpacing.xs +
    kMonthCalendarSixRows * kMonthCalendarRowHeight;

// `CalendarWeekdayBar` used to be defined here. It now lives in
// `shared/widgets/calendar_grid.dart` (mobile-backlog D5) and is re-exported
// above for source compatibility. It renders NO horizontal padding of its
// own any more (mobile-backlog D4): every caller — including this file's own
// `composeWeekdayBar: true` path below — wraps it in the SAME horizontal
// inset its sibling grid uses. Composing it inside this widget's own outer
// `Padding` (below) used to DOUBLE that inset, because the bar carried an
// identical `VelvetSpacing.lg` self-pad on top of it — visibly drifting the
// composed header a half-column off the grid it describes (worst on the
// `BookingsMonthCalendarPanel` expanded surface, where `composeWeekdayBar` is
// `true`). See `calendar_grid.dart`'s file header for the full fix.

/// A SINGLE-MONTH calendar. Only [visibleMonth] is rendered; this widget
/// never scrolls or animates between months itself — a caller either swaps
/// [visibleMonth] in place (the ‹ › chevrons, [showHeader] `true`) or mounts
/// one instance per month inside its own pager ([showHeader] `false`, what
/// `BookingsMonthCalendarPanel` does). Days for which [isAvailable] returns
/// true read camel and are tappable; others are faint and ignore taps.
/// Tapping an available day invokes [onSelectDay].
class MonthCalendar extends StatelessWidget {
  const MonthCalendar({
    super.key,
    required this.visibleMonth,
    required this.today,
    required this.selected,
    required this.isAvailable,
    required this.onSelectDay,
    this.onPrevMonth,
    this.onNextMonth,
    this.composeWeekdayBar = false,
    this.sixWeekRows = false,
    this.showHeader = true,
    this.bookingCount,
    this.allowTapOnUnavailable = false,
    this.stateLabelResolver,
  }) : assert(
         showHeader || (onPrevMonth == null && onNextMonth == null),
         'onPrevMonth/onNextMonth are the ‹ › chevrons _MonthHeader renders — '
         'passing either with showHeader: false silently drops it, which is '
         'always a wiring mistake rather than an intent.',
       );

  /// The single month currently rendered (day-of-month is ignored).
  final DateTime visibleMonth;

  /// Date-only "today" marker — gets the camel ring.
  final DateTime today;

  /// Currently selected date (date-only), or `null`.
  final DateTime? selected;

  /// Whether [day] is tappable / renders camel.
  final bool Function(DateTime day) isAvailable;

  final ValueChanged<DateTime> onSelectDay;

  /// Page to the previous month; `null` disables the ‹ chevron. Meaningless
  /// (and asserted absent) when [showHeader] is `false`.
  final VoidCallback? onPrevMonth;

  /// Page to the next month; `null` disables the › chevron. Meaningless (and
  /// asserted absent) when [showHeader] is `false`.
  final VoidCallback? onNextMonth;

  // ═══════════════════════════════════════════════════════════════════════
  // Варіант D adaptations (`docs/signup-designs/MasterBookingsCalendar`) —
  // all OPT-IN, all default to the widget's ORIGINAL behaviour. Set only by
  // `BookingsMonthCalendarPanel`; [SlotDateScreen] and `MasterSchedulePage`
  // (the two pre-existing callers) never pass any of these and render
  // byte-identically to before this section existed.
  // ═══════════════════════════════════════════════════════════════════════

  /// Composes [CalendarWeekdayBar] between the header and the grid instead
  /// of leaving it to the caller. `false` (the default) renders exactly as
  /// before — [SlotDateScreen] and `MasterSchedulePage` both pin
  /// `CalendarWeekdayBar` as their OWN sibling above [MonthCalendar] and
  /// must keep doing so. `true` is for a caller that reveals the whole
  /// header+bar+grid block behind a single clip and needs the labels
  /// travelling with the grid they describe.
  final bool composeWeekdayBar;

  /// Pads the grid to a constant [kMonthCalendarSixRows] week rows instead
  /// of the natural 4–6 the month needs. `false` (the default) keeps the
  /// existing variable row count. `true` is for a caller that interpolates
  /// this widget's height under a drag gesture — a variable row count would
  /// move the gesture's own destination mid-swipe.
  final bool sixWeekRows;

  /// Renders [_MonthHeader] — the month+year caption between the ‹ › paging
  /// chevrons — above the grid. `true` (the default) is the ORIGINAL
  /// behaviour and is what [SlotDateScreen] and `MasterSchedulePage` both
  /// rely on: the chevrons are their ONLY month-navigation affordance.
  ///
  /// `false` is for a caller that already renders the month+year ITSELF, in a
  /// position that does not move between states, and navigates months by a
  /// gesture rather than by buttons — today only
  /// `BookingsMonthCalendarPanel`, whose `_TopRow` label is permanent and
  /// whose month pager is a horizontal `PageView` over this widget. Keeping
  /// the header there would put the same month name on screen twice and add
  /// two buttons the locked design explicitly forbids.
  ///
  /// Changes this widget's laid-out HEIGHT — see
  /// [kMonthCalendarExpandedHeight], which is derived for the `false`
  /// configuration.
  final bool showHeader;

  /// Bookings-count callback driving up to [kCalendarMaxDensityDots]
  /// density dots under each day number, dimmed on an unavailable day.
  /// `null` (the default) renders no dots — the original appearance, and
  /// the space they would occupy is not even laid out (byte-identical cell
  /// height to before this parameter existed).
  final int Function(DateTime day)? bookingCount;

  /// ⚠ The one BEHAVIOURAL adaptation. `false` (the default) keeps
  /// [isAvailable]'s original meaning: `false` ⇒ the cell renders faint AND
  /// refuses taps — load-bearing for [SlotDateScreen], where "unavailable"
  /// means "cannot be booked".
  ///
  /// `true` repurposes [isAvailable] as a PURELY VISUAL faint/camel switch —
  /// every day stays tappable regardless of what it returns. Set `true`
  /// only by a caller passing "not in the past" as [isAvailable] purely for
  /// the past-day treatment, where refusing the tap would disagree with a
  /// sibling control (e.g. a day rail) that already allows opening any past
  /// day. Do NOT set this `true` for a caller where [isAvailable] still
  /// means "bookable".
  final bool allowTapOnUnavailable;

  /// Overrides the accessibility state word appended to a day cell's label.
  /// `null` (the default) keeps the SLOT-PICKER wording
  /// (`bookingDayAvailableState`/`bookingDayUnavailableState`) — "available"
  /// there means "has bookable slots". A caller whose [isAvailable] means
  /// something else (e.g. "not in the past") must supply its own resolver —
  /// reusing the slot-picker's copy would misinform a screen-reader user.
  final String Function({required bool available, required bool selected})?
  stateLabelResolver;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        VelvetSpacing.lg,
        VelvetSpacing.sm,
        VelvetSpacing.lg,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (showHeader) ...<Widget>[
            _MonthHeader(
              month: visibleMonth,
              onPrev: onPrevMonth,
              onNext: onNextMonth,
            ),
            const SizedBox(height: VelvetSpacing.sm),
          ],
          if (composeWeekdayBar) ...<Widget>[
            const SizedBox(
              height: kMonthCalendarWeekdayBarHeight,
              child: CalendarWeekdayBar(),
            ),
            const SizedBox(height: VelvetSpacing.xs),
          ],
          _MonthGrid(
            month: visibleMonth,
            today: today,
            selected: selected,
            isAvailable: isAvailable,
            onSelectDay: onSelectDay,
            sixWeekRows: sixWeekRows,
            bookingCount: bookingCount,
            allowTapOnUnavailable: allowTapOnUnavailable,
            stateLabelResolver: stateLabelResolver,
          ),
        ],
      ),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.month,
    required this.onPrev,
    required this.onNext,
  });

  final DateTime month;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: <Widget>[
        _MonthChevron(
          key: const Key('booking-calendar-prev-month'),
          icon: Icons.chevron_left_rounded,
          semanticLabel: l10n.bookingCalendarPrevMonth,
          onTap: onPrev,
        ),
        Expanded(
          child: Center(
            child: Text(
              '${monthNominative(month.month)} ${month.year}',
              style: VelvetText.subheading(),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        _MonthChevron(
          key: const Key('booking-calendar-next-month'),
          icon: Icons.chevron_right_rounded,
          semanticLabel: l10n.bookingCalendarNextMonth,
          onTap: onNext,
        ),
      ],
    );
  }
}

class _MonthChevron extends StatefulWidget {
  const _MonthChevron({
    super.key,
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onTap;

  @override
  State<_MonthChevron> createState() => _MonthChevronState();
}

class _MonthChevronState extends State<_MonthChevron> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onTap != null;
    final Color glyph = enabled ? BrandColors.accentDeep : BrandColors.faint;

    final Widget face = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: 40,
      width: 40,
      decoration: BoxDecoration(
        color: BrandColors.base,
        borderRadius: BorderRadius.circular(VelvetRadii.field),
        boxShadow: (!enabled || _pressed) ? null : VelvetShadows.extrudedSmall,
      ),
      child: _pressed
          ? NeumorphicInset(
              radius: VelvetRadii.field,
              child: Center(child: Icon(widget.icon, color: glyph, size: 24)),
            )
          : Icon(widget.icon, color: glyph, size: 24),
    );

    if (!enabled) {
      return Semantics(
        button: true,
        enabled: false,
        label: widget.semanticLabel,
        child: Opacity(opacity: 0.55, child: face),
      );
    }

    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap!();
        },
        child: face,
      ),
    );
  }
}

/// One month: a 7-column day grid (no header — the header lives above it).
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.today,
    required this.selected,
    required this.isAvailable,
    required this.onSelectDay,
    required this.sixWeekRows,
    required this.bookingCount,
    required this.allowTapOnUnavailable,
    required this.stateLabelResolver,
  });

  final DateTime month;
  final DateTime today;
  final DateTime? selected;
  final bool Function(DateTime day) isAvailable;
  final ValueChanged<DateTime> onSelectDay;
  final bool sixWeekRows;
  final int Function(DateTime day)? bookingCount;
  final bool allowTapOnUnavailable;
  final String Function({required bool available, required bool selected})?
  stateLabelResolver;

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final DateTime first = DateTime(month.year, month.month, 1);
    final int daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final int leadingBlanks = first.weekday - 1; // Monday-first.

    final List<int?> cellDays = <int?>[
      for (int i = 0; i < leadingBlanks; i++) null,
      for (int day = 1; day <= daysInMonth; day++) day,
    ];
    if (sixWeekRows) {
      // ADAPTATION — pad to a constant six rows; see
      // [MonthCalendar.sixWeekRows].
      while (cellDays.length < kMonthCalendarSixRows * 7) {
        cellDays.add(null);
      }
    } else {
      while (cellDays.length % 7 != 0) {
        cellDays.add(null);
      }
    }

    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < cellDays.length; i += 7) {
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: _weekRow(context, cellDays.sublist(i, i + 7)),
        ),
      );
    }

    return Column(children: rows);
  }

  Widget _weekRow(BuildContext context, List<int?> weekDays) {
    final List<_DayInfo> infos = <_DayInfo>[
      for (final int? day in weekDays)
        day == null
            ? const _DayInfo.blank()
            : _classify(DateTime(month.year, month.month, day)),
    ];

    return CalendarWeekRow(
      // Single-day selection is still a run of length 1 — kept generic so
      // the recessed-trough geometry matches the range picker pixel-for-pixel
      // (shared [CalendarWeekRow]/[computeSelectedRuns], mobile-backlog D5).
      selectedRuns: computeSelectedRuns(<bool>[
        for (final _DayInfo info in infos) info.selected,
      ]),
      cells: <Widget>[
        for (final _DayInfo info in infos)
          _dayCell(context, info, stateLabelResolver: stateLabelResolver),
      ],
    );
  }

  _DayInfo _classify(DateTime d) {
    final bool available = isAvailable(d);
    final bool isSel = selected != null && _sameDay(d, selected!);
    final int? count = bookingCount?.call(d);
    return _DayInfo(
      day: d.day,
      available: available,
      selected: isSel,
      isToday: _sameDay(d, today),
      // mobile-backlog D3 — see `calendar_grid.dart`'s file header for the
      // precedence this feeds into (`_dayCell` below): selected beats
      // unavailable beats weekend beats normal/available.
      isWeekend: isWeekendWeekday(d.weekday),
      bookings: count ?? 0,
      // ADAPTATION — density-dot space is laid out ONLY when the caller
      // supplied [bookingCount]; see [MonthCalendar.bookingCount] and
      // [_dayCell]. `null` (both pre-existing callers) renders the cell
      // exactly as before this adaptation existed.
      showDots: bookingCount != null,
      // ADAPTATION — see [MonthCalendar.allowTapOnUnavailable].
      onTap: (available || allowTapOnUnavailable) ? () => onSelectDay(d) : null,
    );
  }

  /// Resolves one [_DayInfo] into a shared [CalendarDayCell] — the color/
  /// weight/label decisions [MonthCalendar] owns, painted by the primitive
  /// `shared/widgets/calendar_grid.dart` also hands to [PeriodRangePicker]
  /// (mobile-backlog D5).
  Widget _dayCell(
    BuildContext context,
    _DayInfo info, {
    required String Function({required bool available, required bool selected})?
    stateLabelResolver,
  }) {
    if (info.blank) {
      return const CalendarDayCell(
        day: null,
        cellKey: null,
        // Unused — [CalendarDayCell.build] returns before reading
        // [CalendarDayCell.numberStyle] for a `day: null` cell. A trivial
        // const value only so this constructor call stays `const`
        // (mobile-perf, calendar-consolidation audit).
        numberStyle: TextStyle(),
        isToday: false,
        hasSelectionTrough: false,
        semanticsSelected: false,
        ringColor: BrandColors.faint,
        semanticsLabel: '',
        onTap: null,
      );
    }

    final l10n = AppLocalizations.of(context);

    // mobile-backlog D3 — precedence encoded once, see `calendar_grid.dart`'s
    // file header: SELECTED beats unavailable (existing `faint`/`textSecondary`
    // meaning — see below) beats WEEKEND (`weekendMuted` cue) beats
    // normal/available.
    final Color numberColor;
    if (info.selected) {
      numberColor = BrandColors.accentDeep;
    } else if (!info.available) {
      // mobile-security LOW (calendar-consolidation audit): whether
      // `BrandColors.faint` (1.66:1 on `BrandColors.base`) is legal here
      // turns on WCAG 2.1 SC 1.4.3's "inactive user interface component"
      // exemption, which in turn depends on whether THIS cell is actually
      // tappable — `info.onTap` (resolved by `_classify` from `available ||
      // allowTapOnUnavailable`) is the one source of truth for that, so it
      // is read directly rather than re-deriving the same condition.
      // `SlotDateScreen`/`MasterSchedulePage` (both leave
      // `allowTapOnUnavailable` at its `false` default) never reach the
      // `onTap != null` branch, so a genuinely non-interactive unavailable
      // day is exempt and keeps `faint`, unchanged. `BookingsMonthCalendarPanel`
      // sets `allowTapOnUnavailable: true` so its past days stay tappable
      // (viewing history) — that makes them an ACTIVE component, so the
      // exemption does NOT apply there: those read `textSecondary` (5.03:1,
      // WCAG AA) instead.
      numberColor = info.onTap != null
          ? BrandColors.textSecondary
          : BrandColors.faint;
    } else if (info.isWeekend) {
      numberColor = BrandColors.weekendMuted;
    } else {
      numberColor = BrandColors.accentDeep;
    }

    final TextStyle numberStyle = VelvetText.bodyStrong15.copyWith(
      color: numberColor,
      fontWeight: info.selected ? FontWeight.w700 : FontWeight.w600,
    );

    final Color ringColor = info.available || info.selected
        ? BrandColors.accent.withValues(alpha: 0.95)
        : BrandColors.faint.withValues(alpha: 0.8);

    // ADAPTATION — density dots, in the day rail's own visual language: up
    // to [kCalendarMaxDensityDots], capped, dimmed on an unavailable day so
    // history stays scannable without competing with the work ahead. Laid
    // out ONLY when [info.showDots] — otherwise this cell is the exact
    // 38×38 badge it always was.
    final int dots = info.bookings > kCalendarMaxDensityDots
        ? kCalendarMaxDensityDots
        : info.bookings;

    final Key cellKey = Key('booking-calendar-day-${info.day}');

    // ADAPTATION — see [MonthCalendar.stateLabelResolver]'s doc for why the
    // slot-picker's own "available"/"unavailable" wording cannot be reused
    // by a caller whose [MonthCalendar.isAvailable] means something else.
    final String stateLabel = stateLabelResolver != null
        ? stateLabelResolver(available: info.available, selected: info.selected)
        : info.selected
        ? l10n.bookingSelectedState
        : info.available
        ? l10n.bookingDayAvailableState
        : l10n.bookingDayUnavailableState;
    // A resolver may legitimately have nothing to add (e.g. a normal,
    // unselected, non-past day) — the built-in three-way resolution never
    // does, so this only ever branches for a caller that opted in.
    final String semanticsLabel = stateLabel.isEmpty
        ? '${info.day}'
        : '${info.day}, $stateLabel';

    return CalendarDayCell(
      day: info.day,
      cellKey: cellKey,
      numberStyle: numberStyle,
      isToday: info.isToday,
      hasSelectionTrough: info.selected,
      semanticsSelected: info.selected,
      ringColor: ringColor,
      semanticsLabel: semanticsLabel,
      onTap: info.onTap,
      dots: info.showDots ? dots : null,
      litDotColor: info.available || info.selected
          ? BrandColors.accent
          : BrandColors.accent.withValues(alpha: 0.45),
    );
  }
}

class _DayInfo {
  const _DayInfo({
    required this.day,
    required this.available,
    required this.selected,
    required this.isToday,
    required this.isWeekend,
    required this.bookings,
    required this.showDots,
    required this.onTap,
  }) : blank = false;

  const _DayInfo.blank()
    : day = 0,
      available = false,
      selected = false,
      isToday = false,
      isWeekend = false,
      bookings = 0,
      showDots = false,
      onTap = null,
      blank = true;

  final int day;
  final bool available;
  final bool selected;
  final bool isToday;

  /// Saturday/Sunday — see [isWeekendWeekday]. Mobile-backlog D3.
  final bool isWeekend;

  /// Bookings on this day — capped at [kCalendarMaxDensityDots] dots. Meaningless
  /// when [showDots] is `false`.
  final int bookings;

  /// Whether the cell lays out the density-dot row at all — see
  /// [MonthCalendar.bookingCount]'s doc.
  final bool showDots;
  final bool blank;
  final VoidCallback? onTap;
}
