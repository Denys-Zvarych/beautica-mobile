// Phase 15.8 — DiscreteTimesEditor.
//
// A chip list of bookable start times for EXPLICIT_TIMES mode (weekly template
// days and per-date custom overrides). Designed to live INSIDE an already-raised
// NeumorphicCard — it does NOT add its own outer card shadow.
//
// Mirrors [IntervalEditor] in all respects:
//   • All copy is passed in via [DiscreteTimesEditorStrings] — this widget is
//     localization-free so the `no_raw_ui_strings` CI gate sees no raw strings.
//   • The host owns the [List<TimeOfDay>] and this widget mutates it in place,
//     then calls [onChanged] so the host can `setState` and drive dirty-diff /
//     Save-gate recomputation.
//   • A [fieldKeyPrefix] wires every interactive element with stable [Key]s for
//     widget tests (same pattern as [IntervalEditor.fieldKeyPrefix]).
//
// BEHAVIOUR CONTRACT:
//   • On "Add time": opens [showVelvetTimePicker] (minuteStep=15). Accepted time
//     is inserted, then [sortDedupeTimes] applied. A picked time that already
//     exists in [times] is REJECTED: a transient inline info message is shown for
//     2.5 s (auto-dismissed), nothing is mutated, [onChanged] is NOT called.
//   • Remove chip ✕: removes the time, calls [onChanged].
//   • Window label "HH:MM – HH:MM" (min–max of [times]) is shown above the chips
//     when [times] is non-empty; hidden when empty.
//   • Empty-list error row is shown when [times] is empty (a working day with
//     EXPLICIT_TIMES mode and zero times is invalid and blocks Save via the
//     notifier gate; the editor surfaces this inline so the save gate is never
//     silently dead).

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';

import '../../domain/schedule_model.dart';
import 'velvet_time_picker.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Strings bundle
// ─────────────────────────────────────────────────────────────────────────────

/// All localised copy [DiscreteTimesEditor] needs, resolved by the host through
/// `AppLocalizations`. Mirrors the [IntervalEditorStrings] approach so this
/// widget stays localization-free and off the `no_raw_ui_strings` lint surface.
@immutable
class DiscreteTimesEditorStrings {
  const DiscreteTimesEditorStrings({
    required this.addTimeLabel,
    required this.windowLabel,
    required this.removeTimeSemantic,
    required this.timePickerTitle,
    required this.timePickerConfirm,
    required this.timePickerHoursSemantic,
    required this.timePickerMinutesSemantic,
    required this.errEmpty,
    required this.duplicateMessage,
  });

  /// Button label for the "add a discrete time" action.
  final String addTimeLabel;

  /// Prefix shown before the derived "HH:MM – HH:MM" window range label.
  final String windowLabel;

  /// `(formattedTime) → accessibility label` for a chip's remove button.
  final String Function(String time) removeTimeSemantic;

  /// Title shown at the top of the wheel picker sheet.
  final String timePickerTitle;

  /// Confirm-CTA label inside the wheel picker sheet.
  final String timePickerConfirm;

  /// Accessibility label for the hours wheel.
  final String timePickerHoursSemantic;

  /// Accessibility label for the minutes wheel.
  final String timePickerMinutesSemantic;

  /// Error message shown when a working EXPLICIT_TIMES day has zero times.
  final String errEmpty;

  /// Transient info message shown when the picked time is already in the list.
  final String duplicateMessage;
}

// ─────────────────────────────────────────────────────────────────────────────
// Local formatting helper
// ─────────────────────────────────────────────────────────────────────────────

/// `HH:MM` zero-padded — local copy so this widget does not depend on the
/// domain helper's import surface (mirrors the pattern in `interval_editor.dart`).
String _fmt(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:'
    '${t.minute.toString().padLeft(2, '0')}';

// ─────────────────────────────────────────────────────────────────────────────
// DiscreteTimesEditor
// ─────────────────────────────────────────────────────────────────────────────

/// Chip list of discrete bookable start times for EXPLICIT_TIMES mode.
///
/// The host (a `StatefulWidget`) owns [times] and handles `setState` via
/// [onChanged]. This widget is `StatefulWidget` only to manage the transient
/// duplicate-warning message's auto-dismiss timer — no domain state lives here.
class DiscreteTimesEditor extends StatefulWidget {
  const DiscreteTimesEditor({
    super.key,
    required this.times,
    required this.onChanged,
    required this.strings,
    this.fieldKeyPrefix,
  });

  /// The mutable list of discrete start times — sorted and deduped by the host
  /// before construction. This widget mutates the list in place and then calls
  /// [onChanged].
  final List<TimeOfDay> times;

  /// Called after every mutation so the host can `setState` and recompute the
  /// Save gate (dirty-diff + validation).
  final VoidCallback onChanged;

  /// All localised copy, already resolved by the host through `AppLocalizations`.
  final DiscreteTimesEditorStrings strings;

  /// When set, each interactive element receives a stable `Key` of the form
  /// `'$prefix-add-time'`, `'$prefix-times-wrap'`, and
  /// `'$prefix-chip-HH:MM'` for widget tests.
  final String? fieldKeyPrefix;

  @override
  State<DiscreteTimesEditor> createState() => _DiscreteTimesEditorState();
}

class _DiscreteTimesEditorState extends State<DiscreteTimesEditor> {
  /// Hoisted, build-invariant text styles — allocated once instead of on every
  /// editor build (every chip add/remove). Mirrors [_TimeChip._chipStyle].
  static final TextStyle _windowLabelStyle = VelvetText.label().copyWith(
    fontSize: 12,
    color: BrandColors.accentDeep,
    fontWeight: FontWeight.w700,
  );
  static final TextStyle _addTimeStyle = VelvetText.link().copyWith(
    fontSize: 13,
  );

  /// Transient message shown when the picked time already exists in [times].
  /// `null` when no duplicate attempt is in progress.
  String? _dupeMessage;

  /// Cancelable auto-dismiss timer for [_dupeMessage]. Re-armed on each duplicate
  /// attempt (canceling any in-flight dismiss) so rapid taps can't let a stale
  /// callback clear a newer message; canceled in [dispose].
  Timer? _dismissTimer;

  @override
  void dispose() {
    _dismissTimer?.cancel();
    super.dispose();
  }

  // ── Add ──────────────────────────────────────────────────────────────────---
  Future<void> _addTime() async {
    // Seed the picker just after the last existing time (next full hour), or
    // 09:00 when the list is empty.
    final TimeOfDay seed = widget.times.isEmpty
        ? const TimeOfDay(hour: 9, minute: 0)
        : _nextSeed(widget.times.last);

    final TimeOfDay? picked = await showVelvetTimePicker(
      context,
      seed,
      title: widget.strings.timePickerTitle,
      confirmLabel: widget.strings.timePickerConfirm,
      hoursSemanticLabel: widget.strings.timePickerHoursSemantic,
      minutesSemanticLabel: widget.strings.timePickerMinutesSemantic,
      minuteStep: 15,
    );
    if (!mounted || picked == null) return;

    // Dedupe check — reject silently with a brief inline message.
    final int pickedMin = picked.hour * 60 + picked.minute;
    final bool isDupe = widget.times.any(
      (TimeOfDay t) => t.hour * 60 + t.minute == pickedMin,
    );
    if (isDupe) {
      setState(() => _dupeMessage = widget.strings.duplicateMessage);
      // Auto-dismiss after 2.5 s. Cancel any in-flight dismiss first so a stale
      // callback from an earlier tap can't clear this newer message.
      _dismissTimer?.cancel();
      _dismissTimer = Timer(const Duration(milliseconds: 2500), () {
        if (mounted) setState(() => _dupeMessage = null);
      });
      return;
    }

    // Insert and sort.
    widget.times.add(picked);
    final List<TimeOfDay> sorted = sortDedupeTimes(widget.times);
    widget.times
      ..clear()
      ..addAll(sorted);
    // Clear any stale duplicate message on a successful add.
    if (_dupeMessage != null) setState(() => _dupeMessage = null);
    widget.onChanged();
  }

  // ── Remove ───────────────────────────────────────────────────────────────---
  void _removeTime(TimeOfDay t) {
    widget.times.remove(t);
    widget.onChanged();
  }

  // ── Seed helper ──────────────────────────────────────────────────────────---
  /// Returns the next 15-min-aligned seed just after [last] (wraps at 23:45).
  static TimeOfDay _nextSeed(TimeOfDay last) {
    final int next = last.hour + 1;
    return TimeOfDay(hour: next < 24 ? next : 9, minute: 0);
  }

  // ── Build ─────────────────────────────────────────────────────────────────-
  @override
  Widget build(BuildContext context) {
    final List<TimeOfDay> times = widget.times;
    final DiscreteTimesEditorStrings s = widget.strings;
    final String? prefix = widget.fieldKeyPrefix;

    // A working EXPLICIT_TIMES day with no times is an error (Save blocked).
    final bool hasError = times.isEmpty;

    // Derived window summary: min–max of the sorted list.
    final String? windowRange = times.isNotEmpty
        ? '${_fmt(times.first)} – ${_fmt(times.last)}'
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // ── Derived window label ─────────────────────────────────────────────
        if (windowRange != null) ...<Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.schedule_rounded,
                size: 15,
                color: BrandColors.accentDeep,
              ),
              const SizedBox(width: VelvetSpacing.xs + 2),
              Text('${s.windowLabel}  $windowRange', style: _windowLabelStyle),
            ],
          ),
          const SizedBox(height: VelvetSpacing.sm + 2),
        ],

        // ── Chip wrap ────────────────────────────────────────────────────────
        if (times.isNotEmpty) ...<Widget>[
          Wrap(
            key: prefix != null ? Key('$prefix-times-wrap') : null,
            spacing: VelvetSpacing.sm,
            runSpacing: VelvetSpacing.sm,
            children: <Widget>[
              for (final TimeOfDay t in times)
                _TimeChip(
                  key: Key('${prefix ?? 'discrete'}-chip-${_fmt(t)}'),
                  time: t,
                  removeSemanticLabel: s.removeTimeSemantic(_fmt(t)),
                  onRemove: () => _removeTime(t),
                ),
            ],
          ),
          const SizedBox(height: VelvetSpacing.md),
        ],

        // ── "Add time" action ─────────────────────────────────────────────--
        Align(
          alignment: Alignment.centerLeft,
          child: Semantics(
            button: true,
            label: s.addTimeLabel,
            child: GestureDetector(
              key: prefix != null ? Key('$prefix-add-time') : null,
              onTap: _addTime,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: VelvetSpacing.md,
                  vertical: VelvetSpacing.sm + 2,
                ),
                decoration: BoxDecoration(
                  color: BrandColors.base,
                  borderRadius: BorderRadius.circular(VelvetRadii.field),
                  boxShadow: VelvetShadows.extrudedSmall,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(
                      Icons.more_time_rounded,
                      size: 16,
                      color: BrandColors.accentDeep,
                    ),
                    const SizedBox(width: VelvetSpacing.sm),
                    Text(s.addTimeLabel, style: _addTimeStyle),
                  ],
                ),
              ),
            ),
          ),
        ),

        // ── Duplicate-time transient message ─────────────────────────────---
        if (_dupeMessage != null) ...<Widget>[
          const SizedBox(height: VelvetSpacing.sm),
          Semantics(
            liveRegion: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(
                  Icons.info_outline_rounded,
                  size: 15,
                  color: BrandColors.accentDeep,
                ),
                const SizedBox(width: VelvetSpacing.xs + 2),
                Expanded(
                  child: Text(
                    _dupeMessage!,
                    style: VelvetText.feedback(BrandColors.accentDeep),
                  ),
                ),
              ],
            ),
          ),
        ],

        // ── Empty-day validation error ───────────────────────────────────---
        if (hasError) ...<Widget>[
          const SizedBox(height: VelvetSpacing.sm),
          Semantics(
            liveRegion: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(
                  Icons.error_outline,
                  size: 15,
                  color: BrandColors.error,
                ),
                const SizedBox(width: VelvetSpacing.xs + 2),
                Expanded(
                  child: Text(
                    s.errEmpty,
                    style: VelvetText.feedback(BrandColors.error),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _TimeChip — a single removable time pill.
// ─────────────────────────────────────────────────────────────────────────────

/// Neumorphic raised pill showing one discrete start time with a ✕ remove
/// button. The ✕ itself is a nested circle with its own `extrudedSmall` shadow
/// so it reads as a pressable sub-element rather than a flat icon.
class _TimeChip extends StatelessWidget {
  const _TimeChip({
    super.key,
    required this.time,
    required this.removeSemanticLabel,
    required this.onRemove,
  });

  final TimeOfDay time;
  final String removeSemanticLabel;
  final VoidCallback onRemove;

  static final TextStyle _chipStyle = VelvetText.bodyStrong().copyWith(
    fontSize: 13,
    color: BrandColors.accentDeep,
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
  );

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: BrandColors.base,
        borderRadius: BorderRadius.circular(VelvetRadii.pill),
        boxShadow: VelvetShadows.extrudedSmall,
      ),
      child: Padding(
        padding: const EdgeInsets.only(
          left: VelvetSpacing.md,
          right: VelvetSpacing.xs + 2,
          top: VelvetSpacing.sm - 2,
          bottom: VelvetSpacing.sm - 2,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(_fmt(time), style: _chipStyle),
            const SizedBox(width: VelvetSpacing.xs + 2),
            Semantics(
              button: true,
              label: removeSemanticLabel,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  height: 22,
                  width: 22,
                  decoration: const BoxDecoration(
                    color: BrandColors.base,
                    shape: BoxShape.circle,
                    boxShadow: VelvetShadows.extrudedSmall,
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 13,
                    color: BrandColors.error,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
