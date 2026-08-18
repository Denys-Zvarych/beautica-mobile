// Phases 238 + 239 — the wish list's three non-happy states.
//
// Empty, error and loading, in ONE silhouette: a full-width [HubFlatCard] with
// the same padding, so the section's non-happy paths read as one family rather
// than three foreign widgets taking turns in the same slot. Both surfaces use
// these — the passport page's section and the full-list page — so «Не вдалося
// завантажити улюблені послуги» cannot end up worded or shaped two ways.
//
// The empty and error states are transcribed from the approved preview
// (`passport_screen.dart`'s `_WishlistEmpty` / `_WishlistError`). The LOADING
// state is not in the preview: a mockup has nothing to wait for. It is filled
// in here in the preview's own language rather than invented in a new one —
// see [WishlistLoadingState].
//
// ## Empty and error are NOT interchangeable
//
// An empty wish list is an invitation: it says where the heart lives and what
// happens when it is tapped. A failed fetch is a fault the client can act on by
// retrying. Rendering the former for the latter is the defect class that let
// the always-empty passport bug hide for a whole phase — a 401 was
// pixel-identical to "nothing saved yet". They are separately test-pinned.

import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/brand_colors.dart';
import '../../../../core/theme/velvet_geometry.dart';
import '../../../../core/theme/velvet_text.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../home/presentation/widgets/hub_widgets.dart';

/// The padding every wish-list state card shares. Wider vertically than
/// horizontally because these cards are mostly centred air around one glyph.
const EdgeInsets _kStatePadding = EdgeInsets.symmetric(
  horizontal: VelvetSpacing.md,
  vertical: VelvetSpacing.lg,
);

/// The glyph well the empty and error states share — 52 dp holder, 24 dp glyph,
/// matching `HubEmptyState`'s own hardcoded geometry so the two sit as siblings.
const double _kWell = 52;
const double _kWellGlyph = 24;

/// Nothing hearted yet.
///
/// An empty screen is an invitation to act, so this names exactly where the
/// heart lives and what happens when it is tapped, then offers the one step
/// that gets the client there.
class WishlistEmptyState extends StatelessWidget {
  const WishlistEmptyState({super.key, required this.onFindMaster});

  /// Sends the client to discovery.
  final VoidCallback onFindMaster;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return SizedBox(
      width: double.infinity,
      child: HubFlatCard(
        key: const Key('wishlist_empty_state'),
        padding: _kStatePadding,
        child: HubEmptyState(
          icon: Icons.favorite_border_rounded,
          message: l10n.wishlistEmptyMessage,
          ctaLabel: l10n.wishlistEmptyCta,
          onCta: onFindMaster,
        ),
      ),
    );
  }
}

/// The wish list failed to load.
///
/// Keeps the app's existing failure language verbatim — the `cloud_off` glyph,
/// «Перевір з'єднання та спробуй ще раз.» and the `retryLabel` CTA — inside the
/// section's own card silhouette, so it sits beside its sibling empty state
/// instead of inventing a second failure look.
class WishlistErrorState extends StatelessWidget {
  const WishlistErrorState({super.key, required this.onRetry});

  final VoidCallback onRetry;

  static final BoxDecoration _wellDecoration = BoxDecoration(
    color: BrandColors.white.withValues(alpha: 0.5),
    shape: BoxShape.circle,
    border: Border.all(color: BrandColors.faint.withValues(alpha: 0.5)),
  );

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return SizedBox(
      width: double.infinity,
      child: HubFlatCard(
        key: const Key('wishlist_error_state'),
        padding: _kStatePadding,
        child: Column(
          children: <Widget>[
            Container(
              height: _kWell,
              width: _kWell,
              decoration: _wellDecoration,
              child: const Icon(
                Icons.cloud_off_rounded,
                size: _kWellGlyph,
                color: BrandColors.faint,
              ),
            ),
            const SizedBox(height: VelvetSpacing.md),
            Text(
              l10n.wishlistErrorTitle,
              textAlign: TextAlign.center,
              style: VelvetText.subheading(),
            ),
            const SizedBox(height: VelvetSpacing.xs),
            Text(
              l10n.wishlistErrorBody,
              textAlign: TextAlign.center,
              style: VelvetText.body14,
            ),
            const SizedBox(height: VelvetSpacing.md),
            HubFilledButton(
              key: const Key('wishlist_retry_button'),
              label: l10n.retryLabel,
              onTap: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}

/// The first load, before anything is known.
///
/// NOT in the approved preview — a mockup has nothing to wait for — so it is
/// filled in here in the preview's own language rather than a new one: the same
/// [HubFlatCard] silhouette and the same padding as its two siblings, holding
/// muted bars at the `faint@0.3` weight every other skeleton in this app uses
/// (`passport_screen.dart`'s profile skeleton, the hero skeleton).
///
/// Deliberately NOT a spinner and NOT a pair of ghost cards. A spinner in a
/// section slot reads as "something is stuck"; ghost cards would promise a
/// two-card line that an empty or failed response is about to contradict. Three
/// quiet bars promise only that something is coming.
class WishlistLoadingState extends StatelessWidget {
  const WishlistLoadingState({super.key});

  static const double _kBarHeight = 14;
  static const double _kBarGap = AppSpacing.sm;

  /// The three bars' widths as a fraction of the card, stepping down so the
  /// block reads as text rather than as a table.
  static const List<double> _kBarWidths = <double>[1, 0.72, 0.45];

  static final BoxDecoration _barDecoration = BoxDecoration(
    color: BrandColors.faint.withValues(alpha: 0.3),
    borderRadius: BorderRadius.circular(AppSpacing.xs),
  );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: HubFlatCard(
        key: const Key('wishlist_loading_state'),
        padding: _kStatePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (int i = 0; i < _kBarWidths.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(height: _kBarGap),
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: _kBarWidths[i],
                child: Container(
                  height: _kBarHeight,
                  decoration: _barDecoration,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
