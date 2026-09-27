// Phase 7.6 — «Мої записи» for the independent master.
//
// Phase 7.11 — collapsed to a THIN WRAPPER over the shared
// `BookingsDiscoveryView`, mirroring the approved design's own
// `my_bookings_screen.dart` (a `StatelessWidget` that hands `bookings`,
// `title`, `onBack`, `showMasterFilter: false` straight to
// `BookingsDiscoveryScreen`). Every discovery control — the day rail, the
// timeline body, the four async states, the filter sheet, the count toolbar —
// now lives in `bookings_discovery_view.dart`, built ONCE so the salon-wide
// «Записи» screen can drop it in later without a rewrite (D11, the reuse
// seam).
//
// This file owns exactly three things now:
//   1. `showMasterFilter: false` — a single master's own list never offers
//      the teammate filter.
//   2. `onBack: null` — this is a bottom-nav tab ROOT in the master shell, so
//      there is no back affordance (mirrors the design's own null-onBack
//      case).
//   3. `onBookingTap` — `context.push`es the PROVIDER detail route. Note the
//      go_router gotcha: this push yields an `ImperativeRouteMatch` that is
//      dropped from `currentConfiguration.fullPath`, so nav-detection code
//      must read `leaf.matches.fullPath` instead — see
//      `RouteNames.masterBookingDetail` and `master_bookings_routing_test
//      .dart`.
//
// ## History this file used to carry (now retired, not void)
//
// Everything about pagination, prefetch latches, the vertical card list, the
// sort sheet, and the rail's «Всі» chip is GONE — not because it stopped
// mattering, but because Phase 7.9/7.10/7.11 replaced the whole mechanism
// with a day-scoped, single-fetch timeline. The three reasons Phase 7.6
// originally chose a vertical list over the design's timeline grid
// (unpaginatable, single-day-only, and a since-retired sort concern) are
// recorded in Phase 7.6's divergence note and Phase 7.9's header — read those
// before reintroducing a paginated list here; the underlying data layer no
// longer supports one (`bookingsDayProvider` returns exactly one Kyiv day per
// fetch). It is no longer `ref.keepAlive()`-free either — MEDIUM-2's bounded
// LRU cache pins the last few DISTINCT days visited (see
// `bookings_day_notifier.dart`'s header), which is not the same thing as the
// retired notifier's unconditional keepAlive.
//
// SEC: this screen renders client names and, through the detail it pushes,
// free-text notes — a heavier PII surface than the client-side «Мої записи».
// `BookingsDiscoveryView` acquires the app-wide `ScreenProtectionManager` for
// its own lifetime; this wrapper does not need to.
//
// Phase 7.14 — the master bottom nav bar, wired onto this screen HERE, not
// inside `BookingsDiscoveryView`.
//
// This was the last master "tab" that rendered no bottom nav — a dead end
// reachable only via nav tile 1, with no way back to the other tabs short of
// the OS back gesture. `MasterProfileScreen` (this surface's other tab root)
// already renders `VelvetBottomNavBar(activeIndex: 3)`; this screen now does
// the same at index 1 ("Мої записи").
//
// WHY THE BAR LIVES IN THIS FILE AND NOT IN THE SHARED VIEW: `BookingsDiscoveryView`
// is a deliberate salon-reuse seam (see that file's header) — a future
// salon-wide «Записи» screen drops it in verbatim via a `.salon(...)` query
// member. The bottom nav bar is master-specific chrome; baking it into the
// shared view would make the future salon screen silently inherit master
// navigation. So it is injected from the OUTSIDE, exactly like `onBookingTap`
// — navigation/chrome is the host's concern, never the shared view's.
//
// HOW IT IS COMPOSED: `BookingsDiscoveryView` already builds its own full
// `Scaffold` (header + day rail + timeline). Rather than touch that file, this
// wrapper nests it as the `body` of an outer `Scaffold` that supplies only
// `bottomNavigationBar`. This is the same pattern the approved
// `SalonManagementDesign` shell preview uses for reusing `BookingsDiscoveryScreen`
// under a shell's own `Scaffold(bottomNavigationBar: ...)` (see
// `docs/signup-designs/SalonManagementDesign/lib/screens/master_shell_screen
// .dart`). `Scaffold.extendBody` defaults to `false`, so the inner Scaffold is
// laid out with its bottom edge flush against the TOP of the outer
// `bottomNavigationBar` — no overlap, no clipping of the last timeline card.
// The inner Scaffold's own `SafeArea(bottom: false)` (see
// `bookings_discovery_view.dart`) was already opting OUT of the device's
// bottom safe-area inset; `VelvetBottomNavBar` claims that inset itself via
// its own internal `SafeArea(top: false)`, so it is claimed exactly once,
// not twice.
//
// NAV-BAR-HIDE ON THE PUSHED DETAIL: NOT NEEDED, and deliberately not
// implemented. `ab34c0a`'s "hide bottom nav on booking detail" fix applied to
// `ClientShell` — a PERSISTENT `StatefulShellRoute.indexedStack` where the
// bottom nav is hoisted above every branch and stays mounted across pushes
// within a branch, so it had to be told to disappear. The master surface has
// no such shell (see `app_router.dart`'s `RouteNames.masterBookings`
// registration comment) — this bar is built INSIDE this screen's own
// `build()`, not hoisted above it. `/master/bookings/:bookingId` is a nested
// `GoRoute` pushed with `context.push`, which mounts `BookingDetailScreen` as
// a brand-new full-screen page in the Navigator stack; this screen (bar
// included) is simply the page underneath it, never rebuilt, and is not
// visible until the detail pops. There is nothing to hide.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/api_date.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:beautica_mobile/shared/widgets/velvet_bottom_nav_bar.dart';

import 'bookings_discovery_view.dart';
import '../application/bookings_capability.dart';
import '../domain/booking.dart';
import '../domain/bookings_day_query.dart';

/// A provider's own booking list. A thin wrapper — see the file header.
///
/// Phase 330 — mounted TWICE, at two routes, as ONE widget: `/master/bookings`
/// for the `INDEPENDENT_MASTER` and `/staff/bookings` for the invited,
/// read-only `SALON_MASTER`. Every parameter below is ADDITIVE and NULLABLE
/// (or defaults to the pre-phase-330 literal), so the `/master/bookings`
/// registration — and every test that pumps `const MasterBookingsScreen()` —
/// renders byte-identically to before they existed. The read-only behaviour
/// itself is NOT a parameter: it comes from
/// `bookingCreationEnabledProvider` / `bookingTransitionsEnabledProvider`
/// (phase 328), which read the session. These parameters only say WHERE this
/// mount's own navigation lands, which is the host's concern, never the
/// session's.
class MasterBookingsScreen extends ConsumerWidget {
  const MasterBookingsScreen({
    super.key,
    this.detailRouteBuilder,
    this.archiveRoute,
    this.navServicesRoute,
    this.navScheduleRoute,
    this.navProfileRoute,
    this.canAddWorkingHours = true,
  });

  /// Builds the booking-detail path from a booking id. `null` (the
  /// `/master/bookings` mount and every existing test) means
  /// [RouteNames.masterBookingDetail]; the `/staff/bookings` mount passes
  /// [RouteNames.salonMasterBookingDetail] so the push does not land on a
  /// `/master/*` path the `/staff/*` viewer is gated off.
  final String Function(String bookingId)? detailRouteBuilder;

  /// The «Архів» header button's destination. `null` means
  /// [RouteNames.masterBookingsArchive]; the `/staff/bookings` mount passes
  /// [RouteNames.salonMasterBookingsArchive] (phase 332).
  final String? archiveRoute;

  /// [VelvetBottomNavBar] tile overrides — tiles 0 / 2 / 3. `null` (the
  /// `/master/bookings` mount) leaves each at the literal it has always used,
  /// so that bar stays `const`. Tile 1 is this screen itself
  /// (`activeIndex: 1`), so it resolves to `null` inside the bar regardless
  /// and needs no override here.
  final String? navServicesRoute;
  final String? navScheduleRoute;
  final String? navProfileRoute;

  /// Whether the "no working hours" empty state offers its
  /// «Додати робочі години» CTA. `true` (the `/master/bookings` mount and
  /// every existing test) is the pre-phase-330 behaviour exactly.
  ///
  /// `false` at the `/staff/bookings` mount: publishing working hours is a
  /// SCHEDULE write, which `scheduleEditableProvider` has resolved
  /// `SALON_MASTER → false` since phase 309 — the salon sets their hours, not
  /// them. A day with no hours is a common state for an invited master, so
  /// this CTA would otherwise be the one affordance on the read-only surface
  /// that still promised a write, landing them on a schedule screen with no
  /// pencil to tap.
  ///
  /// A structural flag passed at the ROUTE (mirroring
  /// `ServicesListScreen(writable: false)` at `/staff/services`), not a
  /// `ref.watch(scheduleEditableProvider)` here: that provider lives in
  /// `features/schedule/presentation/`, and a `features/booking/presentation/`
  /// import of it would be the cross-feature presentation→presentation import
  /// the architecture forbids.
  final bool canAddWorkingHours;

  /// The bottom bar, kept `const` for the default (`/master/bookings`) mount
  /// so that call site is byte-identical to before phase 330 — the three
  /// overrides are all `null` there, and a `const` instance is canonicalised
  /// and skipped on rebuild.
  ///
  /// The `/staff/bookings` branch CANNOT be `const`, and not for want of
  /// trying (mobile-perf LOW, 2026-09-15). The three arguments arrive as
  /// INSTANCE FIELDS, and Dart admits no constant expression over those:
  ///
  ///   * inline — `const VelvetBottomNavBar(servicesRoute: navServicesRoute…)`
  ///     is "Constant evaluation error: the variable is not a constant";
  ///   * hoisted into a field — `const MasterBookingsScreen(…) : _navBar =
  ///     VelvetBottomNavBar(servicesRoute: navServicesRoute…)` fails the same
  ///     way, with or without an explicit `const`. A const constructor's
  ///     initialiser must be *potentially constant*, and an object creation
  ///     over a parameter is not. So "cache the instance in a field" is not
  ///     expressible here either.
  ///
  /// The only shapes that WOULD be `const` both cost more than the allocation
  /// is worth: a `static const` bar built from `RouteNames.salonMaster*`
  /// hard-codes the host's routes into this screen — the exact coupling the
  /// phase-330 parameters exist to prevent, plus a fallback branch nothing
  /// exercises; and swapping the three route params for an injected bar
  /// widget would fork the repo-wide `nav*Route` convention that
  /// `ServicesListScreen` (`services_list_screen.dart:390`) also follows.
  ///
  /// The residual cost is one `VelvetBottomNavBar` (a `StatelessWidget` over
  /// four tiles) per rebuild of THIS screen — and `build` watches exactly one
  /// provider, `bookingCreationEnabledProvider`, which is session-derived and
  /// settles once. Not a per-frame allocation.
  VelvetBottomNavBar get _navBar =>
      navServicesRoute == null &&
          navScheduleRoute == null &&
          navProfileRoute == null
      ? const VelvetBottomNavBar(activeIndex: 1)
      : VelvetBottomNavBar(
          activeIndex: 1,
          servicesRoute: navServicesRoute,
          scheduleRoute: navScheduleRoute,
          profileRoute: navProfileRoute,
        );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String scheduleRoute = navScheduleRoute ?? RouteNames.masterSchedule;
    final String Function(String) detailRoute =
        detailRouteBuilder ?? RouteNames.masterBookingDetail;

    // Outer Scaffold exists ONLY to host the bottom nav bar — see the file
    // header for why it wraps rather than modifies `BookingsDiscoveryView`.
    return Scaffold(
      backgroundColor: BrandColors.base,
      body: BookingsDiscoveryView(
        // A day is required by `BookingsDayQuery.of`, but `BookingsDiscoveryView`
        // deliberately does NOT use this field as its initial selection — it
        // derives Kyiv "today" itself (`dateOnly(toBeauticaTime(DateTime.now
        // ()))`) rather than trusting whatever is stamped here. So this value
        // is a genuine no-op today (`BookingsDiscoveryView:210` overwrites
        // it) — but it is still Kyiv-anchored via `kyivToday`, not a bare
        // `DateTime.now()`, so a reader copying this call site as a template
        // learns the right pattern rather than the bug this whole track
        // exists to close (backlog :226). See that file's header for why the
        // day is owned there, not here.
        //
        // NO seed statuses, deliberately — and that is NOT the same as "show
        // every status". An empty seed means "the master has chosen no
        // filter", which `BookingsDiscoveryView` resolves on the wire to
        // `BookingStatus.visibleInDayListByDefault` (CANCELLED and DECLINED
        // hidden, NOT_COMPLETED kept — locked 2026-08-13). Seeding statuses
        // here would instead read as a master-chosen filter and light up the
        // funnel badge. See that file's "CANCELLED/DECLINED are hidden by
        // default" header section.
        query: BookingsDayQuery.of(day: kyivToday(ref.read(clockProvider))),
        title: l10n.masterBookingsTitle,
        // Bottom-nav tab root — no back affordance.
        onBack: null,
        // A single master's own list never offers the teammate filter.
        showMasterFilter: false,
        // The master's own screen is the ONE call site that bounds the
        // timeline by working hours instead of by bookings — see
        // `BookingsDiscoveryView.useScheduleWindow`'s doc.
        useScheduleWindow: true,
        // The "no working hours" empty state's CTA — routes to the
        // schedule screen with the day it was showing pre-selected
        // (`RouteNames.masterSchedule`'s `?date=` contract), so the master
        // can tap that day's pencil straight away rather than hunting for
        // it. `context.go`, not `context.push` — this is a bottom-nav
        // destination, matching `VelvetBottomNavBar`'s own navigation
        // (see that file's header).
        //
        // Phase 330 — the base path is [navScheduleRoute] (the same constant
        // tile 2 of the bottom bar uses), so the `/staff/bookings` mount
        // never emits a `/master/schedule` location its own `/staff/*` gate
        // would bounce. That mount passes `canAddWorkingHours: false`, so
        // this callback is unreachable there; it stays correctly aimed
        // anyway rather than left pointing at a bounced route.
        onAddWorkingHours: (DateTime date) =>
            context.go('$scheduleRoute?date=${toApiDate(date)}'),
        // Phase 330 — see [canAddWorkingHours].
        canAddWorkingHours: canAddWorkingHours,
        onBookingTap: (Booking booking) =>
            context.push(detailRoute(booking.id)),
        // Phase 231 — the master «Архів» page. Additive-only wiring (see
        // `bookings_discovery_view.dart`'s `onOpenArchive` doc).
        onOpenArchive: () =>
            context.push(archiveRoute ?? RouteNames.masterBookingsArchive),
        // Phase 329 — the (+) add-booking button is HIDDEN (not disabled)
        // for a viewer who may not create bookings, i.e. the invited,
        // read-only `SALON_MASTER`. `watch`, not `read`: the capability is
        // derived from the session and must re-render the header the moment
        // the role settles or the session is invalidated. Every other role
        // this screen serves resolves `true`, so the independent master's
        // header is unchanged. See `bookingCreationEnabledProvider`'s doc for
        // why it reads the STRICT settled selector.
        canCreateBooking: ref.watch(bookingCreationEnabledProvider),
      ),
      // Tile 1 («Мої записи») — this screen IS that destination, so the bar
      // short-circuits it to `null` and no `bookingsRoute` override is
      // needed. The other three tiles are aimed by the host (phase 330): at
      // `/master/*` by default (the bar's own literals, so this stays `const`
      // for the INDEPENDENT_MASTER mount) and at `/staff/*` when the
      // `/staff/bookings` route supplies them.
      bottomNavigationBar: _navBar,
    );
  }
}
