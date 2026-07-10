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
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/relative_date.dart';
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
            data: (SalonReviewSummary summary) =>
                _RatingSummary(summary: summary),
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
                        _ReviewCard(review: reviews[i]),
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

/// A camel ★ row for a 1–5 [rating]. Filled stars use [BrandColors.accentDeep];
/// the remaining stars are muted to [BrandColors.faint].
class _StarRow extends StatelessWidget {
  const _StarRow({required this.rating, this.size = 16, this.gap = 2});

  final int rating;
  final double size;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < 5; i++) ...<Widget>[
          Icon(
            Icons.star_rounded,
            size: size,
            color: i < rating ? BrandColors.accentDeep : BrandColors.faint,
          ),
          if (i < 4) SizedBox(width: gap),
        ],
      ],
    );
  }
}

/// The raised rating-summary header: a big average + ★ row + count on the
/// left, a quiet five-row star distribution on the right.
class _RatingSummary extends StatelessWidget {
  const _RatingSummary({required this.summary});

  final SalonReviewSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final List<int> distribution = summary.distribution;
    int sum = 0;
    for (final int c in distribution) {
      sum += c;
    }
    final int denom = sum == 0 ? 1 : sum;
    final double? avg = summary.avgRating;

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
                  key: const Key('salon-review-summary-average'),
                  style: VelvetText.salonReviewAverage,
                ),
                const SizedBox(height: VelvetSpacing.xs + 2),
                const _StarRow(rating: 5, size: 17, gap: 3),
                const SizedBox(height: VelvetSpacing.xs + 2),
                Text(
                  l10n.salonReviewCountLabel(summary.reviewCount),
                  style: VelvetText.feedbackMutedSm,
                ),
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

/// A single review: a raised card with an avatar + name + relative-date
/// header, this review's ★ row, the comment body and an optional muted
/// «послуга: …» sub-line.
class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});

  final SalonReviewItem review;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String relativeDate = formatRelativeDate(l10n, review.createdAt);
    final String? service = review.serviceName;
    return NeumorphicCard(
      key: Key('salon-review-${review.id}'),
      padding: const EdgeInsets.all(VelvetSpacing.md + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              _ReviewAvatar(seed: review.id),
              const SizedBox(width: VelvetSpacing.sm + 2),
              Expanded(
                child: Text(
                  review.clientDisplayName,
                  style: VelvetText.subheading15,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: VelvetSpacing.sm),
              Text(relativeDate, style: VelvetText.feedbackMutedSm),
            ],
          ),
          const SizedBox(height: VelvetSpacing.sm + 2),
          _StarRow(rating: review.rating, size: 16, gap: 2),
          const SizedBox(height: VelvetSpacing.sm + 2),
          Text(review.comment, style: VelvetText.bodyStrong()),
          if (service != null && service.isNotEmpty) ...<Widget>[
            const SizedBox(height: VelvetSpacing.sm + 2),
            Row(
              children: <Widget>[
                const Icon(
                  Icons.spa_outlined,
                  size: 13,
                  color: BrandColors.muted,
                ),
                const SizedBox(width: VelvetSpacing.xs + 1),
                Flexible(
                  child: Text(
                    l10n.salonReviewServicePrefix(service),
                    style: VelvetText.feedbackMuted12w600,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A small circular gradient avatar with an embossed person glyph — the same
/// camel→mocha treatment as [SalonMasterCard]'s avatar, sized for a review
/// row. [seed] deterministically picks the gradient (never a fabricated
/// photo).
class _ReviewAvatar extends StatelessWidget {
  const _ReviewAvatar({required this.seed});

  final String seed;

  static const List<List<Color>> _gradients = <List<Color>>[
    <Color>[Color(0xFFD4B896), Color(0xFF8A6840)],
    <Color>[Color(0xFFB89A7A), Color(0xFF6A4A28)],
    <Color>[Color(0xFFDFC6A8), Color(0xFFB89A7A)],
    <Color>[Color(0xFFC8A878), Color(0xFF6A4A28)],
    <Color>[Color(0xFFCFB090), Color(0xFF8A6840)],
    <Color>[Color(0xFFE0CAAC), Color(0xFFB89A7A)],
  ];

  @override
  Widget build(BuildContext context) {
    final List<Color> gradient =
        _gradients[seed.hashCode.abs() % _gradients.length];
    return Container(
      height: 40,
      width: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
        boxShadow: VelvetShadows.extrudedSmall,
      ),
      child: Center(
        child: Icon(
          Icons.person_rounded,
          color: BrandColors.white.withValues(alpha: 0.82),
          size: 20,
        ),
      ),
    );
  }
}
