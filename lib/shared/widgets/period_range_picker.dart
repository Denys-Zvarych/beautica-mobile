// Phase 15.5 — PeriodRangePicker: the VelvetTouch scrolling-months range
// calendar (the soft-UI replacement for the native `showDateRangePicker`).
//
// Ported VERBATIM from the approved preview app at
// `docs/signup-designs/MasterSchedule/lib/screens/period_range_picker.dart`,
// adapted to the project's structure:
//   • preview `Scaffold` + raw Navigator push/pop  → a `showModalBottomSheet`
//     overlay (exempt from the go_router-only rule, like `showVelvetTimePicker`)
//     that returns the chosen `DateTimeRange`; the picker closes with the
//     go_router `context.pop(range)` extension (NEVER raw Navigator pop).
//   • preview `VelvetColors`/`VelvetText`/`Velvet*` tokens → `BrandColors` /
//     `VelvetText` / `velvet_geometry` project tokens.
//   • the preview's hard-coded Ukrainian header/summary copy → `AppLocalizations`
//     keys (the picker takes resolved strings via [PeriodRangePickerStrings] so
//     it imports no localization itself).
//
// ## Phase 7.7 — promoted from `features/schedule/presentation/` to `shared/`
//
// The master's «Мої записи» filter (Phase 7.7) needs the same calendar, and a
// second 600-line copy of it is not a design decision. Three things changed in
// the move, all additive — the schedule caller's behaviour is byte-identical:
//   • `monthNames` joins `weekdayShort` in [PeriodRangePickerStrings], so this
//     surface no longer imports `schedule/domain/schedule_model.dart` (a
//     `shared/` widget must not reach into a feature's `domain/`). The table
//     itself now lives in `shared/formatters/uk_calendar.dart` (moved there
//     from its former single-purpose home, retired in Phase 23.2).
//   • [monthCount] is a parameter rather than a private constant — bookings
//     reach into the PAST, so the booking caller renders months on both sides
//     of today while the schedule caller keeps its forward-only 24.
//   • [lastSelectableDay] and [maxSpanDays] are new, both optional and both
//     `null` (= unconstrained) for the schedule caller. See [maxSpanDays] for
//     why a picker that PREVENTS an over-long span beats a server 400.
//
// Behaviour is IDENTICAL to the preview: tap a START day then an END day; the
// whole span (endpoints + in-between) renders as one continuous recessed
// neumorphic trough; endpoints are bold camel numbers (no ring); the camel ring
// marks "today"; past days (before [firstSelectableDay]) are faint and ignore
// taps; whole months stack in a single vertical scroll (no chevrons, no swipe);
// the bottom «Зберегти» CTA returns the range. Tapping a new start once a full
// range exists resets the selection.
//
// ## Phase 7.13's single-day `mode` was REMOVED 2026-07-22 (mobile-qa MEDIUM)
//
// A `PeriodRangePickerMode` enum briefly gave this picker a second,
// tap-once-and-resolve behaviour for the booking filter's Дата section. That
// section was itself retired (Phase 7.13 → 7.16, in favour of the day rail
// and the month switcher) before the mode ever acquired a caller, leaving
// shipped, untested branches in `_onTapDay`, the CTA footer and the summary
// line for a behaviour nothing could reach. All of it is gone: this picker
// has exactly ONE behaviour again — tap a start, tap an end, confirm with
// «Зберегти». Do not reintroduce a mode enum without a live caller.

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';

/// Widget key for the picker's cell representing [day].
///
/// Keyed by the FULL date, never the day-of-month. The picker renders 14–36
/// consecutive months, so a bare day number repeats a dozen times and
/// `find.byKey` would silently resolve to whichever month came first — the
/// exact trap `bookings_day_rail.dart`'s `dayChipKey` documents, where a test
/// asserted against January while believing it had tapped July. Exposed so
/// tests address a cell through the same derivation the picker uses instead of
/// re-spelling the format and drifting from it.
Key periodDayCellKey(DateTime day) => Key(
  'period-range-day-'
  '${day.year.toString().padLeft(4, '0')}-'
  '${day.month.toString().padLeft(2, '0')}-'
  '${day.day.toString().padLeft(2, '0')}',
);

/// Default number of consecutive months rendered — long enough to feel like
/// "all months" for a forward-only picker. Callers that need the past (the
/// booking filter) pass their own [PeriodRangePicker.monthCount].
const int kPeriodRangePickerDefaultMonths = 24;

/// Resolved Ukrainian copy for the picker chrome. The caller resolves these via
/// `AppLocalizations` so this surface imports no localization itself (mirrors
/// `showVelvetTimePicker`'s string-bundle pattern).
@immutable
class PeriodRangePickerStrings {
  const PeriodRangePickerStrings({
    required this.title,
    required this.emptyHint,
    required this.backSemantic,
    required this.saveLabel,
    required this.weekdayShort,
    required this.monthNames,
  });

  final String title;
  final String emptyHint;

  /// The «Зберегти» CTA label. Always rendered — the picker has a single
  /// behaviour and always confirms through the CTA.
  final String saveLabel;
  final String backSemantic;

  /// Seven Monday-leading short weekday labels (Пн … Нд).
  final List<String> weekdayShort;

  /// Twelve nominative month names in calendar order (Січень … Грудень) —
  /// `monthNamesNominative` from `shared/formatters/uk_calendar.dart`. Passed
  /// in rather than imported so this widget stays free of any feature's copy
  /// tables, exactly like [weekdayShort].
  final List<String> monthNames;
}

/// Opens the range picker as a full-height modal sheet and resolves with the
/// chosen [DateTimeRange] (or `null` when dismissed without confirming).
///
/// [firstMonth] is the first month rendered at the top of the scroll list;
/// [monthCount] is how many consecutive months follow it. [firstSelectableDay]
/// is the earliest tappable DAY and [lastSelectableDay] the latest — days
/// outside the pair render faint and ignore taps. [maxSpanDays] caps how wide
/// a selection may get; see [PeriodRangePicker.maxSpanDays].
Future<DateTimeRange?> showPeriodRangePicker(
  BuildContext context, {
  required DateTime firstMonth,
  required DateTime firstSelectableDay,
  required PeriodRangePickerStrings strings,
  DateTimeRange? initialRange,
  DateTime? lastSelectableDay,
  DateTime? initialScrollMonth,
  int? maxSpanDays,
  int monthCount = kPeriodRangePickerDefaultMonths,
}) {
  return showModalBottomSheet<DateTimeRange>(
    context: context,
    isScrollControlled: true,
    backgroundColor: BrandColors.base,
    barrierColor: BrandColors.text.withValues(alpha: 0.35),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(VelvetRadii.card),
      ),
    ),
    builder: (BuildContext sheetContext) {
      // Near-full-height so the scrolling month list has room.
      final double maxHeight = MediaQuery.of(sheetContext).size.height * 0.92;
      return SizedBox(
        height: maxHeight,
        child: PeriodRangePicker(
          firstMonth: firstMonth,
          firstSelectableDay: firstSelectableDay,
          lastSelectableDay: lastSelectableDay,
          initialScrollMonth: initialScrollMonth,
          maxSpanDays: maxSpanDays,
          monthCount: monthCount,
          initialRange: initialRange,
          strings: strings,
        ),
      );
    },
  );
}

/// The scrolling-months range calendar body. Returns its [DateTimeRange] via the
/// go_router `context.pop` extension when «Зберегти» is tapped.
class PeriodRangePicker extends StatefulWidget {
  const PeriodRangePicker({
    super.key,
    required this.firstMonth,
    required this.firstSelectableDay,
    required this.strings,
    this.initialRange,
    this.lastSelectableDay,
    this.initialScrollMonth,
    this.maxSpanDays,
    this.monthCount = kPeriodRangePickerDefaultMonths,
    this.clock,
  }) : assert(
         maxSpanDays == null || maxSpanDays > 0,
         'maxSpanDays must be positive when set',
       ),
       assert(monthCount > 0, 'monthCount must be positive');

  /// First selectable month (anchored to "today"); top of the scroll list.
  final DateTime firstMonth;

  /// First selectable DAY (inclusive) — typically "today". Earlier days render
  /// faint and ignore taps.
  final DateTime firstSelectableDay;

  /// Last selectable DAY (inclusive), or `null` for no upper bound. Later days
  /// render faint and ignore taps.
  final DateTime? lastSelectableDay;

  /// Which month the list is scrolled to on open, when there is no
  /// [initialRange] to scroll to instead. Defaults to [firstMonth].
  ///
  /// Separate from [firstMonth] because the two answer different questions:
  /// [firstMonth] is where the reachable window BEGINS, this is where the
  /// user's attention should LAND. They coincide for a forward-only picker,
  /// which is why the picker had only the one value until Phase 7.7 pointed a
  /// caller's window backwards.
  ///
  /// For the booking filter [firstMonth] is `today − 180 days`, so scrolling to
  /// it opened the calendar roughly SIX MONTHS IN THE PAST — the master had to
  /// scroll a quarter of a year (~250 day cells) to reach today before they
  /// could pick anything. That is the same bug the master bookings rail had at
  /// its own origin, fixed for the rail in Phase 7.6 (`_centreRailOnOpen`); the
  /// picker did not get the equivalent at the time.
  ///
  /// Left `null` by the schedule caller, whose [firstMonth] IS the current
  /// month — so its open behaviour is unchanged.
  final DateTime? initialScrollMonth;

  /// Maximum width of a selection, in inclusive days, or `null` for no cap.
  ///
  /// Enforced by DISABLING the out-of-reach days the moment a start is chosen,
  /// rather than by rejecting the pair afterwards. The distinction matters:
  /// the backend's `from`/`to` window is capped (366 days on
  /// `GET /bookings/me`, backend Phase 26.2) and an over-wide pair is a **400**,
  /// so a picker that merely *reports* the violation has already let the user
  /// build something invalid and hand it to the server. Here the invalid tap
  /// target does not exist, which is why there is no error copy for this case
  /// anywhere in the app.
  final int? maxSpanDays;

  /// How many consecutive months are rendered, starting at [firstMonth].
  final int monthCount;

  /// Optional pre-selected range (e.g. a preset chip pre-filled it).
  final DateTimeRange? initialRange;

  final PeriodRangePickerStrings strings;

  /// Injectable LIVE "now" source for the camel "today" ring (backlog :226 —
  /// Kyiv-anchored, mirrors `DayHoursSheet.clock`). `null` → [DateTime.now]
  /// in production; tests pass a callback over a fixed/mutable clock for
  /// deterministic, device-zone-independent rendering.
  final DateTime Function()? clock;

  @override
  State<PeriodRangePicker> createState() => _PeriodRangePickerState();
}

class _PeriodRangePickerState extends State<PeriodRangePicker> {
  late final DateTime _firstDay;
  late final DateTime _initialScrollMonth;
  late final DateTime _firstSelectable;
  late final DateTime? _lastSelectable;
  late final DateTime _today;

  final ScrollController _scrollController = ScrollController();

  DateTime? _start;
  DateTime? _end;

  @override
  void initState() {
    super.initState();
    _firstDay = DateTime(widget.firstMonth.year, widget.firstMonth.month, 1);
    final DateTime fsd = widget.firstSelectableDay;
    _firstSelectable = DateTime(fsd.year, fsd.month, fsd.day);
    final DateTime? lsd = widget.lastSelectableDay;
    _lastSelectable = lsd == null
        ? null
        : DateTime(lsd.year, lsd.month, lsd.day);
    // The camel ring means TODAY, and for a forward-only picker
    // `firstSelectableDay` IS today — which is why it was read from there. The
    // booking filter's first selectable day is six months in the PAST, so
    // deriving "today" from it would ring an arbitrary day in January. Read
    // the clock instead; the schedule caller is unaffected because for it the
    // two values coincide.
    //
    // Kyiv-anchored (backlog :226): both callers' "today" concepts are Kyiv
    // civil days on the backend, so the ring must follow Kyiv's calendar, not
    // the device's — see `shared/time/kyiv_day.dart`.
    // instant-ok: feeds kyivDayOf below, not used as a bare device-day anchor
    _today = kyivDayOf(widget.clock?.call() ?? DateTime.now());
    final DateTime? ism = widget.initialScrollMonth;
    _initialScrollMonth = ism == null
        ? _firstDay
        : DateTime(ism.year, ism.month, 1);
    final DateTimeRange? init = widget.initialRange;
    if (init != null) {
      _start = _dateOnly(init.start);
      _end = _dateOnly(init.end);
    }
    _recomputeSpanBounds();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scrollToMonth(_start ?? _initialScrollMonth, animated: false);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  bool get _hasFullRange => _start != null && _end != null;

  /// `DD.MM` for the header summary (e.g. "01.06 – 31.08").
  static String _short(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';

  bool _sameDay(DateTime a, DateTime? b) =>
      b != null && a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isStart(DateTime d) => _sameDay(d, _start);
  bool _isEnd(DateTime d) => _sameDay(d, _end);

  bool _inBetween(DateTime d) {
    if (_start == null || _end == null) return false;
    return d.isAfter(_start!) && d.isBefore(_end!);
  }

  /// Whether [d] falls outside the picker's absolute selectable window.
  bool _outOfWindow(DateTime d) {
    if (d.isBefore(_firstSelectable)) return true;
    final DateTime? last = _lastSelectable;
    return last != null && d.isAfter(last);
  }

  /// Whether [d] is unreachable because picking it would exceed [maxSpanDays].
  ///
  /// Only bites in the half-open state — a start chosen, no end yet — which is
  /// exactly when the next tap decides the span. With no start, or with a full
  /// range already (where the next tap RESTARTS the selection at [d]), every
  /// in-window day stays reachable; both cases leave the bounds `null`.
  ///
  /// This is now two `DateTime` COMPARISONS against bounds computed once per
  /// selection change ([_recomputeSpanBounds]), not an arithmetic span
  /// measurement per cell. The old form allocated two `DateTime.utc` values and
  /// a `Duration` for every one of the ~90 cells on screen, on every rebuild —
  /// and it did so *only* while a half-open range existed, i.e. during exactly
  /// the mid-selection rebuild storm the cap is being consulted for (perf P6).
  bool _outOfSpan(DateTime d) {
    final DateTime? min = _spanMinDay;
    final DateTime? max = _spanMaxDay;
    if (min == null || max == null) return false;
    return d.isBefore(min) || d.isAfter(max);
  }

  bool _isDisabled(DateTime d) => _outOfWindow(d) || _outOfSpan(d);

  /// Inclusive bounds of what the cap still allows, or `null`/`null` when the
  /// cap does not currently bite. Recomputed on every selection change.
  DateTime? _spanMinDay;
  DateTime? _spanMaxDay;

  /// Derives [_spanMinDay]/[_spanMaxDay] from the current start.
  ///
  /// `cap - 1` because the cap counts INCLUSIVELY: with a 366-day cap, the
  /// start itself is day 1 and the furthest legal end is 365 days away.
  ///
  /// Pure CALENDAR arithmetic (`DateTime(y, m, d ± n)`), which is DST-immune by
  /// construction — it never measures a duration, so there is no 23/25-hour day
  /// for integer division to truncate. The previous implementation had to
  /// project both days onto UTC to dodge exactly that off-by-one (a 366-day
  /// span across the March transition measured 365 and slipped past the cap);
  /// with bounds there is nothing to measure. Pinned by
  /// `period_range_picker_span_cap_test.dart`'s DST-straddling case.
  void _recomputeSpanBounds() {
    final int? cap = widget.maxSpanDays;
    final DateTime? start = _start;
    if (cap == null || start == null || _hasFullRange) {
      _spanMinDay = null;
      _spanMaxDay = null;
      return;
    }
    _spanMinDay = DateTime(start.year, start.month, start.day - (cap - 1));
    _spanMaxDay = DateTime(start.year, start.month, start.day + (cap - 1));
  }

  bool _isToday(DateTime d) => _sameDay(d, _today);

  DateTime _monthForIndex(int index) =>
      DateTime(_firstDay.year, _firstDay.month + index, 1);

  int _indexForMonth(DateTime date) {
    final int raw =
        (date.year - _firstDay.year) * 12 + (date.month - _firstDay.month);
    return raw.clamp(0, widget.monthCount - 1);
  }

  void _scrollToMonth(DateTime date, {bool animated = true}) {
    if (!_scrollController.hasClients) return;
    final double target = _estimatedOffsetForIndex(_indexForMonth(date));
    final double max = _scrollController.position.maxScrollExtent;
    final double clamped = target.clamp(0.0, max);
    if (animated) {
      _scrollController.animateTo(
        clamped,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeInOut,
      );
    } else {
      _scrollController.jumpTo(clamped);
    }
  }

  double _estimatedOffsetForIndex(int index) {
    double offset = 0;
    for (int i = 0; i < index; i++) {
      offset += _estimatedMonthHeight(_monthForIndex(i));
    }
    return offset;
  }

  double _estimatedMonthHeight(DateTime month) {
    final DateTime first = DateTime(month.year, month.month, 1);
    final int daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final int leadingBlanks = first.weekday - 1;
    final int totalCells = leadingBlanks + daysInMonth;
    final int weekRows = (totalCells / 7).ceil();
    const double header = 30;
    const double weekday = 22;
    const double rowHeight = 50;
    const double sectionGap = VelvetSpacing.lg;
    return header + weekday + weekRows * rowHeight + sectionGap;
  }

  void _onTapDay(DateTime d) {
    if (_isDisabled(d)) return;
    setState(() {
      if (_start == null || _hasFullRange) {
        _start = d;
        _end = null;
      } else if (d.isBefore(_start!)) {
        _end = _start;
        _start = d;
      } else {
        _end = d;
      }
      // The cap's reach is a function of `_start` and `_hasFullRange`, so it is
      // re-derived exactly where those change — never during `build`, which
      // would couple correctness to whether the list's `itemBuilder` happens to
      // run before or after the state field was written.
      _recomputeSpanBounds();
    });
  }

  void _save() {
    if (!_hasFullRange) return;
    context.pop<DateTimeRange>(DateTimeRange(start: _start!, end: _end!));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              VelvetSpacing.md,
              VelvetSpacing.md,
              VelvetSpacing.md,
              0,
            ),
            child: _header(),
          ),
          const SizedBox(height: VelvetSpacing.md),
          _rangeSummary(),
          const SizedBox(height: VelvetSpacing.md),
          _weekdayHeaderBar(),
          const SizedBox(height: VelvetSpacing.sm),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                VelvetSpacing.md,
                0,
                VelvetSpacing.md,
                VelvetSpacing.xl,
              ),
              itemCount: widget.monthCount,
              itemBuilder: (BuildContext context, int index) =>
                  _monthSection(_monthForIndex(index)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              VelvetSpacing.md,
              VelvetSpacing.sm,
              VelvetSpacing.md,
              VelvetSpacing.md,
            ),
            child: Opacity(
              opacity: _hasFullRange ? 1 : 0.55,
              child: IgnorePointer(
                ignoring: !_hasFullRange,
                child: NeumorphicButton(
                  key: const Key('btn-range-picker-save'),
                  label: widget.strings.saveLabel,
                  icon: Icons.check_rounded,
                  onPressed: _save,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return SizedBox(
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: NeumorphicIconButton(
              key: const Key('btn-range-picker-back'),
              icon: Icons.arrow_back_ios_new_rounded,
              semanticLabel: widget.strings.backSemantic,
              onTap: () => context.pop(),
            ),
          ),
          Text(
            widget.strings.title,
            textAlign: TextAlign.center,
            style: VelvetText.heading20,
          ),
        ],
      ),
    );
  }

  Widget _rangeSummary() {
    final String text = _start == null
        ? widget.strings.emptyHint
        : _end == null
        ? '${_short(_start!)} – …'
        : '${_short(_start!)} – ${_short(_end!)}';
    return Center(
      child: NeumorphicCard(
        padding: const EdgeInsets.symmetric(
          horizontal: VelvetSpacing.md,
          vertical: VelvetSpacing.sm,
        ),
        shadows: VelvetShadows.extrudedSmall,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.date_range_rounded,
              size: 18,
              color: BrandColors.accentDeep,
            ),
            const SizedBox(width: VelvetSpacing.sm),
            Text(text, style: VelvetText.bodyStrong14),
          ],
        ),
      ),
    );
  }

  Widget _weekdayHeaderBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.md + 2),
      child: Row(
        children: <Widget>[
          for (final String w in widget.strings.weekdayShort)
            Expanded(
              child: Center(child: Text(w, style: VelvetText.label11)),
            ),
        ],
      ),
    );
  }

  Widget _monthSection(DateTime month) {
    return Padding(
      padding: const EdgeInsets.only(bottom: VelvetSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              VelvetSpacing.xs,
              VelvetSpacing.sm,
              0,
              VelvetSpacing.sm,
            ),
            child: Text(
              '${widget.strings.monthNames[month.month - 1]} ${month.year}',
              style: VelvetText.subheading(),
            ),
          ),
          _monthGrid(month),
        ],
      ),
    );
  }

  Widget _monthGrid(DateTime month) {
    final DateTime first = DateTime(month.year, month.month, 1);
    final int daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final int leadingBlanks = first.weekday - 1;

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
          // `start` offset rather than `cellDays.sublist(i, i + 7)` — the slice
          // allocated a throwaway 7-element list per week row, per month, per
          // rebuild (perf P7). The row reads the same seven entries by index.
          child: _weekRow(month, cellDays, i),
        ),
      );
    }
    return Column(children: rows);
  }

  Widget _weekRow(DateTime month, List<int?> cellDays, int start) {
    final List<_DayInfo> infos = <_DayInfo>[
      for (int c = 0; c < 7; c++)
        if (cellDays[start + c] case final int day)
          _classify(DateTime(month.year, month.month, day))
        else
          const _DayInfo.blank(),
    ];

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
    return _DayInfo(
      cellKey: periodDayCellKey(d),
      day: d.day,
      disabled: _isDisabled(d),
      isStart: _isStart(d),
      isEnd: _isEnd(d),
      inBetween: _inBetween(d),
      isToday: _isToday(d),
      onTap: () => _onTapDay(d),
    );
  }
}

/// A contiguous run of selected columns within a single week row (inclusive).
class _SelRun {
  const _SelRun(this.start, this.end);
  final int start;
  final int end;
}

/// Per-column classification for one day in a week row.
class _DayInfo {
  const _DayInfo({
    required this.cellKey,
    required this.day,
    required this.disabled,
    required this.isStart,
    required this.isEnd,
    required this.inBetween,
    required this.isToday,
    required this.onTap,
  }) : blank = false;

  const _DayInfo.blank()
    : cellKey = null,
      day = 0,
      disabled = true,
      isStart = false,
      isEnd = false,
      inBetween = false,
      isToday = false,
      onTap = null,
      blank = true;

  /// `null` for a leading/trailing blank cell — a blank is not a day and must
  /// not be addressable.
  final Key? cellKey;

  final int day;
  final bool disabled;
  final bool isStart;
  final bool isEnd;
  final bool inBetween;
  final bool isToday;
  final bool blank;
  final VoidCallback? onTap;

  bool get selected => isStart || isEnd || inBetween;
}

/// One day cell layered over the week-row inset trough. Endpoints are bold
/// camel numbers (no ring) so the selected span reads as one recessed band; the
/// camel ring is reserved for "today" (drawn whether or not today is selected).
class _DayCell extends StatelessWidget {
  const _DayCell({required this.info});

  final _DayInfo info;

  /// The four reachable number styles, resolved once at class-load instead of
  /// via a `copyWith` per cell per rebuild (~90 throwaway `TextStyle`s a frame
  /// during a scroll — perf P5).
  ///
  /// Precedence matches the original conditional exactly: endpoint wins over
  /// disabled, which wins over in-between. A non-endpoint passes
  /// `fontWeight: null` to `copyWith`, which PRESERVES `bodyStrong15`'s own
  /// weight rather than clearing it — so these are not "w700 vs w400", they are
  /// "w700 vs whatever the token says".
  static final TextStyle _endpointStyle = VelvetText.bodyStrong15.copyWith(
    color: BrandColors.accentDeep,
    fontWeight: FontWeight.w700,
  );
  static final TextStyle _disabledStyle = VelvetText.bodyStrong15.copyWith(
    color: BrandColors.faint,
  );
  static final TextStyle _inBetweenStyle = VelvetText.bodyStrong15.copyWith(
    color: BrandColors.accentDeep,
  );
  static final TextStyle _normalStyle = VelvetText.bodyStrong15.copyWith(
    color: BrandColors.text,
  );

  /// The "today" ring — hoisted for the same reason as the styles: it depends
  /// on nothing per-cell, so it was a `BoxDecoration` + `Border` + `Color`
  /// rebuilt for every today-cell render. `static final` rather than `const`
  /// only because the camel is alpha-adjusted (`withValues` is not const).
  static final BoxDecoration _todayRing = BoxDecoration(
    shape: BoxShape.circle,
    border: Border.all(
      color: BrandColors.accent.withValues(alpha: 0.95),
      width: 1.8,
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (info.blank) {
      return const SizedBox(height: 44);
    }

    final bool endpoint = info.isStart || info.isEnd;
    final TextStyle numberStyle = endpoint
        ? _endpointStyle
        : info.disabled
        ? _disabledStyle
        : info.inBetween
        ? _inBetweenStyle
        : _normalStyle;

    // A plain `Container`, not an `AnimatedContainer` (perf P2).
    //
    // `decoration` was the only animated property and it is driven solely by
    // `info.isToday`, which is CONSTANT for a cell's whole lifetime — a given
    // column in a given week row of a given month is always the same date. So
    // every one of these was a `StatefulWidget` with an `AnimationController`
    // and a `Ticker` registered and scheduled to animate a value that never
    // changes: ~40 per visible month, ~90 live during a scroll. Renders
    // identically at rest, which is what the golden suite pins.
    final Widget content = Container(
      height: 38,
      width: 38,
      alignment: Alignment.center,
      decoration: info.isToday ? _todayRing : null,
      child: Text('${info.day}', style: numberStyle),
    );

    final Widget centered = SizedBox(height: 44, child: Center(child: content));

    if (info.disabled) {
      return Semantics(
        key: info.cellKey,
        label: '${info.day}',
        child: centered,
      );
    }
    return Semantics(
      key: info.cellKey,
      button: true,
      selected: endpoint,
      label: '${info.day}',
      child: GestureDetector(
        onTap: info.onTap,
        behavior: HitTestBehavior.opaque,
        child: centered,
      ),
    );
  }
}
