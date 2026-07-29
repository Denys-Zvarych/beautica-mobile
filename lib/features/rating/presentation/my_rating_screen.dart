// Phase 13.7 (revised) / track 7.x Wave B — My Rating screen.
//
// Replaces the old MyReviewsScreen at /reviews/me. Route: /rating.
//
// Shows the client's aggregate two-sided rating (★ n.n) assigned by masters
// and salons after completed bookings. Wired to `GET /users/me/rating`
// (track 7.x Wave B, backend `POST /client-reviews` + `GET /users/me/rating`)
// via [myRatingProvider] — the Phase 13.7 placeholder that always rendered
// the empty state pending the endpoint is now replaced end-to-end; this is an
// EXISTING surface, not a new screen.
//
// PRODUCT RULE (locked):
//   • The client sees only their own AGGREGATE rating number (e.g. ★4.7) and
//     the review count.
//   • Individual comments from masters/salons are NEVER shown — the endpoint
//     returns none, by design.
//   • The rated/empty distinction is based solely on `ClientRating.avgRating`
//     being non-null vs null — no authored-reviews list, no CTA to write
//     reviews.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failures.dart';
import '../../../core/icons/app_icon.dart';
import '../../../core/icons/beautica_asset_icons.dart';
import '../../../core/theme/brand_colors.dart';
import '../../../core/theme/velvet_geometry.dart';
import '../../../core/theme/velvet_text.dart';
import '../../../core/widgets/neumorphic.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/rating_star.dart';
import '../../../shared/widgets/velvet_top_bar.dart';
import '../../home/presentation/widgets/hub_widgets.dart';
import '../application/my_rating_notifier.dart';
import '../domain/client_rating.dart';

// ---------------------------------------------------------------------------
// MyRatingScreen
// ---------------------------------------------------------------------------

/// CLIENT's aggregate rating screen — shows ★ n.n + review count, or the
/// empty/error/loading state.
class MyRatingScreen extends ConsumerWidget {
  const MyRatingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final AsyncValue<ClientRating> async = ref.watch(myRatingProvider);
    return Scaffold(
      backgroundColor: BrandColors.base,
      // House header: the shared 48 dp VelvetTopBar (centred title at
      // VelvetText.subheading(), NeumorphicIconButton back arrow) as the FIRST
      // child of SafeArea → Column. Its outer padding (lg/md/lg/xs) is baked
      // in — never wrap or double-pad it.
      body: SafeArea(
        child: Column(
          children: <Widget>[
            VelvetTopBar(
              title: l10n.myRatingTitle,
              backKey: const Key('my_rating_back_button'),
              backSemanticLabel: l10n.registerBackStep,
              onBack: () => context.pop(),
            ),
            // PERF: RepaintBoundary isolates the body layer from the static
            // top bar — mirrors ProfileScaffold (see its comment at the same
            // slot). VelvetTopBar's NeumorphicIconButton paints two
            // blurRadius-12 BoxShadows; without this boundary the loading
            // CircularProgressIndicator (which has no RepaintBoundary of its
            // own, and Scaffold inserts none around its slots) would
            // re-rasterize those blurred shadows on every animation frame.
            Expanded(
              child: RepaintBoundary(
                child: Padding(
                  // Top = md, matching ProfileScaffold / SectionScaffold bodies
                  // that sit directly beneath the same top bar (the bar already
                  // contributes its own xs bottom padding).
                  padding: const EdgeInsets.fromLTRB(
                    VelvetSpacing.lg,
                    VelvetSpacing.md,
                    VelvetSpacing.lg,
                    VelvetSpacing.lg,
                  ),
                  child: HubFlatCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: VelvetSpacing.md,
                      vertical: VelvetSpacing.xl,
                    ),
                    child: async.when(
                      loading: () => const Center(
                        key: Key('my_rating_loading'),
                        child: CircularProgressIndicator(
                          color: BrandColors.accent,
                        ),
                      ),
                      error: (Object e, StackTrace _) => _RatingError(
                        error: e,
                        onRetry: () => ref.invalidate(myRatingProvider),
                      ),
                      data: (ClientRating rating) => rating.avgRating != null
                          ? _RatingDisplay(
                              key: const Key('my_rating_display'),
                              rating: rating.avgRating!,
                              reviewCount: rating.reviewCount,
                              l10n: l10n,
                            )
                          : HubEmptyState(
                              key: const Key('my_rating_empty_state'),
                              icon: Icons.star_outline_rounded,
                              iconWidget: const AppIcon(
                                BeauticaAssetIcons.star,
                                size: 24,
                                color: BrandColors.faint,
                              ),
                              message: l10n.myRatingEmpty,
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _RatingDisplay — rated state
// ---------------------------------------------------------------------------

class _RatingDisplay extends StatelessWidget {
  const _RatingDisplay({
    super.key,
    required this.rating,
    required this.reviewCount,
    required this.l10n,
  });

  final double rating;
  final int reviewCount;
  final AppLocalizations l10n;

  // Big number style: Comfortaa-like weight via Manrope bold at large size.
  static final TextStyle _bigNumberStyle = VelvetText.ratingBigNumber;

  static final TextStyle _explanationStyle = VelvetText.ratingExplanation;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Big rating number
        Text(rating.toStringAsFixed(1), style: _bigNumberStyle),
        const SizedBox(height: VelvetSpacing.sm),

        // Single normalized-fill star (1.0 = empty, 5.0 = full). The numeric
        // value is already shown above, so the star carries no label here.
        RatingStar(rating: rating, size: 28, showLabel: false),
        const SizedBox(height: VelvetSpacing.xs),

        // The review count — the ONLY other number this screen ever shows;
        // never a comment (the endpoint returns none, by design).
        Text(
          l10n.myRatingReviewCount(reviewCount),
          key: const Key('my_rating_review_count'),
          style: VelvetText.feedbackMutedSm,
        ),
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
// _RatingError — failed fetch
// ---------------------------------------------------------------------------

class _RatingError extends StatelessWidget {
  const _RatingError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String message = error is Failure
        ? (error as Failure).userMessage(context)
        : l10n.errUnknown;
    return Column(
      key: const Key('my_rating_error_state'),
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Icon(Icons.cloud_off_rounded, size: 40, color: BrandColors.muted),
        const SizedBox(height: VelvetSpacing.md),
        Text(message, textAlign: TextAlign.center, style: VelvetText.body()),
        const SizedBox(height: VelvetSpacing.lg),
        SizedBox(
          width: 220,
          child: NeumorphicButton(
            key: const Key('my_rating_error_retry'),
            label: l10n.retryLabel,
            icon: Icons.refresh_rounded,
            onPressed: onRetry,
          ),
        ),
      ],
    );
  }
}
