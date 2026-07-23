// Phase 15.5 — IntervalEditor + TimeWell + NeumorphicToggle.
//
// Ported from the approved preview app at
// `docs/signup-designs/MasterSchedule/lib/widgets/interval_editor.dart`
// (`TimeWell`, `NeumorphicToggle`, `IntervalEditor`, `_BreakRow`).  The
// preview's standalone tokens (VelvetColors, VelvetText, VelvetRadii,
// VelvetSpacing, VelvetShadows) map 1:1 onto the production equivalents in
// `lib/core/theme/`; the preview's `showVelvetTimePicker` maps to the
// production wheel picker in `velvet_time_picker.dart`.
//
// A working day reads as ONE working window (від–до) with OPTIONAL break ranges
// carved out of it.  The host owns a mutable [DayHours] and rebuilds via the
// [onChanged] callback; this widget mutates window/breaks in place and surfaces
// inline validation.  On save the host calls `day.toIntervals()` to get the
// canonical `List<WorkInterval>` the model + backend port serialise.
//
// LOCALIZATION: this surface imports no localization itself — every piece of
// user-facing copy is passed in by the host, already resolved through
// `AppLocalizations` (mirroring `velvet_time_picker.dart`).  This keeps the
// widget off the `no_raw_ui_strings` lint surface.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';

import '../../domain/schedule_model.dart';
import 'velvet_time_picker.dart';

/// All localised copy the [IntervalEditor] needs, resolved by the host through
/// `AppLocalizations` and passed down so the widget stays localization-free.
@immutable
class IntervalEditorStrings {
  const IntervalEditorStrings({
    required this.workHoursLabel,
    required this.breaksLabel,
    required this.addBreak,
    required this.workStartTitle,
    required this.workEndTitle,
    required this.breakStartTitle,
    required this.breakEndTitle,
    required this.timePickerConfirm,
    required this.timePickerHoursSemantic,
    required this.timePickerMinutesSemantic,
    required this.breakStartSemantic,
    required this.breakEndSemantic,
    required this.removeBreakSemantic,
    required this.errWindowEndBeforeStart,
    required this.errBreakEndBeforeStart,
    required this.errBreakOutsideWindow,
    required this.errBreaksOverlap,
    required this.errTimeNotAligned,
  });

  final String workHoursLabel;
  final String breaksLabel;
  final String addBreak;
  final String workStartTitle;
  final String workEndTitle;
  final String breakStartTitle;
  final String breakEndTitle;
  final String timePickerConfirm;
  final String timePickerHoursSemantic;
  final String timePickerMinutesSemantic;

  /// `(index) → label` — index is 1-based break number.
  final String Function(int index) breakStartSemantic;
  final String Function(int index) breakEndSemantic;
  final String Function(int index) removeBreakSemantic;

  final String errWindowEndBeforeStart;
  final String errBreakEndBeforeStart;
  final String errBreakOutsideWindow;
  final String errBreaksOverlap;
  final String errTimeNotAligned;

  /// Resolves a [DayHoursError] to the matching localised message.
  String messageFor(DayHoursError error) => switch (error.kind) {
    DayHoursErrorKind.windowEndBeforeStart => errWindowEndBeforeStart,
    DayHoursErrorKind.breakEndBeforeStart => errBreakEndBeforeStart,
    DayHoursErrorKind.breakOutsideWindow => errBreakOutsideWindow,
    DayHoursErrorKind.breaksOverlap => errBreaksOverlap,
    DayHoursErrorKind.notAligned => errTimeNotAligned,
  };
}

/// `HH:MM` with zero padding — local copy so this widget doesn't depend on the
/// domain helper's import surface.
String _formatTime(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

// ─────────────────────────────────────────────────────────────────────────────
// NeumorphicToggle — pill open/closed control (per-day in the weekly editor).
// Ported verbatim from the preview's interval_editor.dart NeumorphicToggle.
// ─────────────────────────────────────────────────────────────────────────────
class NeumorphicToggle extends StatelessWidget {
  const NeumorphicToggle({
    super.key,
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    const double width = 56;
    const double height = 32;
    const double thumb = 24;
    return Semantics(
      toggled: value,
      label: semanticLabel,
      button: true,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: NeumorphicInset(
                  radius: height / 2,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    decoration: BoxDecoration(
                      color: value
                          ? BrandColors.accent.withValues(alpha: 0.35)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(height / 2),
                    ),
                  ),
                ),
              ),
              AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.all(VelvetSpacing.xs),
                  child: Container(
                    height: thumb,
                    width: thumb,
                    decoration: BoxDecoration(
                      color: value ? BrandColors.accent : BrandColors.base,
                      shape: BoxShape.circle,
                      boxShadow: VelvetShadows.extrudedSmall,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A tappable inset time well showing `HH:MM` with a clock glyph. Carries an
/// error ring when [hasError] and an [accent] camel tint for working-window
/// fields. Tapping opens the wheel picker via the host's [onTap].
class TimeWell extends StatelessWidget {
  const TimeWell({
    super.key,
    required this.time,
    required this.onTap,
    required this.semanticLabel,
    this.hasError = false,
    this.accent = false,
  });

  final TimeOfDay time;
  final VoidCallback onTap;
  final String semanticLabel;
  final bool hasError;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$semanticLabel ${_formatTime(time)}',
      child: GestureDetector(
        onTap: onTap,
        child: NeumorphicInset(
          hasError: hasError,
          child: SizedBox(
            height: 50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  Icons.schedule_rounded,
                  size: 17,
                  color: accent ? BrandColors.accentDeep : BrandColors.muted,
                ),
                const SizedBox(width: VelvetSpacing.sm),
                Text(
                  _formatTime(time),
                  style: VelvetText.schedIntervalTime.copyWith(
                    color: accent ? BrandColors.accentDeep : BrandColors.text,
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

// ─────────────────────────────────────────────────────────────────────────────
// IntervalEditor — "working hours + breaks".
// ─────────────────────────────────────────────────────────────────────────────
class IntervalEditor extends StatelessWidget {
  const IntervalEditor({
    super.key,
    required this.day,
    required this.onChanged,
    required this.strings,
    this.fieldKeyPrefix,
  });

  /// The day's working window + breaks — mutated in place.
  final DayHours day;

  /// Called after any mutation so the host can `setState`.
  final VoidCallback onChanged;

  /// All localised copy, resolved by the host.
  final IntervalEditorStrings strings;

  /// When set, the working-window wells and add-break action get stable keys
  /// (`$prefix-work-start`, `$prefix-work-end`, `$prefix-add-break`) so widget
  /// tests can target a specific day's editor without relying on Ukrainian copy.
  final String? fieldKeyPrefix;

  Future<void> _pick(
    BuildContext context,
    TimeOfDay current,
    String title,
    ValueChanged<TimeOfDay> apply,
  ) async {
    final TimeOfDay? picked = await showVelvetTimePicker(
      context,
      current,
      title: title,
      confirmLabel: strings.timePickerConfirm,
      hoursSemanticLabel: strings.timePickerHoursSemantic,
      minutesSemanticLabel: strings.timePickerMinutesSemantic,
      minuteStep: 15,
    );
    if (picked != null) {
      apply(picked);
      onChanged();
    }
  }

  /// Seed length (minutes) for a freshly added break — a sensible 1h lunch.
  static const int _defaultBreakMinutes = 60;

  /// Minimum gap (minutes) left between the previous break and a new one, so the
  /// seed never lands flush against (and thus overlapping) an existing break.
  static const int _breakSeedGap = 15;

  /// `true` when there is room to seed another non-overlapping, in-bounds break
  /// after the latest existing break. Drives the add-break guard + disabled UX.
  bool get _hasRoomForBreak =>
      _nextBreakCursor() + _breakSeedGap + _defaultBreakMinutes <=
      day.window.endMinutes;

  /// Minute-of-day to seed the next break AFTER — the latest existing break's
  /// end, or the window start when there are no breaks yet.
  int _nextBreakCursor() {
    int cursor = day.window.startMinutes;
    for (final BreakRange b in day.breaks) {
      if (b.endMinutes > cursor) cursor = b.endMinutes;
    }
    return cursor;
  }

  void _addBreak() {
    final int winEnd = day.window.endMinutes;
    final int cursor = _nextBreakCursor();
    // Seed a small gap after the latest break (or window start), snapped to a
    // 15-min step, with a default 1h length, clamped to fit before window end.
    int start = cursor + _breakSeedGap;
    start = (start ~/ 15) * 15;
    int end = start + _defaultBreakMinutes;
    // No room for a non-overlapping, in-bounds break → no-op the tap rather than
    // appending a degenerate/overlapping range that would gate Save.
    if (end > winEnd) return;
    day.breaks.add(
      BreakRange(
        start: TimeOfDay(hour: start ~/ 60, minute: start % 60),
        end: TimeOfDay(hour: end ~/ 60, minute: end % 60),
      ),
    );
    onChanged();
  }

  void _removeBreak(BreakRange b) {
    day.breaks.remove(b);
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final DayHoursError? error = validateDayHours(day);
    final String? prefix = fieldKeyPrefix;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // ── Working window ──────────────────────────────────────────────────
        Text(strings.workHoursLabel, style: VelvetText.label()),
        const SizedBox(height: VelvetSpacing.sm),
        Row(
          children: <Widget>[
            Expanded(
              child: TimeWell(
                key: prefix == null ? null : Key('$prefix-work-start'),
                time: day.window.start,
                accent: true,
                hasError: error?.windowInvalid ?? false,
                onTap: () => _pick(
                  context,
                  day.window.start,
                  strings.workStartTitle,
                  (TimeOfDay t) => day.window.start = t,
                ),
                semanticLabel: strings.workStartTitle,
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: VelvetSpacing.sm),
              child: Text('–'),
            ),
            Expanded(
              child: TimeWell(
                key: prefix == null ? null : Key('$prefix-work-end'),
                time: day.window.end,
                accent: true,
                hasError: error?.windowInvalid ?? false,
                onTap: () => _pick(
                  context,
                  day.window.end,
                  strings.workEndTitle,
                  (TimeOfDay t) => day.window.end = t,
                ),
                semanticLabel: strings.workEndTitle,
              ),
            ),
          ],
        ),

        // ── Breaks ──────────────────────────────────────────────────────────
        if (day.breaks.isNotEmpty) ...<Widget>[
          const SizedBox(height: VelvetSpacing.md + 2),
          Text(strings.breaksLabel, style: VelvetText.label()),
          const SizedBox(height: VelvetSpacing.sm),
          for (int i = 0; i < day.breaks.length; i++)
            _BreakRow(
              range: day.breaks[i],
              index: i,
              hasError: error?.breakIndex == i,
              startSemanticLabel: strings.breakStartSemantic(i + 1),
              endSemanticLabel: strings.breakEndSemantic(i + 1),
              removeSemanticLabel: strings.removeBreakSemantic(i + 1),
              onPickStart: () => _pick(
                context,
                day.breaks[i].start,
                strings.breakStartTitle,
                (TimeOfDay t) => day.breaks[i].start = t,
              ),
              onPickEnd: () => _pick(
                context,
                day.breaks[i].end,
                strings.breakEndTitle,
                (TimeOfDay t) => day.breaks[i].end = t,
              ),
              onRemove: () => _removeBreak(day.breaks[i]),
            ),
        ],

        // ── Add-break action ────────────────────────────────────────────────
        // Disabled (dimmed, no tap) once the day is full — there's no room to
        // seed another non-overlapping, in-bounds break.
        const SizedBox(height: VelvetSpacing.md),
        Align(
          alignment: Alignment.centerLeft,
          child: Opacity(
            opacity: _hasRoomForBreak ? 1.0 : 0.4,
            child: Semantics(
              button: true,
              enabled: _hasRoomForBreak,
              label: strings.addBreak,
              child: GestureDetector(
                key: prefix == null ? null : Key('$prefix-add-break'),
                onTap: _hasRoomForBreak ? _addBreak : null,
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
                        Icons.coffee_rounded,
                        size: 16,
                        color: BrandColors.accentDeep,
                      ),
                      const SizedBox(width: VelvetSpacing.sm),
                      Text(strings.addBreak, style: VelvetText.link13),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

        // ── Inline validation ───────────────────────────────────────────────
        if (error != null) ...<Widget>[
          const SizedBox(height: VelvetSpacing.md),
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
                    strings.messageFor(error),
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

/// One break-range row — a camel-tinted "carved off-time" surface with
/// start/end wells and a remove affordance.
class _BreakRow extends StatelessWidget {
  const _BreakRow({
    required this.range,
    required this.index,
    required this.hasError,
    required this.startSemanticLabel,
    required this.endSemanticLabel,
    required this.removeSemanticLabel,
    required this.onPickStart,
    required this.onPickEnd,
    required this.onRemove,
  });

  final BreakRange range;
  final int index;
  final bool hasError;
  final String startSemanticLabel;
  final String endSemanticLabel;
  final String removeSemanticLabel;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: VelvetSpacing.sm),
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          VelvetSpacing.sm + 2,
          VelvetSpacing.sm + 2,
          VelvetSpacing.sm,
          VelvetSpacing.sm + 2,
        ),
        decoration: BoxDecoration(
          color: BrandColors.accent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(VelvetRadii.field),
          border: Border.all(
            color: hasError
                ? BrandColors.error
                : BrandColors.accent.withValues(alpha: 0.4),
            width: hasError ? 2 : 1,
          ),
        ),
        child: Row(
          children: <Widget>[
            const Icon(
              Icons.coffee_rounded,
              size: 16,
              color: BrandColors.accentDeep,
            ),
            const SizedBox(width: VelvetSpacing.sm),
            Expanded(
              child: TimeWell(
                time: range.start,
                onTap: onPickStart,
                semanticLabel: startSemanticLabel,
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: VelvetSpacing.sm - 2),
              child: Text('–'),
            ),
            Expanded(
              child: TimeWell(
                time: range.end,
                onTap: onPickEnd,
                semanticLabel: endSemanticLabel,
              ),
            ),
            const SizedBox(width: VelvetSpacing.sm - 2),
            Semantics(
              button: true,
              label: removeSemanticLabel,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  height: 38,
                  width: 38,
                  decoration: const BoxDecoration(
                    color: BrandColors.base,
                    shape: BoxShape.circle,
                    boxShadow: VelvetShadows.extrudedSmall,
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 18,
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
