// Phase 13.7 (revised) / track 7.x Wave B — My Rating screen.
//
// Replaces the old MyReviewsScreen at /reviews/me. Route: /rating.
//
// Shows the client's aggregate two-sided rating (★ n.n + per-star breakdown)
// assigned by masters and salons after completed bookings. Wired to `GET
// /users/me/rating` (track 7.x Wave B, backend `POST /client-reviews` + `GET
// /users/me/rating`) via [myRatingProvider] — the Phase 13.7 placeholder that
// always rendered the empty state pending the endpoint is now replaced
// end-to-end; this is an EXISTING surface, not a new screen.
//
// The rated state renders the SAME `RatingSummaryCard` the master's «Мої
// відгуки» screen uses (`features/review/presentation/widgets/
// rating_summary_card.dart`) — average + ★ row + count on the left, a
// per-star distribution on the right — reused unchanged now that `GET
// /users/me/rating` also zero-fills a `ratingDistribution` (mirroring the
// master/salon summary endpoints).
//
// PRODUCT RULE (locked):
//   • The client sees only their own AGGREGATE rating number (e.g. ★4.7), the
//     review count, and the per-star bucket counts.
//   • Individual comments from masters/salons are NEVER shown — the endpoint
//     returns none, by design. No `ReviewCard`/comment list is ever rendered
//     here.
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
import '../../../shared/widgets/velvet_top_bar.dart';
import '../../home/presentation/widgets/hub_widgets.dart';
import '../../review/presentation/widgets/rating_summary_card.dart';
import '../application/my_rating_notifier.dart';
import '../domain/client_rating.dart';

// PERF: shared by the loading / error / empty branches below — the rated
// branch renders `RatingSummaryCard` bare (it is itself a `NeumorphicCard`;
// see the `HubFlatCard` removal note at that call site) so this padding is
// only relevant to the three non-rated states, which still need a card frame
// of their own.
const EdgeInsets _hubCardPadding = EdgeInsets.symmetric(
  horizontal: VelvetSpacing.md,
  vertical: VelvetSpacing.xl,
);

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
      // House header: the shared 48 dp VelvetTopBar as the FIRST child of
      // SafeArea → Column (NeumorphicIconButton back arrow, outer padding
      // lg/md/lg/xs baked in — never wrap or double-pad it). The centred slot
      // renders the lowercase "beautica" wordmark (VelvetText.wordmark()) via
      // `titleWidget`, reusing the same wordmark visual as ClientTopBar's
      // branch-root chrome for brand consistency — NOT a visible
      // "МІЙ РЕЙТИНГ" title. This screen itself is a pushed top-level
      // GoRoute (reached via push, popped via context.pop(), back arrow
      // intact) — NOT a shell branch root like ClientTopBar's own screens.
      // The accessible identity (`l10n.myRatingTitle`) is preserved via the
      // Semantics(header: true, ...) wrapping the wordmark instead.
      body: SafeArea(
        child: Column(
          children: <Widget>[
            VelvetTopBar(
              // Visually replaced by the "beautica" wordmark below (brand
              // reuse of ClientTopBar's wordmark visual only, NOT routing
              // parity — see the titleWidget doc on VelvetTopBar). `title` is
              // kept as the screen's accessible identity: it is NOT
              // rendered, but VelvetTopBar still requires it, and this is
              // also the value the wrapping Semantics(header: true, ...)
              // below re-asserts for the a11y tree, so the ARB key
              // (`myRatingTitle`) keeps a live code reference even though no
              // visible Text uses it anymore.
              title: l10n.myRatingTitle,
              titleWidget: Semantics(
                header: true,
                label: l10n.myRatingTitle,
                // Without this, the child Text's own auto-generated "beautica"
                // label MERGES into this node (SemanticsNodes concatenate with
                // a newline), so TalkBack would read "Мій рейтинг\nbeautica"
                // instead of the clean single announcement below.
                excludeSemantics: true,
                child: Text(
                  // ignore: avoid_hardcoded_strings — brand wordmark, NOT
                  // translated (mirrors ClientTopBar's wordmark visual).
                  'beautica',
                  style: VelvetText.wordmark(),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
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
                  // No `HubFlatCard` wrapper for the rated branch:
                  // `RatingSummaryCard` is itself a `NeumorphicCard` with
                  // paired extruded shadows, so wrapping it here would stack
                  // a third shadow layer + a redundant fill on top of its own
                  // (mobile-perf LOW). The other two `RatingSummaryCard` call
                  // sites (`master_reviews_body.dart`,
                  // `salon_reviews_section.dart`) render it bare in a plain
                  // `Column` too — this now matches them, and matches the
                  // original ask for "exactly [like] the independent master
                  // rating table". Loading / error / empty still need a card
                  // frame of their own (none of those three widgets paints
                  // one), so they keep the `HubFlatCard` wrapper.
                  child: async.when(
                    loading: () => const HubFlatCard(
                      padding: _hubCardPadding,
                      child: Center(
                        key: Key('my_rating_loading'),
                        child: CircularProgressIndicator(
                          color: BrandColors.accent,
                        ),
                      ),
                    ),
                    error: (Object e, StackTrace _) => HubFlatCard(
                      padding: _hubCardPadding,
                      child: _RatingError(
                        error: e,
                        onRetry: () => ref.invalidate(myRatingProvider),
                      ),
                    ),
                    data: (ClientRating rating) => rating.avgRating != null
                        ? RatingSummaryCard(
                            key: const Key('my_rating_display'),
                            avgRating: rating.avgRating,
                            reviewCount: rating.reviewCount,
                            distribution: rating.distribution,
                            countLabel: l10n.myRatingReviewCount(
                              rating.reviewCount,
                            ),
                            averageKey: const Key('my_rating_average'),
                          )
                        : HubFlatCard(
                            padding: _hubCardPadding,
                            child: HubEmptyState(
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
