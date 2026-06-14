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
// Behaviour is IDENTICAL to the preview: tap a START day then an END day; the
// whole span (endpoints + in-between) renders as one continuous recessed
// neumorphic trough; endpoints are bold camel numbers (no ring); the camel ring
// marks "today"; past days (before [firstSelectableDay]) are faint and ignore
// taps; whole months stack in a single vertical scroll (no chevrons, no swipe);
// the bottom «Зберегти» CTA returns the range. Tapping a new start once a full
// range exists resets the selection.

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';

import '../domain/schedule_model.dart' show monthNominative;

/// Resolved Ukrainian copy for the picker chrome. The caller resolves these via
/// `AppLocalizations` so this surface imports no localization itself (mirrors
/// `showVelvetTimePicker`'s string-bundle pattern).
@immutable
class PeriodRangePickerStrings {
  const PeriodRangePickerStrings({
    required this.title,
    required this.emptyHint,
    required this.saveLabel,
    required this.backSemantic,
    required this.weekdayShort,
  });

  final String title;
  final String emptyHint;
  final String saveLabel;
  final String backSemantic;

  /// Seven Monday-leading short weekday labels (Пн … Нд).
  final List<String> weekdayShort;
}

/// Opens the range picker as a full-height modal sheet and resolves with the
/// chosen [DateTimeRange] (or `null` when dismissed without confirming).
///
/// [firstMonth] is the first month rendered at the top of the scroll list
/// (anchored to "today"); [firstSelectableDay] is the earliest tappable DAY
/// (typically "today") — earlier days render faint and ignore taps.
Future<DateTimeRange?> showPeriodRangePicker(
  BuildContext context, {
  required DateTime firstMonth,
  required DateTime firstSelectableDay,
  required PeriodRangePickerStrings strings,
  DateTimeRange? initialRange,
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
  });

  /// First selectable month (anchored to "today"); top of the scroll list.
  final DateTime firstMonth;

  /// First selectable DAY (inclusive) — typically "today". Earlier days render
  /// faint and ignore taps.
  final DateTime firstSelectableDay;

  /// Optional pre-selected range (e.g. a preset chip pre-filled it).
  final DateTimeRange? initialRange;

  final PeriodRangePickerStrings strings;

  @override
  State<PeriodRangePicker> createState() => _PeriodRangePickerState();
}

class _PeriodRangePickerState extends State<PeriodRangePicker> {
  /// How many consecutive months are rendered, starting at [_firstDay]'s month.
  /// Long enough to feel like "all months"; the far-future cap is enforced by
  /// the apply sheet on save, not in the scroll.
  static const int _monthCount = 24;

  late final DateTime _firstDay;
  late final DateTime _firstSelectable;
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
    _today = _firstSelectable;
    final DateTimeRange? init = widget.initialRange;
    if (init != null) {
      _start = _dateOnly(init.start);
      _end = _dateOnly(init.end);
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scrollToMonth(_start ?? _firstDay, animated: false);
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

  bool _isBefore(DateTime d) => d.isBefore(_firstSelectable);

  bool _isToday(DateTime d) => _sameDay(d, _today);

  DateTime _monthForIndex(int index) =>
      DateTime(_firstDay.year, _firstDay.month + index, 1);

  int _indexForMonth(DateTime date) {
    final int raw =
        (date.year - _firstDay.year) * 12 + (date.month - _firstDay.month);
    return raw.clamp(0, _monthCount - 1);
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
    if (_isBefore(d)) return;
    setState(() {
      if (_start == null || _hasFullRange) {
        _start = d;
        _end = null;
        return;
      }
      if (d.isBefore(_start!)) {
        _end = _start;
        _start = d;
      } else if (_sameDay(d, _start!)) {
        _end = d;
      } else {
        _end = d;
      }
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
              itemCount: _monthCount,
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
            style: VelvetText.heading().copyWith(fontSize: 20),
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
            Text(text, style: VelvetText.bodyStrong().copyWith(fontSize: 14)),
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
              child: Center(
                child: Text(
                  w,
                  style: VelvetText.label().copyWith(fontSize: 11),
                ),
              ),
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
              '${monthNominative(month.month)} ${month.year}',
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
          child: _weekRow(month, cellDays.sublist(i, i + 7)),
        ),
      );
    }
    return Column(children: rows);
  }

  Widget _weekRow(DateTime month, List<int?> weekDays) {
    final List<_DayInfo> infos = <_DayInfo>[
      for (final int? day in weekDays)
        day == null
            ? const _DayInfo.blank()
            : _classify(DateTime(month.year, month.month, day)),
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
      day: d.day,
      disabled: _isBefore(d),
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
    required this.day,
    required this.disabled,
    required this.isStart,
    required this.isEnd,
    required this.inBetween,
    required this.isToday,
    required this.onTap,
  }) : blank = false;

  const _DayInfo.blank()
    : day = 0,
      disabled = true,
      isStart = false,
      isEnd = false,
      inBetween = false,
      isToday = false,
      onTap = null,
      blank = true;

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

  @override
  Widget build(BuildContext context) {
    if (info.blank) {
      return const SizedBox(height: 44);
    }

    final bool endpoint = info.isStart || info.isEnd;
    final Color numberColor = endpoint
        ? BrandColors.accentDeep
        : info.disabled
        ? BrandColors.faint
        : info.inBetween
        ? BrandColors.accentDeep
        : BrandColors.text;

    final Widget content = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      height: 38,
      width: 38,
      alignment: Alignment.center,
      decoration: info.isToday
          ? BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: BrandColors.accent.withValues(alpha: 0.95),
                width: 1.8,
              ),
            )
          : null,
      child: Text(
        '${info.day}',
        style: VelvetText.bodyStrong().copyWith(
          fontSize: 15,
          color: numberColor,
          fontWeight: endpoint ? FontWeight.w700 : null,
        ),
      ),
    );

    final Widget centered = SizedBox(height: 44, child: Center(child: content));

    if (info.disabled) {
      return Semantics(label: '${info.day}', child: centered);
    }
    return Semantics(
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
