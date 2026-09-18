// Phase 21.12 — the salon owner/admin's «Записи» board: slot 1 of
// [SalonShellScreen], replacing the [SalonShellTabPlaceholder] that stood
// there since Phase 21.8.
//
// ============================================================================
// THIS SCREEN IS A COMPOSITION, NOT A SCREEN
// ============================================================================
// It renders [BookingsDiscoveryView] — the same composition behind the
// INDEPENDENT_MASTER's `/master/bookings` and the invited SALON_MASTER's
// `/staff/bookings` — and adds exactly three things to it:
//
//   1. the SEED QUERY's scope (`BookingsDayQuery.salonOf`), which is what
//      makes `bookingsDayProvider` fetch `GET /bookings/salon/{salonId}`
//      instead of `GET /bookings/me` — and, for the same reason, makes the
//      rail's dots `GET /bookings/salon/{salonId}/booked-days` instead of
//      `/bookings/me/booked-days`. The view dispatches on the seed's sealed
//      member and branches on scope nowhere else — see its `_rebuildQuery`
//      and `_bookedDaysAsync`.
//   2. the COLUMNS BUILDER: the salon's roster, partitioned against whatever
//      day the view fetched. The view owns the day and the fetch; this screen
//      owns "which masters exist". Neither can do the other's half, which is
//      exactly why the seam is a builder.
//   3. the chrome differences an owner needs: the salon's name as a subtitle,
//      no «Послуга» filter (the signed-in owner has no master catalogue) and
//      no archive button.
//   4. (Phase 335) the BOARD WINDOW BUILDER: the timeline's vertical bounds,
//      taken from the UNION of every roster master's working hours for the
//      selected day rather than from whichever bookings happen to exist. Same
//      shape as the columns builder and for the same reason — this screen owns
//      "which masters work when", the view owns the day and the fetch.
//   4b. (2026-09-18) the «Майстер» FILTER's option universe — the same roster
//      as (2), handed to `BookingsDiscoveryView.masterFilterOptions` so the
//      shared filter sheet can offer it. The ticked ids come back as
//      [columnsFor]'s `masterIds` and narrow the ROSTER, nothing else.
//
//      ⚠ THIS REVERSES A DOCUMENTED DECISION, deliberately. This header used
//      to list the «Майстер» section under "WHAT IS DELIBERATELY NOT HERE",
//      on the argument that `GET /bookings/salon/{salonId}` takes exactly ONE
//      `masterId` while every section of `BookingsFilterSheet` is
//      multi-select, so a «Майстер» section would have to collapse the board
//      to a single column. The user resolved it with the answer that dissolves
//      that argument: the section is MULTI-SELECT and CLIENT-SIDE. No request
//      changes, `BookingsDayQuery.salon.masterId` stays `null`, the board
//      keeps its side-by-side shape, and it simply draws fewer columns. What
//      that old note said about the roster CHIPS is unchanged and still true:
//      a chip tap is a HIGHLIGHT, not a filter (`BookingsTimelineGrid
//      .selectedMasterId`), and the two never touch each other.
//   5. (Phase 336) the DAY-OFF MARK, off the SAME roster hours phase 335
//      already fetches. A master who is not working the selected day renders
//      as a greyed «Вихідний» column instead of an empty one that reads
//      identically to "working, nothing booked". It travels on the columns
//      builder (which is why that builder now also receives the day) and the
//      predicate is [masterDayOff] — never "this master has no bookings",
//      which is the bug, not the fix.
//
// Everything else — the day rail, the week/month pagers, the filter sheet, the
// four async states, the hour ruler, every [MasterBookingCard] — is the
// shipped widget tree. A fix to any of it reaches this board, the independent
// master's «Мої записи» and the salon master's read-only «Записи» together;
// that propagation is the point of the seam, not a side effect of it.
//
// ============================================================================
// WHAT IS DELIBERATELY NOT HERE
// ============================================================================
//  * MANUAL BOOKING CREATION. The (+) control renders in its final place and
//    styling and its handler is a documented NO-OP — see [_openCreateBooking].
//    Locked by the user for this phase: "don't add for this page the manual
//    adding booking feature, just add the placeholder at first".
//  * A BOOKING-ACTION FOOTER. Cards route to `BookingDetailScreen`
//    ([RouteNames.bookingDetail]), which already role-branches its own
//    provider actions off `bookingViewerRoleProvider` and already offers
//    «Скасувати запис» (`PATCH /bookings/{id}/decline`) to an owner and an
//    assigned admin. Re-deciding that here would be a second, drifting copy of
//    a gate the detail screen already owns.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';

import '../../booking/application/bookings_capability.dart';
import '../../booking/application/salon_masters_roster_notifier.dart';
import '../../booking/domain/booking.dart';
import '../../booking/domain/bookings_day_query.dart';
import '../../booking/presentation/bookings_discovery_view.dart';
import '../../booking/presentation/widgets/bookings_filter_sheet.dart';
import '../../booking/presentation/widgets/bookings_timeline_grid.dart';
import '../../booking/presentation/widgets/master_column_strip.dart';
import '../../booking/presentation/widgets/my_bookings_states.dart';
import '../../booking/presentation/widgets/schedule_timeline_window.dart';
import '../../schedule/domain/weekly_schedule.dart';
import '../../schedule/presentation/salon_effective_schedule_notifier.dart';
import '../../schedule/presentation/schedule_range.dart';
import '../application/salon_manage_capability.dart';
import '../application/salon_management_profile_notifier.dart';
import '../domain/salon_master_summary.dart';

/// The salon-wide bookings board for one salon.
class SalonBookingsScreen extends ConsumerStatefulWidget {
  const SalonBookingsScreen({required this.salonId, super.key});

  final String salonId;

  @override
  ConsumerState<SalonBookingsScreen> createState() =>
      _SalonBookingsScreenState();

  /// Partitions ONE day's bookings across the salon's roster, in roster order.
  ///
  /// Every column is emitted, including a master with nothing booked — an
  /// absent column would silently renumber every column to its right and
  /// un-pin the roster chips above them. The empty column renders its own
  /// «Вільний день» marker (`BookingsTimelineGrid`'s `_BoardStack`) — or, when
  /// [day] and [rosterSchedule] are both supplied and say that master is not
  /// working, a greyed «Вихідний» one instead. Both optional parameters
  /// default to `null` and a `null` [day] short-circuits the lookup entirely,
  /// so the pre-existing two-argument call is unchanged.
  ///
  /// Order is preserved WITHIN each column (this partitions, never re-sorts),
  /// which is load-bearing: `assignLanes` walks its input once and is correct
  /// only on an ascending-`startsAt` stream.
  ///
  /// A booking whose `masterId` is not in the roster is DROPPED — and that is
  /// a real, if rare, case: a master removed from the salon after a booking
  /// was placed, or (transiently) the first frames before the roster fetch
  /// resolves. It is the one place the "columns partition the list" contract
  /// of [TimelineBoardColumn.bookings] can be broken, so the count the header
  /// prints is recomputed from the COLUMNS rather than from the incoming list
  /// — see `bookings_discovery_view.dart`'s `_body`, which is what keeps
  /// «N записів» equal to the cards on screen in that case too.
  /// Phase 336 — whether [masterId] is NOT WORKING on [day], per the
  /// roster-complete effective-schedule response.
  ///
  /// ## THE PREDICATE, AND ITS THREE "I DO NOT KNOW" ANSWERS
  ///
  /// `true` ONLY when the response actually carries a resolved [EffectiveDay]
  /// for this master on this date AND that day has no working hours at all —
  /// which is exactly `scheduleWindowFor(d) == null`, the SAME function
  /// [boardWindowFor]'s union skips a master on. One predicate, two readers:
  /// a column can never be greyed out while its hours are simultaneously
  /// widening the timeline.
  ///
  /// It returns `false` — "not known to be off", never "working" — in each of
  /// three distinct unknowns, and every one of them must render as an
  /// ORDINARY column:
  ///
  ///   1. [rosterSchedule] is `null` — the hours have not resolved yet, or the
  ///      fetch failed. Greying the whole board on a cold mount, then
  ///      un-greying it a frame later, would be a lie told twice.
  ///   2. the master has NO ENTRY in the map. The response is ROSTER-COMPLETE
  ///      by contract (`SalonRosterScheduleRepository
  ///      .salonRosterEffectiveSchedule` — every ACTIVE master appears, even
  ///      with zero schedule rows, whose days then resolve to
  ///      [EffectiveSource.noSchedule]). So a missing key is a genuine
  ///      MISMATCH between the roster strip and the schedule batch — a master
  ///      who left, or joined, between the two fetches — and a mismatch is
  ///      not evidence of a day off.
  ///   3. no [EffectiveDay] carries [day]. The board fetches KYIV-TODAY's
  ///      month (see [build]); paging the rail into another month leaves the
  ///      selected date outside the window, and [boardWindowFor] already
  ///      degrades to the booking-derived window there. This degrades the same
  ///      way, in the same direction: no marks rather than wrong marks.
  ///
  /// What it is emphatically NOT is "this master has no bookings". That is
  /// [MasterColumnEntry.bookingCount] == 0 — «Вільний день», a master who IS
  /// working — and conflating the two is the bug this whole predicate exists
  /// to remove.
  @visibleForTesting
  static bool masterDayOff(
    String masterId,
    DateTime day,
    Map<String, List<EffectiveDay>>? rosterSchedule,
  ) {
    if (rosterSchedule == null) return false;
    final List<EffectiveDay>? days = rosterSchedule[masterId];
    if (days == null) return false;
    for (final EffectiveDay d in days) {
      if (d.date.year == day.year &&
          d.date.month == day.month &&
          d.date.day == day.day) {
        return scheduleWindowFor(d) == null;
      }
    }
    return false;
  }

  /// The roster [masterIds] narrows to, or [roster] itself.
  ///
  /// ## EMPTY MEANS EVERY MASTER — and so does "matches nobody"
  ///
  /// Two distinct inputs collapse to the same answer, for two different
  /// reasons:
  ///
  ///   1. **[masterIds] is empty.** No «Майстер» filter is set — the default,
  ///      every master route, and every pre-existing two-argument call. The
  ///      board renders its whole roster.
  ///   2. **[masterIds] is non-empty but matches NO roster master.** Only
  ///      reachable when every ticked master left the salon mid-session
  ///      (`BookingsDiscoveryView._applyFilters` resolves the selection against
  ///      the offered roster, so it cannot be reached by ticking). The board
  ///      renders its whole roster HERE TOO, and that is a deliberate choice
  ///      over the alternative: an empty column list makes
  ///      `BookingsTimelineGrid._buildBoard` render
  ///      «salon-bookings-no-masters» — a statement that THIS SALON HAS NO
  ///      MASTERS, which would be flatly false. Degrading toward showing more
  ///      is the same rule [masterDayOff] and [boardWindowFor] already follow
  ///      for their own unknowns: never guess, never show less.
  ///
  /// The funnel badge stays lit in case 2 (the owner did set a filter), so the
  /// state is visible and one «Скинути фільтри» away.
  static List<SalonMasterSummary> _narrowRoster(
    List<SalonMasterSummary> roster,
    Set<String> masterIds,
  ) {
    if (masterIds.isEmpty) return roster;
    final List<SalonMasterSummary> narrowed = <SalonMasterSummary>[
      for (final SalonMasterSummary m in roster)
        if (masterIds.contains(m.masterId)) m,
    ];
    return narrowed.isEmpty ? roster : narrowed;
  }

  /// [masterIds] — the «Майстер» filter's ticked ids, EMPTY for every master.
  /// Defaults to empty, so every pre-existing call renders byte-for-byte as it
  /// did. See [_narrowRoster] for the two inputs that mean "no narrowing".
  ///
  /// Narrowing happens BEFORE the partition, so a dropped master's bookings are
  /// not merely hidden — they are never assigned a column, which is what keeps
  /// [_body]'s column-derived «N записів» equal to the cards on screen.
  @visibleForTesting
  static List<TimelineBoardColumn> columnsFor(
    List<Booking> dayItems,
    List<SalonMasterSummary> fullRoster, {
    DateTime? day,
    Map<String, List<EffectiveDay>>? rosterSchedule,
    Set<String> masterIds = const <String>{},
  }) {
    final List<SalonMasterSummary> roster = _narrowRoster(
      fullRoster,
      masterIds,
    );
    final Map<String, List<Booking>> byMaster = <String, List<Booking>>{
      for (final SalonMasterSummary m in roster) m.masterId: <Booking>[],
    };
    for (final Booking b in dayItems) {
      byMaster[b.masterId]?.add(b);
    }
    return <TimelineBoardColumn>[
      for (final SalonMasterSummary m in roster)
        TimelineBoardColumn(
          bookings: byMaster[m.masterId] ?? const <Booking>[],
          header: MasterColumnEntry(
            masterId: m.masterId,
            name: '${m.firstName} ${m.lastName}'.trim(),
            type: m.type,
            professionalTitle: m.professionalTitle,
            // The roster's own "unrated" convention: `avgRating` is already
            // null when `reviewCount` is 0 (see [SalonMasterSummary]), and the
            // chip renders `MasterStrip.noRatingLabel` for it — never a
            // damning `0.0`, exactly as every other identity card in the
            // booking flow.
            avgRating: m.avgRating,
            bookingCount: (byMaster[m.masterId] ?? const <Booking>[]).length,
            // Phase 336 — `false` unless the roster-complete schedule
            // POSITIVELY says this master is off on this date. Both new
            // parameters default to `null`, and `day == null` short-circuits
            // before [masterDayOff] is ever consulted, so every pre-existing
            // two-argument call renders byte-for-byte as it did.
            dayOff:
                day != null && masterDayOff(m.masterId, day, rosterSchedule),
          ),
        ),
    ];
  }

  /// The board's timeline bounds for ONE day: the UNION of every roster
  /// master's working hours, WIDENED to cover every booking on the day.
  ///
  /// ## Why a union, and not the master board's per-person window
  ///
  /// `BookingsDiscoveryView.useScheduleWindow` (the master's own «Мої записи»)
  /// answers "which hours does THIS person work" and DROPS a booking that
  /// starts outside them — see `phase-244-master-timeline-working-hours-window
  /// .md`, whose rule is scoped to the master board and stays correct there.
  /// On a MANAGER's board that same rule is data loss: a 22:00 walk-in must not
  /// vanish because the master it belongs to finishes at 20:00.
  ///
  /// So this board does not filter differently — it asks for a WIDER WINDOW.
  /// `salonBoardWindow` takes the min of the roster's starts AND the earliest
  /// booking start, and the max of the roster's ends AND the latest booking
  /// END, which makes `bookingsInsideScheduleWindow` (still the one and only
  /// filter, unchanged, on both paths) provably vacuous here. The proof is in
  /// `schedule_timeline_window.dart`; `BookingsDiscoveryView._Loaded.build`
  /// asserts it with `identical()` in debug builds.
  ///
  /// ## `null` means "render as before"
  ///
  /// Returned when [rosterSchedule] is `null` (the hours fetch failed, or has
  /// not resolved yet) or when the selected [day] falls outside the fetched
  /// month, or when NO master on the roster works that day. The view then uses
  /// the booking-derived window it has always used. See [build]'s comment for
  /// why a schedule failure is deliberately NOT surfaced as an error state the
  /// way a roster or profile failure is.
  ///
  /// [rosterSchedule] is ROSTER-COMPLETE by contract — every ACTIVE master has
  /// an entry, even with zero schedule rows (see
  /// `SalonRosterScheduleRepository.salonRosterEffectiveSchedule`). That is
  /// what makes `null` above mean "not loaded" and never "everyone is off".
  @visibleForTesting
  static ScheduleTimelineWindow? boardWindowFor(
    List<Booking> dayItems,
    DateTime day,
    Map<String, List<EffectiveDay>>? rosterSchedule,
  ) {
    if (rosterSchedule == null) return null;
    final List<EffectiveDay> daysForDate = <EffectiveDay>[
      for (final List<EffectiveDay> days in rosterSchedule.values)
        for (final EffectiveDay d in days)
          if (d.date.year == day.year &&
              d.date.month == day.month &&
              d.date.day == day.day)
            d,
    ];
    if (daysForDate.isEmpty) return null;
    // Kyiv-minute conversion is owned by `bookings_timeline_grid.dart` — the
    // same one `bookingsInsideScheduleWindow` measures against, so the span fed
    // into the union and the starts the filter tests are in one unit by
    // construction rather than by two agreeing implementations.
    final ({int firstStartMinute, int lastEndMinute})? span =
        bookingsMinuteSpan(dayItems, day);
    return salonBoardWindow(
      rosterDays: daysForDate,
      bookingFirstMinute: span?.firstStartMinute,
      bookingLastEndMinute: span?.lastEndMinute,
    );
  }
}

/// ── WHY THIS SCREEN IS STATEFUL (mobile-perf MEDIUM ×2, 2026-09-17) ───────
///
/// It holds no UI state of its own; it holds two IDENTITIES, and both are
/// load-bearing for caches that live two widgets down.
///
/// `BookingsTimelineGrid` and its `_BoardStack` each memoise expensive work
/// behind an `identical(...)` gate in `didUpdateWidget`
/// (`bookings_timeline_grid.dart`'s two gates: the `O(N log N)` `assignLanes`
/// + per-card geometry recompute, and the built-column cache that lets
/// `Element.updateChild` skip a whole column subtree). When this screen was a
/// `ConsumerWidget`, both gates were DEAD on this route and had been since
/// they shipped:
///
///   * `columnsBuilder:` was an inline closure, so `_Loaded._body`'s
///     `columnsBuilder?.call(items, day)` allocated a FRESH `List` on every
///     rebuild of the view — new identity, both gates missed.
///   * `onBookingTap:` was an inline `(b) => context.push(...)` closure, so
///     `_BoardStack`'s `oldWidget.onBookingTap != widget.onBookingTap` was
///     permanently true on every rebuild of THIS screen.
///
/// Measured (mobile-perf, this audit): fixing either ALONE left the board at
/// 4/4 cards rebuilt and 483 dirty builds — they are AND-gated, because the
/// column-list identity alone resets the very cache the callback identity
/// also resets. Both together: 0/4 cards rebuilt, 371 dirty builds (−23%).
/// Do NOT "simplify" either one back to an inline closure.
///
/// The memo below is deliberately shaped like
/// `_BookingsDiscoveryViewState._visibleBookingsFor` (the sibling fix in
/// `bookings_discovery_view.dart`) — same single-slot, same identity keys,
/// same "a genuine miss is cheap, a false hit is a stale board" trade.
class _SalonBookingsScreenState extends ConsumerState<SalonBookingsScreen> {
  /// The roster and roster-schedule this build resolved, stashed so the
  /// [_columnsFor] / [_boardWindowFor] TEAR-OFFS (which the view stores and
  /// calls back into) can read them without being closures over them.
  ///
  /// A tear-off of an instance method compares EQUAL across rebuilds (same
  /// receiver, same method), which is what an inline closure can never do —
  /// that is the entire reason these two fields exist.
  List<SalonMasterSummary> _roster = const <SalonMasterSummary>[];
  Map<String, List<EffectiveDay>>? _rosterSchedule;

  /// Single-slot memo for [SalonBookingsScreen.columnsFor].
  ///
  /// ## Why these four keys are the COMPLETE input set
  ///
  /// `columnsFor` is `static`: it has no `this`, reads no provider, no
  /// `BuildContext`, no clock, no theme and no locale, so its output is a
  /// pure function of its five parameters and nothing else. That is not a
  /// claim about today's body — it is a property the `static` keyword
  /// enforces, and it is why this memo cannot go stale the way a gate whose
  /// condition set is narrower than its recompute's real inputs does.
  /// (The three `static` helpers it delegates to, `_narrowRoster`,
  /// `masterDayOff` and `scheduleWindowFor`, are closed over the same five
  /// values.)
  ///
  /// `dayItems` and `roster`/`rosterSchedule` are compared by IDENTITY:
  /// `_Loaded._body` passes `visibleItems ?? state.items`, both of which are
  /// identity-stable per booking-day fetch (`stableBookingList` in
  /// `bookings_day_state.dart`, and `bookingsInsideScheduleWindow` handing
  /// back its own input when nothing was filtered), and the two roster values
  /// come straight off an `AsyncValue.value` that only re-allocates on a real
  /// re-emit. `day` is compared by VALUE — it is a date-only `DateTime` token
  /// rebuilt per rail tap, so reference equality would never hit.
  ///
  /// ## `masterIds` IS THE FIFTH KEY, AND IT IS NOT OPTIONAL (2026-09-18)
  ///
  /// Before the «Майстер» filter existed, `dayItems` identity always moved
  /// with `day` — a day change is always a different fetch — so the `day ==`
  /// half of this gate had no stale direction it could actually cover, and an
  /// audit said so. That is no longer true: the «Майстер» selection changes
  /// while the day, the items, the roster and the schedule ALL stay identical,
  /// so without this key the gate would hit and the board would keep serving
  /// the pre-filter columns. The failure is invisible to any test that changes
  /// the day between assertions, which is why
  /// `salon_bookings_master_filter_test.dart` deliberately does not.
  ///
  /// Compared with `setEquals`, NOT by identity: a fresh `Set` arrives from
  /// every «Застосувати», including one that re-applies the same ticks, and
  /// identity would invalidate the whole board for a no-op apply.
  List<Booking>? _cachedColumnsItems;
  DateTime? _cachedColumnsDay;
  List<SalonMasterSummary>? _cachedColumnsRoster;
  Map<String, List<EffectiveDay>>? _cachedColumnsSchedule;
  Set<String> _cachedColumnsMasterIds = const <String>{};
  List<TimelineBoardColumn> _cachedColumns = const <TimelineBoardColumn>[];

  /// The `columnsBuilder:` the view calls back into. See [_cachedColumnsItems].
  List<TimelineBoardColumn> _columnsFor(
    List<Booking> dayItems,
    DateTime day,
    Set<String> masterIds,
  ) {
    if (identical(_cachedColumnsItems, dayItems) &&
        _cachedColumnsDay == day &&
        identical(_cachedColumnsRoster, _roster) &&
        identical(_cachedColumnsSchedule, _rosterSchedule) &&
        setEquals(_cachedColumnsMasterIds, masterIds)) {
      return _cachedColumns;
    }
    final List<TimelineBoardColumn> columns = SalonBookingsScreen.columnsFor(
      dayItems,
      _roster,
      day: day,
      rosterSchedule: _rosterSchedule,
      masterIds: masterIds,
    );
    _cachedColumnsItems = dayItems;
    _cachedColumnsDay = day;
    _cachedColumnsRoster = _roster;
    _cachedColumnsSchedule = _rosterSchedule;
    _cachedColumnsMasterIds = masterIds;
    _cachedColumns = columns;
    return columns;
  }

  /// Single-slot memo for the «Майстер» filter's option universe.
  ///
  /// The list is rebuilt only when the ROSTER's identity moves, not on every
  /// `build` — `BookingsDiscoveryView.masterFilterOptions` is a widget field
  /// and a fresh list per build would be a fresh allocation per build for a
  /// value the sheet reads once, on open. Same single-slot shape and the same
  /// identity key as [_cachedColumnsRoster] above.
  List<SalonMasterSummary>? _cachedOptionsRoster;
  List<MasterFilterOption> _cachedOptions = const <MasterFilterOption>[];

  List<MasterFilterOption> _masterFilterOptions() {
    if (identical(_cachedOptionsRoster, _roster)) return _cachedOptions;
    _cachedOptionsRoster = _roster;
    _cachedOptions = <MasterFilterOption>[
      for (final SalonMasterSummary m in _roster)
        // The SAME joined display name the roster chip above the column shows
        // (`columnsFor`'s `MasterColumnEntry.name`), so the owner ticks the
        // name they just read off the board.
        MasterFilterOption(
          id: m.masterId,
          name: '${m.firstName} ${m.lastName}'.trim(),
        ),
    ];
    return _cachedOptions;
  }

  /// The `boardWindowBuilder:` the view calls back into.
  ///
  /// NOT memoised, deliberately: its result is consumed as two plain `int`s
  /// (`scheduleFirstMinute` / `scheduleWindowEndMinute`) which the grid's gate
  /// compares BY VALUE, so a fresh `ScheduleTimelineWindow` instance costs
  /// nothing downstream. It is a tear-off only so this screen has one rule for
  /// all three callbacks rather than two.
  ScheduleTimelineWindow? _boardWindowFor(
    List<Booking> dayItems,
    DateTime day,
  ) => SalonBookingsScreen.boardWindowFor(dayItems, day, _rosterSchedule);

  /// Opens the booking the owner tapped.
  ///
  /// A named method, NOT an inline closure — see this class's doc. It is the
  /// identity `_BoardStack.didUpdateWidget` compares, and a fresh closure per
  /// build resets that widget's whole built-column cache.
  ///
  /// `RouteNames.salonStaffBookingDetail` — `/salon/bookings/:id`.
  ///
  /// ⚠ THE SCREEN AND THE DESTINATION SIT UNDER DIFFERENT PREFIXES, and
  /// only the destination inherits a prefix gate (audit L7 — this note
  /// used to claim the screen itself "mounts under `/salon/*`", which
  /// would have a reader believe a second role gate applies here that
  /// does not). THIS screen is slot 1 of [SalonShellScreen] at
  /// `RouteNames.salonShell` = `/salons/:salonId/shell` — no path segment
  /// of its own, and `/salons/*` is NOT one of `auth_redirect.dart`'s
  /// role-gated prefixes. Its only router-level gate is
  /// `salonManageGuard`, which deliberately ADMITS an owner whose
  /// `mySalonsProvider` has not resolved — which is why `build` below
  /// binds ownership with `canManageSalonProvider` itself.
  ///
  /// ⚠ NOT `RouteNames.bookingDetail`. That resolves to `/bookings/:id`,
  /// and `/bookings` is a CLIENT branch prefix in `auth_redirect.dart`:
  /// every non-CLIENT role that reaches it is redirected to
  /// `roleHomePath(role)`. An owner tapping a card on their own board was
  /// bounced clean out of the salon shell to the owner home and never saw
  /// a detail screen at all. NOT `masterBookingDetail` either —
  /// `/master/*` is INDEPENDENT_MASTER-only.
  ///
  /// The destination is the SAME [BookingDetailScreen] all three paths
  /// render; only the prefix (and therefore the role gate it inherits)
  /// differs. It role-branches its own provider actions — including
  /// «Скасувати запис» → the decline endpoint — off
  /// `bookingViewerRoleProvider`. See the file header.
  void _onBookingTap(Booking booking) {
    context.push(RouteNames.salonStaffBookingDetail(booking.id));
  }

  /// Phase 21.12 — THE PLACEHOLDER. The «+» control renders in its final
  /// position and styling so the header's layout is settled and never has to
  /// reflow when the flow lands; tapping it does nothing, on purpose.
  ///
  /// ⚠ THIS IS THE ONE LINE TO REPLACE. Everything the wire-up needs already
  /// exists and none of it is new work:
  ///   * `bookingCreationEnabledProvider`
  ///     (`features/booking/application/bookings_capability.dart`, phase 328)
  ///     already resolves `true` for SALON_OWNER and SALON_ADMIN and `false`
  ///     for everyone else — it is the role gate, already written;
  ///   * the SALON walk-in wizard already ships (phases 250–251) — the same
  ///     Appointment + N-Bookings visit shape as the client flow;
  /// so the follow-up is a `context.push(<that route>)` in THIS METHOD BODY,
  /// and nothing else. The `canCreateBooking:` half is already done (audit
  /// M5): it reads `bookingCreationEnabledProvider` rather than a hardcoded
  /// `true`, so filling this body in cannot accidentally ship an ungated
  /// create affordance.
  ///
  /// Deliberately NOT wired now (locked by the user this phase). And the
  /// capability it is gated on resolves `true` for both roles that can reach
  /// this screen, so the button still RENDERS — a hidden one would make the
  /// header narrower today and wider later, which is the reflow this
  /// placeholder exists to avoid.
  void _openCreateBooking() {
    // TODO(phase-21.12-followup): push the salon walk-in wizard here. No-op
    // by design until then — see this method's doc.
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    // ── OWNERSHIP (audit M3, 2026-09-16) ─────────────────────────────────
    // `salonManageGuard` (`app_router.dart`) is NOT sufficient on its own and
    // says so in its own comment: for a `SALON_OWNER` whose `mySalonsProvider`
    // has not yet resolved to `AsyncData` it deliberately ADMITS, leaving the
    // backend as the real boundary. That is fine for the surfaces it guards,
    // whose every fetch is authorized — but THIS screen also mounts the salon
    // ROSTER, and `GET /salons/{id}/masters` is PUBLIC. In the admit window
    // with a foreign `salonId` the bookings fetch correctly 403s while the
    // roster strip renders a stranger's team as if it were the owner's.
    //
    // `canManageSalonProvider` is the repo's fail-CLOSED predicate (it reads
    // the STRICT settled selector and resolves `false` in exactly that window)
    // and is what every other salon-scoped surface consumes — see
    // `_SalonManageServiceSetupRoute` and siblings in `app_router.dart`. The
    // denied rendering is the SAME shared [ErrorState] + [UnauthorizedFailure]
    // those siblings show, not a second spelling of "not yours".
    if (!ref.watch(canManageSalonProvider(widget.salonId))) {
      return const Scaffold(
        key: Key('salon-bookings-screen'),
        backgroundColor: BrandColors.base,
        body: ErrorState(
          key: Key('salon-bookings-denied'),
          failure: UnauthorizedFailure(),
        ),
      );
    }

    // The roster. While it RESOLVES the board renders with ZERO columns, which
    // is the same shape as a salon with no masters and already has a state of
    // its own. Routing the whole screen through a second loading branch would
    // hide the day rail and the header the owner navigates with, for a fetch
    // that is usually already warm (the shell's own «Команда» tab and the
    // salon walk-in wizard both mount it).
    //
    // A FAILURE is a different matter (audit M4): `.value ?? const []` folded
    // an `AsyncError` into "this salon employs nobody" — a 403 or a 500 on the
    // roster rendered as a statement about the owner's team. Matched on the
    // CONCRETE `AsyncError` subtype, never `hasError`: an
    // `AsyncLoading(retrying: true)` carrying a previous error satisfies
    // `hasError` and must keep showing the board, not an error panel.
    final AsyncValue<List<SalonMasterSummary>> rosterState = ref.watch(
      salonMastersRosterProvider(widget.salonId),
    );
    // The salon's own name, under the heading — an owner of several salons
    // must be able to tell whose board this is. `null` while it RESOLVES
    // renders no subtitle line at all rather than a placeholder that would
    // reflow; a FAILURE surfaces, for the same M4 reason as the roster (the
    // profile fetch is the second ownership-sensitive call this screen makes,
    // and a silently missing subtitle is how a 403 on it used to read).
    final AsyncValue<SalonManagementProfileData> profileState = ref.watch(
      salonManagementProfileProvider(widget.salonId),
    );

    final Object? fetchError = switch ((rosterState, profileState)) {
      (AsyncError(:final Object error), _) => error,
      (_, AsyncError(:final Object error)) => error,
      _ => null,
    };
    if (fetchError != null) {
      return Scaffold(
        key: const Key('salon-bookings-screen'),
        backgroundColor: BrandColors.base,
        // REUSED, not re-invented: the exact panel the day fetch inside
        // [BookingsDiscoveryView] already shows for its own failure, so an
        // owner sees one error affordance on this board regardless of which of
        // its three fetches failed. Retry re-arms BOTH — the two resolve
        // together on a cold mount and a partial retry would leave the other
        // half stale.
        body: MyBookingsErrorState(
          error: fetchError,
          onRetry: () {
            ref.invalidate(salonMastersRosterProvider(widget.salonId));
            ref.invalidate(salonManagementProfileProvider(widget.salonId));
          },
        ),
      );
    }

    // Stashed on the state, NOT closed over (mobile-perf MEDIUM ×2,
    // 2026-09-17): [_columnsFor] / [_boardWindowFor] are handed to
    // `BookingsDiscoveryView` as TEAR-OFFS so their identity survives a
    // rebuild, which means they cannot be closures over these two locals and
    // must read them from here instead. Writing a field from `build` is a
    // side effect, and a deliberate one — the same shape as
    // `_BookingsDiscoveryViewState._visibleBookingsFor`'s cache writes. It is
    // safe because the callbacks only ever fire from a DESCENDANT's build,
    // which is strictly after this method returns, and any change to either
    // value rebuilds this screen first (both come from a `ref.watch` above).
    _roster = rosterState.value ?? const <SalonMasterSummary>[];
    final String? salonName = profileState.value?.$1.name;

    // ── THE BOARD'S WORKING-HOURS WINDOW (Phase 335) ─────────────────────
    // One request per MONTH, not per day: the batch route fans out across the
    // whole roster, so a per-day key would fire a roster-wide fan-out on every
    // rail chip tap. `ScheduleRange.month` covers every day the rail can reach
    // in one fetch.
    //
    // ⚠ THE MONTH IS KYIV-TODAY'S, NOT THE SELECTED DAY'S. This screen cannot
    // see the selected day — `BookingsDiscoveryView` owns it deliberately (see
    // its "the day is NOT read from query" section) and exposes no
    // day-changed callback. Paging the board into a DIFFERENT month therefore
    // finds no [EffectiveDay] for that date, [boardWindowFor] returns `null`,
    // and the timeline falls back to the booking-derived window — the same
    // graceful degradation as a failed fetch, never a wrong window and never a
    // dropped booking. Widening this to follow the selection needs an
    // additive `onDayChanged` seam on the view; it is a follow-up, not a
    // silent gap.
    //
    // ── WHY THIS FETCH IS NOT IN THE `fetchError` GATE ABOVE ─────────────
    // The roster and the salon profile are STRUCTURAL: without them there are
    // no columns and no title, so a failure there is an error state (audit
    // M4). The schedule is ADORNMENT: it moves the timeline's top and bottom
    // and nothing else. A board showing today's real bookings against a
    // booking-derived window is completely usable; an error panel in its place
    // is not. So a schedule failure degrades silently and DELIBERATELY. Do not
    // "fix" this by folding it into `fetchError`.
    //
    // `.value`, never a `hasError` branch — an `AsyncLoading(retrying: true)`
    // carrying a previous error satisfies `hasError` while still holding a
    // perfectly good previous window, and `.value` keeps rendering it.
    // See [_roster]'s assignment above for why this is a field write.
    _rosterSchedule = ref
        .watch(
          salonEffectiveScheduleProvider(
            widget.salonId,
            // `kyivToday(clock)`, never a bare `DateTime.now()` — the device
            // supplies the INSTANT, Kyiv decides the DAY (and therefore the
            // month). `watch`, not `read`: a session that crosses Kyiv
            // midnight must re-key onto the new month.
            ScheduleRange.month(kyivToday(ref.watch(clockProvider))),
          ),
        )
        .value;

    return Scaffold(
      key: const Key('salon-bookings-screen'),
      backgroundColor: BrandColors.base,
      body: BookingsDiscoveryView(
        // The SCOPE travels on the seed query — see this file's header and
        // `BookingsDiscoveryView._rebuildQuery`. Kyiv-anchored via
        // `kyivToday(clock)` like every other seed in the app, even though the
        // view re-derives the day itself (`bookings_discovery_view.dart`'s
        // "the day is NOT read from query"): a reader copying this call site
        // learns the right pattern rather than a bare `DateTime.now()`.
        //
        // NO seed statuses — an empty seed means "the owner has chosen no
        // filter", which `BookingsDiscoveryView._rebuildQuery` resolves to
        // `BookingStatus.visibleInDayListByDefault` (CANCELLED and DECLINED
        // hidden, NOT_COMPLETED kept — locked 2026-08-13), the same default the
        // master's own board opens on.
        //
        // ⚠ `.salonOf`, NOT `.salonDayList` — the twin of the master board's
        // own `BookingsDayQuery.of`, and for the same reason. `.salonDayList`
        // RESOLVES the selection through `BookingStatus.dayListWireStatuses`,
        // so an empty seed came back out of it as the WIRE set
        // {CONFIRMED, COMPLETED, NOT_COMPLETED} — which the view then read
        // into `_statuses` as though the owner had picked it, opening the
        // filter sheet with «Підтверджено» and «Виконано» already ticked and
        // lighting the funnel badge on an untouched board. `_statuses`' own
        // doc forbids exactly that ("must never hold an already-resolved wire
        // set"): the mapping is NOT idempotent and belongs solely to
        // `_rebuildQuery`, which applies it once. The resolved wire set is
        // unchanged either way — {} and {CONFIRMED, COMPLETED, NOT_COMPLETED}
        // both resolve to `visibleInDayListByDefault` — so no list's content
        // moves; only the sheet's ticks and the badge do.
        query: BookingsDayQuery.salonOf(
          day: kyivToday(ref.read(clockProvider)),
          salonId: widget.salonId,
        ),
        title: l10n.salonBookingsTitle,
        subtitle: salonName,
        // A bottom-nav destination inside the salon shell — nothing to pop.
        onBack: null,
        // 2026-09-18 — the «Майстер» section, ON. Multi-select and
        // CLIENT-SIDE: nothing below changes the request, and
        // `BookingsDayQuery.salon.masterId` stays `null`. See this file's
        // header item 4b for the decision it reverses.
        showMasterFilter: true,
        // The option universe — the roster this screen already fetched for its
        // columns, so the section costs no request. Memoised on the roster's
        // identity (see [_masterFilterOptions]); an EMPTY roster renders no
        // section at all, so a cold mount never shows an empty heading.
        masterFilterOptions: _masterFilterOptions(),
        // STILL FALSE, and Phase 335 did NOT change that — read this before
        // "finishing the job" by flipping it. `useScheduleWindow` is not just
        // "bound the grid by hours": it also swaps the whole timeline for
        // `MasterBookingsNoWorkingHoursState` on an hours-less day (which on a
        // manager's board would HIDE a real walk-in) and routes EXPLICIT_TIMES
        // days onto a single master's declared-times card list (which has no
        // meaning across a roster). The bounds this board wanted arrive
        // through the additive `boardWindowBuilder` below instead, which
        // brings neither behaviour with it.
        useScheduleWindow: false,
        // An owner has no master service catalogue of their own, so the
        // «Послуга» section would filter against an empty universe — and
        // warming it would be a wasted request on every mount.
        showServiceFilter: false,
        // Backend Phase 319 shipped `GET /bookings/salon/{salonId}/booked-
        // days`, so the rail's dots are now this SALON's days.
        // `BookingsDiscoveryView` picks the endpoint off the seed query's
        // sealed member — this flag only says "fetch them at all". See
        // [BookingsDiscoveryView.showBookedDayDots].
        showBookedDayDots: true,
        // The salon board has no «Архів» page of its own yet.
        onOpenArchive: null,
        // Phase 336 — the builder receives the SELECTED day (the same one
        // `boardWindowBuilder` below gets), which is what lets a master who is
        // not working it render as a greyed «Вихідний» column instead of an
        // empty one indistinguishable from «Вільний день». See [masterDayOff]
        // for the predicate and for the three unknowns it refuses to guess at.
        //
        // A TEAR-OFF, never an inline closure (mobile-perf MEDIUM ×2,
        // 2026-09-17). [_SalonBookingsScreenState._columnsFor] memoises
        // [columnsFor]'s result on its complete input set, so
        // `_Loaded._body`'s `columnsBuilder?.call(items, day)` hands the grid
        // the SAME `List` instance across a rebuild that changed nothing —
        // which is the only thing that lets `BookingsTimelineGrid`'s
        // `!identical(widget.columns, oldWidget.columns)` gate (and
        // `_BoardStack`'s built-column cache behind it) short-circuit at all.
        // Both had been dead on this route since they shipped. See the state
        // class's doc for the measurement and for why this is AND-gated with
        // `onBookingTap:` below — fixing either alone changes nothing.
        columnsBuilder: _columnsFor,
        // Phase 335 — the timeline spans every master's hours, not just the
        // day's bookings. See [boardWindowFor], and the union's vacuity proof
        // in `schedule_timeline_window.dart`: this must never be a window that
        // excludes a booking.
        boardWindowBuilder: _boardWindowFor,
        // The (+) renders; its handler is the documented no-op.
        //
        // Audit M5 — the capability, never a hardcoded `true`. The sibling
        // call site (`master_bookings_screen.dart`) already does exactly this,
        // and a literal here armed an UNGATED create affordance for the moment
        // [_openCreateBooking]'s body is filled in. `watch`, not `read`: the
        // capability is derived from the session and must re-render the header
        // the moment the role settles. A zero-behaviour-change edit TODAY —
        // `bookingCreationEnabledProvider` already resolves `true` for both
        // roles that can reach this screen — which is precisely why it is the
        // right time to make it.
        canCreateBooking: ref.watch(bookingCreationEnabledProvider),
        onCreateBooking: _openCreateBooking,
        // A TEAR-OFF, never an inline closure — the identity
        // `_BoardStack.didUpdateWidget` compares with
        // `oldWidget.onBookingTap != widget.onBookingTap`. A fresh closure
        // per build made that permanently true and reset the whole
        // built-column cache. The route reasoning (and the two routes this
        // deliberately is NOT) lives on [_SalonBookingsScreenState._onBookingTap].
        onBookingTap: _onBookingTap,
      ),
    );
  }
}
