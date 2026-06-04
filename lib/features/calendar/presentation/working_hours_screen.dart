// Phase 6.2 — Working Hours Screen.
//
// Ported verbatim from the approved preview app at
// `docs/signup-designs/WorkingHoursScreen/lib/screens/working_hours_screen.dart`
// and `…/widgets/day_row.dart`.  The preview's standalone tokens (VelvetColors,
// VelvetText, VelvetSpacing, etc.) are replaced 1:1 by the production
// equivalents from `lib/core/theme/`.  The `DayHours` mutable model is
// replaced by the freezed `WorkingHours` domain entity.  Local state uses
// `ConsumerStatefulWidget`; save calls
// `ref.read(workingHoursProvider.notifier).save(…)`.
//
// Layout fidelity contract (design → production mapping):
//   - NeumorphicCard          → lib/core/widgets/neumorphic.dart NeumorphicCard
//   - NeumorphicInset         → lib/core/widgets/neumorphic.dart NeumorphicInset
//   - NeumorphicButton        → lib/core/widgets/neumorphic.dart NeumorphicButton
//   - VelvetColors.*          → BrandColors.*
//   - VelvetText.*()          → VelvetText.*() (same class name in production)
//   - VelvetSpacing.*         → VelvetSpacing.* (same class name in production)
//   - VelvetShadows.*         → VelvetShadows.*
//   - VelvetSizes.*           → VelvetSizes.*
//   - VelvetRadii.*           → VelvetRadii.*
//   - AuthScaffold (preview)  → Scaffold + SafeArea (no AuthScaffold in master flow)
//
// CROSS-MIDNIGHT CONSTRAINT: the schedule model forbids cross-midnight intervals.
// Per-day validation is therefore `end > start` only — no cross-midnight path.

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/calendar/domain/working_hours.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

import 'working_hours_notifier.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Formats a [TimeOfDay] as `HH:MM` (zero-padded, 24 h).
String _formatTime(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Returns the total minutes since midnight for a [TimeOfDay].
int _toMinutes(TimeOfDay t) => t.hour * 60 + t.minute;

/// Whether this [WorkingHours] row has a validation error (end ≤ start).
/// Cross-midnight is forbidden by the schedule model — the only valid state
/// is end > start.
bool _rowHasError(WorkingHours h) =>
    h.isActive && _toMinutes(h.end) <= _toMinutes(h.start);

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

/// Weekly grid editor: one neumorphic row per ISO day of week (Mon–Sun), each
/// with an open/closed toggle and start–end time pickers.  A single Save CTA
/// persists all seven days atomically via [WorkingHoursNotifier.save].
class WorkingHoursScreen extends ConsumerStatefulWidget {
  const WorkingHoursScreen({super.key});

  @override
  ConsumerState<WorkingHoursScreen> createState() => _WorkingHoursScreenState();
}

class _WorkingHoursScreenState extends ConsumerState<WorkingHoursScreen> {
  static const _tag = 'feature.calendar.workinghoursscreen';

  /// Local draft. Initialised once from the notifier state, then edited
  /// locally until the user presses Save.  Never null after [_initDraft]
  /// is called (which happens as soon as the provider resolves).
  List<WorkingHours>? _draft;

  /// Whether a save is in flight.
  bool _saving = false;

  // Computed from _draft.
  bool get _hasErrors => _draft?.any(_rowHasError) ?? false;
  bool get _isDirty => _draft != null;
  bool get _canSave => _isDirty && !_hasErrors && !_saving;

  int get _openCount =>
      _draft?.where((WorkingHours h) => h.isActive).length ?? 0;

  /// Copies the notifier's loaded list into [_draft].  Called exactly once
  /// after the first successful load; subsequent notifier rebuilds do NOT
  /// reset the draft (the user's in-progress edits are preserved).
  void _initDraft(List<WorkingHours> serverList) {
    if (_draft != null) return;
    setState(() => _draft = List<WorkingHours>.of(serverList));
  }

  // ---------------------------------------------------------------------------
  // Time picker helpers
  // ---------------------------------------------------------------------------

  /// Shows a [showTimePicker] dialog themed to the VelvetTouch palette.
  Future<TimeOfDay?> _showTimePicker(TimeOfDay initial) {
    return showTimePicker(
      context: context,
      initialTime: initial,
      initialEntryMode: TimePickerEntryMode.dial,
      builder: (BuildContext ctx, Widget? child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: ColorScheme.fromSeed(
              seedColor: BrandColors.accentDeep,
              brightness: Brightness.light,
              primary: BrandColors.accentDeep,
              onPrimary: BrandColors.white,
              surface: BrandColors.base,
              onSurface: BrandColors.text,
            ),
            timePickerTheme: const TimePickerThemeData(
              backgroundColor: BrandColors.base,
              hourMinuteColor: BrandColors.shadowLightStrong,
              dialBackgroundColor: BrandColors.shadowLightStrong,
              dialHandColor: BrandColors.accent,
              entryModeIconColor: BrandColors.accentDeep,
            ),
          ),
          child: child!,
        );
      },
    );
  }

  Future<void> _pickStart(int index) async {
    final WorkingHours current = _draft![index];
    final TimeOfDay? picked = await _showTimePicker(current.start);
    if (picked == null || !mounted) return;
    setState(() {
      _draft![index] = current.copyWith(
        startTime: WorkingHours.fromTimeOfDay(picked),
      );
    });
  }

  Future<void> _pickEnd(int index) async {
    final WorkingHours current = _draft![index];
    final TimeOfDay? picked = await _showTimePicker(current.end);
    if (picked == null || !mounted) return;
    setState(() {
      _draft![index] = current.copyWith(
        endTime: WorkingHours.fromTimeOfDay(picked),
      );
    });
  }

  void _toggleDay(int index, bool open) {
    setState(() {
      _draft![index] = _draft![index].copyWith(isActive: open);
    });
  }

  // ---------------------------------------------------------------------------
  // Save handler
  // ---------------------------------------------------------------------------

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
    if (kDebugMode) {
      log(
        'save: committing ${_draft!.length} day entries',
        name: _tag,
        level: 800,
      );
    }
    try {
      await ref.read(workingHoursProvider.notifier).save(_draft!);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.savedSnackbar)));
    } on ValidationFailure catch (f) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: BrandColors.error,
          content: Text(f.userMessage(context)),
        ),
      );
    } on Failure catch (f) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: BrandColors.error,
          content: Text(f.userMessage(context)),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // Watch the notifier — handles loading / error states and seeds the draft.
    final asyncWeek = ref.watch(workingHoursProvider);

    return Scaffold(
      backgroundColor: BrandColors.base,
      appBar: AppBar(
        backgroundColor: BrandColors.base,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(l10n.workingHoursTitle, style: VelvetText.subheading()),
        leading: NeumorphicIconButton(
          icon: Icons.arrow_back_ios_new_rounded,
          onTap: () => Navigator.of(context).pop(),
          semanticLabel: l10n.registerBackStep,
        ),
      ),
      body: asyncWeek.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: BrandColors.accent),
        ),
        error: (e, _) => _ErrorBody(
          failure: e,
          onRetry: () => ref.invalidate(workingHoursProvider),
        ),
        data: (List<WorkingHours> serverList) {
          _initDraft(serverList);
          final List<WorkingHours> draft = _draft!;
          return _LoadedBody(
            draft: draft,
            openCount: _openCount,
            hasErrors: _hasErrors,
            canSave: _canSave,
            saving: _saving,
            l10n: l10n,
            onToggle: _toggleDay,
            onPickStart: _pickStart,
            onPickEnd: _pickEnd,
            onSave: _save,
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loaded body — extracted widget so the hot-reload subtree is minimal.
// ---------------------------------------------------------------------------

class _LoadedBody extends StatelessWidget {
  const _LoadedBody({
    required this.draft,
    required this.openCount,
    required this.hasErrors,
    required this.canSave,
    required this.saving,
    required this.l10n,
    required this.onToggle,
    required this.onPickStart,
    required this.onPickEnd,
    required this.onSave,
  });

  final List<WorkingHours> draft;
  final int openCount;
  final bool hasErrors;
  final bool canSave;
  final bool saving;
  final AppLocalizations l10n;
  final void Function(int index, bool open) onToggle;
  final Future<void> Function(int index) onPickStart;
  final Future<void> Function(int index) onPickEnd;
  final Future<void> Function() onSave;

  // ---------------------------------------------------------------------------
  // ListView.builder item model (lazy, O(1) build per visible item):
  //   index 0             → title block
  //   index 1             → open-days summary chip
  //   index 2             → spacer (lg)
  //   index 3 + i*2       → _DayRow for draft[i]   (i = 0..6)
  //   index 3 + i*2 + 1   → separator spacer        (i = 0..5 only)
  //   index 3 + 7*2 - 1   → trailing xl spacer (last entry)
  //
  // Total items = 3 (header) + 7 rows + 6 separators + 1 trailing = 17.
  static const int _headerItemCount = 3;
  static const int _dayCount = 7;

  // Total fixed item count:  header (3) + days (7) + separators (6) + trailing (1) = 17.
  static const int _totalItemCount = _headerItemCount + _dayCount * 2 - 1 + 1;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: <Widget>[
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(
                horizontal: VelvetSpacing.md,
                vertical: VelvetSpacing.md,
              ),
              itemCount: _totalItemCount,
              itemBuilder: (BuildContext ctx, int index) {
                // ── Header items ────────────────────────────────────────────
                if (index == 0) {
                  // Title block.
                  return Center(
                    child: Column(
                      children: <Widget>[
                        Text(
                          l10n.workingHoursTitle,
                          style: VelvetText.heading(),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: VelvetSpacing.sm),
                        Text(
                          l10n.workingHoursSubtext,
                          style: VelvetText.body(),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }
                if (index == 1) {
                  // Open-days summary chip.
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: VelvetSpacing.md),
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
                              l10n.workingHoursOpenCount(openCount),
                              style: VelvetText.bodyStrong().copyWith(
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }
                if (index == 2) {
                  // Spacer between chip and first day row.
                  return const SizedBox(height: VelvetSpacing.lg);
                }

                // ── Day rows and separators ─────────────────────────────────
                final int bodyIndex = index - _headerItemCount;
                // Last item (index 16 = 3 + 7*2 - 1) is the trailing spacer.
                if (index == _totalItemCount - 1) {
                  return const SizedBox(height: VelvetSpacing.xl);
                }
                // Even bodyIndex → day row; odd → separator spacer.
                final int dayIndex = bodyIndex ~/ 2;
                final bool isSeparator = bodyIndex.isOdd;
                if (isSeparator) {
                  return const SizedBox(height: VelvetSpacing.md);
                }
                final WorkingHours hours = draft[dayIndex];
                return _DayRow(
                  key: ValueKey<int>(hours.dayOfWeek),
                  hours: hours,
                  dayLabel: _dayLabel(l10n, hours.dayOfWeek),
                  hasError: _rowHasError(hours),
                  errEndAfterStart: l10n.errEndAfterStart,
                  closedLabel: l10n.workingHoursClosedLabel,
                  activeLabel: l10n.workingHoursActiveLabel,
                  startSemanticLabel: l10n.workingHoursStartSemanticLabel,
                  endSemanticLabel: l10n.workingHoursEndSemanticLabel,
                  dayToggleSemanticLabel: l10n.workingHoursDayToggleSemantic(
                    _dayLabel(l10n, hours.dayOfWeek),
                  ),
                  onToggle: (bool open) => onToggle(dayIndex, open),
                  onPickStart: () => onPickStart(dayIndex),
                  onPickEnd: () => onPickEnd(dayIndex),
                );
              },
            ),
          ),
          // Bottom CTA — always visible above keyboard.
          Padding(
            padding: const EdgeInsets.fromLTRB(
              VelvetSpacing.md,
              0,
              VelvetSpacing.md,
              VelvetSpacing.md,
            ),
            child: NeumorphicButton(
              key: const Key('btn-save-working-hours'),
              label: l10n.step3CtaSave,
              icon: Icons.check_rounded,
              loading: saving,
              onPressed: canSave ? onSave : null,
            ),
          ),
        ],
      ),
    );
  }

  /// Maps ISO dayOfWeek (1 = Mon … 7 = Sun) to the localised day name.
  static String _dayLabel(AppLocalizations l10n, int dow) {
    switch (dow) {
      case 1:
        return l10n.weekdayMon;
      case 2:
        return l10n.weekdayTue;
      case 3:
        return l10n.weekdayWed;
      case 4:
        return l10n.weekdayThu;
      case 5:
        return l10n.weekdayFri;
      case 6:
        return l10n.weekdaySat;
      case 7:
        return l10n.weekdaySun;
      default:
        return '?';
    }
  }
}

// ---------------------------------------------------------------------------
// Error body.
// ---------------------------------------------------------------------------

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.failure, required this.onRetry});

  final Object failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String message = failure is Failure
        ? (failure as Failure).userMessage(context)
        : l10n.errUnknown;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(VelvetSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              message,
              style: VelvetText.body(),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: VelvetSpacing.md),
            NeumorphicButton(label: l10n.retryLabel, onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// NeumorphicToggle — pill-style open/closed toggle.
// Ported verbatim from docs/signup-designs/WorkingHoursScreen/lib/widgets/day_row.dart.
// ---------------------------------------------------------------------------

class _NeumorphicToggle extends StatelessWidget {
  const _NeumorphicToggle({
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
              // Inset track — recessed well; tints camel when active.
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
              // Extruded thumb — slides left/right.
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

// ---------------------------------------------------------------------------
// _TimeWell — tappable inset time display.
// Ported verbatim from docs/signup-designs/WorkingHoursScreen/lib/widgets/day_row.dart.
// ---------------------------------------------------------------------------

class _TimeWell extends StatelessWidget {
  const _TimeWell({
    required this.widgetKey,
    required this.time,
    required this.onTap,
    required this.enabled,
    required this.hasError,
    required this.semanticLabel,
  });

  final Key widgetKey;
  final TimeOfDay time;
  final VoidCallback onTap;
  final bool enabled;
  final bool hasError;
  final String semanticLabel;

  // Hoisted to avoid TextStyle allocation per build.
  static final TextStyle _enabledStyle = VelvetText.input().copyWith(
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
  );
  static final TextStyle _disabledStyle = VelvetText.input().copyWith(
    color: BrandColors.faint,
  );

  @override
  Widget build(BuildContext context) {
    final TextStyle textStyle = enabled ? _enabledStyle : _disabledStyle;

    final Widget well = NeumorphicInset(
      hasError: enabled && hasError,
      child: SizedBox(
        height: 46,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              Icons.schedule_rounded,
              size: 17,
              color: enabled ? BrandColors.muted : BrandColors.faint,
            ),
            const SizedBox(width: VelvetSpacing.sm),
            Text(_formatTime(time), style: textStyle),
          ],
        ),
      ),
    );

    return Semantics(
      button: enabled,
      enabled: enabled,
      label: '$semanticLabel ${_formatTime(time)}',
      child: GestureDetector(
        key: widgetKey,
        onTap: enabled ? onTap : null,
        child: Opacity(opacity: enabled ? 1 : 0.5, child: well),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _DayRow — one neumorphic card per ISO day.
// Ported verbatim from docs/signup-designs/WorkingHoursScreen/lib/widgets/day_row.dart.
// ---------------------------------------------------------------------------

class _DayRow extends StatelessWidget {
  const _DayRow({
    super.key,
    required this.hours,
    required this.dayLabel,
    required this.hasError,
    required this.errEndAfterStart,
    required this.closedLabel,
    required this.activeLabel,
    required this.startSemanticLabel,
    required this.endSemanticLabel,
    required this.dayToggleSemanticLabel,
    required this.onToggle,
    required this.onPickStart,
    required this.onPickEnd,
  });

  final WorkingHours hours;
  final String dayLabel;
  final bool hasError;
  final String errEndAfterStart;
  final String closedLabel;
  final String activeLabel;
  final String startSemanticLabel;
  final String endSemanticLabel;
  final String dayToggleSemanticLabel;
  final ValueChanged<bool> onToggle;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;

  // Hoisted styles — avoids copyWith() per build.
  static final TextStyle _activeDayStyle = VelvetText.subheading();
  static final TextStyle _inactiveDayStyle = VelvetText.subheading().copyWith(
    color: BrandColors.muted,
  );
  static final TextStyle _activeStatusStyle = VelvetText.label().copyWith(
    color: BrandColors.accentDeep,
  );
  static final TextStyle _inactiveStatusStyle = VelvetText.label().copyWith(
    color: BrandColors.muted,
  );
  static final TextStyle _closedBodyStyle = VelvetText.body().copyWith(
    color: BrandColors.muted,
  );

  @override
  Widget build(BuildContext context) {
    final int dow = hours.dayOfWeek;
    return NeumorphicCard(
      padding: const EdgeInsets.symmetric(
        horizontal: VelvetSpacing.md + 2,
        vertical: VelvetSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  dayLabel,
                  style: hours.isActive ? _activeDayStyle : _inactiveDayStyle,
                ),
              ),
              Text(
                hours.isActive ? activeLabel : closedLabel,
                style: hours.isActive
                    ? _activeStatusStyle
                    : _inactiveStatusStyle,
              ),
              const SizedBox(width: VelvetSpacing.sm + 2),
              _NeumorphicToggle(
                key: Key('wh-active-$dow'),
                value: hours.isActive,
                onChanged: onToggle,
                semanticLabel: dayToggleSemanticLabel,
              ),
            ],
          ),
          const SizedBox(height: VelvetSpacing.md),
          if (hours.isActive)
            Row(
              children: <Widget>[
                Expanded(
                  child: _TimeWell(
                    widgetKey: Key('wh-start-$dow'),
                    time: hours.start,
                    onTap: onPickStart,
                    enabled: true,
                    hasError: hasError,
                    semanticLabel: startSemanticLabel,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: VelvetSpacing.sm + 2,
                  ),
                  child: Text('–', style: VelvetText.body()),
                ),
                Expanded(
                  child: _TimeWell(
                    widgetKey: Key('wh-end-$dow'),
                    time: hours.end,
                    onTap: onPickEnd,
                    enabled: true,
                    hasError: hasError,
                    semanticLabel: endSemanticLabel,
                  ),
                ),
              ],
            )
          else
            Row(
              children: <Widget>[
                const Icon(
                  Icons.bedtime_outlined,
                  size: 17,
                  color: BrandColors.faint,
                ),
                const SizedBox(width: VelvetSpacing.sm),
                Text(closedLabel, style: _closedBodyStyle),
              ],
            ),
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
                      errEndAfterStart,
                      style: VelvetText.feedback(BrandColors.error),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
