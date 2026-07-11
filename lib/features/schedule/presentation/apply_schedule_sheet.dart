// Phase 15.5 — ApplyScheduleSheet («Період дії графіка»).
//
// The Propagate / active-window surface: the master sets the weekly template's
// VALIDITY WINDOW (`validFrom` / `validTo`) for a chosen period — via a quick
// preset («Весь поточний місяць / Наступні 3 місяці / Весь рік») or a custom
// range from the [PeriodRangePicker] — and «Застосувати» persists it.
//
// LOCKED CONTRACT (phase doc line 4): applying a range SETS the schedule's
// window via `upsertWeeklySchedule`; it does NOT materialise per-date
// `ScheduleException` override rows. So the sheet rebuilds the active
// [WeeklySchedule] with the chosen `validFrom`/`validTo` (preserving its seven
// `days`) and calls `WeeklyScheduleNotifier.save(scheduleId: ...)` → which hits
// `POST/PUT /masters/{id}/weekly-schedules`. That notifier already invalidates
// the whole `effectiveScheduleProvider` family on success, so the
// Master-Schedule calendar repaints against the new window with no manual
// refresh (Phase 15.5 cache-invalidation requirement).
//
// DATE MATH mirrors the backend `ScheduleDateMath` (Phase 15.3) via the Dart
// [ScheduleDateMath] util: clamped preset ranges, a `today + 2 years` cap, and
// leap-year Feb-29 clamping — so the client never sends a range the backend
// would reject for being too far out.
//
// OVERLAP REJECTION (Phase 15.4): the backend rejects a window that overlaps an
// existing one with a 400 `BusinessException` (mapped client-side to a
// `ValidationFailure`). The backend `GlobalExceptionHandler` masks the detailed
// message to a generic "Invalid request", so the sheet surfaces a LOCALIZED
// inline overlap error card above the CTA — never a silent overwrite, never a
// raw server string.
//
// Ported from the approved preview app at
// `docs/signup-designs/MasterSchedule/lib/screens/weekly_template_editor.dart`
// (`_ActivePeriodSheet` + `_PresetChip`), adapted to Riverpod + the project's
// tokens; the preview's placeholder SnackBar confirm is replaced by the real
// notifier save + inline error handling.

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

import '../domain/schedule_date_math.dart';
import '../domain/schedule_model.dart' show formatDay;
import '../domain/weekly_schedule.dart';
import 'period_range_picker.dart';
import 'weekly_schedule_notifier.dart';

/// Opens the «Період дії графіка» sheet. The result depends on whether the
/// [baseSchedule] is already persisted:
///
///   • EXISTING template (`baseSchedule.id != null`) — the live window-change
///     path: applying PERSISTS the new window immediately and resolves to
///     `true` on success, `false`/`null` when dismissed without saving.
///   • FIRST CREATE (`baseSchedule.id == null`) — nothing is persisted here.
///     The chosen window is returned as a [DateTimeRange] for the editor to
///     stage as a local draft (its Save button is the single commit point);
///     resolves to `null` when dismissed without choosing.
///
/// [baseSchedule] is the active weekly template whose window is being set; its
/// `days` are preserved verbatim — only `validFrom`/`validTo` change. [today]
/// is the injectable wall-clock anchor for the presets / cap.
Future<Object?> showApplyScheduleSheet(
  BuildContext context, {
  required WeeklySchedule baseSchedule,
  required DateTime today,
}) {
  return showModalBottomSheet<Object?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: BrandColors.base,
    barrierColor: BrandColors.text.withValues(alpha: 0.35),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(VelvetRadii.card),
      ),
    ),
    builder: (BuildContext sheetContext) =>
        ApplyScheduleSheet(baseSchedule: baseSchedule, today: today),
  );
}

/// The «Період дії графіка» bottom-sheet body.
class ApplyScheduleSheet extends ConsumerStatefulWidget {
  const ApplyScheduleSheet({
    super.key,
    required this.baseSchedule,
    required this.today,
  });

  /// The active template whose validity window is being set; `days` preserved.
  final WeeklySchedule baseSchedule;

  /// Injectable "now" (date-only) anchoring the presets and far-future cap.
  final DateTime today;

  @override
  ConsumerState<ApplyScheduleSheet> createState() => _ApplyScheduleSheetState();
}

class _ApplyScheduleSheetState extends ConsumerState<ApplyScheduleSheet> {
  static const _tag = 'feature.schedule.apply';

  late final ScheduleDateMath _math = ScheduleDateMath(today: widget.today);

  /// The currently-chosen window (preset or custom), or null until picked.
  DateTimeRange? _range;

  bool _saving = false;

  /// Set when the last apply was rejected for overlapping an existing window
  /// (or any validation error) — surfaced inline above the CTA. Cleared the
  /// moment the user picks a new range.
  String? _inlineError;

  @override
  void initState() {
    super.initState();
    _range = _seedRangeFromSchedule();
  }

  /// Seed the sheet from the template's existing window so re-opening shows it
  /// pre-selected. A null `validTo` (open-ended) is clamped to the far-future
  /// cap so the readout/picker always shows a concrete end.
  DateTimeRange? _seedRangeFromSchedule() {
    final WeeklySchedule s = widget.baseSchedule;
    final DateTime from = _dateOnly(s.validFrom);
    // A past `validFrom` (legacy window) is clamped to today so the picker —
    // whose first selectable day is today — can render it.
    final DateTime start = from.isBefore(_math.today) ? _math.today : from;
    final DateTime end = s.validTo == null
        ? _math.cap()
        : _dateOnly(s.validTo!);
    if (end.isBefore(start)) return null;
    return DateTimeRange(start: start, end: end);
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  int? get _dayCount => _range?.let((DateTimeRange r) => r.duration.inDays + 1);

  bool get _hasRange => _range != null;

  // ── Preset ranges (mirror backend ScheduleDateMath) ──────────────────────
  DateTimeRange get _thisMonth {
    final ScheduleRangeDates r = _math.wholeCurrentMonth();
    return DateTimeRange(start: r.start, end: r.end);
  }

  DateTimeRange get _nextThreeMonths {
    final ScheduleRangeDates r = _math.nextNMonths(3);
    return DateTimeRange(start: r.start, end: _math.clampToCap(r.end));
  }

  DateTimeRange get _wholeYear {
    final ScheduleRangeDates r = _math.wholeYear();
    return DateTimeRange(start: r.start, end: r.end);
  }

  bool _sameRange(DateTimeRange a, DateTimeRange? b) =>
      b != null && _sameDay(a.start, b.start) && _sameDay(a.end, b.end);

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _applyPreset(DateTimeRange range) {
    setState(() {
      _range = range;
      _inlineError = null;
    });
  }

  Future<void> _pickRange() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final DateTimeRange? picked = await showPeriodRangePicker(
      context,
      firstMonth: DateTime(widget.today.year, widget.today.month),
      firstSelectableDay: _math.today,
      initialRange: _range,
      strings: PeriodRangePickerStrings(
        title: l10n.rangePickerTitle,
        emptyHint: l10n.rangePickerEmptyHint,
        saveLabel: l10n.step3CtaSave,
        backSemantic: l10n.registerBackStep,
        weekdayShort: <String>[
          l10n.weekdayShortMon,
          l10n.weekdayShortTue,
          l10n.weekdayShortWed,
          l10n.weekdayShortThu,
          l10n.weekdayShortFri,
          l10n.weekdayShortSat,
          l10n.weekdayShortSun,
        ],
      ),
    );
    if (!mounted || picked == null) return;
    setState(() {
      // Clamp the custom end to the far-future cap so an over-long selection
      // never reaches the backend as a guaranteed 400.
      _range = DateTimeRange(
        start: _dateOnly(picked.start),
        end: _math.clampToCap(picked.end),
      );
      _inlineError = null;
    });
  }

  /// Builds the active template with the chosen window and saves it, surfacing
  /// an overlap/validation rejection inline (never a silent overwrite).
  ///
  /// FIRST CREATE (`baseSchedule.id == null`): does NOT persist. The chosen
  /// window is returned to the editor as a [DateTimeRange] draft — the editor's
  /// Save button is the single commit point on first create, so applying a
  /// window here must not write to the provider or invalidate the calendar.
  Future<void> _apply() async {
    final DateTimeRange? range = _range;
    if (range == null) return;

    // First-create: stage the window as a draft, no persist.
    if (widget.baseSchedule.id == null) {
      if (kDebugMode) {
        log(
          'apply: first-create → return draft window '
          '${range.start} → ${range.end} (no persist)',
          name: _tag,
          level: 800,
        );
      }
      context.pop<DateTimeRange>(
        DateTimeRange(start: _dateOnly(range.start), end: _dateOnly(range.end)),
      );
      return;
    }

    final AppLocalizations l10n = AppLocalizations.of(context);

    setState(() {
      _saving = true;
      _inlineError = null;
    });

    final WeeklySchedule updated = widget.baseSchedule.copyWith(
      validFrom: _dateOnly(range.start),
      validTo: _dateOnly(range.end),
    );

    if (kDebugMode) {
      log(
        'apply: set window ${range.start} → ${range.end} '
        'scheduleId=${widget.baseSchedule.id}',
        name: _tag,
        level: 800,
      );
    }

    final WeeklyScheduleNotifier notifier = ref.read(
      weeklyScheduleProvider.notifier,
    );
    await notifier.save(updated, scheduleId: widget.baseSchedule.id);

    if (!mounted) return;

    // `save` wraps its work in `AsyncValue.guard`, so a rejected window does NOT
    // throw — it lands as an [AsyncError] on the provider state. Branch on it:
    // surface the overlap/validation error inline and DO NOT close the sheet.
    final AsyncValue<List<WeeklySchedule>> result = ref.read(
      weeklyScheduleProvider,
    );
    if (result.hasError) {
      setState(() {
        _saving = false;
        _inlineError = _errorMessage(result.error, l10n);
      });
      return;
    }

    // Applied — the notifier already invalidated `effectiveScheduleProvider`,
    // so the calendar repaints. Close with `true`.
    context.pop<bool>(true);
  }

  /// A localized inline message for a save rejection. A [ValidationFailure]
  /// (the backend's 400 window-overlap) maps to the dedicated overlap copy —
  /// the backend masks its detailed message, so the client owns the wording.
  String _errorMessage(Object? error, AppLocalizations l10n) {
    if (error is ValidationFailure) return l10n.applyScheduleOverlapError;
    if (error is Failure) return error.userMessage(context);
    return l10n.errUnknown;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final double bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
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
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: BrandColors.faint,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: VelvetSpacing.md),
              Row(
                children: <Widget>[
                  const Icon(
                    Icons.date_range_rounded,
                    size: 20,
                    color: BrandColors.accentDeep,
                  ),
                  const SizedBox(width: VelvetSpacing.sm),
                  Expanded(
                    child: Text(
                      l10n.applyScheduleTitle,
                      style: VelvetText.subheading(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: VelvetSpacing.sm),
              Text(l10n.applyScheduleBody, style: VelvetText.body13),
              const SizedBox(height: VelvetSpacing.md + 2),

              // ── Quick-pick presets ─────────────────────────────────────────
              Text(l10n.applyScheduleQuickPick, style: VelvetText.label()),
              const SizedBox(height: VelvetSpacing.sm),
              Wrap(
                spacing: VelvetSpacing.sm,
                runSpacing: VelvetSpacing.sm,
                children: <Widget>[
                  _PresetChip(
                    key: const Key('preset-this-month'),
                    label: l10n.applySchedulePresetThisMonth,
                    selected: _sameRange(_thisMonth, _range),
                    onTap: () => _applyPreset(_thisMonth),
                  ),
                  _PresetChip(
                    key: const Key('preset-next-3-months'),
                    label: l10n.applySchedulePresetNextThreeMonths,
                    selected: _sameRange(_nextThreeMonths, _range),
                    onTap: () => _applyPreset(_nextThreeMonths),
                  ),
                  _PresetChip(
                    key: const Key('preset-whole-year'),
                    label: l10n.applySchedulePresetWholeYear,
                    selected: _sameRange(_wholeYear, _range),
                    onTap: () => _applyPreset(_wholeYear),
                  ),
                ],
              ),
              const SizedBox(height: VelvetSpacing.lg),

              // ── Manual range well ──────────────────────────────────────────
              Text(l10n.applySchedulePeriodLabel, style: VelvetText.label()),
              const SizedBox(height: VelvetSpacing.sm),
              GestureDetector(
                key: const Key('apply-schedule-date-well'),
                onTap: _saving ? null : _pickRange,
                child: NeumorphicInset(
                  child: SizedBox(
                    height: VelvetSizes.field,
                    child: Row(
                      children: <Widget>[
                        const SizedBox(width: VelvetSpacing.md),
                        const Icon(
                          Icons.event_rounded,
                          size: 20,
                          color: BrandColors.muted,
                        ),
                        const SizedBox(width: VelvetSpacing.sm),
                        Expanded(
                          child: Text(
                            _hasRange
                                ? '${formatDay(_range!.start)} — '
                                      '${formatDay(_range!.end)}'
                                : l10n.applyScheduleRangePlaceholder,
                            style: _hasRange
                                ? VelvetText.input()
                                : VelvetText.input().copyWith(
                                    color: BrandColors.placeholder,
                                  ),
                          ),
                        ),
                        const SizedBox(width: VelvetSpacing.sm),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 22,
                          color: BrandColors.muted,
                        ),
                        const SizedBox(width: VelvetSpacing.sm),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Live day-count readout ─────────────────────────────────────
              if (_hasRange) ...<Widget>[
                const SizedBox(height: VelvetSpacing.md),
                Center(
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
                          Icons.event_available_rounded,
                          size: 18,
                          color: BrandColors.accent,
                        ),
                        const SizedBox(width: VelvetSpacing.sm),
                        Text(
                          l10n.applyScheduleDayCount(_dayCount!),
                          style: VelvetText.bodyStrong13,
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              // ── Inline overlap / validation error ──────────────────────────
              if (_inlineError != null) ...<Widget>[
                const SizedBox(height: VelvetSpacing.md),
                _InlineErrorCard(
                  key: const Key('apply-schedule-error'),
                  message: _inlineError!,
                ),
              ],

              const SizedBox(height: VelvetSpacing.lg),
              Opacity(
                opacity: _hasRange ? 1 : 0.55,
                child: IgnorePointer(
                  ignoring: !_hasRange,
                  child: NeumorphicButton(
                    key: const Key('btn-apply-schedule'),
                    label: l10n.applyScheduleCta,
                    icon: Icons.check_rounded,
                    loading: _saving,
                    onPressed: _saving ? null : _apply,
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

/// A neumorphic quick-pick chip for the period presets. Extruded when idle,
/// camel-tinted inset when [selected].
class _PresetChip extends StatelessWidget {
  const _PresetChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(
            horizontal: VelvetSpacing.md,
            vertical: VelvetSpacing.sm + 2,
          ),
          decoration: BoxDecoration(
            color: selected
                ? BrandColors.accent.withValues(alpha: 0.28)
                : BrandColors.base,
            borderRadius: BorderRadius.circular(VelvetRadii.field),
            border: Border.all(
              color: selected
                  ? BrandColors.accent
                  : BrandColors.faint.withValues(alpha: 0.5),
              width: selected ? 1.4 : 1,
            ),
            boxShadow: selected ? null : VelvetShadows.extrudedSmall,
          ),
          child: Text(
            label,
            style: VelvetText.label().copyWith(
              color: selected ? BrandColors.accentDeep : BrandColors.muted,
            ),
          ),
        ),
      ),
    );
  }
}

/// An inline, neumorphic error card surfaced above the CTA when a window apply
/// is rejected (e.g. the backend overlap guard). Error-tinted, never a silent
/// overwrite.
class _InlineErrorCard extends StatelessWidget {
  const _InlineErrorCard({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: VelvetSpacing.md,
        vertical: VelvetSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: BrandColors.error.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(VelvetRadii.field),
        border: Border.all(color: BrandColors.error.withValues(alpha: 0.55)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: BrandColors.error,
          ),
          const SizedBox(width: VelvetSpacing.sm),
          Expanded(
            child: Text(message, style: VelvetText.feedback(BrandColors.error)),
          ),
        ],
      ),
    );
  }
}

/// Small null-safe `let` helper (Kotlin-style) for the optional day-count.
extension _LetExtension<T> on T {
  R let<R>(R Function(T) op) => op(this);
}
