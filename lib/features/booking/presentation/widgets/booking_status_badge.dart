// Phase 14.3 — the booking status pill, shared by `BookingCard` (the list)
// and «Деталі запису» (the status medallion + headline).
//
// Ported from `docs/signup-designs/MyBookings/lib/widgets/booking_status_badge.dart`.
//
// ## ⚠ MEASURED CONTRAST — colour never touches text
//
// The palette has exactly two chromatic colours (green, red) and three
// lightness steps of a warm-brown third — nowhere near five AA-passing text
// colours. So the status colour lives EXCLUSIVELY in *graphical objects* —
// the badge's actor cap, its border, the card's left rail, the detail page's
// hero medallion — where WCAG's bar is 3:1 (SC 1.4.11, non-text contrast),
// not 4.5:1. The badge LABEL is a single colour for every status
// ([BookingStatusVisual.labelColor] = `textSecondary`, 5.03:1 — comfortably
// AA). This also fixes a would-be bug: colouring the label itself with the
// status accent would put `error`'s label at 4.18:1 and `success`'s at
// 3.60:1 — both below the 4.5:1 AA floor for normal text.
//
// ## Colour never carries meaning alone
//
// Both CANCELLED and DECLINED now share ONE neutral label — «Скасовано»
// (product decision 2026-07-15 dropped the «Ви скасували» / «Салон скасував» /
// «Майстер скасував» who-cancelled copy). The residual client-vs-provider
// distinction, for anyone who still cares to read it, is carried by the two
// non-text channels, neither of which was ever the primary signal:
//   1. Colour — warm mocha when the CLIENT acted; error red when the
//      PROVIDER did.
//   2. Glyph — a person mark for the client; the provider's own mark for
//      them (storefront for a salon, scissors for an independent master).
// A third — structure, the recessed-well (received) vs hairline (sent) note
// container — lives on «Деталі запису»; see `booking_notes.dart`.
//
// All of this survives greyscale and colour-blindness.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

import '../../domain/booking.dart';
import '../../domain/booking_display_x.dart';
import '../../domain/booking_status.dart';

/// The visual contract for one booking status — the colour, the glyph, the
/// label. Resolve via [BookingStatusVisual.of].
class BookingStatusVisual {
  const BookingStatusVisual({
    required this.label,
    required this.icon,
    required this.accent,
    required this.wash,
  });

  final String label;
  final IconData icon;

  /// The status colour — tints the badge's actor cap, the badge border, the
  /// card's left rail and the detail page's hero medallion. Never applied to
  /// text; see the file header.
  final Color accent;

  /// The badge's soft background wash — the volume knob that stops a list of
  /// bookings from reading as a traffic light.
  final Color wash;

  /// The badge label's colour — uniform across all five statuses. See file
  /// header.
  static const Color labelColor = BrandColors.textSecondary;

  /// The wash alpha for the three statuses that are simply what normally
  /// happens — confirmed, completed, self-cancelled. Low, so the badge is a
  /// quiet marker.
  static const double _ordinary = 0.10;

  /// The wash alpha for the two that are NOT normal and deserve to be found
  /// while scanning — a no-show, and a booking the provider took away.
  static const double _exceptional = 0.14;

  /// Resolves the visual for [booking]. [BookingDisplayX.atSalon] no longer
  /// affects the CANCELLED/DECLINED label (both read «Скасовано») — it now
  /// only picks the provider glyph (storefront vs scissors) for a decline.
  factory BookingStatusVisual.of(Booking booking, AppLocalizations l10n) {
    switch (booking.status) {
      // Common case — every upcoming booking is one — so the wash stays
      // ordinary. A column of small green caps reads as "all good"; a column
      // of saturated pills would flatten the exceptional cards.
      case BookingStatus.pending:
      case BookingStatus.confirmed:
        return BookingStatusVisual(
          label: l10n.bookingStatusConfirmed,
          icon: Icons.check_rounded,
          accent: BrandColors.success,
          wash: BrandColors.success.withValues(alpha: _ordinary),
        );

      // The single most ordinary thing in this app: a visit happened. The
      // LIGHTEST cap in the set — completed and no-show share «Минулі» and
      // are the one pair the client actually has to tell apart at a glance.
      case BookingStatus.completed:
        return BookingStatusVisual(
          label: l10n.bookingStatusCompleted,
          icon: Icons.done_all_rounded,
          accent: BrandColors.accentLatte,
          wash: BrandColors.accentLatte.withValues(alpha: _ordinary),
        );

      // The no-show. NOT red (red here means "something was taken from you",
      // the opposite direction — it would read as a scolding). NOT faint
      // grey either (a no-show is not a nothing; burying it would be the app
      // quietly keeping a record the client never noticed). `text` (espresso)
      // is the most weighted, least loud colour in the palette — gravity,
      // not alarm. The copy stays agent-less; see `Booking`'s subline.
      case BookingStatus.notCompleted:
        return BookingStatusVisual(
          label: l10n.bookingStatusNotCompleted,
          icon: Icons.event_busy_rounded,
          accent: BrandColors.text,
          wash: BrandColors.text.withValues(alpha: _exceptional),
        );

      // The CLIENT backed out. A person glyph, the brand's own warm mocha, no
      // alarm — a self-cancellation is a normal, blameless act. The LABEL is
      // the neutral «Скасовано» (product decision 2026-07-15 collapsed the
      // who-cancelled copy); the person glyph + warm mocha still set it apart
      // from a provider cancellation at a glance.
      case BookingStatus.cancelled:
        return BookingStatusVisual(
          label: l10n.bookingStatusCancelled,
          icon: Icons.person_rounded,
          accent: BrandColors.accentDeep,
          wash: BrandColors.accentDeep.withValues(alpha: _ordinary),
        );

      // The PROVIDER backed out. Same neutral «Скасовано» label as a client
      // cancellation (the who-cancelled copy distinction was dropped); red is
      // reserved for exactly this — something was taken from you — so scanning
      // «Скасовані» the eye still finds the red caps first, the appointments
      // the client LOST and may want back.
      case BookingStatus.declined:
        return BookingStatusVisual(
          label: l10n.bookingStatusCancelled,
          icon: booking.atSalon
              ? Icons.storefront_rounded
              : Icons.content_cut_rounded,
          accent: BrandColors.error,
          wash: BrandColors.error.withValues(alpha: _exceptional),
        );
    }
  }
}

/// The status pill — a small solid **actor cap** carrying the glyph, butted
/// against the label on a soft wash, so the glyph reads as a stamp applied
/// BY someone, not as generic decoration.
///
/// The cap is the only saturated element on an otherwise quiet card, and on
/// a declined booking it is the only red pixel in the whole list.
class BookingStatusBadge extends StatelessWidget {
  const BookingStatusBadge({super.key, required this.booking});

  final Booking booking;

  static const double _height = 24;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final BookingStatusVisual v = BookingStatusVisual.of(booking, l10n);

    return Semantics(
      label: l10n.bookingStatusSemantics(v.label),
      child: SizedBox(
        height: _height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: v.wash,
            borderRadius: BorderRadius.circular(_height / 2),
            border: Border.all(
              color: v.accent.withValues(alpha: 0.45),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                height: _height - 6,
                width: _height - 6,
                margin: const EdgeInsets.only(left: 3),
                decoration: BoxDecoration(
                  color: v.accent,
                  shape: BoxShape.circle,
                ),
                child: Icon(v.icon, size: 11, color: BrandColors.white),
              ),
              const SizedBox(width: VelvetSpacing.xs - 2),
              // Flexible + ellipsis: on a 360 dp card the longest label
              // («Візит не відбувся») shares its row with the trailing
              // chevron and must yield rather than overflow.
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(right: VelvetSpacing.xs),
                  child: Text(
                    v.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: VelvetText.feedback(BookingStatusVisual.labelColor),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
