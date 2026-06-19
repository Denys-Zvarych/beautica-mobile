// Phase 13.7 — Quick-links card (Step 4).
//
// A flat card containing 3 quick-links (matching the preview which shows 3 —
// search / favorites / bookings). The phase spec mentions a 4th "feedbacks"
// link; however the preview only renders 3. We add feedbacks as the 4th tile.
// Routes: /search, /favorites, /bookings, /reviews/me.
//
// Uses IntrinsicHeight + CrossAxisAlignment.stretch (same fix as stat pills)
// to keep hairline dividers full-height without an infinite-cross-axis.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/brand_colors.dart';
import '../../../../core/theme/velvet_geometry.dart';
import '../../../../core/theme/velvet_text.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../routing/route_names.dart';
import '../widgets/hub_widgets.dart';

/// Quick-links row: 4 equally-weighted tiles in a flat card.
class QuickLinksCard extends StatelessWidget {
  const QuickLinksCard({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final links = <_QuickLinkDef>[
      _QuickLinkDef(
        key: const Key('quick_link_search'),
        icon: Icons.search_rounded,
        label: l10n.homeHubQuickSearch,
        route: RouteNames.clientSearch,
      ),
      _QuickLinkDef(
        key: const Key('quick_link_favorites'),
        icon: Icons.favorite_border_rounded,
        label: l10n.homeHubQuickFavorites,
        route: RouteNames.clientFavorites,
      ),
      _QuickLinkDef(
        key: const Key('quick_link_bookings'),
        icon: Icons.event_note_outlined,
        label: l10n.homeHubQuickBookings,
        route: RouteNames.clientBookings,
      ),
      _QuickLinkDef(
        key: const Key('quick_link_reviews'),
        icon: Icons.rate_review_outlined,
        label: l10n.homeHubQuickReviews,
        // /reviews/me route — registered in Phase 13.7 Step 8
        route: RouteNames.myReviews,
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
  });

  final Key key;
  final IconData icon;
  final String label;
  final String route;
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
          context.push(widget.def.route);
        },
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _pressed ? 0.94 : 1,
          duration: const Duration(milliseconds: 110),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
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
