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
//  * THE «Майстер» FILTER SHEET SECTION. `BookingsDiscoveryView
//    .showMasterFilter` is the seam and it stays `false`: the endpoint takes
//    exactly ONE `masterId` while every section of `BookingsFilterSheet` is
//    multi-select, and narrowing the board to one master defeats the board.
//    `BookingsDayQuery.salon.masterId` is wired end to end and is what such a
//    sheet would set. The roster chips' own tap is a HIGHLIGHT, not a filter —
//    see `BookingsTimelineGrid.selectedMasterId`.
//  * A BOOKING-ACTION FOOTER. Cards route to `BookingDetailScreen`
//    ([RouteNames.bookingDetail]), which already role-branches its own
//    provider actions off `bookingViewerRoleProvider` and already offers
//    «Скасувати запис» (`PATCH /bookings/{id}/decline`) to an owner and an
//    assigned admin. Re-deciding that here would be a second, drifting copy of
//    a gate the detail screen already owns.

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
import '../../booking/presentation/widgets/bookings_timeline_grid.dart';
import '../../booking/presentation/widgets/master_column_strip.dart';
import '../../booking/presentation/widgets/my_bookings_states.dart';
import '../application/salon_manage_capability.dart';
import '../application/salon_management_profile_notifier.dart';
import '../domain/salon_master_summary.dart';

/// The salon-wide bookings board for one salon.
class SalonBookingsScreen extends ConsumerWidget {
  const SalonBookingsScreen({required this.salonId, super.key});

  final String salonId;

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

  /// Partitions ONE day's bookings across the salon's roster, in roster order.
  ///
  /// Every column is emitted, including a master with nothing booked — an
  /// absent column would silently renumber every column to its right and
  /// un-pin the roster chips above them. The empty column renders its own
  /// «Вільний день» marker (`BookingsTimelineGrid`'s `_BoardStack`).
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
  @visibleForTesting
  static List<TimelineBoardColumn> columnsFor(
    List<Booking> dayItems,
    List<SalonMasterSummary> roster,
  ) {
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
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
    if (!ref.watch(canManageSalonProvider(salonId))) {
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
      salonMastersRosterProvider(salonId),
    );
    // The salon's own name, under the heading — an owner of several salons
    // must be able to tell whose board this is. `null` while it RESOLVES
    // renders no subtitle line at all rather than a placeholder that would
    // reflow; a FAILURE surfaces, for the same M4 reason as the roster (the
    // profile fetch is the second ownership-sensitive call this screen makes,
    // and a silently missing subtitle is how a 403 on it used to read).
    final AsyncValue<SalonManagementProfileData> profileState = ref.watch(
      salonManagementProfileProvider(salonId),
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
            ref.invalidate(salonMastersRosterProvider(salonId));
            ref.invalidate(salonManagementProfileProvider(salonId));
          },
        ),
      );
    }

    final List<SalonMasterSummary> roster =
        rosterState.value ?? const <SalonMasterSummary>[];
    final String? salonName = profileState.value?.$1.name;

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
          salonId: salonId,
        ),
        title: l10n.salonBookingsTitle,
        subtitle: salonName,
        // A bottom-nav destination inside the salon shell — nothing to pop.
        onBack: null,
        // See this file's "WHAT IS DELIBERATELY NOT HERE".
        showMasterFilter: false,
        // The working-hours window is a SINGLE master's question ("which
        // hours does THIS person work"), and this board shows many at once.
        // `BookingsDiscoveryView.useScheduleWindow`'s own doc names this exact
        // scope as the one that must leave it false until a per-teammate
        // answer exists. The grid therefore bounds itself by the day's
        // bookings, as it always did before that feature.
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
        columnsBuilder: (List<Booking> dayItems) =>
            columnsFor(dayItems, roster),
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
        // `RouteNames.salonStaffBookingDetail` — `/salon/bookings/:id`.
        //
        // ⚠ THE SCREEN AND THE DESTINATION SIT UNDER DIFFERENT PREFIXES, and
        // only the destination inherits a prefix gate (audit L7 — this note
        // used to claim the screen itself "mounts under `/salon/*`", which
        // would have a reader believe a second role gate applies here that
        // does not). THIS screen is slot 1 of [SalonShellScreen] at
        // `RouteNames.salonShell` = `/salons/:salonId/shell` — no path segment
        // of its own, and `/salons/*` is NOT one of `auth_redirect.dart`'s
        // role-gated prefixes. Its only router-level gate is
        // `salonManageGuard`, which deliberately ADMITS an owner whose
        // `mySalonsProvider` has not resolved — which is why `build` above
        // binds ownership with `canManageSalonProvider` itself.
        //
        // ⚠ NOT `RouteNames.bookingDetail`. That resolves to `/bookings/:id`,
        // and `/bookings` is a CLIENT branch prefix in `auth_redirect.dart`:
        // every non-CLIENT role that reaches it is redirected to
        // `roleHomePath(role)`. An owner tapping a card on their own board was
        // bounced clean out of the salon shell to the owner home and never saw
        // a detail screen at all. NOT `masterBookingDetail` either —
        // `/master/*` is INDEPENDENT_MASTER-only.
        //
        // The destination is the SAME [BookingDetailScreen] all three paths
        // render; only the prefix (and therefore the role gate it inherits)
        // differs. It role-branches its own provider actions — including
        // «Скасувати запис» → the decline endpoint — off
        // `bookingViewerRoleProvider`. See the file header.
        onBookingTap: (Booking booking) =>
            context.push(RouteNames.salonStaffBookingDetail(booking.id)),
      ),
    );
  }
}
