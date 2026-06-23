// Phase 13.7 — Quick-links card (Step 4).
//
// A flat card containing 3 quick-links matching the approved design preview:
// search / favorites / bookings.
// Routes: /search, /favorites, /bookings.
//
// The "Мої відгуки" tile was removed in post-13.7 cleanup — the rating stat
// pill (MyRatingStatCard) navigates to /rating instead.
//
// Uses IntrinsicHeight + CrossAxisAlignment.stretch (same fix as stat pills)
// to keep hairline dividers full-height without an infinite-cross-axis.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/icons/app_icon.dart';
import '../../../../core/icons/beautica_asset_icons.dart';
import '../../../../core/theme/brand_colors.dart';
import '../../../../core/theme/velvet_geometry.dart';
import '../../../../core/theme/velvet_text.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../routing/app_router.dart';
import '../../../../routing/route_names.dart';
import '../widgets/hub_widgets.dart';

/// Quick-links row: 3 equally-weighted tiles in a flat card.
class QuickLinksCard extends StatelessWidget {
  const QuickLinksCard({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final links = <_QuickLinkDef>[
      // All three targets are CLIENT shell branches, so each hops its branch
      // (via [branchIndex]) instead of `context.push` — a push would stack the
      // destination on the Home branch and leave the Home nav tile filled.
      _QuickLinkDef(
        key: const Key('quick_link_search'),
        icon: Icons.search_rounded,
        label: l10n.homeHubQuickSearch,
        route: RouteNames.clientSearch,
        branchIndex: kClientSearchBranch,
      ),
      _QuickLinkDef(
        key: const Key('quick_link_favorites'),
        icon: Icons.favorite_border_rounded,
        // Match the bottom nav-bar "Улюблені" tab icon (client_bottom_nav.dart).
        svgIcon: BeauticaAssetIcons.heartOutline,
        label: l10n.homeHubQuickFavorites,
        route: RouteNames.clientFavorites,
        branchIndex: kClientFavoritesBranch,
      ),
      _QuickLinkDef(
        key: const Key('quick_link_bookings'),
        icon: Icons.event_note_outlined,
        // Match the bottom nav-bar "Записи" tab icon (client_bottom_nav.dart).
        svgIcon: BeauticaAssetIcons.noteOutline,
        label: l10n.homeHubQuickBookings,
        route: RouteNames.clientBookings,
        branchIndex: kClientBookingsBranch,
      ),
    ];

    return HubFlatCard(
      radius: 16,
      padding: const EdgeInsets.symmetric(
        horizontal: VelvetSpacing.xs,
        vertical: VelvetSpacing.sm + 2,
      ),
      // CRITICAL: IntrinsicHeight wraps the stretch Row so the cross-axis is
      // bounded. A bare stretch Row in a ListView main-axis child has an
      // infinite cross extent which silently produces an unpaintable sliver
      // geometry on Flutter web (blanks the whole list).
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (int i = 0; i < links.length; i++) ...<Widget>[
              if (i > 0) const _QuickDivider(),
              Expanded(child: _QuickTile(def: links[i])),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuickLinkDef {
  const _QuickLinkDef({
    required this.key,
    required this.icon,
    required this.label,
    required this.route,
    this.svgIcon,
    this.branchIndex,
  });

  final Key key;
  final IconData icon;

  /// Optional SVG asset path (from [BeauticaAssetIcons]) rendered via [AppIcon]
  /// in place of [icon]. When null the tile falls back to the Material [icon].
  /// Used by the bookings tile so it matches the nav bar's "Записи" SVG.
  final String? svgIcon;
  final String label;
  final String route;

  /// The CLIENT shell branch index this tile targets, or `null` when [route] is
  /// NOT a shell branch (in which case the tile uses `context.push`). When
  /// non-null the tile hops the branch via `StatefulNavigationShell.goBranch`
  /// so the page and the bottom-nav selection stay in sync.
  final int? branchIndex;
}

/// Thin vertical hairline separating quick-link items.
class _QuickDivider extends StatelessWidget {
  const _QuickDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: BrandColors.faint.withValues(alpha: 0.4),
    );
  }
}

class _QuickTile extends StatefulWidget {
  const _QuickTile({required this.def});

  final _QuickLinkDef def;

  @override
  State<_QuickTile> createState() => _QuickTileState();
}

class _QuickTileState extends State<_QuickTile> {
  bool _pressed = false;

  static final TextStyle _labelStyle = VelvetText.body().copyWith(
    fontSize: 10.5,
    height: 1.15,
    color: BrandColors.textSecondary,
  );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.def.label.replaceAll('\n', ' '),
      child: GestureDetector(
        key: widget.def.key,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          final int? branchIndex = widget.def.branchIndex;
          if (branchIndex != null) {
            // Shell-branch target: hop the branch so the bottom-nav selection
            // follows the page (a plain push would keep the Home tile filled).
            StatefulNavigationShell.of(context).goBranch(branchIndex);
          } else {
            // Non-shell route: a normal push is correct.
            context.push(widget.def.route);
          }
        },
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _pressed ? 0.94 : 1,
          duration: const Duration(milliseconds: 110),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (widget.def.svgIcon case final String svgIcon)
                AppIcon(svgIcon, color: BrandColors.accentDeep, size: 21)
              else
                Icon(widget.def.icon, color: BrandColors.accentDeep, size: 21),
              const SizedBox(height: VelvetSpacing.xs + 1),
              Text(
                widget.def.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: _labelStyle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
