// Phase 15.4 — DayHoursSheet (Editor B): the per-date override modal sheet.
//
// Ported from the approved preview app at
// `docs/signup-designs/MasterSchedule/lib/screens/day_hours_sheet.dart`,
// adapted to the project's Riverpod + go_router structure:
//   • preview StatefulWidget + SnackBar-only save  → ConsumerStatefulWidget that
//     persists through [OverridesNotifier] (`PUT /overrides/{date}`)
//   • preview standalone Velvet* tokens             → BrandColors / VelvetText /
//     Velvet* (1:1)
//   • day-off mode                                  → a plain full day-off (the
//     backend dropped reason/note from schedule overrides, so the sheet no
//     longer collects either — just a clean "this day is closed" rest card)
//   • reuses the SHARED [IntervalEditor] / [TimeWell] / wheel picker from 15.3 —
//     no second copy.
//
// It OVERRIDES the weekly template for ONE calendar date (start == end):
//   • Робочі години → [IntervalEditor] seeded from the day's current intervals
//     via `DayHours.fromIntervals` → saves a CUSTOM_HOURS override.
//   • Вихідний       → a plain full day-off (no reason, no note) → saves a
//     DAY_OFF override.
//
// SAVE → CALENDAR REPAINT: [OverridesNotifier.putOverride] / `.clearOverride`
// reload the watched range; because `effectiveScheduleProvider(range)`
// `ref.watch`es `overridesProvider(range)`, that reload makes the effective
// schedule recompute + re-fetch reactively, so the Master-Schedule calendar
// repaints with no manual refresh (no explicit `ref.invalidate` needed).
//
// BOOKING-CONFLICT GATE (2026-07-26 design — REVERSES the former OQ-1 "always
// allowed" rule for SAVE only; `_clear` is untouched, still always allowed).
// `_save` no longer PUTs [override] directly: it first calls
// `OverridesNotifier.checkConflicts` (ONE `POST /overrides/conflicts` call for
// the single date this sheet edits). An empty result saves exactly as before
// — no dialog, no extra tap, no behaviour change. A non-empty result shows
// [showDayOffConflictDialog] (`widgets/day_off_conflict_dialog.dart`, ported
// from `docs/signup-designs/DayOffConflictDialog/`): confirming re-issues the
// PUT with `cancelOverlapping: true` (the backend then declines every
// conflicting CONFIRMED booking atomically with the write) and invalidates
// the affected booking views; backing out persists NOTHING AT ALL — not even
// the override itself — and leaves the sheet open. A 409 on the confirmed PUT
// (a booking appeared between the preview and the confirm) re-runs the check
// rather than surfacing a raw error, bounded to `_kMaxConflictCheckAttempts`
// rounds. See `_saveWithConflictCheck`.
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
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/booking/application/booking_calendar_invalidation.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';

import '../domain/schedule_model.dart';
import 'overrides_notifier.dart';
import 'schedule_range.dart';
import 'widgets/day_off_conflict_dialog.dart';
import 'widgets/discrete_times_editor.dart';
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
    this.initialWindow,
    this.initialMode = WeekdayMode.interval,
    this.initialTimes = const <TimeOfDay>[],
    this.clock,
  });

  /// The single calendar date this override targets (date-only). `start == end`
  /// for the built [ScheduleOverride].
  final DateTime date;

  /// Injectable LIVE "now" source for the submit-time past-date guard. The sheet
  /// is opened only for today/future days (the caller hides the pencil on past
  /// ones), but a midnight rollover WHILE the sheet is open can turn the target
  /// [date] past between open and Save. At save, [date] is re-validated against
  /// the value this returns; a now-past date blocks the PUT rather than POSTing
  /// yesterday (which the backend rejects). A callback (not a snapshot) so it is
  /// recomputed at submit; `null` → `DateTime.now()` (production). Tests pass a
  /// callback over a mutable clock to exercise the rollover.
  final DateTime Function()? clock;

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

  /// The day's STORED display-only working window, when the backend has one.
  /// Non-null → the seed takes the lossless regime (`breaks = window MINUS
  /// intervals`), so a break flush against a window edge is re-rendered as a
  /// break instead of vanishing. `null` (legacy row / day-off / EXPLICIT_TIMES)
  /// → the historical gap reconstruction, unchanged.
  final WorkInterval? initialWindow;

  /// `true` when a per-date override already exists for [date] — drives the
  /// "Видалити перевизначення" (clear) action's visibility.
  final bool hasExistingOverride;

  /// `true` when the existing override (if any) is a day-off — seeds the mode
  /// toggle to «Вихідний». Otherwise the sheet opens in working-hours mode.
  final bool initialDayOff;

  /// The mode of the existing custom-hours override, if any (Phase 15.8).
  /// Defaults to [WeekdayMode.interval] so pre-15.8 callers are unaffected.
  final WeekdayMode initialMode;

  /// The discrete start times of an existing EXPLICIT_TIMES override (Phase 15.8).
  /// Defaults to empty; only populated when [initialMode] is [WeekdayMode.explicitTimes].
  final List<TimeOfDay> initialTimes;

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
    WorkInterval? initialWindow,
    WeekdayMode initialMode = WeekdayMode.interval,
    List<TimeOfDay> initialTimes = const <TimeOfDay>[],
    DateTime Function()? clock,
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
        initialWindow: initialWindow,
        initialMode: initialMode,
        initialTimes: initialTimes,
        clock: clock,
      ),
    );
  }

  @override
  ConsumerState<DayHoursSheet> createState() => _DayHoursSheetState();
}

class _DayHoursSheetState extends ConsumerState<DayHoursSheet> {
  static const _tag = 'feature.schedule.dayoverride';

  /// The working window + breaks for the custom-hours INTERVAL mode (rebuilt
  /// from the incoming intervals so edits never touch the calendar source data).
  late DayHours _day;
  late bool _dayOff;

  /// Work mode: INTERVAL vs EXPLICIT_TIMES (Phase 15.8). Only relevant when
  /// [_dayOff] is false.
  late WeekdayMode _workMode;

  /// Discrete start times for EXPLICIT_TIMES mode (Phase 15.8). Mutable in
  /// place by [DiscreteTimesEditor].
  late List<TimeOfDay> _times;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _dayOff = widget.initialDayOff;
    _workMode = widget.initialMode;
    _times = List<TimeOfDay>.of(widget.initialTimes);
    _day = widget.initialIntervals.isEmpty
        ? DayHours.defaultDay()
        : DayHours.fromIntervals(
            widget.initialIntervals,
            window: widget.initialWindow,
          );
  }

  /// Custom-hours mode is unsaveable while the relevant editor has errors.
  ///   • Day-off: always valid (no inputs).
  ///   • INTERVAL: window/breaks must be valid.
  ///   • EXPLICIT_TIMES: must have ≥1 15-min-aligned time.
  bool get _hasErrors {
    if (_dayOff) return false;
    return _workMode == WeekdayMode.explicitTimes
        ? !discreteTimesValid(_times)
        : !dayHoursValid(_day);
  }

  void _setDayOff(bool off) => setState(() => _dayOff = off);

  void _setWorkMode(WeekdayMode next) => setState(() => _workMode = next);

  /// Hard bound on [_saveWithConflictCheck]'s "409 → re-check" retry loop
  /// (a booking created / changed between the preview and the confirmed PUT).
  /// 2 = the initial confirmed attempt plus exactly one re-check round; a
  /// SECOND consecutive 409 is treated as a genuine (if rare) contention
  /// problem rather than retried forever.
  static const int _kMaxConflictCheckAttempts = 2;

  // ── Persistence ──────────────────────────────────────────────────────────
  Future<void> _save() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    // SUBMIT-TIME PAST-DATE GUARD (M6): the sheet opens only for today/future
    // days, but a midnight rollover WHILE it is open can turn [date] past
    // between open and Save. Re-validate against a FRESH today and block the PUT
    // for a now-past date — a past `start` would otherwise 400 at the backend.
    //
    // Kyiv-anchored (backlog :226): the backend's past-date rejection is a
    // Kyiv civil-day check, so "today" here must follow Kyiv's calendar, not
    // the device's — see `shared/time/kyiv_day.dart`. `widget.date` is left
    // alone: it is already a date token handed down by the caller (the day
    // pencil in `master_schedule_screen.dart`), not a raw instant, so it only
    // needs the local-midnight normalisation `DateTime(y, m, d)` already
    // gives it — running it through [kyivDayOf] a second time would be the
    // exact "date token treated as an instant" bug the helper's doc warns
    // against.
    // instant-ok: feeds kyivDayOf below, not used as a bare device-day anchor
    final DateTime now = widget.clock?.call() ?? DateTime.now();
    final DateTime today = kyivDayOf(now);
    final DateTime targetDate = DateTime(
      widget.date.year,
      widget.date.month,
      widget.date.day,
    );
    if (targetDate.isBefore(today)) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            backgroundColor: BrandColors.error,
            content: Text(l10n.schedulePastDayBlocked),
          ),
        );
      return;
    }

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

    // Build a single-date override (start == end).
    //   • DAY_OFF: plain full day off — no intervals, no times.
    //   • CUSTOM_HOURS INTERVAL: collapsed working-interval list.
    //   • CUSTOM_HOURS EXPLICIT_TIMES: discrete start times (Phase 15.8).
    final ScheduleOverride override;
    if (_dayOff) {
      override = ScheduleOverride.dayOff(start: widget.date, end: widget.date);
    } else if (_workMode == WeekdayMode.explicitTimes) {
      override = ScheduleOverride.explicitTimes(
        start: widget.date,
        end: widget.date,
        times: _times,
      );
    } else {
      override = ScheduleOverride.custom(
        start: widget.date,
        end: widget.date,
        intervals: _day.toIntervals(),
        // Persist the edited від–до as display-only metadata so an edge-flush
        // break survives the next load. Containment holds by construction:
        // `toIntervals()` walks this exact window and clamps to it.
        //
        // Sent UNCONDITIONALLY — including when [widget.initialWindow] was null
        // (a legacy row saved before the window existed), which is how such a
        // row heals itself on its first re-save. This is the deliberate inverse
        // of `ScheduleMapper`'s "never synthesise a window from the intervals"
        // rule; that rule binds the READ path only. See the EXCEPTION note in
        // `data/schedule_mapper.dart`'s header before restoring `null` here.
        window: _day.window.clone(),
      );
    }

    if (kDebugMode) {
      log(
        'save override ${widget.date.toIso8601String()} '
        'kind=${override.kind.name}',
        name: _tag,
        level: 800,
      );
    }

    try {
      final bool persisted = await _saveWithConflictCheck(
        override,
        l10n,
        messenger,
      );
      if (!persisted || !mounted) return;
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

  /// The 2026-07-26 booking-conflict flow: check → (confirm dialog) → save.
  ///
  ///   1. [OverridesNotifier.checkConflicts] for [override] — ONE
  ///      `POST /overrides/conflicts` call, never per-date fan-out (this
  ///      sheet only ever edits one date, so there is nothing to fan out).
  ///   2. Empty result → falls straight through to the PUT — byte-for-byte
  ///      the pre-existing save, no dialog, no extra tap.
  ///   3. Non-empty → [showDayOffConflictDialog]. Confirm → PUT with
  ///      `cancelOverlapping: true` and, on success, invalidate every booking
  ///      view the now-declined bookings could be cached in. Back out
  ///      (`null`) → returns `false` WITHOUT writing anything — not even the
  ///      override itself; the sheet stays open exactly as the master left
  ///      it.
  ///   4. A [ConflictFailure] on the confirmed PUT (the conflict set changed
  ///      between step 1 and step 3 — e.g. a client booked a now-conflicting
  ///      slot in the meantime) re-runs step 1 rather than surfacing a raw
  ///      error, bounded to [_kMaxConflictCheckAttempts] rounds.
  ///   5. A failure of the CHECK itself (step 1) — network down, server
  ///      error — shows [showDayOffCheckErrorDialog] rather than silently
  ///      falling back to an unchecked save (saving blind is exactly what
  ///      this whole flow exists to prevent); tapping its retry re-enters the
  ///      loop at the SAME attempt budget (a check-network retry is a
  ///      separate, fully user-gated concern from the 409-retry bound).
  ///
  /// A LOOP, not recursion, on purpose: `_saving` (the sheet's own Save
  /// button spinner) must be `true` ONLY while a network call is genuinely
  /// in flight, and `false` while a dialog is on screen waiting for the
  /// master — an indeterminate [CircularProgressIndicator] never settles, so
  /// leaving it spinning under an open dialog would both look broken and
  /// hang any `pumpAndSettle()` in tests. Toggling it explicitly around each
  /// `await` (rather than once for the whole method, as the pre-conflict-gate
  /// code did) keeps that contract regardless of how many check/confirm
  /// rounds this takes.
  ///
  /// Returns `true` only when [override] was actually persisted.
  Future<bool> _saveWithConflictCheck(
    ScheduleOverride override,
    AppLocalizations l10n,
    ScaffoldMessengerState messenger,
  ) async {
    final OverridesNotifier notifier = ref.read(
      overridesProvider(widget.range).notifier,
    );
    int attempt = 0;

    while (true) {
      if (mounted) setState(() => _saving = true);
      final OverrideConflictCheck check;
      try {
        check = await notifier.checkConflicts(override);
      } on Failure {
        if (mounted) setState(() => _saving = false);
        if (!mounted) return false;
        final bool? retry = await showDayOffCheckErrorDialog(context);
        if (retry != true || !mounted) return false;
        continue;
      }
      if (mounted) setState(() => _saving = false);
      if (!mounted) return false;

      bool cancelOverlapping = false;
      if (check.isNotEmpty) {
        // The dialog renders every affected booking's `clientDisplayName` —
        // PII — so it acquires screenshot/app-switcher-snapshot protection
        // for exactly as long as it is on screen, same ref-counted contract
        // every other PII-bearing screen uses (`core/security/
        // screen_protection.dart`), just scoped to this one dialog instead
        // of the sheet's whole lifetime (the sheet itself carries no PII
        // outside this branch).
        final ScreenProtectionManager screenProtection = ref.read(
          screenProtectionProvider,
        );
        screenProtection.acquire();
        final bool? confirmed;
        try {
          confirmed = await showDayOffConflictDialog(
            context,
            DayOffConflictPreview(
              kind: override.kind == OverrideKind.dayOff
                  ? DayOffChangeKind.singleDay
                  : DayOffChangeKind.narrowedHours,
              from: override.start,
              to: override.end,
              hoursLabel: override.narrowedHoursLabel,
              check: check,
            ),
          );
        } finally {
          screenProtection.release();
        }
        // Backing out (any non-`true` resolution: the quiet action, the
        // scrim tap, the back gesture) means *do nothing* — the schedule
        // change itself is not saved either, per the locked design.
        if (confirmed != true || !mounted) return false;
        cancelOverlapping = true;
      }

      if (mounted) setState(() => _saving = true);
      await notifier.putOverride(
        override,
        cancelOverlapping: cancelOverlapping,
      );
      if (!mounted) return false;
      // [OverridesNotifier.putOverride] wraps its work in `AsyncValue.guard`,
      // so a failed PUT does NOT throw here — it surfaces as an [AsyncError]
      // on the provider state. Read that resulting state and branch on it.
      final AsyncValue<List<ScheduleOverride>> result = ref.read(
        overridesProvider(widget.range),
      );
      if (mounted) setState(() => _saving = false);

      if (!result.hasError) {
        if (cancelOverlapping) {
          invalidateBookingViewsAfterExternalDecline(
            ref,
            check.conflicts.map((OverrideConflict c) => c.bookingId),
            affectedDates: check.conflicts.map((OverrideConflict c) => c.date),
          );
        }
        return true;
      }

      final Object? error = result.error;
      attempt++;
      if (error is ConflictFailure && attempt < _kMaxConflictCheckAttempts) {
        continue;
      }
      _showError(messenger, error, l10n);
      return false;
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
                  style: VelvetText.body13,
                ),
                const SizedBox(height: VelvetSpacing.lg),
                _modeToggle(l10n),
                const SizedBox(height: VelvetSpacing.lg),
                if (_dayOff)
                  _dayOffSection(l10n)
                else ...<Widget>[
                  // ── Work-mode sub-toggle (Інтервал / Окремі години) ──────
                  Semantics(
                    label: l10n.discreteTimesModeSemantic,
                    child: Row(
                      key: const Key('override-work-mode-toggle'),
                      children: <Widget>[
                        Expanded(
                          child: _modeChip(
                            valueKey: const Key('override-work-mode-interval'),
                            label: l10n.discreteTimesSegmentInterval,
                            icon: Icons.schedule_rounded,
                            selected: _workMode == WeekdayMode.interval,
                            onTap: () => _setWorkMode(WeekdayMode.interval),
                          ),
                        ),
                        const SizedBox(width: VelvetSpacing.sm + 2),
                        Expanded(
                          child: _modeChip(
                            valueKey: const Key('override-work-mode-explicit'),
                            label: l10n.discreteTimesSegmentExplicit,
                            icon: Icons.more_time_rounded,
                            selected: _workMode == WeekdayMode.explicitTimes,
                            onTap: () =>
                                _setWorkMode(WeekdayMode.explicitTimes),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: VelvetSpacing.lg),
                  // ── Editor body — swaps on work-mode change ───────────────
                  if (_workMode == WeekdayMode.interval)
                    IntervalEditor(
                      day: _day,
                      onChanged: () => setState(() {}),
                      strings: _intervalStrings(l10n),
                      fieldKeyPrefix: 'override',
                    )
                  else
                    DiscreteTimesEditor(
                      times: _times,
                      onChanged: () => setState(() {}),
                      strings: _discreteStrings(l10n),
                      fieldKeyPrefix: 'override',
                    ),
                ],
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
              style: VelvetText.bodyStrong13.copyWith(color: tint),
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

  // ── Day-off mode: a plain full day off (no reason, no note) ─────────────────
  /// A single clean rest affordance — a neumorphic-bordered card stating the
  /// date is fully closed for bookings. The backend dropped reason/note from
  /// schedule overrides, so day-off mode collects no input at all.
  Widget _dayOffSection(AppLocalizations l10n) {
    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        key: const Key('override-dayoff-rest'),
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
      ),
    );
  }

  // ── Revert-to-template action (only when an override already exists) ────────
  /// Clears the per-date customization and returns the date to the recurring
  /// weekly template. Non-destructive (no data the user typed is lost), so it
  /// reads as the calm camel accent rather than the error red.
  Widget _deleteAction(AppLocalizations l10n) {
    final Color tint = BrandColors.accentDeep.withValues(
      alpha: _saving ? 0.4 : 1.0,
    );
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
                Icon(Icons.restore_rounded, size: 17, color: tint),
                const SizedBox(width: VelvetSpacing.sm - 2),
                Text(
                  l10n.scheduleOverrideDelete,
                  style: VelvetText.link13.copyWith(color: tint),
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
        errBreakCoversWholeWindow: l10n.intervalEditorErrBreakCoversWholeDay,
        errTimeNotAligned: l10n.scheduleErrTimeNotAligned,
      );

  /// All localised copy the [DiscreteTimesEditor] needs (Phase 15.8).
  DiscreteTimesEditorStrings _discreteStrings(AppLocalizations l10n) =>
      DiscreteTimesEditorStrings(
        addTimeLabel: l10n.discreteTimesAddTime,
        windowSummary: l10n.scheduleDiscreteTimesWindowSummary,
        removeTimeSemantic: l10n.discreteTimesRemoveSemantic,
        timePickerTitle: l10n.discreteTimesPickerTitle,
        timePickerConfirm: l10n.timePickerConfirm,
        timePickerHoursSemantic: l10n.timePickerHoursSemantic,
        timePickerMinutesSemantic: l10n.timePickerMinutesSemantic,
        errEmpty: l10n.discreteTimesErrEmpty,
        duplicateMessage: l10n.discreteTimesDuplicateMessage,
      );
}
