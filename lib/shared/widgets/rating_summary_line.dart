import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

/// The one-line «★ 4.8 · 12 відгуків» rating summary.
///
/// REUSE-FIRST — PROMOTED from the private rating row inside
/// `_SalonHeroCard` (`features/salon/presentation/public_salon_profile_
/// screen.dart:738-768`, Phase 13.6). Its ONLY consumer remains the salon
/// hero card (D3′) — Phase 351's master-profile stat cards use `StatTile`,
/// not this widget; the promotion out of `_SalonHeroCard` into
/// `shared/widgets/` still stands on its own (a private widget promoted to a
/// shared file needs no in-tree second consumer to justify staying shared),
/// and the HEAD-baseline goldens prove the salon hero renders unchanged.
///
/// - `rating == null` → «—» (never a rating yet).
/// - `reviewCount == 0` → «0 відгуків» (a true, renderable fact — distinct
///   from "no rating"; a master/salon can have zero reviews but the label
///   still renders, matching the salon's original behaviour).
/// - Count wording comes from [AppLocalizations.salonReviewCountLabel] — its
///   plural-correct «{n} відгук/відгуки/відгуків» text is neutral (says
///   nothing salon-specific), so both callers reuse the SAME key rather than
///   forking a `masterReviewCountLabel`-shaped duplicate (D4).
class RatingSummaryLine extends StatelessWidget {
  const RatingSummaryLine({
    super.key,
    required this.rating,
    required this.reviewCount,
    this.ratingKey,
    this.countKey,
  });

  /// The average rating, or `null` when there is no rating yet.
  final double? rating;

  /// Total review count. `0` is a valid, renderable value.
  final int reviewCount;

  /// Key on the rating value `Text` (e.g. `salon-profile-rating` /
  /// `public-master-profile-rating-value`) — existing finders survive the
  /// promotion by reusing their pre-promotion key values.
  final Key? ratingKey;

  /// Key on the «· N відгуків» `Text` (e.g. `salon-profile-review-count` /
  /// `public-master-profile-reviews-value`).
  final Key? countKey;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String ratingLabel = rating?.toStringAsFixed(1) ?? '—';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Icon(Icons.star_rounded, size: 16, color: BrandColors.accentDeep),
        const SizedBox(width: 4),
        Text(ratingLabel, key: ratingKey, style: _ratingInlineStyle),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            '·  ${l10n.salonReviewCountLabel(reviewCount)}',
            key: countKey,
            style: VelvetText.feedbackMuted13,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  static final TextStyle _ratingInlineStyle = VelvetText.bodyStrong14;
}
