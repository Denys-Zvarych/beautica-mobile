// Phase 14.16/14.17 — MasterSchedulePage: one master's inline date→time
// picker slide on the salon booking flow's step-3 "Час" screen.
//
// Ports `docs/signup-designs/SalonBookingTime/lib/widgets/master_schedule_page.dart`
// onto real data + providers: the SHARED [MasterStrip] identity header (the
// same card the independent-master flow's date/time screens render), the
// SHARED [MonthCalendar]/[CalendarWeekdayBar] for the DATE (day-gated via the
// real `workingDaysProvider`, exactly like `SlotDateScreen`, Phase 14.14),
// and the SHARED [SlotGroup]/[SlotChip] Ранок/День/Вечір clusters for the
// TIME (fetched via `salonMasterDaySlotsProvider`, keyed on EVERY one of this
// master's assigned services' own per-master ASSIGNMENT ids — see
// `salon_booking_schedule_notifier.dart`'s file header for the full
// architecture note, and `SalonMasterSchedule.orderedMasterServiceIds`'s
// doc comment for why these are assignment ids and not the salon catalog id).
// [MasterStrip]/[MonthCalendar]/[SlotChip] are all shared verbatim with the
// independent-master flow — the identity card was unified onto [MasterStrip]
// (the salon-only `SalonMasterStrip` fork is gone), so a change to that one
// widget now reaches every booking screen in both flows.
//
// Two inline phases on the one slide: pick a DATE → the step-3 CTA («Далі»,
// `SalonTimeScreen._handleNext`) commits that pick and swaps the slide to
// the TIME chips for that date → picking a slot records it, and the SAME CTA
// (now enabled) advances to the next unscheduled master or, once every
// master is scheduled, confirms («Підтвердити») — see
// `SalonBookingSchedule.enterTimePhase`/[SalonScheduleEntry.viewingTime].
// Neither phase transition is automatic any more: a date pick alone no
// longer swaps the slide, and a slot pick alone no longer advances the
// slider — both used to fire directly off the tap; the CTA is now the only
// forward-navigation trigger. Returning from the TIME phase to the calendar
// is still handled three redundant ways — all of which call the SAME
// `_clearDate()` — the
// `SalonTimeScreen` top-bar arrow, the Android system back gesture (both via
// `salon_time_screen.dart`'s `PopScope`), and a left-edge swipe-back
// affordance local to this slide's TIME phase (see `_onEdgeSwipeEnd` below),
// which restores the swipe-back feel the route-level `PopScope(canPop:
// false)` otherwise silently disarms on the slot grid.
//
// Self-sufficient Riverpod integration (mirrors `SlotDateScreen`/
// `SlotTimeScreen`, NOT the preview's parent-owned local `State`): this
// widget reads/writes `salonBookingScheduleProvider` directly rather than
// funnelling every pick through a callback owned by `SalonTimeScreen`.
// [onCompleted] is no longer invoked by this widget at all — forward
// navigation (both date→time and master→master) is entirely CTA-driven from
// `SalonTimeScreen` now, which reads the SAME shared provider state directly
// rather than being told via a callback. The parameter stays (see its own
// doc comment) purely so an existing/future bare-pumped caller's signature
// keeps compiling.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';

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
    this.onCompleted,
    this.keepAlive = false,
  });

  final SalonMasterSchedule schedule;
  final List<Color> avatarGradient;

  /// NO LONGER INVOKED by this widget — forward navigation (date→time and
  /// master→master) moved entirely to the step-3 CTA
  /// (`SalonTimeScreen._handleNext`, reading `salonBookingScheduleProvider`
  /// directly) so a slot pick alone never auto-advances anything. Kept as an
  /// optional, unused-by-this-widget parameter rather than deleted — other
  /// callers/tests may still construct a `MasterSchedulePage` passing it.
  final VoidCallback? onCompleted;

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
  ///
  /// Defaults to `false` — the stock `AutomaticKeepAliveClientMixin`
  /// behaviour — so a bare-pumped page (no host slider) costs nothing.
  final bool keepAlive;

  @override
  ConsumerState<MasterSchedulePage> createState() => _MasterSchedulePageState();
}

class _MasterSchedulePageState extends ConsumerState<MasterSchedulePage>
    with AutomaticKeepAliveClientMixin {
  /// Booking horizon — 3 months out, matching `SlotDateScreen`'s own
  /// `_horizonMonths`; no backend signal dictates a different cap.
  static const int _horizonMonths = 3;

  /// "Today", Kyiv-anchored — mirrors `SlotDateScreen._today`'s own
  /// derivation (`slot_picker_screen.dart`): slot availability is a Kyiv-day
  /// concept on the backend (`SlotCalculationService`'s
  /// `atStartOfDay(TimeZones.KYIV)`), so the past-day gate below must be the
  /// Kyiv day, not the device's own. See `shared/time/kyiv_day.dart`.
  /// Captured once here (unlike `SlotDateScreen`, which re-derives per build
  /// to survive a picker left open across midnight) — this slide is
  /// recreated whenever `SalonTimeScreen`'s pager rebuilds it, which is
  /// enough of a re-anchor point for the horizon/past-day gate this widget
  /// needs.
  late final DateTime _today;
  late final DateTime _firstMonth;
  late final DateTime _lastMonth;
  late DateTime _visibleMonth;

  /// Loading-flash fix, mirroring `SlotDateScreen._lastWorkingDays` — see
  /// that file for the full rationale.
  List<WorkingDay>? _lastWorkingDays;

  /// mobile-perf Finding (LOW) fix — the comma-joined service-name heading
  /// (`_datePhase`/`_timePhase`, both) used to be recomputed with
  /// `.join(', ')` on every `build()`. That's cheap for `_datePhase` (only
  /// rebuilds on date pick/clear) but `_timePhase` rebuilds on EVERY slot
  /// tap (`_selectSlot` → `salonBookingScheduleProvider.notifier
  /// .selectSlot` → the `entryFor(_masterId)` `select` watched in `build()`
  /// → re-enters `_timePhase`), so the same string got rebuilt on a much
  /// hotter path than it needs to. `widget.schedule` is immutable for the
  /// life of a given slide (see the field's own doc comment / this file's
  /// header), so the joined string is computed exactly once per slide —
  /// here in `initState` — and refreshed only in `didUpdateWidget` if this
  /// State is ever reused for a different `schedule` (e.g. a future pager
  /// change that reparents an existing Element onto a new master). Also
  /// collapses any run of whitespace — including a literal `\n` a
  /// server-controlled service name could contain — to a single space, so
  /// an adversarial/malformed name can't consume the `maxLines: 2` budget
  /// below with blank lines. Both phases read this ONE cached value now —
  /// see `_datePhase`/`_timePhase`.
  late String _serviceNamesHeading;

  /// mobile-security Finding (LOW) fix — service names are server-controlled
  /// (a salon owner names their own catalogue), so a comma-joined heading
  /// could smuggle Unicode bidi *format* controls (category Cf, but NOT
  /// whitespace — the old `\s+` collapse below never touched them). An
  /// embedded RLO/RLI etc. can visually reorder the rendered glyphs, e.g.
  /// making the second service in a two-service heading appear to lead.
  /// This matches exactly the Unicode `Bidi_Control=Yes` property set (ALM,
  /// LRM, RLM, the explicit embeddings/overrides LRE/RLE/PDF/LRO/RLO, and
  /// the isolates LRI/RLI/FSI/PDI) — deliberately narrower than all of Cf,
  /// which would also catch U+00AD soft hyphen and U+FEFF ZWNBSP/BOM. Those
  /// two affect line-breaking/byte-order, not left-to-right/right-to-left
  /// order, so they're a different (out-of-scope) concern from the visual
  /// reordering this finding is about. Neither Cyrillic nor Latin script
  /// needs any Bidi_Control character to render correctly, so stripping
  /// this exact set is lossless for every real Ukrainian, Latin, or
  /// mixed-script service name — it only ever removes an adversarial or
  /// accidental control character, never a character load-bearing for a
  /// legitimate name.
  static final RegExp _bidiControlPattern = RegExp(
    '[\u061C\u200E\u200F\u202A-\u202E\u2066-\u2069]',
  );

  static final RegExp _whitespacePattern = RegExp(r'\s+');

  static String _joinServiceNames(SalonMasterSchedule schedule) => schedule
      .services
      .map((SalonCatalogService s) => s.name)
      .join(', ')
      .replaceAll(_bidiControlPattern, '')
      .replaceAll(_whitespacePattern, ' ')
      .trim();

  @override
  void initState() {
    super.initState();
    _today = kyivToday(ref.read(clockProvider));
    _firstMonth = DateTime(_today.year, _today.month, 1);
    _lastMonth = DateTime(_today.year, _today.month + _horizonMonths, 1);
    _visibleMonth = _firstMonth;
    _serviceNamesHeading = _joinServiceNames(widget.schedule);
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
    if (oldWidget.schedule != widget.schedule) {
      _serviceNamesHeading = _joinServiceNames(widget.schedule);
    }
  }

  String get _masterId => widget.schedule.masterId;

  WorkingDaysQuery get _workingDaysQuery => WorkingDaysQuery.month(
    masterId: _masterId,
    anyDayInMonth: _visibleMonth,
    serviceIds: widget.schedule.orderedMasterServiceIds,
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
    ref.read(salonBookingScheduleProvider.notifier).selectDate(_masterId, day);
  }

  void _clearDate() {
    ref.read(salonBookingScheduleProvider.notifier).clearDate(_masterId);
  }

  // ---------------------------------------------------------------------
  // Left-edge swipe-back on the TIME phase — restores the affordance
  // `PopScope(canPop: !inTimePhase)` in `salon_time_screen.dart` silently
  // disarms (a `canPop: false` `PopScope` never arms Cupertino's own
  // edge-drag recognizer at all — see this fix's PR description for the
  // full trace through `ModalRoute.popGestureEnabled` /
  // `CupertinoRouteTransitionMixin`). Scoped as a SLIDE-LOCAL gesture
  // (not a route-level one) so it can never fight the `PageView`'s own
  // master-to-master swipe in `salon_time_screen.dart` — see `_timePhase`
  // below for how the detector is confined to a narrow left-edge strip.
  // Reuses `_clearDate()` verbatim: the exact same call the removed
  // `_ChangeDateButton`/the still-present `_NoSlotsEmptyState` use, so
  // there is only ever ONE notion of "go back a phase".
  // ---------------------------------------------------------------------

  /// Left-edge hit-strip width — same order of magnitude as Cupertino's own
  /// `_kBackGestureWidth` (`cupertino/route.dart`, 20.0) so the arm-zone
  /// feels consistent with the real system back-swipe that takes over once
  /// this master reaches the date phase.
  static const double _kEdgeSwipeWidth = 20;

  /// Net rightward travel (logical px) that alone commits the gesture, even
  /// at low velocity — roughly 2.4× the hit-strip width, comfortably above
  /// touch-slop-scale jitter but well short of a full swipe.
  static const double _kEdgeSwipeDistanceThreshold = 48;

  /// Rightward fling velocity (logical px/s) that alone commits the gesture
  /// even if [_kEdgeSwipeDistanceThreshold] wasn't reached yet — mirrors
  /// Cupertino's own velocity-based "drop the swipe, still commit" escape
  /// hatch (`_kMinFlingVelocity` in `cupertino/route.dart`).
  static const double _kEdgeSwipeVelocityThreshold = 400;

  /// Net signed horizontal travel accumulated since the current edge-drag's
  /// `onHorizontalDragStart` — reset at both the start and the end of every
  /// gesture.
  double _edgeSwipeDx = 0;

  void _onEdgeSwipeStart(DragStartDetails details) {
    _edgeSwipeDx = 0;
  }

  void _onEdgeSwipeUpdate(DragUpdateDetails details) {
    _edgeSwipeDx += details.delta.dx;
  }

  void _onEdgeSwipeEnd(DragEndDetails details) {
    final double dx = _edgeSwipeDx;
    final double velocity = details.primaryVelocity ?? 0;
    _edgeSwipeDx = 0;
    // Rightward only (the standard "back" direction) — a leftward or
    // negligible drag never fires.
    if (dx >= _kEdgeSwipeDistanceThreshold ||
        velocity >= _kEdgeSwipeVelocityThreshold) {
      _clearDate();
    }
  }

  /// Records [slot] as this master's chosen time. Purely a state write now —
  /// no auto-advance: the step-3 CTA («Далі»/«Підтвердити»,
  /// `SalonTimeScreen._handleNext`/`_confirm`) is the only thing that moves
  /// the pager or pushes the confirm screen, once the client presses it.
  void _selectSlot(BookingSlot slot) {
    ref.read(salonBookingScheduleProvider.notifier).selectSlot(_masterId, slot);
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
    // Deliberately keyed on [SalonScheduleEntry.viewingTime], NOT
    // `entry.date == null` — a date pick alone must not swap this slide to
    // the TIME phase; only the step-3 CTA committing via `enterTimePhase`
    // does (see this file's header and that field's own doc comment).
    final bool datePhase = !entry.viewingTime;

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
                ? _datePhase(l10n, entry.date)
                : _timePhase(l10n, entry.date!, entry.slot),
          ),
        ],
      ),
    );
  }

  Widget _datePhase(AppLocalizations l10n, DateTime? selectedDate) {
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
          selected: selectedDate,
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
        // FIX 2 (owner-reported, supersedes FIX 1's intro sentence) — the
        // wrapper sentence («Оберіть зручну дату для «X» — далі підберемо
        // вільний час.») is gone entirely; only the bare, bold service
        // name(s) remain. Service names are DATA, not translated UI copy, so
        // this reads directly off `widget.schedule.services` with no ARB key
        // at all (the two keys that used to hold the sentence,
        // `salonScheduleDateIntro`/`salonScheduleDateIntroForServices`, are
        // removed from both ARB files — see `app_uk.arb`/`app_en.arb`). A
        // master with 2+ assigned services still gets them comma-joined
        // (mirrors the booking-success calendar export's `serviceLabel`
        // join, `booking_success_screen.dart`) — this is a single heading
        // line, not a recap table (the full per-service breakdown is already
        // shown later, on the confirm screen's `BookingRecap`). Style is
        // `VelvetText.bookName16w800` — the SAME token `BookingRecap` uses
        // for a service name at regular (non-compact) size
        // (`booking_recap.dart:446`): reused rather than forked because this
        // heading is semantically identical ("name a service, boldly") just
        // in a different screen region. Empty `services` never happens on a
        // well-formed slide (every assigned master has >=1 service by
        // construction — see `SalonMasterSchedule`'s doc); rather than
        // render an empty bold line, the whole block (heading + its trailing
        // gap) is simply omitted.
        // mobile-security LOW fix — service names are server-controlled
        // (a salon owner names their own services), so this heading is
        // bounded: `maxLines: 2` (a 2-service comma-join is the common
        // case this heading exists for; anything past that ellipsizes
        // rather than pushing the calendar/slot list down) with
        // `TextOverflow.ellipsis`. `_serviceNamesHeading` (cached in
        // `initState`/`didUpdateWidget` — see that field's doc comment,
        // also the mobile-perf fix for this same heading) already
        // collapses embedded whitespace/newlines to single spaces, so a
        // name containing a literal `\n` can't burn through both lines as
        // blank space before the ellipsis kicks in.
        if (widget.schedule.services.isNotEmpty) ...<Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
            child: Text(
              _serviceNamesHeading,
              style: VelvetText.bookName16w800,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: VelvetSpacing.md),
        ],
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
          // The FULL ordered list of this master's assignment ids — every
          // assigned service, not just the first. Each entry MUST be the
          // master's own service-ASSIGNMENT id (`MasterServiceResponse.id`),
          // NOT `services[i].id` (the salon-wide catalog id) — the backend's
          // slots endpoint 404s ("masterService not found") on the catalog
          // id. See `SalonMasterSchedule.orderedMasterServiceIds`'s doc
          // comment. Passing only the primary/first id here queried slot
          // availability against ONE assignment's duration while the strip
          // above displays N — every offered slot was too short (Phase 270
          // D3 fix).
          serviceIds: widget.schedule.orderedMasterServiceIds,
          date: date,
        ),
      ),
    );
    // Wrapped in a single horizontal Padding — unlike `_datePhase`, nothing
    // in this phase's subtree (slot-chip groups, empty/loading/error states)
    // self-pads horizontally, so one `VelvetSpacing.lg` inset here is enough
    // and can't double up with anything (there's no shared
    // `MonthCalendar`/`CalendarWeekdayBar` on this phase).
    //
    // The row that used to lead this phase — a "Вільний час" heading plus a
    // compact inline «Змінити» change-date button — is gone entirely. The
    // button became redundant once the left-edge swipe-back gesture below
    // joined the top-bar arrow and the system back gesture (all three call
    // the same `_clearDate()`), and the heading it sat beside was labelling
    // the only content on the phase, so it carried no information the
    // Ранок/День/Вечір cluster labels don't already give. `_NoSlotsEmptyState`
    // still carries its own change-date button for the zero-slot day.
    //
    // FIX 2 (owner-reported) restores a single leading line — the SAME bare,
    // bold service-name heading `_datePhase` renders (no sentence, no ARB
    // key: see that phase's own comment for the full rationale). The client
    // needs the same "which service is this for" anchor when picking a time
    // as when picking a date, and this is the same slide/same schedule
    // object, so it's the identical widget, not a fork. `build()` already
    // lays a `VelvetSpacing.lg` gap between the `MasterStrip` identity card
    // and the `AnimatedSwitcher` this is a child of, so no extra leading
    // spacer is needed above the heading itself; a `VelvetSpacing.md` gap
    // follows it before the slot groups, mirroring the gap `_datePhase`
    // places between its own heading and the calendar.
    final Widget content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
      child: Column(
        // MUST be `.stretch`, not `.start` (mobile-perf audit fix): this
        // Column is a child of `AnimatedSwitcher`'s default layout builder,
        // which wraps transitioning children in its own
        // `Stack(alignment: .center)` fed via `StackFit.loose` — so this
        // Column receives a LOOSE width and, with `.start`, sizes itself to
        // its narrowest branch (the bare-`Text` error state or
        // `_NoSlotsEmptyState`'s centered content) instead of the full
        // slide width. Verified empirically (`salon_time_screen_test.dart`,
        // "phase container fills the slide" tests): this does NOT actually
        // relocate the left-edge swipe-back `GestureDetector` below —
        // `SizeTransition`'s own `Align` (default `axis: Axis.vertical`,
        // `axisAlignment: -1` here) already claims full width and
        // left-pins its child regardless of this Column's width, so the
        // detector's rendered x stays at the true screen edge either way.
        // What DOES shrink without `.stretch` is this phase's own
        // `Semantics(container: true)` node (the `Stack` wrapping `content`
        // + the detector, returned below) — from the full slide width down
        // to the narrow branch's natural width — which shrinks the
        // accessible bounding box TalkBack's Local Context Menu ("reading
        // menu" → Actions) and Switch Access's per-item action menu use to
        // surface the `onDismiss` action to a sliver in the top-left corner
        // instead of the whole slide. `.stretch` restores full width
        // regardless of the `slotsAsync.when()` branch, mirroring
        // `_datePhase`'s own `Column(crossAxisAlignment: .stretch, ...)`
        // above.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Bounded + cached — same rationale as `_datePhase`'s identical
          // heading (mobile-security LOW: `maxLines`/`overflow` guard a
          // server-controlled name; mobile-perf LOW: `_serviceNamesHeading`
          // is computed once per slide, not on every `slotsAsync`-driven
          // rebuild this phase gets on every slot tap — see that field's
          // doc comment on `_MasterSchedulePageState`).
          if (widget.schedule.services.isNotEmpty) ...<Widget>[
            Text(
              _serviceNamesHeading,
              style: VelvetText.bookName16w800,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: VelvetSpacing.md),
          ],
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

    // `Semantics(onDismiss: _clearDate)` exposes the SAME phase-back action
    // as the edge-swipe below to assistive tech, since the drag itself is
    // not discoverable by a screen-reader user and is not operable by
    // switch access. `ACTION_DISMISS` is surfaced through TalkBack's Local
    // Context Menu ("reading menu" → Actions) and Switch Access's per-item
    // action menu — NOT any two-finger scrub/Z-gesture, which is a
    // navigation gesture, not how a labelled `onDismiss` action is reached.
    // `hint:` names the action explicitly (reusing the still-live
    // `bookingChangeDateCta` copy, NOT the deleted `bookingChangeDateSemantics`
    // key — see this file's header for why the visible button it used to
    // label is gone) so neither menu presents an anonymous, nameless
    // "Dismiss" action. The `key` lives here (not on the inner `Padding`)
    // since this `Semantics` is now the actual `child` `AnimatedSwitcher`
    // compares between the 'date' and 'time' phases.
    //
    // The `Stack` confines the drag detector to a narrow LEFT-EDGE strip —
    // positioned at the slide's true left edge (outside `content`'s own
    // `VelvetSpacing.lg` padding, matching Cupertino's own edge-anchored
    // `_kBackGestureWidth` strip) — so it can never compete with the
    // `PageView`'s master-to-master swipe anywhere else on the slide. A
    // touch starting mid-slide never even hit-tests this detector, so
    // there's no gesture-arena contest for it to lose; a touch starting
    // within the strip DOES enter the same arena as the ancestor
    // `PageView`'s own horizontal drag recognizer, but — being the deeper
    // descendant — this detector is dispatched the pointer first each frame
    // and wins on first sufficient movement, the same "innermost recognizer
    // wins its own footprint" mechanics Cupertino's real edge-swipe (an
    // ANCESTOR-positioned recognizer) already relies on to coexist with this
    // very `PageView` on the DATE phase today.
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
