// Phase 250 — the SALON wizard's own two steps: `dateTime` (date-only) and
// `masters` (per-master expandable slot pickers) — plus the tile/status/
// slot-section pieces they compose. NOT part of Phase 249's promotion: those
// promoted widgets (`ClientStep`, `ServiceStep`, `ConfirmStep`, …) are
// SHARED with the master wizard; these two are salon-only, so they live in
// their own file rather than bloating `booking_wizard_steps.dart` with code
// the master wizard never touches (keeps that file's diff — and its golden
// — untouched by this phase).
//
// ## Why `DateTimeStep` (promoted) could NOT be reused for the date step
//
// `DateTimeStep` wraps [MasterSchedulePage], which needs a KNOWN single
// master up front (it builds a [SalonMasterSchedule] from `master:`) and
// bundles DATE + TIME into one embedded flow via
// `salonBookingScheduleProvider`. The whole point of this phase is that no
// master is chosen yet at the date step — the master (and, with it, the
// time) is chosen ONE step later, inside a tile. There is no way to feed
// `DateTimeStep` a master that does not exist yet, so this is a genuinely
// different widget, not a param away from the promoted one. [SalonDateStep]
// below reuses the SAME calendar primitives `MasterSchedulePage`'s own date
// phase does ([MonthCalendar] + [CalendarWeekdayBar]) — it is the master/time
// coupling that differs, not the calendar grid itself.
//
// ## Masters-step data sources
//
// * Roster — [salonStaffMastersRosterProvider] (`salon/application/
//   salon_staff_masters_roster.dart`): the management `GET /salons/{id}/staff`
//   roster projected onto its masters. NOT the public `/masters` rail
//   ([salonMastersRosterProvider]), which lists only BOOKABLE masters — see
//   that file's header (2026-10-05).
// * Coverage (does master X perform this service) —
//   [salonMasterServiceCoverageProvider], the SAME family the CLIENT-facing
//   `SalonMasterSelectionScreen` already uses, called with a single-element
//   `selectedServiceIds` (it was already designed to take a list).
// * Slots — [salonMasterDaySlotsProvider], the SAME family
//   `MasterSchedulePage`'s time phase already uses, keyed per-master here
//   instead of per-visit.
//
// ## Deviation from the design's eager status pill / free-slots-first sort
//
// The design's demo data resolves EVERY master's free-slot count up front
// (`_MastersStepState._slotsFor`, pure in-memory math over fixture data) and
// sorts free-first / offers-first / fully-booked-last, with the pill reading
// "N слот(и/ів)" / "Зайнятий" / "Не виконує". This screen does not go that
// far — the status pill is never a live slot COUNT — but it IS eager about
// the binary has-slots-today/no-slots-today question (see the next
// paragraph): a real-device pass found the OLD lazy-only design let a
// master with genuinely zero free time on the picked day sit in the list
// looking identical to a bookable one until tapped, which read as broken
// rather than correct. Sort order is still COVERING-FIRST (roster order
// preserved within the covering group) — a master who does not perform
// EVERY selected service is not merely deprioritised, it is HIDDEN (see
// the next paragraph), so there is no "offers"/"does not offer" split left
// to sort by.
//
// ## HIDE non-covering, DISABLE covering-but-slotless (2026-09-18 real-
// device fixes)
//
// A master who fails the "every selected service" coverage rule
// (`_resolveOrderedAssignments` returning `null`) is no longer rendered at
// all — `SalonMastersStep` drops `nonCovering` entirely rather than
// appending it dimmed after `covering`. The "Виконує" pill is gone too: a
// covering, bookable tile carries no pill at all now (silence IS the
// affirmative state). What replaces both is a THIRD tile state this file
// did not previously distinguish: covering, but no free time left on the
// picked day (confirmed against the real backend — a master with a single
// 17:43→18:00 window left against a longer chained visit, a master who
// simply does not work the picked weekday, and a master with no
// `weekly_schedules` row at all all legitimately return `{"slots":[]}`).
// That state reuses [_SalonMasterTileState]'s existing per-element
// `_kDisabledDim` fade/pill machinery (previously the non-covering tile's
// only customer, now free for this) and [_SalonMasterStatusPill] (kept —
// still the vehicle for `bookingNoSlotsTitle`'s "Немає вільного часу"),
// and is now known EAGERLY: [_SalonMasterTileState.build] watches
// [salonMasterDaySlotsProvider] unconditionally for every covering tile,
// not only once the user expands it, so the disabled face — and the
// tile's own non-tappability — is visible without a tap. The fan-out this
// reintroduces is bounded by the ALREADY-filtered covering-master list
// (typically small for a salon roster), and Riverpod dedupes: the eager
// watch here and [_SalonTileSlotSection]'s own watch key on the identical
// [SalonMasterDaySlotsQuery], so expanding a tile never re-fetches. The
// "empty slot list renders the empty state, not a spinner" requirement
// from the previous design is still met structurally (the empty branch in
// [_SalonTileSlotSection] stays reachable for the narrow race of a tap
// landing before the eager fetch resolves), but the steady-state path a
// user actually sees is the collapsed disabled tile, not an expanded empty
// list.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/features/salon/application/salon_staff_masters_roster.dart';
import 'package:beautica_mobile/features/salon/domain/salon_master_summary.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/master/presentation/master_role_label.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:beautica_mobile/shared/formatters/duration_minutes.dart';
import 'package:beautica_mobile/shared/formatters/service_price_display.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';

import '../../application/salon_master_coverage_notifier.dart';
import '../../application/salon_booking_schedule_notifier.dart'
    show salonMasterDaySlotsProvider;
import '../../application/working_days_notifier.dart';
import '../../domain/booking_slot.dart';
import '../../domain/salon_booking_args.dart';
import '../../domain/salon_master_day_slots_query.dart';
import '../../domain/working_day.dart';
import '../../domain/working_days_query.dart';
import 'master_strip.dart' show MasterRatingReadout;
import 'month_calendar.dart';
import 'salon_avatar_gradients.dart';
import 'slot_chip.dart';

// ---------------------------------------------------------------------------
// Time-of-day bucketing — shared by the collapsed single-master body and
// every expanded tile's slot section.
// ---------------------------------------------------------------------------

/// Splits [slots] into morning (< 12) / afternoon (12–17) / evening (>= 17)
/// on the KYIV wall-clock hour — mirrors `MasterSchedulePage._bucketSlots`'
/// same derivation (`toBeauticaTime(...).hour`, never the raw UTC hour).
(List<BookingSlot>, List<BookingSlot>, List<BookingSlot>) _bucketSlots(
  List<BookingSlot> slots,
) {
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
  return (morning, afternoon, evening);
}

Widget _slotGroups(
  AppLocalizations l10n,
  List<BookingSlot> slots,
  BookingSlot? selected,
  ValueChanged<BookingSlot> onPick,
  String keyPrefix,
) {
  final (
    List<BookingSlot> morning,
    List<BookingSlot> afternoon,
    List<BookingSlot> evening,
  ) = _bucketSlots(
    slots,
  );

  Widget group(String label, List<BookingSlot> group) => SlotGroup(
    label: label,
    children: <Widget>[
      for (final BookingSlot s in group)
        SizedBox(
          width: 74,
          child: SlotChip(
            key: Key('$keyPrefix-${s.startAt.toIso8601String()}'),
            time: formatSlotTime(s.startAt),
            available: s.available,
            selected: selected == s,
            onTap: () => onPick(s),
          ),
        ),
    ],
  );

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      if (morning.isNotEmpty) ...<Widget>[
        group(l10n.bookingMorningLabel, morning),
        const SizedBox(height: VelvetSpacing.md),
      ],
      if (afternoon.isNotEmpty) ...<Widget>[
        group(l10n.bookingAfternoonLabel, afternoon),
        const SizedBox(height: VelvetSpacing.md),
      ],
      if (evening.isNotEmpty) group(l10n.bookingEveningLabel, evening),
    ],
  );
}

// ---------------------------------------------------------------------------
// SalonDateStep — the salon wizard's DATE-ONLY step. Time is chosen one step
// later, inside a master tile — see this file's header.
//
// 2026-09-18 — DAY-LEVEL GATING (fan-out + union). No master is picked yet
// here (that is the whole point of this step existing separately from
// `masters`), so there is no single `masterId` to key `workingDaysProvider`
// on the way `MasterSchedulePage`/`SlotDateScreen` do. Locked product
// decision: fan the query out across every COVERING master (the same
// "performs EVERY selected service" set `SalonMastersStep` computes via
// `_resolveOrderedAssignments`, reused verbatim below — it is already a
// top-level, file-private helper, so nothing needed promoting) and UNION
// their schedule-shape `working` flags — a day greys out only when NO
// covering master works it. `WorkingDaysQuery.month(...)` is called WITHOUT
// `serviceIds` deliberately (the schedule-shape mode, not the
// availability-aware duration-fit mode `MasterSchedulePage` uses one step
// later) — this is a coarser, cheaper signal by design. Accepted and
// explicitly NOT fixed: a day where a covering master works but is fully
// booked, or (today only) has too little time left for the visit's summed
// duration, still shows enabled here and is caught one step later by the
// masters step's existing "Немає вільного часу" disabled tile.
//
// FAIL OPEN (not closed): a day is only greyed once EVERY covering master's
// working-days fetch for the visible month has actually resolved (no
// loading, no error) AND none of them confirm `working: true` for that day.
// While any covering master's fetch is still in flight or errored, or before
// roster/coverage themselves have resolved, every future day stays tappable
// — exactly today's (pre-feature) behaviour. Zero covering masters (nobody
// performs the whole selected set) is treated the same way: this step never
// renders an all-grey month with no explanation — it stays fully tappable
// and the existing `SalonMastersStep` empty state (`_SalonMastersEmptyState`)
// explains the "no covering master" case one step later, where the copy
// already lives.
//
// CAPPED FAN-OUT (mobile-security MEDIUM fix, phase 341 audit) — the
// covering-master set is truncated to `_SalonDateStepState._kFetchChunkSize`
// (same value as `salonMasterServiceCoverageProvider`'s identically-named
// cap, reused rather than a second scheme) before it drives any
// `workingDaysProvider` watch, so an uncapped salon roster can no longer
// turn one mount into N authenticated calls. Exceeding the cap ALSO forces
// the union predicate open for every future day (see `_unionAvailability`'s
// `overCap`) — a truncated subset can prove "some master is free" but never
// "every covering master is off", so it must never gate on incomplete data.
// ---------------------------------------------------------------------------

/// mobile-perf LOW (phase 341 audit) — bumped once per genuine recompute of
/// [_SalonDateStepState]'s memoized covering-master-ids list, never on a
/// cache hit. Mirrors [debugResolveSalonMastersCallCount]'s identical
/// precedent (own doc above, in `SalonMastersStep`'s section).
@visibleForTesting
int debugCoveringMasterIdsCallCount = 0;

/// Resets [debugCoveringMasterIdsCallCount] to 0 — call at the top of a test
/// that asserts an exact recompute count.
@visibleForTesting
void debugResetCoveringMasterIdsCallCount() {
  debugCoveringMasterIdsCallCount = 0;
}

class SalonDateStep extends ConsumerStatefulWidget {
  const SalonDateStep({
    super.key,
    required this.salonId,
    required this.services,
    required this.selected,
    required this.onSelect,
  });

  final String salonId;

  /// The visit's selected services (1..n) — same list `SalonMastersStep`
  /// receives as `services`, reused here purely to resolve which masters
  /// COVER the whole set (see this class's header). Never sent over the
  /// wire from this step.
  final List<MasterService> services;

  final DateTime? selected;
  final ValueChanged<DateTime> onSelect;

  @override
  ConsumerState<SalonDateStep> createState() => _SalonDateStepState();
}

class _SalonDateStepState extends ConsumerState<SalonDateStep> {
  late DateTime _pagedMonth;
  bool _initialized = false;

  static const int _horizonMonths = 3;

  /// mobile-security MEDIUM (phase 341 audit) — ceiling on how many covering
  /// masters this step fans `workingDaysProvider` out to per mount/month
  /// change. Mirrors `salonMasterServiceCoverageProvider`'s `_kFetchChunkSize`
  /// (same value, same rationale: bounded fan-out over an uncapped roster —
  /// see that file's header) rather than inventing a second capping scheme.
  /// Unlike that provider's mechanism — which still reaches every selected
  /// service eventually, just in bounded-concurrency batches — this is a hard
  /// TRUNCATION: masters past the first [_kFetchChunkSize] (roster order,
  /// deterministic) are never queried at all, because there is no sequencing
  /// step here that could catch up to them (an eager per-build `ref.watch`
  /// fan-out, not an awaited batch loop). See [_unionAvailability]'s
  /// `overCap` parameter for what that means for the gate: it stays fail
  /// open (never greys a day) whenever the covering roster exceeds this
  /// ceiling, because greying requires confirming EVERY covering master is
  /// off, which a truncated subset can never assert.
  static const int _kFetchChunkSize = 8;

  /// Mirrors `MasterSchedulePage._dayKey`/`SlotPickerNotifier`'s identical
  /// private helper (both already duplicate this exact one-liner rather
  /// than share it — an established precedent in this file's sibling
  /// screens, not a new fork introduced here).
  static int _dayKey(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  // mobile-perf LOW (phase 341 audit) — memoized `_coveringMasterIds` result.
  // Keyed the SAME shape as `_SalonMastersStepState._resolveDerived` (own
  // doc there, reused verbatim): `listEquals` CONTENT-equality on the
  // ordered service ids (the caller mutates its selected-services list IN
  // PLACE, so an `identical()` check on the list itself would report a
  // stale HIT — `project_freezed_getter_defeats_identical_memo`) plus
  // `identical()` on `roster`/`coverage` (safe — both are replaced, never
  // mutated, by Riverpod's cached `AsyncValue.value` on refetch).
  List<String>? _cachedServiceDefIds;
  List<SalonMasterSummary>? _cachedRoster;
  Map<String, Map<String, String>>? _cachedCoverage;
  List<String>? _cachedCoveringIds;

  /// The masters who cover EVERY service in [ordered] — same "every, not
  /// any" rule `SalonMastersStep._resolveDerived` applies, reusing the SAME
  /// `_resolveOrderedAssignments` helper (file-private, already shared by
  /// both steps). Returns `null` (not just an empty list) when roster or
  /// coverage has not resolved yet, so the caller can distinguish
  /// "not known yet" (fail open) from "known: zero masters cover this set"
  /// (also fail open, per this class's header, but a distinct case worth
  /// keeping separate at the call site).
  List<String>? _coveringMasterIds(
    List<MasterService> ordered,
    List<SalonMasterSummary>? roster,
    Map<String, Map<String, String>>? coverage,
  ) {
    if (roster == null || coverage == null) return null;

    final List<String> serviceDefIds = <String>[
      for (final MasterService s in ordered) s.serviceDefId,
    ];
    final bool hit =
        _cachedCoveringIds != null &&
        listEquals(_cachedServiceDefIds, serviceDefIds) &&
        identical(_cachedRoster, roster) &&
        identical(_cachedCoverage, coverage);
    if (hit) return _cachedCoveringIds!;

    debugCoveringMasterIdsCallCount++;
    final List<String> result = <String>[
      for (final SalonMasterSummary m in roster)
        if (_resolveOrderedAssignments(coverage[m.masterId], ordered) != null)
          m.masterId,
    ];

    _cachedServiceDefIds = serviceDefIds;
    _cachedRoster = roster;
    _cachedCoverage = coverage;
    _cachedCoveringIds = result;
    return result;
  }

  /// Builds the union `isAvailable` predicate for [visibleMonth] from
  /// [workingDaysByMaster] (one [workingDaysProvider] watch per covering
  /// master, already capped to [_kFetchChunkSize] by the caller — see this
  /// class's header for the fail-open contract). [overCap] is true whenever
  /// the covering roster EXCEEDED that ceiling before truncation — see
  /// [_kFetchChunkSize]'s doc for why that forces every future day to stay
  /// tappable regardless of what the capped subset reports.
  bool Function(DateTime) _unionAvailability(
    Map<String, AsyncValue<List<WorkingDay>>> workingDaysByMaster,
    DateTime today, {
    required bool overCap,
  }) {
    final List<Map<int, bool>> resolvedByMaster = <Map<int, bool>>[];
    bool allResolved = true;
    for (final AsyncValue<List<WorkingDay>> async
        in workingDaysByMaster.values) {
      final List<WorkingDay>? days = async.value;
      if (async.hasError || days == null) {
        // Loading OR errored: this master contributes nothing to the union
        // AND must never cause a grey day on its own (fail open).
        allResolved = false;
        continue;
      }
      resolvedByMaster.add(<int, bool>{
        for (final WorkingDay w in days) _dayKey(w.date): w.working,
      });
    }
    return (DateTime day) {
      if (day.isBefore(today)) return false;
      if (overCap) return true; // truncated subset can never confirm ALL off
      if (workingDaysByMaster.isEmpty) return true; // no covering master yet
      final int key = _dayKey(day);
      for (final Map<int, bool> byDay in resolvedByMaster) {
        if (byDay[key] == true) return true; // UNION: any master works it
      }
      // No covering master CONFIRMED working this day. Only grey out once
      // every one of them has actually resolved — otherwise fail open.
      return !allResolved;
    };
  }

  DateTime _firstMonth(DateTime today) => DateTime(today.year, today.month, 1);

  DateTime _lastMonth(DateTime today) =>
      DateTime(today.year, today.month + _horizonMonths, 1);

  DateTime _visibleMonth(DateTime today) {
    final DateTime first = _firstMonth(today);
    return _pagedMonth.isBefore(first) ? first : _pagedMonth;
  }

  void _prevMonth(DateTime today) {
    final DateTime visible = _visibleMonth(today);
    if (!visible.isAfter(_firstMonth(today))) return;
    setState(() => _pagedMonth = DateTime(visible.year, visible.month - 1, 1));
  }

  void _nextMonth(DateTime today) {
    final DateTime visible = _visibleMonth(today);
    if (!visible.isBefore(_lastMonth(today))) return;
    setState(() => _pagedMonth = DateTime(visible.year, visible.month + 1, 1));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Kyiv-anchored "today", re-derived every build — mirrors
    // `MasterSchedulePage._today`'s own rationale (never captured once in
    // `initState`, so a build straddling Kyiv midnight stays internally
    // consistent).
    final DateTime today = kyivToday(ref.read(clockProvider));
    if (!_initialized) {
      _pagedMonth = _firstMonth(today);
      _initialized = true;
    }
    final DateTime visibleMonth = _visibleMonth(today);

    // Single normalisation point — mirrors `SalonMastersStep.build()`.
    final List<MasterService> ordered = widget.services;
    final AsyncValue<List<SalonMasterSummary>> rosterAsync = ref.watch(
      salonStaffMastersRosterProvider(widget.salonId),
    );
    final SalonBookingMasterSelectionArgs coverageArgs =
        SalonBookingMasterSelectionArgs(
          salonId: widget.salonId,
          selectedServiceIds: <String>[
            for (final MasterService s in ordered) s.serviceDefId,
          ],
        );
    final AsyncValue<SalonCoverage> coverageAsync = ref.watch(
      salonMasterServiceCoverageProvider(coverageArgs),
    );

    // FAIL OPEN (class header): a roster/coverage error or in-flight fetch
    // resolves `covering` to `null`, which `_unionAvailability` (via an
    // empty `workingDaysByMaster` map below) treats identically to "zero
    // covering masters" — every future day stays tappable, no error surface
    // blocks the calendar the way `SalonMastersStep`'s `ErrorState` does one
    // step later (this step has nothing actionable to retry from yet; the
    // masters step re-fetches the SAME providers right after). Phase 266 —
    // `.byMaster` only: a degraded service still resolves `covering` exactly
    // as it did before that phase (absent from every master's row), and
    // `degradedServiceIds` has no retry surface on THIS step — see the phase
    // doc's consumer table.
    final List<String>? covering = _coveringMasterIds(
      ordered,
      rosterAsync.value,
      coverageAsync.value?.byMaster,
    );

    // Requirement 4 — N requests, keyed per (masterId, visible month): one
    // `workingDaysProvider` family watch per covering master, re-keyed
    // automatically whenever `visibleMonth` changes (a new
    // `WorkingDaysQuery` instance, normalised-equal across re-renders of the
    // SAME month so chevron re-taps on a month already fetched reuse the
    // cached family member instead of refetching).
    //
    // mobile-security MEDIUM (phase 341 audit) — capped at
    // [_kFetchChunkSize]: an uncapped salon roster used to turn one mount
    // into N authenticated calls. See [_kFetchChunkSize]'s doc for why
    // masters past the cap are truncated (not batched) and what that implies
    // for the gate below.
    final List<String> coveringIds = covering ?? const <String>[];
    final bool overCap = coveringIds.length > _kFetchChunkSize;
    final List<String> cappedCoveringIds = overCap
        ? coveringIds.sublist(0, _kFetchChunkSize)
        : coveringIds;
    final Map<String, AsyncValue<List<WorkingDay>>> workingDaysByMaster =
        <String, AsyncValue<List<WorkingDay>>>{
          for (final String masterId in cappedCoveringIds)
            masterId: ref.watch(
              workingDaysProvider(
                WorkingDaysQuery.month(
                  masterId: masterId,
                  anyDayInMonth: visibleMonth,
                ),
              ),
            ),
        };
    final bool Function(DateTime) isAvailable = _unionAvailability(
      workingDaysByMaster,
      today,
      overCap: overCap,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        VelvetSpacing.lg,
        VelvetSpacing.sm,
        VelvetSpacing.lg,
        VelvetSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            l10n.salonCreateBookingDateHeading,
            style: VelvetText.subheadingWizard15,
          ),
          const SizedBox(height: VelvetSpacing.md),
          // 2026-09-18 real-device fix — `CalendarWeekdayBar` used to sit
          // here as [SalonDateStep]'s OWN sibling, ahead of `MonthCalendar`'s
          // own header (chevrons + month/year), so the heading→calendar gap
          // was really `md` + the weekday row's 20dp + another `xs`, with the
          // weekday LABELS landing above the month header instead of
          // directly over the grid they describe. `composeWeekdayBar: true`
          // (an existing additive opt-in on [MonthCalendar], previously used
          // only by `BookingsMonthCalendarPanel`) folds the SAME
          // `CalendarWeekdayBar` inside `MonthCalendar`, after its header —
          // collapsing this step back to the approved design's single `md`
          // gap between the heading and ONE cohesive calendar block
          // (`docs/signup-designs/SalonManagementDesign/lib/screens/
          // create_booking_screen.dart:644-660`'s `_DateTimeStep`, whose
          // `_MiniCalendar` bundles its own weekday row the same way).
          MonthCalendar(
            key: const Key('salon-create-booking-date-calendar'),
            visibleMonth: visibleMonth,
            today: today,
            selected: widget.selected,
            isAvailable: isAvailable,
            onSelectDay: widget.onSelect,
            onPrevMonth: visibleMonth.isAfter(_firstMonth(today))
                ? () => _prevMonth(today)
                : null,
            onNextMonth: visibleMonth.isBefore(_lastMonth(today))
                ? () => _nextMonth(today)
                : null,
            composeWeekdayBar: true,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SalonMastersStep — per-master expandable slot pickers. The COLLAPSE RULE
// (locked, keyed on roster COUNT, never on caller role) lives here.
// ---------------------------------------------------------------------------

/// mobile-perf LOW (phase 335 diff) — bumped once per genuine recompute of
/// [_SalonMastersStepState]'s memoized `(resolved, covering, nonCovering)`
/// triple, never on a cache hit. Mirrors `master_archive_screen.dart`'s
/// `debugGroupArchiveByKyivDayCallCount` precedent; an int increment is
/// negligible cost so this stays live in every build config.
@visibleForTesting
int debugResolveSalonMastersCallCount = 0;

/// Resets [debugResolveSalonMastersCallCount] to 0 — call at the top of a
/// test that asserts an exact recompute count.
@visibleForTesting
void debugResetResolveSalonMastersCallCount() {
  debugResolveSalonMastersCallCount = 0;
}

class SalonMastersStep extends ConsumerStatefulWidget {
  const SalonMastersStep({
    super.key,
    required this.salonId,
    this.service,
    this.services,
    required this.date,
    required this.onPick,
  }) : assert(
         (service == null) != (services == null),
         'SalonMastersStep needs exactly one of service (legacy single) or '
         'services (Phase 335 ordered multi) — never both, never neither.',
       );

  final String salonId;

  /// Legacy single-service path. `null` when [services] is provided instead
  /// — see this constructor's assert and [services]' own doc.
  final MasterService? service;

  /// PHASE 335 — the visit's full ordered service selection (1..n). `null`
  /// preserves the pre-335 single-service behaviour exactly (every call site
  /// until this phase passed [service] alone). When non-null, this wins and
  /// [service] is ignored. `.serviceDefId` is the id the coverage query keys
  /// on (see `salonServiceForShelf`'s own doc: `id`/`serviceDefId` both carry
  /// the salon-catalog id for a salon-sourced [MasterService]).
  final List<MasterService>? services;

  /// Date-only.
  final DateTime date;

  /// Fires once a slot is picked — [List]`<String>` is the chosen master's
  /// OWN per-master `MasterServiceAssignment` id for EVERY selected service,
  /// ordered index-for-index with the selection — the exact list
  /// `CreateMasterBookingRequest.masterServiceIds` needs — NEVER
  /// `service.id`/`service.serviceDefId` (the salon-catalog id; see
  /// `salon_master_schedule.dart`'s "ID-SPACE NOTE" for why the two id
  /// spaces must never be conflated).
  final void Function(
    SalonMasterSummary master,
    List<String> assignmentIds,
    BookingSlot slot,
  )
  onPick;

  @override
  ConsumerState<SalonMastersStep> createState() => _SalonMastersStepState();
}

class _SalonMastersStepState extends ConsumerState<SalonMastersStep> {
  // mobile-perf LOW (phase 335 diff) — memoized `(resolved, covering,
  // nonCovering)` triple. Re-derived only when the selected-service order OR
  // the roster/coverage data actually changed, instead of on every build
  // (a sibling step ticking a provider used to re-run all three
  // comprehensions for nothing).
  //
  // Cache key is CONTENT for the service list, not identity: the caller
  // (`salon_create_booking_screen.dart`) holds `_selectedServices` as ONE
  // `final List<MasterService>` mutated IN PLACE via `.add`/`.removeWhere`,
  // so `widget.services` keeps the SAME list identity across an add/remove —
  // an `identical()` check here would report a cache HIT for stale data.
  // Same trap as `project_freezed_getter_defeats_identical_memo`: identity
  // survives a content change. `roster`/`coverage` are safe on identity —
  // they come straight from Riverpod's cached `AsyncValue.value` and are
  // replaced, never mutated, on refetch.
  List<String>? _cachedServiceDefIds;
  List<SalonMasterSummary>? _cachedRoster;
  Map<String, Map<String, String>>? _cachedCoverage;
  List<(SalonMasterSummary, List<String>?)>? _cachedResolved;
  List<(SalonMasterSummary, List<String>?)>? _cachedCovering;
  List<(SalonMasterSummary, List<String>?)>? _cachedNonCovering;

  (
    List<(SalonMasterSummary, List<String>?)>,
    List<(SalonMasterSummary, List<String>?)>,
    List<(SalonMasterSummary, List<String>?)>,
  )
  _resolveDerived(
    List<MasterService> ordered,
    List<SalonMasterSummary> roster,
    Map<String, Map<String, String>> coverage,
  ) {
    final List<String> serviceDefIds = <String>[
      for (final MasterService s in ordered) s.serviceDefId,
    ];
    final bool hit =
        _cachedResolved != null &&
        listEquals(_cachedServiceDefIds, serviceDefIds) &&
        identical(_cachedRoster, roster) &&
        identical(_cachedCoverage, coverage);
    if (hit) {
      return (_cachedResolved!, _cachedCovering!, _cachedNonCovering!);
    }

    debugResolveSalonMastersCallCount++;
    // D2 — "every", not "any": a master is bookable only if they cover
    // EVERY selected service — one master performs the whole visit
    // (`project_salon_scheduling_is_per_master`), so a master covering a
    // strict subset is non-covering, not a partial candidate.
    final List<(SalonMasterSummary, List<String>?)> resolved =
        <(SalonMasterSummary, List<String>?)>[
          for (final SalonMasterSummary m in roster)
            (m, _resolveOrderedAssignments(coverage[m.masterId], ordered)),
        ];
    final List<(SalonMasterSummary, List<String>?)> covering =
        <(SalonMasterSummary, List<String>?)>[
          for (final (SalonMasterSummary, List<String>?) r in resolved)
            if (r.$2 != null) r,
        ];
    final List<(SalonMasterSummary, List<String>?)> nonCovering =
        <(SalonMasterSummary, List<String>?)>[
          for (final (SalonMasterSummary, List<String>?) r in resolved)
            if (r.$2 == null) r,
        ];

    _cachedServiceDefIds = serviceDefIds;
    _cachedRoster = roster;
    _cachedCoverage = coverage;
    _cachedResolved = resolved;
    _cachedCovering = covering;
    _cachedNonCovering = nonCovering;
    return (resolved, covering, nonCovering);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Single normalisation point (mirrors `ConfirmStep`/`DateTimeStep`) —
    // every use below reads `ordered`, never `service`/`services` directly.
    final List<MasterService> ordered =
        widget.services ?? <MasterService>[widget.service!];

    final AsyncValue<List<SalonMasterSummary>> rosterAsync = ref.watch(
      salonStaffMastersRosterProvider(widget.salonId),
    );
    final SalonBookingMasterSelectionArgs coverageArgs =
        SalonBookingMasterSelectionArgs(
          salonId: widget.salonId,
          selectedServiceIds: <String>[
            for (final MasterService s in ordered) s.serviceDefId,
          ],
        );
    final AsyncValue<SalonCoverage> coverageAsync = ref.watch(
      salonMasterServiceCoverageProvider(coverageArgs),
    );

    final Object? error = rosterAsync.error ?? coverageAsync.error;
    if (error != null) {
      return ErrorState(
        key: const Key('salon-create-booking-masters-error'),
        failure: error is Failure ? error : UnknownFailure(cause: error),
        onRetry: () {
          ref.invalidate(salonStaffMastersRosterProvider(widget.salonId));
          ref.invalidate(salonMasterServiceCoverageProvider(coverageArgs));
        },
      );
    }

    final List<SalonMasterSummary>? roster = rosterAsync.value;
    // Phase 266 — `.byMaster` only; this step has no per-service retry UI
    // (D5 scopes that to `SalonMasterSelectionScreen` alone), so a degraded
    // service renders here exactly as it did before that phase: absent from
    // every master's coverage row, same as a genuine "nobody covers it".
    final Map<String, Map<String, String>>? coverage =
        coverageAsync.value?.byMaster;
    if (roster == null || coverage == null) {
      return const Center(
        key: ValueKey<String>('salon-create-booking-masters-loading'),
        child: CircularProgressIndicator(color: BrandColors.accent),
      );
    }

    final (
      List<(SalonMasterSummary, List<String>?)> resolved,
      List<(SalonMasterSummary, List<String>?)> covering,
      List<(SalonMasterSummary, List<String>?)> _,
    ) = _resolveDerived(
      ordered,
      roster,
      coverage,
    );

    if (covering.isEmpty) {
      // D3 — the singular ("this one service") and plural ("this whole set
      // of services") empty states genuinely mean different things; a
      // one-service salon must not read the plural framing.
      final bool multi = ordered.length > 1;
      return _SalonMastersEmptyState(
        key: const Key('salon-create-booking-no-covering-master'),
        title: multi
            ? l10n.salonBookingNoCoveringMasterTitle
            : l10n.salonBookingNoCoveringMasterSingularTitle,
        hint: multi
            ? l10n.salonBookingNoCoveringMasterHint
            : l10n.salonBookingNoCoveringMasterSingularHint,
      );
    }

    // COLLAPSE RULE (locked) — a salon with exactly one active master gets
    // the same treatment an independent master's own calendar would: no
    // one-row picker, just the slot grid. Keyed on ROSTER count, never on
    // the caller's role. Only its assignmentIds argument became plural.
    if (roster.length == 1) {
      final (SalonMasterSummary soleMaster, List<String>? soleAssignments) =
          resolved.single;
      // Guaranteed non-null: `covering` is non-empty and roster has exactly
      // one entry, so that one entry IS the covering one.
      final List<String> assignmentIds = soleAssignments!;
      return _SalonCollapsedSlots(
        key: const Key('salon-create-booking-masters-collapsed'),
        masterId: soleMaster.masterId,
        assignmentIds: assignmentIds,
        date: widget.date,
        onPick: (BookingSlot slot) =>
            widget.onPick(soleMaster, assignmentIds, slot),
      );
    }

    // 2026-09-18 real-device fix — a master who does not cover EVERY
    // selected service used to render here too, dimmed. The user asked for
    // it gone outright: `covering` alone, roster order preserved, no
    // dimmed tail — see this file's header.
    final List<(SalonMasterSummary, List<String>?)> orderedMasters = covering;

    return ListView.separated(
      key: const Key('salon-create-booking-masters-list'),
      padding: const EdgeInsets.fromLTRB(
        VelvetSpacing.lg,
        VelvetSpacing.sm,
        VelvetSpacing.lg,
        VelvetSpacing.xxl,
      ),
      itemCount: orderedMasters.length,
      separatorBuilder: (BuildContext context, int i) =>
          const SizedBox(height: VelvetSpacing.sm),
      itemBuilder: (BuildContext context, int i) {
        final (SalonMasterSummary m, List<String>? assignmentIds) =
            orderedMasters[i];
        return _SalonMasterTile(
          key: Key('salon-master-tile-${m.masterId}'),
          index: i,
          master: m,
          services: ordered,
          assignmentIds: assignmentIds,
          date: widget.date,
          onSlotPick: assignmentIds == null
              ? null
              : (BookingSlot slot) => widget.onPick(m, assignmentIds, slot),
        );
      },
    );
  }
}

/// Resolves [row]'s (a master's `serviceDefId -> assignmentId` coverage map)
/// assignment id for EVERY service in [ordered], in the SAME order — or
/// `null` the moment any one of [ordered] is missing from [row] (D2: "every",
/// not "any"). Non-null values are safe to `!` at every call site because a
/// master only reaches [SalonMastersStep]'s `covering` list when this
/// returned non-null.
List<String>? _resolveOrderedAssignments(
  Map<String, String>? row,
  List<MasterService> ordered,
) {
  if (row == null) return null;
  final List<String> ids = <String>[];
  for (final MasterService s in ordered) {
    final String? id = row[s.serviceDefId];
    if (id == null) return null;
    ids.add(id);
  }
  return ids;
}

class _SalonMastersEmptyState extends StatelessWidget {
  const _SalonMastersEmptyState({
    super.key,
    required this.title,
    required this.hint,
  });

  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(VelvetSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.person_search_outlined,
              size: 36,
              color: BrandColors.accent,
            ),
            const SizedBox(height: VelvetSpacing.md),
            Text(
              title,
              style: VelvetText.headingSm,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: VelvetSpacing.sm),
            Text(hint, style: VelvetText.body(), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// The one-active-master collapsed body — just the slot grid, no tile chrome
/// (the collapse rule's whole point).
class _SalonCollapsedSlots extends ConsumerWidget {
  const _SalonCollapsedSlots({
    super.key,
    required this.masterId,
    required this.assignmentIds,
    required this.date,
    required this.onPick,
  });

  final String masterId;

  /// Every selected service's assignment id for this master, in tap order —
  /// see `SalonMastersStep.onPick`'s own doc.
  final List<String> assignmentIds;
  final DateTime date;
  final ValueChanged<BookingSlot> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final AsyncValue<List<BookingSlot>> slotsAsync = ref.watch(
      salonMasterDaySlotsProvider(
        SalonMasterDaySlotsQuery(
          masterId: masterId,
          serviceIds: assignmentIds,
          date: date,
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        VelvetSpacing.lg,
        VelvetSpacing.sm,
        VelvetSpacing.lg,
        VelvetSpacing.xxl,
      ),
      child: slotsAsync.when(
        loading: () => const Center(
          key: ValueKey<String>('salon-create-booking-collapsed-loading'),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: VelvetSpacing.xl),
            child: CircularProgressIndicator(color: BrandColors.accent),
          ),
        ),
        error: (Object e, StackTrace _) => ErrorState(
          key: const Key('salon-create-booking-collapsed-error'),
          failure: e is Failure ? e : UnknownFailure(cause: e),
          onRetry: () => ref.invalidate(
            salonMasterDaySlotsProvider(
              SalonMasterDaySlotsQuery(
                masterId: masterId,
                serviceIds: assignmentIds,
                date: date,
              ),
            ),
          ),
        ),
        data: (List<BookingSlot> slots) {
          if (slots.isEmpty) {
            return Center(
              key: const ValueKey<String>(
                'salon-create-booking-collapsed-empty',
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: VelvetSpacing.xl),
                child: Text(
                  l10n.bookingNoSlotsTitle,
                  style: VelvetText.bodyStrong(),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return _slotGroups(
            l10n,
            slots,
            null,
            onPick,
            'salon-collapsed-slot-chip',
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _SalonMasterTile — one master row in the multi-master picker.
// ---------------------------------------------------------------------------

class _SalonMasterTile extends ConsumerStatefulWidget {
  const _SalonMasterTile({
    super.key,
    required this.index,
    required this.master,
    required this.services,
    required this.assignmentIds,
    required this.date,
    required this.onSlotPick,
  });

  final int index;
  final SalonMasterSummary master;

  /// The visit's full ordered service selection (1..n) — see
  /// `SalonMastersStep.services`' own doc.
  final List<MasterService> services;

  /// `null` when this master does NOT cover EVERY service in [services] —
  /// 2026-09-18: `SalonMastersStep` now filters these out before ever
  /// constructing a tile, so this stays `null` only defensively; no live
  /// caller passes it. Non-null carries one assignment id per [services]
  /// entry, index-aligned.
  final List<String>? assignmentIds;
  final DateTime date;
  final ValueChanged<BookingSlot>? onSlotPick;

  @override
  ConsumerState<_SalonMasterTile> createState() => _SalonMasterTileState();
}

class _SalonMasterTileState extends ConsumerState<_SalonMasterTile> {
  bool _expanded = false;

  /// Set at the top of every [build] — see [_hasNoFreeTime]'s own doc for
  /// why this can't just be a getter.
  bool _hasNoFreeTime = false;

  bool get _offers => widget.assignmentIds != null;

  /// Alpha multiplier for a disabled tile's whole face — same value the
  /// tile previously wrapped in `Opacity(opacity: 0.42, ...)` (mobile-perf
  /// P1, Phase 250): that subtree `Opacity` forced a `saveLayer` per faded
  /// tile on screen (avatar, name, role, rating, pill — every painted
  /// layer). Every color below is faded individually instead so no
  /// `saveLayer` is needed. See `test/golden/salon_master_tile_golden_test
  /// .dart` for the before/after equivalence check.
  ///
  /// 2026-09-18: this used to gate on [_offers] (a non-covering master's
  /// face). Non-covering masters are hidden outright now (never reach this
  /// widget — see [_SalonMasterTile.assignmentIds]'s doc), which freed this
  /// dim treatment for the tile state that replaced it: a COVERING master
  /// with no free time left on the picked day.
  static const double _kDisabledDim = 0.42;

  /// Multiplies [color]'s own alpha by [_kDisabledDim] when this tile has no
  /// free time; returns [color] unchanged otherwise. Composable with a color
  /// that already carries its own alpha (e.g. the avatar icon's `0.85`) —
  /// the two multiply together, same as they would inside a group
  /// `Opacity`.
  Color _fade(Color color) =>
      _hasNoFreeTime ? color.withValues(alpha: color.a * _kDisabledDim) : color;

  /// Maps [_fade] over every shadow's color, preserving offset/blur/spread.
  List<BoxShadow> _fadeShadows(List<BoxShadow> shadows) => <BoxShadow>[
    for (final BoxShadow s in shadows)
      BoxShadow(
        color: _fade(s.color),
        offset: s.offset,
        blurRadius: s.blurRadius,
        spreadRadius: s.spreadRadius,
      ),
  ];

  void _toggle() {
    if (!_offers || _hasNoFreeTime) return;
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final SalonMasterSummary m = widget.master;
    final String name = '${m.firstName} ${m.lastName}'.trim();
    final String? ownTitle = m.professionalTitle?.trim();
    final String role = (ownTitle != null && ownTitle.isNotEmpty)
        ? ownTitle
        : masterRoleLabel(m.type, l10n);
    final double? rating = m.reviewCount > 0 ? m.avgRating : null;
    final String ratingLabel = rating?.toStringAsFixed(1) ?? '—';

    // 2026-09-18 real-device fix — eager, not lazy-on-expand: watched
    // unconditionally so a covering master with genuinely zero free time
    // today renders disabled from the first frame, never only after a tap.
    // Same [SalonMasterDaySlotsQuery] value [_SalonTileSlotSection] builds
    // below, so Riverpod dedupes the two watches to ONE fetch — expanding
    // never re-queries. Loading/error both read as "unknown, not yet
    // disabled" (`valueOrNull` is `null` in both), matching the tile's
    // pre-existing default (tappable) face until proven otherwise.
    final List<BookingSlot>? loadedSlots = _offers
        ? ref
              .watch(
                salonMasterDaySlotsProvider(
                  SalonMasterDaySlotsQuery(
                    masterId: m.masterId,
                    serviceIds: widget.assignmentIds!,
                    date: widget.date,
                  ),
                ),
              )
              .value
        : null;
    _hasNoFreeTime = _offers && loadedSlots != null && loadedSlots.isEmpty;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: BrandColors.base,
        borderRadius: BorderRadius.circular(VelvetRadii.card),
        border: Border.all(
          color: _fade(
            _expanded
                ? BrandColors.accent
                : _hasNoFreeTime
                ? BrandColors.faint
                : BrandColors.accent.withValues(alpha: 0.18),
          ),
          width: _expanded ? 1.5 : 1,
        ),
        boxShadow: _hasNoFreeTime ? null : VelvetShadows.extrudedSmall,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Semantics(
            button: _offers && !_hasNoFreeTime,
            enabled: _offers && !_hasNoFreeTime,
            label: l10n.salonMasterCardSemanticLabel(name, role, ratingLabel),
            child: ExcludeSemantics(
              child: GestureDetector(
                onTap: _toggle,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(VelvetSpacing.md),
                  child: Row(
                    children: <Widget>[
                      Container(
                        height: 48,
                        width: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: <Color>[
                              for (final Color c in salonAvatarGradient(
                                widget.index,
                              ))
                                _fade(c),
                            ],
                          ),
                          boxShadow: _fadeShadows(VelvetShadows.extrudedSmall),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.person_rounded,
                            color: _fade(
                              BrandColors.white.withValues(alpha: 0.85),
                            ),
                            size: 24,
                          ),
                        ),
                      ),
                      const SizedBox(width: VelvetSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              name,
                              // Already 14 sp — matches the design's own
                              // sizing for this row exactly, so no extra
                              // size override is needed here.
                              style: VelvetText.subheading().copyWith(
                                color: _fade(BrandColors.text),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              role,
                              style: VelvetText.feedbackMutedSm.copyWith(
                                color: _fade(BrandColors.muted),
                              ),
                            ),
                            // D6 — no duration/price ARITHMETIC in this
                            // step: for a single-service visit this line
                            // shows that one service's own duration/price
                            // (unchanged rendering, no summing involved). A
                            // multi-service visit has no single number to
                            // show here without summing — rather than
                            // render a partial/misleading figure, the line
                            // is omitted; Σ-duration/price belong to
                            // `confirm`, fed by the backend's own totals.
                            if (_offers &&
                                widget.services.length == 1) ...<Widget>[
                              const SizedBox(height: 3),
                              Text(
                                '${DurationMinutes.format(widget.services.single.durationMinutes)} '
                                '· ${ServicePriceDisplay.format(widget.services.single)}',
                                style: VelvetText.feedbackAccentSm.copyWith(
                                  color: _fade(BrandColors.accentDeep),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: VelvetSpacing.sm),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          if (m.reviewCount > 0)
                            MasterRatingReadout(
                              avgRating: rating,
                              reviewCount: m.reviewCount,
                              opacity: _hasNoFreeTime ? _kDisabledDim : 1.0,
                            ),
                          // 2026-09-18 real-device fix — the affirmative
                          // "covers, has free time" state carries NO pill at
                          // all now (silence IS the affirmative signal; the
                          // old «Виконує» pill is gone). Only the disabled
                          // "covers, but nothing free today" state still
                          // needs one, reusing `bookingNoSlotsTitle`'s
                          // «Немає вільного часу» — the SAME copy the
                          // expanded slot section already shows for this
                          // exact condition (`_SalonTileSlotSection`'s
                          // `data` branch below) — rather than minting a
                          // near-duplicate key.
                          if (_hasNoFreeTime) ...<Widget>[
                            if (m.reviewCount > 0) const SizedBox(height: 5),
                            _SalonMasterStatusPill(
                              label: l10n.bookingNoSlotsTitle,
                              color: BrandColors.textSecondary,
                              opacity: _kDisabledDim,
                            ),
                          ],
                        ],
                      ),
                      if (_offers && !_hasNoFreeTime) ...<Widget>[
                        const SizedBox(width: VelvetSpacing.xs + 2),
                        AnimatedRotation(
                          turns: _expanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 220),
                          child: const Icon(
                            Icons.expand_more_rounded,
                            size: 22,
                            color: BrandColors.accent,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(VelvetRadii.card - 1),
            ),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 230),
              curve: Curves.easeOutCubic,
              child: _expanded
                  ? _SalonTileSlotSection(
                      masterId: m.masterId,
                      assignmentIds: widget.assignmentIds!,
                      date: widget.date,
                      onPick: widget.onSlotPick!,
                    )
                  : const SizedBox(width: double.infinity, height: 0),
            ),
          ),
        ],
      ),
    );
  }
}

class _SalonMasterStatusPill extends StatelessWidget {
  const _SalonMasterStatusPill({
    required this.label,
    required this.color,
    this.opacity = 1.0,
  });

  final String label;
  final Color color;

  /// Alpha multiplier for the whole pill (background fill + label) — 1.0
  /// (default) renders identically to before this param existed. Lets
  /// `_SalonMasterTile` dim a disabled (no-free-time) master's pill without
  /// wrapping it (or any wider ancestor) in `Opacity`.
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final Color textColor = opacity == 1.0
        ? color
        : color.withValues(alpha: color.a * opacity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14 * opacity),
        borderRadius: BorderRadius.circular(VelvetRadii.pill),
      ),
      child: Text(label, style: VelvetText.feedback(textColor)),
    );
  }
}

/// The expanded tile's own lazily-fetched slot section — see this file's
/// header for why this fetches on first expand rather than eagerly.
class _SalonTileSlotSection extends ConsumerWidget {
  const _SalonTileSlotSection({
    required this.masterId,
    required this.assignmentIds,
    required this.date,
    required this.onPick,
  });

  final String masterId;

  /// Every selected service's assignment id for this master, in tap order —
  /// see `SalonMastersStep.onPick`'s own doc.
  final List<String> assignmentIds;
  final DateTime date;
  final ValueChanged<BookingSlot> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final SalonMasterDaySlotsQuery query = SalonMasterDaySlotsQuery(
      masterId: masterId,
      serviceIds: assignmentIds,
      date: date,
    );
    final AsyncValue<List<BookingSlot>> slotsAsync = ref.watch(
      salonMasterDaySlotsProvider(query),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: BrandColors.accent.withValues(alpha: 0.15)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(VelvetSpacing.md),
        child: slotsAsync.when(
          loading: () => const Center(
            key: ValueKey<String>('salon-master-tile-slots-loading'),
            child: SizedBox(
              height: 28,
              width: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: BrandColors.accent,
              ),
            ),
          ),
          error: (Object e, StackTrace _) => ErrorState(
            key: const Key('salon-master-tile-slots-error'),
            failure: e is Failure ? e : UnknownFailure(cause: e),
            onRetry: () => ref.invalidate(salonMasterDaySlotsProvider(query)),
          ),
          data: (List<BookingSlot> slots) {
            if (slots.isEmpty) {
              return Center(
                key: const ValueKey<String>('salon-master-tile-slots-empty'),
                child: Text(
                  l10n.bookingNoSlotsTitle,
                  style: VelvetText.bodyStrong(),
                  textAlign: TextAlign.center,
                ),
              );
            }
            return _slotGroups(
              l10n,
              slots,
              null,
              onPick,
              'salon-tile-slot-chip-$masterId',
            );
          },
        ),
      ),
    );
  }
}
