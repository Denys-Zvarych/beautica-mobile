// Phase 13.4 — Discovery results async-state widgets.
//
// The three non-data states for the results screen:
//   • [ResultsSkeleton] — a 6-card shimmerless neumorphic placeholder list shown
//     while the first page loads,
//   • [ResultsEmpty]    — «Нічого не знайдено» + a «Змінити фільтри» action,
//   • [ResultsError]    — the failure message + a retry button.
//
// All three live inside the same padded list region as the real cards so the
// layout never jumps between states.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

/// Padding shared by the results list + all of its states.
const EdgeInsets kResultsListPadding = EdgeInsets.fromLTRB(
  VelvetSpacing.lg,
  VelvetSpacing.sm,
  VelvetSpacing.lg,
  VelvetSpacing.xl,
);

/// First-page loading placeholder — six muted card-shaped wells.
class ResultsSkeleton extends StatelessWidget {
  const ResultsSkeleton({super.key});

  static const int _count = 6;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      key: const Key('results_skeleton'),
      padding: kResultsListPadding,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _count,
      separatorBuilder: (_, _) => const SizedBox(height: VelvetSpacing.md),
      itemBuilder: (_, _) => const _SkeletonCard(),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  static final BoxDecoration _block = BoxDecoration(
    color: BrandColors.faint.withValues(alpha: 0.3),
    borderRadius: BorderRadius.circular(VelvetRadii.field),
  );

  @override
  Widget build(BuildContext context) {
    return NeumorphicCard(
      padding: const EdgeInsets.all(VelvetSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(height: 72, width: 72, decoration: _block),
          const SizedBox(width: VelvetSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(height: 16, width: 140, decoration: _block),
                const SizedBox(height: VelvetSpacing.sm),
                Container(height: 12, width: 100, decoration: _block),
                const SizedBox(height: VelvetSpacing.sm),
                Container(height: 12, width: 70, decoration: _block),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// «Нічого не знайдено» empty state with a «Змінити фільтри» action.
class ResultsEmpty extends StatelessWidget {
  const ResultsEmpty({
    super.key,
    required this.onEditFilters,
    this.serviceFilterActive = false,
  });

  /// Invoked by the «Змінити фільтри» button (re-opens the filter controls).
  final VoidCallback onEditFilters;

  /// Whether the empty result came from an active per-service (`serviceTypeSlugs`)
  /// filter. When true the supporting copy guides the user to broaden the
  /// SERVICE selection specifically (a narrower OR / union set still narrows), instead of the
  /// generic "change city / category / price" message.
  final bool serviceFilterActive;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String body = serviceFilterActive
        ? l10n.searchResultsEmptyServiceBody
        : l10n.searchResultsEmptyBody;
    return Center(
      key: const Key('results_empty'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          padding: const EdgeInsets.all(VelvetSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.search_off_rounded,
                size: 48,
                color: BrandColors.accent,
              ),
              const SizedBox(height: VelvetSpacing.md),
              Text(
                l10n.searchResultsEmptyTitle,
                textAlign: TextAlign.center,
                style: VelvetText.subheading(),
              ),
              const SizedBox(height: VelvetSpacing.sm),
              Text(body, textAlign: TextAlign.center, style: VelvetText.body()),
              const SizedBox(height: VelvetSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: NeumorphicButton(
                  key: const Key('results_empty_edit_filters'),
                  label: l10n.searchResultsEditFilters,
                  icon: Icons.tune_rounded,
                  onPressed: onEditFilters,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Error state — the failure message + a retry button.
class ResultsError extends StatelessWidget {
  const ResultsError({super.key, required this.error, required this.onRetry});

  /// The thrown error (a [Failure] resolves to a localized message).
  final Object error;

  /// Re-runs the search.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String message = error is Failure
        ? (error as Failure).userMessage(context)
        : l10n.errUnknown;

    return Center(
      key: const Key('results_error'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          padding: const EdgeInsets.all(VelvetSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.cloud_off_rounded,
                size: 48,
                color: BrandColors.muted,
              ),
              const SizedBox(height: VelvetSpacing.md),
              Text(
                message,
                textAlign: TextAlign.center,
                style: VelvetText.body(),
              ),
              const SizedBox(height: VelvetSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: NeumorphicButton(
                  key: const Key('results_error_retry'),
                  label: l10n.retryLabel,
                  icon: Icons.refresh_rounded,
                  onPressed: onRetry,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
