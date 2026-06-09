// Phase 15.5 — WeeklyTemplateEditorScreen («Робочі дні та години»).
//
// THE real weekly-template editor — it replaces the Phase 15.2
// `WeeklyTemplateEditorStubScreen` at the same route
// (`RouteNames.scheduleWeeklyEditor`), mirroring how `/done` graduated from a
// placeholder to the real `DoneScreen`. Reached from the Master-Schedule
// screen's empty-state CTA and its «Редагувати» affordances.
//
// Ported from the approved preview app at
// `docs/signup-designs/MasterSchedule/lib/screens/weekly_template_editor.dart`
// (`WeeklyTemplateEditor`), adapted to the project's Riverpod + go_router
// structure:
//   • preview StatefulWidget + Navigator        → ConsumerStatefulWidget + go_router
//   • preview in-memory `_days`/`_stash` sample  → seeded from the real
//     `weeklyScheduleProvider` (Phase 15.1) loaded list
//   • preview placeholder SnackBar save          → `WeeklyScheduleNotifier.save` /
//     `.delete` against `POST/PUT/DELETE /masters/{id}/weekly-schedules`
//   • preview tokens (Velvet*)                   → BrandColors / VelvetText / Velvet*
//
// SAVE → CALENDAR REPAINT: `WeeklyScheduleNotifier.save` / `.delete` already
// invalidate the whole `effectiveScheduleProvider` family on success, so the
// Master-Schedule calendar re-fetches and repaints with no manual refresh.
//
// CROSS-MIDNIGHT: the Phase 15.x model forbids cross-midnight intervals. Every
// day collapses to a `List<WorkInterval>` via `DayHours.toIntervals()` whose
// every interval has `end > start`; the editor never emits `end <= start`
// (inline validation blocks Save while any window/break is inverted).
//
// ACTIVE WINDOW: the editor preserves the loaded template's `validFrom`/`validTo`
// (open-ended `validTo == null` for a fresh create, anchored at the injectable
// `today`). The active-window card is informational here; editing the validity
// window via the range picker is a later phase (the preview's PeriodRangePicker
// is not yet ported).

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
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/velvet_top_bar.dart';

import '../domain/schedule_model.dart';
import '../domain/weekly_schedule.dart';
import 'weekly_schedule_notifier.dart';
import 'widgets/interval_editor.dart';

/// Number of ISO days in a week.
const int _kDaysInWeek = 7;

/// The full-screen weekly-template editor.
class WeeklyTemplateEditorScreen extends ConsumerStatefulWidget {
  const WeeklyTemplateEditorScreen({super.key, DateTime? clock})
    : _clock = clock;

  /// Injectable "now" (M6 / wall-clock decoupling): a fresh create anchors its
  /// `validFrom` on this date. Defaults to `DateTime.now()` in production; tests
  /// pass a fixed clock so the saved window is run-day independent.
  final DateTime? _clock;

  @override
  ConsumerState<WeeklyTemplateEditorScreen> createState() =>
      _WeeklyTemplateEditorScreenState();
}

class _WeeklyTemplateEditorScreenState
    extends ConsumerState<WeeklyTemplateEditorScreen> {
  static const _tag = 'feature.schedule.weeklyeditor';

  /// One editable [DayHours] per ISO weekday (Mon..Sun), or `null` for a
  /// day-off. Seeded once from the server list, then edited locally until Save.
  List<DayHours?>? _days;

  /// Last hours per day so toggling a day back on restores them rather than
  /// starting blank.
  late final List<DayHours> _stash = <DayHours>[
    for (int i = 0; i < _kDaysInWeek; i++) DayHours.defaultDay(),
  ];

  /// The server template the draft was seeded from (null when the master has no
  /// template yet). Drives the create-vs-update-vs-delete decision and the
  /// dirty diff. Captured once alongside [_days].
  WeeklySchedule? _serverTemplate;

  /// The canonical interval lists the draft was seeded with — the dirty-diff
  /// baseline (Phase 6.2 pristine-load contract: Save stays disabled until the
  /// user actually edits, never merely because data loaded). Indexed Mon..Sun.
  List<List<WorkInterval>>? _baseline;

  bool _saving = false;

  /// Drives the Save button's enabled state in isolation. A single-day edit
  /// recomputes the dirty-diff + validation and pushes the result here, so only
  /// the Save button (wrapped in a `ValueListenableBuilder`) rebuilds — the 6
  /// untouched `_DayCard`s never re-run `build()`/`validateDayHours`.
  final ValueNotifier<bool> _canSaveNotifier = ValueNotifier<bool>(false);

  /// Drives the summary chip's open-day count in isolation. Updated alongside
  /// the Save gate on a toggle, so the chip rebuilds without touching the cards.
  final ValueNotifier<int> _openCountNotifier = ValueNotifier<int>(0);

  @override
  void dispose() {
    _canSaveNotifier.dispose();
    _openCountNotifier.dispose();
    super.dispose();
  }

  DateTime get _today {
    final DateTime c = widget._clock ?? DateTime.now();
    return DateTime(c.year, c.month, c.day);
  }

  // ── Seeding (once, on first successful load) ────────────────────────────────
  void _seed(List<WeeklySchedule> serverList) {
    if (_days != null) return;
    final WeeklySchedule? template = serverList.isEmpty
        ? null
        : serverList.first;
    final List<DayHours?> seeded = List<DayHours?>.filled(_kDaysInWeek, null);
    final List<List<WorkInterval>> baseline = <List<WorkInterval>>[
      for (int i = 0; i < _kDaysInWeek; i++) <WorkInterval>[],
    ];
    if (template != null) {
      for (final TemplateDay d in template.days) {
        final int idx = d.dayOfWeek - 1;
        if (idx < 0 || idx >= _kDaysInWeek) continue;
        baseline[idx] = d.cloneIntervals();
        if (d.intervals.isNotEmpty) {
          seeded[idx] = DayHours.fromIntervals(d.intervals);
        }
      }
    }
    // setState is safe here — called from build() during the data branch, so we
    // schedule it post-frame to avoid a setState-during-build assertion.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _serverTemplate = template;
        _days = seeded;
        _baseline = baseline;
      });
      // Pristine load: Save stays disabled until a real edit (Phase 6.2).
      _canSaveNotifier.value = _canSave;
      _openCountNotifier.value = _openCount;
    });
  }

  /// Recompute the Save gate (and open-day count) after a single-day edit and
  /// push the results to the Save button / summary chip only. Does NOT call
  /// `setState`, so no `_DayCard` rebuilds.
  void _onDayMutated() {
    _canSaveNotifier.value = _canSave;
    _openCountNotifier.value = _openCount;
  }

  // ── Derived state ───────────────────────────────────────────────────────────
  bool get _hasErrors =>
      _days?.any((DayHours? d) => d != null && !dayHoursValid(d)) ?? false;

  int get _openCount => _days?.where((DayHours? d) => d != null).length ?? 0;

  /// True when the draft differs from the seeded baseline. Compares each day's
  /// collapsed canonical interval list against the server's — so a pristine load
  /// is NOT dirty (Phase 6.2 contract), and a no-op edit (e.g. toggle off then
  /// on with the same hours) doesn't enable Save.
  bool get _isDirty {
    final List<DayHours?>? days = _days;
    final List<List<WorkInterval>>? baseline = _baseline;
    if (days == null || baseline == null) return false;
    for (int i = 0; i < _kDaysInWeek; i++) {
      final List<WorkInterval> draftIntervals = days[i] == null
          ? const <WorkInterval>[]
          : days[i]!.toIntervals();
      if (!_sameIntervals(draftIntervals, baseline[i])) return true;
    }
    return false;
  }

  bool get _canSave => _isDirty && !_hasErrors && !_saving;

  static bool _sameIntervals(List<WorkInterval> a, List<WorkInterval> b) {
    if (a.length != b.length) return false;
    final List<WorkInterval> sa = List<WorkInterval>.of(a)
      ..sort((x, y) => x.startMinutes.compareTo(y.startMinutes));
    final List<WorkInterval> sb = List<WorkInterval>.of(b)
      ..sort((x, y) => x.startMinutes.compareTo(y.startMinutes));
    for (int i = 0; i < sa.length; i++) {
      if (sa[i].startMinutes != sb[i].startMinutes ||
          sa[i].endMinutes != sb[i].endMinutes) {
        return false;
      }
    }
    return true;
  }

  // ── Mutations ────────────────────────────────────────────────────────────────
  /// Apply a day-on/off toggle to the host's canonical store + stash and return
  /// the new slot value to the (stateful) `_DayCard`, which rebuilds only
  /// itself. The host then recomputes the Save gate in isolation. No host
  /// `setState` — the 6 untouched cards stay put.
  DayHours? _toggleDay(int index, bool open) {
    final List<DayHours?> days = _days!;
    if (open) {
      days[index] = _stash[index].clone();
    } else {
      final DayHours? current = days[index];
      if (current != null) _stash[index] = current.clone();
      days[index] = null;
    }
    _onDayMutated();
    return days[index];
  }

  // ── Save ──────────────────────────────────────────────────────────────────────
  Future<void> _save() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    if (_hasErrors) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            backgroundColor: BrandColors.error,
            content: Text(l10n.weeklyEditorErrorsBanner),
          ),
        );
      return;
    }

    final List<DayHours?> days = _days!;
    final WeeklySchedule? existing = _serverTemplate;
    final bool allOff = days.every((DayHours? d) => d == null);

    setState(() => _saving = true);
    _canSaveNotifier.value = _canSave;
    try {
      final WeeklyScheduleNotifier notifier = ref.read(
        weeklyScheduleProvider.notifier,
      );

      if (allOff) {
        // No working days. If a template exists, deleting it returns the master
        // to the NO_SCHEDULE state (so the calendar empty-state shows again).
        // If none exists there is nothing to persist.
        if (existing?.id != null) {
          if (kDebugMode) {
            log('save: all-off → delete ${existing!.id}', name: _tag);
          }
          await notifier.delete(existing!.id!);
        }
      } else {
        final WeeklySchedule schedule = _buildSchedule(days, existing);
        if (kDebugMode) {
          log(
            'save: ${existing?.id == null ? 'create' : 'update'} '
            'template ($_openCount open days)',
            name: _tag,
            level: 800,
          );
        }
        await notifier.save(schedule, scheduleId: existing?.id);
      }

      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.savedSnackbar)));
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(RouteNames.masterSchedule);
      }
    } on Failure catch (f) {
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            backgroundColor: BrandColors.error,
            content: Text(f.userMessage(context)),
          ),
        );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        _canSaveNotifier.value = _canSave;
      }
    }
  }

  /// Maps the 7 draft days onto a [WeeklySchedule], preserving the loaded
  /// template's active window (open-ended from `today` for a fresh create).
  WeeklySchedule _buildSchedule(
    List<DayHours?> days,
    WeeklySchedule? existing,
  ) {
    final List<TemplateDay> templateDays = <TemplateDay>[
      for (int i = 0; i < _kDaysInWeek; i++)
        TemplateDay(
          dayOfWeek: i + 1,
          label: _serverTemplate?.days[i].label ?? '',
          intervals: days[i] == null
              ? <WorkInterval>[]
              : days[i]!.toIntervals(),
        ),
    ];
    return WeeklySchedule(
      id: existing?.id,
      validFrom: existing?.validFrom ?? _today,
      validTo: existing?.validTo,
      days: templateDays,
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────--
  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<WeeklySchedule>> asyncWeekly = ref.watch(
      weeklyScheduleProvider,
    );

    return Scaffold(
      backgroundColor: BrandColors.base,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            VelvetTopBar(
              title: l10n.scheduleWeeklyEditorTitle,
              backSemanticLabel: l10n.registerBackStep,
              onBack: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go(RouteNames.masterSchedule);
                }
              },
            ),
            Expanded(
              child: asyncWeekly.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: BrandColors.accent),
                ),
                error: (Object e, _) => _ErrorBody(
                  failure: e,
                  onRetry: () => ref.invalidate(weeklyScheduleProvider),
                ),
                data: (List<WeeklySchedule> serverList) {
                  _seed(serverList);
                  final List<DayHours?>? days = _days;
                  if (days == null) {
                    // Post-frame seed hasn't landed yet — one frame of spinner.
                    return const Center(
                      child: CircularProgressIndicator(
                        color: BrandColors.accent,
                      ),
                    );
                  }
                  return _LoadedBody(
                    days: days,
                    openCountListenable: _openCountNotifier,
                    canSaveListenable: _canSaveNotifier,
                    saving: _saving,
                    activeWindow: _activeWindowLabel(l10n),
                    l10n: l10n,
                    onToggle: _toggleDay,
                    onMutated: _onDayMutated,
                    onSave: _save,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The informational active-window line for the card.
  String _activeWindowLabel(AppLocalizations l10n) {
    final WeeklySchedule? t = _serverTemplate;
    final DateTime from = t?.validFrom ?? _today;
    final DateTime? to = t?.validTo;
    if (to == null) {
      return l10n.weeklyEditorActiveWindowOpenEnded(_ddmm(from));
    }
    return l10n.weeklyEditorActiveWindowRange(_ddmm(from), _ddmm(to));
  }

  static String _ddmm(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';
}

// ─────────────────────────────────────────────────────────────────────────────
// Loaded body.
// ─────────────────────────────────────────────────────────────────────────────
class _LoadedBody extends StatelessWidget {
  _LoadedBody({
    required this.days,
    required this.openCountListenable,
    required this.canSaveListenable,
    required this.saving,
    required this.activeWindow,
    required this.l10n,
    required this.onToggle,
    required this.onMutated,
    required this.onSave,
  });

  final List<DayHours?> days;

  /// Open-day count, listened to so only the summary chip rebuilds on a toggle.
  final ValueListenable<int> openCountListenable;

  /// Save-enabled gate, listened to so only the Save button rebuilds on an edit.
  final ValueListenable<bool> canSaveListenable;
  final bool saving;
  final String activeWindow;
  final AppLocalizations l10n;

  /// Applies a day toggle in the host and returns the new slot value for the
  /// (stateful) `_DayCard` to render.
  final DayHours? Function(int index, bool open) onToggle;

  /// Notifies the host to recompute the Save gate after an in-place edit.
  final VoidCallback onMutated;
  final Future<void> Function() onSave;

  /// `IntervalEditorStrings` is invariant for the screen's lifetime — resolve
  /// it once instead of rebuilding it on every `build`.
  late final IntervalEditorStrings _strings = _intervalStrings();

  static String _dayLabel(AppLocalizations l10n, int dow) => switch (dow) {
    1 => l10n.weekdayMon,
    2 => l10n.weekdayTue,
    3 => l10n.weekdayWed,
    4 => l10n.weekdayThu,
    5 => l10n.weekdayFri,
    6 => l10n.weekdaySat,
    _ => l10n.weekdaySun,
  };

  IntervalEditorStrings _intervalStrings() => IntervalEditorStrings(
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
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              VelvetSpacing.md,
              VelvetSpacing.md,
              VelvetSpacing.md,
              VelvetSpacing.xl,
            ),
            children: <Widget>[
              _summaryChip(),
              const SizedBox(height: VelvetSpacing.sm + 2),
              _activeWindowCard(),
              const SizedBox(height: VelvetSpacing.lg),
              for (int i = 0; i < _kDaysInWeek; i++) ...<Widget>[
                _DayCard(
                  key: Key('weekly-day-${i + 1}'),
                  dayOfWeek: i + 1,
                  label: _dayLabel(l10n, i + 1),
                  initialDay: days[i],
                  dayOffLabel: l10n.workingHoursClosedLabel,
                  dayOffRestLabel: l10n.weeklyEditorDayOffRest,
                  toggleSemanticLabel: l10n.weeklyEditorDayToggleSemantic(
                    _dayLabel(l10n, i + 1),
                  ),
                  strings: _strings,
                  onToggle: (bool open) => onToggle(i, open),
                  onMutated: onMutated,
                ),
                if (i != _kDaysInWeek - 1)
                  const SizedBox(height: VelvetSpacing.md),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            VelvetSpacing.md,
            VelvetSpacing.sm,
            VelvetSpacing.md,
            VelvetSpacing.md,
          ),
          child: ValueListenableBuilder<bool>(
            valueListenable: canSaveListenable,
            builder: (BuildContext context, bool canSave, _) {
              return NeumorphicButton(
                key: const Key('btn-save-weekly-template'),
                label: l10n.step3CtaSave,
                icon: Icons.check_rounded,
                loading: saving,
                onPressed: canSave ? onSave : null,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _summaryChip() {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.calendar_today_rounded,
            size: 15,
            color: BrandColors.muted.withValues(alpha: 0.8),
          ),
          const SizedBox(width: VelvetSpacing.xs),
          ValueListenableBuilder<int>(
            valueListenable: openCountListenable,
            builder: (BuildContext context, int openCount, _) {
              return Text(
                l10n.weeklyEditorOpenCount(openCount),
                style: VelvetText.label().copyWith(letterSpacing: 0),
              );
            },
          ),
        ],
      ),
    );
  }

  /// Informational active-window card (read-only in this phase — editing the
  /// validity window via the range picker is a later phase).
  Widget _activeWindowCard() {
    return NeumorphicCard(
      padding: const EdgeInsets.symmetric(
        horizontal: VelvetSpacing.md,
        vertical: VelvetSpacing.sm + 2,
      ),
      shadows: VelvetShadows.extrudedSmall,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.event_available_rounded,
            size: 16,
            color: BrandColors.accent,
          ),
          const SizedBox(width: VelvetSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  activeWindow,
                  style: VelvetText.bodyStrong().copyWith(fontSize: 13),
                ),
                const SizedBox(height: VelvetSpacing.xs),
                Text(
                  l10n.weeklyEditorActiveWindowHint,
                  style: VelvetText.feedback(BrandColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _DayCard — one neumorphic card per ISO weekday.
// ─────────────────────────────────────────────────────────────────────────────
class _DayCard extends StatefulWidget {
  const _DayCard({
    super.key,
    required this.dayOfWeek,
    required this.label,
    required this.initialDay,
    required this.dayOffLabel,
    required this.dayOffRestLabel,
    required this.toggleSemanticLabel,
    required this.strings,
    required this.onToggle,
    required this.onMutated,
  });

  final int dayOfWeek;
  final String label;

  /// The host's slot value for this weekday at seed/save time. The card holds
  /// its own reference and mutates it in place; the host shares the SAME
  /// `DayHours` object via [_days], so the dirty-diff/save sees every edit.
  final DayHours? initialDay;
  final String dayOffLabel;
  final String dayOffRestLabel;
  final String toggleSemanticLabel;
  final IntervalEditorStrings strings;

  /// Applies the toggle in the host and returns the new slot value (a clone of
  /// the stash on open, `null` on close).
  final DayHours? Function(bool open) onToggle;

  /// Notifies the host to recompute the Save gate after an in-place edit.
  final VoidCallback onMutated;

  @override
  State<_DayCard> createState() => _DayCardState();
}

class _DayCardState extends State<_DayCard> {
  /// This day's editable hours, shared by reference with the host's `_days`
  /// slot. A toggle/interval edit mutates it and `setState`s THIS card only —
  /// the other six days never re-run `build()`/`validateDayHours`.
  late DayHours? _day = widget.initialDay;

  @override
  void didUpdateWidget(_DayCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-seed after a host-level rebuild (e.g. a fresh load) so the card tracks
    // the canonical slot rather than a stale local reference.
    if (!identical(oldWidget.initialDay, widget.initialDay)) {
      _day = widget.initialDay;
    }
  }

  void _handleToggle(bool open) {
    final DayHours? next = widget.onToggle(open);
    setState(() => _day = next);
  }

  void _handleIntervalChanged() {
    // The IntervalEditor mutated `_day` in place; rebuild this card only, then
    // let the host recompute the Save gate.
    setState(() {});
    widget.onMutated();
  }

  @override
  Widget build(BuildContext context) {
    final DayHours? day = _day;
    final bool active = day != null;
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
                  widget.label,
                  style: VelvetText.subheading().copyWith(
                    color: active ? BrandColors.text : BrandColors.muted,
                  ),
                ),
              ),
              if (!active) ...<Widget>[
                Text(
                  widget.dayOffLabel,
                  style: VelvetText.label().copyWith(color: BrandColors.muted),
                ),
                const SizedBox(width: VelvetSpacing.sm + 2),
              ],
              NeumorphicToggle(
                key: Key('weekly-toggle-${widget.dayOfWeek}'),
                value: active,
                onChanged: _handleToggle,
                semanticLabel: widget.toggleSemanticLabel,
              ),
            ],
          ),
          const SizedBox(height: VelvetSpacing.md),
          if (day != null)
            IntervalEditor(
              day: day,
              onChanged: _handleIntervalChanged,
              strings: widget.strings,
              fieldKeyPrefix: 'weekly-day-${widget.dayOfWeek}',
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
                Text(
                  widget.dayOffRestLabel,
                  style: VelvetText.body().copyWith(color: BrandColors.muted),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Error body — neumorphic retry (mirrors the schedule / working-hours screens).
// ─────────────────────────────────────────────────────────────────────────────
class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.failure, required this.onRetry});

  final Object failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
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
            NeumorphicButton(
              key: const Key('weekly-editor-retry'),
              label: l10n.retryLabel,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
