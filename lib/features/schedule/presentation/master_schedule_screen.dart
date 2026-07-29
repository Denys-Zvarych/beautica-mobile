// Phase 15.2 — MasterScheduleScreen («Графік роботи»).
//
// The calendar-first schedule shell — a literal port of the approved preview
// `docs/signup-designs/MasterSchedule/lib/screens/master_schedule_screen.dart`,
// adapted to the project's Riverpod + go_router structure:
//   • preview StatefulWidget + Navigator  → ConsumerStatefulWidget + context.go
//   • preview in-memory `DaySchedule` sample → real [EffectiveDay] data from the
//     Phase 15.1 `effectiveScheduleProvider` (keyed by the visible month range)
//   • preview SnackBar dead-ends           → routed editor stubs (15.3–15.5)
//   • preview tokens (Velvet*)             → BrandColors / VelvetText / Velvet*
//
// Top → bottom: header · weekly-template pill card · "Календар" header · month
// navigator · week date-strip (with override dots) · selected-day panel · the
// 30-min availability grid · legend. A persistent NO_SCHEDULE banner (OQ-3)
// mounts above the grid when the viewed day/period has no published hours.
//
// Role gating (OQ-2): every edit affordance is gated on
// [scheduleEditableProvider]. A read-only viewer (SALON_MASTER) sees the full
// read content but no edit entry points (no pencil, no card tap, no banner CTA).

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/app_refresh_indicator.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/uk_calendar.dart';
import 'package:beautica_mobile/shared/widgets/velvet_bottom_nav_bar.dart';
import 'package:beautica_mobile/shared/widgets/velvet_top_bar.dart';

import '../domain/schedule_model.dart';
import '../domain/weekly_schedule.dart';
import 'day_hours_sheet.dart';
import 'effective_schedule_notifier.dart';
import 'schedule_capability.dart';
import 'schedule_range.dart';
import 'weekly_schedule_notifier.dart';
import 'widgets/day_schedule.dart';
import 'widgets/schedule_widgets.dart';
import 'widgets/slot_colors.dart';

/// The calendar-first Master Schedule screen.
class MasterScheduleScreen extends ConsumerStatefulWidget {
  const MasterScheduleScreen({super.key, DateTime Function()? clock})
    : _clock = clock;

  /// Injectable LIVE "now" source (wall-clock decoupling, mirroring
  /// [WeeklyTemplateEditorScreen]): "today" — which day the calendar selects on
  /// mount, anchors its month/week request on, and gates past days against —
  /// resolves from this. It is a callback (not a frozen snapshot) so the
  /// past-day gate ([_isPast]) and the add-hours affordance stay correct across
  /// a midnight rollover: the cell that was "today" when the screen mounted
  /// becomes past (and non-addable) once the day turns over. Defaults to
  /// `DateTime.now()` in production; tests pass a callback over a mutable clock
  /// they can advance so the rendered calendar (and its goldens) stay run-day
  /// independent.
  final DateTime Function()? _clock;

  @override
  ConsumerState<MasterScheduleScreen> createState() =>
      _MasterScheduleScreenState();
}

class _MasterScheduleScreenState extends ConsumerState<MasterScheduleScreen> {
  static const _tag = 'feature.schedule.masterschedule';

  /// Capitalized weekday abbreviations for the week-strip / weekly-pill
  /// captions, Monday-first — computed ONCE (perf carry-over from the 23.1
  /// audit: `ukCapitalize` is not memoized, so this must not re-run per cell
  /// or per frame on a scrolling week strip). Byte-identical to the retired
  /// hard-coded 7-entry list this replaces (Phase 23.2).
  static final List<String> _weekdayCaptions = List<String>.unmodifiable(
    <String>[
      for (int day = 1; day <= 7; day++) ukCapitalize(weekdayAbbrev(day)),
    ],
  );

  /// "Today" resolved LIVE from the injected clock (or the device date in
  /// production), date-only — recomputed on every read so the past-day gate
  /// ([_isPast]) and the add-hours affordance follow a midnight rollover instead
  /// of freezing the mount-time date. The initial calendar anchors ([_selected],
  /// [_visibleMonth], [_weekStart]) intentionally capture this once on mount.
  DateTime get _today => _dateOnly(widget._clock?.call() ?? DateTime.now());

  /// Selected date as a notifier (HIGH-1): day selection updates this WITHOUT a
  /// `setState`, so only the listeners — the two affected week-strip pills and
  /// the isolated [_SelectedDayView] — rebuild. The static siblings
  /// (month navigator, weekly-template card, legend) never re-run on a tap.
  late final ValueNotifier<DateTime> _selected = ValueNotifier<DateTime>(
    _today,
  );

  late DateTime _visibleMonth = DateTime(_today.year, _today.month);

  /// Monday of the week currently shown in the strip.
  late DateTime _weekStart = _mondayOf(_today);

  @override
  void dispose() {
    _selected.dispose();
    super.dispose();
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _mondayOf(DateTime d) =>
      _dateOnly(d).subtract(Duration(days: d.weekday - 1));

  /// True when [d] falls strictly before today (today itself stays selectable).
  bool _isPast(DateTime d) => _dateOnly(d).isBefore(_today);

  bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Whether a resolved [EffectiveDay] is a WORKING day for the week-strip dot /
  /// template-pill verdict. Phase 15.9: an EXPLICIT_TIMES day carries discrete
  /// `times` but NO `intervals`, so the legacy `intervals.isNotEmpty` test alone
  /// would render it (incorrectly) as closed. A day works iff it has continuous
  /// intervals OR ≥1 discrete time.
  static bool _isWorkingDay(EffectiveDay day) =>
      day.intervals.isNotEmpty || day.isExplicitTimes;

  // ── Range that backs the visible month UNION the displayed week ────────────
  // The week strip can straddle a month boundary (e.g. Mon 29 Jun → Sun 5 Jul):
  // `_visibleMonth` resolves to the majority month, so a plain
  // `ScheduleRange.month(_visibleMonth)` leaves the spillover days (29–30 Jun)
  // uncovered. `_DayIndex.lookup` would then serve a NO_SCHEDULE fallback for
  // them and render those cells as day-off even when the weekly template marks
  // them working. We instead fetch the UNION of the month and the visible week
  // so every cell the strip and the template pills read is server-authoritative
  // (overrides on spillover days resolve too — no fallback widening).
  //
  // Width stays bounded: a calendar month (≤31 days) plus at most 6 spillover
  // days on either side is ≤ ~37 days — well under `kMaxScheduleRangeDays` (366).
  // The key stays stable per (visibleMonth, weekStart) pair, so Riverpod family
  // caching does not thrash within a fixed month+week view.
  ScheduleRange get _range {
    final DateTime monthFirst = DateTime(
      _visibleMonth.year,
      _visibleMonth.month,
    );
    final DateTime monthLast = DateTime(
      _visibleMonth.year,
      _visibleMonth.month + 1,
      0,
    );
    final DateTime weekFirst = _dateOnly(_weekStart);
    final DateTime weekLast = weekFirst.add(const Duration(days: 6));
    final DateTime from = weekFirst.isBefore(monthFirst)
        ? weekFirst
        : monthFirst;
    final DateTime to = weekLast.isAfter(monthLast) ? weekLast : monthLast;
    return ScheduleRange(from: from, to: to);
  }

  // ── Navigation ─────────────────────────────────────────────────────────────
  // Day selection mutates the notifier only (no setState): the static calendar
  // chrome stays put; just the strip highlight + selected-day view rebuild.
  void _selectDate(DateTime d) => _selected.value = d;

  void _stepMonth(int delta) {
    // Capture the weekday offset of the current selection within the OLD week
    // before the window moves, so we can re-anchor onto the same column.
    final int offset = _selectedWeekdayOffset();
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta);
      _weekStart = _mondayOf(
        DateTime(_visibleMonth.year, _visibleMonth.month, 1),
      );
    });
    // Re-anchor the selection into the new visible week, preserving its column.
    // Notifier-only (no setState) — mirrors `_selectDate`'s HIGH-1 scoping. The
    // result is guaranteed inside `_range` (which covers the new `_weekStart`),
    // so `_DayIndex.lookup` resolves real data instead of the NO_SCHEDULE
    // fallback.
    _selected.value = _dateOnly(_weekStart.add(Duration(days: offset)));
  }

  /// Offset (0..6) of the current selection from the CURRENT `_weekStart`,
  /// clamped so a selection outside the visible week still lands on a valid
  /// column when re-anchored.
  int _selectedWeekdayOffset() {
    final int diff = _dateOnly(_selected.value).difference(_weekStart).inDays;
    return diff.clamp(0, 6);
  }

  /// The month that owns a Monday-anchored week — the month containing the 4th
  /// day (Thursday), which is always in the majority month.
  static DateTime _monthOfWeek(DateTime weekStart) {
    final DateTime mid = weekStart.add(const Duration(days: 3));
    return DateTime(mid.year, mid.month);
  }

  void _stepWeek(int delta) {
    // Capture the weekday offset of the current selection within the OLD week
    // before the window moves, so the highlight stays in the same column.
    final int offset = _selectedWeekdayOffset();
    setState(() {
      final next = _weekStart.add(Duration(days: delta * 7));
      _weekStart = _dateOnly(next);
      _visibleMonth = _monthOfWeek(_weekStart);
    });
    // Re-anchor the selection into the new visible week, preserving its column.
    // Notifier-only (no setState) — mirrors `_selectDate`'s HIGH-1 scoping. The
    // result is guaranteed inside `_range` (which covers the new `_weekStart`),
    // so `_DayIndex.lookup` resolves real data instead of the NO_SCHEDULE
    // fallback.
    _selected.value = _dateOnly(_weekStart.add(Duration(days: offset)));
  }

  void _goToday() {
    _selected.value = _today;
    setState(() {
      _visibleMonth = DateTime(_today.year, _today.month);
      _weekStart = _mondayOf(_today);
    });
  }

  // ── Edit entry points (routed stubs; gated by [scheduleEditableProvider]) ───
  void _openTemplateEditor() {
    if (kDebugMode) log('open weekly template editor', name: _tag, level: 800);
    // Phase 15.5 — route to the REAL weekly-template editor (saves via the
    // `weekly-schedules` data path the calendar reads), NOT the deprecated
    // `working_hours` editor at [RouteNames.workingHours].
    context.push(RouteNames.scheduleWeeklyEditor);
  }

  /// Phase 15.4 — opens the per-date override modal sheet ([DayHoursSheet]) for
  /// [day], seeded from the day's current effective intervals / day-off reason.
  /// Replaces the old push to the retired `PerDateOverrideStubScreen`.
  ///
  /// The sheet mutates `overridesProvider(_range)` (the SAME family key the
  /// calendar watches). Because `effectiveScheduleProvider(range)` now
  /// `ref.watch`es `overridesProvider(range)`, that mutation makes the effective
  /// schedule recompute + re-fetch reactively, so the week strip dots + the grid
  /// repaint with no manual refresh. Past days never reach here — the pencil is
  /// hidden on them.
  Future<void> _openDayOverride(EffectiveDay day) async {
    if (kDebugMode) log('open per-date override', name: _tag, level: 800);
    final bool hasOverride =
        day.source == EffectiveSource.overrideCustom ||
        day.source == EffectiveSource.overrideDayOff;
    final bool dayOff = day.source == EffectiveSource.overrideDayOff;
    // Capture the range the edit targets BEFORE awaiting — a month step while
    // the sheet is open would change `_range` out from under us.
    final ScheduleRange editedRange = _range;
    final DateTime? changed = await DayHoursSheet.show(
      context,
      date: day.date,
      weekdayFull: _weekdayFull(day.date),
      dateLabel: formatDay(day.date),
      range: editedRange,
      initialIntervals: day.intervals,
      // Stored display-only window (may be null on a legacy row) — lets the
      // sheet re-render a break flush against a window edge instead of losing it
      // to gap reconstruction.
      initialWindow: day.window,
      hasExistingOverride: hasOverride,
      initialDayOff: dayOff,
      // Phase 15.8: seed the work-mode sub-toggle from the resolved effective day.
      initialMode: day.isExplicitTimes
          ? WeekdayMode.explicitTimes
          : WeekdayMode.interval,
      initialTimes: day.times,
      // Thread the LIVE clock so the sheet's submit-time past-date guard sees a
      // midnight rollover that happens while the sheet is open.
      clock: widget._clock,
    );
    // Plain dismiss (close / barrier / validation bail) → nothing changed.
    if (changed == null || !mounted) return;

    // (a) Move the selected day onto the changed date so the selected-day panel
    // focuses it. Notifier-only (no setState) — preserves the HIGH-1 scope.
    _selected.value = _dateOnly(changed);

    // (b) Show the saved changes immediately. The override save reloaded
    // `overridesProvider(editedRange)`, which (via the reactive `ref.watch`
    // dependency) makes `effectiveScheduleProvider(editedRange)` recompute and
    // re-fetch. That refetch is a SEAMLESS reload in Riverpod 3.x — its
    // in-flight state retains the previous (pre-save) value — so the range-aware
    // guard in [_body] deliberately routes this same-range reload through the
    // loading gate instead of serving the retained stale snapshot. Awaiting the
    // provider's `.future` here resolves to the GENUINE refetch result (not the
    // retained previous value), so the next rebuild lands with the fresh
    // override already resolved — no stale render, no manual re-tap. Scoped to
    // the edited range only (does not widen the family invalidation).
    try {
      await ref.read(effectiveScheduleProvider(editedRange).future);
    } on Object {
      // A failed refetch surfaces through the normal AsyncError → _ErrorBody
      // path on the next build; nothing extra to do here.
    }
  }

  // ── Effective-day lookup from the resolved range ───────────────────────────
  // Perf (MEDIUM-2): the previous helpers linear-scanned `days` ~15×/build (one
  // O(n) walk per strip cell + the panel + the whole-week check) and allocated
  // a fresh fallback [EffectiveDay] on every miss. We now build a date→day
  // [_DayIndex] ONCE per resolved list (cached by list identity) for O(1)
  // lookups, and reuse a single memoized NO_SCHEDULE fallback for gaps.
  _DayIndex? _indexCache;
  List<EffectiveDay>? _indexedDays;

  /// Loading-flash fix: the last successfully-resolved effective-days list,
  /// retained across month-key changes. `effectiveScheduleProvider` is a family
  /// keyed by the visible month, so stepping a month yields a fresh
  /// `AsyncLoading` whose `.value` is null for the new family member (Riverpod's
  /// previous-data retention does NOT survive a family-key change). Caching the
  /// last good list lets us keep showing the previous month's content with a
  /// subtle inline indicator during the brief reload — the full-screen spinner
  /// is reserved for the genuine first load, when this is still null.
  ///
  /// Save-freshness fix (the bug this re-fix targets): a SAME-range post-save
  /// reload is SEAMLESS in Riverpod 3.x — the new `AsyncLoading` carries the
  /// PREVIOUS data via `copyWithPrevious`, so `asyncDays.value` is NOT null and
  /// keying off `value == null` to detect the reload is a dead branch. We must
  /// therefore distinguish the two reload kinds by RANGE, not by null-ness:
  ///   • range differs from [_lastDaysRange]  → month step → keep stale content;
  ///   • range matches [_lastDaysRange] while refreshing → post-save → do NOT
  ///     adopt the retained previous value as fresh; wait for the genuine
  ///     refetch result (see [_body]).
  /// Critically, we only update [_lastDays]/[_lastDaysRange] from a value that is
  /// NOT a seamless-retained reload snapshot, so a same-range refresh never
  /// caches the stale list as if it were fresh.
  List<EffectiveDay>? _lastDays;

  /// The [ScheduleRange] [_lastDays] was captured for. Distinguishes a
  /// month-step reload (range differs → keep stale content) from a same-range
  /// post-save reload (range matches → do not serve stale).
  ScheduleRange? _lastDaysRange;

  _DayIndex _indexOf(List<EffectiveDay> days) {
    if (identical(_indexedDays, days) && _indexCache != null) {
      return _indexCache!;
    }
    final index = _DayIndex(days);
    _indexedDays = days;
    _indexCache = index;
    return index;
  }

  /// True when EVERY day of the visible week is NO_SCHEDULE — drives the
  /// whole-period banner copy.
  bool _wholeWeekUnscheduled(_DayIndex index) {
    for (int i = 0; i < 7; i++) {
      final EffectiveDay d = index.lookup(_weekStart.add(Duration(days: i)));
      if (d.source != EffectiveSource.noSchedule) return false;
    }
    return true;
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final editable = ref.watch(scheduleEditableProvider);
    final asyncDays = ref.watch(effectiveScheduleProvider(_range));
    // The global "has the master published ANY schedule?" signal. Watched
    // alongside the visible range so the empty-state decision is a global
    // verdict (no weekly template defined) rather than a per-month one.
    final asyncWeekly = ref.watch(weeklyScheduleProvider);

    return Scaffold(
      backgroundColor: BrandColors.base,
      // Tile 2 ("Графік") — this screen IS that destination. Hosted via
      // Scaffold's own slot (not nested inside the body SafeArea below) so it
      // mounts identically to the other three master tab screens — see
      // `VelvetBottomNavBar`'s doc comment and `ProfileScaffold.bottomNavBar`.
      // `Scaffold` zeroes the bottom `MediaQuery` padding it hands to `body`
      // whenever `bottomNavigationBar` is non-null, so the outer `SafeArea`
      // below consumes nothing extra here — no double-counted inset.
      bottomNavigationBar: const VelvetBottomNavBar(activeIndex: 2),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            VelvetTopBar(
              title: l10n.scheduleTitle,
              backSemanticLabel: l10n.registerBackStep,
              onBack: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go(RouteNames.masterProfile);
                }
              },
            ),
            Expanded(child: _body(l10n, editable, asyncDays, asyncWeekly)),
          ],
        ),
      ),
    );
  }

  /// Combines the effective-range and weekly-template async states cleanly:
  ///   • either errored  → the retry body (invalidates both sources);
  ///   • both have data  → the empty state when the master has NO schedule at
  ///     all, otherwise the full calendar; the empty-state verdict needs both
  ///     resolved lists, so a value from one + loading from the other still
  ///     shows the spinner;
  ///   • otherwise        → spinner.
  Widget _body(
    AppLocalizations l10n,
    bool editable,
    AsyncValue<List<EffectiveDay>> asyncDays,
    AsyncValue<List<WeeklySchedule>> asyncWeekly,
  ) {
    // Either source erroring takes precedence: show the retry body.
    if (asyncDays.hasError) {
      return _ErrorBody(
        failure: asyncDays.error!,
        onRetry: () => ref.invalidate(effectiveScheduleProvider(_range)),
      );
    }
    if (asyncWeekly.hasError) {
      return _ErrorBody(
        failure: asyncWeekly.error!,
        onRetry: () => ref.invalidate(weeklyScheduleProvider),
      );
    }

    // Riverpod 3.x state discrimination (the heart of this re-fix):
    //
    //  • A MONTH STEP creates a NEW family member (different `range` key). That
    //    instance has no prior state, so `isLoading == true`, `.value == null`,
    //    and BOTH `isRefreshing`/`isReloading` are false (they require a
    //    previously-emitted value). We tell it apart from a genuine first load
    //    by the presence of a cached list for a DIFFERENT range.
    //
    //  • A POST-SAVE SAME-RANGE reload rebuilds the SAME family member because
    //    its watched dependency (`overridesProvider(range)`) changed. That is a
    //    SEAMLESS reload: `isLoading == true`, `isReloading == true`, and
    //    `.value` RETAINS the previous (pre-save) data via `copyWithPrevious`.
    //    Keying off `value == null` here is a dead branch — the old bug. We use
    //    `isReloading` instead and DO NOT treat the retained value as fresh.
    //
    //  • A SETTLED state (`!isLoading`) with a non-null `.value` is fresh.
    final bool reloadingSameMember = asyncDays.isReloading;
    final List<EffectiveDay>? freshValue = (!asyncDays.isLoading)
        ? asyncDays.value
        : null;

    // Cache the FRESH list only (tagged with its range). A seamless-retained
    // reload snapshot is NOT fresh and must never be cached as if it were, or
    // the same-range post-save path would re-serve the pre-save list.
    if (freshValue != null) {
      _lastDays = freshValue;
      _lastDaysRange = _range;
    }

    // A month-step reload: this range is loading for the first time, but we hold
    // a good list captured for a DIFFERENT range. Keep showing it (with the
    // inline progress line) so the previous month does not flash to a spinner.
    final bool monthStepReload =
        freshValue == null &&
        !reloadingSameMember &&
        _lastDays != null &&
        _lastDaysRange != _range;

    // Decide what to render:
    //   • fresh settled value   → use it directly;
    //   • month-step reload     → the cached previous-range list (stale-but-OK);
    //   • everything else (genuine first load OR same-range post-save reload)
    //     → null → the spinner gate below. For the post-save case this is
    //       deliberate: we wait for the genuine refetch instead of repainting
    //       the just-edited day with its retained pre-save intervals.
    final List<EffectiveDay>? days =
        freshValue ?? (monthStepReload ? _lastDays : null);
    final List<WeeklySchedule>? weekly = asyncWeekly.value;
    // Both must be resolved before we can decide empty vs. full. With the cache
    // in play this only stays null on the genuine FIRST load OR a same-range
    // post-save reload (where we intentionally wait for the fresh value).
    if (days == null || weekly == null) {
      return const Center(
        child: CircularProgressIndicator(color: BrandColors.accent),
      );
    }

    // The subtle inline progress line is reserved for the month-step reload (we
    // are showing the previous month's cached content while the new month
    // resolves). A same-range post-save reload never reaches here — it went
    // through the spinner gate above — so this never flashes stale content for
    // the save path.
    final bool reloading = monthStepReload;

    // "No schedule at all" — no weekly template defined AND no override covers
    // any visible day (every resolved day is NO_SCHEDULE). Both conditions
    // guard against a master who has only per-date overrides but no template.
    final bool noSchedule =
        weekly.isEmpty &&
        days.every((d) => d.source == EffectiveSource.noSchedule);
    if (noSchedule) {
      return _EmptyScheduleBody(
        // OQ-2: the CTA is present only for editable viewers (read-only
        // SALON_MASTER sees the message informationally, no action button).
        onAddHours: editable ? _openTemplateEditor : null,
      );
    }

    return _content(l10n, editable, days, reloading: reloading);
  }

  Widget _content(
    AppLocalizations l10n,
    bool editable,
    List<EffectiveDay> days, {
    bool reloading = false,
  }) {
    final _DayIndex index = _indexOf(days);
    final Widget list = ListView(
      // AlwaysScrollableScrollPhysics ensures RefreshIndicator can always be
      // triggered, even when content is shorter than the viewport.
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(
        VelvetSpacing.md,
        VelvetSpacing.sm,
        VelvetSpacing.md,
        VelvetSpacing.xxl,
      ),
      children: <Widget>[
        _templateCard(l10n, editable, index),
        const SizedBox(height: VelvetSpacing.lg + 4),
        SectionHeader(title: l10n.scheduleCalendarSection),
        const SizedBox(height: VelvetSpacing.md),
        _calendarCard(l10n, editable, index, reloading: reloading),
      ],
    );

    // Loading-flash fix: on a month-change reload keep the (stale) content fully
    // visible and overlay a thin top progress line — no layout shift, dismissed
    // the instant the new month resolves. First load never reaches here (it goes
    // through the full-screen spinner gate above).
    final Widget stack = Stack(
      children: <Widget>[
        list,
        if (reloading)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: LinearProgressIndicator(
                minHeight: 2,
                color: BrandColors.accent,
                backgroundColor: Colors.transparent,
              ),
            ),
          ),
      ],
    );

    // Pull-to-refresh: invalidate BOTH the effective schedule for the current
    // visible range AND the weekly-schedule template. The screen's own
    // _body() method re-runs as soon as the providers rebuild.
    // Riverpod 3.x note: invalidate + await .future — never gate on value==null.
    return AppRefreshIndicator(
      onRefresh: () async {
        ref.invalidate(effectiveScheduleProvider(_range));
        ref.invalidate(weeklyScheduleProvider);
        try {
          await Future.wait([
            ref.read(effectiveScheduleProvider(_range).future),
            ref.read(weeklyScheduleProvider.future),
          ]);
        } on Object {
          // Errors surface through the normal AsyncError → _ErrorBody path.
        }
      },
      child: stack,
    );
  }

  // ── Weekly-template card ─────────────────────────────────────────────────--
  // Tappable to open the template editor (editable viewers only); a trailing
  // pencil signals the affordance. The seven pills reflect which ISO weekdays
  // are working days FOR THE CURRENTLY-DISPLAYED WEEK (`_weekStart`..+6) — the
  // exact same per-day verdict the week strip below renders. Scoping to the
  // visible week (not the whole month) means a one-off single-date override
  // (e.g. a Friday added "only this week") lights its pill ONLY while that week
  // is displayed; navigating to another week recomputes the pills for that week.
  Widget _templateCard(AppLocalizations l10n, bool editable, _DayIndex index) {
    final List<bool> template = _templatePattern(index);
    final card = NeumorphicCard(
      padding: const EdgeInsets.all(VelvetSpacing.md + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.calendar_month_rounded,
                size: 20,
                color: BrandColors.accentDeep,
              ),
              const SizedBox(width: VelvetSpacing.sm + 2),
              Expanded(
                child: Text(
                  l10n.scheduleWeeklyCardTitle,
                  style: VelvetText.subheading(),
                ),
              ),
              if (editable)
                const Icon(
                  Icons.edit_outlined,
                  size: 18,
                  color: BrandColors.accentDeep,
                ),
            ],
          ),
          const SizedBox(height: VelvetSpacing.md + 2),
          WeekdayPillRow(
            // Structural signal of the displayed week's active-weekday set so a
            // widget test can assert week-scoping without relying on a golden:
            // the value-key encodes the 7 ISO booleans (Mon→Sun) for the week
            // currently shown. Changing weeks changes this key.
            key: ValueKey<String>(
              'schedule-weekly-pills-${template.map((b) => b ? '1' : '0').join()}',
            ),
            labels: _weekdayCaptions,
            active: template,
          ),
        ],
      ),
    );

    if (!editable) {
      return Semantics(label: l10n.scheduleWeeklyCardTitle, child: card);
    }
    return Semantics(
      button: true,
      label: l10n.scheduleWeeklyCardEditSemantic,
      child: GestureDetector(
        key: const Key('schedule-weekly-card'),
        onTap: _openTemplateEditor,
        behavior: HitTestBehavior.opaque,
        child: card,
      ),
    );
  }

  /// Derives the seven ISO weekday working/closed booleans for the CURRENTLY-
  /// DISPLAYED WEEK (`_weekStart`..`_weekStart+6`, Monday-first ISO order):
  /// weekday `i` is "active" iff that specific date of the shown week resolves
  /// to a working day (TEMPLATE/OVERRIDE_CUSTOM with non-empty intervals).
  ///
  /// Week-scoped on purpose (the bug fix): the previous version scanned the
  /// whole resolved month, so a one-off single-date override on (say) a Friday
  /// lit the Friday pill for EVERY week of that month. Reading the seven dates
  /// of `_weekStart` through the shared [_DayIndex] makes each pill mirror the
  /// week strip cell directly below it — a current-week-only Friday shows on
  /// this week and disappears the moment another week is displayed.
  ///
  /// Cross-month edge: when the displayed week straddles two months, `_range`
  /// fetches the UNION of the visible month and the displayed week, so the
  /// adjacent-month spillover days ARE covered. [_DayIndex.lookup] returns their
  /// real resolved [EffectiveDay] (template/override), not a NO_SCHEDULE
  /// fallback — so a Monday the template marks working lights its pill even when
  /// that Monday belongs to the previous month. Driving the card off the same
  /// `index` the week strip uses keeps the card and strip 1:1 consistent.
  List<bool> _templatePattern(_DayIndex index) {
    final active = List<bool>.filled(7, false);
    for (int i = 0; i < 7; i++) {
      final DateTime d = _weekStart.add(Duration(days: i));
      if (_isWorkingDay(index.lookup(d))) {
        active[d.weekday - 1] = true;
      }
    }
    return active;
  }

  // ── Month nav + week strip + day panel + grid + legend (one card) ──────────
  // HIGH-1: the `_selected`-dependent sub-tree (selected-day panel + NO_SCHEDULE
  // banner + the 42-cell grid) is extracted into [_SelectedDayView], rebuilt
  // only when the selection (or `editable`) changes via a single
  // [ValueListenableBuilder] on [_selected]. The month navigator and week strip
  // are siblings that do NOT re-run on a day tap.
  //
  // The legend now lives INSIDE the same builder so it can track the selected
  // day's day-off state (it is hidden on a settled day off — see `dayOff`
  // below). [SlotLegend] is a cheap static 3-row [StatelessWidget], so rebuilding
  // it on a day tap is negligible; the perf-critical sub-tree (panel + grid)
  // stays isolated in [_SelectedDayView] as before.
  Widget _calendarCard(
    AppLocalizations l10n,
    bool editable,
    _DayIndex index, {
    bool reloading = false,
  }) {
    return NeumorphicCard(
      padding: const EdgeInsets.all(VelvetSpacing.md + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _monthNavigator(l10n),
          const SizedBox(height: VelvetSpacing.md + 2),
          _weekStrip(l10n, index),
          const SizedBox(height: VelvetSpacing.md),
          const Divider(height: 1, color: BrandColors.faint),
          const SizedBox(height: VelvetSpacing.md),
          ValueListenableBuilder<DateTime>(
            valueListenable: _selected,
            builder: (BuildContext context, DateTime selected, _) {
              // Loading-flash fix: during a week-step reload we are serving the
              // PREVIOUS range's cached list (`reloading == true`). If the newly
              // re-anchored selection falls OUTSIDE that stale range, `index`
              // can't see it (`!contains`) and `lookup` would manufacture a
              // NO_SCHEDULE fallback — which the detail panel would render as a
              // definitive day-off banner, then flip to working once the fetch
              // lands. Suppress that verdict with a neutral placeholder while the
              // coverage is genuinely unknown.
              //
              // Strictly gated on (in-flight reload AND not covered): once the
              // fetch settles, `reloading` is false and the fresh `index` covers
              // the selection, so a LEGITIMATE day-off renders its banner
              // normally. A real NO_SCHEDULE within a covered range is never
              // suppressed.
              final bool coverageUnknown =
                  reloading && !index.contains(selected);
              if (coverageUnknown) {
                return _SelectedDayLoadingPlaceholder(label: l10n.loadingLabel);
              }
              final EffectiveDay day = index.lookup(selected);
              // Single source of truth for the day-off verdict: a settled day
              // off has no working intervals, is NOT an EXPLICIT_TIMES day
              // (Phase 15.9 — those carry discrete times but no intervals, yet
              // are working days), AND is not the unset/uncovered NO_SCHEDULE
              // state. [_SelectedDayView] receives this and the legend below is
              // hidden for it (the day-off empty state already communicates "no
              // hours"; the swatch legend is redundant noise).
              final bool dayOff =
                  day.intervals.isEmpty &&
                  !day.isExplicitTimes &&
                  day.source != EffectiveSource.noSchedule;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _SelectedDayView(
                    day: day,
                    dayOff: dayOff,
                    editable: editable,
                    isPast: _isPast(day.date),
                    wholeWeekUnscheduled: _wholeWeekUnscheduled(index),
                    weekdayFull: _weekdayFull(day.date),
                    onAddHours: _openTemplateEditor,
                    onDayOverride: () => _openDayOverride(day),
                  ),
                  if (!dayOff) ...<Widget>[
                    const SizedBox(height: VelvetSpacing.lg),
                    _legendCard(l10n),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Month navigator ─────────────────────────────────────────────────────--
  Widget _monthNavigator(AppLocalizations l10n) {
    return Row(
      children: <Widget>[
        _navArrow(
          Icons.keyboard_double_arrow_left_rounded,
          l10n.schedulePrevMonth,
          () => _stepMonth(-1),
        ),
        Expanded(
          child: Center(
            // Fixed two-row stack: month always on row 1, year always on row 2,
            // both centered — so the header never wraps inconsistently with
            // width. MergeSemantics collapses the two Text nodes into a single
            // "<month> <year>" announcement for TalkBack.
            child: MergeSemantics(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Text(
                    monthNominative(_visibleMonth.month),
                    textAlign: TextAlign.center,
                    style: VelvetText.monthNavTitle,
                  ),
                  Text(
                    '${_visibleMonth.year}',
                    textAlign: TextAlign.center,
                    style: VelvetText.monthNavTitle,
                  ),
                ],
              ),
            ),
          ),
        ),
        _navArrow(
          Icons.keyboard_double_arrow_right_rounded,
          l10n.scheduleNextMonth,
          () => _stepMonth(1),
        ),
        const SizedBox(width: VelvetSpacing.sm),
        GhostButton(
          key: const Key('schedule-today'),
          label: l10n.scheduleTodayAction,
          onPressed: _goToday,
        ),
      ],
    );
  }

  Widget _navArrow(IconData icon, String label, VoidCallback onTap) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 36,
          width: 36,
          decoration: const BoxDecoration(
            color: BrandColors.base,
            shape: BoxShape.circle,
            boxShadow: VelvetShadows.extrudedSmall,
          ),
          child: Icon(icon, size: 22, color: BrandColors.textSecondary),
        ),
      ),
    );
  }

  // ── Week date-strip ────────────────────────────────────────────────────────
  // HIGH-1: each strip cell listens to [_selected] on its own — a day tap
  // repaints only the two pills whose `selected` flag flips, never the whole
  // strip or the grid. The strip's static content (labels, override dots,
  // past styling) is captured once and reused across selection changes.
  Widget _weekStrip(AppLocalizations l10n, _DayIndex index) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (DragEndDetails details) {
        final double v = details.primaryVelocity ?? 0;
        if (v == 0) return;
        _stepWeek(v < 0 ? 1 : -1);
      },
      child: Row(
        children: <Widget>[
          _weekArrow(
            Icons.chevron_left_rounded,
            l10n.schedulePrevWeek,
            () => _stepWeek(-1),
          ),
          const SizedBox(width: VelvetSpacing.sm - 2),
          Expanded(
            child: Row(
              children: <Widget>[
                for (int i = 0; i < 7; i++)
                  Expanded(
                    child: Builder(
                      builder: (_) {
                        final DateTime d = _weekStart.add(Duration(days: i));
                        // Working flag is selection-independent — computed once
                        // per cell here (same rule as `_templatePattern` / the
                        // top card) and captured; it does not re-run on a day
                        // tap, preserving the HIGH-1 per-cell repaint scope. An
                        // EXPLICIT_TIMES day (Phase 15.9) carries no intervals
                        // but is a working day — count it via [_isWorkingDay].
                        final bool working = _isWorkingDay(index.lookup(d));
                        return ValueListenableBuilder<DateTime>(
                          valueListenable: _selected,
                          builder:
                              (BuildContext context, DateTime selected, _) =>
                                  WeekStripDay(
                                    weekdayLabel: _weekdayCaptions[i],
                                    day: d.day,
                                    selected: _sameDate(d, selected),
                                    working: working,
                                    inMonth: d.month == _visibleMonth.month,
                                    hasOverride: index.hasOverride(d),
                                    past: _isPast(d),
                                    plainSemanticLabel: l10n.scheduleStripDay(
                                      _weekdayCaptions[i],
                                      d.day,
                                    ),
                                    pastSemanticLabel: l10n
                                        .scheduleStripDayPast(
                                          _weekdayCaptions[i],
                                          d.day,
                                        ),
                                    onTap: () => _selectDate(d),
                                  ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: VelvetSpacing.sm - 2),
          _weekArrow(
            Icons.chevron_right_rounded,
            l10n.scheduleNextWeek,
            () => _stepWeek(1),
          ),
        ],
      ),
    );
  }

  Widget _weekArrow(IconData icon, String label, VoidCallback onTap) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 30,
          width: 30,
          decoration: const BoxDecoration(
            color: BrandColors.base,
            shape: BoxShape.circle,
            boxShadow: VelvetShadows.extrudedSmall,
          ),
          child: Icon(icon, size: 20, color: BrandColors.accentDeep),
        ),
      ),
    );
  }

  // ── Legend ────────────────────────────────────────────────────────────────-
  Widget _legendCard(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(VelvetSpacing.md),
      decoration: BoxDecoration(
        color: BrandColors.base,
        borderRadius: BorderRadius.circular(VelvetRadii.field),
        border: Border.all(color: BrandColors.faint.withValues(alpha: 0.5)),
      ),
      child: SlotLegend(l10n: l10n),
    );
  }

  // ── Localised full weekday name (Понеділок … Неділя), ISO order ───────────--
  String _weekdayFull(DateTime date) {
    final l10n = AppLocalizations.of(context);
    return switch (date.weekday) {
      DateTime.monday => l10n.weekdayMon,
      DateTime.tuesday => l10n.weekdayTue,
      DateTime.wednesday => l10n.weekdayWed,
      DateTime.thursday => l10n.weekdayThu,
      DateTime.friday => l10n.weekdayFri,
      DateTime.saturday => l10n.weekdaySat,
      _ => l10n.weekdaySun,
    };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Error body — neumorphic retry, mirroring the working-hours screen.
// ─────────────────────────────────────────────────────────────────────────────
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
            NeumorphicButton(
              key: const Key('schedule-retry'),
              label: l10n.retryLabel,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _EmptyScheduleBody — the focused "no schedule at all" state.
//
// When the master has not published any schedule (no weekly template + no
// override covering the visible range), the whole calendar is replaced by a
// single centered [NoScheduleBanner]: the «графік не задано» whole-period copy +
// the «Додати робочі години» CTA → the weekly-template editor. Deliberately
// renders NONE of the full layout (template card, month navigator, week strip,
// availability grid, legend, quick actions).
//
// Role gating (OQ-2): [onAddHours] is null for read-only viewers, so the banner
// shows informationally with no action button — identical to the in-grid banner.
// ─────────────────────────────────────────────────────────────────────────────
class _EmptyScheduleBody extends StatelessWidget {
  const _EmptyScheduleBody({required this.onAddHours});

  /// Tap handler for the CTA. Null → read-only viewer → CTA is hidden.
  final VoidCallback? onAddHours;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(VelvetSpacing.lg),
        child: NoScheduleBanner(
          message: l10n.scheduleNoSchedulePeriod,
          helper: l10n.scheduleNoScheduleHelper,
          ctaLabel: l10n.scheduleAddHoursCta,
          onAddHours: onAddHours,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _DayIndex (MEDIUM-2) — O(1) date → resolved-day lookup over a resolved range.
//
// Built ONCE per resolved `days` list (the screen caches it by list identity).
// Replaces the previous repeated O(n) scans (~15×/build) and per-miss
// [EffectiveDay] allocations: gaps return a single shared NO_SCHEDULE fallback
// re-dated lazily (one allocation per distinct missing date, memoised), while
// the all-grey / banner semantics are unchanged from the old `_dayFrom`.
// ─────────────────────────────────────────────────────────────────────────────
class _DayIndex {
  _DayIndex(List<EffectiveDay> days)
    : _byDay = <int, EffectiveDay>{
        for (final EffectiveDay d in days) _key(d.date): d,
      };

  final Map<int, EffectiveDay> _byDay;

  // Memoised fallbacks for dates the range doesn't cover (adjacent-month strip
  // bleed). Keyed identically so a repeated lookup of the same gap day reuses
  // its instance instead of re-allocating per call.
  final Map<int, EffectiveDay> _fallbacks = <int, EffectiveDay>{};

  static int _key(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  /// The resolved day for [date], or a NO_SCHEDULE fallback for uncovered dates
  /// (consistent with the backend's gap semantics: all-grey + empty banner).
  EffectiveDay lookup(DateTime date) {
    final int k = _key(date);
    final EffectiveDay? hit = _byDay[k];
    if (hit != null) return hit;
    return _fallbacks[k] ??= EffectiveDay(
      date: DateTime(date.year, date.month, date.day),
      source: EffectiveSource.noSchedule,
      intervals: const <WorkInterval>[],
    );
  }

  bool hasOverride(DateTime date) {
    final EffectiveDay d = lookup(date);
    return d.source == EffectiveSource.overrideCustom ||
        d.source == EffectiveSource.overrideDayOff;
  }

  /// Whether the underlying resolved range actually covers [date] — i.e. the
  /// backend returned a real [EffectiveDay] for it. Unlike [lookup], this does
  /// NOT manufacture a NO_SCHEDULE fallback for uncovered dates, so callers can
  /// distinguish "genuinely a day off" from "outside this (stale) range while a
  /// reload is in flight". Used by the detail panel to suppress the day-off
  /// verdict during a week-step reload whose new range hasn't landed yet.
  bool contains(DateTime date) => _byDay.containsKey(_key(date));
}

// ─────────────────────────────────────────────────────────────────────────────
// _SelectedDayLoadingPlaceholder — neutral stand-in for the selected-day detail
// panel during an in-flight week-step reload where the re-anchored selection is
// not yet covered by the (stale) resolved range. Renders a small centered
// progress line instead of letting `_SelectedDayView` paint a manufactured
// NO_SCHEDULE day-off verdict that would flip to "working" once the new range
// lands. Mirrors the screen's existing thin-line reloading treatment.
// ─────────────────────────────────────────────────────────────────────────────
class _SelectedDayLoadingPlaceholder extends StatelessWidget {
  const _SelectedDayLoadingPlaceholder({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('schedule-selected-day-loading'),
      padding: const EdgeInsets.symmetric(vertical: VelvetSpacing.xl),
      child: Column(
        children: <Widget>[
          const SizedBox(
            width: 120,
            child: LinearProgressIndicator(
              minHeight: 2,
              color: BrandColors.accent,
              backgroundColor: BrandColors.faint,
            ),
          ),
          const SizedBox(height: VelvetSpacing.md),
          Text(
            label,
            style: VelvetText.body().copyWith(color: BrandColors.muted),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _DayOffEmptyState — replaces the all-grey/red 42-cell hour grid on a settled
// day off (no working intervals, not the NO_SCHEDULE "unset" state). A calm,
// centered icon + line instead of a wall of "unavailable" boxes. Mirrors the
// day-off iconography of the per-date override sheet (`_dayOffSection` →
// `Icons.bedtime_rounded`) and the structural treatment of
// `_SelectedDayLoadingPlaceholder`.
// ─────────────────────────────────────────────────────────────────────────────
class _DayOffEmptyState extends StatelessWidget {
  const _DayOffEmptyState();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Padding(
      key: const Key('schedule-day-off-empty'),
      padding: const EdgeInsets.symmetric(vertical: VelvetSpacing.xl),
      // Span the full card width (the parent column is CrossAxisAlignment.start)
      // and center the icon + text horizontally within it.
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            const Icon(
              Icons.bedtime_rounded,
              size: 32,
              color: BrandColors.faint,
            ),
            const SizedBox(height: VelvetSpacing.md),
            Text(
              l10n.scheduleDayOffEmptyState,
              textAlign: TextAlign.center,
              style: VelvetText.body().copyWith(
                color: BrandColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SelectedDayView (HIGH-1 + HIGH-2) — the perf-critical sub-tree that depends
// on the selected date. Rebuilt by a single [ValueListenableBuilder] on the
// screen's `_selected` notifier, so a day tap never re-runs the month
// navigator, the weekly-template card, or the week strip body. (The legend is a
// sibling under the same builder and DOES rebuild on selection so it can hide on
// a day off — see [_calendarCard]; it is a cheap static 3-row widget.) The
// 42-cell grid is wrapped in a [RepaintBoundary] (HIGH-2) so its raster layer is
// cached and a strip-highlight repaint never re-rasters the chips; the cells
// themselves are memoised in [buildDayCells].
//
// The `dayOff` verdict is computed once by the caller and passed in, so the
// legend-hide condition and the day-off empty state share a single predicate.
//
// Pure render projection — identical markup/tokens to the pre-refactor
// `_dayPanel` + NO_SCHEDULE banner + `_timeGrid`; no visual/behavioural change.
// ─────────────────────────────────────────────────────────────────────────────
class _SelectedDayView extends StatelessWidget {
  const _SelectedDayView({
    required this.day,
    required this.dayOff,
    required this.editable,
    required this.isPast,
    required this.wholeWeekUnscheduled,
    required this.weekdayFull,
    required this.onAddHours,
    required this.onDayOverride,
  });

  final EffectiveDay day;

  /// A settled day off: no working intervals AND not the unset/uncovered
  /// NO_SCHEDULE state. Computed once by the caller ([_calendarCard]) so the
  /// legend-hide condition and the day-off empty state share one predicate.
  final bool dayOff;
  final bool editable;
  final bool isPast;
  final bool wholeWeekUnscheduled;
  final String weekdayFull;
  final VoidCallback onAddHours;
  final VoidCallback onDayOverride;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    // NO_SCHEDULE keeps its own banner; `dayOff` (a settled day off → friendly
    // empty state instead of the hour grid) is computed once by the caller and
    // passed in, so it can never diverge from the legend-hide predicate.
    final bool dayUnscheduled = day.source == EffectiveSource.noSchedule;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _dayPanel(l10n),
        const SizedBox(height: VelvetSpacing.md + 2),
        // NO_SCHEDULE → banner ONLY (no grid, no day-off state). The banner +
        // CTA already communicate the unset state; the all-grey grid below it is
        // redundant noise.
        if (dayUnscheduled)
          NoScheduleBanner(
            message: wholeWeekUnscheduled
                ? l10n.scheduleNoSchedulePeriod
                : l10n.scheduleNoScheduleDay,
            helper: l10n.scheduleNoScheduleHelper,
            ctaLabel: l10n.scheduleAddHoursCta,
            // OQ-2: read-only viewers get the banner WITHOUT the CTA.
            onAddHours: editable && !isPast ? onAddHours : null,
          )
        // Settled day off → friendly empty state instead of the hour grid.
        else if (dayOff)
          const _DayOffEmptyState()
        // Phase 15.9 — EXPLICIT_TIMES working day → render the discrete start
        // times as read-only chips (no continuous-availability grid; the day is
        // a discrete set of bookable starts, not a span). The derived window is
        // already shown as the secondary summary in [_dayPanel] above.
        else if (day.isExplicitTimes)
          _DiscreteTimesView(times: day.times)
        // Working INTERVAL day → the 42-cell hour grid (unchanged).
        else
          RepaintBoundary(child: _timeGrid(l10n)),
      ],
    );
  }

  // ── Selected-day panel ───────────────────────────────────────────────────--
  Widget _dayPanel(AppLocalizations l10n) {
    // Phase 15.9: an EXPLICIT_TIMES day has no intervals — it is a discrete set
    // of bookable starts, not a continuous span. Enumerate the hours instead of
    // deriving a misleading min–max window.
    final String summary = switch (day.source) {
      EffectiveSource.overrideDayOff => l10n.workingHoursClosedLabel,
      EffectiveSource.noSchedule => l10n.scheduleDaySummaryUnset,
      _ when day.isExplicitTimes => l10n.scheduleDiscreteTimesWindowSummary(
        day.times.map(formatTime).join(', '),
      ),
      _ =>
        day.intervals.isEmpty
            ? l10n.workingHoursClosedLabel
            : l10n.scheduleDaySummaryWorking(summariseSpan(day.intervals)),
    };
    // The pencil shows only for editable viewers on today/future days. Read-only
    // viewers (OQ-2) and past days (read-only history) get the muted hint.
    final bool showPencil = editable && !isPast;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: Text(
                '$weekdayFull, ${formatDay(day.date)}',
                style: VelvetText.bodyStrong(),
              ),
            ),
            const SizedBox(width: VelvetSpacing.sm),
            if (showPencil)
              Semantics(
                button: true,
                label: l10n.scheduleEditDaySemantic,
                child: GestureDetector(
                  key: const Key('schedule-day-pencil'),
                  onTap: onDayOverride,
                  child: const Icon(
                    Icons.edit_outlined,
                    size: 18,
                    color: BrandColors.accentDeep,
                  ),
                ),
              )
            else if (isPast)
              _readOnlyHint(l10n),
          ],
        ),
        const SizedBox(height: VelvetSpacing.xs),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            summary,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: VelvetText.label().copyWith(
              color: BrandColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _readOnlyHint(AppLocalizations l10n) {
    return Semantics(
      label: l10n.schedulePastDaySemantic,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: BrandColors.base,
          borderRadius: BorderRadius.circular(VelvetRadii.field),
          border: Border.all(color: BrandColors.faint.withValues(alpha: 0.6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.history_rounded,
              size: 15,
              color: BrandColors.muted,
            ),
            const SizedBox(width: VelvetSpacing.xs + 1),
            Text(l10n.scheduleViewOnly, style: VelvetText.label11),
          ],
        ),
      ),
    );
  }

  // ── Two-column time grid (read-only render projection) ─────────────────────
  Widget _timeGrid(AppLocalizations l10n) {
    final List<SlotCell> cells = buildDayCells(day);
    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < cells.length; i += 2) {
      final SlotCell left = cells[i];
      final SlotCell? right = i + 1 < cells.length ? cells[i + 1] : null;
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: VelvetSpacing.sm + 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              SizedBox(
                width: 46,
                child: Text(
                  '${left.time.hour.toString().padLeft(2, '0')}:00',
                  style: VelvetText.schedTimeAxisLabel,
                ),
              ),
              Expanded(
                child: SlotChip(
                  cell: left,
                  stateLabel: slotCellLabel(l10n, left),
                  onTap: null,
                ),
              ),
              const SizedBox(width: VelvetSpacing.sm + 2),
              Expanded(
                child: right == null
                    ? const SizedBox.shrink()
                    : SlotChip(
                        cell: right,
                        stateLabel: slotCellLabel(l10n, right),
                        onTap: null,
                      ),
              ),
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _DiscreteTimesView (Phase 15.9; restyled in the discrete-times-client track) —
// read-only render of an EXPLICIT_TIMES day's discrete start times. To stay
// visually consistent with the INTERVAL day's hour grid, each discrete start is
// rendered with the SAME [SlotChip] used by [_SelectedDayView._timeGrid]: a
// discrete start IS a bookable working start, so it maps to a synthetic
// [SlotState.available] cell and reads as a green "working" chip identical to
// the grid's. A section heading sits above a [Wrap] of chips so the row reflows
// at narrow widths / large text scale and never overflows (Phase 17.2 guard).
// Each chip is given a fixed slot width so it reads as a tile (matching the
// grid chips' spacious column fill) rather than shrink-wrapping its label. The
// whole block is collapsed into a single semantic announcement of the times so
// the chips are conveyed without relying on layout.
//
// Read-only: the [SlotChip]s pass `onTap: null` exactly like the interval grid
// render, so there is no tap / edit affordance.
//
// The derived min–max window is intentionally NOT repeated here — it is already
// the secondary summary in [_SelectedDayView._dayPanel] above (window label as
// secondary context, per the phase doc).
// ─────────────────────────────────────────────────────────────────────────────
class _DiscreteTimesView extends StatelessWidget {
  const _DiscreteTimesView({required this.times});

  /// The resolved discrete start times — sorted + de-duped by the mapper.
  /// Non-empty by construction (this widget renders only for an EXPLICIT_TIMES
  /// working day; an empty list is a day-off and routes to [_DayOffEmptyState]).
  final List<TimeOfDay> times;

  /// `HH:MM` zero-padded — matches the editor chip / window-label formatting and
  /// the per-chip render key.
  static String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';

  // Perf #56: hoist the per-build TextStyle so it is allocated once for the
  // whole class, not per chip / per day-cell rebuild.
  static final TextStyle _headingStyle = VelvetText.schedTimeAxisLabel;

  // Fixed slot width so each [SlotChip] reads as a tile (matching the interval
  // grid chips, which fill their `Expanded` column) instead of shrink-wrapping
  // its `HH:MM` label. Sized to fit the label with the same breathing room as a
  // grid column; the [Wrap] reflows these tiles at narrow widths / large text.
  static const double _chipWidth = 92;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String joined = times.map(_fmt).join(', ');
    return Padding(
      key: const Key('schedule-discrete-times'),
      padding: const EdgeInsets.symmetric(vertical: VelvetSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.scheduleDiscreteTimesTitle, style: _headingStyle),
          const SizedBox(height: VelvetSpacing.sm + 2),
          // MergeSemantics collapses the chips into one TalkBack announcement;
          // the inner Semantics carries the full time list as the label.
          MergeSemantics(
            child: Semantics(
              label: l10n.scheduleDiscreteTimesSemantic(joined),
              child: Wrap(
                spacing: VelvetSpacing.sm,
                runSpacing: VelvetSpacing.sm,
                children: <Widget>[
                  for (final TimeOfDay t in times)
                    SizedBox(
                      key: Key('schedule-discrete-chip-${_fmt(t)}'),
                      width: _chipWidth,
                      // Same chip as the interval grid: a working start →
                      // SlotState.available (green). `onTap: null` keeps it
                      // read-only, mirroring the grid render.
                      child: SlotChip(
                        cell: SlotCell(time: t, state: SlotState.available),
                        stateLabel: slotCellLabel(
                          l10n,
                          SlotCell(time: t, state: SlotState.available),
                        ),
                        onTap: null,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
