// Phase 13.7 — "BEAUTY PASSPORT" preview card (Step 3).
//
// Shows a compact stat pill pointing to the passport page.
// The title "BEAUTY PASSPORT" is intentionally an untranslated English brand
// constant per the locked product decision.
//
// The card currently always shows the empty/placeholder state because
// GET /clients/me/passport (backend 19.5) is not yet shipped.
// TODO(19.5): show bookingsConsidered count + favourite procedures/districts/budget.

import 'package:flutter/material.dart';

import '../../../../core/theme/brand_colors.dart';
import '../../../../core/theme/velvet_geometry.dart';
import '../../../../core/theme/velvet_text.dart';
import '../../../../l10n/app_localizations.dart';
import '../widgets/hub_widgets.dart';

/// Compact BEAUTY PASSPORT preview tile in the stat-pills row.
///
/// [onTap] navigates to `/passport` (Phase 13.8).
class PassportPreviewCard extends StatelessWidget {
  const PassportPreviewCard({super.key, required this.onTap});

  final VoidCallback onTap;

  // Pre-composed text styles.
  static final TextStyle _titleStyle = VelvetText.bodyStrong().copyWith(
    fontSize: 11,
    letterSpacing: 0.3,
    height: 1.15,
    fontWeight: FontWeight.w800,
  );

  static final TextStyle _subtitleStyle = VelvetText.body().copyWith(
    fontSize: 11,
    height: 1.25,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return HubFlatCard(
      onTap: onTap,
      radius: 18,
      padding: const EdgeInsets.symmetric(
        horizontal: VelvetSpacing.sm + 2,
        vertical: VelvetSpacing.md - 4,
      ),
      child: Row(
        children: <Widget>[
          Container(
            height: 32,
            width: 32,
            decoration: BoxDecoration(
              color: BrandColors.base,
              shape: BoxShape.circle,
              border: Border.all(
                color: BrandColors.faint.withValues(alpha: 0.4),
              ),
            ),
            child: const Icon(
              Icons.badge_outlined,
              size: 17,
              color: BrandColors.accentDeep,
            ),
          ),
          const SizedBox(width: VelvetSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // "BEAUTY PASSPORT" — intentionally untranslated (brand constant).
                Text(
                  // ignore: avoid_hardcoded_strings — locked brand literal
                  'BEAUTY PASSPORT',
                  maxLines: 2,
                  overflow: TextOverflow.visible,
                  softWrap: true,
                  style: _titleStyle,
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.homeHubPassportSubtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _subtitleStyle,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The companion stat tile: review count + member since year.
class ReviewsStatCard extends StatelessWidget {
  const ReviewsStatCard({
    super.key,
    required this.reviewsLeft,
    required this.memberSinceYear,
    required this.onTap,
  });

  final int reviewsLeft;
  final int memberSinceYear;
  final VoidCallback onTap;

  static final TextStyle _titleStyle = VelvetText.bodyStrong().copyWith(
    fontSize: 12.5,
  );
  static final TextStyle _subtitleStyle = VelvetText.body().copyWith(
    fontSize: 11,
    height: 1.25,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return HubFlatCard(
      onTap: onTap,
      radius: 18,
      padding: const EdgeInsets.symmetric(
        horizontal: VelvetSpacing.sm + 2,
        vertical: VelvetSpacing.md - 4,
      ),
      child: Row(
        children: <Widget>[
          Container(
            height: 32,
            width: 32,
            decoration: BoxDecoration(
              color: BrandColors.base,
              shape: BoxShape.circle,
              border: Border.all(
                color: BrandColors.faint.withValues(alpha: 0.4),
              ),
            ),
            child: const Icon(
              Icons.star_rounded,
              size: 17,
              color: BrandColors.accentDeep,
            ),
          ),
          const SizedBox(width: VelvetSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  l10n.homeHubReviewsCount(reviewsLeft),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _titleStyle,
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.homeHubMemberSince(memberSinceYear),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _subtitleStyle,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
