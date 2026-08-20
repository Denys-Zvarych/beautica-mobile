// MO-4 (single-master single-visit rework) — MasterSchedulePage: the chosen
// master's inline date→time picker body on the salon booking flow's step-3
// "Час" screen.
//
// The salon flow now books ONE visit against ONE master, so this is a single
// picker (no `PageView`, no per-master keep-alive) reading the single-state
// `salonBookingScheduleProvider`. It ports the same shared widgets the
// independent-master flow uses: the [MasterStrip] identity header, the
// [MonthCalendar]/[CalendarWeekdayBar] for the DATE (day-gated via
// `workingDaysProvider` in availability-aware mode — the SUMMED duration of
// ALL selected services must fit), and the [SlotGroup]/[SlotChip]
// Ранок/День/Вечір clusters for the TIME (fetched via
// `salonMasterDaySlotsProvider`, keyed on ALL the visit's ordered per-master
// assignment ids as a summed block).
//
// Two inline phases on the one screen: pick a DATE → swap to the TIME chips for
// that date → picking a slot selects the visit time. Returning from the TIME
// phase to the calendar is handled three redundant ways — all calling the SAME
// `salonBookingScheduleProvider.clearDate()` — the `SalonTimeScreen` top-bar
// arrow, the Android system back gesture (both via that screen's `PopScope`),
// and a left-edge swipe-back affordance local to the TIME phase (restoring the
// swipe-back feel the route-level `PopScope(canPop: false)` otherwise disarms).

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';

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
    this.showMasterStrip = true,
    this.showDateIntro = true,
    this.stagedDate,
    this.onDateStaged,
  });

  /// The chosen master's fully-resolved visit (identity + ordered services +
  /// per-master assignment ids).
  final SalonMasterSchedule schedule;
  final List<Color> avatarGradient;

  /// Whether to render the [MasterStrip] identity header above the picker.
  ///
  /// Defaults to `true` — `salon_time_screen.dart`, where the booker picked
  /// this master out of several and needs to see WHO they are booking with,
  /// renders exactly as before. The master «Новий запис» wizard passes `false`:
  /// there the master IS the logged-in user creating a booking on their own
  /// calendar, so the strip names the reader back to themselves. That is the
  /// same reasoning the wizard's confirm step already uses to omit its own
  /// master card (see `booking_wizard_steps.dart`'s [ConfirmStep] and
  /// `master_create_booking_screen.dart`'s file-header deviation #4).
  final bool showMasterStrip;

  /// Whether to render the `salonScheduleDateIntro` line above the calendar
  /// («Оберіть зручну дату для цього майстра…»).
  ///
  /// Defaults to `true` (salon flow unchanged). The wizard passes `false` — its
  /// own step header already says «Дата та час», so the intro only repeats it,
  /// and its "для цього майстра" phrasing is self-referential there for the
  /// same reason [showMasterStrip] is.
  final bool showDateIntro;

  /// Wizard opt-out of the calendar's tap-to-ADVANCE behaviour.
  ///
  /// By default (both `null`) a day tap writes straight through to
  /// `salonBookingScheduleProvider.selectDate(...)`, which flips this page into
  /// its time sub-phase in the same frame — `salon_time_screen.dart`'s shipped
  /// behaviour, unchanged. With [stagedDate] `null` the calendar is built
  /// DIRECTLY, with no [ValueListenableBuilder] wrapper at all, so the salon
  /// flow's element tree is byte-identical to before this parameter existed.
  ///
  /// When [onDateStaged] is non-null the tap does NOT touch the provider: it is
  /// reported to the owner, which holds the pending day and paints it back via
  /// [stagedDate] (rendered as the calendar's `selected` day). Committing —
  /// and therefore the sub-phase flip — is then the owner's call, made from its
  /// own pinned «Далі» CTA.
  ///
  /// A [ValueListenable], NOT a plain `DateTime?` (mobile-perf MEDIUM,
  /// 2026-08-20): a staged day passed as a plain value forces the OWNER to
  /// `setState`, which reconstructed the whole wizard — 683 of the tree's 921
  /// elements per day tap, 146 of them chrome ABOVE this page (`BookingTopBar`,
  /// `StepIndicator` + its `AnimatedContainer`s, the step `AnimatedSwitcher`,
  /// the `Scaffold`, the footer) that cannot depend on the staged day. Handed
  /// down as a listenable, the tap rebuilds only [MonthCalendar] (which must
  /// repaint its selection) and the owner's own footer.
  final ValueListenable<DateTime?>? stagedDate;
  final ValueChanged<DateTime>? onDateStaged;

  @override
  ConsumerState<MasterSchedulePage> createState() => _MasterSchedulePageState();
}

class _MasterSchedulePageState extends ConsumerState<MasterSchedulePage> {
  /// Booking horizon — 3 months out, matching `SlotDateScreen`'s own
  /// `_horizonMonths`.
  static const int _horizonMonths = 3;

  /// "Today", Kyiv-anchored — RE-DERIVED on every read, never captured once.
  /// Mirrors `SlotDateScreen._today` (`slot_picker_screen.dart`) exactly; see
  /// that getter's doc for the Kyiv-anchoring rationale and for why capturing
  /// it in `initState` froze the calendar's past-day gate across midnight.
  ///
  /// Read exactly ONCE per build and threaded down as a parameter — see
  /// `SlotDateScreen._today` for why that is a correctness requirement (a
  /// build straddling Kyiv midnight must not mix day N and day N+1).
  DateTime get _today => kyivToday(ref.read(clockProvider));

  DateTime _firstMonth(DateTime today) => DateTime(today.year, today.month, 1);

  DateTime _lastMonth(DateTime today) =>
      DateTime(today.year, today.month + _horizonMonths, 1);

  /// Backing store for [_visibleMonth] — the month the user has paged to.
  late DateTime _pagedMonth;

  /// The month grid to render: [_pagedMonth] clamped UP to the live
  /// [_firstMonth] floor — mirrors `SlotDateScreen`'s own clamp; see it for
  /// why the floor can move out from under the store, and for why only the
  /// LOWER bound is clamped ([_lastMonth] only ever moves forward, and
  /// [_nextMonth] already refuses to page past it).
  DateTime _visibleMonth(DateTime today) {
    final DateTime first = _firstMonth(today);
    return _pagedMonth.isBefore(first) ? first : _pagedMonth;
  }

  /// Loading-flash fix, mirroring `SlotDateScreen._lastWorkingDays`.
  List<WorkingDay>? _lastWorkingDays;

  /// Memoized morning/afternoon/evening split, keyed on the slot-list identity.
  /// A slot tap rebuilds the time phase but reuses the same `slots` list, so the
  /// bucketing (and its O(n) tz conversion) runs once per fetched list rather
  /// than once per tap.
  List<BookingSlot>? _lastBucketedSlots;
  (List<BookingSlot>, List<BookingSlot>, List<BookingSlot>)? _cachedBuckets;

  /// Splits [slots] into morning / afternoon / evening on the KYIV wall-clock
  /// hour — mirroring `SlotPickerScreen`'s `_SlotsSectionState._bucketsFor`.
  ///
  /// `BookingSlot.startAt` is a canonical UTC instant (built_value deserializes
  /// the ISO-8601 wire value with `.toUtc()`), so `startAt.hour` is the UTC
  /// hour — uniformly 2-3h behind the Kyiv hour the chip beside the heading
  /// actually renders (`formatSlotTime` → `toBeauticaTime`). Bucketing on it
  /// filed a 13:00-15:00 Kyiv working day entirely under «Ранок». This is not
  /// a device-zone leak — it was wrong on every device, Kyiv ones included —
  /// so the fix is the market zone, not the host's: `toBeauticaTime(...).hour`,
  /// the same derivation the visible label goes through.
  ///
  /// The chip `Key`s deliberately stay on the raw UTC ISO string (see
  /// [_slotGroup]) — they are identity, not display.
  (List<BookingSlot>, List<BookingSlot>, List<BookingSlot>) _bucketSlots(
    List<BookingSlot> slots,
  ) {
    final (List<BookingSlot>, List<BookingSlot>, List<BookingSlot>)? cached =
        _cachedBuckets;
    if (cached != null && identical(_lastBucketedSlots, slots)) {
      return cached;
    }
    final List<BookingSlot> morning = <BookingSlot>[];
    final List<BookingSlot> afternoon = <BookingSlot>[];
    final List<BookingSlot> evening = <BookingSlot>[];
    for (final BookingSlot s in slots) {
      final int hour = toBeauticaTime(s.startAt).hour;
      if (hour < 12) {
        morning.add(s);
      } else if (hour < 17) {
        afternoon.add(s);
      } else {
        evening.add(s);
      }
    }
    final (List<BookingSlot>, List<BookingSlot>, List<BookingSlot>) buckets = (
      morning,
      afternoon,
      evening,
    );
    _lastBucketedSlots = slots;
    _cachedBuckets = buckets;
    return buckets;
  }

  @override
  void initState() {
    super.initState();
    _pagedMonth = _firstMonth(_today);
  }

  String get _masterId => widget.schedule.masterId;

  /// The visit's ordered per-master assignment ids — both the availability-aware
  /// working-days gate and the slot fetch key off this exact ordered list, so
  /// the calendar day-gate agrees with the time grid (summed-block availability).
  List<String> get _serviceIds => widget.schedule.orderedMasterServiceIds;

  WorkingDaysQuery _workingDaysQuery(DateTime visibleMonth) =>
      WorkingDaysQuery.month(
        masterId: _masterId,
        anyDayInMonth: visibleMonth,
        serviceIds: _serviceIds,
      );

  static int _dayKey(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  /// [today] is the build's single Kyiv-day read, passed in rather than
  /// re-derived — the returned closure runs for all ~35-42 day cells of the
  /// grid, and it must agree with the `today` handed to [MonthCalendar] in the
  /// same frame (see [_today]).
  bool Function(DateTime) _availabilityFrom(
    List<WorkingDay> days,
    DateTime today,
  ) {
    final Map<int, bool> workingByDay = <int, bool>{
      for (final WorkingDay w in days) _dayKey(w.date): w.working,
    };
    return (DateTime day) {
      if (day.isBefore(today)) return false;
      return workingByDay[_dayKey(day)] ?? false;
    };
  }

  void _prevMonth() {
    final DateTime today = _today;
    final DateTime visible = _visibleMonth(today);
    if (!visible.isAfter(_firstMonth(today))) return;
    setState(() {
      _pagedMonth = DateTime(visible.year, visible.month - 1, 1);
    });
  }

  void _nextMonth() {
    final DateTime today = _today;
    final DateTime visible = _visibleMonth(today);
    if (!visible.isBefore(_lastMonth(today))) return;
    setState(() {
      _pagedMonth = DateTime(visible.year, visible.month + 1, 1);
    });
  }

  void _selectDay(DateTime day) {
    final ValueChanged<DateTime>? stage = widget.onDateStaged;
    if (stage != null) {
      // Staging mode — see [MasterSchedulePage.onDateStaged]. Deliberately does
      // NOT touch `salonBookingScheduleProvider`: writing `date` there is what
      // flips this page into its time sub-phase, and in staging mode that flip
      // belongs to the owner's «Далі» CTA, not to the tap.
      stage(day);
      return;
    }
    ref.read(salonBookingScheduleProvider.notifier).selectDate(day);
  }

  void _clearDate() {
    ref.read(salonBookingScheduleProvider.notifier).clearDate();
  }

  void _selectSlot(BookingSlot slot) {
    ref.read(salonBookingScheduleProvider.notifier).selectSlot(slot);
  }

  // ---------------------------------------------------------------------
  // Left-edge swipe-back on the TIME phase — restores the affordance
  // `PopScope(canPop: !inTimePhase)` in `salon_time_screen.dart` disarms.
  // ---------------------------------------------------------------------

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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final SalonBookingScheduleState schedule = ref.watch(
      salonBookingScheduleProvider,
    );
    final bool datePhase = schedule.date == null;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: VelvetSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (widget.showMasterStrip) ...<Widget>[
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
            // Spacing belongs to the strip, not to the picker below it —
            // dropping both together is what keeps the wizard from opening on
            // an orphan gap.
            const SizedBox(height: VelvetSpacing.lg),
          ],
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
                : _timePhase(l10n, schedule.date!, schedule.slot),
          ),
        ],
      ),
    );
  }

  Widget _datePhase(AppLocalizations l10n) {
    // The build's ONE Kyiv-day read — everything date-derived below hangs off
    // this single value so the frame is internally consistent (see [_today]).
    final DateTime today = _today;
    final DateTime visibleMonth = _visibleMonth(today);
    final AsyncValue<List<WorkingDay>> workingDaysAsync = ref.watch(
      workingDaysProvider(_workingDaysQuery(visibleMonth)),
    );

    Widget calendarBody;
    if (workingDaysAsync.hasError) {
      calendarBody = _WorkingDaysErrorBody(
        key: const ValueKey<String>('salon-schedule-error'),
        failure: workingDaysAsync.error!,
        onRetry: () => ref.invalidate(
          workingDaysProvider(_workingDaysQuery(visibleMonth)),
        ),
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
        // Hoisted out of the builder below: it materialises a ~31-42 entry
        // lookup map, and re-running it on every staged-day change would
        // rebuild that map for a value it does not depend on.
        final bool Function(DateTime) isAvailable = _availabilityFrom(
          daysToRender,
          today,
        );
        MonthCalendar buildCalendar(DateTime? selected) => MonthCalendar(
          key: const Key('booking-month-calendar'),
          visibleMonth: visibleMonth,
          today: today,
          // `null` in the salon flow (a tap advances instantly, so there is
          // never a selected-but-uncommitted day to paint) — the staged day in
          // the wizard. See [MasterSchedulePage.stagedDate].
          selected: selected,
          isAvailable: isAvailable,
          onSelectDay: _selectDay,
          onPrevMonth: visibleMonth.isAfter(_firstMonth(today))
              ? _prevMonth
              : null,
          onNextMonth: visibleMonth.isBefore(_lastMonth(today))
              ? _nextMonth
              : null,
        );

        final ValueListenable<DateTime?>? staged = widget.stagedDate;
        // The salon flow takes the FIRST branch — no wrapper element, so its
        // tree is unchanged. The wizard's staged day rebuilds the calendar and
        // NOTHING above it (see [MasterSchedulePage.stagedDate]).
        final Widget calendar = staged == null
            ? buildCalendar(null)
            : ValueListenableBuilder<DateTime?>(
                valueListenable: staged,
                builder: (BuildContext context, DateTime? day, Widget? child) =>
                    buildCalendar(day),
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
        if (widget.showDateIntro) ...<Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
            child: Text(
              l10n.salonScheduleDateIntro,
              style: VelvetText.scheduleDateIntro,
            ),
          ),
          // Paired with the line above — see the [MasterStrip] block in
          // `build` for why the spacer goes with the widget it separates.
          const SizedBox(height: VelvetSpacing.md),
        ],
        // `CalendarWeekdayBar` renders no horizontal padding of its own
        // (mobile-backlog D4/D5 — see `calendar_grid.dart`'s file header):
        // every caller wraps it in whatever inset its own sibling grid uses.
        // `MonthCalendar` self-pads by this same `VelvetSpacing.lg`, so
        // matching it here is what keeps the bar's captions above the day
        // columns they describe.
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
          child: CalendarWeekdayBar(),
        ),
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
          serviceIds: _serviceIds,
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
              final (
                List<BookingSlot> morning,
                List<BookingSlot> afternoon,
                List<BookingSlot> evening,
              ) = _bucketSlots(
                slots,
              );
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
              key: const Key('salon-schedule-time-edge-back-swipe'),
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
