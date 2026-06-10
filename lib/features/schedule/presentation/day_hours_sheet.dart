// Phase 15.4 — DayHoursSheet (Editor B): the per-date override modal sheet.
//
// Ported from the approved preview app at
// `docs/signup-designs/MasterSchedule/lib/screens/day_hours_sheet.dart`,
// adapted to the project's Riverpod + go_router structure:
//   • preview StatefulWidget + SnackBar-only save  → ConsumerStatefulWidget that
//     persists through [OverridesNotifier] (`PUT /overrides/{date}`)
//   • preview standalone Velvet* tokens             → BrandColors / VelvetText /
//     Velvet* (1:1)
//   • preview inline reason/note stubs              → the real four-reason picker
//     + optional note (the parts the preview left for the port; design filled in
//     via `frontend-design`, constrained to the locked Velvet Touch palette)
//   • reuses the SHARED [IntervalEditor] / [TimeWell] / wheel picker from 15.3 —
//     no second copy.
//
// It OVERRIDES the weekly template for ONE calendar date (start == end):
//   • Робочі години → [IntervalEditor] seeded from the day's current intervals
//     via `DayHours.fromIntervals` → saves a CUSTOM_HOURS override.
//   • Вихідний       → reason picker (VACATION/HOLIDAY/SICK_DAY/OTHER) + optional
//     note → saves a DAY_OFF override.
//
// SAVE → CALENDAR REPAINT: [OverridesNotifier.putOverride] / `.clearOverride`
// reload the watched range AND `ref.invalidate(effectiveScheduleProvider)` on
// success, so the Master-Schedule calendar re-fetches and repaints with no
// manual refresh.
//
// OQ-1 (ALWAYS ALLOW): saving an override / day-off is NEVER blocked or gated by
// existing bookings, and no conflict confirmation is required. There is no
// booking-conflict gate in this sheet (the optional «N бронювань» info note is a
// non-blocking nice-to-have, omitted for MVP).
//
// SINGLE DATE ONLY: this sheet edits one date (`start == end`). A multi-day
// Time-Off span (vacation week) is the Propagate/range surface (Phase 15.5),
// which fans out to N bounded `PUT /overrides/{date}` calls. This sheet never
// loops over a span.
//
// PAST-DATE INVARIANT: the sheet is never constructed for a past date — the
// caller (the day pencil in `master_schedule_screen.dart`) is hidden on past
// days. The sheet itself does not re-derive "today"; it stays wall-clock free
// (M6) so widget/golden tests are run-day independent.

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/navigation/overlay_navigation.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

import '../domain/schedule_model.dart';
import 'overrides_notifier.dart';
import 'schedule_range.dart';
import 'widgets/interval_editor.dart';

/// The per-date override modal bottom sheet.
///
/// Present it with [DayHoursSheet.show]. It still repaints the calendar
/// reactively (via the invalidated effective schedule), but ALSO resolves to
/// the [DateTime] that was just put / cleared on a successful save, so the host
/// can move the selection onto the changed day. A plain dismiss (close button,
/// barrier tap, validation bail-out) resolves to `null`.
class DayHoursSheet extends ConsumerStatefulWidget {
  const DayHoursSheet({
    super.key,
    required this.date,
    required this.weekdayFull,
    required this.dateLabel,
    required this.range,
    required this.initialIntervals,
    required this.hasExistingOverride,
    required this.initialDayOff,
    this.initialReason,
    this.initialNote,
  });

  /// The single calendar date this override targets (date-only). `start == end`
  /// for the built [ScheduleOverride].
  final DateTime date;

  /// Localised full weekday name (e.g. «Вівторок»), resolved by the host.
  final String weekdayFull;

  /// Localised long date (e.g. «21 травня»), resolved by the host via the
  /// domain `formatDay` helper so this sheet stays calendar-format free.
  final String dateLabel;

  /// The visible-month [ScheduleRange] backing the calendar — the SAME family
  /// key the screen watches, so mutating `overridesProvider(range)` reloads the
  /// list the calendar reads and the override dots / grid stay in sync.
  final ScheduleRange range;

  /// The day's CURRENT working intervals (template-derived or an existing
  /// custom override). Seeds the [IntervalEditor] via `DayHours.fromIntervals`.
  /// Empty → the working-hours editor seeds a sensible default day.
  final List<WorkInterval> initialIntervals;

  /// `true` when a per-date override already exists for [date] — drives the
  /// "Видалити перевизначення" (clear) action's visibility.
  final bool hasExistingOverride;

  /// `true` when the existing override (if any) is a day-off — seeds the mode
  /// toggle to «Вихідний». Otherwise the sheet opens in working-hours mode.
  final bool initialDayOff;

  /// The existing day-off reason (when [initialDayOff]); seeds the reason
  /// picker. Defaults to VACATION when absent.
  final OverrideReason? initialReason;

  /// The existing day-off note (when [initialDayOff]); seeds the note field.
  final String? initialNote;

  /// Presents the sheet. Resolves to the edited [date] on a successful save /
  /// clear (so the host can focus that day), or `null` on a plain dismiss.
  static Future<DateTime?> show(
    BuildContext context, {
    required DateTime date,
    required String weekdayFull,
    required String dateLabel,
    required ScheduleRange range,
    required List<WorkInterval> initialIntervals,
    required bool hasExistingOverride,
    required bool initialDayOff,
    OverrideReason? initialReason,
    String? initialNote,
  }) {
    return showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: BrandColors.text.withValues(alpha: 0.35),
      builder: (BuildContext context) => DayHoursSheet(
        date: date,
        weekdayFull: weekdayFull,
        dateLabel: dateLabel,
        range: range,
        initialIntervals: initialIntervals,
        hasExistingOverride: hasExistingOverride,
        initialDayOff: initialDayOff,
        initialReason: initialReason,
        initialNote: initialNote,
      ),
    );
  }

  @override
  ConsumerState<DayHoursSheet> createState() => _DayHoursSheetState();
}

class _DayHoursSheetState extends ConsumerState<DayHoursSheet> {
  static const _tag = 'feature.schedule.dayoverride';

  /// The working window + breaks for the custom-hours mode (rebuilt from the
  /// incoming intervals so edits never touch the calendar's source data).
  late DayHours _day;
  late bool _dayOff;
  late OverrideReason _reason;
  late final TextEditingController _noteController;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _dayOff = widget.initialDayOff;
    _day = widget.initialIntervals.isEmpty
        ? DayHours.defaultDay()
        : DayHours.fromIntervals(widget.initialIntervals);
    _reason = widget.initialReason ?? OverrideReason.vacation;
    _noteController = TextEditingController(text: widget.initialNote ?? '');
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  /// Custom-hours mode is unsaveable while the window/breaks are invalid.
  /// Day-off mode is always valid (a reason is always selected).
  bool get _hasErrors => !_dayOff && !dayHoursValid(_day);

  void _setDayOff(bool off) => setState(() => _dayOff = off);

  /// Resolves an [OverrideReason] to its localised label.
  String _reasonLabel(AppLocalizations l10n, OverrideReason reason) =>
      switch (reason) {
        OverrideReason.vacation => l10n.scheduleOverrideReasonVacation,
        OverrideReason.holiday => l10n.scheduleOverrideReasonHoliday,
        OverrideReason.sickDay => l10n.scheduleOverrideReasonSickDay,
        OverrideReason.other => l10n.scheduleOverrideReasonOther,
      };

  // ── Persistence (OQ-1: always allowed — no booking-conflict gate) ───────────
  Future<void> _save() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    if (_hasErrors) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            backgroundColor: BrandColors.error,
            content: Text(l10n.scheduleOverrideErrorsBanner),
          ),
        );
      return;
    }

    // Build a single-date override (start == end). CUSTOM_HOURS carries the
    // collapsed working-interval list; DAY_OFF carries the reason + note.
    final ScheduleOverride override = _dayOff
        ? ScheduleOverride.dayOff(
            start: widget.date,
            end: widget.date,
            reason: _reason,
            note: _noteController.text.trim().isEmpty
                ? null
                : _noteController.text.trim(),
          )
        : ScheduleOverride.custom(
            start: widget.date,
            end: widget.date,
            intervals: _day.toIntervals(),
          );

    if (kDebugMode) {
      log(
        'save override ${widget.date.toIso8601String()} '
        'kind=${override.kind.name}',
        name: _tag,
        level: 800,
      );
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(overridesProvider(widget.range).notifier)
          .putOverride(override);
      if (!mounted) return;
      // [OverridesNotifier.putOverride] wraps its work in `AsyncValue.guard`, so
      // a failed PUT does NOT throw here — it surfaces as an [AsyncError] on the
      // provider state. Read that resulting state and branch on it: only pop +
      // show success when the mutation actually persisted (`hasError == false`).
      final AsyncValue<List<ScheduleOverride>> result = ref.read(
        overridesProvider(widget.range),
      );
      if (result.hasError) {
        _showError(messenger, result.error, l10n);
        return;
      }
      // Resolve the sheet's future with the edited date so the host moves the
      // selected day onto it and re-reads the now-fresh override (rather than a
      // retained stale snapshot) the instant the sheet closes.
      dismissOverlay<DateTime>(context, widget.date);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.savedSnackbar)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Clears the existing override → reverts [date] to the weekly template.
  /// Always allowed (OQ-1) — never gated on bookings.
  Future<void> _clear() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    if (kDebugMode) {
      log(
        'clear override ${widget.date.toIso8601String()}',
        name: _tag,
        level: 800,
      );
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(overridesProvider(widget.range).notifier)
          .clearOverride(widget.date);
      if (!mounted) return;
      // As in [_save]: `clearOverride` swallows a [Failure] into the provider's
      // [AsyncError] state rather than rethrowing, so inspect the resulting
      // state and only pop + report success on a clean clear.
      final AsyncValue<List<ScheduleOverride>> result = ref.read(
        overridesProvider(widget.range),
      );
      if (result.hasError) {
        _showError(messenger, result.error, l10n);
        return;
      }
      // Same as [_save]: resolve with the cleared date so the host focuses it
      // and re-reads the reverted (template) day immediately.
      dismissOverlay<DateTime>(context, widget.date);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(l10n.scheduleOverrideClearedSnack)),
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Shows the failure snackbar for a swallowed-into-state override mutation.
  /// [error] is the provider's [AsyncValue.error]: a typed [Failure] when the
  /// repository mapped it, otherwise the generic unknown-error copy.
  void _showError(
    ScaffoldMessengerState messenger,
    Object? error,
    AppLocalizations l10n,
  ) {
    final String message = error is Failure
        ? error.userMessage(context)
        : l10n.errUnknown;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(backgroundColor: BrandColors.error, content: Text(message)),
      );
  }

  // ── Build ────────────────────────────────────────────────────────────────--
  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final double bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: BrandColors.base,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(VelvetRadii.card),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              VelvetSpacing.lg,
              VelvetSpacing.md,
              VelvetSpacing.lg,
              VelvetSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Center(child: _grabber()),
                const SizedBox(height: VelvetSpacing.md),
                _headerRow(l10n),
                const SizedBox(height: VelvetSpacing.xs),
                Text(
                  l10n.scheduleOverrideSheetSubtitle,
                  style: VelvetText.body().copyWith(fontSize: 13),
                ),
                const SizedBox(height: VelvetSpacing.lg),
                _modeToggle(l10n),
                const SizedBox(height: VelvetSpacing.lg),
                if (_dayOff)
                  _dayOffSection(l10n)
                else
                  IntervalEditor(
                    day: _day,
                    onChanged: () => setState(() {}),
                    strings: _intervalStrings(l10n),
                    fieldKeyPrefix: 'override',
                  ),
                const SizedBox(height: VelvetSpacing.xl),
                NeumorphicButton(
                  key: const Key('override-save'),
                  label: l10n.scheduleOverrideSave,
                  icon: Icons.check_rounded,
                  loading: _saving,
                  onPressed: _saving ? null : _save,
                ),
                if (widget.hasExistingOverride) ...<Widget>[
                  const SizedBox(height: VelvetSpacing.sm + 2),
                  _deleteAction(l10n),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _grabber() {
    return Container(
      height: 5,
      width: 44,
      decoration: BoxDecoration(
        color: BrandColors.faint,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }

  Widget _headerRow(AppLocalizations l10n) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Text(
            '${widget.weekdayFull}, ${widget.dateLabel}',
            style: VelvetText.heading(),
          ),
        ),
        Semantics(
          button: true,
          label: l10n.scheduleOverrideCloseSemantic,
          child: GestureDetector(
            key: const Key('override-close'),
            onTap: () => dismissOverlay(context),
            child: Container(
              height: 40,
              width: 40,
              decoration: const BoxDecoration(
                color: BrandColors.base,
                shape: BoxShape.circle,
                boxShadow: VelvetShadows.extrudedSmall,
              ),
              child: const Icon(
                Icons.close_rounded,
                size: 20,
                color: BrandColors.textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Two-option segmented choice: custom intervals vs. full day-off.
  Widget _modeToggle(AppLocalizations l10n) {
    return Semantics(
      label: l10n.scheduleOverrideModeToggleSemantic,
      child: Row(
        key: const Key('override-mode-toggle'),
        children: <Widget>[
          Expanded(
            child: _modeChip(
              valueKey: const Key('override-mode-working'),
              label: l10n.scheduleOverrideModeWorking,
              icon: Icons.schedule_rounded,
              selected: !_dayOff,
              onTap: () => _setDayOff(false),
            ),
          ),
          const SizedBox(width: VelvetSpacing.sm + 2),
          Expanded(
            child: _modeChip(
              valueKey: const Key('override-mode-dayoff'),
              label: l10n.scheduleOverrideModeDayOff,
              icon: Icons.event_busy_rounded,
              selected: _dayOff,
              onTap: () => _setDayOff(true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeChip({
    required Key valueKey,
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final Color tint = selected ? BrandColors.accentDeep : BrandColors.muted;
    final Widget content = Padding(
      padding: const EdgeInsets.symmetric(vertical: VelvetSpacing.sm + 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(icon, size: 18, color: tint),
          const SizedBox(width: VelvetSpacing.sm - 2),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: VelvetText.bodyStrong().copyWith(
                fontSize: 13,
                color: tint,
              ),
            ),
          ),
        ],
      ),
    );

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        key: valueKey,
        onTap: onTap,
        child: selected
            ? NeumorphicInset(radius: VelvetRadii.field, child: content)
            : DecoratedBox(
                decoration: BoxDecoration(
                  color: BrandColors.base,
                  borderRadius: BorderRadius.circular(VelvetRadii.field),
                  boxShadow: VelvetShadows.extrudedSmall,
                ),
                child: content,
              ),
      ),
    );
  }

  // ── Day-off mode: reason picker + optional note ─────────────────────────────
  Widget _dayOffSection(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _dayOffRest(l10n),
        const SizedBox(height: VelvetSpacing.lg),
        Text(l10n.scheduleOverrideReasonLabel, style: VelvetText.label()),
        const SizedBox(height: VelvetSpacing.sm),
        _reasonGrid(l10n),
        const SizedBox(height: VelvetSpacing.lg),
        Text(l10n.scheduleOverrideNoteLabel, style: VelvetText.label()),
        const SizedBox(height: VelvetSpacing.sm),
        NeumorphicTextField(
          key: const Key('override-note-field'),
          label: l10n.scheduleOverrideNoteLabel,
          controller: _noteController,
          hintText: l10n.scheduleOverrideNoteHint,
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.done,
          maxLength: 120,
        ),
      ],
    );
  }

  Widget _dayOffRest(AppLocalizations l10n) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: BrandColors.base,
        borderRadius: BorderRadius.circular(VelvetRadii.field),
        border: Border.all(color: BrandColors.faint.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(VelvetSpacing.lg),
        child: Column(
          children: <Widget>[
            const Icon(
              Icons.bedtime_rounded,
              size: 28,
              color: BrandColors.faint,
            ),
            const SizedBox(height: VelvetSpacing.sm),
            Text(
              l10n.scheduleOverrideDayOffRest,
              textAlign: TextAlign.center,
              style: VelvetText.body().copyWith(color: BrandColors.muted),
            ),
          ],
        ),
      ),
    );
  }

  /// 2×2 grid of selectable reason tiles: selected = inset + camel accent,
  /// unselected = extruded.
  Widget _reasonGrid(AppLocalizations l10n) {
    const List<OverrideReason> reasons = OverrideReason.values;
    return Column(
      children: <Widget>[
        for (int row = 0; row < reasons.length; row += 2)
          Padding(
            padding: EdgeInsets.only(
              bottom: row + 2 < reasons.length ? VelvetSpacing.sm + 2 : 0,
            ),
            child: Row(
              children: <Widget>[
                Expanded(child: _reasonTile(l10n, reasons[row])),
                const SizedBox(width: VelvetSpacing.sm + 2),
                Expanded(
                  child: row + 1 < reasons.length
                      ? _reasonTile(l10n, reasons[row + 1])
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _reasonTile(AppLocalizations l10n, OverrideReason reason) {
    final bool selected = _reason == reason;
    final Color tint = selected ? BrandColors.accentDeep : BrandColors.muted;
    final String label = _reasonLabel(l10n, reason);
    final Widget content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: VelvetSpacing.md,
        vertical: VelvetSpacing.md - 2,
      ),
      child: Row(
        children: <Widget>[
          Icon(reason.icon, size: 18, color: tint),
          const SizedBox(width: VelvetSpacing.sm),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: VelvetText.bodyStrong().copyWith(
                fontSize: 13,
                color: tint,
              ),
            ),
          ),
        ],
      ),
    );

    return Semantics(
      button: true,
      selected: selected,
      label: l10n.scheduleOverrideReasonSemantic(label),
      child: GestureDetector(
        key: Key('override-reason-${reason.wire}'),
        onTap: () => setState(() => _reason = reason),
        child: selected
            ? NeumorphicInset(radius: VelvetRadii.field, child: content)
            : DecoratedBox(
                decoration: BoxDecoration(
                  color: BrandColors.base,
                  borderRadius: BorderRadius.circular(VelvetRadii.field),
                  boxShadow: VelvetShadows.extrudedSmall,
                ),
                child: content,
              ),
      ),
    );
  }

  // ── Destructive clear action (only when an override already exists) ─────────
  Widget _deleteAction(AppLocalizations l10n) {
    return Semantics(
      button: true,
      label: l10n.scheduleOverrideDelete,
      child: GestureDetector(
        key: const Key('override-delete'),
        onTap: _saving ? null : _clear,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: 44,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.delete_outline_rounded,
                  size: 17,
                  color: BrandColors.error.withValues(
                    alpha: _saving ? 0.4 : 1.0,
                  ),
                ),
                const SizedBox(width: VelvetSpacing.sm - 2),
                Text(
                  l10n.scheduleOverrideDelete,
                  style: VelvetText.link().copyWith(
                    fontSize: 13,
                    color: BrandColors.error.withValues(
                      alpha: _saving ? 0.4 : 1.0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// All localised copy the shared [IntervalEditor] needs (same mapping the
  /// weekly editor uses, so the two editors speak identical strings).
  IntervalEditorStrings _intervalStrings(AppLocalizations l10n) =>
      IntervalEditorStrings(
        workHoursLabel: l10n.intervalEditorWorkHours,
        breaksLabel: l10n.intervalEditorBreaks,
        addBreak: l10n.intervalEditorAddBreak,
        workStartTitle: l10n.intervalEditorWorkStartTitle,
        workEndTitle: l10n.intervalEditorWorkEndTitle,
        breakStartTitle: l10n.intervalEditorBreakStartTitle,
        breakEndTitle: l10n.intervalEditorBreakEndTitle,
        timePickerConfirm: l10n.timePickerConfirm,
        timePickerHoursSemantic: l10n.timePickerHoursSemantic,
        timePickerMinutesSemantic: l10n.timePickerMinutesSemantic,
        breakStartSemantic: l10n.intervalEditorBreakStartSemantic,
        breakEndSemantic: l10n.intervalEditorBreakEndSemantic,
        removeBreakSemantic: l10n.intervalEditorRemoveBreak,
        errWindowEndBeforeStart: l10n.intervalEditorErrEndAfterStart,
        errBreakEndBeforeStart: l10n.intervalEditorErrBreakEndAfterStart,
        errBreakOutsideWindow: l10n.intervalEditorErrBreakInsideWindow,
        errBreaksOverlap: l10n.intervalEditorErrBreaksOverlap,
        errTimeNotAligned: l10n.scheduleErrTimeNotAligned,
      );
}
