// Phase 4.6 — Independent-master received-reviews screen ("Мої відгуки").
//
// The salon "Відгуки" tab (Phase 13.6) lifted onto a standalone, pushed master
// screen: a rating-summary card (avg ★ + count + 5★→1★ distribution) over a
// sortable list of review cards, with a ⇅ sort control. Renders from the SAME
// shared `review` widgets the salon profile uses (Phase 4.5 extraction), so the
// two surfaces are visually identical.
//
// Master deltas vs salon (documented, not bugs):
//   • Standalone screen with a back affordance (pushed route), titled
//     «Мої відгуки» — not a tab inside another profile.
//
// The «послуга:» sub-line (backend `92280c3` added `serviceName` to the master
// review item) is built by [_masterReviewCard] below, mirroring salon's
// `_salonReviewCard` — hidden when the backend couldn't resolve a service name.
//
// masterId source (CORRECTNESS — HIGH): the review endpoints
// `GET /masters/{masterId}/reviews[/summary]` MUST be keyed on the Master-row
// id, which is an independently generated UUID DISTINCT from the session user
// id (`master.id != user.id`). That id is read from the loaded profile
// ([masterProfileProvider] → `GET /masters/me` → `MasterDetailResponse.masterId`,
// surfaced as [Master.id] by [MasterMapper.fromDto]). Querying by
// `session.user.id` (the old bug) lands every real independent master on the
// backend's non-master routes: summary 404 + an empty list. The screen therefore
// resolves the id from [masterProfileProvider], handling its own loading/error
// states, while keeping the unauthenticated fail-closed short-circuit.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/master/application/master_review_summary_notifier.dart';
import 'package:beautica_mobile/features/master/application/master_reviews_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/domain/master_review.dart';
import 'package:beautica_mobile/features/review/presentation/widgets/rating_summary_card.dart';
import 'package:beautica_mobile/features/review/presentation/widgets/review_card.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';

import 'master_profile_notifier.dart';
import 'widgets/master_review_sort_sheet.dart';
import 'widgets/profile_scaffold.dart';

/// The master's own received-reviews screen.
///
/// Resolves the masterId from the loaded [masterProfileProvider] (the
/// Master-row id — see the file header) and threads it into
/// [masterReviewSummaryProvider] / [masterReviewsProvider]. Acquires the
/// ref-counted [ScreenProtectionManager] for the lifetime of this PII surface
/// (mirrors [MasterProfileScreen]).
class MasterReceivedReviewsScreen extends ConsumerStatefulWidget {
  const MasterReceivedReviewsScreen({super.key});

  @override
  ConsumerState<MasterReceivedReviewsScreen> createState() =>
      _MasterReceivedReviewsScreenState();
}

class _MasterReceivedReviewsScreenState
    extends ConsumerState<MasterReceivedReviewsScreen> {
  // Captured in initState so dispose() never touches `ref` — under Riverpod 3.x
  // reading `ref` in dispose() throws. Hold the keepAlive manager reference.
  late final ScreenProtectionManager _screenProtection;

  @override
  void initState() {
    super.initState();
    // SEC LOW: ref-counted screenshot guard + iOS app-switcher-snapshot blur
    // for this PII-bearing `/master/*` surface (client names + comments). The
    // manager is idempotent and `!kDebugMode`-guarded internally.
    _screenProtection = ref.read(screenProtectionProvider)..acquire();
  }

  @override
  void dispose() {
    // SEC LOW: release the ref-counted guard; protection only lifts once the
    // last PII route unmounts.
    _screenProtection.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final session = ref.watch(authProvider).value;

    if (session is! Authenticated) {
      // No authenticated session — the redirect guard normally prevents this,
      // but fail closed with a retryable error rather than a crash. Short-
      // circuits BEFORE watching the profile or the review providers.
      return ProfileScaffold(
        title: l10n.masterReviewsTitle,
        child: ErrorState(
          failure: const UnauthorizedFailure(),
          onRetry: () => ref.invalidate(authProvider),
        ),
      );
    }

    // Resolve the Master-row id from the loaded profile — NOT session.user.id
    // (see the file header). The profile's own loading / error states are
    // rendered here so the review providers are only keyed once a real id
    // exists.
    final masterAsync = ref.watch(masterProfileProvider);

    return ProfileScaffold(
      title: l10n.masterReviewsTitle,
      child: masterAsync.when(
        data: (Master master) => _ReviewsContent(masterId: master.id),
        loading: () => const _ReviewsScreenSkeleton(),
        error: (Object e, _) => ErrorState(
          failure: e is Failure ? e : UnknownFailure(cause: e),
          onRetry: () => ref.invalidate(masterProfileProvider),
        ),
      ),
    );
  }
}

/// Loaded-profile body: the sort-independent summary card over the sortable
/// review list. Composed of two sibling subtrees so a sort toggle (held in
/// [_SortableReviewList]) rebuilds ONLY the list — never the summary card.
class _ReviewsContent extends StatelessWidget {
  const _ReviewsContent({required this.masterId});

  /// The Master-row id (from [masterProfileProvider]).
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
                    final Widget card = _masterReviewCard(l10n, r);
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

/// Full-screen skeleton shown while the master profile itself is loading:
/// the rating-summary placeholder over the review-list placeholder.
class _ReviewsScreenSkeleton extends StatelessWidget {
  const _ReviewsScreenSkeleton();

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
/// «послуга: …» sub-line from [MasterReviewItem.serviceName] when the backend
/// resolved one (backend `92280c3`; mirrors salon's `_salonReviewCard` in
/// `salon_reviews_section.dart`, including the reused `salonReviewServicePrefix`
/// l10n key — the "послуга: {service}" copy is feature-neutral).
ReviewCard _masterReviewCard(AppLocalizations l10n, MasterReviewItem item) {
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
    servicePrefix: (service != null && service.isNotEmpty)
        ? l10n.salonReviewServicePrefix(service)
        : null,
  );
}
