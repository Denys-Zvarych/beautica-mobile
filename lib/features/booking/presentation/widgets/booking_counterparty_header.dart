// Phase 7.2 — the counterparty strip on «Деталі запису».
//
// A booking has two sides. The detail screen shows the viewer the OTHER one:
//   * a CLIENT viewer sees the master / salon  → the shipped `MasterStrip`
//     (via `MasterStrip.fromBooking`, `_MasterStrip` below).
//   * a PROVIDER viewer sees the CLIENT       → `_ClientStrip`, below, on the
//     same `MasterStripShell` card (photo + name + ★ rating).
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
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';

import '../../application/booking_viewer_role.dart';
import '../../domain/booking.dart';
import '../../domain/booking_display_x.dart';
import '../../domain/booking_status.dart';
import 'master_strip.dart';
import 'master_strip_shell.dart';

/// The other side of [booking], as seen by a [viewer].
class BookingCounterpartyHeader extends StatelessWidget {
  const BookingCounterpartyHeader({
    super.key,
    required this.booking,
    required this.viewer,
  });

  final Booking booking;
  final BookingViewerRole viewer;

  @override
  Widget build(BuildContext context) {
    return viewer.isProvider
        ? _ClientStrip(booking: booking)
        : _MasterStrip(booking: booking);
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
        : () => context.push(RouteNames.masterPublicReviews(masterId));

    final Widget strip = MasterStrip.fromBooking(
      booking,
      key: const Key('booking-detail-master-strip'),
      onTap: openReviews,
    );

    if (!isDead) return strip;

    // Dimmed on a dead booking, matching `_ClientStrip`'s `Opacity` below.
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

/// The CLIENT as the provider sees them — the SAME [MasterStripShell] card the
/// client viewer sees the master in: photo (monogram fallback), name, a muted
/// «Запис за посиланням» qualifier on a guest booking, and the client's ★
/// rating (em-dash when unreviewed; none at all for a guest, who has no
/// account to be rated).
///
/// Reuses the shell directly rather than [MasterStrip]: that widget is
/// master-shaped (a [MasterType] role sub-line, the «Запис до майстра» caption,
/// master-worded semantics), whereas the shell is the data-agnostic frame the
/// task needs. Everything it adds is additive and null-by-default.
class _ClientStrip extends StatelessWidget {
  const _ClientStrip({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    // A cancelled/declined booking's counterparty is dimmed — the same
    // `Opacity(0.7)` treatment the master strip gets, so the two branches read
    // as one screen.
    final bool isDead =
        booking.status == BookingStatus.cancelled ||
        booking.status == BookingStatus.declined;

    final String displayName =
        booking.clientName ?? l10n.bookingDetailGuestClient;
    // The guest marker is shown ONLY for an actual guest booking
    // (`client_id IS NULL`) — never merely because a name is missing.
    final bool isGuest = booking.isGuestBooking;
    final double? rating = booking.clientDisplayRating;
    final int reviewCount = booking.clientReviewCount ?? 0;
    final String? qualifier = isGuest
        ? l10n.bookingDetailGuestBookingLabel
        : null;

    final String semantics;
    if (isGuest) {
      semantics = <String>[
        l10n.bookingDetailClientSemantics(displayName),
        ?qualifier,
      ].join(', ');
    } else if (rating == null) {
      // Unreviewed: spoken as plain "no reviews yet", never «Рейтинг —». The
      // visible readout keeps its em-dash.
      semantics = <String>[
        l10n.bookingDetailClientSemantics(displayName),
        l10n.masterReviewsEmpty,
      ].join('. ');
    } else {
      semantics = l10n.bookingDetailClientRatedSemantics(
        displayName,
        rating.toStringAsFixed(1),
        l10n.salonReviewCountLabel(reviewCount),
      );
    }

    // dim-gated: test/features/booking/presentation/booking_detail_provider_view_test.dart
    return Opacity(
      opacity: isDead ? 0.7 : 1,
      child: MasterStripShell(
        key: const Key('booking-detail-client-strip'),
        semanticsLabel: semantics,
        name: displayName,
        avatarImageUrl: booking.clientAvatarUrl,
        avatarInitials: booking.clientInitials,
        avatarImageKey: const Key('booking-detail-client-avatar-photo'),
        middleLine: qualifier == null
            ? null
            : Text(
                qualifier,
                style: VelvetText.feedbackMutedSm,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
        trailing: isGuest
            ? null
            : MasterRatingReadout(avgRating: rating, reviewCount: reviewCount),
      ),
    );
  }
}
