// Phase 13.6 — Salon reviews tab ("Відгуки") — the read-only, client-facing
// reviews view of a salon.
//
// Ported from the approved preview app at
// `docs/signup-designs/PublicSalonProfile/lib/widgets/salon_reviews.dart`,
// wired to [salonReviewSummaryProvider] / [salonReviewsProvider] instead of
// the preview's static mock data + local client-side sort. Sorting now
// RE-FETCHES a server-sorted page (re-keys the [salonReviewsProvider] family)
// rather than re-ordering the previous page client-side.
//
// In Beautica's two-sided rating model a public profile shows the provider's
// reputation: the aggregate score plus the individual reviews left by other
// clients. There is deliberately NO "leave review" affordance here —
// authoring a review is a separate, post-booking flow (a future phase).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/review/presentation/widgets/rating_summary_card.dart';
import 'package:beautica_mobile/features/review/presentation/widgets/review_card.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';

import '../../application/salon_review_summary_notifier.dart';
import '../../application/salon_reviews_notifier.dart';
import '../../domain/salon_review.dart';

/// Returns the localised label for [sort].
String salonReviewSortLabel(AppLocalizations l10n, SalonReviewSort sort) {
  switch (sort) {
    case SalonReviewSort.newest:
      return l10n.salonReviewSortNewest;
    case SalonReviewSort.oldest:
      return l10n.salonReviewSortOldest;
    case SalonReviewSort.highest:
      return l10n.salonReviewSortHighest;
    case SalonReviewSort.lowest:
      return l10n.salonReviewSortLowest;
  }
}

/// The "Відгуки" tab body: a rating-summary card, a sort header, and the
/// list of individual review cards.
class SalonReviewsSection extends ConsumerStatefulWidget {
  const SalonReviewsSection({super.key, required this.salonId});

  final String salonId;

  @override
  ConsumerState<SalonReviewsSection> createState() =>
      _SalonReviewsSectionState();
}

class _SalonReviewsSectionState extends ConsumerState<SalonReviewsSection> {
  SalonReviewSort _sort = SalonReviewSort.newest;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final summaryAsync = ref.watch(salonReviewSummaryProvider(widget.salonId));
    final reviewsAsync = ref.watch(salonReviewsProvider(widget.salonId, _sort));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          summaryAsync.when(
            data: (SalonReviewSummary summary) => RatingSummaryCard(
              avgRating: summary.avgRating,
              reviewCount: summary.reviewCount,
              distribution: summary.distribution,
              countLabel: l10n.salonReviewCountLabel(summary.reviewCount),
              averageKey: const Key('salon-review-summary-average'),
            ),
            loading: () => const _RatingSummarySkeleton(),
            error: (Object e, _) => ErrorState(
              failure: e is Failure ? e : UnknownFailure(cause: e),
              onRetry: () =>
                  ref.invalidate(salonReviewSummaryProvider(widget.salonId)),
            ),
          ),
          const SizedBox(height: VelvetSpacing.md),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  salonReviewSortLabel(l10n, _sort),
                  style: VelvetText.salonSortLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: VelvetSpacing.sm),
              _SortIconButton(
                active: _sort,
                onSelected: (SalonReviewSort s) => setState(() => _sort = s),
              ),
            ],
          ),
          const SizedBox(height: VelvetSpacing.md),
          reviewsAsync.when(
            data: (List<SalonReviewItem> reviews) => reviews.isEmpty
                ? Padding(
                    key: const Key('salon-reviews-empty'),
                    padding: const EdgeInsets.symmetric(
                      vertical: VelvetSpacing.lg,
                    ),
                    child: Text(
                      l10n.salonReviewsEmpty,
                      textAlign: TextAlign.center,
                      style: VelvetText.feedback(BrandColors.muted),
                    ),
                  )
                : Column(
                    children: <Widget>[
                      for (int i = 0; i < reviews.length; i++) ...<Widget>[
                        _salonReviewCard(l10n, reviews[i]),
                        if (i < reviews.length - 1)
                          const SizedBox(height: VelvetSpacing.md),
                      ],
                    ],
                  ),
            loading: () => const _ReviewListSkeleton(),
            error: (Object e, _) => ErrorState(
              failure: e is Failure ? e : UnknownFailure(cause: e),
              onRetry: () =>
                  ref.invalidate(salonReviewsProvider(widget.salonId, _sort)),
            ),
          ),
        ],
      ),
    );
  }
}

/// A square extruded ⇅ icon button that opens [_SortSheet].
class _SortIconButton extends StatelessWidget {
  const _SortIconButton({required this.active, required this.onSelected});

  final SalonReviewSort active;
  final ValueChanged<SalonReviewSort> onSelected;

  Future<void> _open(BuildContext context) async {
    final SalonReviewSort? picked = await _SortSheet.show(context, active);
    if (picked != null && picked != active) onSelected(picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: l10n.salonReviewSortButtonLabel,
      value: salonReviewSortLabel(l10n, active),
      child: GestureDetector(
        key: const Key('salon-reviews-sort-button'),
        onTap: () => _open(context),
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 44,
          width: 44,
          decoration: const BoxDecoration(
            color: BrandColors.base,
            borderRadius: BorderRadius.all(Radius.circular(VelvetRadii.field)),
            boxShadow: VelvetShadows.extrudedSmall,
          ),
          child: const Icon(
            Icons.swap_vert_rounded,
            color: BrandColors.textSecondary,
            size: 22,
          ),
        ),
      ),
    );
  }
}

/// The sort-options modal bottom sheet.
class _SortSheet extends StatelessWidget {
  const _SortSheet({required this.active});

  final SalonReviewSort active;

  static Future<SalonReviewSort?> show(
    BuildContext context,
    SalonReviewSort active,
  ) {
    return showModalBottomSheet<SalonReviewSort>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) => _SortSheet(active: active),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: BrandColors.base,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(VelvetRadii.card),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            VelvetSpacing.lg,
            VelvetSpacing.md,
            VelvetSpacing.lg,
            VelvetSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Container(
                  height: 4,
                  width: 44,
                  decoration: BoxDecoration(
                    color: BrandColors.faint,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: VelvetSpacing.md),
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text(
                  l10n.salonReviewSortSheetTitle,
                  style: VelvetText.subheading(),
                ),
              ),
              const SizedBox(height: VelvetSpacing.md),
              for (final SalonReviewSort option
                  in SalonReviewSort.values) ...<Widget>[
                _SortRow(
                  option: option,
                  label: salonReviewSortLabel(l10n, option),
                  selected: option == active,
                  onTap: () => context.pop(option),
                ),
                if (option != SalonReviewSort.values.last)
                  const SizedBox(height: VelvetSpacing.sm),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One selectable sort row. Selected → pressed inset well + camel check;
/// unselected → raised on the base surface.
class _SortRow extends StatelessWidget {
  const _SortRow({
    required this.option,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final SalonReviewSort option;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Widget row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: VelvetSpacing.md,
        vertical: VelvetSpacing.md,
      ),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: VelvetText.bodyStrong15)),
          if (selected)
            const Icon(
              Icons.check_rounded,
              color: BrandColors.accent,
              size: 22,
            ),
        ],
      ),
    );

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        key: Key('salon-review-sort-option-${option.name}'),
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: selected
            ? NeumorphicInset(radius: VelvetRadii.field, child: row)
            : DecoratedBox(
                decoration: const BoxDecoration(
                  color: BrandColors.base,
                  borderRadius: BorderRadius.all(
                    Radius.circular(VelvetRadii.field),
                  ),
                  boxShadow: VelvetShadows.extrudedSmall,
                ),
                child: row,
              ),
      ),
    );
  }
}

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

/// Maps a salon [SalonReviewItem] to the shared [ReviewCard], populating the
/// «послуга: …» sub-line from the item's [SalonReviewItem.serviceName] (master
/// reviews have no service, so their cards pass no [ReviewCard.servicePrefix]).
ReviewCard _salonReviewCard(AppLocalizations l10n, SalonReviewItem item) {
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
    keyPrefix: 'salon-review',
    servicePrefix: (service != null && service.isNotEmpty)
        ? l10n.salonReviewServicePrefix(service)
        : null,
  );
}
