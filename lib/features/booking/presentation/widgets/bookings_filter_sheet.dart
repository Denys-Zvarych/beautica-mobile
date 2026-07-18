// Phase 7.7 — the master «Мої записи» filter sheet: Дата · Статус · Послуга.
//
// ## Where this was transcribed from
//
// As with the sort sheet, the design app has no status/service filter sheet to
// copy verbatim — `bookings_toolbar.dart`'s only sheet is `_MasterFilterSheet`
// (`:1169`), the salon-wide TEAMMATE filter, which is explicitly out of scope
// (`showMasterFilter: false`; see the phase doc's scope table). What IS
// transcribed from it is its whole visual vocabulary, verbatim: the sheet
// chrome, the grabber, `_PickerRow`'s check-circle/circle-outline toggle
// (`:1290`), and the «Скинути» / «Застосувати» footer affordances
// (`:1253`, `:1275`). Only the SECTIONS are new, and each maps 1:1 to a query
// parameter the backend already ships.
//
// **No «Майстер» section is rendered, ever.** A single master's own list never
// offers a teammate filter, there is no `masterId` parameter on this path, and
// backend 26.x deliberately did not extend Phase 23.4's salon endpoint for it.
// Pinned by a test.
//
// ## Draft state, applied once
//
// Every toggle mutates SHEET-LOCAL draft state. Nothing reaches
// `MasterBookingsQuery` until «Застосувати». Live-applying per tap would fire a
// request per checkbox — five taps to build one filter is five page-0 fetches,
// four of them for a filter the master never asked to see.
//
// ## The caps are enforced here, not discovered at the server
//
// The backend rejects >5 statuses, >50 serviceIds and a >366-day window with a
// **400** (Phase 26.1/26.4/26.2/26.6). None of those is reachable from this
// sheet: the status universe is exactly 5 by construction, the service rows
// stop toggling on at [kMaxServiceFilterIds], and the date range is capped
// inside the picker itself (`PeriodRangePicker.maxSpanDays`). There is
// deliberately no error copy for any of the three — an unreachable state needs
// no message.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

import '../../domain/booking_status.dart';

/// Server-side cap on `?serviceId=` values (backend Phase 26.4). The sheet
/// stops toggling rows ON at this count so the cap is never reached from the
/// UI.
const int kMaxServiceFilterIds = 50;

/// The user-facing status groups offered by the filter.
///
/// ## Four rows, not five — and NOT because PENDING was dropped
///
/// `BookingStatus.filterable` has five members and all five are offered; two of
/// them share one row. `DECLINED` (provider-initiated cancellation) and
/// `CANCELLED` (client-initiated) both render as «Скасовано» app-wide — the
/// who-cancelled distinction was deliberately collapsed on the booking detail
/// and on the client «Мої записи» list. Two rows reading «Скасовано» would be a
/// filter the master cannot tell apart, so the row selects BOTH wire statuses.
/// Selecting every row therefore sends exactly 5 `?status=` values, which is
/// the cap precisely — and is why the cap can never be exceeded from here.
///
/// PENDING is absent for a different reason entirely: it no longer exists.
/// Track 24.x made booking creation auto-confirm, the backend enum has no such
/// member, and the design preview that still shows «Очікує» is stale on this
/// point (see `booking_status.dart`'s header). Do not re-add it.
enum BookingStatusFilterGroup {
  confirmed(<BookingStatus>{BookingStatus.confirmed}),
  completed(<BookingStatus>{BookingStatus.completed}),
  notCompleted(<BookingStatus>{BookingStatus.notCompleted}),
  cancelled(<BookingStatus>{BookingStatus.cancelled, BookingStatus.declined});

  const BookingStatusFilterGroup(this.statuses);

  /// The wire statuses this row selects. Never contains [BookingStatus.unknown]
  /// — it is a decode-only member with no wire representation, and sending
  /// `status=UNKNOWN` is a 400.
  final Set<BookingStatus> statuses;
}

/// Returns the localised label for [group].
String bookingStatusFilterLabel(
  AppLocalizations l10n,
  BookingStatusFilterGroup group,
) {
  switch (group) {
    case BookingStatusFilterGroup.confirmed:
      return l10n.bookingStatusConfirmed;
    case BookingStatusFilterGroup.completed:
      return l10n.bookingStatusCompleted;
    case BookingStatusFilterGroup.notCompleted:
      return l10n.bookingStatusNotCompleted;
    case BookingStatusFilterGroup.cancelled:
      return l10n.bookingStatusCancelled;
  }
}

/// The filter values the sheet resolves with — the three query parameters it
/// owns, and nothing else.
///
/// Deliberately NOT a `MasterBookingsQuery`: the sort is not a filter, the
/// sheet never sees it, and returning a whole query would let this surface
/// silently reset it. The screen folds these three onto the query it already
/// holds.
@immutable
class BookingsFilterSelection {
  const BookingsFilterSelection({
    this.statuses = const <BookingStatus>{},
    this.serviceIds = const <String>{},
    this.from,
    this.to,
  });

  final Set<BookingStatus> statuses;
  final Set<String> serviceIds;

  /// Inclusive local-date bounds. A single day is `from == to`; there is one
  /// date concept here, not a day AND a range — see
  /// `master_bookings_screen.dart`'s header for why.
  final DateTime? from;
  final DateTime? to;

  /// Number of ACTIVE filter groups, for the header badge.
  int get activeCount => bookingsActiveFilterCount(
    hasStatuses: statuses.isNotEmpty,
    hasServiceIds: serviceIds.isNotEmpty,
    hasDates: from != null || to != null,
  );
}

/// The ONE definition of "how many filter groups are active".
///
/// Counts groups, not values: «status» is one active filter whether the master
/// picked one status or four, and a date range is one filter, not two bounds. A
/// badge reading "6" for a two-decision filter is noise.
///
/// Shared between [BookingsFilterSelection.activeCount] (the sheet's own view)
/// and the screen's header badge, which counts off the already-canonical
/// `MasterBookingsQuery` instead of rebuilding a throwaway selection on every
/// `build()` (perf P8). Two independent copies of this formula is exactly how
/// the badge and the sheet come to disagree about what "active" means.
int bookingsActiveFilterCount({
  required bool hasStatuses,
  required bool hasServiceIds,
  required bool hasDates,
}) => (hasStatuses ? 1 : 0) + (hasServiceIds ? 1 : 0) + (hasDates ? 1 : 0);

/// The neumorphic funnel button in the «Мої записи» header.
///
/// Carries a count badge whenever any filter is active — the screen's
/// filter-empty state («Немає записів за цим фільтром») is only comprehensible
/// if the master can see that a filter IS on, and a silently-filtered list is
/// the top support question for this kind of screen.
class BookingsFilterButton extends StatelessWidget {
  const BookingsFilterButton({
    super.key,
    required this.activeCount,
    required this.onTap,
  });

  final int activeCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool active = activeCount > 0;
    return Semantics(
      button: true,
      label: l10n.bookingFilterButtonLabel,
      value: active ? l10n.bookingFilterActiveCount(activeCount) : null,
      child: GestureDetector(
        key: const Key('master-bookings-filter-button'),
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Container(
              height: 44,
              width: 44,
              decoration: BoxDecoration(
                color: BrandColors.base,
                borderRadius: BorderRadius.circular(VelvetRadii.field),
                boxShadow: VelvetShadows.borderedButton,
                border: Border.all(
                  color: active
                      ? BrandColors.accent
                      : BrandColors.accent.withValues(alpha: 0.18),
                  width: active ? 1.5 : 1,
                ),
              ),
              child: Icon(
                Icons.tune_rounded,
                color: active
                    ? BrandColors.accentDeep
                    : BrandColors.textSecondary,
                size: 22,
              ),
            ),
            if (active)
              Positioned(
                top: -4,
                right: -4,
                child: _CountBadge(count: activeCount),
              ),
          ],
        ),
      ),
    );
  }
}

/// The camel count pill on the filter button. Excluded from semantics — the
/// button already announces the count as its `value`, and a bare digit read out
/// twice is worse than once.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        key: const Key('master-bookings-filter-badge'),
        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.xs),
        decoration: BoxDecoration(
          // Mocha, not the design's camel dot — see `VelvetText.filterBadge`
          // for the contrast reason (a dot carries no digit).
          color: BrandColors.accentDeep,
          borderRadius: BorderRadius.circular(VelvetRadii.pill),
          border: Border.all(color: BrandColors.base, width: 1.5),
        ),
        child: Text('$count', style: VelvetText.filterBadge),
      ),
    );
  }
}

/// The multi-select filter sheet. Resolves with the applied
/// [BookingsFilterSelection], or `null` when dismissed without applying.
class BookingsFilterSheet extends StatefulWidget {
  const BookingsFilterSheet({
    super.key,
    required this.initial,
    required this.services,
    required this.onPickDates,
  });

  final BookingsFilterSelection initial;

  /// The option universe for «Послуга» — the master's own catalogue, from
  /// `masterServiceCatalogProvider`. Empty (or still loading) hides the whole
  /// section rather than showing an empty one.
  final List<MasterService> services;

  /// Opens the range calendar and resolves with the picked bounds, or `null` if
  /// dismissed. Injected rather than called directly so the sheet stays a pure
  /// widget — and so a test can drive the date section without pumping a
  /// 36-month scrolling calendar.
  final Future<DateTimeRange?> Function(
    BuildContext context,
    DateTimeRange? current,
  )
  onPickDates;

  static Future<BookingsFilterSelection?> show(
    BuildContext context, {
    required BookingsFilterSelection initial,
    required List<MasterService> services,
    required Future<DateTimeRange?> Function(BuildContext, DateTimeRange?)
    onPickDates,
  }) {
    return showModalBottomSheet<BookingsFilterSelection>(
      context: context,
      backgroundColor: Colors.transparent,
      // The service catalogue is unbounded, so the sheet must be able to grow
      // and scroll rather than overflow at ~8 rows.
      isScrollControlled: true,
      builder: (BuildContext ctx) => BookingsFilterSheet(
        initial: initial,
        services: services,
        onPickDates: onPickDates,
      ),
    );
  }

  @override
  State<BookingsFilterSheet> createState() => _BookingsFilterSheetState();
}

class _BookingsFilterSheetState extends State<BookingsFilterSheet> {
  late Set<BookingStatus> _statuses;
  late Set<String> _serviceIds;
  DateTime? _from;
  DateTime? _to;

  @override
  void initState() {
    super.initState();
    _statuses = Set<BookingStatus>.of(widget.initial.statuses);
    _serviceIds = Set<String>.of(widget.initial.serviceIds);
    _from = widget.initial.from;
    _to = widget.initial.to;
  }

  bool _groupSelected(BookingStatusFilterGroup g) =>
      g.statuses.every(_statuses.contains);

  void _toggleGroup(BookingStatusFilterGroup g) {
    setState(() {
      if (_groupSelected(g)) {
        _statuses.removeAll(g.statuses);
      } else {
        _statuses.addAll(g.statuses);
      }
    });
  }

  /// Whether [id]'s row still responds to a tap.
  ///
  /// The SINGLE enforcement point for the 50-id cap — both the row's `enabled`
  /// flag and [_toggleService] read it. Deliberately not duplicated as two
  /// independent checks: with a redundant pair, breaking either one alone left
  /// the other silently covering for it, so no test could observe the loss (a
  /// cap test stayed green through a mutation of each guard in turn and only
  /// failed when BOTH were removed). One guard, one mutation, one failure.
  ///
  /// Already-selected ids always stay tappable, so the cap can never trap the
  /// master into being unable to DEselect.
  bool _canToggleService(String id) =>
      _serviceIds.contains(id) || _serviceIds.length < kMaxServiceFilterIds;

  void _toggleService(String id) {
    if (!_canToggleService(id)) return;
    setState(() {
      if (_serviceIds.contains(id)) {
        _serviceIds.remove(id);
      } else {
        // Silently refuses past the cap rather than surfacing the server's
        // 400. See the file header.
        _serviceIds.add(id);
      }
    });
  }

  Future<void> _pickDates() async {
    final DateTime? from = _from;
    final DateTime? to = _to;
    final DateTimeRange? current = (from == null || to == null)
        ? null
        : DateTimeRange(start: from, end: to);
    final DateTimeRange? picked = await widget.onPickDates(context, current);
    if (!mounted || picked == null) return;
    setState(() {
      _from = picked.start;
      _to = picked.end;
    });
  }

  void _clearDates() => setState(() {
    _from = null;
    _to = null;
  });

  void _resetAll() => setState(() {
    _statuses = <BookingStatus>{};
    _serviceIds = <String>{};
    _from = null;
    _to = null;
  });

  void _apply() => context.pop(
    BookingsFilterSelection(
      statuses: _statuses,
      serviceIds: _serviceIds,
      from: _from,
      to: _to,
    ),
  );

  bool get _anyActive =>
      _statuses.isNotEmpty ||
      _serviceIds.isNotEmpty ||
      _from != null ||
      _to != null;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return DecoratedBox(
      key: const Key('master-bookings-filter-sheet'),
      decoration: const BoxDecoration(
        color: BrandColors.base,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(VelvetRadii.card),
        ),
      ),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          // Never taller than most of the viewport — a 40-service catalogue
          // would otherwise push the «Застосувати» footer off-screen, which is
          // the one control the sheet cannot function without.
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.only(top: VelvetSpacing.md),
                child: _SheetGrabber(),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(
                    VelvetSpacing.lg,
                    VelvetSpacing.md,
                    VelvetSpacing.lg,
                    0,
                  ),
                  children: <Widget>[
                    Text(
                      l10n.bookingFilterSheetTitle,
                      style: VelvetText.subheading(),
                    ),
                    const SizedBox(height: VelvetSpacing.md),
                    _SectionLabel(
                      l10n.bookingFilterSectionDate,
                      labelKey: const Key(
                        'master-bookings-filter-section-date',
                      ),
                    ),
                    _DateRow(
                      from: _from,
                      to: _to,
                      onPick: _pickDates,
                      onClear: _clearDates,
                    ),
                    const SizedBox(height: VelvetSpacing.md),
                    _SectionLabel(
                      l10n.bookingFilterSectionStatus,
                      labelKey: const Key(
                        'master-bookings-filter-section-status',
                      ),
                    ),
                    for (final BookingStatusFilterGroup g
                        in BookingStatusFilterGroup.values)
                      _PickerRow(
                        rowKey: Key('master-bookings-filter-status-${g.name}'),
                        label: bookingStatusFilterLabel(l10n, g),
                        selected: _groupSelected(g),
                        onToggle: () => _toggleGroup(g),
                      ),
                    // The section is omitted entirely when the master has no
                    // services — an empty «Послуга» heading reads as a broken
                    // fetch rather than an empty catalogue.
                    if (widget.services.isNotEmpty) ...<Widget>[
                      const SizedBox(height: VelvetSpacing.md),
                      _SectionLabel(
                        l10n.bookingFilterSectionService,
                        labelKey: const Key(
                          'master-bookings-filter-section-service',
                        ),
                      ),
                      for (final MasterService s in widget.services)
                        _PickerRow(
                          rowKey: Key('master-bookings-filter-service-${s.id}'),
                          label: s.name,
                          selected: _serviceIds.contains(s.id),
                          // Cap reached → the unselected rows stop responding
                          // (backend 26.4 rejects >50 with a 400).
                          enabled: _canToggleService(s.id),
                          onToggle: () => _toggleService(s.id),
                        ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  VelvetSpacing.lg,
                  VelvetSpacing.sm,
                  VelvetSpacing.lg,
                  VelvetSpacing.lg,
                ),
                child: Row(
                  children: <Widget>[
                    if (_anyActive)
                      Semantics(
                        button: true,
                        label: l10n.bookingFilterResetSemantics,
                        child: GestureDetector(
                          key: const Key('master-bookings-filter-reset'),
                          onTap: _resetAll,
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: VelvetSpacing.sm,
                            ),
                            child: Text(
                              l10n.bookingFilterReset,
                              style: VelvetText.link(),
                            ),
                          ),
                        ),
                      ),
                    const Spacer(),
                    Semantics(
                      button: true,
                      label: l10n.bookingFilterApplySemantics,
                      child: GestureDetector(
                        key: const Key('master-bookings-filter-apply'),
                        onTap: _apply,
                        behavior: HitTestBehavior.opaque,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: BrandColors.base,
                            borderRadius: BorderRadius.circular(
                              VelvetRadii.pill,
                            ),
                            boxShadow: VelvetShadows.borderedButton,
                            border: Border.all(color: BrandColors.accent),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: VelvetSpacing.lg,
                              vertical: VelvetSpacing.sm + 2,
                            ),
                            child: Text(
                              l10n.bookingFilterApply,
                              style: VelvetText.link(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The «Дата» row — opens the calendar, and clears the window when one is set.
class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.from,
    required this.to,
    required this.onPick,
    required this.onClear,
  });

  final DateTime? from;
  final DateTime? to;
  final VoidCallback onPick;
  final VoidCallback onClear;

  static String _short(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final DateTime? f = from;
    final DateTime? t = to;
    final bool active = f != null || t != null;
    final String label = (f == null || t == null)
        ? l10n.bookingFilterDateAny
        : f == t
        ? _short(f)
        : '${_short(f)} – ${_short(t)}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: VelvetSpacing.sm),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Semantics(
              button: true,
              label: l10n.bookingFilterDateSemantics,
              value: label,
              child: GestureDetector(
                key: const Key('master-bookings-filter-date'),
                onTap: onPick,
                behavior: HitTestBehavior.opaque,
                child: NeumorphicInset(
                  radius: VelvetRadii.field,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: VelvetSpacing.md,
                      vertical: VelvetSpacing.sm + 2,
                    ),
                    child: Row(
                      children: <Widget>[
                        const Icon(
                          Icons.date_range_rounded,
                          size: 18,
                          color: BrandColors.accentDeep,
                        ),
                        const SizedBox(width: VelvetSpacing.sm),
                        Expanded(
                          child: Text(
                            label,
                            style: VelvetText.bodyStrong14,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (active) ...<Widget>[
            const SizedBox(width: VelvetSpacing.sm),
            Semantics(
              button: true,
              label: l10n.bookingFilterClearDate,
              child: GestureDetector(
                key: const Key('master-bookings-filter-date-clear'),
                onTap: onClear,
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.all(VelvetSpacing.sm),
                  child: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: BrandColors.accentDeep,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A section heading inside the sheet.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.labelKey});

  final String text;

  /// Optional key so a test can assert a SECTION's presence without a
  /// locale-coupled `find.text('Послуга')` (banned by
  /// `scripts/forbid_cyrillic_finder.sh` — such a finder silently becomes a
  /// `findsNothing` false pass the day EN ships).
  final Key? labelKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: labelKey,
      padding: const EdgeInsets.only(bottom: VelvetSpacing.xs),
      child: Text(text, style: VelvetText.label()),
    );
  }
}

/// One multi-select row — the design's `_PickerRow` (`bookings_toolbar.dart:
/// 1290`), plus a disabled state for the service cap.
class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.rowKey,
    required this.label,
    required this.selected,
    required this.onToggle,
    this.enabled = true,
  });

  final Key rowKey;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: label,
      child: GestureDetector(
        key: rowKey,
        onTap: enabled ? onToggle : null,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: VelvetSpacing.sm + 2),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: VelvetText.bodyStrong14.copyWith(
                    color: enabled ? BrandColors.text : BrandColors.faint,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: 20,
                color: selected
                    ? BrandColors.accentDeep
                    : enabled
                    ? BrandColors.textSecondary
                    : BrandColors.faint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The 4×44 grabber pill every VelvetTouch bottom sheet carries.
class _SheetGrabber extends StatelessWidget {
  const _SheetGrabber();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        height: 4,
        width: 44,
        decoration: BoxDecoration(
          color: BrandColors.faint,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
