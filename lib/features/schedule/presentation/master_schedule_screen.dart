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
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
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

/// The calendar-first Master Schedule screen.
class MasterScheduleScreen extends ConsumerStatefulWidget {
  const MasterScheduleScreen({super.key});

  @override
  ConsumerState<MasterScheduleScreen> createState() =>
      _MasterScheduleScreenState();
}

class _MasterScheduleScreenState extends ConsumerState<MasterScheduleScreen> {
  static const _tag = 'feature.schedule.masterschedule';

  static const List<String> _weekdayShort = <String>[
    'Пн',
    'Вт',
    'Ср',
    'Чт',
    'Пт',
    'Сб',
    'Нд',
  ];

  /// "Today" anchored to the device date (date-only). Used for past-day gating.
  late final DateTime _today = _dateOnly(DateTime.now());

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

  // ── Range that backs the visible month (bounded family key) ────────────────
  ScheduleRange get _range => ScheduleRange.month(_visibleMonth);

  // ── Navigation ─────────────────────────────────────────────────────────────
  // Day selection mutates the notifier only (no setState): the static calendar
  // chrome stays put; just the strip highlight + selected-day view rebuild.
  void _selectDate(DateTime d) => _selected.value = d;

  void _stepMonth(int delta) {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta);
      _weekStart = _mondayOf(
        DateTime(_visibleMonth.year, _visibleMonth.month, 1),
      );
    });
  }

  /// The month that owns a Monday-anchored week — the month containing the 4th
  /// day (Thursday), which is always in the majority month.
  static DateTime _monthOfWeek(DateTime weekStart) {
    final DateTime mid = weekStart.add(const Duration(days: 3));
    return DateTime(mid.year, mid.month);
  }

  void _stepWeek(int delta) {
    setState(() {
      final next = _weekStart.add(Duration(days: delta * 7));
      _weekStart = _dateOnly(next);
      _visibleMonth = _monthOfWeek(_weekStart);
    });
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
  /// calendar watches) and invalidates the effective-schedule cache on a
  /// successful put/clear, so the week strip dots + the grid repaint with no
  /// manual refresh. Past days never reach here — the pencil is hidden on them.
  void _openDayOverride(EffectiveDay day) {
    if (kDebugMode) log('open per-date override', name: _tag, level: 800);
    final bool hasOverride =
        day.source == EffectiveSource.overrideCustom ||
        day.source == EffectiveSource.overrideDayOff;
    final bool dayOff = day.source == EffectiveSource.overrideDayOff;
    DayHoursSheet.show(
      context,
      date: day.date,
      weekdayFull: _weekdayFull(day.date),
      dateLabel: formatDay(day.date),
      range: _range,
      initialIntervals: day.intervals,
      hasExistingOverride: hasOverride,
      initialDayOff: dayOff,
      initialReason: day.reason,
      initialNote: null,
    );
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
  /// `AsyncLoading` with `value == null` (Riverpod's previous-data retention
  /// does NOT survive a family-key change). Caching the last good list lets us
  /// keep showing the previous month's content with a subtle inline indicator
  /// during the brief reload — the full-screen spinner is reserved for the
  /// genuine first load, when this is still null.
  List<EffectiveDay>? _lastDays;

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

    // Riverpod 3.x: `.value` is the nullable getter (`valueOrNull` was removed).
    // Loading-flash fix: cache the freshly-resolved list, then fall back to the
    // last good one while a month-step reload is in flight (new family key →
    // `value == null`). Caching a reference during build is safe (no setState).
    final List<EffectiveDay>? resolved = asyncDays.value;
    if (resolved != null) _lastDays = resolved;
    final List<EffectiveDay>? days = resolved ?? _lastDays;
    final List<WeeklySchedule>? weekly = asyncWeekly.value;
    // Both must be resolved before we can decide empty vs. full. With the cache
    // in play this only stays null on the genuine FIRST load.
    if (days == null || weekly == null) {
      return const Center(
        child: CircularProgressIndicator(color: BrandColors.accent),
      );
    }

    // A month-change reload: we have cached content to keep on screen, but the
    // newly-keyed range is still resolving. Drives the subtle inline indicator
    // (instead of a full-screen spinner) in [_content].
    final bool reloading = resolved == null && asyncDays.isLoading;

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
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        VelvetSpacing.md,
        VelvetSpacing.sm,
        VelvetSpacing.md,
        VelvetSpacing.xxl,
      ),
      children: <Widget>[
        _templateCard(l10n, editable, days),
        const SizedBox(height: VelvetSpacing.lg + 4),
        SectionHeader(title: l10n.scheduleCalendarSection),
        const SizedBox(height: VelvetSpacing.md),
        _calendarCard(l10n, editable, index),
      ],
    );

    // Loading-flash fix: on a month-change reload keep the (stale) content fully
    // visible and overlay a thin top progress line — no layout shift, dismissed
    // the instant the new month resolves. First load never reaches here (it goes
    // through the full-screen spinner gate above).
    return Stack(
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
  }

  // ── Weekly-template card ─────────────────────────────────────────────────--
  // Tappable to open the template editor (editable viewers only); a trailing
  // pencil signals the affordance. The seven pills reflect which ISO weekdays
  // are templated as working days, derived from the resolved month's data.
  Widget _templateCard(
    AppLocalizations l10n,
    bool editable,
    List<EffectiveDay> days,
  ) {
    final List<bool> template = _templatePattern(days);
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
          WeekdayPillRow(labels: _weekdayShort, active: template),
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

  /// Derives the seven ISO weekday working/closed booleans from the resolved
  /// month: a weekday is "active" if at least one date of that weekday in the
  /// visible month resolves to a working day (TEMPLATE/OVERRIDE_CUSTOM with
  /// intervals). Pure projection — no template fetch needed for the read shell.
  List<bool> _templatePattern(List<EffectiveDay> days) {
    // MEDIUM-1: derive from the already-watched [days] — no second
    // `ref.read(effectiveScheduleProvider)` and no extra month scan beyond the
    // single pass the projection inherently needs.
    final active = List<bool>.filled(7, false);
    for (final d in days) {
      if (d.intervals.isNotEmpty) active[d.date.weekday - 1] = true;
    }
    return active;
  }

  // ── Month nav + week strip + day panel + grid + legend (one card) ──────────
  // HIGH-1: the `_selected`-dependent sub-tree (selected-day panel + NO_SCHEDULE
  // banner + the 42-cell grid) is extracted into [_SelectedDayView], rebuilt
  // only when the selection (or `editable`) changes via a single
  // [ValueListenableBuilder] on [_selected]. The month navigator, week strip
  // and legend are siblings that do NOT re-run on a day tap.
  Widget _calendarCard(AppLocalizations l10n, bool editable, _DayIndex index) {
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
              final EffectiveDay day = index.lookup(selected);
              return _SelectedDayView(
                day: day,
                editable: editable,
                isPast: _isPast(day.date),
                wholeWeekUnscheduled: _wholeWeekUnscheduled(index),
                weekdayFull: _weekdayFull(day.date),
                onAddHours: _openTemplateEditor,
                onDayOverride: () => _openDayOverride(day),
              );
            },
          ),
          const SizedBox(height: VelvetSpacing.lg),
          _legendCard(l10n),
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
                        return ValueListenableBuilder<DateTime>(
                          valueListenable: _selected,
                          builder:
                              (BuildContext context, DateTime selected, _) =>
                                  WeekStripDay(
                                    weekdayLabel: _weekdayShort[i],
                                    day: d.day,
                                    selected: _sameDate(d, selected),
                                    inMonth: d.month == _visibleMonth.month,
                                    hasOverride: index.hasOverride(d),
                                    past: _isPast(d),
                                    plainSemanticLabel: l10n.scheduleStripDay(
                                      _weekdayShort[i],
                                      d.day,
                                    ),
                                    pastSemanticLabel: l10n
                                        .scheduleStripDayPast(
                                          _weekdayShort[i],
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
}

// ─────────────────────────────────────────────────────────────────────────────
// _SelectedDayView (HIGH-1 + HIGH-2) — the only sub-tree that depends on the
// selected date. Rebuilt by a single [ValueListenableBuilder] on the screen's
// `_selected` notifier, so a day tap never re-runs the month navigator, the
// weekly-template card, the week strip body, or the legend. The 42-cell grid is
// wrapped in a [RepaintBoundary] (HIGH-2) so its raster layer is cached and a
// strip-highlight repaint never re-rasters the chips; the cells themselves are
// memoised in [buildDayCells].
//
// Pure render projection — identical markup/tokens to the pre-refactor
// `_dayPanel` + NO_SCHEDULE banner + `_timeGrid`; no visual/behavioural change.
// ─────────────────────────────────────────────────────────────────────────────
class _SelectedDayView extends StatelessWidget {
  const _SelectedDayView({
    required this.day,
    required this.editable,
    required this.isPast,
    required this.wholeWeekUnscheduled,
    required this.weekdayFull,
    required this.onAddHours,
    required this.onDayOverride,
  });

  final EffectiveDay day;
  final bool editable;
  final bool isPast;
  final bool wholeWeekUnscheduled;
  final String weekdayFull;
  final VoidCallback onAddHours;
  final VoidCallback onDayOverride;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool dayUnscheduled = day.source == EffectiveSource.noSchedule;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _dayPanel(l10n),
        const SizedBox(height: VelvetSpacing.md + 2),
        if (dayUnscheduled) ...<Widget>[
          NoScheduleBanner(
            message: wholeWeekUnscheduled
                ? l10n.scheduleNoSchedulePeriod
                : l10n.scheduleNoScheduleDay,
            helper: l10n.scheduleNoScheduleHelper,
            ctaLabel: l10n.scheduleAddHoursCta,
            // OQ-2: read-only viewers get the banner WITHOUT the CTA.
            onAddHours: editable && !isPast ? onAddHours : null,
          ),
          const SizedBox(height: VelvetSpacing.md + 2),
        ],
        RepaintBoundary(child: _timeGrid(l10n)),
      ],
    );
  }

  // ── Selected-day panel ───────────────────────────────────────────────────--
  Widget _dayPanel(AppLocalizations l10n) {
    final String summary = switch (day.source) {
      EffectiveSource.overrideDayOff =>
        day.reason?.label ?? l10n.workingHoursClosedLabel,
      EffectiveSource.noSchedule => l10n.scheduleDaySummaryUnset,
      _ =>
        day.intervals.isEmpty
            ? l10n.workingHoursClosedLabel
            : l10n.scheduleDaySummaryWorking(summariseIntervals(day.intervals)),
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
            Text(
              l10n.scheduleViewOnly,
              style: VelvetText.label().copyWith(
                fontSize: 11,
                color: BrandColors.muted,
              ),
            ),
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
                  style: VelvetText.label().copyWith(
                    fontSize: 12,
                    color: BrandColors.textSecondary,
                  ),
                ),
              ),
              Expanded(
                child: SlotChip(
                  cell: left,
                  stateLabel: slotStateLabel(l10n, left.state),
                  onTap: null,
                ),
              ),
              const SizedBox(width: VelvetSpacing.sm + 2),
              Expanded(
                child: right == null
                    ? const SizedBox.shrink()
                    : SlotChip(
                        cell: right,
                        stateLabel: slotStateLabel(l10n, right.state),
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
