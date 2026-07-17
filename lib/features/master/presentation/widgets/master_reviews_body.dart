// Phase 4.6 / 4.x — Shared reviews body, parameterized by masterId.
//
// Extracted from `master_received_reviews_screen.dart` so the SAME summary +
// sortable-list UI can be reused by both:
//   • [MasterReceivedReviewsScreen] — the authenticated master's own reviews,
//     masterId resolved from `masterProfileProvider` (GET /masters/me);
//   • `PublicMasterReviewsScreen` — a CLIENT viewing another master's public
//     reviews, masterId supplied directly via the route param.
//
// Both `masterReviewsProvider(masterId, sort)` and
// `masterReviewSummaryProvider(masterId)` are `@riverpod` families keyed on an
// arbitrary masterId, independent of the authenticated session — so this
// widget itself needs no session/auth awareness at all.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/features/master/application/master_review_summary_notifier.dart';
import 'package:beautica_mobile/features/master/application/master_reviews_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master_review.dart';
import 'package:beautica_mobile/features/review/presentation/widgets/rating_summary_card.dart';
import 'package:beautica_mobile/features/review/presentation/widgets/review_card.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';

import 'master_review_sort_sheet.dart';

/// Sort-independent summary card over a sortable review list, for [masterId].
///
/// Composed of two sibling subtrees so a sort toggle (held in
/// [_SortableReviewList]) rebuilds ONLY the list — never the summary card.
class MasterReviewsBody extends StatelessWidget {
  const MasterReviewsBody({super.key, required this.masterId});

  /// The Master-row id (backend UUID, distinct from the session user id).
  final String masterId;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SummarySection(masterId: masterId),
        const SizedBox(height: VelvetSpacing.md),
        _SortableReviewList(masterId: masterId),
      ],
    );
  }
}

/// Shimmer placeholder matching [MasterReviewsBody]'s layout, for callers that
/// need to render a loading state BEFORE a masterId is known (e.g. the own-
/// profile screen while `masterProfileProvider` itself is still loading).
class MasterReviewsBodySkeleton extends StatelessWidget {
  const MasterReviewsBodySkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _RatingSummarySkeleton(),
        SizedBox(height: VelvetSpacing.md),
        _ReviewListSkeleton(),
      ],
    );
  }
}

/// Sort-independent rating-summary card. Watches only
/// [masterReviewSummaryProvider], so it is untouched when the sort changes
/// (PERF LOW: scope the sort rebuild away from the summary).
class _SummarySection extends ConsumerWidget {
  const _SummarySection({required this.masterId});

  final String masterId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final summaryAsync = ref.watch(masterReviewSummaryProvider(masterId));

    return summaryAsync.when(
      data: (MasterReviewSummary summary) => RatingSummaryCard(
        avgRating: summary.avgRating,
        reviewCount: summary.reviewCount,
        distribution: summary.distribution,
        countLabel: l10n.masterReviewCountLabel(summary.reviewCount),
        averageKey: const Key('master-review-summary-average'),
      ),
      loading: () => const _RatingSummarySkeleton(),
      error: (Object e, _) => ErrorState(
        failure: e is Failure ? e : UnknownFailure(cause: e),
        onRetry: () => ref.invalidate(masterReviewSummaryProvider(masterId)),
      ),
    );
  }
}

/// The sort control + sortable review list. Holds the active [MasterReviewSort]
/// locally (default NEWEST); changing the sort re-keys [masterReviewsProvider]
/// so the list re-fetches a server-sorted page. Because the sort state lives
/// here, a toggle rebuilds only this subtree — the sibling [_SummarySection] is
/// left untouched (PERF LOW).
class _SortableReviewList extends ConsumerStatefulWidget {
  const _SortableReviewList({required this.masterId});

  final String masterId;

  @override
  ConsumerState<_SortableReviewList> createState() =>
      _SortableReviewListState();
}

class _SortableReviewListState extends ConsumerState<_SortableReviewList> {
  MasterReviewSort _sort = MasterReviewSort.newest;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String masterId = widget.masterId;
    final reviewsAsync = ref.watch(masterReviewsProvider(masterId, _sort));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                masterReviewSortLabel(l10n, _sort),
                style: VelvetText.salonSortLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: VelvetSpacing.sm),
            MasterReviewSortIconButton(
              active: _sort,
              onSelected: (MasterReviewSort s) => setState(() => _sort = s),
            ),
          ],
        ),
        const SizedBox(height: VelvetSpacing.md),
        reviewsAsync.when(
          data: (List<MasterReviewItem> reviews) => reviews.isEmpty
              ? Padding(
                  key: const Key('master-reviews-empty'),
                  padding: const EdgeInsets.symmetric(
                    vertical: VelvetSpacing.lg,
                  ),
                  child: Text(
                    l10n.masterReviewsEmpty,
                    textAlign: TextAlign.center,
                    style: VelvetText.feedback(BrandColors.muted),
                  ),
                )
              // PERF LOW: lazy list — the review cards are built on demand
              // rather than eagerly in a Column/for-loop. shrinkWrap +
              // NeverScrollableScrollPhysics let it live inside the scaffold's
              // outer SingleChildScrollView. Keys (`master-review-<id>`) and
              // inter-card spacing are preserved 1:1.
              : ListView.builder(
                  key: const Key('master-reviews-list'),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  itemCount: reviews.length,
                  itemBuilder: (BuildContext context, int i) {
                    final MasterReviewItem r = reviews[i];
                    final Widget card = _masterReviewCard(r);
                    // Gap between cards, not after the last — matches the
                    // previous Column's inter-card SizedBox exactly.
                    if (i == reviews.length - 1) return card;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: VelvetSpacing.md),
                      child: card,
                    );
                  },
                ),
          loading: () => const _ReviewListSkeleton(),
          error: (Object e, _) => ErrorState(
            failure: e is Failure ? e : UnknownFailure(cause: e),
            onRetry: () =>
                ref.invalidate(masterReviewsProvider(masterId, _sort)),
          ),
        ),
      ],
    );
  }
}

/// Neumorphic shimmer placeholder for the rating-summary card (copied from the
/// salon reviews section).
class _RatingSummarySkeleton extends StatelessWidget {
  const _RatingSummarySkeleton();

  @override
  Widget build(BuildContext context) {
    return const SkeletonShimmerScope(
      child: SkeletonBlock(
        width: double.infinity,
        height: 132,
        radius: VelvetRadii.card,
      ),
    );
  }
}

/// Neumorphic shimmer placeholder for the review list (copied from the salon
/// reviews section).
class _ReviewListSkeleton extends StatelessWidget {
  const _ReviewListSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SkeletonShimmerScope(
      child: Column(
        children: <Widget>[
          SkeletonBlock(
            width: double.infinity,
            height: 110,
            radius: VelvetRadii.card,
          ),
          SizedBox(height: VelvetSpacing.md),
          SkeletonBlock(
            width: double.infinity,
            height: 110,
            radius: VelvetRadii.card,
          ),
        ],
      ),
    );
  }
}

/// Maps a [MasterReviewItem] to the shared [ReviewCard], populating the
/// muted service-name sub-line from [MasterReviewItem.serviceName] when the
/// backend resolved one (backend `92280c3`; mirrors salon's
/// `_salonReviewCard` in `salon_reviews_section.dart`). The name is rendered
/// as-is with no label.
ReviewCard _masterReviewCard(MasterReviewItem item) {
  final String? service = item.serviceName;
  return ReviewCard(
    data: ReviewCardData(
      id: item.id,
      clientDisplayName: item.clientDisplayName,
      rating: item.rating,
      comment: item.comment,
      createdAt: item.createdAt,
      serviceName: item.serviceName,
    ),
    keyPrefix: 'master-review',
    serviceName: (service != null && service.isNotEmpty) ? service : null,
  );
}
