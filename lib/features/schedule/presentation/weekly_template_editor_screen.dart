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
// `today`). The active-window card is now TAPPABLE — it opens the Phase 15.5
// `ApplyScheduleSheet` («Період дії графіка»), where the master sets the
// validity window via a preset or the `PeriodRangePicker`. Applying a window
// calls `upsertWeeklySchedule` with the chosen `validFrom`/`validTo` (it sets
// the window — it does NOT materialise per-date overrides), then re-seeds the
// editor from the saved server list.

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
import 'apply_schedule_sheet.dart';
import 'weekly_schedule_notifier.dart';
import 'widgets/discrete_times_editor.dart';
import 'widgets/interval_editor.dart';

/// Number of ISO days in a week.
const int _kDaysInWeek = 7;

/// Why the Save button is in its current state — drives both the button's
/// enabled flag and the inline hint that explains a disabled Save, so a day-off
/// selection never leaves the user staring at a silently-dead button.
enum _SaveGate {
  /// The draft differs from the persisted schedule and has no validation
  /// errors → Save is enabled.
  saveable,

  /// The draft matches the persisted schedule (a clean no-op, e.g. an all-off
  /// week with no existing template, or a toggle off→on with the same hours) →
  /// Save is disabled and the "no changes" hint is shown.
  noChanges,

  /// At least one day has an invalid window/break → Save is disabled (the
  /// per-field inline validation already explains the error in-card; tapping
  /// Save would surface the errors banner).
  hasErrors,

  /// First-time create where the validity window («Графік діє з…») has NOT yet
  /// been explicitly chosen → Save is disabled and the inline hint routes the
  /// user to the «Період дії графіка» sheet. Prevents the editor from silently
  /// persisting a `validFrom = today` the master never picked.
  windowUnset,

  /// A save/delete is in flight → Save shows its loading state.
  saving,
}

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
  /// Used exclusively for the INTERVAL shape — interval window + breaks.
  List<DayHours?>? _days;

  /// Per-weekday mode + discrete times (Phase 15.8). Parallel to [_days]:
  /// entry `i` is `null` when day `i` is off (regardless of mode). When
  /// non-null, [TemplateDay.mode] and [TemplateDay.times] carry the discrete
  /// shape; [TemplateDay.intervals] is not authoritative here (that lives in
  /// [_days]). Seeded alongside [_days].
  List<TemplateDay?>? _templateDays;

  /// Last hours per day so toggling a day back on restores them rather than
  /// starting blank.
  late final List<DayHours> _stash = <DayHours>[
    for (int i = 0; i < _kDaysInWeek; i++) DayHours.defaultDay(),
  ];

  /// Stash for discrete times — parallel to [_stash] — so toggling a discrete
  /// day off and back on restores the discrete times.
  late final List<List<TimeOfDay>> _timesStash = <List<TimeOfDay>>[
    for (int i = 0; i < _kDaysInWeek; i++) <TimeOfDay>[],
  ];

  /// Stash for mode — which mode was active when a day was toggled off.
  late final List<WeekdayMode> _modeStash = <WeekdayMode>[
    for (int i = 0; i < _kDaysInWeek; i++) WeekdayMode.interval,
  ];

  /// The server template the draft was seeded from (null when the master has no
  /// template yet). Drives the create-vs-update-vs-delete decision and the
  /// dirty diff. Captured once alongside [_days].
  WeeklySchedule? _serverTemplate;

  /// The persisted server state projected onto the seven ISO weekdays — the
  /// dirty-diff source of truth for INTERVAL shape. Equals seven empty lists
  /// when `_serverTemplate == null` (the NO_SCHEDULE / fresh-create case).
  List<List<WorkInterval>>? _baseline;

  /// Persisted baseline for EXPLICIT_TIMES shape — discrete times per weekday.
  /// Parallel to [_baseline]. Empty list means "was not EXPLICIT_TIMES" or
  /// "was EXPLICIT_TIMES day-off".
  List<List<TimeOfDay>>? _baselineTimes;

  /// Persisted baseline mode per weekday (indexed Mon..Sun).
  List<WeekdayMode>? _baselineModes;

  /// FIRST-CREATE validity-window draft (`_serverTemplate == null` only). Holds
  /// the window the master chose in the «Період дії графіка» sheet BEFORE the
  /// editor's Save is pressed — the single commit point on first create. `null`
  /// means "not chosen yet" → the create persists open-ended (`validFrom =
  /// today`, `validTo = null`). Never read for an existing template, whose
  /// window comes from `_serverTemplate`.
  DateTimeRange? _draftWindow;

  bool _saving = false;

  /// Drives the Save button's enabled state AND the inline disabled-reason hint
  /// in isolation. A single-day edit recomputes the dirty-diff + validation and
  /// pushes the result here, so only the Save area (wrapped in a
  /// `ValueListenableBuilder`) rebuilds — the 6 untouched `_DayCard`s never
  /// re-run `build()`/`validateDayHours`.
  final ValueNotifier<_SaveGate> _saveGateNotifier = ValueNotifier<_SaveGate>(
    _SaveGate.noChanges,
  );

  /// Drives the summary chip's open-day count in isolation. Updated alongside
  /// the Save gate on a toggle, so the chip rebuilds without touching the cards.
  final ValueNotifier<int> _openCountNotifier = ValueNotifier<int>(0);

  @override
  void dispose() {
    _saveGateNotifier.dispose();
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
    final List<TemplateDay?> seededTemplate = List<TemplateDay?>.filled(
      _kDaysInWeek,
      null,
    );
    final List<List<WorkInterval>> baseline = <List<WorkInterval>>[
      for (int i = 0; i < _kDaysInWeek; i++) <WorkInterval>[],
    ];
    final List<List<TimeOfDay>> baselineTimes = <List<TimeOfDay>>[
      for (int i = 0; i < _kDaysInWeek; i++) <TimeOfDay>[],
    ];
    final List<WeekdayMode> baselineModes = <WeekdayMode>[
      for (int i = 0; i < _kDaysInWeek; i++) WeekdayMode.interval,
    ];
    if (template != null) {
      for (final TemplateDay d in template.days) {
        final int idx = d.dayOfWeek - 1;
        if (idx < 0 || idx >= _kDaysInWeek) continue;
        baselineModes[idx] = d.mode;
        if (d.mode == WeekdayMode.explicitTimes) {
          // EXPLICIT_TIMES day — seed discrete shape.
          baselineTimes[idx] = List<TimeOfDay>.of(d.times);
          if (d.times.isNotEmpty) {
            // Working explicit-times day: seed seeded slot so the card renders.
            seeded[idx] = DayHours.defaultDay(); // placeholder; not used by UI
            seededTemplate[idx] = TemplateDay(
              dayOfWeek: d.dayOfWeek,
              label: d.label,
              intervals: <WorkInterval>[],
              mode: WeekdayMode.explicitTimes,
              times: List<TimeOfDay>.of(d.times),
            );
          }
        } else {
          // INTERVAL day — seed interval shape.
          baseline[idx] = d.cloneIntervals();
          if (d.intervals.isNotEmpty) {
            seeded[idx] = DayHours.fromIntervals(d.intervals);
            seededTemplate[idx] = TemplateDay(
              dayOfWeek: d.dayOfWeek,
              label: d.label,
              intervals: d.cloneIntervals(),
              mode: WeekdayMode.interval,
              times: const <TimeOfDay>[],
            );
          }
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
        _templateDays = seededTemplate;
        _baseline = baseline;
        _baselineTimes = baselineTimes;
        _baselineModes = baselineModes;
      });
      // Pristine load: Save stays disabled until a real edit (Phase 6.2).
      _saveGateNotifier.value = _saveGate;
      _openCountNotifier.value = _openCount;
    });
  }

  /// Recompute the Save gate (and open-day count) after a single-day edit and
  /// push the results to the Save area / summary chip only. Does NOT call
  /// `setState`, so no `_DayCard` rebuilds.
  void _onDayMutated() {
    _saveGateNotifier.value = _saveGate;
    _openCountNotifier.value = _openCount;
  }

  // ── Derived state ───────────────────────────────────────────────────────────

  /// True when any WORKING day has a validation error.
  ///
  /// INTERVAL days: `dayHoursValid` (window + breaks).
  /// EXPLICIT_TIMES days: `discreteTimesValid` (non-empty, 15-min aligned).
  ///
  /// Day-off entries (null slot) are never in error.
  bool get _hasErrors {
    final List<DayHours?>? days = _days;
    final List<TemplateDay?>? tDays = _templateDays;
    if (days == null) return false;
    for (int i = 0; i < _kDaysInWeek; i++) {
      if (days[i] == null) continue; // day-off: no error
      final TemplateDay? td = tDays?[i];
      if (td != null && td.mode == WeekdayMode.explicitTimes) {
        // Working EXPLICIT_TIMES day — validate discrete times.
        if (!discreteTimesValid(td.times)) return true;
      } else {
        // Working INTERVAL day — validate window + breaks.
        if (!dayHoursValid(days[i]!)) return true;
      }
    }
    return false;
  }

  int get _openCount => _days?.where((DayHours? d) => d != null).length ?? 0;

  /// True when the draft differs from the PERSISTED server state. For INTERVAL
  /// days, compares the collapsed canonical interval list against [_baseline].
  /// For EXPLICIT_TIMES days, compares mode + sorted times against
  /// [_baselineModes] / [_baselineTimes]. Phase 6.2 pristine-load contract
  /// preserved: Save stays disabled until the user actually edits.
  bool get _isDirty {
    final List<DayHours?>? days = _days;
    final List<TemplateDay?>? tDays = _templateDays;
    final List<List<WorkInterval>>? baseline = _baseline;
    final List<List<TimeOfDay>>? baselineTimes = _baselineTimes;
    final List<WeekdayMode>? baselineModes = _baselineModes;
    if (days == null || baseline == null) return false;
    for (int i = 0; i < _kDaysInWeek; i++) {
      final TemplateDay? td = tDays?[i];
      final WeekdayMode draftMode = (days[i] != null && td != null)
          ? td.mode
          : WeekdayMode.interval;
      final WeekdayMode persistedMode = baselineModes != null
          ? baselineModes[i]
          : WeekdayMode.interval;

      // Mode changed → always dirty.
      if (days[i] != null && draftMode != persistedMode) return true;

      if (days[i] != null && draftMode == WeekdayMode.explicitTimes) {
        // EXPLICIT_TIMES: compare sorted times.
        final List<TimeOfDay> draftTimes = td != null
            ? sortDedupeTimes(td.times)
            : <TimeOfDay>[];
        final List<TimeOfDay> persisted = baselineTimes != null
            ? sortDedupeTimes(baselineTimes[i])
            : <TimeOfDay>[];
        if (!_sameTimes(draftTimes, persisted)) return true;
      } else {
        // INTERVAL: compare collapsed intervals.
        final List<WorkInterval> draftIntervals = days[i] == null
            ? const <WorkInterval>[]
            : days[i]!.toIntervals();
        if (!_sameIntervals(draftIntervals, baseline[i])) return true;
      }
    }
    return false;
  }

  static bool _sameTimes(List<TimeOfDay> a, List<TimeOfDay> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].hour != b[i].hour || a[i].minute != b[i].minute) return false;
    }
    return true;
  }

  /// The current Save-button state and its reason. `saving` and `hasErrors`
  /// take precedence over the dirty check; a non-dirty draft is a clean no-op
  /// (`noChanges`) — surfaced as the inline hint so a day-off selection never
  /// looks like a broken Save button.
  _SaveGate get _saveGate {
    if (_saving) return _SaveGate.saving;
    if (_hasErrors) return _SaveGate.hasErrors;
    if (!_isDirty) return _SaveGate.noChanges;
    // FIRST-CREATE: a dirty draft with ≥1 valid working day is saveable even
    // before the validity window is chosen — the editor's Save is the single
    // commit point. The «Період дії графіка» sheet now only STAGES the window
    // into `_draftWindow` (it no longer eagerly persists), so there is nothing
    // to gate on: an unchosen window defaults to open-ended (`validFrom =
    // today`, `validTo = null`) at build time. `_SaveGate.windowUnset` is
    // retained for the informational hint only and is never returned here.
    return _SaveGate.saveable;
  }

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
  /// Apply a day-on/off toggle to the host's canonical stores + stashes and
  /// return the new slot value to the (stateful) `_DayCard`, which rebuilds
  /// only itself. The host then recomputes the Save gate in isolation. No host
  /// `setState` — the 6 untouched cards stay put.
  ///
  /// Returns a record `(DayHours?, WeekdayMode, List<TimeOfDay>)` so the card
  /// can restore both interval and discrete state from the stash.
  ({DayHours? dayHours, WeekdayMode mode, List<TimeOfDay> times}) _toggleDay(
    int index,
    bool open,
  ) {
    final List<DayHours?> days = _days!;
    final List<TemplateDay?> tDays = _templateDays!;
    if (open) {
      days[index] = _stash[index].clone();
      tDays[index] = TemplateDay(
        dayOfWeek: index + 1,
        label: tDays[index]?.label ?? '',
        intervals: _stash[index].toIntervals(),
        mode: _modeStash[index],
        times: List<TimeOfDay>.of(_timesStash[index]),
      );
    } else {
      // Stash current state before clearing.
      final DayHours? current = days[index];
      if (current != null) _stash[index] = current.clone();
      final TemplateDay? currentTd = tDays[index];
      if (currentTd != null) {
        _modeStash[index] = currentTd.mode;
        _timesStash[index] = List<TimeOfDay>.of(currentTd.times);
      }
      days[index] = null;
      tDays[index] = null;
    }
    _onDayMutated();
    final TemplateDay? td = tDays[index];
    return (
      dayHours: days[index],
      mode: td?.mode ?? WeekdayMode.interval,
      times: td?.times ?? const <TimeOfDay>[],
    );
  }

  /// Called by `_DayCard` when the mode toggle is flipped. Updates the
  /// [_templateDays] slot for this weekday and recomputes the Save gate.
  void _onModeChanged(int index, WeekdayMode next) {
    final List<TemplateDay?> tDays = _templateDays!;
    final TemplateDay? td = tDays[index];
    if (td == null) return; // day-off — should not be called
    td.setMode(next);
    _onDayMutated();
  }

  /// Called by `_DayCard` when discrete times are mutated. The card mutates its
  /// own private `_times` copy (not the host's `TemplateDay`), so write the
  /// edited list back into the authoritative [TemplateDay.times] before
  /// recomputing the Save gate — otherwise the EXPLICIT_TIMES dirty check reads
  /// stale (empty) times and the Save button never enables.
  void _onTimesChanged(int index, List<TimeOfDay> times) {
    _templateDays?[index]?.times = List<TimeOfDay>.of(times);
    _onDayMutated();
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

    // First create is committed HERE (the single commit point): the validity
    // window comes from `_draftWindow` if the master chose one in the «Період
    // дії графіка» sheet, otherwise it defaults to open-ended (`validFrom =
    // today`, `validTo = null`) in `_buildSchedule`. No eager persist happens
    // in the sheet anymore, so there is nothing to block here.

    setState(() => _saving = true);
    _saveGateNotifier.value = _saveGate;
    try {
      final WeeklyScheduleNotifier notifier = ref.read(
        weeklyScheduleProvider.notifier,
      );

      // Whether the all-off branch actually had a template to delete. When
      // there is nothing to persist (all-off with no existing template), there
      // is no mutation to inspect — treat it as a clean no-op below.
      bool mutated = true;

      if (allOff) {
        // No working days. If a template exists, deleting it returns the master
        // to the NO_SCHEDULE state (so the calendar empty-state shows again).
        // If none exists there is nothing to persist.
        if (existing?.id != null) {
          if (kDebugMode) {
            log('save: all-off → delete ${existing!.id}', name: _tag);
          }
          await notifier.delete(existing!.id!);
        } else {
          mutated = false;
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
      // `WeeklyScheduleNotifier.save` / `.delete` wrap their work in
      // `AsyncValue.guard`, so a failed POST/PUT/DELETE does NOT throw here — it
      // surfaces as an [AsyncError] on the provider state. Read that resulting
      // state and branch on it: only pop + show success when the mutation
      // actually persisted (`hasError == false`). A no-op (all-off, no existing
      // template) never touched the provider, so skip the check for it.
      if (mutated) {
        final AsyncValue<List<WeeklySchedule>> result = ref.read(
          weeklyScheduleProvider,
        );
        if (result.hasError) {
          _showError(messenger, result.error, l10n);
          return;
        }
      }

      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.savedSnackbar)));
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(RouteNames.masterSchedule);
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        _saveGateNotifier.value = _saveGate;
      }
    }
  }

  /// Shows the failure snackbar for a swallowed-into-state save/delete mutation.
  /// [error] is the provider's [AsyncValue.error]: a typed [Failure] when the
  /// repository mapped it, otherwise the generic unknown-error copy. Does NOT
  /// pop and does NOT show a success snackbar — the false-success guard.
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

  /// Maps the 7 draft days onto a [WeeklySchedule], preserving the loaded
  /// template's active window. For each weekday the mode is taken from
  /// [_templateDays]; EXPLICIT_TIMES days carry [TemplateDay.times]; INTERVAL
  /// days carry the collapsed [DayHours.toIntervals()] list.
  ///
  /// Window sourcing:
  ///   • EXISTING template — `validFrom`/`validTo` come from [existing],
  ///     preserving the persisted window verbatim.
  ///   • FIRST CREATE (`existing == null`) — the window comes from
  ///     [_draftWindow] when the master picked one in the «Період дії графіка»
  ///     sheet; otherwise it defaults to open-ended (`validFrom = today`,
  ///     `validTo = null`), which the backend accepts (see
  ///     `WeeklyScheduleNotifier.save`).
  WeeklySchedule _buildSchedule(
    List<DayHours?> days,
    WeeklySchedule? existing,
  ) {
    final List<TemplateDay?> tDays =
        _templateDays ?? List<TemplateDay?>.filled(_kDaysInWeek, null);
    final List<TemplateDay> templateDays = <TemplateDay>[
      for (int i = 0; i < _kDaysInWeek; i++)
        () {
          final TemplateDay? td = tDays[i];
          if (days[i] == null) {
            // Day off.
            return TemplateDay(
              dayOfWeek: i + 1,
              label: _serverTemplate?.days[i].label ?? '',
              intervals: <WorkInterval>[],
              mode: td?.mode ?? WeekdayMode.interval,
              times: const <TimeOfDay>[],
            );
          }
          if (td != null && td.mode == WeekdayMode.explicitTimes) {
            return TemplateDay(
              dayOfWeek: i + 1,
              label: _serverTemplate?.days[i].label ?? '',
              intervals: <WorkInterval>[],
              mode: WeekdayMode.explicitTimes,
              times: List<TimeOfDay>.of(td.times),
            );
          }
          return TemplateDay(
            dayOfWeek: i + 1,
            label: _serverTemplate?.days[i].label ?? '',
            intervals: days[i]!.toIntervals(),
            mode: WeekdayMode.interval,
            times: const <TimeOfDay>[],
          );
        }(),
    ];
    return WeeklySchedule(
      id: existing?.id,
      // First create draws from the staged draft window; an unchosen window is
      // open-ended (validFrom = today, validTo = null).
      validFrom: existing?.validFrom ?? _draftWindow?.start ?? _today,
      validTo: existing != null ? existing.validTo : _draftWindow?.end,
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
                    templateDays:
                        _templateDays ??
                        List<TemplateDay?>.filled(_kDaysInWeek, null),
                    openCountListenable: _openCountNotifier,
                    saveGateListenable: _saveGateNotifier,
                    saving: _saving,
                    activeWindow: _activeWindowLabel(l10n),
                    isWindowSet:
                        _serverTemplate != null || _draftWindow != null,
                    l10n: l10n,
                    onToggle: _toggleDay,
                    onMutated: _onDayMutated,
                    onModeChanged: _onModeChanged,
                    onTimesChanged: _onTimesChanged,
                    onSave: _save,
                    onTapWindow: _openApplyWindowSheet,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Opens the «Період дії графіка» sheet to set the weekly template's
  /// validity window (`validFrom`/`validTo`) for a chosen period. Builds the
  /// active [WeeklySchedule] from the current draft (preserving the seven
  /// `days`), so the window apply persists the master's in-editor day shape too.
  ///
  /// Per the locked Phase 15.5 contract the sheet sets the WINDOW via
  /// `upsertWeeklySchedule` (it does NOT materialise per-date overrides). The
  /// notifier invalidates `effectiveScheduleProvider` on success, so the
  /// calendar repaints. On a successful apply the editor re-seeds from the
  /// freshly-saved server list so the active-window card reflects the new
  /// window.
  Future<void> _openApplyWindowSheet() async {
    final List<DayHours?>? days = _days;
    if (days == null) return;
    final WeeklySchedule base = _buildSchedule(days, _serverTemplate);
    final Object? result = await showApplyScheduleSheet(
      context,
      baseSchedule: base,
      today: _today,
    );
    if (!mounted) return;

    // FIRST CREATE: the sheet returns the chosen window as a draft — it did NOT
    // persist. Stage it locally and recompute the Save gate / card label; the
    // editor's Save remains the single commit point. Do NOT re-seed from the
    // server (there is nothing saved to re-seed from).
    if (_serverTemplate == null) {
      if (result is! DateTimeRange) return; // dismissed without choosing
      setState(() => _draftWindow = result);
      _onDayMutated();
      if (kDebugMode) {
        log(
          'apply-window: first-create draft staged '
          '${result.start} → ${result.end}',
          name: _tag,
        );
      }
      return;
    }

    // EXISTING template: the sheet persisted the new window itself (returns
    // `true`). Re-seed from the now-saved server list so the card + dirty-diff
    // track the persisted window/template. Clear the local seed so `_seed`
    // re-runs.
    if (result != true) return;
    setState(() {
      _days = null;
      _templateDays = null;
      _baseline = null;
      _baselineTimes = null;
      _baselineModes = null;
      _serverTemplate = null;
    });
    if (kDebugMode) {
      log('apply-window: applied → re-seeding from server', name: _tag);
    }
  }

  /// The informational active-window line for the card.
  ///
  /// EXISTING template: reflects the persisted `validFrom`/`validTo`.
  /// FIRST CREATE (`_serverTemplate == null`): reflects the staged
  /// [_draftWindow] (chosen-but-unsaved) when set; otherwise the placeholder
  /// prompt, so the card reads as «not chosen yet» until the master picks one.
  String _activeWindowLabel(AppLocalizations l10n) {
    final WeeklySchedule? t = _serverTemplate;
    if (t == null) {
      final DateTimeRange? draft = _draftWindow;
      if (draft == null) {
        return l10n.weeklyEditorActiveWindowUnset;
      }
      return l10n.weeklyEditorActiveWindowRange(
        _ddmm(draft.start),
        _ddmm(draft.end),
      );
    }
    final DateTime from = t.validFrom;
    final DateTime? to = t.validTo;
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
    required this.templateDays,
    required this.openCountListenable,
    required this.saveGateListenable,
    required this.saving,
    required this.activeWindow,
    required this.isWindowSet,
    required this.l10n,
    required this.onToggle,
    required this.onMutated,
    required this.onModeChanged,
    required this.onTimesChanged,
    required this.onSave,
    required this.onTapWindow,
  });

  /// Filled active-window label style — committed value (Nunito 13/700, text).
  static final TextStyle _windowSetStyle = VelvetText.bodyStrong().copyWith(
    fontSize: 13,
  );

  /// Unset active-window prompt style — reads as a placeholder, not a value
  /// (Nunito 13/600, placeholder color). See frontend-design judgment.
  static final TextStyle _windowUnsetStyle = VelvetText.bodyStrong().copyWith(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: BrandColors.placeholder,
  );

  final List<DayHours?> days;

  /// Parallel mode+times tracking per weekday (Phase 15.8).
  final List<TemplateDay?> templateDays;

  /// Open-day count, listened to so only the summary chip rebuilds on a toggle.
  final ValueListenable<int> openCountListenable;

  /// Save gate (enabled state + disabled reason), listened to so only the Save
  /// area (button + inline hint) rebuilds on an edit.
  final ValueListenable<_SaveGate> saveGateListenable;
  final bool saving;
  final String activeWindow;

  /// Whether a validity window has been persisted. When `false`, [activeWindow]
  /// is the unset placeholder prompt and the card renders it as a placeholder
  /// (muted weight/color) rather than a committed value.
  final bool isWindowSet;
  final AppLocalizations l10n;

  /// Applies a day toggle in the host and returns the record of new slot values
  /// (dayHours, mode, times) for the (stateful) `_DayCard` to render.
  final ({DayHours? dayHours, WeekdayMode mode, List<TimeOfDay> times})
  Function(int index, bool open)
  onToggle;

  /// Notifies the host to recompute the Save gate after an in-place edit.
  final VoidCallback onMutated;

  /// Called when the day's mode toggle is flipped.
  final void Function(int index, WeekdayMode next) onModeChanged;

  /// Called after discrete times are mutated by the `_DayCard`. Threads the
  /// card's current times list up so the host can write it back into the
  /// authoritative [TemplateDay.times] before recomputing the Save gate.
  final void Function(int index, List<TimeOfDay> times) onTimesChanged;

  final Future<void> Function() onSave;

  /// Opens the «Період дії графіка» sheet to set the validity window.
  final Future<void> Function() onTapWindow;

  /// `IntervalEditorStrings` is invariant for the screen's lifetime — resolve
  /// it once instead of rebuilding it on every `build`.
  late final IntervalEditorStrings _strings = _intervalStrings();

  /// `DiscreteTimesEditorStrings` — resolved once alongside [_strings].
  late final DiscreteTimesEditorStrings _discreteStrings =
      _buildDiscreteStrings();

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
    errTimeNotAligned: l10n.scheduleErrTimeNotAligned,
  );

  DiscreteTimesEditorStrings _buildDiscreteStrings() =>
      DiscreteTimesEditorStrings(
        addTimeLabel: l10n.discreteTimesAddTime,
        windowLabel: l10n.discreteTimesWindowLabel,
        removeTimeSemantic: l10n.discreteTimesRemoveSemantic,
        timePickerTitle: l10n.discreteTimesPickerTitle,
        timePickerConfirm: l10n.timePickerConfirm,
        timePickerHoursSemantic: l10n.timePickerHoursSemantic,
        timePickerMinutesSemantic: l10n.timePickerMinutesSemantic,
        errEmpty: l10n.discreteTimesErrEmpty,
        duplicateMessage: l10n.discreteTimesDuplicateMessage,
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
                  initialMode: templateDays[i]?.mode ?? WeekdayMode.interval,
                  initialTimes: templateDays[i]?.times ?? const <TimeOfDay>[],
                  dayOffLabel: l10n.workingHoursClosedLabel,
                  dayOffRestLabel: l10n.weeklyEditorDayOffRest,
                  toggleSemanticLabel: l10n.weeklyEditorDayToggleSemantic(
                    _dayLabel(l10n, i + 1),
                  ),
                  modeToggleSemantic: l10n.discreteTimesModeSemantic,
                  segmentIntervalLabel: l10n.discreteTimesSegmentInterval,
                  segmentExplicitLabel: l10n.discreteTimesSegmentExplicit,
                  strings: _strings,
                  discreteStrings: _discreteStrings,
                  onToggle: (bool open) => onToggle(i, open),
                  onMutated: onMutated,
                  onModeChanged: (WeekdayMode next) => onModeChanged(i, next),
                  onTimesChanged: (List<TimeOfDay> times) =>
                      onTimesChanged(i, times),
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
          child: ValueListenableBuilder<_SaveGate>(
            valueListenable: saveGateListenable,
            builder: (BuildContext context, _SaveGate gate, _) {
              final bool canSave = gate == _SaveGate.saveable;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // Explain a disabled Save when the draft is a clean no-op
                  // (e.g. an all-off week with no template) so a day-off
                  // selection never looks like a broken button.
                  if (gate == _SaveGate.noChanges) ...<Widget>[
                    Text(
                      key: const Key('weekly-no-changes-hint'),
                      l10n.weeklyEditorNoChangesHint,
                      style: VelvetText.feedback(BrandColors.muted),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: VelvetSpacing.xs),
                  ],
                  // First-time create with working days but no chosen validity
                  // window: explain why Save is disabled and route the tap to the
                  // «Період дії графіка» sheet so the dead button becomes an
                  // actionable affordance.
                  if (gate == _SaveGate.windowUnset) ...<Widget>[
                    GestureDetector(
                      key: const Key('weekly-window-unset-hint'),
                      onTap: onTapWindow,
                      behavior: HitTestBehavior.opaque,
                      child: Text(
                        l10n.weeklyEditorWindowUnsetHint,
                        style: VelvetText.feedback(BrandColors.accentDeep),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: VelvetSpacing.xs),
                  ],
                  NeumorphicButton(
                    key: const Key('btn-save-weekly-template'),
                    label: l10n.step3CtaSave,
                    icon: Icons.check_rounded,
                    loading: saving,
                    onPressed: canSave ? onSave : null,
                  ),
                ],
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

  /// Tappable active-window card. Opens the «Період дії графіка» sheet
  /// ([onTapWindow]) to set the validity window (`validFrom`/`validTo`) via a
  /// preset or custom range (Phase 15.5). A trailing chevron + the
  /// localized hint invite the tap so the affordance is never a dead button.
  Widget _activeWindowCard() {
    return Semantics(
      button: true,
      label: activeWindow,
      child: GestureDetector(
        key: const Key('weekly-active-window-card'),
        onTap: onTapWindow,
        behavior: HitTestBehavior.opaque,
        child: NeumorphicCard(
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
                      style: isWindowSet ? _windowSetStyle : _windowUnsetStyle,
                    ),
                    const SizedBox(height: VelvetSpacing.xs),
                    Text(
                      l10n.weeklyEditorActiveWindowHint,
                      style: VelvetText.feedback(BrandColors.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: VelvetSpacing.sm),
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: BrandColors.muted,
              ),
            ],
          ),
        ),
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
    required this.initialMode,
    required this.initialTimes,
    required this.dayOffLabel,
    required this.dayOffRestLabel,
    required this.toggleSemanticLabel,
    required this.modeToggleSemantic,
    required this.segmentIntervalLabel,
    required this.segmentExplicitLabel,
    required this.strings,
    required this.discreteStrings,
    required this.onToggle,
    required this.onMutated,
    required this.onModeChanged,
    required this.onTimesChanged,
  });

  final int dayOfWeek;
  final String label;

  /// The host's slot value for this weekday at seed/save time. The card holds
  /// its own reference and mutates it in place; the host shares the SAME
  /// `DayHours` object via [_days], so the dirty-diff/save sees every edit.
  final DayHours? initialDay;

  /// Seeded mode for this weekday (Phase 15.8).
  final WeekdayMode initialMode;

  /// Seeded discrete times for this weekday (Phase 15.8). Mutable in place by
  /// [DiscreteTimesEditor] (this widget holds a local copy).
  final List<TimeOfDay> initialTimes;

  final String dayOffLabel;
  final String dayOffRestLabel;
  final String toggleSemanticLabel;
  final String modeToggleSemantic;
  final String segmentIntervalLabel;
  final String segmentExplicitLabel;
  final IntervalEditorStrings strings;
  final DiscreteTimesEditorStrings discreteStrings;

  /// Applies the toggle in the host and returns the record of new slot values
  /// (dayHours, mode, times) for this card to render.
  final ({DayHours? dayHours, WeekdayMode mode, List<TimeOfDay> times})
  Function(bool open)
  onToggle;

  /// Notifies the host to recompute the Save gate after an in-place INTERVAL edit.
  final VoidCallback onMutated;

  /// Called when the mode toggle is flipped — notifies the host + Save gate.
  final void Function(WeekdayMode next) onModeChanged;

  /// Called after discrete times are mutated — passes the card's current times
  /// list up so the host can write it back, then notifies the Save gate.
  final void Function(List<TimeOfDay> times) onTimesChanged;

  @override
  State<_DayCard> createState() => _DayCardState();
}

class _DayCardState extends State<_DayCard> {
  /// This day's editable hours (INTERVAL shape), shared by reference with the
  /// host's `_days` slot. Mutated in place by [IntervalEditor].
  late DayHours? _day = widget.initialDay;

  /// Current mode — driven by the host's [_templateDays] and the local toggle.
  late WeekdayMode _mode = widget.initialMode;

  /// Discrete start times for EXPLICIT_TIMES mode — mutable in place.
  late List<TimeOfDay> _times = List<TimeOfDay>.of(widget.initialTimes);

  @override
  void didUpdateWidget(_DayCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-seed after a host-level rebuild (e.g. a fresh load after apply-window)
    // so the card tracks the canonical state rather than stale local references.
    if (!identical(oldWidget.initialDay, widget.initialDay)) {
      _day = widget.initialDay;
    }
    if (oldWidget.initialMode != widget.initialMode) {
      _mode = widget.initialMode;
    }
    if (!identical(oldWidget.initialTimes, widget.initialTimes)) {
      _times = List<TimeOfDay>.of(widget.initialTimes);
    }
  }

  void _handleToggle(bool open) {
    final result = widget.onToggle(open);
    setState(() {
      _day = result.dayHours;
      _mode = result.mode;
      _times = List<TimeOfDay>.of(result.times);
    });
  }

  void _handleIntervalChanged() {
    // IntervalEditor mutated `_day` in place; rebuild this card only, then
    // notify the host to recompute the Save gate.
    setState(() {});
    widget.onMutated();
  }

  void _handleModeChanged(WeekdayMode next) {
    if (_mode == next) return;
    setState(() => _mode = next);
    widget.onModeChanged(next);
  }

  void _handleTimesChanged() {
    // DiscreteTimesEditor mutated `_times` in place; rebuild this card only,
    // then thread the current times up so the host writes them back into its
    // authoritative TemplateDay before recomputing the Save gate.
    setState(() {});
    widget.onTimesChanged(_times);
  }

  // ── Mode toggle chip (mirrors _modeChip in DayHoursSheet) ─────────────────
  Widget _modeChip({
    required Key valueKey,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final Color tint = selected ? BrandColors.accentDeep : BrandColors.muted;
    final Widget content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: VelvetSpacing.md,
        vertical: VelvetSpacing.sm + 2,
      ),
      child: Text(
        label,
        overflow: TextOverflow.ellipsis,
        style: VelvetText.bodyStrong().copyWith(fontSize: 13, color: tint),
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
          // ── Day label + on/off toggle ──────────────────────────────────────
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

          // ── Working-day body ───────────────────────────────────────────────
          if (active) ...<Widget>[
            // Mode toggle (Інтервал / Окремі години) — only for working days.
            Semantics(
              label: widget.modeToggleSemantic,
              child: Row(
                key: Key('weekly-mode-toggle-${widget.dayOfWeek}'),
                children: <Widget>[
                  Expanded(
                    child: _modeChip(
                      valueKey: Key('weekly-mode-interval-${widget.dayOfWeek}'),
                      label: widget.segmentIntervalLabel,
                      selected: _mode == WeekdayMode.interval,
                      onTap: () => _handleModeChanged(WeekdayMode.interval),
                    ),
                  ),
                  const SizedBox(width: VelvetSpacing.sm + 2),
                  Expanded(
                    child: _modeChip(
                      valueKey: Key('weekly-mode-explicit-${widget.dayOfWeek}'),
                      label: widget.segmentExplicitLabel,
                      selected: _mode == WeekdayMode.explicitTimes,
                      onTap: () =>
                          _handleModeChanged(WeekdayMode.explicitTimes),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: VelvetSpacing.md),

            // Editor body — swaps on mode change.
            if (_mode == WeekdayMode.interval)
              IntervalEditor(
                day: day,
                onChanged: _handleIntervalChanged,
                strings: widget.strings,
                fieldKeyPrefix: 'weekly-day-${widget.dayOfWeek}',
              )
            else
              DiscreteTimesEditor(
                times: _times,
                onChanged: _handleTimesChanged,
                strings: widget.discreteStrings,
                fieldKeyPrefix: 'weekly-day-${widget.dayOfWeek}',
              ),
          ] else ...<Widget>[
            // Day-off placeholder row.
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
