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
// CALENDAR DAY-AVAILABILITY GATING (Phase 14.14): [SlotDateScreen] derives
// its [MonthCalendar.isAvailable] callback from `workingDaysProvider`
// (`application/working_days_notifier.dart`), keyed to the currently-visible
// month for `widget.args.masterId` — see that file and the updated header of
// `widgets/month_calendar.dart` for the full rationale. A day is tappable iff
// it is not in the past AND the resolved working-days set marks it working.
//
// FULLY-BOOKED EMPTY STATE (Phase 14.15): a working day can still resolve to
// zero bookable slots once chosen (fully booked) — [_SlotsSection] renders a
// dedicated empty state for that case, distinct from the calendar's
// day-level greying above and from a genuine fetch error.

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
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';

import '../application/slot_picker_notifier.dart';
import '../application/working_days_notifier.dart';
import '../domain/booking_confirm_args.dart';
import '../domain/booking_slot.dart';
import '../domain/booking_slot_picker_args.dart';
import '../domain/working_day.dart';
import '../domain/working_days_query.dart';
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

  /// Loading-flash fix (mirrors `MasterScheduleScreen`'s `_lastDays` visual
  /// pattern, NOT its keepAlive cache lifetime — see
  /// `working_days_notifier.dart`'s file header): the last successfully
  /// resolved working-days list, retained across a month-step so the grid
  /// does not flash to a full-screen spinner while the new month's fetch is
  /// still in flight. When it is showing while a DIFFERENT month's fetch is
  /// pending, its dates simply won't match the new grid's day keys, so
  /// [_availabilityFrom] conservatively renders every cell as non-working
  /// (never a false "available") until the fresh month's data lands — the
  /// thin top progress line (see [_calendarBody]) signals that fetch is
  /// still in flight. Never explicitly cleared — a stale-but-OK list is
  /// always preferable to nothing once we have one, and it is naturally
  /// superseded the next time a fetch resolves.
  List<WorkingDay>? _lastWorkingDays;

  /// The family key for `workingDaysProvider`, scoped to the master carried
  /// by [widget.args] and the currently-visible month.
  WorkingDaysQuery get _workingDaysQuery => WorkingDaysQuery.month(
    masterId: widget.args.masterId,
    anyDayInMonth: _visibleMonth,
  );

  static int _dayKey(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  /// Builds the [MonthCalendar.isAvailable] predicate from a resolved
  /// working-days list: not in the past AND the fetched set marks the day
  /// `working: true`. A day absent from the set (should not normally happen
  /// — the query always spans the full visible month) is treated
  /// conservatively as non-working rather than defaulting to tappable.
  bool Function(DateTime) _availabilityFrom(List<WorkingDay> days) {
    final Map<int, bool> workingByDay = <int, bool>{
      for (final WorkingDay w in days) _dayKey(w.date): w.working,
    };
    return (DateTime day) {
      if (day.isBefore(_today)) return false;
      return workingByDay[_dayKey(day)] ?? false;
    };
  }

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
    // Phase 14.14: the per-day working/non-working signal for the currently
    // visible month, re-derived (and re-watched) whenever `_visibleMonth`
    // changes — see `_workingDaysQuery`.
    final AsyncValue<List<WorkingDay>> workingDaysAsync = ref.watch(
      workingDaysProvider(_workingDaysQuery),
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
              // Hero (jank fix): `SlotTimeScreen` renders its own `MasterStrip`
              // for the exact same master, and both screens are mounted on the
              // SAME `go_router` Navigator (see `app_router.dart`'s nested
              // `bookingSlots` / `bookingSlots/time` routes) via a real
              // `CupertinoPageTransitionsBuilder` push — so a shared `Hero` tag
              // lets the framework fly/hold this card across the transition
              // instead of the two independently-laid-out instances swapping
              // at mismatched y-offsets the instant the push settles.
              child: Hero(
                tag: 'master-strip-${widget.args.master.id}',
                child: MasterStrip(master: widget.args.master),
              ),
            ),
            const SizedBox(height: VelvetSpacing.lg),
            // `CalendarWeekdayBar` (and `_calendarBody`'s `MonthCalendar`) are
            // deliberately left UNWRAPPED here — both already self-pad
            // horizontally by the same `VelvetSpacing.lg`, matching
            // `master_schedule_page.dart`'s pattern (see its comment at the
            // `CalendarWeekdayBar` usage there). Nesting either inside this
            // screen's own `Padding(horizontal: VelvetSpacing.lg)` — as
            // `MasterStrip` above still needs, since it does NOT self-pad —
            // would stack insets and misalign the weekday labels from the
            // day-grid columns beneath them.
            const CalendarWeekdayBar(),
            const SizedBox(height: VelvetSpacing.xs),
            Expanded(
              child: _calendarBody(l10n, selectedDate, workingDaysAsync),
            ),
          ],
        ),
      ),
    );
  }

  /// Renders the month grid once the current month's working-days fetch has
  /// SOMETHING to show (fresh or cached-stale), a full-screen spinner on a
  /// genuine first load with nothing cached yet, or a retry state on error.
  /// Mirrors `MasterScheduleScreen._body`'s three-way split, simplified for
  /// this screen's single (unbounded-cache) data source — see
  /// `working_days_notifier.dart`'s file header for why the full keepAlive
  /// machinery isn't mirrored too.
  Widget _calendarBody(
    AppLocalizations l10n,
    DateTime? selectedDate,
    AsyncValue<List<WorkingDay>> workingDaysAsync,
  ) {
    if (workingDaysAsync.hasError) {
      return _WorkingDaysErrorBody(
        failure: workingDaysAsync.error!,
        onRetry: () => ref.invalidate(workingDaysProvider(_workingDaysQuery)),
      );
    }

    final List<WorkingDay>? resolvedDays = workingDaysAsync.value;
    if (resolvedDays != null) {
      _lastWorkingDays = resolvedDays;
    }

    final bool loading = workingDaysAsync.isLoading;
    final List<WorkingDay>? daysToRender =
        resolvedDays ?? (loading ? _lastWorkingDays : null);

    if (daysToRender == null) {
      // Genuine first load: nothing resolved yet for ANY month this screen
      // instance has shown.
      return const Center(
        child: CircularProgressIndicator(color: BrandColors.accent),
      );
    }

    final Widget calendar = SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: MonthCalendar(
        key: const Key('booking-month-calendar'),
        visibleMonth: _visibleMonth,
        today: _today,
        selected: selectedDate,
        isAvailable: _availabilityFrom(daysToRender),
        onSelectDay: _selectDay,
        onPrevMonth: _visibleMonth.isAfter(_firstMonth) ? _prevMonth : null,
        onNextMonth: _visibleMonth.isBefore(_lastMonth) ? _nextMonth : null,
      ),
    );

    // Loading-flash fix: keep the (possibly stale-month) grid fully visible
    // and overlay a thin top progress line while a fetch is in flight — no
    // layout shift, dismissed the instant the fetch resolves. The genuine
    // first load never reaches here (it returned the spinner above).
    if (!loading) return calendar;
    return Stack(
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
    );
  }
}

// ---------------------------------------------------------------------------
// Working-days error body — neumorphic retry, mirroring
// `MasterScheduleScreen`'s `_ErrorBody`.
// ---------------------------------------------------------------------------

class _WorkingDaysErrorBody extends StatelessWidget {
  const _WorkingDaysErrorBody({required this.failure, required this.onRetry});

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
              key: const Key('booking-calendar-retry'),
              label: l10n.retryLabel,
              onPressed: onRetry,
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
    // Narrow watch (mobile-perf finding): mirrors `SlotDateScreen`'s own fix
    // above. `SlotPickerState` has no `==` override, so a raw
    // `ref.watch(slotPickerProvider)` treats EVERY `state = state.copyWith(…)`
    // assignment as "changed" — including a no-op re-tap of the
    // already-selected slot — and rebuilds the whole tree (`MasterStrip`,
    // `_SlotsSection`) every time, even though this screen's
    // three field reads below (`selectedDate`, `selectedSlot`, `slots`) each
    // have proper value equality (`DateTime`, freezed `BookingSlot`,
    // `AsyncValue`). Selecting them individually means an unchanged field
    // never re-triggers this build, while a genuinely changed one still does
    // (`selectSlot()` → `selectedSlot`; a still-in-flight `loadSlots()` fetch
    // resolving after "Далі" was tapped early → `slots`).
    final DateTime? selectedDate = ref.watch(
      slotPickerProvider.select((SlotPickerState s) => s.selectedDate),
    );
    final BookingSlot? selectedSlot = ref.watch(
      slotPickerProvider.select((SlotPickerState s) => s.selectedSlot),
    );
    final AsyncValue<List<BookingSlot>> slotsAsync = ref.watch(
      slotPickerProvider.select((SlotPickerState s) => s.slots),
    );

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
                  // Jank fix: matches `SlotDateScreen`'s established
                  // top-bar-bottom(`sm`) + own-top-inset(`md`) = 24dp total gap
                  // above `MasterStrip` (that screen's spacing predates this
                  // one — `MasterStrip` was only added here afterwards, see
                  // below). Was `VelvetSpacing.sm` (16dp total), which put the
                  // incoming card 8dp higher than the outgoing one relative to
                  // the shared `_BookingTopBar`, visibly hopping the card the
                  // instant the push transition settled.
                  VelvetSpacing.md,
                  VelvetSpacing.lg,
                  VelvetSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // Phase 14.1 follow-up: mirrors `SlotDateScreen`'s own
                    // `MasterStrip` placement (and `master_schedule_page.dart`'s
                    // persistent-strip pattern for the salon-booking flow) so
                    // the "who you're booking with" context survives the
                    // date → time step, not just the date screen. No extra
                    // horizontal `Padding` wrapper here (unlike
                    // `SlotDateScreen`'s) — this screen's enclosing
                    // `SingleChildScrollView` already applies
                    // `VelvetSpacing.lg` horizontal padding to every child.
                    //
                    // Jank fix: now wrapped in a `Hero` sharing
                    // `SlotDateScreen`'s exact tag (`master-strip-<id>`) so the
                    // framework flies/holds this card across the real
                    // `CupertinoPageTransitionsBuilder` push between the two
                    // nested `go_router` routes (both mounted on the same
                    // Navigator — see `app_router.dart`), instead of the two
                    // independently-laid-out instances swapping at mismatched
                    // y-offsets the instant the transition settles. Previously
                    // carried no `Hero`/shared-element tag or `GlobalKey`.
                    //
                    // Phase 14.1 correction: this screen used to ALSO render a
                    // `_DayHeaderChip` (day label + master name/role + a
                    // "change date" CTA) directly below `MasterStrip`. Once
                    // `MasterStrip` was added, that chip's master-identity
                    // line became a pure duplicate of `MasterStrip`'s own
                    // content, so the chip was removed outright rather than
                    // kept as a second card — this screen shows exactly ONE
                    // card at the top. Its "change date" affordance is not
                    // lost: `_BookingTopBar`'s back button (`onBack: () =>
                    // context.pop()`) already pops back to `SlotDateScreen`,
                    // which is the exact same action the removed chip's
                    // `onChange` performed.
                    Hero(
                      tag: 'master-strip-${args.master.id}',
                      child: MasterStrip(master: args.master),
                    ),
                    const SizedBox(height: VelvetSpacing.lg),
                    _SlotsSection(
                      slotsAsync: slotsAsync,
                      selectedSlot: selectedSlot,
                      onSelectSlot: (BookingSlot slot) => ref
                          .read(slotPickerProvider.notifier)
                          .selectSlot(slot),
                      onChangeDate: () => context.pop(),
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
// Slots section (Ранок / День / Вечір clusters)
// ---------------------------------------------------------------------------

class _SlotsSection extends StatefulWidget {
  const _SlotsSection({
    required this.slotsAsync,
    required this.selectedSlot,
    required this.onSelectSlot,
    required this.onChangeDate,
  });

  final AsyncValue<List<BookingSlot>> slotsAsync;
  final BookingSlot? selectedSlot;
  final ValueChanged<BookingSlot> onSelectSlot;

  /// Phase 14.15 — the "Обрати іншу дату" CTA on the fully-booked-day empty
  /// state pops back to [SlotDateScreen], mirroring `_BookingTopBar`'s own
  /// back-button action on this screen.
  final VoidCallback onChangeDate;

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
              // Phase 14.15 — a resolved-but-empty result means the day IS a
              // working day (it passed the Phase 14.14 calendar gate to get
              // here) that happens to be fully booked — distinct from the
              // `error` branch above (a genuine fetch failure), which keeps
              // the older generic "unavailable" copy.
              return _NoSlotsEmptyState(onChangeDate: widget.onChangeDate);
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

// ---------------------------------------------------------------------------
// Phase 14.15 — _NoSlotsEmptyState: the fully-booked-day empty state.
//
// Renders when [SlotPickerNotifier.loadSlots] resolves SUCCESSFULLY to an
// empty list — i.e. the chosen day passed the Phase 14.14 calendar gate (it
// IS a working day), but every slot on it is already booked out. Mirrors the
// icon + centered-text composition of
// `MasterScheduleScreen`'s `_DayOffEmptyState`, plus a "Обрати іншу дату" CTA
// (the same back-to-`SlotDateScreen` affordance `_BookingTopBar`'s back
// button already exposes above) so the client isn't left at a dead end.
// ---------------------------------------------------------------------------
class _NoSlotsEmptyState extends StatelessWidget {
  const _NoSlotsEmptyState({required this.onChangeDate});

  final VoidCallback onChangeDate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      key: const Key('booking-no-slots-empty-state'),
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
            style: VelvetText.body().copyWith(color: BrandColors.textSecondary),
          ),
          const SizedBox(height: VelvetSpacing.lg),
          NeumorphicButton(
            key: const Key('booking-no-slots-change-date'),
            label: l10n.bookingChangeDateCta,
            icon: Icons.edit_calendar_outlined,
            onPressed: onChangeDate,
          ),
        ],
      ),
    );
  }
}
