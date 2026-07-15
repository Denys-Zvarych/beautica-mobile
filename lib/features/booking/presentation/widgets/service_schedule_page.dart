// ServiceSchedulePage: one selected service's inline date→time picker slide on
// the independent-master booking flow's per-service time screen
// (`BookingTimeScreen`).
//
// The independent analogue of `master_schedule_page.dart` (the salon flow's
// per-master slide), keyed by SERVICE instead of MASTER: the SHARED
// [MasterStrip] identity header (the SAME master on every slide), the SHARED
// [MonthCalendar]/[CalendarWeekdayBar] for the DATE (day-gated via the real
// `workingDaysProvider`, availability-aware on THIS service's id exactly like
// `SlotDateScreen`), and the SHARED [SlotGroup]/[SlotChip] Ранок/День/Вечір
// clusters for the TIME (fetched via `independentServiceDaySlotsProvider`,
// keyed on this service's own id — no assignment-id indirection).
//
// Two inline phases on the one slide: pick a DATE → the slide swaps to the
// TIME chips for that date → picking a slot completes the service (the host
// `BookingTimeScreen` then auto-advances to the next unscheduled service via
// [onCompleted]). Returning from the TIME phase to the calendar is handled
// three redundant ways — all of which call the SAME `_clearDate()` — the
// `BookingTimeScreen` top-bar arrow, the Android system back gesture (both via
// that screen's `PopScope`), and a left-edge swipe-back affordance local to
// this slide's TIME phase.
//
// Self-sufficient Riverpod integration (mirrors `master_schedule_page.dart`):
// this widget reads/writes `independentBookingScheduleProvider` directly; only
// the "this service just became fully scheduled for the FIRST time" signal
// bubbles up (via [onCompleted]), since only the host knows the other slides'
// indices needed to compute the next unscheduled one.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';

import '../../application/independent_booking_schedule_notifier.dart';
import '../../application/working_days_notifier.dart';
import '../../domain/booking_slot.dart';
import '../../domain/independent_service_day_slots_query.dart';
import '../../domain/working_day.dart';
import '../../domain/working_days_query.dart';
import 'master_strip.dart';
import 'month_calendar.dart';
import 'slot_chip.dart';

class ServiceSchedulePage extends ConsumerStatefulWidget {
  const ServiceSchedulePage({
    super.key,
    required this.master,
    required this.service,
    required this.onCompleted,
    required this.keepAlive,
  });

  final Master master;
  final MasterService service;

  /// Fires once this service transitions from unscheduled to fully scheduled
  /// (both date AND time set) — drives `BookingTimeScreen`'s slider
  /// auto-advance. Never fires again on a subsequent slot edit.
  final VoidCallback onCompleted;

  /// Whether this slide should retain its widget `State` (and its
  /// `workingDaysProvider`/`independentServiceDaySlotsProvider` subscriptions)
  /// while scrolled off-screen — bounded to the active slide ±1 by the host.
  final bool keepAlive;

  @override
  ConsumerState<ServiceSchedulePage> createState() =>
      _ServiceSchedulePageState();
}

class _ServiceSchedulePageState extends ConsumerState<ServiceSchedulePage>
    with AutomaticKeepAliveClientMixin {
  /// Booking horizon — 3 months out, matching `SlotDateScreen`'s own
  /// `_horizonMonths`.
  static const int _horizonMonths = 3;

  late final DateTime _today;
  late final DateTime _firstMonth;
  late final DateTime _lastMonth;
  late DateTime _visibleMonth;

  /// Loading-flash fix, mirroring `SlotDateScreen._lastWorkingDays`.
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
  void didUpdateWidget(covariant ServiceSchedulePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.keepAlive != widget.keepAlive) {
      updateKeepAlive();
    }
  }

  String get _serviceId => widget.service.id;
  String get _masterId => widget.master.id;

  /// Availability-aware calendar gating — passes THIS service's id so a day's
  /// `working` flag means "this service's full duration fits a free range",
  /// the SAME computation `getMasterSlots` runs (mirrors `SlotDateScreen`).
  WorkingDaysQuery get _workingDaysQuery => WorkingDaysQuery.month(
    masterId: _masterId,
    anyDayInMonth: _visibleMonth,
    serviceId: _serviceId,
  );

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
    ref
        .read(independentBookingScheduleProvider.notifier)
        .selectDate(_serviceId, day);
  }

  void _clearDate() {
    ref.read(independentBookingScheduleProvider.notifier).clearDate(_serviceId);
  }

  // Left-edge swipe-back on the TIME phase — mirrors `master_schedule_page.dart`.
  static const double _kEdgeSwipeWidth = 20;
  static const double _kEdgeSwipeDistanceThreshold = 48;
  static const double _kEdgeSwipeVelocityThreshold = 400;

  double _edgeSwipeDx = 0;

  void _onEdgeSwipeStart(DragStartDetails details) => _edgeSwipeDx = 0;

  void _onEdgeSwipeUpdate(DragUpdateDetails details) =>
      _edgeSwipeDx += details.delta.dx;

  void _onEdgeSwipeEnd(DragEndDetails details) {
    final double dx = _edgeSwipeDx;
    final double velocity = details.primaryVelocity ?? 0;
    _edgeSwipeDx = 0;
    if (dx >= _kEdgeSwipeDistanceThreshold ||
        velocity >= _kEdgeSwipeVelocityThreshold) {
      _clearDate();
    }
  }

  void _selectSlot(BookingSlot slot) {
    final bool wasScheduled = ref
        .read(independentBookingScheduleProvider)
        .isScheduled(_serviceId);
    ref
        .read(independentBookingScheduleProvider.notifier)
        .selectSlot(_serviceId, slot);
    if (wasScheduled) return; // editing an existing slot — no auto-advance.
    Future<void>.delayed(const Duration(milliseconds: 360), () {
      if (mounted) widget.onCompleted();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context);
    final IndependentScheduleEntry entry = ref.watch(
      independentBookingScheduleProvider.select(
        (IndependentBookingScheduleState s) => s.entryFor(_serviceId),
      ),
    );
    final bool datePhase = entry.date == null;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: VelvetSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
            child: MasterStrip.fromMaster(
              widget.master,
              showRole: true,
              showRating: true,
            ),
          ),
          const SizedBox(height: VelvetSpacing.md),
          // Which service THIS slide is scheduling (the master card above is
          // identical on every slide — this names the differentiator). The
          // service name is domain data, not translated UI copy.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
            child: Text(widget.service.name, style: VelvetText.subheading16),
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
        key: const ValueKey<String>('service-schedule-error'),
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
          key: ValueKey<String>('service-schedule-loading'),
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
                key: const ValueKey<String>('service-schedule-calendar-stale'),
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
                key: const ValueKey<String>('service-schedule-calendar'),
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
            l10n.bookingServiceScheduleDateIntro,
            style: VelvetText.scheduleDateIntro,
          ),
        ),
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
      independentServiceDaySlotsProvider(
        IndependentServiceDaySlotsQuery(
          masterId: _masterId,
          serviceId: _serviceId,
          date: date,
        ),
      ),
    );
    final Widget content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
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

    return Semantics(
      key: const ValueKey<String>('time'),
      container: true,
      hint: l10n.bookingChangeDateCta,
      onDismiss: _clearDate,
      child: Stack(
        children: <Widget>[
          content,
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: _kEdgeSwipeWidth,
            child: GestureDetector(
              key: const Key('service-schedule-time-edge-back-swipe'),
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: _onEdgeSwipeStart,
              onHorizontalDragUpdate: _onEdgeSwipeUpdate,
              onHorizontalDragEnd: _onEdgeSwipeEnd,
            ),
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
              key: Key('independent-slot-chip-${s.startAt.toIso8601String()}'),
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
              key: const Key('service-schedule-calendar-retry'),
              label: l10n.retryLabel,
              onPressed: onRetry,
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
      key: const Key('service-schedule-no-slots-empty-state'),
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
            key: const Key('service-schedule-no-slots-change-date'),
            label: l10n.bookingChangeDateCta,
            icon: Icons.edit_calendar_outlined,
            onPressed: onChangeDate,
          ),
        ],
      ),
    );
  }
}
