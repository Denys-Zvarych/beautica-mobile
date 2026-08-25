// Phase 111 (old 13.10) — the two «Улюблені» empty states.
//
// Ported from `docs/signup-designs/ClientFavorites/lib/widgets/
// favorites_empty_state.dart`. Two of them, because the two situations need
// different directions:
//
//   * **Nothing saved yet** — explain what this tab collects, then send the
//     client to search. The list is genuinely empty and search is the only way
//     to fill it.
//   * **Nothing in this category** — the LIST is not empty, the FILTER is. The
//     fix is one tap, so offer that instead of search: sending someone to
//     search when they already have favourites two taps away is the wrong
//     direction.
//
// The glyph is a recessed disc — an empty place in the surface, drawn from the
// same inset language the removed-row dent uses, so "nothing here" is stated in
// the design system's own vocabulary rather than with an illustration.
//
// NOT `shared/widgets/error_state.dart` or `LoadingSkeleton`: those render a
// FAILURE and a WAIT. An empty favourites list is neither — it is a correct,
// successful answer, and dressing it in error chrome would tell the client
// something went wrong when nothing did.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

/// «Ще немає улюблених» — nothing saved at all, with a CTA into «Пошук».
class FavoritesEmptyState extends StatelessWidget {
  const FavoritesEmptyState({super.key, required this.onFindMaster});

  final VoidCallback onFindMaster;

  /// Width of the CTA — narrower than the column so the button reads as one
  /// offered action rather than as a page-wide primary commitment.
  static const double _ctaWidth = 220;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return _EmptyFrame(
      key: const Key('favorites-empty-state'),
      icon: Icons.favorite_border_rounded,
      title: l10n.favoritesEmptyTitle,
      body: l10n.favoritesEmptyBody,
      action: SizedBox(
        width: _ctaWidth,
        child: NeumorphicButton(
          key: const Key('favorites-find-master-button'),
          label: l10n.favoritesEmptyCta,
          icon: Icons.search_rounded,
          onPressed: onFindMaster,
        ),
      ),
    );
  }
}

/// «У категорії «X» порожньо» — the filter, not the list, is empty.
class FavoritesCategoryEmptyState extends StatelessWidget {
  const FavoritesCategoryEmptyState({
    super.key,
    required this.categoryLabel,
    required this.onClearFilter,
  });

  final String categoryLabel;
  final VoidCallback onClearFilter;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return _EmptyFrame(
      key: const Key('favorites-category-empty-state'),
      icon: Icons.filter_alt_off_rounded,
      title: l10n.favoritesCategoryEmptyTitle(categoryLabel),
      body: l10n.favoritesCategoryEmptyBody,
      action: Semantics(
        button: true,
        label: l10n.favoritesShowAllLabel,
        child: GestureDetector(
          key: const Key('favorites-show-all-button'),
          behavior: HitTestBehavior.opaque,
          onTap: onClearFilter,
          child: Padding(
            padding: const EdgeInsets.all(VelvetSpacing.sm),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.grid_view_rounded,
                  size: 17,
                  color: BrandColors.accentDeep,
                ),
                const SizedBox(width: VelvetSpacing.sm - 2),
                Text(l10n.favoritesShowAll, style: VelvetText.link()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared frame: recessed glyph disc, title, body, one action.
class _EmptyFrame extends StatelessWidget {
  const _EmptyFrame({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget action;

  /// Diameter of the recessed glyph disc; its radius is exactly half, so the
  /// inset painter draws a true circle rather than a squircle.
  static const double _glyphDisc = 108;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: VelvetSpacing.lg,
        vertical: VelvetSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            height: _glyphDisc,
            width: _glyphDisc,
            child: NeumorphicInset(
              radius: _glyphDisc / 2,
              child: Center(
                child: Icon(icon, size: 40, color: BrandColors.accent),
              ),
            ),
          ),
          const SizedBox(height: VelvetSpacing.lg + 2),
          Text(title, textAlign: TextAlign.center, style: VelvetText.headingSm),
          const SizedBox(height: VelvetSpacing.sm + 2),
          Text(body, textAlign: TextAlign.center, style: VelvetText.body()),
          const SizedBox(height: VelvetSpacing.lg + 2),
          action,
        ],
      ),
    );
  }
}
