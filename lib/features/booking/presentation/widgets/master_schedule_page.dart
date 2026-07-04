// Phase 14.16/14.17 — MasterSchedulePage: one master's inline date→time
// picker slide on the salon booking flow's step-3 "Час" screen.
//
// Ports `docs/signup-designs/SalonBookingTime/lib/widgets/master_schedule_page.dart`
// onto real data + providers: the carried [SalonMasterStrip] header, the
// SHARED [MonthCalendar]/[CalendarWeekdayBar] for the DATE (day-gated via the
// real `workingDaysProvider`, exactly like `SlotDateScreen`, Phase 14.14),
// and the SHARED [SlotGroup]/[SlotChip] Ранок/День/Вечір clusters for the
// TIME (fetched via `salonMasterDaySlotsProvider`, keyed on this master's
// PRIMARY assigned service's own per-master ASSIGNMENT id — see
// `salon_booking_schedule_notifier.dart`'s file header for the full
// architecture note, and `SalonMasterSchedule.primaryServiceAssignmentId`'s
// doc comment for why this is an assignment id and not the salon catalog id).
// [MonthCalendar]/[SlotChip] are the ONLY widgets shared verbatim with the
// independent-master flow — see the phase docs' "Architecture decision"
// section.
//
// Two inline phases on the one slide: pick a DATE → the slide swaps to the
// TIME chips for that date → picking a slot completes the master (the host
// `SalonTimeScreen` then auto-advances to the next unscheduled master via
// [onCompleted]). The day-header chip's «Змінити» clears the date.
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
import 'master_strip.dart' show masterRoleLabel;
import 'month_calendar.dart';
import 'salon_master_strip.dart';
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

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        VelvetSpacing.lg,
        VelvetSpacing.md,
        VelvetSpacing.lg,
        VelvetSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SalonMasterStrip(
            schedule: widget.schedule,
            avatarGradient: widget.avatarGradient,
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
        Text(l10n.salonScheduleDateIntro, style: VelvetText.scheduleDateIntro),
        const SizedBox(height: VelvetSpacing.md),
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
    final String masterName =
        '${widget.schedule.firstName} ${widget.schedule.lastName}'.trim();
    final String masterRole = masterRoleLabel(widget.schedule.type, l10n);
    final String? windowLabel = selectedSlot == null
        ? null
        : formatBookingWindow(
            selectedSlot.startAt,
            selectedSlot.startAt.add(
              Duration(minutes: widget.schedule.summedDurationMinutes),
            ),
          );

    return Column(
      key: const ValueKey<String>('time'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _DayHeaderChip(
          label: formatBookingDayHeader(date),
          masterName: masterName,
          masterRole: masterRole,
          onChange: _clearDate,
        ),
        const SizedBox(height: VelvetSpacing.lg),
        Text(
          l10n.bookingFreeTimeHeading,
          style: VelvetText.scheduleTimeHeading,
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
        const SizedBox(height: VelvetSpacing.lg),
        _WindowLine(label: windowLabel),
      ],
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

class _DayHeaderChip extends StatelessWidget {
  const _DayHeaderChip({
    required this.label,
    required this.masterName,
    required this.masterRole,
    required this.onChange,
  });

  final String label;
  final String masterName;
  final String masterRole;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      label: l10n.bookingDayHeaderSemantics(label, masterName, masterRole),
      child: NeumorphicCard(
        color: const Color(0xFFEDE4D5),
        padding: const EdgeInsets.symmetric(
          horizontal: VelvetSpacing.md,
          vertical: VelvetSpacing.sm + 2,
        ),
        child: Row(
          children: <Widget>[
            Container(
              height: 36,
              width: 36,
              decoration: BoxDecoration(
                color: BrandColors.base,
                borderRadius: BorderRadius.circular(VelvetRadii.field),
                boxShadow: VelvetShadows.extrudedSmall,
              ),
              child: const Icon(
                Icons.event_rounded,
                size: 18,
                color: BrandColors.accent,
              ),
            ),
            const SizedBox(width: VelvetSpacing.sm + 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    label,
                    style: VelvetText.dayHeaderTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '$masterName · $masterRole',
                    style: VelvetText.dayHeaderSubtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: VelvetSpacing.sm),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onChange,
              child: Semantics(
                button: true,
                label: l10n.bookingChangeDateSemantics,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: VelvetSpacing.sm,
                    vertical: 4,
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
                      Text(
                        l10n.bookingChangeDateCta,
                        style: VelvetText.changeDateCta,
                      ),
                    ],
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

/// The per-master window line — a recessed camel-wash well with the booked
/// window once a slot is chosen, or a muted prompt.
class _WindowLine extends StatelessWidget {
  const _WindowLine({required this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bool chosen = label != null;
    return NeumorphicInset(
      radius: VelvetRadii.field,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: VelvetSpacing.md,
          vertical: VelvetSpacing.sm + 4,
        ),
        child: Row(
          children: <Widget>[
            Icon(
              chosen ? Icons.event_available_rounded : Icons.schedule_rounded,
              size: 18,
              color: chosen ? BrandColors.accentDeep : BrandColors.muted,
            ),
            const SizedBox(width: VelvetSpacing.sm),
            Text(
              chosen
                  ? l10n.bookingChosenWindowLabel
                  : l10n.salonScheduleWindowPrompt,
              style: VelvetText.windowLinePrompt,
            ),
            if (chosen) ...<Widget>[
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: VelvetText.windowLineAccent,
                ),
              ),
            ] else
              const Spacer(),
          ],
        ),
      ),
    );
  }
}
