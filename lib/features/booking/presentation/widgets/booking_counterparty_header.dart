// Phase 7.2 — the counterparty strip on «Деталі запису».
//
// A booking has two sides. The detail screen shows the viewer the OTHER one:
//   * a CLIENT viewer sees the master / salon  → the shipped `MasterStrip`
//     (via `MasterStripFromBooking`), unchanged since Phase 14.4.
//   * a PROVIDER viewer sees the CLIENT       → `_ClientStrip`, below.
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

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

import '../../application/booking_viewer_role.dart';
import '../../domain/booking.dart';
import '../../domain/booking_display_x.dart';
import '../../domain/booking_status.dart';
import '../booking_detail_screen.dart' show MasterStripFromBooking;

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
        : MasterStripFromBooking(booking: booking);
  }
}

/// The CLIENT as the provider sees them — a monogram avatar, the name, and a
/// «Гість» marker when the booking has no registered account behind it.
///
/// Deliberately mirrors `MasterStrip`'s geometry (a 52dp leading avatar, name
/// on the first line, a muted qualifier on the second) so the provider view
/// and the client view of the same screen have the same visual rhythm — only
/// the identity in the slot changes.
class _ClientStrip extends StatelessWidget {
  const _ClientStrip({required this.booking});

  final Booking booking;

  /// Matches `MasterStrip`'s avatar diameter so the two strips are swappable
  /// in the recap card without shifting the rows beside them.
  static const double _avatarDiameter = 52;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    // A cancelled/declined booking's counterparty is dimmed — the same
    // `Opacity(0.7)` treatment `MasterStripFromBooking` gives the master
    // strip, so the two branches read as one screen.
    final bool isDead =
        booking.status == BookingStatus.cancelled ||
        booking.status == BookingStatus.declined;

    final String? name = booking.clientName;
    final String displayName = name ?? l10n.bookingDetailGuestClient;

    return Opacity(
      opacity: isDead ? 0.7 : 1,
      child: Row(
        key: const Key('booking-detail-client-strip'),
        children: <Widget>[
          _ClientAvatar(
            initials: booking.clientInitials,
            diameter: _avatarDiameter,
          ),
          const SizedBox(width: VelvetSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: VelvetText.subheading(),
                ),
                // The guest marker is shown ONLY for an actual guest booking
                // (`client_id IS NULL`) — never merely because a name is
                // missing. Conflating the two would label a registered client
                // with an incomplete profile as a guest, which is a claim
                // about their account status that the app cannot support.
                if (booking.isGuestBooking) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    l10n.bookingDetailGuestBookingLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: VelvetText.feedback(BrandColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A raised monogram avatar. Falls back to a person glyph when the booking
/// carries no name to derive initials from.
class _ClientAvatar extends StatelessWidget {
  const _ClientAvatar({required this.initials, required this.diameter});

  final String? initials;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: diameter,
      width: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: BrandColors.accent.withValues(alpha: 0.18),
        border: Border.all(
          color: BrandColors.accent.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      alignment: Alignment.center,
      child: initials == null
          ? const Icon(
              Icons.person_rounded,
              size: 24,
              color: BrandColors.accentDeep,
            )
          : Text(
              initials!,
              style: VelvetText.subheading().copyWith(
                color: BrandColors.accentDeep,
              ),
            ),
    );
  }
}
