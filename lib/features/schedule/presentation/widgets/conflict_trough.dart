/// The day-off/pause booking-conflict dialog's signature element: **one
/// recessed trough holding the bookings that are about to be taken away.**
///
/// Ported verbatim from the approved preview
/// `docs/signup-designs/DayOffConflictDialog/lib/widgets/conflict_list.dart`.
///
/// ## Why a trough and not a stack of cards
///
/// Everywhere else in Beautica a booking is a *raised* neumorphic card — a
/// live object you can pick up and tap into. Here the bookings are not
/// objects any more; they are the contents of a decision. So the whole list
/// is sunk into a single inset well, rows separated by hairlines, and no row
/// is individually tappable. That inversion costs no new colour — "inset =
/// recessed / inactive" is already the design system's own vocabulary.
///
/// ## Structure of a row
///
/// ```
///  10:00 │ Олена Гриценко
///  11:30 │ Стрижка + укладка
/// ```
///
/// A right-aligned time stub (start over end, tight-leading numerals), a
/// hairline rule, then the person and what they booked. The person's name is
/// the heaviest text in the row because the person is what the master is
/// weighing.
///
/// The **date** is never repeated per row: on a single-date change the
/// dialog's own subline establishes it; on a multi-date range the rows group
/// under date headers inside the trough.
///
/// ## Scroll affordance
///
/// When the content overflows, a base-tone gradient eats the clipped edge —
/// top, bottom, or both — so a partially-visible row never looks like a
/// render bug. Pure `LinearGradient` over the base tone: no `BackdropFilter`,
/// no blur.
library;

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';

import '../../domain/schedule_model.dart';

/// Wraps a row in its staggered entrance slice. Supplied by the dialog.
typedef RowReveal = Widget Function(int index, Widget child);

class ConflictTrough extends StatefulWidget {
  const ConflictTrough({
    super.key,
    required this.conflicts,
    required this.spansMultipleDates,
    required this.reveal,
    this.maxHeight = maxTroughHeight,
  });

  /// Sorted chronologically by the backend — rendered in this order, never
  /// re-sorted.
  final List<OverrideConflict> conflicts;

  /// True when [conflicts] spans more than one calendar date — the trough
  /// then groups rows under date headers instead of relying on the dialog's
  /// subline to establish the day.
  final bool spansMultipleDates;

  final RowReveal reveal;

  /// The trough never grows past this, no matter how tall the screen or how
  /// many bookings there are. Lands mid-row on purpose: a clipped row is the
  /// cheapest and most honest "there is more below" signal there is.
  final double maxHeight;

  static const double maxTroughHeight = 316;

  @override
  State<ConflictTrough> createState() => _ConflictTroughState();
}

class _ConflictTroughState extends State<ConflictTrough> {
  final ScrollController _scroll = ScrollController();

  bool _fadeTop = false;
  bool _fadeBottom = false;
  bool _syncScheduled = false;

  /// The flattened row plan — computed ONCE from [widget.conflicts] /
  /// [widget.spansMultipleDates] (not per `itemBuilder` call), so build cost
  /// stays flat regardless of how many conflicts the backend returns (capped
  /// at 500 server-side; the trough only ever paints ~5-6 rows through its
  /// bounded height). Recomputed only when those inputs actually change —
  /// see [didUpdateWidget].
  late List<_TroughRow> _rows;

  @override
  void initState() {
    super.initState();
    _rows = _buildRowPlan();
    _scheduleSync();
  }

  @override
  void didUpdateWidget(covariant ConflictTrough oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.conflicts, widget.conflicts) ||
        oldWidget.spansMultipleDates != widget.spansMultipleDates) {
      _rows = _buildRowPlan();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Recompute the edge fades after the frame settles. Deferring to a
  /// post-frame callback keeps `setState` out of scroll-notification dispatch,
  /// which can land mid-layout.
  void _scheduleSync() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted || !_scroll.hasClients) return;
      final ScrollPosition p = _scroll.position;
      final bool top = p.pixels > p.minScrollExtent + 1;
      final bool bottom = p.pixels < p.maxScrollExtent - 1;
      if (top != _fadeTop || bottom != _fadeBottom) {
        setState(() {
          _fadeTop = top;
          _fadeBottom = bottom;
        });
      }
    });
  }

  /// Flattens the conflict list into a plain-data row PLAN, injecting a date
  /// header whenever the day changes — but only when the change actually
  /// spans several dates. Pure data, no widget construction: this is the
  /// "index map computed once" that [_rowAt] then looks up per
  /// `itemBuilder` call, so a 500-row conflict list costs exactly the same
  /// to plan as a 1-row one, and only the handful of visibly-scrolled rows
  /// are ever turned into widgets.
  ///
  /// The `revealIndex` assigned to each header/conflict row is byte-for-byte
  /// the same sequence the pre-`.builder` version produced (headers and
  /// conflict rows increment it; hairline rules do not) — that index is what
  /// [DayOffConflictDialog._revealRow] staggers and caps at
  /// `_maxStaggeredRows`, so the approved entrance animation is unaffected by
  /// this change.
  List<_TroughRow> _buildRowPlan() {
    final List<OverrideConflict> conflicts = widget.conflicts;
    final bool grouped = widget.spansMultipleDates;
    final List<_TroughRow> out = <_TroughRow>[];

    DateTime? currentDay;
    int rowIndex = 0;

    for (int i = 0; i < conflicts.length; i++) {
      final OverrideConflict c = conflicts[i];
      if (grouped && c.date != currentDay) {
        out.add(
          _TroughRow.header(
            day: c.date,
            first: currentDay == null,
            revealIndex: rowIndex,
          ),
        );
        rowIndex++;
        currentDay = c.date;
      } else if (out.isNotEmpty) {
        out.add(const _TroughRow.rule());
      }

      out.add(_TroughRow.conflict(conflict: c, revealIndex: rowIndex));
      rowIndex++;
    }
    return out;
  }

  /// Materializes ONE row plan entry into its widget — called only for rows
  /// `ListView.builder` actually needs to lay out.
  Widget _rowAt(int index) {
    final _TroughRow row = _rows[index];
    switch (row.kind) {
      case _RowKind.header:
        return widget.reveal(
          row.revealIndex!,
          _DateGroupHeader(day: row.day!, first: row.first),
        );
      case _RowKind.rule:
        return const _RowRule();
      case _RowKind.conflict:
        return widget.reveal(
          row.revealIndex!,
          _ConflictRow(conflict: row.conflict!),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      // A bounded max even when the parent hands down unbounded height (the
      // dialog's outer scroll view does exactly that), so the trough always
      // resolves to `min(content, maxHeight)` and its own ListView takes over
      // from there.
      constraints: BoxConstraints(maxHeight: widget.maxHeight),
      child: NeumorphicInset(
        radius: VelvetRadii.card,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(VelvetRadii.card),
          child: Stack(
            children: <Widget>[
              NotificationListener<ScrollNotification>(
                onNotification: (ScrollNotification n) {
                  _scheduleSync();
                  return false;
                },
                child: Scrollbar(
                  controller: _scroll,
                  thumbVisibility: _fadeBottom || _fadeTop,
                  child: ListView.builder(
                    controller: _scroll,
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(
                      vertical: VelvetSpacing.sm,
                    ),
                    itemCount: _rows.length,
                    itemBuilder: (BuildContext context, int index) =>
                        _rowAt(index),
                  ),
                ),
              ),
              _EdgeFade(alignment: Alignment.topCenter, visible: _fadeTop),
              _EdgeFade(
                alignment: Alignment.bottomCenter,
                visible: _fadeBottom,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The three shapes a flattened trough row can take. Plain data — see
/// [_ConflictTroughState._buildRowPlan].
enum _RowKind { header, rule, conflict }

/// One entry in the trough's flattened row plan. Exactly one of [conflict] /
/// [day] is set, matching [kind]; [revealIndex] is set for [_RowKind.header]
/// and [_RowKind.conflict] (the two kinds that pass through
/// [ConflictTrough.reveal]) and `null` for [_RowKind.rule] (a plain hairline,
/// never staggered).
class _TroughRow {
  const _TroughRow.header({
    required DateTime this.day,
    required this.first,
    required int this.revealIndex,
  }) : kind = _RowKind.header,
       conflict = null;

  const _TroughRow.rule()
    : kind = _RowKind.rule,
      day = null,
      first = false,
      revealIndex = null,
      conflict = null;

  const _TroughRow.conflict({
    required OverrideConflict this.conflict,
    required int this.revealIndex,
  }) : kind = _RowKind.conflict,
       day = null,
       first = false;

  final _RowKind kind;
  final DateTime? day;
  final bool first;
  final OverrideConflict? conflict;
  final int? revealIndex;
}

/// One booking about to be cancelled.
class _ConflictRow extends StatelessWidget {
  const _ConflictRow({required this.conflict});

  final OverrideConflict conflict;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          '${formatSlotTime(conflict.startsAt)} – '
          '${formatSlotTime(conflict.endsAt)}, '
          '${conflict.clientDisplayName}, ${conflict.serviceName}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          VelvetSpacing.md,
          VelvetSpacing.sm + 4,
          VelvetSpacing.md,
          VelvetSpacing.sm + 4,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            SizedBox(
              width: 44,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    formatSlotTime(conflict.startsAt),
                    style: VelvetText.dayOffConflictRowTime,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatSlotTime(conflict.endsAt),
                    style: VelvetText.dayOffConflictRowTimeEnd,
                  ),
                ],
              ),
            ),
            const SizedBox(width: VelvetSpacing.sm + 4),
            Container(
              width: 1,
              height: 32,
              color: BrandColors.faint.withValues(alpha: 0.55),
            ),
            const SizedBox(width: VelvetSpacing.sm + 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    conflict.clientDisplayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: VelvetText.dayOffConflictRowName,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    conflict.serviceName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: VelvetText.dayOffConflictRowService,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hairline between two rows of the same day. Inset from both edges so it
/// reads as a rule inside the trough rather than a cut across it.
class _RowRule extends StatelessWidget {
  const _RowRule();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.md),
      child: Container(
        height: 1,
        color: BrandColors.faint.withValues(alpha: 0.38),
      ),
    );
  }
}

/// Date header inside the trough — only rendered when the change spans
/// several dates. The camel dot is the only accent colour in the list.
class _DateGroupHeader extends StatelessWidget {
  const _DateGroupHeader({required this.day, required this.first});

  final DateTime day;

  /// The first header needs no separating space above it — the trough
  /// padding already provides it.
  final bool first;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        VelvetSpacing.md,
        first ? VelvetSpacing.xs : VelvetSpacing.sm + 4,
        VelvetSpacing.md,
        VelvetSpacing.xs,
      ),
      child: Row(
        children: <Widget>[
          Container(
            height: 5,
            width: 5,
            decoration: const BoxDecoration(
              color: BrandColors.accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: VelvetSpacing.sm),
          Text(formatBookingDayHeader(day), style: VelvetText.label()),
          const SizedBox(width: VelvetSpacing.sm),
          Expanded(
            child: Container(
              height: 1,
              color: BrandColors.faint.withValues(alpha: 0.38),
            ),
          ),
        ],
      ),
    );
  }
}

/// A base-tone gradient that eats the clipped edge of the scroll viewport.
class _EdgeFade extends StatelessWidget {
  const _EdgeFade({required this.alignment, required this.visible});

  final Alignment alignment;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final bool top = alignment == Alignment.topCenter;
    return Positioned(
      top: top ? 0 : null,
      bottom: top ? null : 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: Container(
            height: 28,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: top ? Alignment.topCenter : Alignment.bottomCenter,
                end: top ? Alignment.bottomCenter : Alignment.topCenter,
                colors: <Color>[
                  BrandColors.base,
                  BrandColors.base.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
