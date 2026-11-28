// M510 — the body of «Рейтинг клієнта» (ClientCardVariants `RatingBody`):
// the average + stars + count, the 5→1 distribution bars and the privacy note
// (CLI-60 — no «Ваші оцінки» section, CLI-D07).
//
// The summary comes from the CARD (D7) — no read of its own.
//
// M545 (CLI-60, REV-44) — with a [RatingBody.scope], the anonymous comments
// follow the note as the «Коментарі» section ([ClientCommentsSliver]): every
// row is the SHARED [ReviewCard] (the master «Відгуки» row, REUSE-FIRST) with
// no avatar and no name — only «Ваш коментар» on the viewer's own — the visit
// month in the date slot, the stars and the text. Hidden while loading and
// when there are none; an inline retry on error; a «⋮» report
// (`CLIENT_REVIEW`, MOD-41) on every comment that is not the viewer's own.
//
// A SLIVER widget (for [ProfileScaffold.slivers]).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/my_bookings_states.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/booking/application/pending_booking_actions_count.dart';
import 'package:beautica_mobile/features/booking/application/booking_detail_notifier.dart';
import 'package:beautica_mobile/features/clients/application/client_comments_controller.dart';
import 'package:beautica_mobile/features/clients/application/client_card_controller.dart';
import 'package:beautica_mobile/features/clients/application/client_list_controller.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/delete_client_rating_dialog.dart';
import 'package:beautica_mobile/features/clients/domain/client_card.dart';
import 'package:beautica_mobile/features/clients/domain/client_review_comment.dart';
import 'package:beautica_mobile/features/clients/domain/client_summary.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/client_card_text.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/star_row.dart';
import 'package:beautica_mobile/features/moderation/application/my_reported_targets_notifier.dart';
import 'package:beautica_mobile/features/moderation/domain/content_report.dart';
import 'package:beautica_mobile/features/moderation/presentation/widgets/report_sheet.dart';
import 'package:beautica_mobile/features/review/presentation/widgets/review_card.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/feedback/show_velvet_snack.dart';
import 'package:beautica_mobile/shared/widgets/load_more_retry_footer.dart';
import 'package:beautica_mobile/shared/widgets/rating_star.dart';

class RatingBody extends StatelessWidget {
  const RatingBody({super.key, required this.card, this.scope});

  final ClientCard card;

  /// ADDITIVE (M545): the card's scope. When set, the anonymous comments
  /// section follows the note ([ClientCommentsSliver]); `null` renders the
  /// summary and the note only, exactly as before.
  final ClientListScope? scope;

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
    final ClientListScope? commentsScope = scope;
    return SliverMainAxisGroup(
      slivers: <Widget>[
        SliverToBoxAdapter(child: _summary(l10n, avg, total)),
        SliverToBoxAdapter(child: _privacyNote(l10n)),
        if (commentsScope != null)
          ClientCommentsSliver(scope: commentsScope, client: card.ref),
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

/// M545 — the «Коментарі» section (REV-44): a lazy sliver of [ReviewCard]s
/// over [clientCommentsControllerProvider]. The ONLY widget that watches it,
/// so paging rebuilds just this section. Nothing renders while page 0 loads
/// or when there are no comments (E1, E4) — the section only ever appears
/// with content, never as a flashing placeholder.
class ClientCommentsSliver extends ConsumerWidget {
  const ClientCommentsSliver({
    super.key,
    required this.scope,
    required this.client,
  });

  final ClientListScope scope;
  final ClientRef client;

  static const Key titleKey = Key('client-rating-comments-title');
  static const Key retryKey = Key('client-rating-comments-retry');
  static const Key retryMoreKey = Key('client-rating-comments-retry-more');

  /// The [ReviewCard] key namespace: rows are `client-comment-<reviewId>`,
  /// the «⋮» `client-comment-more-<reviewId>` ([ReviewCard.moreKey]).
  static const String keyPrefix = 'client-comment';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ClientCommentsControllerProvider provider =
        clientCommentsControllerProvider(scope, client);
    final AsyncValue<ClientCommentsState> comments = ref.watch(provider);
    return comments.when(
      // A failed refresh keeps the loaded rows, and a reload never blanks them.
      skipError: comments.hasValue,
      skipLoadingOnReload: true,
      loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
      error: (Object e, StackTrace _) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: VelvetSpacing.md),
          child: LoadMoreRetryFooter(
            message: l10n.clientRatingCommentsLoadFailed,
            onRetry: () => ref.invalidate(provider),
            retryKey: retryKey,
          ),
        ),
      ),
      data: (ClientCommentsState s) {
        if (s.comments.isEmpty) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }
        if (s.canLoadMore) _loadMoreIfUnscrollable(context, ref, provider);
        final int count = s.comments.length;
        final bool tail = s.loadMoreFailed || s.isLoadingMore;
        return SliverList.builder(
          // Title + rows + an optional retry / spinner tail.
          itemCount: 1 + count + (tail ? 1 : 0),
          itemBuilder: (BuildContext context, int index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(
                  top: VelvetSpacing.lg,
                  bottom: VelvetSpacing.sm,
                ),
                child: Text(
                  l10n.clientRatingCommentsTitle,
                  key: titleKey,
                  style: VelvetText.sectionLabel(),
                ),
              );
            }
            if (index <= count) {
              final ClientReviewComment c = s.comments[index - 1];
              final double gap = index == count && !tail ? 0 : _kRowGap;
              // Own «⋮» → delete the whole rating, the row collapsing out
              // (M572, REV-45).
              if (c.own) {
                return _OwnCommentRow(
                  key: ValueKey<String>('client-comment-row-${c.reviewId}'),
                  comment: c,
                  provider: provider,
                  bottomGap: gap,
                );
              }
              return Padding(
                key: ValueKey<String>('client-comment-row-${c.reviewId}'),
                padding: EdgeInsets.only(bottom: gap),
                // Report once, ever (phase 428): a per-row Consumer so a
                // report flips ONE row, never the whole section.
                child: Consumer(
                  builder: (BuildContext context, WidgetRef ref, _) =>
                      _commentCard(
                        l10n,
                        c,
                        onMore:
                            watchIsReported(
                              ref,
                              ReportTargetType.clientReview,
                              c.reviewId,
                            )
                            ? null
                            : () => showReportSheet(
                                context,
                                targetType: ReportTargetType.clientReview,
                                targetId: c.reviewId,
                                subject: l10n.reportSubjectClientComment,
                              ),
                      ),
                ),
              );
            }
            return s.loadMoreFailed
                ? LoadMoreRetryFooter(
                    message: l10n.clientRatingCommentsLoadFailed,
                    onRetry: () => ref.read(provider.notifier).retryLoadMore(),
                    retryKey: retryMoreKey,
                  )
                : const MyBookingsLoadMoreSpinner();
          },
        );
      },
    );
  }
}

/// Paging is scroll-driven, so a page that fits the viewport would never be
/// followed by the next one. After it lands, check once post-frame: if the
/// list cannot scroll, append now (the controller guards duplicates).
void _loadMoreIfUnscrollable(
  BuildContext context,
  WidgetRef ref,
  ClientCommentsControllerProvider provider,
) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    final ScrollPosition? position = Scrollable.maybeOf(context)?.position;
    if (position == null ||
        !position.hasContentDimensions ||
        position.maxScrollExtent > position.minScrollExtent) {
      return;
    }
    ref.read(provider.notifier).loadMore();
  });
}

/// «листопад 2026» — the comment's Kyiv visit month, in the app locale.
String formatCommentVisitMonth(
  AppLocalizations l10n,
  ClientReviewComment comment,
) => _visitMonthFormats
    .putIfAbsent(l10n.localeName, () => DateFormat('LLLL y', l10n.localeName))
    .format(DateTime(comment.visitYear, comment.visitMonth));

/// One `LLLL y` formatter per locale, built once — not per row per build.
final Map<String, DateFormat> _visitMonthFormats = <String, DateFormat>{};

/// The gap between two comment rows (M572 — the compact row's `sm+4`).
const double _kRowGap = VelvetSpacing.sm + 4;

/// Rows clamp to this many lines; «Ще» expands the rest (M572).
const int _kCommentCollapsedLines = 3;

/// How long a deleted row takes to collapse out (the M571 preview's value).
const Duration _kCollapse = Duration(milliseconds: 280);

/// The fade takes the first part of the collapse (the preview's 180 ms).
const int _kFadeMs = 180;

/// The viewer's own comment row (M572, CLI-102, REV-45): «⋮» → confirm → the
/// server deletes the whole rating → the row fades and collapses out (the M571
/// preview's curve and duration; at once under reduced motion) → it is dropped
/// from the list. The row only leaves AFTER the server said yes, so a failure
/// leaves it exactly where it was (error snack, no flash). On success (or an
/// already-gone 404) the views that show the rating are dropped so they
/// re-read: the card (average and distribution), the «Клієнти» list row, the
/// archive pending count (BOOK-D11) and every cached booking detail — the
/// comment is anonymous (REV-44), so its booking is unknown and the whole
/// family goes, letting `providerCanReviewClient` re-read true (REV-43).
class _OwnCommentRow extends ConsumerStatefulWidget {
  const _OwnCommentRow({
    super.key,
    required this.comment,
    required this.provider,
    required this.bottomGap,
  });

  final ClientReviewComment comment;
  final ClientCommentsControllerProvider provider;
  final double bottomGap;

  @override
  ConsumerState<_OwnCommentRow> createState() => _OwnCommentRowState();
}

class _OwnCommentRowState extends ConsumerState<_OwnCommentRow>
    with SingleTickerProviderStateMixin {
  /// 1 (visible, at rest) → 0 over [_kCollapse]: drives the size and (its
  /// last 180 ms) the fade. The tree below is the SAME before and during the
  /// collapse, so the card's own state (an expanded «Ще») survives it.
  late final AnimationController _collapse;
  late final CurvedAnimation _size;
  late final CurvedAnimation _fade;

  /// A delete is in flight or playing out — a second «⋮» tap does nothing.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _collapse = AnimationController(
      vsync: this,
      duration: _kCollapse,
      value: 1,
    );
    _size = CurvedAnimation(parent: _collapse, curve: Curves.easeInOutCubic);
    _fade = CurvedAnimation(
      parent: _collapse,
      curve: const Interval(1 - _kFadeMs / 280, 1),
    );
  }

  @override
  void dispose() {
    _size.dispose();
    _fade.dispose();
    _collapse.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (_busy) return;
    final bool? confirmed = await showDeleteClientRatingDialog(context);
    if (confirmed != true || !mounted || _busy) return;
    _busy = true;
    final AppLocalizations l10n = AppLocalizations.of(context);
    // Captured BEFORE any await: the invalidations below must still run when
    // the screen is popped during the request or the collapse.
    final ProviderContainer container = ProviderScope.containerOf(
      context,
      listen: false,
    );
    final ClientCommentsController controller = ref.read(
      widget.provider.notifier,
    );
    final String reviewId = widget.comment.reviewId;
    final bool deleted;
    try {
      deleted = await controller.deleteOwn(reviewId);
    } catch (e) {
      _busy = false;
      if (!mounted) return;
      showErrorSnack(
        context,
        (e is Failure ? e : UnknownFailure(cause: e)).userMessage(context),
      );
      return;
    }
    // Gone on the server (deleted or already gone): the views that show the
    // rating re-read now. NOT the comments family — [dropComment] removes the
    // row locally, and a refetch would drop the loaded pages — and NOT the
    // visits (a deleted rating changes none).
    container.invalidate(clientCardProvider);
    container.invalidate(clientListControllerProvider);
    container.invalidate(pendingBookingActionsCountProvider);
    container.invalidate(bookingDetailProvider);
    if (!mounted) {
      // The row is already gone from the tree: drop it from the list at once
      // so a surviving provider never shows a stale row.
      controller.dropComment(reviewId);
      return;
    }
    if (deleted) showSuccessSnack(context, l10n.clientRatingDeleted);
    if (!MediaQuery.disableAnimationsOf(context)) {
      try {
        await _collapse.reverse().orCancel;
      } on TickerCanceled {
        // Unmounted mid-collapse: drop it now.
      }
    }
    final bool dropped = controller.dropComment(reviewId);
    if (!dropped && mounted) {
      // Nothing to drop it from (the list is not loaded): never leave an
      // invisible zero-height ghost — the row reappears at rest and the
      // provider's next data removes it (the delete does not invalidate the
      // comments family).
      _collapse.value = 1;
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Widget card = Padding(
      padding: EdgeInsets.only(bottom: widget.bottomGap),
      child: _commentCard(l10n, widget.comment, onMore: _delete),
    );
    // `Align` (not `SizeTransition`) shrinks the row: it never clips, so the
    // card's neumorphic shadows stay whole at rest; while collapsing, the
    // overflow fades with the row.
    return AnimatedBuilder(
      animation: _size,
      builder: (BuildContext context, Widget? child) => Align(
        alignment: Alignment.topCenter,
        heightFactor: _size.value,
        child: child,
      ),
      // dim-decorative: the delete collapse-out fade; 1 at rest, and the row
      // is gone once it reaches 0 — nothing durable is encoded.
      child: FadeTransition(opacity: _fade, child: card),
    );
  }
}

/// One comment as the shared [ReviewCard] in its dense layout (M572, CLI-102):
/// stars, visit month and — on the viewer's own — the «Ваш коментар» tag on
/// one meta line, then the text clamped to three lines. No avatar, no author
/// (REV-D10).
ReviewCard _commentCard(
  AppLocalizations l10n,
  ClientReviewComment c, {
  required VoidCallback? onMore,
}) => ReviewCard(
  data: ReviewCardData(
    id: c.reviewId,
    clientDisplayName: '',
    rating: c.stars,
    comment: c.comment,
  ),
  keyPrefix: ClientCommentsSliver.keyPrefix,
  showAvatar: false,
  dense: true,
  dateLabel: formatCommentVisitMonth(l10n, c),
  tagLabel: c.own ? l10n.clientRatingOwnComment : null,
  collapsedLines: _kCommentCollapsedLines,
  expandLabel: l10n.clientRatingExpand,
  onMore: onMore,
);

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
