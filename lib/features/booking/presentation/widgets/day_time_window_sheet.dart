// Phase 7.12, Step 2 — the intra-day time-of-day window picker sheet for the
// master's «Мої записи» timeline.
//
// ## Chrome transcribed from `bookings_filter_sheet.dart`
//
// Grabber, section label, «Скинути» / «Застосувати» footer pair, the
// `BrandColors.base` rounded-top sheet shell — all lifted verbatim from the
// sibling filter sheet (Phase 7.7) so the two read as ONE system, per this
// phase's brief. Bordered surfaces only — **no `extrudedCard`/
// `extrudedButton`** anywhere here (the Impeller white-corner bug; see
// `master_bookings_states.dart`'s header for the same note repeated
// throughout this feature).
//
// The individual hour/minute wheels are NOT reinvented here — they reuse
// `showVelvetTimePicker` (`features/schedule/presentation/widgets/
// velvet_time_picker.dart`), the same VelvetTouch wheel picker the working-
// hours screen already uses for every time field in the app. That widget is
// already reused across features (`working_hours_screen.dart`, under
// `calendar/presentation/`, imports it from the `schedule` feature) — this
// sheet does the same rather than re-implement a second wheel picker.
//
// ## Draft state, applied once — same discipline as the filter sheet
//
// Every wheel tap mutates SHEET-LOCAL draft state (`_draftStart`/
// `_draftEnd`). Nothing reaches the caller until «Застосувати» — a live-
// applying picker would rebuild the timeline (and, worse, invite someone to
// wire it into the query) on every single wheel notch.
//
// ## Three resolutions, not two — [DayTimeWindowPickResult]
//
// A bare `Future<DayTimeWindow?>` cannot distinguish "dismissed without
// changing anything" from "the user explicitly removed the window" — both
// would resolve `null`. [DayTimeWindowPickResult] is the sealed three-way
// split the caller (`bookings_discovery_view.dart`) actually needs:
// `null` (dismissed, unchanged), [DayTimeWindowCleared] (the «Скинути»
// affordance — always visible, whether or not a window was already active,
// mirroring the phase brief's "clear affordance to remove the window"), and
// [DayTimeWindowApplied] (a validated [DayTimeWindow] from «Застосувати»).
//
// «Застосувати» is disabled (never a thrown `ArgumentError`) whenever the
// draft end does not exceed the draft start — [DayTimeWindow.new]'s
// validation is a construction-time invariant for every OTHER caller, but
// this sheet is the one place that must never let the user drive it there in
// the first place.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/schedule/presentation/widgets/velvet_time_picker.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

import '../../domain/day_time_window.dart';

/// The sheet's resolution — see the file header for why this is a sealed
/// three-way split rather than a bare `DayTimeWindow?`.
sealed class DayTimeWindowPickResult {
  const DayTimeWindowPickResult();
}

/// The user picked (or edited) a window and confirmed «Застосувати».
final class DayTimeWindowApplied extends DayTimeWindowPickResult {
  const DayTimeWindowApplied(this.window);

  final DayTimeWindow window;
}

/// The user explicitly removed the window via «Скинути».
final class DayTimeWindowCleared extends DayTimeWindowPickResult {
  const DayTimeWindowCleared();
}

/// Default draft start when the sheet opens with no existing window — a
/// generic working-day start, purely a convenience seed so «Застосувати» is
/// immediately actionable without forcing two wheel edits first.
const TimeOfDay _kDefaultDraftStart = TimeOfDay(hour: 9, minute: 0);

/// Default draft end — see [_kDefaultDraftStart].
const TimeOfDay _kDefaultDraftEnd = TimeOfDay(hour: 18, minute: 0);

/// Minutes since midnight for [t]. NOT the [DayTimeWindow] representation
/// (which additionally supports >1440 for a past-midnight END) — this sheet
/// only ever collects a start/end pair from a 00:00–23:59 wheel picker, so a
/// plain `hour * 60 + minute` is exact for every value this sheet can
/// produce.
int _toMinutes(TimeOfDay t) => t.hour * 60 + t.minute;

/// `HH:MM`, zero-padded, 24h.
String _formatTime(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// The intra-day time-window picker sheet. Resolves with a
/// [DayTimeWindowPickResult], or `null` when dismissed without changing
/// anything.
class DayTimeWindowSheet extends StatefulWidget {
  const DayTimeWindowSheet({super.key, required this.initial});

  /// The currently active window, if any — seeds the draft wheels and gates
  /// whether «Скинути» is shown.
  final DayTimeWindow? initial;

  static Future<DayTimeWindowPickResult?> show(
    BuildContext context, {
    required DayTimeWindow? initial,
  }) {
    return showModalBottomSheet<DayTimeWindowPickResult>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) => DayTimeWindowSheet(initial: initial),
    );
  }

  @override
  State<DayTimeWindowSheet> createState() => _DayTimeWindowSheetState();
}

class _DayTimeWindowSheetState extends State<DayTimeWindowSheet> {
  late TimeOfDay _draftStart;
  late TimeOfDay _draftEnd;

  @override
  void initState() {
    super.initState();
    final DayTimeWindow? initial = widget.initial;
    if (initial == null) {
      _draftStart = _kDefaultDraftStart;
      _draftEnd = _kDefaultDraftEnd;
    } else {
      _draftStart = TimeOfDay(
        hour: initial.startMinute ~/ 60,
        minute: initial.startMinute % 60,
      );
      // A stored end past 23:59 (past-midnight) cannot round-trip through a
      // 00:00–23:59 wheel — clamp for DISPLAY only. Unreachable from this
      // sheet's own output (see `_toMinutes`'s doc), so this only matters if
      // a future caller ever seeds `initial` with a past-midnight end.
      final int clampedEnd = initial.endMinute.clamp(0, 24 * 60 - 1);
      _draftEnd = TimeOfDay(hour: clampedEnd ~/ 60, minute: clampedEnd % 60);
    }
  }

  bool get _canApply => _toMinutes(_draftEnd) > _toMinutes(_draftStart);

  Future<void> _pickStart() async {
    final l10n = AppLocalizations.of(context);
    final TimeOfDay? picked = await showVelvetTimePicker(
      context,
      _draftStart,
      title: l10n.masterBookingsTimeWindowPickerStartTitle,
      confirmLabel: l10n.timePickerConfirm,
      hoursSemanticLabel: l10n.timePickerHoursSemantic,
      minutesSemanticLabel: l10n.timePickerMinutesSemantic,
    );
    if (picked == null || !mounted) return;
    setState(() => _draftStart = picked);
  }

  Future<void> _pickEnd() async {
    final l10n = AppLocalizations.of(context);
    final TimeOfDay? picked = await showVelvetTimePicker(
      context,
      _draftEnd,
      title: l10n.masterBookingsTimeWindowPickerEndTitle,
      confirmLabel: l10n.timePickerConfirm,
      hoursSemanticLabel: l10n.timePickerHoursSemantic,
      minutesSemanticLabel: l10n.timePickerMinutesSemantic,
    );
    if (picked == null || !mounted) return;
    setState(() => _draftEnd = picked);
  }

  void _clear() => context.pop(const DayTimeWindowCleared());

  void _apply() {
    if (!_canApply) return;
    context.pop(
      DayTimeWindowApplied(
        DayTimeWindow(
          startMinute: _toMinutes(_draftStart),
          endMinute: _toMinutes(_draftEnd),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DecoratedBox(
      key: const Key('day-time-window-sheet'),
      decoration: const BoxDecoration(
        color: BrandColors.base,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(VelvetRadii.card),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            VelvetSpacing.lg,
            VelvetSpacing.md,
            VelvetSpacing.lg,
            VelvetSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const _SheetGrabber(),
              const SizedBox(height: VelvetSpacing.md),
              Text(
                l10n.masterBookingsTimeWindowSheetTitle,
                style: VelvetText.subheading(),
              ),
              const SizedBox(height: VelvetSpacing.md),
              _TimeRow(
                rowKey: const Key('day-time-window-start'),
                label: l10n.masterBookingsTimeWindowFromLabel,
                semanticLabel: l10n.masterBookingsTimeWindowFromSemantics,
                value: _formatTime(_draftStart),
                onTap: _pickStart,
              ),
              const SizedBox(height: VelvetSpacing.sm),
              _TimeRow(
                rowKey: const Key('day-time-window-end'),
                label: l10n.masterBookingsTimeWindowToLabel,
                semanticLabel: l10n.masterBookingsTimeWindowToSemantics,
                value: _formatTime(_draftEnd),
                onTap: _pickEnd,
              ),
              const SizedBox(height: VelvetSpacing.lg),
              Row(
                children: <Widget>[
                  // Always offered, whether or not a window is already
                  // active — this is the "remove the window" affordance the
                  // phase brief calls for, distinct from the filter sheet's
                  // «Скинути», which only appears once something is active.
                  Semantics(
                    button: true,
                    label: l10n.masterBookingsTimeWindowResetSemantics,
                    child: GestureDetector(
                      key: const Key('day-time-window-reset'),
                      onTap: _clear,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: VelvetSpacing.sm,
                        ),
                        child: Text(
                          l10n.masterBookingsTimeWindowReset,
                          style: VelvetText.link(),
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Semantics(
                    button: true,
                    enabled: _canApply,
                    label: l10n.masterBookingsTimeWindowApplySemantics,
                    child: GestureDetector(
                      key: const Key('day-time-window-apply'),
                      onTap: _canApply ? _apply : null,
                      behavior: HitTestBehavior.opaque,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: BrandColors.base,
                          borderRadius: BorderRadius.circular(VelvetRadii.pill),
                          boxShadow: _canApply
                              ? VelvetShadows.borderedButton
                              : null,
                          border: Border.all(
                            color: _canApply
                                ? BrandColors.accent
                                : BrandColors.faint,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: VelvetSpacing.lg,
                            vertical: VelvetSpacing.sm + 2,
                          ),
                          child: Text(
                            l10n.masterBookingsTimeWindowApply,
                            style: _canApply
                                ? VelvetText.link()
                                : VelvetText.link().copyWith(
                                    color: BrandColors.faint,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One `Від`/`До` row — a neumorphic inset well showing the current draft
/// time, tapping opens the wheel picker. Mirrors `bookings_filter_sheet
/// .dart`'s `_DateRow` layout.
class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.rowKey,
    required this.label,
    required this.semanticLabel,
    required this.value,
    required this.onTap,
  });

  final Key rowKey;
  final String label;
  final String semanticLabel;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      value: value,
      child: GestureDetector(
        key: rowKey,
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: NeumorphicInset(
          radius: VelvetRadii.field,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: VelvetSpacing.md,
              vertical: VelvetSpacing.sm + 2,
            ),
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.schedule_rounded,
                  size: 18,
                  color: BrandColors.accentDeep,
                ),
                const SizedBox(width: VelvetSpacing.sm),
                Text(label, style: VelvetText.bodyStrong14),
                const Spacer(),
                Text(
                  value,
                  style: VelvetText.bodyStrong14.copyWith(
                    color: BrandColors.accentDeep,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The 4×44 grabber pill every VelvetTouch bottom sheet carries. Duplicated
/// from `bookings_filter_sheet.dart`'s private `_SheetGrabber` — both are
/// private to their own file by construction, so sharing it would mean
/// promoting it to a public widget for a 12-line pill; not worth the export.
class _SheetGrabber extends StatelessWidget {
  const _SheetGrabber();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        height: 4,
        width: 44,
        decoration: BoxDecoration(
          color: BrandColors.faint,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
