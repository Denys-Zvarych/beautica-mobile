// Phase 14.1 — SlotPickerScreen: booking flow Step 2 (calendar + time grid).
//
// DESIGN SOURCE: `docs/signup-designs/BookingSlotPicker/` (approved
// 2026-06-30) — TWO sequential screens sharing the SAME
// `slotPickerProvider` state ([SlotDateScreen] "Оберіть дату" then
// [SlotTimeScreen] "Оберіть час"), NOT the phase doc's original pre-approval
// single combined-screen sketch. Both are routed via `go_router`
// (`RouteNames.bookingSlots` → `RouteNames.bookingSlotsTime`), never
// `Navigator.push` — see `app_router.dart` for the nested-route wiring.
//
// SCOPE BOUNDARY (multi-service selection vs. single-service booking): the
// approved Step 1 design lets the client multi-select services, and this
// screen's carried [BookingSlotPickerArgs.services] renders the FULL
// selection in the summary shelf + sums their durations for the chosen-window
// line, exactly as designed. But the Phase 14.0 booking data layer
// (`SlotRepository.getMasterSlots`, `CreateBookingRequest`) supports exactly
// ONE service per booking — there is no backend capability for "one
// appointment covering N services" today. Slot AVAILABILITY is therefore
// fetched, and the eventual booking is created, against `services.first` (the
// PRIMARY service) only. This mirrors the phase doc's literal acceptance
// criteria (`SlotRepository.getMasterSlots(masterId, serviceId, date)` and
// the `/booking/confirm` extras are both singular-`serviceId`) and is a
// deliberate, documented scope boundary for this phase — not an oversight.
//
// DEVIATION (calendar day availability): see the file header of
// `widgets/month_calendar.dart` — there is no month/day-level availability
// endpoint, so [SlotDateScreen] marks every non-past day as tappable rather
// than fabricating Sunday/fully-booked heuristics the backend cannot back up.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';

import '../application/slot_picker_notifier.dart';
import '../domain/booking_confirm_args.dart';
import '../domain/booking_slot.dart';
import '../domain/booking_slot_picker_args.dart';
import 'widgets/booking_summary_bar.dart';
import 'widgets/master_strip.dart';
import 'widgets/month_calendar.dart';
import 'widgets/slot_chip.dart';

// ---------------------------------------------------------------------------
// Step 2a — date screen
// ---------------------------------------------------------------------------

/// "Оберіть дату" — a single-month calendar. Tapping a day fetches that day's
/// slots (via [SlotPickerNotifier.loadSlots]) so they are ready by the time
/// the client reaches [SlotTimeScreen]. "Далі" enables once a day is chosen.
class SlotDateScreen extends ConsumerStatefulWidget {
  const SlotDateScreen({super.key, required this.args});

  final BookingSlotPickerArgs args;

  @override
  ConsumerState<SlotDateScreen> createState() => _SlotDateScreenState();
}

class _SlotDateScreenState extends ConsumerState<SlotDateScreen> {
  late final DateTime _today;
  late final DateTime _firstMonth;
  late final DateTime _lastMonth;
  late DateTime _visibleMonth;

  /// Booking horizon — 3 months out. Matches the master schedule's own
  /// period-range picker horizon; no backend signal dictates a different cap.
  static const int _horizonMonths = 3;

  @override
  void initState() {
    super.initState();
    final DateTime now = DateTime.now();
    _today = DateTime(now.year, now.month, now.day);
    _firstMonth = DateTime(_today.year, _today.month, 1);
    _lastMonth = DateTime(_today.year, _today.month + _horizonMonths, 1);
    _visibleMonth = _firstMonth;
  }

  bool _isAvailable(DateTime day) => !day.isBefore(_today);

  void _selectDay(DateTime day) {
    final String serviceId = widget.args.services.first.id;
    ref
        .read(slotPickerProvider.notifier)
        .loadSlots(
          masterId: widget.args.masterId,
          serviceId: serviceId,
          date: day,
        );
  }

  void _prevMonth() {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month - 1, 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 1);
    });
  }

  void _goToTime() {
    context.push(RouteNames.bookingSlotsTime, extra: widget.args);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Narrow watch (mobile-perf finding #3): this screen only ever renders
    // `selectedDate` (via `MonthCalendar` + `BookingSummaryBar.enabled`) —
    // never `state.slots`. Watching the full `SlotPickerState` meant every
    // `loadSlots()` call (AsyncLoading → resolved) rebuilt the whole screen,
    // including the ~35-42 cell month grid, twice per day-tap for state this
    // screen never displays.
    final DateTime? selectedDate = ref.watch(
      slotPickerProvider.select((SlotPickerState s) => s.selectedDate),
    );

    return Scaffold(
      backgroundColor: BrandColors.base,
      bottomNavigationBar: BookingSummaryBar(
        services: widget.args.services,
        ctaLabel: l10n.bookingNextCta,
        ctaIcon: Icons.arrow_forward_rounded,
        enabled: selectedDate != null,
        onAction: _goToTime,
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            _BookingTopBar(
              title: l10n.bookingDateScreenTitle,
              backSemantics: l10n.registerBackStep,
              onBack: () => context.pop(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                VelvetSpacing.lg,
                VelvetSpacing.md,
                VelvetSpacing.lg,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    l10n.bookingDateScreenIntro,
                    style: VelvetText.body().copyWith(fontSize: 14),
                  ),
                  const SizedBox(height: VelvetSpacing.lg),
                  MasterStrip(master: widget.args.master),
                  const SizedBox(height: VelvetSpacing.lg),
                  const CalendarWeekdayBar(),
                  const SizedBox(height: VelvetSpacing.xs),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: MonthCalendar(
                  key: const Key('booking-month-calendar'),
                  visibleMonth: _visibleMonth,
                  today: _today,
                  selected: selectedDate,
                  isAvailable: _isAvailable,
                  onSelectDay: _selectDay,
                  onPrevMonth: _visibleMonth.isAfter(_firstMonth)
                      ? _prevMonth
                      : null,
                  onNextMonth: _visibleMonth.isBefore(_lastMonth)
                      ? _nextMonth
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 2b — time screen
// ---------------------------------------------------------------------------

/// "Оберіть час" — Ранок/День/Вечір time-chip clusters for the date chosen on
/// [SlotDateScreen]. "Підтвердити" enables once a slot is chosen and pushes
/// `RouteNames.bookingConfirm`.
class SlotTimeScreen extends ConsumerWidget {
  const SlotTimeScreen({super.key, required this.args});

  final BookingSlotPickerArgs args;

  void _confirm(BuildContext context, BookingSlot slot) {
    context.push(
      RouteNames.bookingConfirm,
      extra: BookingConfirmArgs(
        masterId: args.masterId,
        serviceId: args.services.first.id,
        startAt: slot.startAt,
        rescheduleBookingId: args.rescheduleBookingId,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final SlotPickerState state = ref.watch(slotPickerProvider);
    final DateTime? selectedDate = state.selectedDate;

    if (selectedDate == null) {
      // Defensive: this route is only reachable via SlotDateScreen's "Далі",
      // which requires a selected date first — reaching it without one (e.g.
      // a stale deep link) is a broken-flow edge case, not a normal path.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.pop();
      });
      return const Scaffold(body: SizedBox.shrink());
    }

    final int totalMinutes = args.services.fold<int>(
      0,
      (int sum, service) => sum + service.durationMinutes,
    );
    final BookingSlot? selectedSlot = state.selectedSlot;
    final String? windowLabel = selectedSlot == null
        ? null
        : formatBookingWindow(
            selectedSlot.startAt,
            selectedSlot.startAt.add(Duration(minutes: totalMinutes)),
          );

    return Scaffold(
      backgroundColor: BrandColors.base,
      bottomNavigationBar: BookingSummaryBar(
        services: args.services,
        ctaLabel: l10n.bookingConfirmCta,
        ctaIcon: Icons.check_circle_outline_rounded,
        enabled: selectedSlot != null,
        showChosenWindow: true,
        chosenWindowLabel: windowLabel,
        onAction: selectedSlot == null
            ? () {}
            : () => _confirm(context, selectedSlot),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            _BookingTopBar(
              title: l10n.bookingTimeScreenTitle,
              backSemantics: l10n.bookingTimeScreenBackSemantics,
              onBack: () => context.pop(),
            ),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  VelvetSpacing.lg,
                  VelvetSpacing.sm,
                  VelvetSpacing.lg,
                  VelvetSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _DayHeaderChip(
                      label: formatBookingDayHeader(selectedDate),
                      master: args.master,
                      onChange: () => context.pop(),
                    ),
                    const SizedBox(height: VelvetSpacing.lg),
                    _SlotsSection(
                      slotsAsync: state.slots,
                      selectedSlot: selectedSlot,
                      onSelectSlot: (BookingSlot slot) => ref
                          .read(slotPickerProvider.notifier)
                          .selectSlot(slot),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared top bar
// ---------------------------------------------------------------------------

class _BookingTopBar extends StatelessWidget {
  const _BookingTopBar({
    required this.title,
    required this.backSemantics,
    required this.onBack,
  });

  final String title;
  final String backSemantics;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        VelvetSpacing.lg,
        VelvetSpacing.md,
        VelvetSpacing.lg,
        VelvetSpacing.sm,
      ),
      child: SizedBox(
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Align(
              alignment: Alignment.centerLeft,
              child: NeumorphicIconButton(
                key: const Key('slot-picker-back'),
                icon: Icons.arrow_back_ios_new_rounded,
                semanticLabel: backSemantics,
                onTap: onBack,
              ),
            ),
            Text(
              title,
              style: VelvetText.subheading(),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Day header chip (time screen)
// ---------------------------------------------------------------------------

class _DayHeaderChip extends StatelessWidget {
  const _DayHeaderChip({
    required this.label,
    required this.master,
    required this.onChange,
  });

  final String label;
  final Master master;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String masterName = '${master.firstName} ${master.lastName}'.trim();
    final String masterRole = masterRoleLabel(master.type, l10n);
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
                    style: VelvetText.subheading().copyWith(
                      fontSize: 16,
                      color: BrandColors.accentDeep,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '$masterName · $masterRole',
                    style: VelvetText.feedback(
                      BrandColors.textSecondary,
                    ).copyWith(fontSize: 11),
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
                        style: VelvetText.feedback(
                          BrandColors.accentDeep,
                        ).copyWith(fontSize: 13, fontWeight: FontWeight.w800),
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

// ---------------------------------------------------------------------------
// Slots section (Ранок / День / Вечір clusters)
// ---------------------------------------------------------------------------

class _SlotsSection extends StatefulWidget {
  const _SlotsSection({
    required this.slotsAsync,
    required this.selectedSlot,
    required this.onSelectSlot,
  });

  final AsyncValue<List<BookingSlot>> slotsAsync;
  final BookingSlot? selectedSlot;
  final ValueChanged<BookingSlot> onSelectSlot;

  @override
  State<_SlotsSection> createState() => _SlotsSectionState();
}

class _SlotsSectionState extends State<_SlotsSection> {
  // Memoized time-of-day buckets (mobile-perf finding #5): bucketing `slots`
  // into Ранок/День/Вечір doesn't depend on `selectedSlot`, but this widget
  // used to redo the O(n) bucketing loop on every rebuild — including the
  // rebuild triggered by simply tapping a time chip (which only ever changes
  // `selectedSlot`, never `slots`). Cache the three buckets and only
  // recompute when the underlying `slots` list identity changes.
  List<BookingSlot>? _cachedSlots;
  (List<BookingSlot>, List<BookingSlot>, List<BookingSlot>)? _cachedBuckets;

  (List<BookingSlot>, List<BookingSlot>, List<BookingSlot>) _bucketsFor(
    List<BookingSlot> slots,
  ) {
    final (List<BookingSlot>, List<BookingSlot>, List<BookingSlot>)? cached =
        _cachedBuckets;
    if (cached != null && identical(_cachedSlots, slots)) {
      return cached;
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
    final (List<BookingSlot>, List<BookingSlot>, List<BookingSlot>) result = (
      morning,
      afternoon,
      evening,
    );
    _cachedSlots = slots;
    _cachedBuckets = result;
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          l10n.bookingFreeTimeHeading,
          style: VelvetText.subheading().copyWith(fontSize: 16),
        ),
        const SizedBox(height: VelvetSpacing.md),
        widget.slotsAsync.when(
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
              style: VelvetText.feedback(BrandColors.muted),
            ),
          ),
          data: (List<BookingSlot> slots) {
            if (slots.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: VelvetSpacing.lg),
                child: Text(
                  l10n.bookingDayUnavailableState,
                  style: VelvetText.feedback(BrandColors.muted),
                ),
              );
            }
            final (
              List<BookingSlot> morning,
              List<BookingSlot> afternoon,
              List<BookingSlot> evening,
            ) = _bucketsFor(
              slots,
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (morning.isNotEmpty) ...<Widget>[
                  _group(l10n.bookingMorningLabel, morning),
                  const SizedBox(height: VelvetSpacing.md),
                ],
                if (afternoon.isNotEmpty) ...<Widget>[
                  _group(l10n.bookingAfternoonLabel, afternoon),
                  const SizedBox(height: VelvetSpacing.md),
                ],
                if (evening.isNotEmpty)
                  _group(l10n.bookingEveningLabel, evening),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _group(String label, List<BookingSlot> group) {
    return SlotGroup(
      label: label,
      children: <Widget>[
        for (final BookingSlot s in group)
          SizedBox(
            width: 74,
            child: SlotChip(
              key: Key('slot-chip-${s.startAt.toIso8601String()}'),
              time: formatSlotTime(s.startAt),
              available: s.available,
              selected: widget.selectedSlot == s,
              onTap: () => widget.onSelectSlot(s),
            ),
          ),
      ],
    );
  }
}
