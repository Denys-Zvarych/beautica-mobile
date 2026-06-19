// Phase 13.7 (revised) — My Rating screen.
//
// Replaces the old MyReviewsScreen at /reviews/me. Route: /rating.
//
// Shows the client's aggregate two-sided rating (★ n.n) assigned by masters
// and salons after completed bookings. The two-sided client-rating backend
// endpoint (GET /clients/me/rating) is not yet shipped; the screen always
// shows the empty state until then.
//
// PRODUCT RULE (locked):
//   • The client sees only their own AGGREGATE rating number (e.g. ★4.7).
//   • Individual comments from masters/salons are NEVER shown.
//   • The rated/empty distinction is based solely on [clientRating] being
//     non-null vs null — no authored-reviews list, no CTA to write reviews.
//
// TODO(backend): wire GET /clients/me/rating when endpoint ships and push
//   [clientRating] via a Riverpod @riverpod provider. For now the screen
//   always receives null via GoRouter.extra or defaults to null.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/brand_colors.dart';
import '../../../core/theme/velvet_geometry.dart';
import '../../../core/theme/velvet_text.dart';
import '../../../l10n/app_localizations.dart';
import '../../home/presentation/widgets/hub_widgets.dart';

// ---------------------------------------------------------------------------
// MyRatingScreen
// ---------------------------------------------------------------------------

/// CLIENT's aggregate rating screen — shows ★ n.n or empty state.
class MyRatingScreen extends StatelessWidget {
  const MyRatingScreen({super.key, this.clientRating});

  // Pre-composed AppBar title style — static final so it is computed once at
  // class-load time, never per-build (house pattern: styles on the owning class).
  static final TextStyle _titleStyle = VelvetText.heading().copyWith(
    fontSize: 18,
  );

  /// The client's aggregate rating; null = no rating yet.
  ///
  /// TODO(backend): replace with a @riverpod provider watching
  /// GET /clients/me/rating when the endpoint ships.
  final double? clientRating;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: BrandColors.base,
      appBar: AppBar(
        backgroundColor: BrandColors.base,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          key: const Key('my_rating_back_button'),
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: BrandColors.accentDeep,
            size: 20,
          ),
          onPressed: () => context.pop(),
        ),
        title: Text(l10n.myRatingTitle, style: _titleStyle),
        centerTitle: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            VelvetSpacing.lg,
            VelvetSpacing.lg,
            VelvetSpacing.lg,
            VelvetSpacing.lg,
          ),
          child: HubFlatCard(
            padding: const EdgeInsets.symmetric(
              horizontal: VelvetSpacing.md,
              vertical: VelvetSpacing.xl,
            ),
            child: clientRating != null
                ? _RatingDisplay(
                    key: const Key('my_rating_display'),
                    rating: clientRating!,
                    l10n: l10n,
                  )
                : HubEmptyState(
                    key: const Key('my_rating_empty_state'),
                    icon: Icons.star_outline_rounded,
                    message: l10n.myRatingEmpty,
                  ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _RatingDisplay — rated state
// ---------------------------------------------------------------------------

class _RatingDisplay extends StatelessWidget {
  const _RatingDisplay({super.key, required this.rating, required this.l10n});

  final double rating;
  final AppLocalizations l10n;

  // Big number style: Comfortaa-like weight via Manrope bold at large size.
  static final TextStyle _bigNumberStyle = VelvetText.displayName().copyWith(
    fontSize: 56,
    fontWeight: FontWeight.w700,
    color: BrandColors.accentDeep,
    height: 1.0,
  );

  static final TextStyle _explanationStyle = VelvetText.body().copyWith(
    fontSize: 13,
    color: BrandColors.textSecondary,
    height: 1.4,
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Big rating number
        Text(rating.toStringAsFixed(1), style: _bigNumberStyle),
        const SizedBox(height: VelvetSpacing.sm),

        // 5-star row
        _StarRow(rating: rating),
        const SizedBox(height: VelvetSpacing.md),

        // Explanation
        Text(
          l10n.myRatingExplanation,
          textAlign: TextAlign.center,
          style: _explanationStyle,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _StarRow — filled / half / outlined stars in camel
// ---------------------------------------------------------------------------

class _StarRow extends StatelessWidget {
  const _StarRow({required this.rating});

  final double rating;

  static const int _totalStars = 5;
  static const double _starSize = 28;
  static const Color _starColor = BrandColors.accentDeep;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List<Widget>.generate(_totalStars, (int index) {
        final double starValue = index + 1;
        final IconData iconData;

        if (rating >= starValue) {
          // Fully filled
          iconData = Icons.star_rounded;
        } else if (rating >= starValue - 0.5) {
          // Half filled (frac >= 0.5)
          iconData = Icons.star_half_rounded;
        } else {
          // Outlined
          iconData = Icons.star_outline_rounded;
        }

        // VelvetSpacing.xs - 2 == 4 - 2 == 2 — a compile-time constant, so
        // EdgeInsets.symmetric(horizontal: 2) is const; avoids a per-star
        // EdgeInsets allocation on every build.
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Icon(iconData, size: _starSize, color: _starColor),
        );
      }),
    );
  }
}
