/// Phase 293 — the salon-name attribution row, promoted out of
/// `booking_card.dart` (formerly its private `_identity()` helper, lines
/// 374-400) so `MasterBookingCard` can reuse it verbatim in a later phase
/// instead of hand-copying the glyph + text pairing.
///
/// Pure extraction: rendering is byte-identical to the row `BookingCard` used
/// to inline — same storefront glyph at size 12, same 3dp gap, same
/// `VelvetText.bookingCardCaption` style, same dimmed/lively colour swap. The
/// caller decides whether to render this row at all (a booking with no salon
/// renders nothing) — this widget never self-hides on a null name, because
/// `salonName` is non-null by contract (see phase doc D1).
library;

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';

/// One line: a small storefront glyph plus the salon's name, truncated to a
/// single line. Used beneath a master's identity block on a booking card to
/// attribute the appointment to the salon it happens at.
class BookingSalonRow extends StatelessWidget {
  const BookingSalonRow({
    super.key,
    required this.salonName,
    this.dimmed = false,
  });

  /// The salon's display name. Never null — if a booking has no salon, the
  /// caller simply does not build this widget at all.
  final String salonName;

  /// Whether the enclosing card is in its "dead" (cancelled/declined)
  /// stratum — swaps the glyph and text to the muted/faint palette instead
  /// of the lively accent/secondary pair.
  final bool dimmed;

  /// The glyph's "lively" tint. Never varies, so it need not reallocate on
  /// each build — mirrors the `_deadShadows` static-hoist in
  /// `booking_card.dart`.
  static final Color _livelyIconColor = BrandColors.accent.withValues(
    alpha: 0.9,
  );

  /// Caption style for the "lively" (non-dimmed) stratum. Hoisted alongside
  /// [_dimmedCaption] so neither `.copyWith` call reallocates per build.
  static final TextStyle _livelyCaption = VelvetText.bookingCardCaption
      .copyWith(color: BrandColors.textSecondary);

  /// Caption style for the "dead" (cancelled/declined) stratum.
  static final TextStyle _dimmedCaption = VelvetText.bookingCardCaption
      .copyWith(color: BrandColors.muted);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(
          Icons.storefront_rounded,
          size: 12,
          color: dimmed ? BrandColors.faint : _livelyIconColor,
        ),
        const SizedBox(width: 3),
        Expanded(
          child: Text(
            salonName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: dimmed ? _dimmedCaption : _livelyCaption,
          ),
        ),
      ],
    );
  }
}
