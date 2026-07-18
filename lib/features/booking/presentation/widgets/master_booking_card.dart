// Phase 7.6 — one booking in the MASTER's «Мої записи» list.
//
// Transcribed from `docs/signup-designs/SalonManagementDesign/lib/widgets/
// booking_widgets.dart` (`BookingCard`), which is already drawn from the
// provider's perspective: the client is the headline, because the master
// already knows who the master is.
//
// ## Why this is NOT an extension of the shipped `booking_card.dart`
//
// Phase 7.6's brief asks that the client-side `BookingCard` be extended if it
// generalises. It does not, and the reason is structural rather than
// cosmetic — the two cards disagree about what a booking IS.
//
//   * The CLIENT card's dominant element is a date STUB in its own exclusive
//     left column, pinned to a fixed y-offset, beside a master photo. Its
//     whole grid exists to answer "when am I going somewhere, and to whom".
//     Its identity slot renders the master (avatar, professional title, salon
//     name) — three fields this card must not show.
//   * The MASTER card's dominant element is the CLIENT's name on the first
//     line, with the date demoted to an inline caption chip beside the
//     service. It answers "who is coming to me, and for what".
//
// Generalising would mean a widget with two mutually exclusive grids, two
// identity blocks and a mode flag selecting between them — which is two
// widgets wearing one name, with every future edit to either forced to reason
// about the other. The genuinely shared pieces ARE shared: `BookingStatusBadge`
// (Phase 14.7, consumed verbatim — Phase 7.4's replacement badge is retired),
// `BookingDisplayX.showsPrice`, and the date formatters.
//
// The one design element deliberately dropped: the preview's SECOND identity
// row (`b.masterName` under the client) is salon-scope only — it names which
// teammate serves the booking. A single master's own list never needs it, the
// same reason `showMasterFilter: false`.
//
// SEC: renders a client name (PII). The hosting screen holds the
// `ScreenProtectionManager`; this widget logs nothing.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';

import '../../domain/booking.dart';
import '../../domain/booking_display_x.dart';
import 'booking_status_badge.dart';

/// A provider-perspective booking row. The whole card is one tap target that
/// opens «Деталі запису» — it carries no per-action buttons (those live on the
/// detail screen, Phase 7.3).
class MasterBookingCard extends StatefulWidget {
  const MasterBookingCard({
    super.key,
    required this.booking,
    required this.onTap,
  });

  final Booking booking;
  final VoidCallback onTap;

  @override
  State<MasterBookingCard> createState() => _MasterBookingCardState();
}

class _MasterBookingCardState extends State<MasterBookingCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Booking b = widget.booking;
    final String clientName = b.clientName ?? l10n.bookingDetailGuestClient;

    return Semantics(
      button: true,
      label: l10n.masterBookingCardSemantics(clientName, b.serviceName),
      child: GestureDetector(
        key: Key('master-booking-card-${b.id}'),
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _pressed ? 0.99 : 1,
          duration: const Duration(milliseconds: 110),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: BrandColors.base,
              borderRadius: BorderRadius.circular(VelvetRadii.card),
              border: Border.all(
                color: BrandColors.accent.withValues(alpha: 0.18),
                width: 1,
              ),
              // `borderedCard`, NOT `extrudedCard` — the extruded pair's
              // offset near-white light shadow pokes past the rounded corner
              // under Impeller and paints a white wedge there (resolved
              // 34db74f). The hairline border above defines the card instead.
              boxShadow: _pressed ? null : VelvetShadows.borderedCard,
            ),
            padding: const EdgeInsets.all(VelvetSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Row 1 — avatar + client name. No badge on this row, so the
                // name gets the full remaining width (design's note).
                Row(
                  children: <Widget>[
                    _ClientAvatar(initials: b.clientInitials),
                    const SizedBox(width: VelvetSpacing.sm + 2),
                    Expanded(
                      child: Text(
                        clientName,
                        style: VelvetText.masterCardClientName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: VelvetSpacing.sm + 2),
                Container(height: 1, color: BrandColors.faint),
                const SizedBox(height: VelvetSpacing.sm + 2),
                // Row 2 — service name + date caption.
                Row(
                  children: <Widget>[
                    const Icon(
                      Icons.spa_outlined,
                      size: 16,
                      color: BrandColors.accent,
                    ),
                    const SizedBox(width: VelvetSpacing.sm),
                    Expanded(
                      child: Text(
                        b.serviceName,
                        style: VelvetText.masterCardService,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: VelvetSpacing.sm),
                    _BookingDateChip(startAt: b.startAt),
                  ],
                ),
                const SizedBox(height: VelvetSpacing.xs + 2),
                // Row 3 — price (left) + status badge (right).
                Row(
                  children: <Widget>[
                    const SizedBox(width: 16 + VelvetSpacing.sm),
                    // See `BookingDisplayX.showsPrice`: a cancelled, declined
                    // or missed appointment owes nothing, so printing a sum on
                    // it would assert a debt that does not exist.
                    if (b.showsPrice)
                      _PriceTag(
                        price:
                            '${b.price.toStringAsFixed(0)} '
                            '${l10n.pricingCurrencySuffix}',
                      ),
                    const Spacer(),
                    BookingStatusBadge(booking: b),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A price pill — «450 ₴».
///
/// The design draws this as a `NeumorphicInset`. Rendered here as a hairline
/// bordered pill instead: the card already sits on `borderedCard`, and nesting
/// a recessed well inside a raised card at this size reads as noise rather
/// than depth. The accent hairline is the same edge language the card and the
/// calendar button use.
class _PriceTag extends StatelessWidget {
  const _PriceTag({required this.price});

  final String price;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: BrandColors.base,
        borderRadius: BorderRadius.circular(VelvetRadii.pill),
        border: Border.all(
          color: BrandColors.accent.withValues(alpha: 0.22),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: VelvetSpacing.sm,
          vertical: 3,
        ),
        child: Text(
          price,
          style: VelvetText.pill(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

/// A muted date+time caption with a clock glyph — «12 лип, 14:30».
class _BookingDateChip extends StatelessWidget {
  const _BookingDateChip({required this.startAt});

  final DateTime startAt;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Icon(Icons.schedule_outlined, size: 12, color: BrandColors.muted),
        const SizedBox(width: 3),
        Text(formatShortDateTime(startAt), style: VelvetText.masterCardDate),
      ],
    );
  }
}

/// A raised monogram avatar for the client, falling back to a person glyph
/// when the booking carries no name.
class _ClientAvatar extends StatelessWidget {
  const _ClientAvatar({required this.initials});

  final String? initials;

  static const double _diameter = 46;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _diameter,
      width: _diameter,
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
              size: 22,
              color: BrandColors.accentDeep,
            )
          : Text(initials!, style: VelvetText.masterCardInitials),
    );
  }
}
