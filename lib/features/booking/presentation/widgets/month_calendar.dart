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

/// The pinned Monday-first weekday header bar, shown once above the single
/// month grid.
class CalendarWeekdayBar extends StatelessWidget {
  const CalendarWeekdayBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Matches `MonthCalendar.build()`'s own horizontal inset
      // (`VelvetSpacing.lg`) exactly, so the 7 weekday labels line up with
      // the 7 day-grid columns beneath them. Was `VelvetSpacing.md + 2`
      // (18dp/side, copied from `period_range_picker.dart`'s
      // `_weekdayHeaderBar()`, whose sibling grid uses `VelvetSpacing.md` —
      // a different, smaller inset than this widget's own grid) — that
      // mismatched `MonthCalendar`'s `VelvetSpacing.lg` (24dp/side) inset by
      // 6dp/side, visibly drifting the header off the grid columns.
      padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
      child: Row(
        children: <Widget>[
          for (int day = 1; day <= 7; day++)
            Expanded(
              child: Center(
                child: Text(weekdayAbbrev(day), style: VelvetText.label11),
              ),
            ),
        ],
      ),
    );
  }
}

/// A SINGLE-MONTH calendar. Only [visibleMonth] is rendered; stepping months
/// swaps the grid in place (no scrolling). Days for which [isAvailable]
/// returns true read camel and are tappable; others are faint and ignore
/// taps. Tapping an available day invokes [onSelectDay].
class MonthCalendar extends StatelessWidget {
  const MonthCalendar({
    super.key,
    required this.visibleMonth,
    required this.today,
    required this.selected,
    required this.isAvailable,
    required this.onSelectDay,
    required this.onPrevMonth,
    required this.onNextMonth,
  });

  /// The single month currently rendered (day-of-month is ignored).
  final DateTime visibleMonth;

  /// Date-only "today" marker — gets the camel ring.
  final DateTime today;

  /// Currently selected date (date-only), or `null`.
  final DateTime? selected;

  /// Whether [day] is tappable / renders camel.
  final bool Function(DateTime day) isAvailable;

  final ValueChanged<DateTime> onSelectDay;

  /// Page to the previous month; `null` disables the ‹ chevron.
  final VoidCallback? onPrevMonth;

  /// Page to the next month; `null` disables the › chevron.
  final VoidCallback? onNextMonth;

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
          _MonthHeader(
            month: visibleMonth,
            onPrev: onPrevMonth,
            onNext: onNextMonth,
          ),
          const SizedBox(height: VelvetSpacing.sm),
          _MonthGrid(
            month: visibleMonth,
            today: today,
            selected: selected,
            isAvailable: isAvailable,
            onSelectDay: onSelectDay,
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
  });

  final DateTime month;
  final DateTime today;
  final DateTime? selected;
  final bool Function(DateTime day) isAvailable;
  final ValueChanged<DateTime> onSelectDay;

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
    while (cellDays.length % 7 != 0) {
      cellDays.add(null);
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

    // Contiguous runs of selected columns (single-day → a run of length 1;
    // kept generic so the recessed-trough geometry matches the master range
    // picker pixel-for-pixel).
    final List<_SelRun> runs = <_SelRun>[];
    int? runStart;
    for (int c = 0; c < 7; c++) {
      final bool sel = infos[c].selected;
      if (sel && runStart == null) {
        runStart = c;
      } else if (!sel && runStart != null) {
        runs.add(_SelRun(runStart, c - 1));
        runStart = null;
      }
    }
    if (runStart != null) {
      runs.add(_SelRun(runStart, 6));
    }

    return SizedBox(
      height: 44,
      child: Stack(
        children: <Widget>[
          for (final _SelRun run in runs)
            Positioned.fill(
              child: Row(
                children: <Widget>[
                  for (int c = 0; c < 7; c++)
                    Expanded(
                      child: c < run.start || c > run.end
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
              for (final _DayInfo info in infos)
                Expanded(child: _DayCell(info: info)),
            ],
          ),
        ],
      ),
    );
  }

  _DayInfo _classify(DateTime d) {
    final bool available = isAvailable(d);
    final bool isSel = selected != null && _sameDay(d, selected!);
    return _DayInfo(
      day: d.day,
      available: available,
      selected: isSel,
      isToday: _sameDay(d, today),
      onTap: available ? () => onSelectDay(d) : null,
    );
  }
}

class _SelRun {
  const _SelRun(this.start, this.end);
  final int start;
  final int end;
}

class _DayInfo {
  const _DayInfo({
    required this.day,
    required this.available,
    required this.selected,
    required this.isToday,
    required this.onTap,
  }) : blank = false;

  const _DayInfo.blank()
    : day = 0,
      available = false,
      selected = false,
      isToday = false,
      onTap = null,
      blank = true;

  final int day;
  final bool available;
  final bool selected;
  final bool isToday;
  final bool blank;
  final VoidCallback? onTap;
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.info});

  final _DayInfo info;

  @override
  Widget build(BuildContext context) {
    if (info.blank) {
      return const SizedBox(height: 44);
    }

    final l10n = AppLocalizations.of(context);
    final Color numberColor = (info.selected || info.available)
        ? BrandColors.accentDeep
        : BrandColors.faint;

    final Color ringColor = info.available || info.selected
        ? BrandColors.accent.withValues(alpha: 0.95)
        : BrandColors.faint.withValues(alpha: 0.8);

    final Widget content = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      height: 38,
      width: 38,
      alignment: Alignment.center,
      decoration: info.isToday
          ? BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: ringColor, width: 1.8),
            )
          : null,
      child: Text(
        '${info.day}',
        style: VelvetText.bodyStrong15.copyWith(
          color: numberColor,
          fontWeight: info.selected ? FontWeight.w700 : FontWeight.w600,
        ),
      ),
    );

    final Widget centered = SizedBox(height: 44, child: Center(child: content));
    final Key cellKey = Key('booking-calendar-day-${info.day}');

    final String stateLabel = info.selected
        ? l10n.bookingSelectedState
        : info.available
        ? l10n.bookingDayAvailableState
        : l10n.bookingDayUnavailableState;

    if (info.onTap == null) {
      return Semantics(
        key: cellKey,
        label: '${info.day}, $stateLabel',
        child: centered,
      );
    }
    return Semantics(
      key: cellKey,
      button: true,
      selected: info.selected,
      label: '${info.day}, $stateLabel',
      child: GestureDetector(
        onTap: info.onTap,
        behavior: HitTestBehavior.opaque,
        child: centered,
      ),
    );
  }
}
