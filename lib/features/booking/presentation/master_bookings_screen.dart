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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';

import 'bookings_discovery_view.dart';
import '../domain/booking.dart';
import '../domain/bookings_day_query.dart';

/// The independent master's own booking list. A thin wrapper — see the file
/// header.
class MasterBookingsScreen extends ConsumerWidget {
  const MasterBookingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return BookingsDiscoveryView(
      // A day is required by `BookingsDayQuery.of`, but `BookingsDiscoveryView`
      // deliberately does NOT use this field as its initial selection — it
      // derives Kyiv "today" itself (`dateOnly(toBeauticaTime(DateTime.now
      // ()))`) rather than trusting a host-local `DateTime.now()` stamped
      // here. See that file's header for why the day is owned there, not
      // here.
      query: BookingsDayQuery.of(day: DateTime.now()),
      title: l10n.masterBookingsTitle,
      // Bottom-nav tab root — no back affordance.
      onBack: null,
      // A single master's own list never offers the teammate filter.
      showMasterFilter: false,
      onBookingTap: (Booking booking) =>
          context.push(RouteNames.masterBookingDetail(booking.id)),
    );
  }
}
