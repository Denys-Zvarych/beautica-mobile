// M510 — the body of «Рейтинг клієнта» (ClientCardVariants `RatingBody`):
// the average + stars + count, the 5→1 distribution bars, «Ваші оцінки» and
// the privacy note.
//
// Average, count and distribution come from the CARD (D7); only the own
// ratings are a separate paged read. NO review comment text exists anywhere on
// this page: the contract and the domain types have no field for it (REV-D10),
// and the muted note says so.
//
// A SLIVER widget (for [ProfileScaffold.slivers]): «Ваші оцінки» is a lazy
// [SliverList], so a long own-ratings history builds only its visible rows.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/my_bookings_states.dart'
    show MyBookingsLoadMoreSpinner;
import 'package:beautica_mobile/features/clients/application/client_own_ratings_controller.dart';
import 'package:beautica_mobile/features/clients/domain/client_card.dart';
import 'package:beautica_mobile/features/clients/domain/client_own_rating.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/client_card_text.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/star_row.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/uk_calendar.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/load_more_retry_footer.dart';
import 'package:beautica_mobile/shared/widgets/rating_star.dart';

class RatingBody extends StatelessWidget {
  const RatingBody({
    super.key,
    required this.card,
    required this.own,
    required this.onRetryOwn,
    required this.onRetryMore,
  });

  final ClientCard card;

  /// The viewer's own ratings of this client (paged).
  final AsyncValue<ClientOwnRatingsState> own;
  final VoidCallback onRetryOwn;
  final VoidCallback onRetryMore;

  static const Key averageKey = Key('client-rating-average');
  static const Key countKey = Key('client-rating-count');
  static const Key ownEmptyKey = Key('client-own-ratings-empty');
  static const Key ownErrorKey = Key('client-own-ratings-error');
  static const Key ownRetryMoreKey = Key('client-own-ratings-retry-more');
  static const Key privacyNoteKey = Key('client-rating-private-note');

  /// Key of the distribution bar for [stars] (5..1).
  static Key barKey(int stars) => Key('client-rating-bar-$stars');

  static Key ownRowKey(String bookingId) => Key('client-own-rating-$bookingId');

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final int total = card.ratingCount;
    final double? avg = card.displayRating;
    return SliverMainAxisGroup(
      slivers: <Widget>[
        SliverToBoxAdapter(child: _summary(l10n, avg, total)),
        _ownSection(context, l10n),
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
        const SizedBox(height: 22),
        Text(l10n.clientOwnRatingsTitle, style: VelvetText.sectionLabel()),
        const SizedBox(height: 10),
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

  Widget _ownSection(BuildContext context, AppLocalizations l10n) {
    return own.when(
      loading: () =>
          const SliverToBoxAdapter(child: MyBookingsLoadMoreSpinner()),
      error: (Object e, StackTrace _) => SliverToBoxAdapter(
        child: ErrorState(
          key: ownErrorKey,
          failure: e is Failure ? e : UnknownFailure(cause: e),
          onRetry: onRetryOwn,
        ),
      ),
      data: (ClientOwnRatingsState data) {
        if (data.items.isEmpty) {
          return SliverToBoxAdapter(
            child: Text(
              l10n.clientOwnRatingsEmpty,
              key: ownEmptyKey,
              style: VelvetText.feedbackMutedSm,
            ),
          );
        }
        final List<ClientOwnRating> items = data.items;
        return SliverMainAxisGroup(
          slivers: <Widget>[
            // The NeumorphicCard look (padding zero, field radius, small
            // extrusion) painted around a lazy list instead of a Column.
            DecoratedSliver(
              decoration: BoxDecoration(
                color: BrandColors.base,
                borderRadius: BorderRadius.circular(VelvetRadii.field),
                boxShadow: VelvetShadows.extrudedSmall,
              ),
              sliver: SliverList.builder(
                itemCount: items.length,
                itemBuilder: (BuildContext _, int i) {
                  final Widget row = _OwnRatingRow(
                    key: ownRowKey(items[i].bookingId),
                    rating: items[i],
                  );
                  if (i == 0) return row;
                  return Column(
                    key: ValueKey<String>('own-rating-${items[i].bookingId}'),
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[const _Hairline(), row],
                  );
                },
              ),
            ),
            if (data.loadMoreFailed)
              SliverToBoxAdapter(
                child: LoadMoreRetryFooter(
                  message: l10n.clientsLoadMoreFailed,
                  onRetry: onRetryMore,
                  retryKey: ownRetryMoreKey,
                ),
              )
            else if (data.isLoadingMore)
              const SliverToBoxAdapter(child: MyBookingsLoadMoreSpinner()),
          ],
        );
      },
    );
  }
}

class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) => Container(
    height: 1,
    margin: const EdgeInsets.only(left: 16, right: 16),
    color: BrandColors.faint.withValues(alpha: 0.45),
  );
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

class _OwnRatingRow extends StatelessWidget {
  const _OwnRatingRow({super.key, required this.rating});

  final ClientOwnRating rating;

  /// «5 листопада 2026» — Kyiv wall-clock date.
  static String _date(DateTime instant) {
    final DateTime local = toBeauticaTime(instant);
    return '${local.day} ${monthGenitive(local.month)} ${local.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  rating.serviceName,
                  style: VelvetText.masterCardServiceFull,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _date(rating.visitAt),
                  style: VelvetText.masterCardDateFull,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          StarRow(stars: rating.stars, size: 15),
        ],
      ),
    );
  }
}
