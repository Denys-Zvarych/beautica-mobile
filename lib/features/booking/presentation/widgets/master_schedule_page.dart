// Phase 14.16/14.17 — MasterSchedulePage: one master's inline date→time
// picker slide on the salon booking flow's step-3 "Час" screen.
//
// Ports `docs/signup-designs/SalonBookingTime/lib/widgets/master_schedule_page.dart`
// onto real data + providers: the SHARED [MasterStrip] identity header (the
// same card the independent-master flow's date/time screens render), the
// SHARED [MonthCalendar]/[CalendarWeekdayBar] for the DATE (day-gated via the
// real `workingDaysProvider`, exactly like `SlotDateScreen`, Phase 14.14),
// and the SHARED [SlotGroup]/[SlotChip] Ранок/День/Вечір clusters for the
// TIME (fetched via `salonMasterDaySlotsProvider`, keyed on this master's
// PRIMARY assigned service's own per-master ASSIGNMENT id — see
// `salon_booking_schedule_notifier.dart`'s file header for the full
// architecture note, and `SalonMasterSchedule.primaryServiceAssignmentId`'s
// doc comment for why this is an assignment id and not the salon catalog id).
// [MasterStrip]/[MonthCalendar]/[SlotChip] are all shared verbatim with the
// independent-master flow — the identity card was unified onto [MasterStrip]
// (the salon-only `SalonMasterStrip` fork is gone), so a change to that one
// widget now reaches every booking screen in both flows.
//
// Two inline phases on the one slide: pick a DATE → the slide swaps to the
// TIME chips for that date → picking a slot completes the master (the host
// `SalonTimeScreen` then auto-advances to the next unscheduled master via
// [onCompleted]). A compact inline «Змінити» button beside the "Вільний час"
// heading clears the date to re-open the calendar.
//
// Self-sufficient Riverpod integration (mirrors `SlotDateScreen`/
// `SlotTimeScreen`, NOT the preview's parent-owned local `State`): this
// widget reads/writes `salonBookingScheduleProvider` directly rather than
// funnelling every pick through a callback owned by `SalonTimeScreen` — only
// the "this master just became fully scheduled for the FIRST time" signal
// bubbles up (via [onCompleted]), since only the host knows the other
// slides' indices needed to compute the next unscheduled one.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';

import '../../application/salon_booking_schedule_notifier.dart';
import '../../application/working_days_notifier.dart';
import '../../domain/booking_slot.dart';
import '../../domain/salon_master_day_slots_query.dart';
import '../../domain/salon_master_schedule.dart';
import '../../domain/working_day.dart';
import '../../domain/working_days_query.dart';
import 'master_strip.dart';
import 'month_calendar.dart';
import 'slot_chip.dart';

class MasterSchedulePage extends ConsumerStatefulWidget {
  const MasterSchedulePage({
    super.key,
    required this.schedule,
    required this.avatarGradient,
    required this.onCompleted,
    required this.keepAlive,
  });

  final SalonMasterSchedule schedule;
  final List<Color> avatarGradient;

  /// Fires once this master transitions from unscheduled to fully scheduled
  /// (both date AND time set) — drives `SalonTimeScreen`'s slider
  /// auto-advance. Never fires again on a subsequent slot edit.
  final VoidCallback onCompleted;

  /// Whether this slide should retain its widget `State` — and therefore
  /// its `workingDaysProvider`/`salonMasterDaySlotsProvider` subscriptions
  /// — while scrolled off-screen.
  ///
  /// mobile-perf Finding B (MEDIUM): unconditionally keeping every visited
  /// master's slide alive for the whole `SalonTimeScreen` session grows
  /// retention linearly with masters visited. `SalonTimeScreen` passes
  /// `true` only for the active slide and its immediate neighbours
  /// (current ± 1) — bounded enough (given this codebase's ≤50-master
  /// accepted ceiling elsewhere) to keep the loading-flash-prevention
  /// benefit `AutomaticKeepAliveClientMixin` was added for on the common
  /// back/forward step, while letting far-away slides release their state
  /// once the client has moved well past them.
  final bool keepAlive;

  @override
  ConsumerState<MasterSchedulePage> createState() => _MasterSchedulePageState();
}

class _MasterSchedulePageState extends ConsumerState<MasterSchedulePage>
    with AutomaticKeepAliveClientMixin {
  /// Booking horizon — 3 months out, matching `SlotDateScreen`'s own
  /// `_horizonMonths`; no backend signal dictates a different cap.
  static const int _horizonMonths = 3;

  late final DateTime _today;
  late final DateTime _firstMonth;
  late final DateTime _lastMonth;
  late DateTime _visibleMonth;

  /// Loading-flash fix, mirroring `SlotDateScreen._lastWorkingDays` — see
  /// that file for the full rationale.
  List<WorkingDay>? _lastWorkingDays;

  @override
  void initState() {
    super.initState();
    final DateTime now = DateTime.now();
    _today = DateTime(now.year, now.month, now.day);
    _firstMonth = DateTime(_today.year, _today.month, 1);
    _lastMonth = DateTime(_today.year, _today.month + _horizonMonths, 1);
    _visibleMonth = _firstMonth;
  }

  @override
  bool get wantKeepAlive => widget.keepAlive;

  @override
  void didUpdateWidget(covariant MasterSchedulePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.keepAlive != widget.keepAlive) {
      // Required by `AutomaticKeepAliveClientMixin`'s contract: whenever
      // `wantKeepAlive`'s return value changes, the framework must be told
      // explicitly so it can add/remove this Element's keep-alive bucket
      // (see Finding B fix note on `keepAlive` above).
      updateKeepAlive();
    }
  }

  String get _masterId => widget.schedule.masterId;

  WorkingDaysQuery get _workingDaysQuery =>
      WorkingDaysQuery.month(masterId: _masterId, anyDayInMonth: _visibleMonth);

  static int _dayKey(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  bool Function(DateTime) _availabilityFrom(List<WorkingDay> days) {
    final Map<int, bool> workingByDay = <int, bool>{
      for (final WorkingDay w in days) _dayKey(w.date): w.working,
    };
    return (DateTime day) {
      if (day.isBefore(_today)) return false;
      return workingByDay[_dayKey(day)] ?? false;
    };
  }

  void _prevMonth() {
    if (!_visibleMonth.isAfter(_firstMonth)) return;
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month - 1, 1);
    });
  }

  void _nextMonth() {
    if (!_visibleMonth.isBefore(_lastMonth)) return;
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 1);
    });
  }

  void _selectDay(DateTime day) {
    ref.read(salonBookingScheduleProvider.notifier).selectDate(_masterId, day);
  }

  void _clearDate() {
    ref.read(salonBookingScheduleProvider.notifier).clearDate(_masterId);
  }

  void _selectSlot(BookingSlot slot) {
    final bool wasScheduled = ref
        .read(salonBookingScheduleProvider)
        .isScheduled(_masterId);
    ref.read(salonBookingScheduleProvider.notifier).selectSlot(_masterId, slot);
    if (wasScheduled) return; // editing an existing slot — no auto-advance.
    // Let the chip's press animation land, then signal completion — mirrors
    // the preview's `_selectSlot` delayed `_goTo`.
    Future<void>.delayed(const Duration(milliseconds: 360), () {
      if (mounted) widget.onCompleted();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context);
    final SalonScheduleEntry entry = ref.watch(
      salonBookingScheduleProvider.select(
        (SalonBookingScheduleState s) => s.entryFor(_masterId),
      ),
    );
    final bool datePhase = entry.date == null;

    // Vertical-only here — deliberately. The shared [MonthCalendar] (used by
    // `_datePhase` below) already self-pads horizontally by `VelvetSpacing.lg`
    // (see its own `build()`), matching `SlotDateScreen`'s single lg inset.
    // Adding a horizontal inset on this outer scroll view too would stack a
    // SECOND lg on top of the calendar's own — exactly the double-padding bug
    // this file previously had (48px per side instead of 24px). Every other
    // child below now carries its own explicit horizontal padding instead, so
    // the net inset stays a single `VelvetSpacing.lg` everywhere.
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: VelvetSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
            child: MasterStrip.fromSchedule(
              widget.schedule,
              showRole: true,
              showRating: true,
              avatarGradient: widget.avatarGradient,
              avatarBordered: true,
            ),
          ),
          const SizedBox(height: VelvetSpacing.lg),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (Widget child, Animation<double> a) =>
                FadeTransition(
                  opacity: a,
                  child: SizeTransition(
                    sizeFactor: a,
                    axisAlignment: -1,
                    child: child,
                  ),
                ),
            child: datePhase
                ? _datePhase(l10n)
                : _timePhase(l10n, entry.date!, entry.slot),
          ),
        ],
      ),
    );
  }

  Widget _datePhase(AppLocalizations l10n) {
    final AsyncValue<List<WorkingDay>> workingDaysAsync = ref.watch(
      workingDaysProvider(_workingDaysQuery),
    );

    Widget calendarBody;
    if (workingDaysAsync.hasError) {
      calendarBody = _WorkingDaysErrorBody(
        key: const ValueKey<String>('salon-schedule-error'),
        failure: workingDaysAsync.error!,
        onRetry: () => ref.invalidate(workingDaysProvider(_workingDaysQuery)),
      );
    } else {
      final List<WorkingDay>? resolvedDays = workingDaysAsync.value;
      if (resolvedDays != null) _lastWorkingDays = resolvedDays;
      final bool loading = workingDaysAsync.isLoading;
      final List<WorkingDay>? daysToRender =
          resolvedDays ?? (loading ? _lastWorkingDays : null);

      if (daysToRender == null) {
        calendarBody = const Padding(
          key: ValueKey<String>('salon-schedule-loading'),
          padding: EdgeInsets.symmetric(vertical: VelvetSpacing.xl),
          child: Center(
            child: CircularProgressIndicator(color: BrandColors.accent),
          ),
        );
      } else {
        final Widget calendar = MonthCalendar(
          key: const Key('booking-month-calendar'),
          visibleMonth: _visibleMonth,
          today: _today,
          selected: null,
          isAvailable: _availabilityFrom(daysToRender),
          onSelectDay: _selectDay,
          onPrevMonth: _visibleMonth.isAfter(_firstMonth) ? _prevMonth : null,
          onNextMonth: _visibleMonth.isBefore(_lastMonth) ? _nextMonth : null,
        );
        calendarBody = loading
            ? Stack(
                key: const ValueKey<String>('salon-schedule-calendar-stale'),
                children: <Widget>[
                  calendar,
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
              )
            : KeyedSubtree(
                key: const ValueKey<String>('salon-schedule-calendar'),
                child: calendar,
              );
      }
    }

    return Column(
      key: const ValueKey<String>('date'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
          child: Text(
            l10n.salonScheduleDateIntro,
            style: VelvetText.scheduleDateIntro,
          ),
        ),
        const SizedBox(height: VelvetSpacing.md),
        // `CalendarWeekdayBar` and `calendarBody` (which wraps the shared
        // `MonthCalendar`) are deliberately left UNWRAPPED here — both
        // already self-pad horizontally by the same `VelvetSpacing.lg`
        // (`CalendarWeekdayBar`'s self-pad and `MonthCalendar`'s own outer
        // inset match exactly as of the month_calendar.dart alignment fix),
        // exactly matching `SlotDateScreen`. Adding another horizontal
        // Padding around either is the double-padding bug this file is
        // fixed for — see the outer `SingleChildScrollView`'s comment in
        // `build()`.
        const CalendarWeekdayBar(),
        const SizedBox(height: VelvetSpacing.xs),
        calendarBody,
      ],
    );
  }

  Widget _timePhase(
    AppLocalizations l10n,
    DateTime date,
    BookingSlot? selectedSlot,
  ) {
    final AsyncValue<List<BookingSlot>> slotsAsync = ref.watch(
      salonMasterDaySlotsProvider(
        SalonMasterDaySlotsQuery(
          masterId: _masterId,
          // MUST be the master's own service-ASSIGNMENT id
          // (`MasterServiceResponse.id`), NOT `services.first.id` (the
          // salon-wide catalog id) — the backend's slots endpoint 404s
          // ("masterService not found") on the catalog id. See
          // `SalonMasterSchedule.primaryServiceAssignmentId`'s doc comment.
          serviceId: widget.schedule.primaryServiceAssignmentId,
          date: date,
        ),
      ),
    );
    // Wrapped in a single horizontal Padding — unlike `_datePhase`, nothing
    // in this phase's subtree (heading row, slot-chip groups,
    // empty/loading/error states) self-pads horizontally, so
    // one `VelvetSpacing.lg` inset here is enough and can't double up with
    // anything (there's no shared `MonthCalendar`/`CalendarWeekdayBar` on
    // this phase). The `ValueKey` moves to this `Padding` since it — not the
    // inner `Column` — is now the actual `child` `AnimatedSwitcher` compares.
    return Padding(
      key: const ValueKey<String>('time'),
      padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // The day-header chip that used to lead this phase (date label +
          // master name/role + a «Змінити» change-date action) was removed;
          // its only still-needed affordance — re-choosing the date — now
          // lives as this compact inline button beside the "Вільний час"
          // heading, so a client who already picked a date and sees slots can
          // still return to the calendar without relying on back navigation.
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  l10n.bookingFreeTimeHeading,
                  style: VelvetText.scheduleTimeHeading,
                ),
              ),
              const SizedBox(width: VelvetSpacing.sm),
              _ChangeDateButton(onChangeDate: _clearDate),
            ],
          ),
          const SizedBox(height: VelvetSpacing.md),
          slotsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: VelvetSpacing.lg),
              child: Center(
                child: SizedBox(
                  height: 28,
                  width: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: BrandColors.accent,
                  ),
                ),
              ),
            ),
            error: (Object e, StackTrace _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: VelvetSpacing.lg),
              child: Text(
                l10n.bookingDayUnavailableState,
                style: VelvetText.dayUnavailableLabel,
              ),
            ),
            data: (List<BookingSlot> slots) {
              if (slots.isEmpty) {
                return _NoSlotsEmptyState(onChangeDate: _clearDate);
              }
              final List<BookingSlot> morning = <BookingSlot>[];
              final List<BookingSlot> afternoon = <BookingSlot>[];
              final List<BookingSlot> evening = <BookingSlot>[];
              for (final BookingSlot s in slots) {
                final int hour = s.startAt.hour;
                if (hour < 12) {
                  morning.add(s);
                } else if (hour < 17) {
                  afternoon.add(s);
                } else {
                  evening.add(s);
                }
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (morning.isNotEmpty) ...<Widget>[
                    _slotGroup(l10n.bookingMorningLabel, morning, selectedSlot),
                    const SizedBox(height: VelvetSpacing.md),
                  ],
                  if (afternoon.isNotEmpty) ...<Widget>[
                    _slotGroup(
                      l10n.bookingAfternoonLabel,
                      afternoon,
                      selectedSlot,
                    ),
                    const SizedBox(height: VelvetSpacing.md),
                  ],
                  if (evening.isNotEmpty)
                    _slotGroup(l10n.bookingEveningLabel, evening, selectedSlot),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _slotGroup(
    String label,
    List<BookingSlot> group,
    BookingSlot? selectedSlot,
  ) {
    return SlotGroup(
      label: label,
      children: <Widget>[
        for (final BookingSlot s in group)
          SizedBox(
            width: 74,
            child: SlotChip(
              key: Key('salon-slot-chip-${s.startAt.toIso8601String()}'),
              time: formatSlotTime(s.startAt),
              available: s.available,
              selected: selectedSlot == s,
              onTap: () => _selectSlot(s),
            ),
          ),
      ],
    );
  }
}

class _WorkingDaysErrorBody extends StatelessWidget {
  const _WorkingDaysErrorBody({
    super.key,
    required this.failure,
    required this.onRetry,
  });

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
              key: const Key('salon-schedule-calendar-retry'),
              label: l10n.retryLabel,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}

/// A compact, on-palette "change date" text button shown inline beside the
/// slot-phase "Вільний час" heading. It is the ONLY date re-selection
/// affordance once a day is chosen and its slots are showing — the
/// `_NoSlotsEmptyState`'s own change-date button only appears on a zero-slot
/// day, and the removed `_DayHeaderChip` used to carry this for every other
/// case. Reuses the same edit-calendar glyph + copy as that empty state so
/// the "change date" gesture reads identically wherever it surfaces.
class _ChangeDateButton extends StatelessWidget {
  const _ChangeDateButton({required this.onChangeDate});

  final VoidCallback onChangeDate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: l10n.bookingChangeDateSemantics,
      child: GestureDetector(
        key: const Key('salon-schedule-change-date'),
        behavior: HitTestBehavior.opaque,
        onTap: onChangeDate,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: VelvetSpacing.xs,
            vertical: VelvetSpacing.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.edit_calendar_outlined,
                size: 15,
                color: BrandColors.accentDeep,
              ),
              const SizedBox(width: 4),
              Text(l10n.bookingChangeDateCta, style: VelvetText.changeDateCta),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoSlotsEmptyState extends StatelessWidget {
  const _NoSlotsEmptyState({required this.onChangeDate});

  final VoidCallback onChangeDate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      key: const Key('salon-schedule-no-slots-empty-state'),
      padding: const EdgeInsets.symmetric(vertical: VelvetSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          const Icon(
            Icons.event_busy_rounded,
            size: 32,
            color: BrandColors.faint,
          ),
          const SizedBox(height: VelvetSpacing.md),
          Text(
            l10n.bookingNoSlotsTitle,
            textAlign: TextAlign.center,
            style: VelvetText.bodyStrong(),
          ),
          const SizedBox(height: VelvetSpacing.xs),
          Text(
            l10n.bookingNoSlotsMessage,
            textAlign: TextAlign.center,
            style: VelvetText.body(),
          ),
          const SizedBox(height: VelvetSpacing.lg),
          NeumorphicButton(
            key: const Key('salon-schedule-no-slots-change-date'),
            label: l10n.bookingChangeDateCta,
            icon: Icons.edit_calendar_outlined,
            onPressed: onChangeDate,
          ),
        ],
      ),
    );
  }
}
