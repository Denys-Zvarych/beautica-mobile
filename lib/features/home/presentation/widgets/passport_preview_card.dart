// Phase 13.7 — "BEAUTY PASSPORT" preview card + "МІЙ РЕЙТИНГ" stat card.
//
// PassportPreviewCard shows a compact stat pill pointing to the passport page.
// The title "BEAUTY PASSPORT" is intentionally an untranslated English brand
// constant per the locked product decision.
//
// The card currently always shows the empty/placeholder state because
// GET /clients/me/passport (backend 19.5) is not yet shipped.
// TODO(19.5): show bookingsConsidered count + favourite procedures/districts/budget.
//
// MyRatingStatCard replaces the old ReviewsStatCard (Phase 13.7 revision):
// shows the client's aggregate two-sided rating (★ n.n) or an em-dash when no
// rating yet. Client comments are never shown.
// TODO(backend): GET /clients/me/rating (two-sided client rating, excludes comments).

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

  // Hoisted icon-circle decoration — withValues inside build() would allocate
  // a new Color on every rebuild; static final computes it once at class load.
  static final BoxDecoration _iconCircleDecoration = BoxDecoration(
    color: BrandColors.base,
    shape: BoxShape.circle,
    border: Border.all(color: BrandColors.faint.withValues(alpha: 0.4)),
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
            decoration: _iconCircleDecoration,
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

/// Stat tile that shows the client's aggregate two-sided rating (★ n.n)
/// or an em-dash when no rating has been assigned yet.
///
/// [clientRating] is null when the backend rating endpoint hasn't yet returned
/// a value (backend GET /clients/me/rating, two-sided system — excludes comments).
/// [onTap] navigates to [RouteNames.myRating].
class MyRatingStatCard extends StatelessWidget {
  const MyRatingStatCard({
    super.key,
    required this.clientRating,
    required this.onTap,
  });

  final double? clientRating;
  final VoidCallback onTap;

  // Pre-composed text styles — no per-build allocation.
  static final TextStyle _labelStyle = VelvetText.bodyStrong().copyWith(
    fontSize: 11,
    letterSpacing: 0.3,
    height: 1.15,
    fontWeight: FontWeight.w800,
  );
  static final TextStyle _valueRatedStyle = VelvetText.body().copyWith(
    fontSize: 11,
    height: 1.25,
    color: BrandColors.accentDeep,
    fontWeight: FontWeight.w700,
  );
  static final TextStyle _valueEmptyStyle = VelvetText.body().copyWith(
    fontSize: 11,
    height: 1.25,
    color: BrandColors.textSecondary,
  );

  // Hoisted icon-circle decoration — withValues inside build() allocates a new
  // Color on every rebuild; static final computes it once at class load.
  static final BoxDecoration _iconCircleDecoration = BoxDecoration(
    color: BrandColors.base,
    shape: BoxShape.circle,
    border: Border.all(color: BrandColors.faint.withValues(alpha: 0.4)),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String valueText = clientRating != null
        ? '★ ${clientRating!.toStringAsFixed(1)}'
        : '—';
    final TextStyle valueStyle = clientRating != null
        ? _valueRatedStyle
        : _valueEmptyStyle;

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
            decoration: _iconCircleDecoration,
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
                  l10n.homeHubMyRating,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _labelStyle,
                ),
                const SizedBox(height: 2),
                Text(
                  valueText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: valueStyle,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
