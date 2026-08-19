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
// * Roster — [salonMastersRosterProvider] (`salon_masters_roster_notifier
//   .dart`), NOT [publicSalonProfileProvider] — see that file's header for
//   why the public-profile bundle is the wrong source for a staff caller.
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
// "N слот(и/ів)" / "Зайнятий" / "Не виконує". Doing the same against the
// REAL slot endpoint would mean fetching every covering master's day slots
// the instant the masters step mounts — an eager N-way fan-out with no
// existing bound (unlike `salonMasterServiceCoverageProvider`'s own
// deliberate `_kFetchChunkSize` cap for a comparable fan-out). This screen
// instead fetches a master's slots LAZILY, on first expand
// ([_SalonMasterTileState._expanded]), and the status pill is a plain
// two-state "Виконує" / "Не виконує" (offers the service or not) rather than
// a live slot count. Sort order is COVERING-FIRST (roster order preserved
// within each group), not further split by slot availability. The "empty
// slot list renders the empty state, not a spinner" requirement is still
// met — it fires once a tile's own lazy fetch resolves empty — and the
// zero-covering-master case still shows the informational empty state, just
// without the day-specific "спробуйте інший день" framing (folded into the
// existing `salonBookingNoCoveringMasterTitle`/`Hint` copy, reused verbatim
// rather than adding a near-duplicate pair of keys).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/salon/domain/salon_master_summary.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:beautica_mobile/shared/formatters/duration_minutes.dart';
import 'package:beautica_mobile/shared/formatters/service_price_display.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';

import '../../application/salon_master_coverage_notifier.dart';
import '../../application/salon_masters_roster_notifier.dart';
import '../../application/salon_booking_schedule_notifier.dart'
    show salonMasterDaySlotsProvider;
import '../../domain/booking_slot.dart';
import '../../domain/salon_booking_args.dart';
import '../../domain/salon_master_day_slots_query.dart';
import 'master_strip.dart' show masterRoleLabel, MasterRatingReadout;
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
// ---------------------------------------------------------------------------

class SalonDateStep extends ConsumerStatefulWidget {
  const SalonDateStep({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.onNext,
  });

  final DateTime? selected;
  final ValueChanged<DateTime> onSelect;

  /// Disabled (`onPressed: null`) until [selected] is non-null.
  final VoidCallback? onNext;

  @override
  ConsumerState<SalonDateStep> createState() => _SalonDateStepState();
}

class _SalonDateStepState extends ConsumerState<SalonDateStep> {
  late DateTime _pagedMonth;
  bool _initialized = false;

  static const int _horizonMonths = 3;

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
          const CalendarWeekdayBar(),
          const SizedBox(height: VelvetSpacing.xs),
          MonthCalendar(
            key: const Key('salon-create-booking-date-calendar'),
            visibleMonth: visibleMonth,
            today: today,
            selected: widget.selected,
            isAvailable: (DateTime day) => !day.isBefore(today),
            onSelectDay: widget.onSelect,
            onPrevMonth: visibleMonth.isAfter(_firstMonth(today))
                ? () => _prevMonth(today)
                : null,
            onNextMonth: visibleMonth.isBefore(_lastMonth(today))
                ? () => _nextMonth(today)
                : null,
          ),
          const SizedBox(height: VelvetSpacing.xl),
          NeumorphicButton(
            key: const Key('salon-create-booking-date-next'),
            label: l10n.salonCreateBookingDateNextCta,
            icon: Icons.arrow_forward_rounded,
            onPressed: widget.onNext,
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

class SalonMastersStep extends ConsumerWidget {
  const SalonMastersStep({
    super.key,
    required this.salonId,
    required this.service,
    required this.date,
    required this.onPick,
  });

  final String salonId;

  /// The chosen catalogue service — `.serviceDefId` is the id the coverage
  /// query keys on (see `salonServiceForShelf`'s own doc: `id`/`serviceDefId`
  /// both carry the salon-catalog id for a salon-sourced [MasterService]).
  final MasterService service;

  /// Date-only.
  final DateTime date;

  /// Fires once a slot is picked — [String] is the chosen master's OWN
  /// per-master `MasterServiceAssignment` id (`assignmentId`), the exact id
  /// `CreateMasterBookingRequest.masterServiceId` needs — NEVER
  /// `service.id`/`service.serviceDefId` (the salon-catalog id; see
  /// `salon_master_schedule.dart`'s "ID-SPACE NOTE" for why the two id
  /// spaces must never be conflated).
  final void Function(
    SalonMasterSummary master,
    String assignmentId,
    BookingSlot slot,
  )
  onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final String serviceDefId = service.serviceDefId;

    final AsyncValue<List<SalonMasterSummary>> rosterAsync = ref.watch(
      salonMastersRosterProvider(salonId),
    );
    final SalonBookingMasterSelectionArgs coverageArgs =
        SalonBookingMasterSelectionArgs(
          salonId: salonId,
          selectedServiceIds: <String>[serviceDefId],
        );
    final AsyncValue<Map<String, Map<String, String>>> coverageAsync = ref
        .watch(salonMasterServiceCoverageProvider(coverageArgs));

    final Object? error = rosterAsync.error ?? coverageAsync.error;
    if (error != null) {
      return ErrorState(
        key: const Key('salon-create-booking-masters-error'),
        failure: error is Failure ? error : UnknownFailure(cause: error),
        onRetry: () {
          ref.invalidate(salonMastersRosterProvider(salonId));
          ref.invalidate(salonMasterServiceCoverageProvider(coverageArgs));
        },
      );
    }

    final List<SalonMasterSummary>? roster = rosterAsync.value;
    final Map<String, Map<String, String>>? coverage = coverageAsync.value;
    if (roster == null || coverage == null) {
      return const Center(
        key: ValueKey<String>('salon-create-booking-masters-loading'),
        child: CircularProgressIndicator(color: BrandColors.accent),
      );
    }

    final List<(SalonMasterSummary, String?)> resolved =
        <(SalonMasterSummary, String?)>[
          for (final SalonMasterSummary m in roster)
            (m, coverage[m.masterId]?[serviceDefId]),
        ];
    final List<(SalonMasterSummary, String?)> covering =
        <(SalonMasterSummary, String?)>[
          for (final (SalonMasterSummary, String?) r in resolved)
            if (r.$2 != null) r,
        ];

    if (covering.isEmpty) {
      return _SalonMastersEmptyState(
        key: const Key('salon-create-booking-no-covering-master'),
        title: l10n.salonBookingNoCoveringMasterTitle,
        hint: l10n.salonBookingNoCoveringMasterHint,
      );
    }

    // COLLAPSE RULE (locked) — a salon with exactly one active master gets
    // the same treatment an independent master's own calendar would: no
    // one-row picker, just the slot grid. Keyed on ROSTER count, never on
    // the caller's role.
    if (roster.length == 1) {
      final (SalonMasterSummary soleMaster, String? soleAssignment) =
          resolved.single;
      // Guaranteed non-null: `covering` is non-empty and roster has exactly
      // one entry, so that one entry IS the covering one.
      final String assignmentId = soleAssignment!;
      return _SalonCollapsedSlots(
        key: const Key('salon-create-booking-masters-collapsed'),
        masterId: soleMaster.masterId,
        assignmentId: assignmentId,
        date: date,
        onPick: (BookingSlot slot) => onPick(soleMaster, assignmentId, slot),
      );
    }

    final List<(SalonMasterSummary, String?)> nonCovering =
        <(SalonMasterSummary, String?)>[
          for (final (SalonMasterSummary, String?) r in resolved)
            if (r.$2 == null) r,
        ];
    final List<(SalonMasterSummary, String?)> ordered =
        <(SalonMasterSummary, String?)>[...covering, ...nonCovering];

    return ListView.separated(
      key: const Key('salon-create-booking-masters-list'),
      padding: const EdgeInsets.fromLTRB(
        VelvetSpacing.lg,
        VelvetSpacing.sm,
        VelvetSpacing.lg,
        VelvetSpacing.xxl,
      ),
      itemCount: ordered.length,
      separatorBuilder: (BuildContext context, int i) =>
          const SizedBox(height: VelvetSpacing.sm),
      itemBuilder: (BuildContext context, int i) {
        final (SalonMasterSummary m, String? assignmentId) = ordered[i];
        return _SalonMasterTile(
          key: Key('salon-master-tile-${m.masterId}'),
          index: i,
          master: m,
          service: service,
          assignmentId: assignmentId,
          date: date,
          onSlotPick: assignmentId == null
              ? null
              : (BookingSlot slot) => onPick(m, assignmentId, slot),
        );
      },
    );
  }
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
    required this.assignmentId,
    required this.date,
    required this.onPick,
  });

  final String masterId;
  final String assignmentId;
  final DateTime date;
  final ValueChanged<BookingSlot> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final AsyncValue<List<BookingSlot>> slotsAsync = ref.watch(
      salonMasterDaySlotsProvider(
        SalonMasterDaySlotsQuery(
          masterId: masterId,
          serviceIds: <String>[assignmentId],
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
                serviceIds: <String>[assignmentId],
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
    required this.service,
    required this.assignmentId,
    required this.date,
    required this.onSlotPick,
  });

  final int index;
  final SalonMasterSummary master;
  final MasterService service;

  /// `null` when this master does NOT offer [service] — renders a faint,
  /// non-tappable row (design's `offersService == false` face).
  final String? assignmentId;
  final DateTime date;
  final ValueChanged<BookingSlot>? onSlotPick;

  @override
  ConsumerState<_SalonMasterTile> createState() => _SalonMasterTileState();
}

class _SalonMasterTileState extends ConsumerState<_SalonMasterTile> {
  bool _expanded = false;

  bool get _offers => widget.assignmentId != null;

  /// Alpha multiplier for a non-covering tile's whole face — same value the
  /// tile previously wrapped in `Opacity(opacity: 0.42, ...)` (mobile-perf
  /// P1, Phase 250): that subtree `Opacity` forced a `saveLayer` per
  /// non-covering tile on screen (avatar, name, role, rating, pill — every
  /// painted layer). Every color below is faded individually instead so no
  /// `saveLayer` is needed. See `test/golden/salon_master_tile_golden_test
  /// .dart` for the before/after equivalence check.
  static const double _kNonOfferingDim = 0.42;

  /// Multiplies [color]'s own alpha by [_kNonOfferingDim] when this tile does
  /// NOT offer the service; returns [color] unchanged otherwise. Composable
  /// with a color that already carries its own alpha (e.g. the avatar
  /// icon's `0.85`) — the two multiply together, same as they would inside a
  /// group `Opacity`.
  Color _fade(Color color) =>
      _offers ? color : color.withValues(alpha: color.a * _kNonOfferingDim);

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
    if (!_offers) return;
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

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: BrandColors.base,
        borderRadius: BorderRadius.circular(VelvetRadii.card),
        border: Border.all(
          color: _fade(
            _expanded
                ? BrandColors.accent
                : _offers
                ? BrandColors.accent.withValues(alpha: 0.18)
                : BrandColors.faint,
          ),
          width: _expanded ? 1.5 : 1,
        ),
        boxShadow: _offers ? VelvetShadows.extrudedSmall : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Semantics(
            button: _offers,
            enabled: _offers,
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
                            if (_offers) ...<Widget>[
                              const SizedBox(height: 3),
                              Text(
                                '${DurationMinutes.format(widget.service.durationMinutes)} '
                                '· ${ServicePriceDisplay.format(widget.service)}',
                                style: VelvetText.feedbackAccentSm,
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
                              opacity: _offers ? 1.0 : _kNonOfferingDim,
                            ),
                          const SizedBox(height: 5),
                          _SalonMasterStatusPill(
                            label: _offers
                                ? l10n.salonCreateBookingMasterOffers
                                : l10n.salonCreateBookingMasterNotOffered,
                            color: _offers
                                ? BrandColors.success
                                : BrandColors.textSecondary,
                            opacity: _offers ? 1.0 : _kNonOfferingDim,
                          ),
                        ],
                      ),
                      if (_offers) ...<Widget>[
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
                      assignmentId: widget.assignmentId!,
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
  /// `_SalonMasterTile` dim a non-covering master's pill without wrapping it
  /// (or any wider ancestor) in `Opacity`.
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
    required this.assignmentId,
    required this.date,
    required this.onPick,
  });

  final String masterId;
  final String assignmentId;
  final DateTime date;
  final ValueChanged<BookingSlot> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final SalonMasterDaySlotsQuery query = SalonMasterDaySlotsQuery(
      masterId: masterId,
      serviceIds: <String>[assignmentId],
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
