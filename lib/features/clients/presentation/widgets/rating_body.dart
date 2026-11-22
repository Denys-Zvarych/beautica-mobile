// M510 — the body of «Рейтинг клієнта» (ClientCardVariants `RatingBody`):
// the average + stars + count, the 5→1 distribution bars and the privacy note
// (CLI-60 — no «Ваші оцінки» section, CLI-D07).
//
// Everything comes from the CARD (D7) — no read of its own. NO review comment
// text exists anywhere on this page: the contract and the domain types have no
// field for it (REV-D10), and the muted note says so.
//
// A SLIVER widget (for [ProfileScaffold.slivers]).

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/clients/domain/client_card.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/client_card_text.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/star_row.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/rating_star.dart';

class RatingBody extends StatelessWidget {
  const RatingBody({super.key, required this.card});

  final ClientCard card;

  static const Key averageKey = Key('client-rating-average');
  static const Key countKey = Key('client-rating-count');
  static const Key privacyNoteKey = Key('client-rating-private-note');

  /// Key of the distribution bar for [stars] (5..1).
  static Key barKey(int stars) => Key('client-rating-bar-$stars');

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final int total = card.ratingCount;
    final double? avg = card.displayRating;
    return SliverMainAxisGroup(
      slivers: <Widget>[
        SliverToBoxAdapter(child: _summary(l10n, avg, total)),
        SliverToBoxAdapter(child: _privacyNote(l10n)),
      ],
    );
  }

  Widget _summary(AppLocalizations l10n, double? avg, int total) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        NeumorphicCard(
          padding: const EdgeInsets.all(VelvetSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    avg == null ? '—' : formatClientRatingAvg(avg),
                    key: averageKey,
                    // The shipped `RatingSummaryCard` average.
                    style: VelvetText.salonReviewAverage,
                  ),
                  const SizedBox(height: 4),
                  StarRow(stars: (avg ?? 0).round(), size: 14),
                  const SizedBox(height: 4),
                  Text(
                    total == 0
                        ? l10n.clientRatingEmpty
                        : l10n.clientRatingCount(total),
                    key: countKey,
                    style: VelvetText.feedbackMutedSm,
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: <Widget>[
                    for (int i = 0; i < kClientRatingBuckets; i++)
                      _DistributionBar(
                        stars: kClientRatingBuckets - i,
                        count: card.ratingDistribution[i],
                        total: total,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _privacyNote(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(
                Icons.lock_outline_rounded,
                size: 14,
                color: BrandColors.muted,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                l10n.clientRatingPrivacyNote,
                key: privacyNoteKey,
                style: VelvetText.feedbackMutedSm,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DistributionBar extends StatelessWidget {
  const _DistributionBar({
    required this.stars,
    required this.count,
    required this.total,
  });

  final int stars;
  final int count;
  final int total;

  @override
  Widget build(BuildContext context) {
    final double fraction = total == 0 ? 0 : (count / total).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 12,
            child: Text(
              '$stars',
              // `RatingSummaryCard`'s distribution star number.
              style: VelvetText.bodyStrong12,
            ),
          ),
          const RatingStar(rating: 5, size: 12, showLabel: false),
          const SizedBox(width: 6),
          Expanded(
            child: SizedBox(
              key: RatingBody.barKey(stars),
              height: 8,
              child: NeumorphicInset(
                radius: 4,
                animatedRing: false,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: fraction),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOutCubic,
                    builder: (BuildContext _, double v, Widget? _) =>
                        FractionallySizedBox(
                          widthFactor: v,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: VelvetGradients.accentDiscFace,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 20,
            child: Text(
              '$count',
              textAlign: TextAlign.right,
              style: VelvetText.feedbackMutedXs,
            ),
          ),
        ],
      ),
    );
  }
}
