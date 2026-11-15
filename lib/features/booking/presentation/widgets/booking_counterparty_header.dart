// Phase 7.2 — the counterparty strip on «Деталі запису».
//
// A booking has two sides. The detail screen shows the viewer the OTHER one:
//   * a CLIENT viewer sees the master / salon  → the shipped `MasterStrip`
//     (via `MasterStrip.fromBooking`, `_MasterStrip` below).
//   * a PROVIDER viewer sees the CLIENT       → [BookingClientStrip]
//     (`booking_client_strip.dart`, promoted from this file's `_ClientStrip`
//     2026-11-14), on the same `MasterStripShell` card (photo + name + ★).
//
// This widget is the whole of the header half of locked decision D5's
// "branch ONLY the counterparty header and the footer slot". It is a switch,
// not a second screen.
//
// ## The guest/LINK case is the ORDINARY case, not an edge case
//
// A LINK booking has `client_id IS NULL` — there is no registered account.
// That is the entire link-booking flow, not a rare fault, so a null-client
// crash here would take out the master's detail screen for a whole class of
// their bookings.
//
// It resolves more simply than the Phase 7.2 phase doc suggests, though: the
// backend's `BookingDetailResponse` ALREADY falls the name back to the
// booking's OTP-verified `guestName`/`guestSurname` server-side, so
// `clientFirstName`/`clientLastName` carry a usable name on a guest booking
// and the wire has no `guestName` field for the client to read. What this
// widget still guards is the genuinely nameless row — an old or partial
// record — which renders the localized «Гість» rather than an empty strip.
//
// SEC: the client's name is PII. The hosting screen holds the
// `ScreenProtectionManager` for its lifetime; this widget adds no logging.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/navigation/single_flight.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/routing/route_names.dart';

import '../../application/booking_viewer_role.dart';
import '../../domain/booking.dart';
import '../../domain/booking_status.dart';
import 'booking_client_strip.dart';
import 'master_strip.dart';

/// The other side of [booking], as seen by a [viewer].
class BookingCounterpartyHeader extends StatelessWidget {
  const BookingCounterpartyHeader({
    super.key,
    required this.booking,
    required this.viewer,
    this.showPerformingMaster = false,
    this.onMore,
  });

  final Booking booking;
  final BookingViewerRole viewer;

  /// Provider branch only: also shows the master who PERFORMS the booking
  /// (inert, under the client strip). Set for a salon owner/admin viewing a
  /// booking performed by another master; default `false` changes nothing.
  final bool showPerformingMaster;

  /// ADDITIVE (phase 425 D2): provider branch only — renders a quiet «⋯» at
  /// the end of the client strip that opens the client actions sheet (report
  /// / block / unblock). `null` (the default) renders the strip exactly as
  /// before; ignored on the client branch.
  final VoidCallback? onMore;

  /// Widget key of the client strip's «⋯» hit target.
  static const Key clientMoreKey = BookingClientStrip.moreKey;

  @override
  Widget build(BuildContext context) {
    if (!viewer.isProvider) return _MasterStrip(booking: booking);
    if (!showPerformingMaster || booking.masterId.isEmpty) {
      return BookingClientStrip.fromBooking(booking, onMore: onMore);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        BookingClientStrip.fromBooking(booking, onMore: onMore),
        const SizedBox(height: VelvetSpacing.sm),
        _PerformingMasterStrip(booking: booking),
      ],
    );
  }
}

/// The MASTER as the client sees them — name, title, ★ rating — and the
/// client's route into that master's reviews.
///
/// The strip is rendered OUTSIDE «Деталі запису»'s status switch, so making it
/// tappable gives every status a route to the master's reviews at once —
/// including `NOT_COMPLETED`, whose action footer is deliberately empty and
/// which therefore had no route to the master at all before this.
class _MasterStrip extends StatelessWidget {
  const _MasterStrip({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final bool isDead =
        booking.status == BookingStatus.cancelled ||
        booking.status == BookingStatus.declined;

    // `booking_mapper.dart:119` maps `masterId: dto.masterId ?? ''`, so an
    // empty id is reachable on a partial payload — and it is now a NAVIGATION
    // TARGET. `/masters//reviews` cannot match `/masters/:masterId/reviews`
    // (go_router compiles `:masterId` to `[^/]+`) and `app_router.dart`
    // declares no `errorBuilder`, so the tap would dump the client on
    // go_router's default "page not found" screen. A blank id means "we don't
    // know which master" — the honest affordance is an INERT strip, not a
    // button that breaks.
    final String masterId = booking.masterId;
    final VoidCallback? openReviews = masterId.isEmpty
        ? null
        // TAPPABLE per the policy on `MasterStrip.onTap`: «Деталі запису» is a
        // terminal screen, so leaving it costs the client nothing. `push` (not
        // `go`) so the back gesture returns here with this screen's state
        // intact.
        : () => context.pushOnce(RouteNames.masterPublicReviews(masterId));

    final Widget strip = MasterStrip.fromBooking(
      booking,
      key: const Key('booking-detail-master-strip'),
      onTap: openReviews,
    );

    if (!isDead) return strip;

    // Dimmed on a dead booking, matching [BookingClientStrip]'s `Opacity`.
    //
    // Do NOT wrap this in a `RepaintBoundary` "to stop the splash repaint from
    // walking up into the `Opacity`". That was tried and reverted, and both
    // halves of the rationale were measured false:
    //   * `RenderOpacity.isRepaintBoundary => child != null && _alpha > 0`
    //     (`proxy_box.dart:884`). At alpha 179 the `RenderOpacity` ALREADY is
    //     the boundary, so `markNeedsPaint` from the ink stops there either
    //     way — an extra boundary just moves the mark down one node.
    //   * It cannot remove the `saveLayer`. The engine elides that only on
    //     group-opacity compatibility, a property of the picture's own draw
    //     ops (overlapping shadow + fill + border + avatar + text + splash,
    //     `isComplex = true`). Re-parenting the identical picture under one
    //     more container layer makes the flag LESS likely, never more.
    // Layer dumps confirmed it: `OpacityLayer → PictureLayer` without,
    // `OpacityLayer → OffsetLayer → PictureLayer` with. The residual
    // `saveLayer` is inherent to `Opacity` and bounded to a dead booking's
    // header while a splash runs; mobile-perf retracted the finding.
    // dim-gated: test/features/booking/presentation/booking_detail_screen_test.dart
    return Opacity(opacity: 0.7, child: strip);
  }
}

/// The master who PERFORMS the booking, as a salon owner/admin sees them —
/// the shipped [MasterStrip] (label «Запис до майстра», role, ★), inert, dimmed on a
/// dead booking like its [BookingClientStrip] sibling.
class _PerformingMasterStrip extends StatelessWidget {
  const _PerformingMasterStrip({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final bool isDead =
        booking.status == BookingStatus.cancelled ||
        booking.status == BookingStatus.declined;
    // dim-gated: test/features/booking/presentation/booking_detail_provider_view_test.dart
    return Opacity(
      opacity: isDead ? 0.7 : 1,
      child: MasterStrip.fromBooking(
        booking,
        key: const Key('booking-detail-performing-master-strip'),
      ),
    );
  }
}
