// Phase 4.5 — Shared rating-summary card (review-section header).
//
// Extracted verbatim from the salon "Відгуки" tab
// (`features/salon/presentation/widgets/salon_reviews_section.dart`, Phase 13.6)
// so the salon public profile AND the independent-master received-reviews
// screen (Phase 4.6) render the aggregate rating header from ONE code path.
//
// Parameterised by primitives (avgRating / reviewCount / distribution) plus an
// already-formatted [countLabel] string, so the widget stays decoupled from any
// feature domain model AND from a feature-specific count l10n key (salon uses
// `salonReviewCountLabel`, master uses `masterReviewCountLabel`).
//
// Distribution-ready but graceful: when [reviewCount] is 0 the counts naturally
// render as empty bars (fraction 0) and the average shows «—» — safe if the
// summary endpoint is briefly unavailable.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';

import 'review_card.dart' show ReviewStarRow;

/// The raised rating-summary header: a big average + ★ row + count on the left,
/// a quiet five-row star distribution on the right.
///
/// [distribution] is highest-first (index 0 = 5★ … index 4 = 1★), length 5.
/// [averageKey] keys the big average number for widget tests (salon uses
/// `salon-review-summary-average`, master uses `master-review-summary-average`).
class RatingSummaryCard extends StatelessWidget {
  const RatingSummaryCard({
    super.key,
    required this.avgRating,
    required this.reviewCount,
    required this.distribution,
    required this.countLabel,
    this.averageKey,
  });

  /// Null when [reviewCount] is 0 — renders «—».
  final double? avgRating;
  final int reviewCount;

  /// Star-bucket counts, highest first (5★ → 1★), length 5.
  final List<int> distribution;

  /// Already-localised review-count line (e.g. "128 відгуків").
  final String countLabel;

  /// Optional key on the big average number.
  final Key? averageKey;

  @override
  Widget build(BuildContext context) {
    int sum = 0;
    for (final int c in distribution) {
      sum += c;
    }
    final int denom = sum == 0 ? 1 : sum;
    final double? avg = avgRating;

    return NeumorphicCard(
      padding: const EdgeInsets.all(VelvetSpacing.lg),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Text(
                  avg == null ? '—' : avg.toStringAsFixed(1),
                  key: averageKey,
                  style: VelvetText.salonReviewAverage,
                ),
                const SizedBox(height: VelvetSpacing.xs + 2),
                const ReviewStarRow(rating: 5, size: 17, gap: 3),
                const SizedBox(height: VelvetSpacing.xs + 2),
                Text(countLabel, style: VelvetText.feedbackMutedSm),
              ],
            ),
            const SizedBox(width: VelvetSpacing.lg),
            const VerticalDivider(
              width: 1,
              thickness: 1,
              color: BrandColors.faint,
            ),
            const SizedBox(width: VelvetSpacing.lg),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  for (int star = 5; star >= 1; star--) ...<Widget>[
                    _DistributionRow(
                      star: star,
                      count: distribution[5 - star],
                      fraction: distribution[5 - star] / denom,
                    ),
                    if (star > 1) const SizedBox(height: VelvetSpacing.sm),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One row of the distribution: the star number, a thin recessed track with a
/// camel-filled proportion bar, and the bucket count.
class _DistributionRow extends StatelessWidget {
  const _DistributionRow({
    required this.star,
    required this.count,
    required this.fraction,
  });

  final int star;
  final int count;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Text('$star', style: VelvetText.bodyStrong12),
        const SizedBox(width: 3),
        const Icon(Icons.star_rounded, size: 12, color: BrandColors.accent),
        const SizedBox(width: VelvetSpacing.sm),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Container(
              height: 6,
              color: BrandColors.faint.withValues(alpha: 0.45),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: fraction.clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: <Color>[
                        BrandColors.accent,
                        BrandColors.accentLatte,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: VelvetSpacing.sm),
        SizedBox(
          width: 26,
          child: Text(
            '$count',
            textAlign: TextAlign.right,
            style: VelvetText.feedbackMutedXs,
          ),
        ),
      ],
    );
  }
}
