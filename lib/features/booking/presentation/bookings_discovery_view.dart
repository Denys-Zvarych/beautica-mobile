// Phase 7.11 — BookingsDiscoveryView: the shared «Записи» composition — day
// rail, timeline body, states — factored out of `master_bookings_screen.dart`
// so the salon-wide screen can drop it in later WITHOUT a rewrite.
//
// ## The reuse seam, honoured
//
// The approved design already factors this split (`docs/signup-designs/
// SalonManagementDesign/lib/screens/my_bookings_screen.dart` is a THIN
// wrapper over `BookingsDiscoveryScreen`, passing `showMasterFilter: false`;
// `bookings_toolbar.dart:1053-1094`'s `_CountToolbar` renders the teammate
// filter icon conditionally on that flag). This file mirrors it: three
// injection points, and only three —
//
//   1. [query] — the scope AND the seed filters, a [BookingsDayQuery] (Phase
//      7.9's sealed union). Today only `.masterOwn`; the salon phase adds
//      `.salon(...)` and `bookingsDayProvider` dispatches on the member. This
//      view never branches on scope — it reads [BookingsDayQuery.statuses] /
//      [BookingsDayQuery.serviceIds] off whatever member it was handed and
//      rebuilds through [BookingsDayQuery.of] on every change, which works
//      identically for either member because `.of()` is scope-agnostic.
//   2. [showMasterFilter] + [masterFilterOptions] — the teammate («Майстер»)
//      filter section. `true` on the SALON BOARD since 2026-09-18 and `false`
//      on both master routes, forever. The old rule ("false at every call
//      site, because the endpoint takes exactly ONE `masterId` while the
//      sheet is multi-select") was reversed by the user with the answer that
//      dissolves it: the section is multi-select AND CLIENT-SIDE, so nothing
//      about it reaches the wire and the endpoint's limit is irrelevant. The
//      board keeps its side-by-side shape; it simply draws fewer columns. See
//      [masterFilterOptions] for the whole mechanism.
//   2b. [columnsBuilder] — Phase 21.12, and the ACTUAL scope switch. `null`
//      (the default, and both master routes) keeps the single-master
//      overlap-lane timeline. Non-null turns the SAME
//      [BookingsTimelineGrid] into the salon master-column board and selects
//      [TimelineDensity.salon] for it — derived, never a separate parameter,
//      so a caller cannot hand in columns at master density.
//   3. [onBookingTap] — navigation is the HOST's concern, keeping this widget
//      route-agnostic. No `Navigator`/`context.push` anywhere in this file.
//
// ## The day is NOT read from [query] — it is owned here, in Kyiv
//
// [query]'s own `day` field is deliberately NOT used as the initial
// selection. This view OWNS the selected day (locked decision — Phase
// 7.11's Step 1), and the day it opens on is `dateOnly(toBeauticaTime(
// DateTime.now()))` — Kyiv "today", not host "today" and not whatever `day`
// the caller happened to stamp on its seed query (the thin wrapper has no
// principled way to know Kyiv-today at construction time without doing this
// same derivation itself, so centralising it here is both correct AND the
// only single source of truth). [query]'s `statuses`/`serviceIds` DO seed
// this view's filter state — that half of "the scope AND the filters" is
// real.
//
// ## No more «Всі» / range mode
//
// `BookingsDayQuery` (Phase 7.9) carries exactly one Kyiv day — there is no
// all-days or range concept left to express. So:
//   * Exactly one day is selected at all times, including on first open.
//   * If today has no bookings, TODAY STAYS SELECTED — no auto-jump to the
//     nearest booked day. The master's overwhelmingly common intent is
//     "what's on today"; a silent jump makes an empty day indistinguishable
//     from a navigation bug. The dots (`bookedDaysProvider`, unchanged, still
//     filter-independent) show where the work actually is.
//   * `BookingsFilterSheet`'s «Дата» section (Phase 7.7) is RETIRED too
//     (Phase 7.13) — the sheet now resolves only `statuses`/`serviceIds`, so
//     there is nothing date-shaped left for `_applyFilters` to discard.
//
// ## Phase 7.16 — the calendar jump is retired; day selection is by scroll
//
// The rail's calendar button (`_openCalendar`, opening `bookings_day_picker
// .dart`'s `showBookingsDayPicker`) is gone — judged redundant once the month
// switcher's prev/next and «Сьогодні» (`bc08986`) already covered the
// long-distance jumps a single-day picker used to exist for.
// `showBookingsDayPicker` and its widget were deleted outright rather than
// left as dead UI code — this button was their only production call site.
// The Варіант D port (see `widgets/bookings_month_calendar_panel.dart`)
// later replaced that month switcher with the expandable calendar itself,
// which is a strictly BIGGER long-distance-jump affordance than the
// switcher it replaced — so this retirement still stands. [_selectDay]/
// [_applySelectedDay] are unaffected: a rail-chip tap, a grid-cell tap, a
// resolved month step, and «Сьогодні» are now the only ways [_day] changes,
// and all of them funnel through the same single mutation path
// ([_applySelectedDay], via [_selectDay]'s debounce or [_selectImmediate]).
//
// ## Two horizontal pagers (user-requested rework, this session)
//
// The rail is now a Mon→Sun WEEK pager and the expanded grid a MONTH pager;
// the grid's ‹ › chevrons are retired and the panel's month+year label is
// permanent. The list of things that change [_day] is UNCHANGED by that —
// only the gesture that produces a "month step" is different. The contract
// keeping the two pagers, the label and the query in agreement is written
// out in full on [_BookingsDiscoveryViewState._selectDay]; read it before
// touching either pager.
//
// ## CANCELLED/DECLINED are hidden by default — on the WIRE, not after
//
// Locked product decision (2026-08-13): a provider's day list opens showing
// only live work. Two sets, deliberately kept apart:
//
//   * `_statuses` — the MASTER's selection. Empty until they tick a group in
//     the filter sheet. Drives `_activeFilterCount` (so an untouched screen
//     shows NO funnel badge) and `_hasUserFilters` (so an empty day still
//     reads «Немає записів», not «…за цим фільтром»).
//   * the WIRE set — what `_rebuildQuery` puts on the query, resolved from
//     `_statuses` by `BookingStatus.dayListWireStatuses` inside
//     `BookingsDayQuery.dayList`. Empty selection →
//     `BookingStatus.visibleInDayListByDefault` (= `filterable` − {CANCELLED,
//     DECLINED}); every group ticked → the EMPTY set, which omits `status`
//     from the request entirely so a status the backend gained after this
//     build shipped is still reachable (it would otherwise be excluded by the
//     server's `status IN (...)` even under "select all"); anything else →
//     `_statuses` verbatim, so ticking «Скасовані» sends exactly CANCELLED +
//     DECLINED and they re-appear.
//
// The mapping is NOT idempotent and is applied exactly once, at query
// construction — the `State` holds the raw selection and never a wire set.
// `BookingsDayQuery.dayList` is also what the two post-write invalidation
// sites build through (`booking_calendar_invalidation.dart`,
// `booking_confirm_screen.dart`), so they target the member this screen
// actually watches; see that factory's doc for the stale-data bug that came
// of them drifting apart.
//
// NOT_COMPLETED stays visible — it is the master's own no-show record and it
// feeds the two-sided client rating.
//
// Server-side is load-bearing, not a preference: `BookingsDayNotifier` fetches
// the day in ONE `size: 100` request with no paging, so cancelled rows
// consuming that budget could silently truncate live ones. Every downstream
// consumer — the header count, `BookingsTimelineGrid`, `DeclaredTimeCards` —
// reads `state.items`/`state.totalElements`, which are now the SERVER's
// already-narrowed list and count, so all of them agree by construction with
// no per-branch filtering added anywhere.
//
// `booking_lane_layout.dart`'s pass 2 (cancelled-vs-replacement overlap) is
// therefore unexercised by DEFAULT but still fully live whenever the filter
// re-shows cancelled bookings. Do not delete it, do not collapse it to a
// single pass.
//
// ## Read the async value with `.asData?.value`, never `value == null`
//
// Riverpod's `ref.invalidate` retains the previous `.value` through the next
// `AsyncLoading`/`AsyncError` (seamless reload) — a `value == null` check
// never fires and silently stops detecting anything. This view avoids the
// whole hazard for the day-scoped fetch by dispatching on `.when()`, which
// never inspects `.value` directly; the one place that reads a retained value
// on purpose (`masterServiceCatalogProvider` in `_applyFilters`, mirroring
// the retired screen's S1 audit fix) uses `.asData?.value` explicitly.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/api_date.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';

import '../application/booked_days_notifier.dart';
import '../application/bookings_day_notifier.dart';
import 'package:beautica_mobile/features/services/data/master_service_catalog_provider.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/schedule/application/own_schedule_scope.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/features/schedule/presentation/effective_schedule_notifier.dart';
import 'package:beautica_mobile/features/schedule/presentation/schedule_range.dart';

import '../domain/booking.dart';
import '../domain/booking_status.dart';
import '../domain/bookings_day_query.dart';
import '../domain/bookings_day_state.dart';
import 'widgets/bookings_day_rail.dart';
import 'widgets/bookings_filter_sheet.dart';
import 'widgets/bookings_month_calendar_panel.dart';
import 'widgets/bookings_timeline_grid.dart';
import 'widgets/timeline_density.dart';
import 'widgets/declared_time_cards.dart';
import 'widgets/master_bookings_states.dart';
import 'widgets/my_bookings_states.dart';
import 'widgets/schedule_timeline_window.dart';

/// The sheet's OWN status coverage, not `BookingStatus.filterable`'s default
/// — computed from `BookingStatusFilterGroup.values` so the two can never
/// drift apart (2026-08-15: the sheet dropped its NOT_COMPLETED row). Passed
/// as `_rebuildQuery`'s `maximalStatuses`; see that method's doc for why the
/// distinction matters.
///
/// Hoisted to a module-level constant (mobile-perf, this session):
/// `_rebuildQuery` runs on every filter/day/service mutation, and the
/// comprehension below was being re-evaluated — a fresh `Set` allocated —
/// on each of those calls. `BookingStatusFilterGroup.values` never changes
/// at runtime, so the set only needs building once.
///
/// DELIBERATELY still ENUM-DERIVED, not flattened into a literal —
/// flattening would reintroduce the exact drift this expression exists to
/// prevent: whoever adds or retires a filter group would have to remember to
/// hand-edit a second, unrelated set. Keep the comprehension; only the
/// allocation is hoisted.
final Set<BookingStatus> _kMaximalFilterStatuses = <BookingStatus>{
  for (final BookingStatusFilterGroup g in BookingStatusFilterGroup.values)
    ...g.statuses,
};

/// The timeline column's LEFT screen inset — deliberately HALF the
/// `VelvetSpacing.lg` (24) used everywhere else on this screen, so the hour
/// ruler sits closer to the screen edge and the lane area reclaims 12dp.
///
/// WHY: the horizontal chrome budget before a card could start was
/// `24 (screen pad L) + 42 (TimelineHourRuler._kRulerWidth) + 4
/// (VelvetSpacing.xs, the ruler↔grid gap)` = 70dp. On the 360dp Android
/// baseline that left only 266dp of lane area against
/// `BookingsTimelineGrid._kCardW` (272), so ADDENDUM 3's
/// `math.min(_kCardW, constraints.maxWidth)` clamped the card DOWN by 6dp on
/// the single most common device. At 12dp the lane area becomes 278dp and the
/// leading card renders at its full natural 272dp on 360dp for the first
/// time. See "ADDENDUM 3" in `widgets/bookings_timeline_grid.dart` — its
/// arithmetic is stated there and kept in sync with this constant.
///
/// APPLIES TO THE TIMELINE-GRID BRANCH ONLY. `DeclaredTimeCards` (the
/// EXPLICIT_TIMES day) has NO ruler gutter — its cards start flush at the
/// padding edge, so moving it left would misalign it with the day header
/// (`masterBookingsCount`, 24dp) and `MasterBookingsTruncatedNotice` (24dp
/// margin). The grid is safe precisely because 12 + 42 + 4 = 58dp still puts
/// its first card comfortably right of the 24dp header.
///
/// Do NOT "fix" this by shrinking `TimelineHourRuler._kRulerWidth` (42) —
/// that would break "23:00" at 11sp, and worse at accessibility text scales.
/// The ruler keeps its width; only the column's left offset moves.
const double _kTimelineLeftInset = VelvetSpacing.sm + VelvetSpacing.xs; // 12

/// The two body insets, hoisted WHOLE rather than selected term-by-term.
///
/// Both branches differ only in the left term, so the tempting spelling is one
/// `EdgeInsets.fromLTRB(cond ? a : b, …)`. That silently drops `const`: a
/// ternary is not a constant expression, so the whole `EdgeInsets` becomes a
/// per-`build` allocation. Selecting between two fully-const insets keeps the
/// canonicalised instances and makes the rebuild a pointer choice.
const EdgeInsets _kTimelineBodyPadding = EdgeInsets.fromLTRB(
  _kTimelineLeftInset,
  0,
  VelvetSpacing.lg,
  VelvetSpacing.xxl,
);
const EdgeInsets _kDeclaredBodyPadding = EdgeInsets.fromLTRB(
  VelvetSpacing.lg,
  0,
  VelvetSpacing.lg,
  VelvetSpacing.xxl,
);

/// Phase 21.12 — the SALON board's body inset: [_kTimelineLeftInset] on BOTH
/// sides, where the master timeline keeps `VelvetSpacing.lg` (24) on the
/// right.
///
/// WHY THE RIGHT EDGE MOVES ONLY HERE. On the master timeline the lane area
/// holds ONE card and a 24dp right gutter is ordinary page rhythm. The salon
/// board scrolls horizontally through master columns, so 24dp of dead space at
/// the right edge is 24dp fewer of the NEXT column — and the partially-visible
/// next column IS the scroll affordance. At the 360dp baseline the 12dp inset
/// is what makes `TimelineDensity.columnWidth`'s two-column arithmetic land on
/// 148dp (see that method's worked example); at 24dp it would be 142dp, still
/// two columns but with the affordance eaten. Unchanged on both master routes,
/// which never select this constant.
const EdgeInsets _kBoardBodyPadding = EdgeInsets.fromLTRB(
  _kTimelineLeftInset,
  0,
  _kTimelineLeftInset,
  VelvetSpacing.xxl,
);

/// The shared «Записи» discovery composition: header, count toolbar, day
/// rail, timeline body, and the four async states. Parameterised over scope
/// so the salon-wide screen can reuse it verbatim — see the file header.
class BookingsDiscoveryView extends ConsumerStatefulWidget {
  const BookingsDiscoveryView({
    required this.query,
    required this.title,
    this.onBack,
    this.showMasterFilter = false,
    this.masterFilterOptions = const <MasterFilterOption>[],
    this.useScheduleWindow = false,
    this.onAddWorkingHours,
    required this.onBookingTap,
    this.onOpenArchive,
    this.canCreateBooking = true,
    this.canAddWorkingHours = true,
    this.subtitle,
    this.columnsBuilder,
    this.boardWindowBuilder,
    this.onCreateBooking,
    this.showServiceFilter = true,
    this.showBookedDayDots = true,
    super.key,
  }) : assert(
         !useScheduleWindow || !canAddWorkingHours || onAddWorkingHours != null,
         'onAddWorkingHours is required whenever useScheduleWindow is true '
         'AND canAddWorkingHours is true — the "no working hours" empty '
         'state always needs somewhere to route the CTA it is offering.',
       );

  /// The scope AND the seed filters — see the file header for exactly which
  /// half of this is actually used as a seed (statuses/serviceIds) versus
  /// re-derived (the day).
  final BookingsDayQuery query;

  final String title;

  /// Phase 21.12 — a muted second line under [title]. `null` (the default, and
  /// both master routes) renders NOTHING at all, not an empty line: the header
  /// keeps its exact current height and the `Row` its exact current children.
  /// Only the salon board passes one — the salon's own name, so an owner of
  /// several salons can tell whose board this is without leaving it.
  final String? subtitle;

  /// The back affordance. `null` on a bottom-nav tab root (the master's own
  /// screen); non-null returns to a host shell's home tab.
  final VoidCallback? onBack;

  /// Whether the teammate («Майстер») filter section is offered.
  ///
  /// `false` (the DEFAULT, and both master routes, forever) is byte-for-byte
  /// the pre-2026-09-18 behaviour: [_masterIds] is pinned empty, the sheet is
  /// handed no roster so it renders no section, and [_activeFilterCount] can
  /// never count a master group. A single master's own list — and the master's
  /// own «Архів», which shows this sheet directly — never offers it.
  ///
  /// `true` only on `SalonBookingsScreen`, which also supplies
  /// [masterFilterOptions]. The two are ANDed: `true` with an empty roster
  /// (a cold mount, a salon with no masters) still renders no section, so the
  /// flag can never produce an empty heading.
  final bool showMasterFilter;

  /// ═══════════════════════════════════════════════════════════════════════
  /// 2026-09-18 — THE «Майстер» FILTER'S OPTION UNIVERSE
  /// ═══════════════════════════════════════════════════════════════════════
  /// The masters the sheet may offer, supplied by the HOST for exactly
  /// [columnsBuilder]'s reason: this view owns the day and the fetch, the host
  /// owns "which masters exist". `SalonBookingsScreen` passes its already-
  /// fetched roster — the SAME `salonMastersRosterProvider` list that builds
  /// the board's columns — so the section adds no request of its own.
  ///
  /// EMPTY (the default, and both master routes) renders no section.
  ///
  /// ## WHERE THE SELECTION IS APPLIED — NOT HERE, AND NOT ON THE WIRE
  ///
  /// This view stores the ticked ids ([_masterIds]) and hands them to
  /// [columnsBuilder] as its third argument. It does NOT filter
  /// [BookingsDayState.items] itself and it does NOT put them on
  /// [BookingsDayQuery] — `SalonDayQuery.masterId` is untouched by this
  /// feature and stays `null`. Two consequences worth knowing:
  ///
  ///   * the board keeps its side-by-side shape (locked user decision);
  ///     ticking two masters draws two columns, not a collapsed single-master
  ///     timeline.
  ///   * the header's «N записів» count already recomputes from the COLUMNS
  ///     whenever [columnsBuilder] is non-null (see [_Loaded._body]), so it
  ///     narrows with the filter for free and cannot disagree with the cards
  ///     on screen.
  ///
  /// ## THE HIGHLIGHT IS NOT THE FILTER
  ///
  /// [_selectedMasterId] (a roster-chip tap) stays completely independent: the
  /// filter never changes it and it never changes the filter. A highlighted
  /// master who is then filtered out simply has no chip to carry the highlight
  /// — `MasterColumnStrip` draws the selected border on that chip ALONE and
  /// dims nothing else, so an off-screen highlight is inert rather than a
  /// board where every column looks deselected. Re-ticking that master brings
  /// the highlight back exactly where it was.
  final List<MasterFilterOption> masterFilterOptions;

  /// ═══════════════════════════════════════════════════════════════════════
  /// WORKING-HOURS WINDOW (the master's own booking timeline only)
  /// ═══════════════════════════════════════════════════════════════════════
  /// Whether the timeline's vertical bounds come from the master's WORKING
  /// HOURS for the selected day (via `effectiveScheduleProvider`) instead of
  /// from the day's bookings, and whether a day with NO working hours
  /// replaces the timeline with [MasterBookingsNoWorkingHoursState].
  ///
  /// `false` (the default, and every OTHER call site — the reuse-seam test
  /// included) keeps this view's ORIGINAL behaviour byte-for-byte: the
  /// booking-derived window `BookingsTimelineGrid` has always used, and no
  /// dependency on `effectiveScheduleProvider` at all (the provider is never
  /// even watched). Set `true` ONLY by `MasterBookingsScreen` — a single
  /// independent master's own list is the one scope where "which hours does
  /// THIS person work" is unambiguous; a future salon-wide consumer (the
  /// `showMasterFilter` reuse seam) would need its own per-teammate answer to
  /// that question before ever setting this `true`, so it stays `false` there
  /// until that is built. See `_Loaded` for the branching this drives.
  final bool useScheduleWindow;

  /// Required whenever [useScheduleWindow] is `true` (see the constructor
  /// assert) — the "no working hours" empty state's CTA fires this with the
  /// selected day so the HOST can route to the schedule editor with that date
  /// pre-selected. Navigation stays the host's concern, same as
  /// [onBookingTap]/[onBack] — no `context.go`/`context.push` in this file.
  final ValueChanged<DateTime>? onAddWorkingHours;

  /// Fires with the tapped booking. Navigation is the HOST's concern — no
  /// `Navigator`/`context.push` anywhere in this widget.
  final ValueChanged<Booking> onBookingTap;

  /// Phase 231 — fires when the header's archive button is tapped. `null`
  /// (the default) hides the button entirely; only `master_bookings_screen
  /// .dart` passes a non-null callback (`context.push(RouteNames
  /// .masterBookingsArchive)`). ADDITIVE ONLY — see this file's own
  /// "touch it as little as possible" constraint for this phase; no other
  /// header behaviour changed. Navigation is the HOST's concern, same as
  /// [onBookingTap]/[onBack] — no `Navigator`/`context.push` in this file.
  final VoidCallback? onOpenArchive;

  /// Phase 329 — whether the header's manual add-booking (+) button is
  /// rendered at all. `false` makes it ABSENT, not disabled: the invited
  /// `SALON_MASTER` this track's read-only «Записи» exists for must not see a
  /// write affordance they can never use (the same user-locked ruling that
  /// removed the permanently-disabled «Перенести» button in
  /// `booking_detail_screen.dart`'s `_providerActions`).
  ///
  /// ADDITIVE, defaulting to `true` — every pre-existing call site (the one
  /// production host `MasterBookingsScreen`, and every test that pumps this
  /// view directly) renders byte-identically without passing it. Only
  /// `MasterBookingsScreen` passes it, from `bookingCreationEnabledProvider`
  /// (`../application/bookings_capability.dart`).
  ///
  /// A widget PARAMETER and not a `ref.watch` inside this view, deliberately
  /// and for the same reason `showMasterFilter`/`useScheduleWindow` are
  /// parameters: this composition is the salon-reuse seam
  /// (`bookings_discovery_view_reuse_test.dart` pins it), so every scope
  /// decision stays the HOST's to make. Note this differs from
  /// `booking_viewer_role.dart`'s "never a constructor flag" rule — that rule
  /// is about the VIEWER'S IDENTITY, which a caller must not be able to
  /// assert; this flag only narrows what an already-identified viewer is
  /// offered, and its one host resolves it from the session anyway.
  final bool canCreateBooking;

  /// Phase 330 — whether the "no working hours" empty state renders its
  /// «Додати робочі години» CTA at all. `false` makes it ABSENT, not
  /// disabled, exactly like [canCreateBooking] — the title and the helper
  /// copy still render, so the read-only viewer is told WHY the timeline is
  /// missing, just not invited to fix it.
  ///
  /// ADDITIVE, defaulting to `true` — every pre-existing call site (the
  /// `/master/bookings` mount and every test that pumps this view directly)
  /// renders byte-identically without passing it, and the constructor assert
  /// above is unchanged for them. Only the `/staff/bookings` mount passes
  /// `false`: publishing working hours is a SCHEDULE write that
  /// `scheduleEditableProvider` has denied `SALON_MASTER` since phase 309.
  ///
  /// Like [canCreateBooking], a PARAMETER and not a `ref.watch` here — this
  /// composition is the salon-reuse seam, so every scope decision stays the
  /// host's. See that field's doc for the full reasoning.
  final bool canAddWorkingHours;

  /// ═══════════════════════════════════════════════════════════════════════
  /// PHASE 21.12 — THE SALON MASTER-COLUMN BOARD
  /// ═══════════════════════════════════════════════════════════════════════
  /// Maps ONE day's fetched bookings onto master columns. `null` (the default,
  /// and BOTH master routes) keeps the single-master overlap-lane timeline —
  /// [BookingsTimelineGrid] is handed `columns: null` and
  /// [TimelineDensity.master], which is byte-for-byte what it rendered before
  /// this parameter existed.
  ///
  /// A BUILDER, not a `List`, for one reason: the columns are a function of
  /// the day's fetched bookings, which this view owns and the HOST cannot see
  /// (the host supplies a seed query; the day, the filters and the fetch all
  /// live here). The host supplies the ROSTER — which masters exist, their
  /// names and ratings — and this view supplies the bookings to partition
  /// across them. See `SalonBookingsScreen`.
  ///
  /// The returned columns MUST partition the list handed in, in order: that
  /// is what keeps the «N записів» header count and the rendered cards one
  /// number rather than two agreeing computations. See
  /// [TimelineBoardColumn.bookings].
  ///
  /// ## PHASE 336 — WHY THIS TAKES `day`
  ///
  /// Identical in shape to [boardWindowBuilder], and now literally so. The
  /// host must mark a master who is NOT WORKING on the shown day
  /// ([MasterColumnEntry.dayOff]), and "which day" is a fact this view owns
  /// and the host cannot see — the host supplies a SEED query; the selected
  /// day lives in `_BookingsDiscoveryViewState` and moves with the rail (see
  /// "the day is NOT read from query"). So the day travels the same way the
  /// bookings do: as an argument.
  ///
  /// Widening the arity rather than adding a third builder was the narrower
  /// change, not the wider one: this callback has exactly ONE call site in
  /// the repository (`SalonBookingsScreen`), both master routes pass `null`,
  /// and the two host seams now have one signature between them instead of
  /// two that differ for no reason a reader could recover.
  ///
  /// ## 2026-09-18 — WHY THIS ALSO TAKES `masterIds`
  ///
  /// Same argument as `day`, one step further. The «Майстер» filter's ticked
  /// ids live in `_BookingsDiscoveryViewState`; WHICH masters those ids name
  /// is a roster fact only the host holds. So the selection travels to the
  /// host as an argument, and the host's one already-existing partition
  /// narrows its roster — rather than this view post-filtering the returned
  /// list, which would allocate a fresh `List` per rebuild and kill the
  /// `identical(widget.columns, oldWidget.columns)` gate the board's whole
  /// rebuild budget rests on (see `SalonBookingsScreen`'s state-class doc and
  /// its 483 → 371 measurement).
  ///
  /// **EMPTY MEANS EVERY MASTER.** Every caller that offers no «Майстер»
  /// section passes `const <String>{}` here forever, so the host's partition
  /// must treat that as "no narrowing", never as "nobody".
  ///
  /// ⚠ A HOST THAT MEMOISES THIS MUST KEY ON `masterIds` TOO. The filter can
  /// change while the day does NOT, so a memo keyed on `(dayItems, day,
  /// roster)` alone serves stale columns on exactly the interaction this
  /// parameter exists for. `SalonBookingsScreen._columnsFor` does.
  final List<TimelineBoardColumn> Function(
    List<Booking> dayItems,
    DateTime day,
    Set<String> masterIds,
  )?
  columnsBuilder;

  /// ═══════════════════════════════════════════════════════════════════════
  /// PHASE 335 — THE SALON BOARD'S UNION WINDOW
  /// ═══════════════════════════════════════════════════════════════════════
  /// Resolves the timeline's vertical bounds for ONE day from something the
  /// HOST knows and this view does not — on the salon board, every roster
  /// master's working hours. Returns `null` when no such bound applies.
  ///
  /// `null` (the DEFAULT, and both master routes, and every test that pumps
  /// this view without it) is byte-for-byte the behaviour that predates this
  /// parameter: [_Loaded.build]'s `!useScheduleWindow` arm calls
  /// `boardWindowBuilder?.call(...)`, gets `null`, and takes the same
  /// `_body(context, window: null)` return it always has. Nothing else in this
  /// file reads it. That is the whole compatibility argument — there is no
  /// second code path to reason about.
  ///
  /// A BUILDER, not a `ScheduleTimelineWindow`, for exactly [columnsBuilder]'s
  /// reason: the window is a function of the day's fetched bookings (which
  /// this view owns and the host cannot see) AND of the roster's schedule
  /// (which the host owns and this view must not learn about).
  ///
  /// ## Why this is NOT `useScheduleWindow: true`
  ///
  /// `useScheduleWindow` drags in two behaviours that are correct for one
  /// master and wrong for a manager's board:
  ///   * [MasterBookingsNoWorkingHoursState], which REPLACES the whole
  ///     timeline. On a salon board that would hide a real walk-in behind a
  ///     "no working hours" panel.
  ///   * the EXPLICIT_TIMES free-card branch, which is a single master's
  ///     declared-times list and has no meaning across a roster.
  /// It also has ~30 production references, so widening its contract would
  /// reach every one of them. This parameter is additive and reaches nothing.
  ///
  /// ## THE WINDOW THIS RETURNS MUST NOT EXCLUDE ANY BOOKING
  ///
  /// [_Loaded.build] runs the returned window through the SAME
  /// `bookingsInsideScheduleWindow` the master path uses — no flag, no branch,
  /// no divergent code path. On a manager's board a dropped booking is DATA
  /// LOSS, so the host must return a window under which that filter is
  /// VACUOUS: `salonBoardWindow` (`schedule_timeline_window.dart`) unions the
  /// roster's hours with the day's own booking span for precisely that
  /// reason, and [_Loaded.build] asserts the vacuity with `identical()` in
  /// debug builds. Read that function's proof before writing another
  /// implementation of this callback.
  final ScheduleTimelineWindow? Function(List<Booking> dayItems, DateTime day)?
  boardWindowBuilder;

  /// Overrides where the header's (+) button goes. `null` (the default, and
  /// both master routes) keeps the Phase 248 behaviour verbatim —
  /// `context.push(RouteNames.masterBookingNew)`. [canCreateBooking] still
  /// gates whether the button renders AT ALL, independently of this.
  ///
  /// The salon board passes a documented NO-OP (see
  /// `SalonBookingsScreen._openCreateBooking`): the control must occupy its
  /// final place and styling so the header's layout is settled, while the
  /// salon walk-in wizard stays deliberately unwired this phase.
  final VoidCallback? onCreateBooking;

  /// Whether the «Послуга» filter section is offered, and — because the two
  /// must not disagree — whether `masterServiceCatalogProvider` is subscribed
  /// to at all.
  ///
  /// `true` (the default) is every pre-existing call site, unchanged.
  /// The salon board passes `false`: that provider is the signed-in user's OWN
  /// master service catalogue, which for a SALON_OWNER or SALON_ADMIN is
  /// empty or irrelevant — offering it would be a filter that matches nothing,
  /// and warming it would be a wasted request on every mount. (The sheet
  /// already hides an empty section on its own; this additionally stops the
  /// fetch.)
  final bool showServiceFilter;

  /// Whether the day rail's booked-day dots are fetched at all.
  ///
  /// `true` on every current call site. WHICH endpoint supplies them is NOT
  /// this flag's business — [_bookedDaysAsync] dispatches on the seed query's
  /// sealed member, exactly as [_rebuildQuery] does, so the master's own board
  /// reads `bookedDaysProvider` (`GET /bookings/me/booked-days`) and the salon
  /// board reads `salonBookedDaysProvider(salonId)`
  /// (`GET /bookings/salon/{salonId}/booked-days`, backend Phase 319).
  ///
  /// The salon board passed `false` until that endpoint existed: `/me/booked-
  /// days` is the CALLER's days — for an owner it aggregates every salon they
  /// own and for a `SALON_ADMIN` the backend rejects it outright, so it is
  /// never THIS board's days. Both of those are now moot; the flag is kept as
  /// the "don't pay for the feature's heaviest request" seam (a full ±180-day
  /// sweep) for any future host that wants a rail without dots.
  final bool showBookedDayDots;

  @override
  ConsumerState<BookingsDiscoveryView> createState() =>
      _BookingsDiscoveryViewState();
}

class _BookingsDiscoveryViewState extends ConsumerState<BookingsDiscoveryView> {
  /// The single source of truth for the selected day. Always set — there is
  /// no «Всі» / null-day state (Phase 7.11).
  late DateTime _day;

  /// The month `_TopRow` (`bookings_month_calendar_panel.dart`) labels
  /// itself with WHILE THE RAIL IS COLLAPSED AND INTERACTIVE — separate from
  /// [_day] on purpose. [_day] only ever changes on a SELECTION (a chip tap,
  /// a grid tap, «Сьогодні», a month step); paging the rail is deliberately
  /// NOT a selection (see [_selectDay]'s "RAIL↔CALENDAR CONSISTENCY
  /// CONTRACT" doc) and must stay that way — no additional fetch may result
  /// from a rail flick. Before this field existed, `_TopRow`'s label read
  /// [_day]'s month directly, so scrolling the rail into a different month
  /// left the label frozen on the OLD month until the master tapped a chip.
  ///
  /// Kept in lockstep with [_day] from BOTH directions:
  ///   * every mutation of [_day] ([_applySelectedDay]) resets this to the
  ///     NEW [_day]'s month in the SAME `setState` — so «Сьогодні» / a chip
  ///     tap / a grid tap / a month step always lands the label on the
  ///     freshly selected month immediately, even if the rail itself is
  ///     still mid-animation back to that week's page.
  ///   * [BookingsDayRail.onVisibleWeekChanged] ([_onRailVisibleWeekChanged])
  ///     updates it independently whenever the rail SETTLES on a different
  ///     week — including a week the master merely scrolled past without
  ///     selecting anything in it.
  ///
  /// `BookingsMonthCalendarPanel` reads this only while its own rail layer is
  /// interactive (`t < _kPanelHandoffT`); once the grid takes over it derives
  /// the label from [_day] instead, because the grid's own pager already
  /// selects on every settled step — see that widget's `_railInteractive`.
  late DateTime _visibleMonth;

  /// The USER's status selection — what the filter sheet resolved with, and
  /// EMPTY until the master picks a group. Deliberately the RAW selection, NOT
  /// the set that goes on the wire: the default cancelled/declined exclusion is
  /// a rendering default, not a filter the master chose, so it must never light
  /// up the funnel badge ([_activeFilterCount]) or flip the empty state's copy
  /// to «Немає записів за цим фільтром» ([_hasUserFilters]).
  ///
  /// The wire mapping is applied exactly once, by [BookingsDayQuery.dayList] in
  /// [_rebuildQuery] — it is not idempotent, so this field must never hold an
  /// already-resolved wire set. See [BookingStatus.dayListWireStatuses].
  late Set<BookingStatus> _statuses;
  late Set<String> _serviceIds;

  /// The ticked «Майстер» ids — EMPTY MEANS EVERY MASTER (see
  /// [BookingsDiscoveryView.masterFilterOptions]).
  ///
  /// Seeded EMPTY, never from [BookingsDayQuery]: `SalonDayQuery.masterId` is
  /// the wire's single-master narrowing and this feature deliberately does not
  /// touch it. Pinned empty forever whenever
  /// [BookingsDiscoveryView.showMasterFilter] is `false` — [_applyFilters]
  /// resolves it against the offered options, and an unoffered section has no
  /// options, so no sheet result can put anything here on a master route.
  ///
  /// A FRESH `Set` on every apply, never mutated in place: the host's column
  /// memo may compare it, and an in-place mutation would be invisible to any
  /// key at all.
  Set<String> _masterIds = const <String>{};

  /// Whether the MASTER narrowed the list — the empty state's copy switch and
  /// the funnel badge both key off this, never off
  /// [BookingsDayQuery.hasFilters], which is a wire-shape question: `true` even
  /// on an untouched screen (the default exclusion is on the query) and `false`
  /// when every group is ticked (the maximal filter is genuinely unfiltered).
  bool get _hasUserFilters =>
      _statuses.isNotEmpty || _serviceIds.isNotEmpty || _masterIds.isNotEmpty;

  /// The live query, rebuilt through [BookingsDayQuery.of] on every change —
  /// the single mutation path, mirroring the retired screen's `_setQuery`
  /// discipline. Never built any other way (`.masterOwn(` directly is banned
  /// outside its declaring file by `scripts/forbid_raw_bookings_query.sh`).
  late BookingsDayQuery _liveQuery;

  /// Pages the day rail one WEEK at a time. A [PageController], not a bare
  /// [ScrollController]: the rail has no valid resting position between two
  /// weeks (Monday first, Sunday last, always), so there is no pixel offset
  /// for this class to compute any more — see [_showRailWeekOf], which
  /// replaced the retired `_centreRailOn`/`_alignRailTodayFirst` pair and
  /// their `kRailItemExtent` arithmetic.
  late final PageController _railController;

  /// Kyiv "today", captured once at open — not host "today". See the file
  /// header's "day is NOT read from query" section.
  late final DateTime _today;

  /// The Monday the rail's FIRST week page starts on.
  late final DateTime _railFirstWeekStart;

  /// Debounces day-chip taps. A scroll-fling across the rail can land a dozen
  /// taps in under a second, and each one is a new family member and a new
  /// request; without this the flick costs 40 round trips.
  Timer? _dayDebounce;

  // Captured in initState so dispose() never touches `ref` (Riverpod 3.x
  // throws on a post-dispose `ref` read).
  late final ScreenProtectionManager _screenProtection;

  /// Memoises [bookingsInsideScheduleWindow]'s result across rebuilds where
  /// the inputs haven't actually changed — mobile-perf MEDIUM fix (2026-09-17).
  /// `_Loaded` is a `StatelessWidget` (deliberately, see its class doc) and
  /// calls this via [_visibleBookingsFor] instead of the free function
  /// directly, so a rebuild triggered by `effectiveScheduleProvider`
  /// re-fetching with an UNCHANGED resolved window (see
  /// `effective_schedule_notifier.dart:78`) reuses the SAME list instance
  /// instead of reallocating one.
  ///
  /// ## WHAT THIS ACTUALLY BUYS, PER ROUTE (mobile-perf LOW, 2026-09-17)
  ///
  /// An earlier revision of this doc ended "— which is what lets
  /// [BookingsTimelineGrid]'s `identical(widget.bookings, oldWidget.bookings)`
  /// gate (`didUpdateWidget`) short-circuit again", full stop. That is true on
  /// ONE of the two routes and overstated on the other, and the difference is
  /// worth knowing before anyone "simplifies" this away or copies the claim:
  ///
  ///   * MASTER board (`useScheduleWindow: true`) — identity IS on this memo.
  ///     When the working-hours window genuinely excludes a booking,
  ///     [bookingsInsideScheduleWindow] must allocate a filtered copy, and a
  ///     fresh copy per rebuild is exactly what defeats the grid's gate. This
  ///     memo is the only thing holding that identity stable.
  ///   * SALON board (`columnsBuilder` + `boardWindowBuilder`) — identity is
  ///     ALREADY preserved without it. `salonBoardWindow` is the union of the
  ///     roster's hours WIDENED to cover every booking, so the filter is
  ///     provably vacuous there (the proof is in
  ///     `schedule_timeline_window.dart`; `_Loaded.build` asserts it with
  ///     `identical()` in debug), and
  ///     [bookingsInsideScheduleWindow]'s own "nothing was excluded → hand
  ///     back the input instance" short-circuit returns the same list anyway.
  ///     Here this memo saves only the O(N) window scan — ~8 µs on a full
  ///     board — never an identity.
  ///
  /// Load-bearing on the master route, a micro-optimisation on the salon one.
  /// Do NOT remove it on the strength of the salon measurement alone.
  ///
  /// Single-slot, not a per-day map: a day switch is a genuine cache miss
  /// anyway ([BookingsDayState.items] changes identity as soon as
  /// `bookingsDayProvider` re-fetches for the new day), so there is nothing
  /// to gain from keeping more than the last result.
  ///
  /// THIS MEMO WAS INERT UNTIL 2026-09-17 and every call missed. Its identity
  /// key is only meaningful because [BookingsDayState.items] is now
  /// identity-stable; before `stableBookingList` (see its doc in
  /// `bookings_day_state.dart`) freezed's getter allocated a fresh
  /// `EqualUnmodifiableListView` on every access, so `identical` below could
  /// never hit. Do not "simplify" that wrapping away.
  List<Booking>? _cachedVisibleSource;
  DateTime? _cachedVisibleDay;
  int? _cachedVisibleFirstMinute;
  int? _cachedVisibleWindowEndMinute;
  bool? _cachedVisibleIsExplicitTimes;
  List<Booking> _cachedVisibleResult = const <Booking>[];

  /// See [_cachedVisibleSource]'s doc. Compares [items] by IDENTITY (a list
  /// [BookingsDayState] only ever hands out fresh on a genuine re-fetch —
  /// true only because the notifier stores it via `stableBookingList`) and
  /// [window] by its three VALUE fields — [ScheduleTimelineWindow] has no
  /// `==` override and a fresh instance is constructed on every schedule
  /// resolve regardless of whether the working hours actually changed (see
  /// `_Loaded.build`'s `data:` branch), so comparing by reference would
  /// never hit.
  List<Booking> _visibleBookingsFor(
    List<Booking> items,
    DateTime day,
    ScheduleTimelineWindow window,
  ) {
    if (identical(_cachedVisibleSource, items) &&
        _cachedVisibleDay == day &&
        _cachedVisibleFirstMinute == window.firstMinute &&
        _cachedVisibleWindowEndMinute == window.windowEndMinute &&
        _cachedVisibleIsExplicitTimes == window.isExplicitTimes) {
      return _cachedVisibleResult;
    }
    final List<Booking> visible = bookingsInsideScheduleWindow(
      items,
      day,
      window,
    );
    _cachedVisibleSource = items;
    _cachedVisibleDay = day;
    _cachedVisibleFirstMinute = window.firstMinute;
    _cachedVisibleWindowEndMinute = window.windowEndMinute;
    _cachedVisibleIsExplicitTimes = window.isExplicitTimes;
    _cachedVisibleResult = visible;
    return visible;
  }

  @override
  void initState() {
    super.initState();
    // `clockProvider`, NOT a bare `DateTime.now()` (mobile-qa, 2026-07-22).
    // The Kyiv-vs-host distinction this line exists to make is only OBSERVABLE
    // at an instant when the two name different calendar days — roughly a 3h
    // window per day on a UTC runner — so the guard test for it was gated
    // behind a `skip:` that empirically never ran. Reading the injectable
    // clock seam lets that test pin "now" inside the skew window and assert
    // the landing query unconditionally. See `master_bookings_screen_test
    // .dart`'s "initial day" group. Behaviour in production is unchanged:
    // `clockProvider` resolves to `DateTime.now`.
    //
    // `kyivToday(clock)` IS `dateOnly(toBeauticaTime(clock()))`
    // (`shared/time/kyiv_day.dart:84,94`) — the canonical spelling, so `lib/`
    // has one name for this derivation rather than two.
    _today = kyivToday(ref.read(clockProvider));
    // CALENDAR arithmetic — `subtract(Duration(days: n))` would land on 23:00
    // or 01:00 across a Europe/Kyiv DST transition and skew every rail date
    // derived from it. See `bookings_day_rail.dart`'s header. `mondayOf`
    // routes through the same `railDayAt` for the same reason.
    _railFirstWeekStart = railDayAt(
      mondayOf(_today),
      -kRailWeekLength * kBookingsDayRailWeekSpan,
    );
    _day = _today;
    _visibleMonth = DateTime(_today.year, _today.month);
    _statuses = widget.query.statuses.toSet();
    _serviceIds = widget.query.serviceIds.toSet();
    // Through [_rebuildQuery], NOT a second inline `BookingsDayQuery.of` — it
    // is the one place that folds the default status exclusion onto the wire
    // (via [BookingsDayQuery.dayList]), and a landing query built any other way
    // would skip it.
    _rebuildQuery();
    // The rail opens on the week containing `_day` (= Kyiv today) with NO
    // post-frame correction: `initialPage` is applied before the pager's
    // first layout, so there is no frame where the rail shows week 0 of the
    // span and then jumps. The retired `_alignRailTodayFirst` needed a
    // post-frame callback only because a pixel offset cannot be computed
    // before `position.viewportDimension` is known; a PAGE index can.
    _railController = PageController(
      initialPage: railWeekIndex(_railFirstWeekStart, _day),
    );
    _screenProtection = ref.read(screenProtectionProvider)..acquire();
  }

  @override
  void dispose() {
    _dayDebounce?.cancel();
    _screenProtection.release();
    _railController.dispose();
    super.dispose();
  }

  // ── Rail paging ─────────────────────────────────────────────────────────
  //
  // The rail is a Monday→Sunday WEEK pager (user-requested, this session —
  // "it should always start from Monday … the first day is monday and last is
  // sunday"). Two methods retired with the continuous strip it replaced:
  //
  //   * `_centreRailOn` — there is nothing to centre. A week page fills the
  //     viewport, so the only question left is WHICH week, and the answer is
  //     an index, not a pixel offset.
  //   * `_alignRailTodayFirst` — "today leftmost" is not expressible any
  //     more, and the design intent behind it survives anyway: the week
  //     containing today opens with today already on screen, alongside the
  //     rest of the week the master is actually working.
  //
  // Both carried DST-unsafe-arithmetic warnings in their docs; that hazard is
  // now concentrated in `railWeekIndex`/`mondayOf`
  // (`bookings_day_rail.dart`), which is where the tests pin it.

  /// Pages the rail to the week containing [day].
  ///
  /// Called ONLY from [_selectImmediate] — i.e. for a grid-cell tap, a month
  /// page turn, or «Сьогодні». A rail-chip tap deliberately does NOT page
  /// (the tapped day is already on the visible week), and neither does the
  /// master's own paging: see [_selectDay]'s doc for the rail↔calendar
  /// consistency contract those two halves uphold between them.
  ///
  /// [animated] is a REQUEST, not a guarantee — see [_kRailAnimateMaxPages].
  void _showRailWeekOf(DateTime day, {bool animated = false}) {
    if (!_railController.hasClients) return;
    // Clamped: the rail's week span is finite (± [kBookingsDayRailWeekSpan]),
    // and while it is deliberately far wider than any realistic navigation,
    // `animateToPage`/`jumpToPage` assert on an out-of-range index — a
    // corrupt selection must park the rail at its edge, not crash the screen.
    final int target = railWeekIndex(
      _railFirstWeekStart,
      dateOnly(day),
    ).clamp(0, _railWeekCount - 1);
    // mobile-perf LOW fix (finding #2). Every caller but «Сьогодні» reaches
    // here while the month panel is EXPANDED, i.e. while the rail sits under
    // `Opacity(0)` + `IgnorePointer` — so the 320ms sweep is invisible, and
    // `animateToPage` still builds and lays out every week page it passes
    // through (≈26 of them after a six-month excursion across the grid).
    // Jumping when the distance is more than one page skips all of that and
    // reads identically, since the only frame the master can ever see is the
    // one after the panel collapses. This is the same choice, for the same
    // reason, that the panel's own month pager already makes in
    // `bookings_month_calendar_panel.dart`'s `didUpdateWidget`.
    //
    // `page` can still be null with clients attached (before the rail's first
    // layout), in which case the distance is unknowable and jumping — the
    // cheaper, always-correct branch — wins.
    final double? current = _railController.page;
    final bool adjacent =
        current != null && (target - current).abs() <= _kRailAnimateMaxPages;
    if (animated && adjacent) {
      _railController.animateToPage(
        target,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
      );
    } else {
      _railController.jumpToPage(target);
    }
  }

  /// How far the rail may travel before [_showRailWeekOf] downgrades an
  /// animated request to a jump. One page: a neighbouring week is the only
  /// distance whose sweep carries any meaning, and it is also the only one
  /// that builds no page the master will not end up looking at.
  static const double _kRailAnimateMaxPages = 1;

  /// Total rail week pages — symmetric around the week containing [_today].
  static const int _railWeekCount = kBookingsDayRailWeekSpan * 2 + 1;

  // ── Month calendar panel (Варіант D port) ───────────────────────────────
  //
  // The old month switcher's `_focusedMonth`/`_prevMonth`/`_nextMonth` are
  // RETIRED — see `widgets/bookings_month_calendar_panel.dart`'s file header
  // for the full replacement contract. There is now exactly ONE piece of
  // date state on this screen ([_day]); the month is `DateTime(_day.year,
  // _day.month)`, derived wherever it is needed (inside the panel), never
  // stored separately. A month step — the panel's ‹ › chevrons or a sideways
  // swipe on the grid — now SELECTS, same as a rail tap or «Сьогодні»: this
  // is the fix for the original chevron/label/query disagreement bug.

  /// The single mutation point for every date-navigation control BESIDES a
  /// rail-chip tap: a grid-cell tap, the «Сьогодні» pill, and a resolved
  /// month step. All three are single deliberate actions, unlike a rail
  /// flick, so — mirroring the retired `_goToToday`'s own shape — this
  /// cancels any pending rail-tap debounce, applies the selection
  /// immediately, and recentres the rail so the collapsed strip already
  /// agrees with the grid the moment the master collapses it back down.
  void _selectImmediate(DateTime day) {
    _dayDebounce?.cancel();
    _applySelectedDay(day);
    _showRailWeekOf(day, animated: true);
  }

  /// Resolves a month step ([BookingsMonthCalendarPanel.onStepMonth] — a
  /// settled horizontal page turn on the grid, [delta] a signed month count)
  /// into a selection: the SAME day-of-month in the target month, clamped to
  /// that month's length — so "the 31st" survives a jump into a 30-day month,
  /// exactly as the approved design's own `_stepMonth`. Not clamped to the
  /// rail's own week span; [_showRailWeekOf] clamps the resulting PAGE INDEX
  /// on its own, so a day outside the rail's span parks the rail at its edge
  /// instead of crashing, and the query (unlike the rail) has no such bound
  /// to respect.
  ///
  /// SELECTING, not merely relabelling, is the locked contract — see
  /// `integration_test/master_bookings_month_step_flow_test.dart`. It is what
  /// keeps the `_TopRow` label, the rail, and the fetched list agreeing on
  /// one day, and it is unchanged by the chevrons' retirement: the gesture
  /// that resolves the step changed, the meaning of a step did not.
  void _stepMonth(int delta) {
    // Every call here is a COMMITTED page turn — [_resolveMonthPage] only
    // invokes [onStepMonth] once `delta != 0`, i.e. never for the
    // spring-back case or the programmatic resync `jumpToPage` triggers in
    // `didUpdateWidget`. So the tactile cue belongs here, not at the pager
    // itself, and never fires on a swipe that snaps back to where it started.
    HapticFeedback.selectionClick();
    final DateTime targetMonth = DateTime(_day.year, _day.month + delta);
    final int lastDayOfTargetMonth = DateTime(
      targetMonth.year,
      targetMonth.month + 1,
      0,
    ).day;
    final int day = _day.day > lastDayOfTargetMonth
        ? lastDayOfTargetMonth
        : _day.day;
    _selectImmediate(DateTime(targetMonth.year, targetMonth.month, day));
  }

  // ── Query mutation ──────────────────────────────────────────────────────

  /// Rebuilds [_liveQuery] from the current [_day]/[_statuses]/[_serviceIds]
  /// — the ONE place that constructs the live query. Every mutator below goes
  /// through this rather than building a query itself.
  ///
  /// [BookingsDayQuery.dayList], never [BookingsDayQuery.of]: the default
  /// cancelled/declined exclusion lives on the WIRE and is owned by that
  /// factory, which the two post-write invalidation sites also build through
  /// so they target the member this screen actually watches. Passing
  /// [_statuses] RAW is load-bearing — the mapping is not idempotent. The UI's
  /// own notion of "is a filter active" stays [_hasUserFilters].
  ///
  /// Phase 21.12 — dispatches on the SEED query's sealed member, which is what
  /// the file header always promised ("[query] — the scope AND the seed
  /// filters … the salon phase adds `.salon(...)`"). The scope therefore
  /// travels on the seed the host already passes, and this view still never
  /// branches on scope anywhere else. Both branches resolve the SAME
  /// non-idempotent status mapping through the SAME
  /// [BookingStatus.dayListWireStatuses], exactly once.
  void _rebuildQuery() {
    _liveQuery = switch (widget.query) {
      SalonDayQuery(:final String salonId, :final String? masterId) =>
        BookingsDayQuery.salonDayList(
          day: _day,
          salonId: salonId,
          masterId: masterId,
          statuses: _statuses,
          serviceIds: _serviceIds,
          maximalStatuses: _kMaximalFilterStatuses,
        ),
      MasterOwnDayQuery() => _masterOwnQuery(),
    };
  }

  BookingsDayQuery _masterOwnQuery() {
    return BookingsDayQuery.dayList(
      day: _day,
      statuses: _statuses,
      serviceIds: _serviceIds,
      // The sheet's OWN coverage, not `BookingStatus.filterable`'s default —
      // computed from `BookingStatusFilterGroup.values` so the two can never
      // drift apart (2026-08-15: the sheet dropped its NOT_COMPLETED row).
      // Without this, ticking every row the sheet still shows would produce
      // an INCLUSION list that silently excludes NOT_COMPLETED on the wire —
      // see `BookingStatus.dayListWireStatuses`'s `maximal` doc. Hoisted to
      // the module-level `_kMaximalFilterStatuses` — see its doc for why.
      maximalStatuses: _kMaximalFilterStatuses,
    );
  }

  /// The booked-day dot set for THIS view's scope, or `null` when
  /// [BookingsDiscoveryView.showBookedDayDots] is `false` (nothing is watched
  /// at all, so no request is issued).
  ///
  /// Dispatches on the SEED query's sealed member, exactly as [_rebuildQuery]
  /// does and for the same reason — the scope travels on the seed the host
  /// already passes, so this view still never branches on "am I a salon?"
  /// anywhere else. The two endpoints are strictly scope twins (same window,
  /// same 366-day cap, same filter-independence, one shared provider body in
  /// `booked_days_notifier.dart`), so everything downstream of here is
  /// identical for both.
  ///
  /// Takes the `Consumer`'s own [WidgetRef], NOT the `State`'s: the watch must
  /// stay scoped to that builder, which is what keeps a dot-set emission from
  /// rebuilding the timeline subtree above it (see the call site's comment).
  AsyncValue<Set<DateTime>>? _bookedDaysAsync(WidgetRef ref) {
    if (!widget.showBookedDayDots) return null;
    return switch (widget.query) {
      SalonDayQuery(:final String salonId) => ref.watch(
        salonBookedDaysProvider(salonId),
      ),
      MasterOwnDayQuery() => ref.watch(bookedDaysProvider),
    };
  }

  /// Selecting a rail day narrows to exactly that day. Debounced; see
  /// [_dayDebounce] — a rail flick can land a dozen taps in under a second,
  /// and each one is a new family member and a new request without this.
  ///
  /// ## THE RAIL↔CALENDAR CONSISTENCY CONTRACT (locked, this session)
  ///
  /// Two horizontal pagers now sit in one panel — the rail's week pager and
  /// the expanded grid's month pager. They cannot desync, because only ONE of
  /// the four possible moves writes date state:
  ///
  ///   1. Rail chip TAP → selects (here, debounced). The tapped day is on the
  ///      visible week already, so nothing pages.
  ///   2. Rail week PAGE → selects NOTHING. It moves the rail's own viewport
  ///      and nothing else, exactly as scrolling the old continuous strip
  ///      did. A pager that selected on settle would fire one query per week
  ///      flick, which is precisely what [_dayDebounce] exists to prevent,
  ///      and would make an idle flick through the month rewrite the
  ///      timeline half a dozen times.
  ///   3. Grid cell TAP / «Сьогодні» → selects immediately ([_selectImmediate])
  ///      and pages the rail to the new day's week.
  ///   4. Grid month PAGE → selects immediately too ([_stepMonth] → same
  ///      day-of-month, clamped → [_selectImmediate]) and likewise pages the
  ///      rail.
  ///
  /// So [_day] stays the single source of truth, and the two derived views
  /// agree by construction: `_TopRow`'s label is `_day`'s month, the grid's
  /// resting page is `_day`'s month, the rail's resting page is `_day`'s week
  /// AFTER any move that changed `_day`. Collapsing the panel having paged to
  /// month M+1 therefore lands on: label M+1, rail on the selected day's week
  /// inside M+1, timeline on that day's bookings. Nothing to reconcile,
  /// because nothing was ever separately stored.
  ///
  /// The one state that is deliberately NOT reconciled is a rail the master
  /// paged away from the selection by hand (move 2). That is a browsing
  /// position, not a disagreement — the selected chip is simply off-screen,
  /// as it always was when the old strip was scrolled away — and re-opening
  /// the calendar still shows `_day`'s month, unmoved.
  void _selectDay(DateTime day) {
    _dayDebounce?.cancel();
    _dayDebounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      _applySelectedDay(day);
    });
  }

  /// The single mutation a rail-day selection resolves to — sets [_day] and
  /// rebuilds [_liveQuery]. Called after [_dayDebounce] elapses
  /// ([_selectDay]). [_goToToday] mirrors this shape directly rather than
  /// calling it, since it also has to move the rail's scroll position.
  void _applySelectedDay(DateTime day) {
    final DateTime selected = dateOnly(day);
    setState(() {
      _day = selected;
      // Resyncs the `_TopRow` label to the FRESH selection immediately — see
      // [_visibleMonth]'s doc. For a NON-adjacent [_showRailWeekOf] resync
      // (`jumpToPage`, synchronous) this is redundant with the independent
      // `onVisibleWeekChanged` relabel that follows it in the very same
      // frame, so mutating it alone cannot be made to fail through most
      // scenarios — confirmed, not merely assumed (mobile-qa, 2026-08-14).
      // It IS load-bearing for the one case that actually samples a gap: an
      // ADJACENT-week resync (`animateToPage`, a real 280-320ms
      // `AnimationController` sweep — see `_kRailAnimateMaxPages`) that also
      // crosses a month boundary. Without this line, the label stays on the
      // browsed-to month for that whole window instead of updating the
      // instant the selection changes; RED/GREEN-proven by
      // `bookings_discovery_view_visible_month_test.dart`'s
      // "REGRESSION (mid-animation window)" case, which samples via
      // `pump(Duration)` mid-animation rather than `pumpAndSettle()`.
      _visibleMonth = DateTime(selected.year, selected.month);
      _rebuildQuery();
    });
  }

  /// `BookingsDayRail.onVisibleWeekChanged` (routed through
  /// `BookingsMonthCalendarPanel`) — fires with the Monday of whichever week
  /// the rail just SETTLED on, on scroll-end only. Updates ONLY
  /// [_visibleMonth]: never [_day], never [_liveQuery] — see that field's doc
  /// for why paging the rail must stay pure navigation. No `setState` (hence
  /// no rebuild, hence no provider fetch) when the settled week's month
  /// hasn't actually changed — a spring-back, or a programmatic resync that
  /// lands back on the already-shown month, is a no-op here.
  ///
  /// ## Straddling weeks label by the SELECTION, not by the rail's Monday
  ///
  /// A week that crosses a month boundary belongs to two months at once, and
  /// its Monday is not the master's selection. Labelling such a week by its
  /// week-START relabels the collapsed strip to the PREVIOUS month for every
  /// selection in the tail of a straddling week — «Сьогодні» on 1–4 Oct 2026
  /// reads «Вересень 2026», a grid-cell tap on a first-of-month day reads the
  /// month the master just left, and so does a month page turn followed by a
  /// collapse. All three arrive here through [_selectImmediate], whose
  /// [_showRailWeekOf] resync fires this callback AFTER [_applySelectedDay]
  /// has already set the correct month — so this writer clobbers it.
  ///
  /// So: when the settled week is the SELECTION's own week, the label is the
  /// selected day's month. Move 2 of the contract above — a genuine browse to
  /// a week [_day] is NOT in — is untouched and still labels by week-start,
  /// which is the only month it can honestly name.
  void _onRailVisibleWeekChanged(DateTime weekStart) {
    final DateTime month = mondayOf(_day) == weekStart
        ? DateTime(_day.year, _day.month)
        : DateTime(weekStart.year, weekStart.month);
    if (_visibleMonth == month) return;
    setState(() => _visibleMonth = month);
  }

  /// The «Скинути фільтри» escape hatch on the filter-empty state — clears
  /// status/service filters back to the DEFAULT view (which still excludes
  /// CANCELLED/DECLINED via [BookingsDayQuery.dayList]; "cleared" means "the
  /// master chose nothing", not "show everything" — the latter is ticking
  /// every group in the sheet, which is a different wire set entirely). The day
  /// is navigation, not a filter, and is deliberately left untouched: a master
  /// who narrowed by status on TODAY and hit a filter-empty result wants
  /// today's unfiltered list, not to be bounced back to a different day.
  void _clearAllFilters() {
    _dayDebounce?.cancel();
    setState(() {
      _statuses = <BookingStatus>{};
      _serviceIds = <String>{};
      // «Майстер» is CLIENT-SIDE and so is invisible to `_rebuildQuery` — but
      // it is still a filter the owner set, so «Скинути фільтри» must clear it
      // too or the board stays narrowed after the user was told it was reset.
      _masterIds = const <String>{};
      _rebuildQuery();
    });
  }

  /// Opens the filter sheet and applies whatever it resolves with.
  ///
  /// The sheet holds DRAFT state and resolves exactly once, on «Застосувати».
  /// `applied.statuses`/`applied.serviceIds` are the whole of what it can
  /// resolve with (Phase 7.13 retired the sheet's «Дата» section along with
  /// `BookingsFilterSelection.from`/`.to` — there is nothing date-shaped left
  /// to discard). The rail, the month switcher, and «Сьогодні» remain the
  /// only day controls (Phase 7.16 retired the calendar jump).
  Future<void> _applyFilters() async {
    _dayDebounce?.cancel();
    // `asData?.value`, NEVER `.value` — see the file header.
    //
    // Phase 21.12 — an EMPTY list when [showServiceFilter] is false, which the
    // sheet already renders as "no «Послуга» section" (`bookings_filter_sheet
    // .dart`'s `if (widget.services.isNotEmpty)`), so no new sheet parameter
    // was needed. Reading the provider here would also SUBSCRIBE to it, which
    // is the very fetch `_ServiceCatalogueWarmer` is skipping on that scope.
    final List<MasterService> services = widget.showServiceFilter
        ? (ref.read(masterServiceCatalogProvider).asData?.value ??
              const <MasterService>[])
        : const <MasterService>[];
    // The «Майстер» universe — EMPTY unless the host both offers the section
    // and has a roster, which is what makes the flag and the options one
    // decision rather than two that can disagree.
    final List<MasterFilterOption> masters = widget.showMasterFilter
        ? widget.masterFilterOptions
        : const <MasterFilterOption>[];
    final BookingsFilterSelection? applied = await BookingsFilterSheet.show(
      context,
      initial: BookingsFilterSelection(
        statuses: _statuses,
        serviceIds: _serviceIds,
        masterIds: _masterIds,
      ),
      services: services,
      masters: masters,
    );
    if (!mounted || applied == null) return;
    // RESOLVED AGAINST THE OFFERED OPTIONS, not taken verbatim. Two things
    // fall out of this one line:
    //   * on a surface with no «Майстер» section (`masters` empty — both
    //     master routes) the result is ALWAYS empty, so the flag cannot be
    //     bypassed by any sheet result whatsoever;
    //   * a master who left the salon between two opens of the sheet cannot
    //     linger as an INVISIBLE tick — the sheet offers only the current
    //     roster, so their id is dropped the next time the owner applies.
    //     (`columnsFor` independently refuses to render an empty board for a
    //     selection that matches nobody; this is the half that stops the
    //     situation arising in the first place.)
    final Set<String> offered = <String>{
      for (final MasterFilterOption m in masters) m.id,
    };
    final Set<String> resolvedMasterIds = <String>{
      for (final String id in applied.masterIds)
        if (offered.contains(id)) id,
    };
    setState(() {
      _statuses = applied.statuses;
      _serviceIds = applied.serviceIds;
      _masterIds = resolvedMasterIds;
      _rebuildQuery();
    });
  }

  /// The count the header badge shows — ACTIVE FILTER GROUPS (day excluded;
  /// it is navigation, not a filter).
  ///
  /// Reads [_statuses] (the master's own selection), never the resolved WIRE
  /// set. Both ends of that mapping would give the wrong answer: the default
  /// cancelled/declined exclusion is not a decision the master made, so an
  /// untouched screen must report **0** and show no badge; and ticking every
  /// group resolves to an EMPTY wire set, which must still report **1** and
  /// show the badge — the master narrowed nothing away, but they did make a
  /// choice, and the funnel is how they find their way back out of it.
  int get _activeFilterCount => bookingsActiveFilterCount(
    hasStatuses: _statuses.isNotEmpty,
    hasServiceIds: _serviceIds.isNotEmpty,
    // GROUPS, not values — ticking three masters is ONE active filter, exactly
    // as ticking three statuses is. See [bookingsActiveFilterCount]. Counted
    // here so a narrowed board shows its badge without the owner opening the
    // sheet, which is the whole reason the badge exists.
    hasMasterIds: _masterIds.isNotEmpty,
  );

  /// Phase 248 — the header's "+" add-booking affordance.
  ///
  /// Pushes `RouteNames.masterBookingNew` (`/master/bookings/new`), the
  /// Phase 247 «Новий запис» walk-in wizard — a CHILD of `RouteNames
  /// .masterBookings` registered with `pageBuilder` +
  /// `MaterialPage(fullscreenDialog: true)` in `app_router.dart`. Deliberately
  /// NOT `RouteNames.bookingNew`: that is the CLIENT's own "book a master"
  /// flow (wrong direction — it would walk a MASTER through booking
  /// themselves as a client). This screen only ever mounts under `/master/*`,
  /// which `auth_redirect.dart` already gates to `INDEPENDENT_MASTER`
  /// (redirecting any other authenticated role — including `SALON_MASTER` —
  /// to the home shell before this screen, or the wizard route it pushes,
  /// ever builds), so no separate role check is needed here.
  ///
  /// ZERO-ARG ON PURPOSE (mobile-perf LOW): it reads `context` off the
  /// `State` so the call site can pass the TEAR-OFF (`onAdd:
  /// _openCreateBooking`) rather than a fresh `() => _openCreateBooking(
  /// context)` closure per build. Dart canonicalises instance-method
  /// tear-offs, so the resulting `VoidCallback` is `identical` across
  /// rebuilds — which saves ONE closure allocation per build and keeps
  /// `_Header`'s `onAdd` field stable. It does NOT let `_Header` skip its
  /// subtree: `build` constructs a fresh `_Header(...)` every time, and a
  /// `StatelessWidget` element only short-circuits when the NEW widget
  /// instance is `identical` to the old one (`Element.update`'s first check)
  /// — a claim an earlier revision of this comment made and that was simply
  /// false. Keep the tear-off for the allocation, not for a skip that never
  /// happened; do not reintroduce the `BuildContext` parameter.
  void _openCreateBooking() {
    // Phase 21.12 — the HOST may redirect this. `null` (both master routes)
    // keeps the Phase 248 destination verbatim. See
    // [BookingsDiscoveryView.onCreateBooking].
    final VoidCallback? hostHandler = widget.onCreateBooking;
    if (hostHandler != null) {
      hostHandler();
      return;
    }
    context.push(RouteNames.masterBookingNew);
  }

  /// Phase 21.12 — the roster chip the owner tapped, or `null`. PURELY a strip
  /// affordance: it highlights one column so a wide board stays readable, and
  /// it deliberately does NOT narrow anything. Filtering the board down to one
  /// master by tapping its own chip would collapse the thing the board exists
  /// to show.
  ///
  /// ⚠ 2026-09-18 — STILL NOT THE FILTER, now that a real one exists. The
  /// «Майстер» section writes [_masterIds]; a chip tap writes this. Neither
  /// touches the other, in either direction:
  ///   * applying a filter never clears or moves the highlight — it would be a
  ///     second, invisible consequence of a control the owner used for one
  ///     thing;
  ///   * a highlight on a master the filter excludes is INERT, not broken —
  ///     `MasterColumnStrip` draws the selected border on that one chip and
  ///     dims no other, so an absent chip simply carries no highlight and the
  ///     remaining columns render in their ordinary state. Re-ticking that
  ///     master restores it.
  String? _selectedMasterId;

  void _onSelectMasterColumn(String masterId) {
    setState(() {
      _selectedMasterId = _selectedMasterId == masterId ? null : masterId;
    });
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Built ONCE per `build()` call and threaded through UNCHANGED into
    // `BookingsMonthCalendarPanel`'s `timeline:` slot below — see that call
    // site's comment for why hoisting it here (rather than inside the
    // `Consumer` that watches `bookedDaysProvider` for the panel's dots)
    // matters: `Element.updateChild` skips rebuilding a child entirely when
    // the incoming widget is `identical` to the previous one, so a
    // bookedDays change never tears this subtree down, and the panel itself
    // hands it to an `AnimatedBuilder` as a `child:` too, so a drag frame or
    // the 280ms open/close settle never rebuilds it either.
    final Widget timeline = RepaintBoundary(
      child: Consumer(
        builder: (BuildContext context, WidgetRef ref, Widget? _) {
          final AsyncValue<BookingsDayState> async = ref.watch(
            bookingsDayProvider(_liveQuery),
          );

          // mobile-perf MEDIUM fix (earlier session): watched HERE,
          // ALONGSIDE `bookingsDayProvider` rather than from inside
          // `_Loaded` (which only ever mounts once `async` resolves to
          // `data:`) — so the two fetches fire in PARALLEL on every day
          // change instead of the schedule round trip waiting on the
          // bookings one to finish first. `null` when `useScheduleWindow`
          // is `false`: the provider is still NEVER watched for any other
          // caller — the doc'd invariant on
          // `BookingsDiscoveryView.useScheduleWindow` is unchanged, just
          // enforced one level up.
          // Phase 312 — `effectiveScheduleProvider` gained a [ScheduleScope]
          // parameter; this view always reads the master's OWN calendar
          // (never a viewed-colleague's), so it resolves through
          // `ownScheduleScopeProvider` exactly like every other pre-Phase-312
          // caller — unaffected by the new owner/admin viewed-master path.
          final AsyncValue<List<EffectiveDay>>? scheduleAsync =
              widget.useScheduleWindow
              ? ref.watch(
                  effectiveScheduleProvider(
                    ref.watch(ownScheduleScopeProvider),
                    ScheduleRange(from: _day, to: _day),
                  ),
                )
              : null;

          return async.when(
            // Bare, unscrolled `Column`s inside a scroll view — the shipped
            // client screen hosts its own loading/error states the same
            // way, and dropping either straight into an `Expanded`
            // overflows the remaining height on a short device (Phase
            // 17.2 overflow guard).
            loading: () => ListView(
              key: const Key('master-bookings-skeleton'),
              physics: const AlwaysScrollableScrollPhysics(),
              // Stays at `VelvetSpacing.lg` (24) even though the timeline body
              // moved to [_kTimelineLeftInset] (12) — deliberately, and it
              // NARROWS the load→loaded shift rather than widening it.
              // `BookingsSkeleton` is a bare `_SkeletonCard` column with no
              // ruler gutter, so its card edge IS this padding edge (24). The
              // grid's first card edge is 12 + 42 (`_kRulerWidth`) + 4
              // (ruler↔grid gap) = 58, so the eye tracks a 34dp card→card
              // offset, down from 24→70 = 46dp before the inset change.
              // Matching 12 here would push it back out to 46dp. The
              // declared-times branch (also 24, no gutter) stays a 0dp swap.
              padding: const EdgeInsets.fromLTRB(
                VelvetSpacing.lg,
                0,
                VelvetSpacing.lg,
                VelvetSpacing.xxl,
              ),
              children: <Widget>[
                const BookingsSkeleton(),
                // The escape hatch for an indefinite `AsyncLoading`, added
                // after a master reported the skeleton shimmering forever on
                // the one day a manual walk-in booking had just been created
                // for. That day is by construction the ONE day not in
                // `bookings_day_notifier.dart`'s ≤3-day keepAlive LRU, so it
                // is the only one that must hit the network — and
                // `AsyncValue.when` routes `AsyncLoading(retrying: true)`
                // here too, so every automatic re-attempt looked identical to
                // a first attempt. The `error:` branch below has always had a
                // retry button; this gives `loading:` a bounded one.
                //
                // Renders nothing at all until
                // [kMyBookingsSlowLoadThreshold] elapses, so a healthy load —
                // which replaces this whole subtree long before then — never
                // shows it. See the widget's own doc for why no flash is
                // possible.
                MyBookingsSlowLoadNotice(
                  // `.fetchKey`, not `_liveQuery` (audit M2) — on the SALON
                  // member a filtered query DERIVES from the unfiltered one
                  // and issues no request of its own, so invalidating it
                  // would rebuild a derivation over the same cached (and,
                  // here, still-pending) base. `fetchKey` is identity on the
                  // master member, so this line is unchanged for it. See
                  // `BookingsDayQuery.fetchKey`.
                  onRetry: () =>
                      ref.invalidate(bookingsDayProvider(_liveQuery.fetchKey)),
                ),
              ],
            ),
            error: (Object e, StackTrace _) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                VelvetSpacing.lg,
                0,
                VelvetSpacing.lg,
                VelvetSpacing.xxl,
              ),
              children: <Widget>[
                MyBookingsErrorState(
                  error: e,
                  // `.fetchKey` — same reason as the `loading:` branch above.
                  // A derived salon member's error IS the base member's error;
                  // invalidating the derivation alone would re-read the cached
                  // failure and the retry button would do nothing.
                  onRetry: () =>
                      ref.invalidate(bookingsDayProvider(_liveQuery.fetchKey)),
                ),
              ],
            ),
            data: (BookingsDayState state) => _Loaded(
              state: state,
              // [_hasUserFilters], NOT `_liveQuery.hasFilters` — the live
              // query always carries statuses now (the default exclusion),
              // so reading it here would render the «Немає записів за цим
              // фільтром» copy on a screen the master never filtered.
              hasFilters: _hasUserFilters,
              // …but THIS one IS a wire-shape question, so it reads
              // `_liveQuery`, not `_statuses`/`_serviceIds`. See
              // [BookingsDayQuery.showsAllOccupancy].
              showsAllOccupancy: _liveQuery.showsAllOccupancy,
              day: _day,
              useScheduleWindow: widget.useScheduleWindow,
              scheduleAsync: scheduleAsync,
              visibleBookingsFor: _visibleBookingsFor,
              onClearFilters: _clearAllFilters,
              onBookingTap: widget.onBookingTap,
              onAddWorkingHours: widget.onAddWorkingHours,
              canAddWorkingHours: widget.canAddWorkingHours,
              // Phase 21.12 — `null` on both master routes, which is what
              // keeps `_body` selecting the single-master grid verbatim.
              columnsBuilder: widget.columnsBuilder,
              // 2026-09-18 — the «Майстер» selection, threaded to the HOST's
              // partition. `const {}` on both master routes (the section is
              // never offered there), which is what keeps
              // `columnsBuilder?.call(...)` a no-narrowing call everywhere it
              // was one before.
              masterIds: _masterIds,
              // Phase 335 — `null` on both master routes, which is what keeps
              // `_Loaded.build`'s `!useScheduleWindow` arm identical.
              boardWindowBuilder: widget.boardWindowBuilder,
              selectedMasterId: _selectedMasterId,
              onSelectMaster: _onSelectMasterColumn,
            ),
          );
        },
      ),
    );

    return Scaffold(
      key: const Key('master-bookings-screen'),
      backgroundColor: BrandColors.base,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _Header(
              title: widget.title,
              subtitle: widget.subtitle,
              onBack: widget.onBack,
              activeFilterCount: _activeFilterCount,
              onOpenFilters: _applyFilters,
              // Phase 329 — `null` when the viewer may not create bookings,
              // which removes the (+) button from the header entirely rather
              // than disabling it. See
              // [BookingsDiscoveryView.canCreateBooking].
              onAdd: widget.canCreateBooking ? _openCreateBooking : null,
              onOpenArchive: widget.onOpenArchive,
            ),
            // Phase 21.12 — skipped entirely on a scope with no «Послуга»
            // section, so the salon board never subscribes to the signed-in
            // user's own master catalogue. A `SizedBox.shrink()` either way,
            // so the column's layout is identical in both branches.
            if (widget.showServiceFilter)
              const _ServiceCatalogueWarmer()
            else
              const SizedBox.shrink(),
            // mobile-perf HIGH fix (finding #2), current shape — displacement
            // without relayout. `timeline` (built once above, at the top of
            // this `build()`) is threaded through UNCHANGED into
            // [BookingsMonthCalendarPanel]'s `timeline:` slot; the panel now
            // owns laying it out in a fixed-geometry `Positioned` box AND
            // repositioning it at PAINT time via `Transform.translate` as its
            // own `_open` animates — see that widget's file header ("the
            // timeline lives INSIDE this widget's subtree") and its
            // `kBookingsMonthCalendarPanelCollapsedHeight` doc for the full
            // mechanism and its history, including the REJECTED overlay
            // design this replaced: an earlier revision of this fix let the
            // expanding panel draw OVER the timeline instead of displacing
            // it (matching the ported preview's own framing of the grid as a
            // temporary overlay) — the user rejected that once it shipped,
            // wanting the approved design's actual push-down behaviour, which
            // this shape now gives them without reintroducing the relayout
            // coupling the original `Column`+`Expanded` composition had.
            //
            // Wrapping this call in a `Consumer` (for `bookedDaysProvider`,
            // which only the panel's dots need) does NOT rebuild `timeline`
            // when bookedDays changes — it is the same `Widget` instance
            // every time, and `Element.updateChild` skips rebuilding a child
            // whose incoming widget is `identical` to the previous one.
            Expanded(
              child: Consumer(
                builder: (BuildContext context, WidgetRef ref, Widget? _) {
                  // Filter-INDEPENDENT by design — the dots describe where
                  // the master's work is, not what the current filter
                  // matches, so they must not evaporate as the user
                  // narrows. Feeds BOTH the collapsed rail's dots and the
                  // expanded grid's density dots inside the panel — same
                  // source, unchanged.
                  // Which ENDPOINT is a scope question, answered once in
                  // [_bookedDaysAsync] off the seed query's sealed member —
                  // see [BookingsDiscoveryView.showBookedDayDots].
                  final AsyncValue<Set<DateTime>>? bookedDaysAsync =
                      _bookedDaysAsync(ref);
                  final Set<DateTime> bookedDays =
                      bookedDaysAsync?.value ?? const <DateTime>{};

                  return BookingsMonthCalendarPanel(
                    railController: _railController,
                    railFirstWeekStart: _railFirstWeekStart,
                    weekCount: _railWeekCount,
                    today: _today,
                    selectedDay: _day,
                    bookedDays: bookedDays,
                    onSelectRailDay: _selectDay,
                    onSelectDay: _selectImmediate,
                    onStepMonth: _stepMonth,
                    visibleMonth: _visibleMonth,
                    onVisibleWeekChanged: _onRailVisibleWeekChanged,
                    timeline: timeline,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A zero-height subscription that keeps the «Послуга» option universe WARM —
/// carried verbatim from the retired screen. See that history for why this is
/// a widget rather than a one-shot `ref.read` in `initState`: the catalogue
/// provider is `keepAlive` and lazy, and an invalidated-but-unsubscribed
/// `keepAlive` provider defers its refetch to the next read, which would open
/// the filter sheet on `AsyncLoading` right after a service create/edit
/// invalidates it.
///
/// Deliberately renders zero height rather than being conditional on the
/// async state — a widget that came and went would relayout the column.
class _ServiceCatalogueWarmer extends ConsumerWidget {
  const _ServiceCatalogueWarmer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(masterServiceCatalogProvider);
    return const SizedBox.shrink();
  }
}

/// The loaded body — the count line, the truncation notice (if any), then the
/// timeline or one of three empties.
///
/// [StatelessWidget] again (mobile-perf MEDIUM fix, this session): this used
/// to be a [ConsumerWidget] purely to `ref.watch(effectiveScheduleProvider
/// (...))` itself — which meant that watch could only ever start once the
/// OUTER `Consumer`'s `bookingsDayProvider` had already resolved to `data:`
/// (this widget is constructed nowhere else), serialising two independent
/// network round trips that have nothing to do with each other. The outer
/// `Consumer` now watches both providers side by side and hands the schedule
/// fetch's [AsyncValue] in as [scheduleAsync] instead — see that `Consumer`'s
/// builder. When [useScheduleWindow] is `false`, [scheduleAsync] is `null`
/// and the provider was never watched at all, exactly as before.
class _Loaded extends StatelessWidget {
  const _Loaded({
    required this.state,
    required this.hasFilters,
    required this.showsAllOccupancy,
    required this.day,
    required this.useScheduleWindow,
    required this.scheduleAsync,
    required this.visibleBookingsFor,
    required this.onClearFilters,
    required this.onBookingTap,
    required this.onAddWorkingHours,
    required this.canAddWorkingHours,
    required this.columnsBuilder,
    required this.masterIds,
    required this.boardWindowBuilder,
    required this.selectedMasterId,
    required this.onSelectMaster,
  }) : assert(
         !useScheduleWindow || scheduleAsync != null,
         'scheduleAsync must be set whenever useScheduleWindow is true — '
         'the outer Consumer always watches effectiveScheduleProvider in '
         'that case.',
       );

  final BookingsDayState state;

  /// `_BookingsDiscoveryViewState._hasUserFilters` — whether the MASTER
  /// narrowed the list. Deliberately NOT `_liveQuery.hasFilters`: the live
  /// query carries a status set on an untouched screen (the default
  /// cancelled/declined exclusion) and NO status set when every group is
  /// ticked, so that getter answers the opposite question at both ends. See
  /// `_statuses`' doc on the `State` and [BookingStatus.dayListWireStatuses].
  final bool hasFilters;

  /// `_BookingsDiscoveryViewState._liveQuery.showsAllOccupancy` — whether the
  /// fetched list can see EVERY booking that occupies the master's clock.
  ///
  /// The mirror image of [hasFilters]' sourcing: this one is a WIRE-shape
  /// question and MUST come off the live query, never off the raw selection
  /// (which knows nothing of the default exclusion or the select-all escape
  /// hatch). See [BookingsDayQuery.showsAllOccupancy] for the predicate.
  ///
  /// Consumed on the EXPLICIT_TIMES branch only: it gates `DeclaredTimeCards`'
  /// free cards, and — because suppressing them can leave that branch with
  /// nothing to draw — the filter-aware empty state in [_body]. The INTERVAL
  /// grid never reads it (it draws only what it fetched and has never had
  /// this bug).
  final bool showsAllOccupancy;
  final DateTime day;

  /// `widget.useScheduleWindow` — see that field's doc on
  /// [BookingsDiscoveryView].
  final bool useScheduleWindow;

  /// The master's working-hours fetch for [day] — watched by the OUTER
  /// `Consumer`, in PARALLEL with `bookingsDayProvider`, so the two round
  /// trips race instead of serialising (see the class doc). `null` iff
  /// [useScheduleWindow] is `false` (constructor assert); non-null and
  /// dispatched on via `.when()` otherwise, exactly as this widget used to
  /// dispatch on its own `ref.watch` result.
  final AsyncValue<List<EffectiveDay>>? scheduleAsync;

  /// `_BookingsDiscoveryViewState._visibleBookingsFor` — mobile-perf MEDIUM
  /// fix (this session). `_Loaded` is a [StatelessWidget] and has nowhere of
  /// its own to remember the last filtered list across a rebuild, so the
  /// memo lives in the `State` above and is handed in as a callback instead
  /// — keeps this widget itself unchanged (still a pure function of its
  /// constructor args), it just no longer calls
  /// [bookingsInsideScheduleWindow] directly. See that method's doc for why
  /// the cache lives there rather than here.
  final List<Booking> Function(
    List<Booking> items,
    DateTime day,
    ScheduleTimelineWindow window,
  )
  visibleBookingsFor;

  final VoidCallback onClearFilters;
  final ValueChanged<Booking> onBookingTap;

  /// `widget.onAddWorkingHours` — non-null whenever [useScheduleWindow] is
  /// `true` AND [canAddWorkingHours] is `true` (the constructor assert on
  /// [BookingsDiscoveryView] guarantees it), unused otherwise.
  final ValueChanged<DateTime>? onAddWorkingHours;

  /// `widget.canAddWorkingHours` — see that field's doc on
  /// [BookingsDiscoveryView]. `false` drops the empty state's CTA entirely,
  /// which is also what makes [onAddWorkingHours] legitimately `null` on a
  /// `useScheduleWindow: true` mount.
  final bool canAddWorkingHours;

  /// `widget.columnsBuilder` — `null` on both master routes, which is what
  /// makes [_body] hand [BookingsTimelineGrid] `columns: null` and
  /// [TimelineDensity.master], i.e. the pre-existing call verbatim.
  final List<TimelineBoardColumn> Function(
    List<Booking> dayItems,
    DateTime day,
    Set<String> masterIds,
  )?
  columnsBuilder;

  /// `_BookingsDiscoveryViewState._masterIds` — the ticked «Майстер» ids, or
  /// EMPTY for "every master". Consumed ONLY as [columnsBuilder]'s third
  /// argument; this widget never filters anything with it itself.
  final Set<String> masterIds;

  /// `widget.boardWindowBuilder` — see that field's doc on
  /// [BookingsDiscoveryView], which carries the full contract (including why
  /// the window it returns must make `bookingsInsideScheduleWindow` vacuous).
  /// `null` on both master routes and on every pre-existing test mount.
  final ScheduleTimelineWindow? Function(List<Booking> dayItems, DateTime day)?
  boardWindowBuilder;

  /// `_BookingsDiscoveryViewState._selectedMasterId` — the highlighted roster
  /// chip. Ignored unless [columnsBuilder] is non-null.
  final String? selectedMasterId;

  final ValueChanged<String> onSelectMaster;

  @override
  Widget build(BuildContext context) {
    if (!useScheduleWindow) {
      // ═══════════════════════════════════════════════════════════════════
      // PHASE 335 — THE SALON BOARD'S UNION WINDOW
      // ═══════════════════════════════════════════════════════════════════
      // `null` on every pre-existing call site (both master routes, every
      // test that pumps this view without the new parameter), and a `null`
      // builder yields a `null` window, so the next two statements collapse
      // to the single `return _body(context, window: null)` this arm has
      // always been. There is no second path for those callers to take.
      //
      // DEGRADATION IS DELIBERATE AND IS THE HOST'S TO DECIDE. The builder
      // also returns `null` when the salon's working-hours fetch has FAILED
      // or is still LOADING — see `salon_bookings_screen.dart`, which owns
      // that rule and states it in full. Summary for whoever reads this file
      // first and is tempted to "fix" it by surfacing an error here: the
      // roster and the salon profile are STRUCTURAL (there are no columns
      // without them, so the screen shows `MyBookingsErrorState`); the
      // schedule is ADORNMENT — it moves the timeline's top and bottom and
      // nothing else. A board that renders today's bookings against a
      // booking-derived window is completely usable; an error panel in its
      // place is not. Do not fold the schedule fetch into that error gate.
      // READ `state.items` EXACTLY ONCE, into a local, and use THAT local
      // everywhere below (mobile-qa HIGH, 2026-09-17). This is not style.
      // `BookingsDayState` is freezed, and freezed's generated `items` getter
      // is:
      //
      //     if (_items is EqualUnmodifiableListView) return _items;
      //     return EqualUnmodifiableListView(_items);
      //
      // so whenever the stored list is RAW it allocates a BRAND NEW wrapper on
      // every single access, and reading the getter twice yields two DIFFERENT
      // objects over the same rows. The `identical` assert below — whose whole
      // job is to police the WINDOW — then fired on that wrapper identity
      // instead, red-screening the board in every asserts-enabled build with
      // the nonsense diagnostic "0 of N would be dropped".
      //
      // THE STORED LIST WAS RAW ON EVERY ROUTE, not just the salon board's.
      // `PageResponse` is hand-written rather than freezed (see
      // `core/network/page_response.dart`), so `page.items` is a plain
      // `List<Booking>` and every `BookingsDayState` the notifier built stored
      // one. `_narrowSalonDay`'s `sublist` branch is NOT what caused this — it
      // merely yields another plain list. Falsified 2026-09-17 by reverting
      // this hoist and running the vacuity group's own "a VACUOUS window
      // passes straight through" case, which pumps a plain `MyBookingsQuery`
      // with no narrowing, no `sublist` and no CANCELLED row: it went red too.
      //
      // FIXED AT THE ROOT as well — `BookingsDayNotifier` now stores
      // `stableBookingList(...)` (see its doc in `bookings_day_state.dart`), so
      // the getter is identity-stable and three further gates that silently
      // depended on it work again. This hoist is kept as the local guarantee:
      // it is correct regardless of what any future writer of that state does,
      // and it is one fewer getter call either way.
      //
      // `state` is a `final` field of an immutable widget and nothing between
      // this read and the assert can reach it — `boardWindowBuilder` receives
      // the list as an argument and `visibleBookingsFor` only touches the
      // memo's own fields — so ONE read is genuinely sufficient.
      //
      // Release behaviour is unchanged (the assert is stripped, and the rows
      // are the same either way).
      final List<Booking> items = state.items;
      final ScheduleTimelineWindow? boardWindow = boardWindowBuilder?.call(
        items,
        day,
      );
      if (boardWindow == null) {
        return _body(context, window: null);
      }

      // THE SAME `bookingsInsideScheduleWindow` THE MASTER PATH USES — no
      // flag, no branch, no second predicate. What differs is the WINDOW: on
      // a manager's board a dropped booking is DATA LOSS (a 22:00 walk-in
      // must not vanish because its master finishes at 20:00), so
      // `salonBoardWindow` returns a union wide enough that this call is
      // provably VACUOUS. See its proof in `schedule_timeline_window.dart`.
      final List<Booking> visible = visibleBookingsFor(items, day, boardWindow);
      // THE VACUITY, ASSERTED — as TWO separate claims, because they fail for
      // entirely different reasons and a single `identical` could not tell
      // them apart. That ambiguity is not hypothetical: it is exactly what
      // made the original one-assert form report "0 of 1 would be dropped"
      // when nothing was being dropped at all (mobile-qa HIGH, 2026-09-17).
      //
      // Both are debug-only and neither can change shipped behaviour.
      //
      // (1) THE WINDOW EXCLUDED NOTHING. `bookingsInsideScheduleWindow` only
      // ever REMOVES elements (it never adds or reorders), so equal length is
      // an EXACT "excluded nothing" oracle — and, unlike identity, it stays
      // exact even if that function ever loses its return-the-input
      // optimisation. This is the claim about the WINDOW, and it is the one
      // the negative control in `bookings_discovery_view_schedule_window_test
      // .dart` ("a builder whose window EXCLUDES a booking") trips.
      assert(
        visible.length == items.length,
        'boardWindowBuilder returned a window that EXCLUDES bookings — '
        '${items.length - visible.length} of ${items.length} '
        'would be dropped from the board. On a salon board that is data '
        'loss. The window must satisfy salonBoardWindow\'s vacuity proof '
        '(schedule_timeline_window.dart): min over master starts AND the '
        'earliest booking start, max over master ends AND the latest '
        'booking END.',
      );
      // (2) …AND HANDED BACK THE INPUT INSTANCE. Given (1) this is no longer a
      // statement about the window at all — it is the IDENTITY contract three
      // shipped gates depend on: `visibleBookingsFor`'s memo,
      // `BookingsTimelineGrid.didUpdateWidget`'s `identical(widget.bookings,
      // oldWidget.bookings)` (which decides whether to re-run `assignLanes`
      // plus every card's layout), and `bookingsInsideScheduleWindow`'s own
      // return-the-input optimisation that exists to feed them. Breaking it
      // costs frames, not rows, so it gets its own message rather than
      // masquerading as data loss.
      assert(
        identical(visible, items),
        'the board window excluded nothing (both lists hold '
        '${items.length} booking(s)) but visibleBookingsFor returned a '
        'DIFFERENT list instance. No booking is lost, but every identity gate '
        'downstream now misses on every rebuild — BookingsTimelineGrid will '
        're-run assignLanes and re-lay-out every card. Either '
        'bookingsInsideScheduleWindow stopped returning its input instance, '
        'or BookingsDayState.items lost its identity stability (see '
        'stableBookingList in bookings_day_state.dart).',
      );
      return _body(context, window: boardWindow, visibleItems: visible);
    }

    // No `!` (repo style) — the constructor assert above guarantees
    // non-null whenever `useScheduleWindow` is true, which is the only way
    // this line runs; the `??` is a documented, release-mode safety net for
    // that invariant, not an expected path.
    final AsyncValue<List<EffectiveDay>> schedule =
        scheduleAsync ?? const AsyncValue<List<EffectiveDay>>.loading();

    // NOTE (2026-08-17) — both fallbacks below pass `window: null`, which means
    // `state.items` reaches `BookingsTimelineGrid` UNFILTERED:
    // `bookingsInsideScheduleWindow` runs only on the `data:` branch, for an
    // INTERVAL day, once a real window has resolved. `loading` is the state of
    // every cold open and `error` is permanent, so that filter can NEVER be
    // what bounds the grid's extent. The bound lives in the grid itself
    // (`BookingsTimelineGrid._kMaxEndMinute`) precisely because of this
    // ordering — see that constant's doc before changing either side.
    return schedule.when(
      // Never flash the gray state while the schedule is still resolving —
      // render exactly as `useScheduleWindow: false` would, using the
      // legacy booking-derived window, until a genuine verdict lands.
      loading: () => _body(context, window: null),
      // Same fallback on error — an unreachable schedule endpoint must not
      // read as "no working hours" to the master.
      error: (Object _, StackTrace _) => _body(context, window: null),
      data: (List<EffectiveDay> days) {
        final EffectiveDay? resolved = _effectiveDayFor(days, day);
        final ScheduleTimelineWindow? window = resolved == null
            ? null
            : scheduleWindowFor(resolved);
        // `resolved == null` is checked ALONGSIDE `window == null` purely for
        // flow-typing (repo style forbids `!`): by construction `window` is
        // null whenever `resolved` is (see the ternary above), so this OR
        // never changes which real-world days land here — it only lets the
        // analyzer promote [resolved] to non-null below, alongside [window].
        if (window == null || resolved == null) {
          // No `!` (repo style) — the constructor assert on
          // [BookingsDiscoveryView] guarantees [onAddWorkingHours] is set
          // whenever [useScheduleWindow] AND [canAddWorkingHours] are both
          // `true`, which is the only way the CTA branch is ever reached; the
          // `??` fallback is a documented, release-mode safety net for that
          // invariant, not an expected path.
          //
          // Phase 330 — when [canAddWorkingHours] is `false` the CTA is
          // ABSENT and `onAddHours` is handed `null`, so the callback is
          // never resolved at all and a `null` [onAddWorkingHours] is
          // legitimate rather than a violated invariant.
          final ValueChanged<DateTime> addWorkingHours =
              onAddWorkingHours ??
              (DateTime _) => throw StateError(
                'onAddWorkingHours must be set when useScheduleWindow and '
                'canAddWorkingHours are both true — see '
                'BookingsDiscoveryView\'s constructor assert.',
              );
          return MasterBookingsNoWorkingHoursState(
            dayOff: resolved?.source == EffectiveSource.overrideDayOff,
            onAddHours: canAddWorkingHours ? () => addWorkingHours(day) : null,
          );
        }

        // ═══════════════════════════════════════════════════════════════
        // EXPLICIT_TIMES days — a UNION list of declared-time cards, never
        // a filtered grid. See `declared_time_cards.dart`'s header for the
        // full correctness contract. Gated on [EffectiveDay.isExplicitTimes]
        // alone — every INTERVAL day falls through to the unchanged
        // `bookingsInsideScheduleWindow` + `BookingsTimelineGrid` path below.
        //
        // `state.items` is handed through UNFILTERED (never
        // `bookingsInsideScheduleWindow` — that predicate is a GRID concept
        // and would silently drop a booking whose start does not match any
        // declared time), so both the header count ([_body]'s `count`) and
        // the rendered card set come from the exact same list and can never
        // disagree — the same invariant `visibleBookingsFor` protects for
        // INTERVAL days, held here by construction instead.
        //
        // "UNFILTERED" IS CLIENT-SIDE ONLY. `state.items` is already narrowed
        // by the master's own status/service filter, SERVER-SIDE — which is
        // why [showsAllOccupancy] has to travel alongside it: this list
        // cannot tell a free declared time from one whose booking the filter
        // hid. See `declared_time_cards.dart`'s "FREE CARDS ARE A CLAIM".
        if (resolved.isExplicitTimes) {
          return _body(
            context,
            window: window,
            visibleItems: state.items,
            declaredTimes: resolved.times,
          );
        }

        // mobile-security HIGH fix (this session): the ONE filtering
        // computation — see `bookingsInsideScheduleWindow`'s doc. Its result
        // feeds BOTH the header count and the grid's card set below
        // ([_body]), so the two can never read different numbers.
        //
        // `visibleBookingsFor`, NOT `bookingsInsideScheduleWindow` directly
        // (mobile-perf MEDIUM fix, this session) — see [visibleBookingsFor]'s
        // doc: this keeps the result's identity stable across a rebuild
        // where `state.items` and the resolved window haven't changed.
        final List<Booking> visible = visibleBookingsFor(
          state.items,
          day,
          window,
        );
        return _body(context, window: window, visibleItems: visible);
      },
    );
  }

  /// The resolved [EffectiveDay] matching [day] out of [days] (a single-day
  /// range normally returns exactly one entry, but this scans defensively
  /// rather than assuming index 0). `null` when the range genuinely does not
  /// cover [day] — treated exactly like an unresolved/no-hours day by [build]
  /// (falls through to the "no working hours" state) rather than crashing.
  static EffectiveDay? _effectiveDayFor(List<EffectiveDay> days, DateTime day) {
    for (final EffectiveDay d in days) {
      if (d.date.year == day.year &&
          d.date.month == day.month &&
          d.date.day == day.day) {
        return d;
      }
    }
    return null;
  }

  /// The count line, the truncation notice, then the timeline or the
  /// filter-aware empty pair. [window] is `null` for every call site that
  /// predates this feature (and for `useScheduleWindow: true`'s
  /// loading/error/fallback branches); non-null only once a real
  /// working-hours window has resolved, in which case it is threaded through
  /// to [BookingsTimelineGrid] to bound the grid.
  ///
  /// [visibleItems] — mobile-security HIGH fix (this session): the master's
  /// own bookings, already filtered to [window] by
  /// [bookingsInsideScheduleWindow] (see [build]'s `data:` branch) — EXCEPT
  /// on an EXPLICIT_TIMES day (see [declaredTimes]), where it is [state.
  /// items] handed through UNFILTERED, since `DeclaredTimeCards` unions
  /// rather than filters. `null` for every call site above where no window
  /// has resolved (legacy path, loading, error) — in which case this uses
  /// `state.items`/`state.totalElements` exactly as before this feature, so
  /// the `useScheduleWindow: false` behaviour is provably untouched.
  /// Non-null drives BOTH the rendered count and the timeline body's own
  /// bookings from the SAME list, so they cannot disagree.
  ///
  /// [declaredTimes] — non-null ONLY when [build]'s `data:` branch resolved
  /// an EXPLICIT_TIMES [EffectiveDay] ([EffectiveDay.times]). When set, this
  /// renders `DeclaredTimeCards` instead of `BookingsTimelineGrid` — see
  /// `declared_time_cards.dart`'s header for the full contract. `null` for
  /// every INTERVAL-day call site, which keeps rendering the grid exactly as
  /// before this feature.
  Widget _body(
    BuildContext context, {
    required ScheduleTimelineWindow? window,
    List<Booking>? visibleItems,
    List<TimeOfDay>? declaredTimes,
  }) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<Booking> items = visibleItems ?? state.items;
    // Phase 21.12 — built from the SAME `items` the header count below reads
    // and the grid renders, so the columns cannot partition a different list
    // than the one that was counted.
    // Phase 336 — `day` is this widget's own field, the SAME one
    // [boardWindowBuilder] is handed in [build] and the same one the grid
    // renders, so the columns' day-off marks and the timeline's bounds can
    // never describe two different dates.
    // 2026-09-18 — [masterIds] is the «Майстер» selection, EMPTY for "every
    // master". It narrows the ROSTER inside the host's partition, never this
    // `items` list: the count recomputed from `columns` a few lines down
    // therefore follows the filter automatically and still cannot disagree
    // with the cards on screen. Both master routes pass `const {}` here and
    // a `null` builder ignores it outright, so neither is touched.
    final List<TimelineBoardColumn>? columns = columnsBuilder?.call(
      items,
      day,
      masterIds,
    );
    // `totalElements` is the SERVER's whole-day count (see
    // `bookings_day_state.dart`'s header) — kept ONLY as the legacy/loading/
    // error fallback. Once a window has resolved, `visibleItems!.length` is
    // what actually renders below, so that is what the header must say.
    //
    // STILL EXACT ON THE EXPLICIT_TIMES BRANCH after free-card suppression,
    // and in fact tighter than before: `DeclaredTimeCards` renders exactly
    // one card per booking in [items] (pass 1 match or pass 2 stray — no
    // booking is ever dropped), plus free cards, which are not bookings and
    // were never counted. Suppressing the free cards removes only uncounted
    // rows, so under a filter this line reads the number of BOOKINGS
    // matching that filter — which is now also the exact number of cards on
    // screen.
    int count = visibleItems?.length ?? state.totalElements;
    // Phase 21.12 — on the salon board the RENDERED set is the columns, not
    // `items`: a booking whose master has since left the salon has no column
    // to sit in and is not drawn. Counting `items` there would print a number
    // one higher than the cards on screen — the exact header-vs-cards
    // divergence `bookingsInsideScheduleWindow` was extracted to close on the
    // master branch. Recomputed from the same `columns` the grid is handed, so
    // the two come off one source. `null` columns leaves the line above
    // untouched, so both master routes are unaffected.
    if (columns != null) {
      int rendered = 0;
      for (final TimelineBoardColumn column in columns) {
        rendered += column.bookings.length;
      }
      count = rendered;
    }

    // Whether the EXPLICIT_TIMES branch below will emit NO free cards — see
    // `declared_time_cards.dart`'s "FREE CARDS ARE A CLAIM" section. Needed
    // by the empty gate immediately below: with the free cards gone, a
    // filtered day matching no booking has literally nothing left to draw.
    // Always `false` on the INTERVAL branch (`declaredTimes == null`), which
    // is what keeps that path byte-for-byte unchanged.
    final bool suppressesFreeCards =
        declaredTimes != null && !showsAllOccupancy;

    // THE SECOND LOCKSTEP, made loud. The empty gate below routes a
    // free-card-suppressed day to [MasterBookingsNoResultsState] (which has a
    // clear-filters CTA) purely because `!showsAllOccupancy` implies the
    // master filtered — see [BookingsDayQuery.showsAllOccupancy]'s lockstep
    // note. That implication holds only while
    // [BookingStatus.hiddenFromDayListByDefault] excludes both CONFIRMED and
    // COMPLETED: add either and the DEFAULT, UNFILTERED wire set would fail
    // the predicate, and a day with genuine declared times would silently
    // render [MasterBookingsEmptyState] with no way out of a filter the
    // master never set. Not reachable today — which is exactly why it needs
    // an assert rather than a comment. Debug-only: stripped from release, so
    // it cannot change shipped behaviour, only fail a dev/test build loudly.
    assert(
      showsAllOccupancy || hasFilters,
      'showsAllOccupancy is false on a query the master did not filter — '
      'BookingStatus.hiddenFromDayListByDefault must exclude CONFIRMED and '
      'COMPLETED for the empty gate below to pick the right copy',
    );

    // `state.isEmpty` (the day has nothing at all) necessarily makes
    // `state.items` empty too, and a status/service filter that matches
    // nothing on this day also lands here — as does a day whose bookings
    // exist but ALL fall outside the resolved working-hours window. Which
    // COPY renders is entirely `hasFilters`' job — see that field's doc.
    // Reachable regardless of [window]: a working day with genuinely zero
    // (visible) bookings is "no bookings", not "no working hours" (that
    // verdict is [build]'s job, decided BEFORE this method is ever called —
    // see the class doc).
    //
    // ── THE SECOND DISJUNCT, `suppressesFreeCards` (bug fix, 2026-08-13) ──
    // `window == null` alone made this branch UNREACHABLE on an
    // EXPLICIT_TIMES day: a resolved explicit-times day always has a non-null
    // window, so «Немає записів за цим фільтром» could never render there.
    // That was harmless only while a filtered day still drew a column of free
    // cards — which was itself the bug. With those suppressed, a filtered day
    // matching no booking would go BLANK, so the filter-aware state is
    // re-enabled for exactly that case.
    //
    // The two empties are NOT conflated: `suppressesFreeCards` implies the
    // master narrowed the list ([BookingsDayQuery.showsAllOccupancy]'s doc —
    // neither the default wire set nor the select-all empty set can fail that
    // predicate), so `hasFilters` below is necessarily `true` here and the
    // filter copy is the one that renders. A genuinely-unfiltered empty day
    // is occupancy-COMPLETE, never reaches this disjunct, and keeps drawing
    // its declared times as free cards; the `window == null` call sites keep
    // showing «Немає записів» exactly as before.
    //
    // BUG FIX (user-reported) — gated on `window == null` now, not on
    // `items.isEmpty` alone. Once a real working-hours window has resolved,
    // the master's day HAS hours — an empty result (zero bookings, bookings
    // that all fall outside the window, or a filter matching nothing) must
    // still render the hour ruler AND gridlines, just with no cards on them,
    // so the master can see the shape of their working day even when it's
    // empty. Locked product decision: no accompanying empty-state text in
    // that case — just the grid. `window == null` covers every call site
    // that predates this feature (`useScheduleWindow: false`, and
    // `useScheduleWindow: true`'s own loading/error fallbacks — see [build]),
    // which keep the illustrated empty states exactly as before.
    // Phase 21.12 — `columns == null` keeps the two illustrated empty states
    // exactly where they were on both master routes. On the salon board an
    // empty day still draws the roster strip and the ruled, card-less grid
    // (the same locked decision that makes a resolved-window master day render
    // its empty grid rather than an illustration): the owner must be able to
    // see WHICH masters are free, which an illustration cannot say. A salon
    // with no masters AT ALL is a different situation — `columns` is then
    // non-null but EMPTY, and the board's own roster empty state covers it.
    if (items.isEmpty &&
        columns == null &&
        (window == null || suppressesFreeCards)) {
      // The two empties are genuinely different situations — see
      // `master_bookings_states.dart`'s header. `hasFilters` is the whole
      // distinction: with no filter active, an empty result means this day is
      // free; with one, it means this filter matches nothing on this day.
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: <Widget>[
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.6,
            child: hasFilters
                ? MasterBookingsNoResultsState(onClearFilters: onClearFilters)
                : const MasterBookingsEmptyState(),
          ),
        ],
      );
    }

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            VelvetSpacing.lg,
            0,
            VelvetSpacing.lg,
            VelvetSpacing.sm,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  l10n.masterBookingsCount(count),
                  key: const Key('master-bookings-count'),
                  style: VelvetText.label(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        // A genuinely reachable case, not a defensive one — see
        // `MasterBookingsTruncatedNotice`'s doc. Gated on `state.isTruncated`
        // alone (the server's own ">100 bookings this day" signal), same as
        // always — [visibleItems] narrows WHICH of those bookings render, it
        // says nothing about whether the day overflowed the server's page.
        if (state.isTruncated) const MasterBookingsTruncatedNotice(),
        Expanded(
          child: Padding(
            // The LEFT inset is branch-dependent — see [_kTimelineLeftInset].
            // Only the ruler-bearing timeline grid moves left; the
            // declared-times branch keeps `VelvetSpacing.lg` so its flush
            // cards stay aligned with the 24dp day header above.
            // Phase 21.12 — three branches now, and the THIRD is selected by
            // `columns != null` alone. A `declaredTimes` day cannot occur on
            // the salon board (`useScheduleWindow` is false there, so
            // `declaredTimes` is always null on that scope), so the order of
            // these two tests is not load-bearing — only their independence.
            padding: declaredTimes != null
                ? _kDeclaredBodyPadding
                : (columns != null
                      ? _kBoardBodyPadding
                      : _kTimelineBodyPadding),
            child: declaredTimes != null
                ? DeclaredTimeCards(
                    declaredTimes: declaredTimes,
                    bookings: items,
                    day: day,
                    showsAllOccupancy: showsAllOccupancy,
                    onTapBooking: onBookingTap,
                  )
                // ONE widget, two scopes. `columns` is null and `density` is
                // the default on every pre-existing call site, so the two
                // master routes reach the identical constructor invocation
                // they always have. See `bookings_timeline_grid.dart`'s
                // "ADDENDUM 10".
                : BookingsTimelineGrid(
                    bookings: items,
                    day: day,
                    onBookingTap: onBookingTap,
                    scheduleFirstMinute: window?.firstMinute,
                    scheduleWindowEndMinute: window?.windowEndMinute,
                    density: columns == null
                        ? TimelineDensity.master
                        : TimelineDensity.salon,
                    columns: columns,
                    selectedMasterId: selectedMasterId,
                    onSelectMaster: onSelectMaster,
                  ),
          ),
        ),
      ],
    );
  }
}

/// The screen header. `onBack` renders a back arrow when non-null; `null` on
/// a bottom-nav tab root (the master's own screen never sets it).
class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.onBack,
    required this.activeFilterCount,
    required this.onOpenFilters,
    this.subtitle,
    this.onAdd,
    this.onOpenArchive,
  });

  final String title;

  /// Phase 21.12 — `null` (both master routes) emits NOTHING: the title stays
  /// a bare `Text` in the `Expanded`, so the header's height, its `Row`'s
  /// children and their vertical centring are all byte-identical. Non-null
  /// wraps the title in a two-line `Column` — see [build].
  final String? subtitle;
  final VoidCallback? onBack;
  final int activeFilterCount;
  final VoidCallback onOpenFilters;

  /// Finding #6 — the add-booking affordance.
  ///
  /// Phase 329: `null` hides it ENTIRELY (button not rendered), exactly like
  /// [onOpenArchive] below — the header grew a second optional trailing
  /// control rather than a parallel `bool` + non-null callback, so the two
  /// read the same way. Non-null on every pre-existing path: the host
  /// ([BookingsDiscoveryView.canCreateBooking]) defaults to `true`, and only
  /// a read-only viewer (`SALON_MASTER`) resolves it to `null`.
  ///
  /// Was previously documented as "always shown" — that was true while this
  /// view had exactly one host (the independent master's own bookings). The
  /// track that gives an invited `SALON_MASTER` this same screen read-only is
  /// what made the affordance conditional.
  final VoidCallback? onAdd;

  /// Phase 231 — the archive button. `null` hides it entirely; see
  /// [BookingsDiscoveryView.onOpenArchive]'s doc.
  final VoidCallback? onOpenArchive;

  // Hoisted — `Color.withValues` and `BorderRadius.circular` are not const,
  // so this can't be `static const`, but resolving once at class-load time
  // avoids a fresh allocation on every header rebuild (mirrors the same fix
  // pattern used throughout `master_booking_card.dart`).
  static final BoxDecoration _addButtonDecoration = BoxDecoration(
    color: BrandColors.accentDeep,
    // A rounded-rect, NOT `shape: BoxShape.circle` — the Impeller-GLES
    // circle+shadow artifact (resolved 34db74f / the guarded avatars in
    // `impeller_circle_shadow_guard_test.dart`) is specifically triggered by
    // pairing `BoxShape.circle` with a `boxShadow`. A `BorderRadius.circular`
    // of half the side length renders visually identical on a square box
    // while routing through Impeller's correct RRect blur path.
    borderRadius: BorderRadius.circular(20),
    boxShadow: const <BoxShadow>[
      BoxShadow(color: Color(0x506A4A28), offset: Offset(0, 3), blurRadius: 8),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: BrandColors.accent.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          VelvetSpacing.lg,
          VelvetSpacing.md,
          VelvetSpacing.lg,
          VelvetSpacing.sm,
        ),
        child: Row(
          children: <Widget>[
            if (onBack != null) ...<Widget>[
              NeumorphicIconButton(
                key: const Key('bookings-discovery-back'),
                icon: Icons.arrow_back_ios_new_rounded,
                semanticLabel: l10n.bookingsDiscoveryBackSemantics,
                onTap: onBack!,
              ),
              const SizedBox(width: VelvetSpacing.md),
            ],
            Expanded(
              child: subtitle == null
                  // The pre-existing shape, untouched — see [subtitle].
                  ? Text(
                      title,
                      style: VelvetText.pageTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          style: VelvetText.pageTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          subtitle!,
                          key: const Key('bookings-discovery-subtitle'),
                          style: VelvetText.feedbackMutedSm,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
            ),
            const SizedBox(width: VelvetSpacing.sm),
            if (onOpenArchive != null) ...<Widget>[
              NeumorphicIconButton(
                key: const Key('master-bookings-open-archive'),
                icon: Icons.inventory_2_outlined,
                semanticLabel: l10n.masterArchiveOpenSemantics,
                onTap: onOpenArchive!,
              ),
              const SizedBox(width: VelvetSpacing.sm),
            ],
            BookingsFilterButton(
              activeCount: activeFilterCount,
              onTap: onOpenFilters,
            ),
            // Phase 329 — the (+) affordance and ITS OWN leading gap are
            // dropped together when [onAdd] is null. Spreading the
            // `SizedBox` inside the guard (rather than leaving it above as
            // an unconditional sibling) is what keeps a read-only header
            // from ending in 8dp of stray trailing space after the filter
            // button. With a non-null [onAdd] the emitted child order is
            // unchanged — gap, then button — so every existing caller
            // renders byte-identically.
            if (onAdd != null) ...<Widget>[
              const SizedBox(width: VelvetSpacing.sm),
              Semantics(
                button: true,
                label: l10n.masterBookingsAddSemantics,
                child: GestureDetector(
                  key: const Key('master-bookings-add'),
                  onTap: onAdd,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    height: 40,
                    width: 40,
                    decoration: _addButtonDecoration,
                    child: const Icon(
                      Icons.add_rounded,
                      color: BrandColors.white,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
