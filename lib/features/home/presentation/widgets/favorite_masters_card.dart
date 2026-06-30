// Phase 13.7 — Favourite masters card (Step 6).
//
// A horizontal rail of 80dp-wide master mini-cards. Each shows:
//   • gradient avatar with initials (HubPhoto)
//   • name (up to 2 lines so full name+surname shows)
//   • lastServiceName (1 line)
//   • star rating + count
//   • heart-filled badge in top-right → unlike (optimistic DELETE via notifier)
//
// Ported verbatim from `_FavoriteMastersSection` + `_MasterMiniCard` in the
// approved preview. Favorites rail base height was 140dp (preview value),
// raised to 158dp to fit a 2-line name without overflow.
//
// When [masters] is empty, renders the HubEmptyState.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/brand_colors.dart';
import '../../../../core/theme/velvet_geometry.dart';
import '../../../../core/theme/velvet_text.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../routing/route_names.dart';
import '../../../../shared/widgets/rating_star.dart';
import '../../application/home_hub_notifier.dart';
import '../../domain/home_hub_models.dart';
import '../widgets/hub_widgets.dart';

/// Favourite masters section: header + 140dp horizontal rail or empty state.
class FavoriteMastersCard extends ConsumerWidget {
  const FavoriteMastersCard({
    super.key,
    required this.masters,
    required this.totalCount,
  });

  final List<FavoriteMasterItem> masters;
  final int totalCount;

  // Base height: avatar (76) + spacing + last service (1 line) + rating (1 line)
  // + name (now up to 2 lines so full name+surname shows, e.g. "Олександра
  // Зварич"). The +18 over the original 140 absorbs one extra wrapped name line
  // (fontSize 12) so the fixed-height rail never RenderFlex-overflows.
  static const double _railHeight = 158;

  // Overflow-hardening: the avatar is fixed (76dp) but the lines below it (name
  // up to 2 lines, last service, rating) grow with the (clamped) text scale.
  // Add the scaled text headroom on top of the fixed base so the inner Column
  // never overflows at textScale up to 1.3, without redesigning the rail.
  static double _scaledTextHeadroom(BuildContext context) {
    final double scale = MediaQuery.textScalerOf(context).scale(1.0);
    // name (12 ×2 lines) + service (10.5) + rating (13)
    const double textLinesBase = 48;
    return ((scale - 1.0).clamp(0.0, 0.3)) * textLinesBase + 4;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        HubSectionTitle(
          title: l10n.homeHubFavoriteMastersTitle,
          trailing: masters.isEmpty
              ? null
              : HubSeeAllLink(
                  key: const Key('favorite_masters_see_all'),
                  label: l10n.homeHubFavoriteMastersSeeAll(totalCount),
                  onTap: () => context.push('/favorites'),
                ),
        ),
        const SizedBox(height: VelvetSpacing.md),
        if (masters.isEmpty)
          HubFlatCard(
            key: const Key('favorite_masters_empty'),
            padding: const EdgeInsets.symmetric(
              horizontal: VelvetSpacing.md,
              vertical: VelvetSpacing.lg,
            ),
            child: HubEmptyState(
              icon: Icons.favorite_border_rounded,
              message: l10n.homeHubFavoriteMastersEmpty,
            ),
          )
        else
          SizedBox(
            key: const Key('favorite_masters_rail'),
            height: _railHeight + _scaledTextHeadroom(context),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              itemCount: masters.length,
              separatorBuilder: (BuildContext context, int index) =>
                  const SizedBox(width: VelvetSpacing.md - 4),
              itemBuilder: (BuildContext context, int i) => RepaintBoundary(
                child: _MasterMiniCard(
                  master: masters[i],
                  // Phase 13.5 — the /masters/:id public-profile route is now
                  // registered (CLIENT-guarded), so tapping the card opens it.
                  onTap: () => context.push(
                    RouteNames.masterPublicProfile(masters[i].masterId),
                  ),
                  onUnlike: () => ref
                      .read(unlikeFavoriteMasterProvider.notifier)
                      .unlike(masters[i].favoriteId),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MasterMiniCard extends StatelessWidget {
  const _MasterMiniCard({
    required this.master,
    required this.onTap,
    required this.onUnlike,
  });

  final FavoriteMasterItem master;

  /// Opens the master's public profile (Phase 13.5). The unlike heart sits in a
  /// nested [GestureDetector] that wins the gesture arena, so tapping the heart
  /// never also triggers this card-body tap.
  final VoidCallback onTap;
  final VoidCallback onUnlike;

  static final TextStyle _nameStyle = VelvetText.bodyStrong().copyWith(
    fontSize: 12,
  );
  static final TextStyle _serviceStyle = VelvetText.body().copyWith(
    fontSize: 10.5,
  );
  static final TextStyle _ratingStyle = VelvetText.statCaption().copyWith(
    fontSize: 10.5,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Phase 13.5 — the card body is now a button that opens the master's public
    // profile. The unlike heart below stays interactive (its nested
    // GestureDetector wins the arena over this body tap).
    return Semantics(
      key: Key('favorite_master_${master.masterId}'),
      button: true,
      label: master.name,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 80,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  HubPhoto(
                    initials: master.initials,
                    size: 76,
                    radius: 14,
                    fontSize: 20,
                  ),
                  Positioned(
                    right: 5,
                    top: 5,
                    child: Semantics(
                      button: true,
                      label: l10n.homeHubUnlikeMasterLabel,
                      child: GestureDetector(
                        key: Key('unlike_master_${master.masterId}'),
                        onTap: onUnlike,
                        child: Container(
                          height: 22,
                          width: 22,
                          decoration: BoxDecoration(
                            color: BrandColors.white.withValues(alpha: 0.92),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.favorite_rounded,
                            size: 13,
                            color: BrandColors.error,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: VelvetSpacing.xs + 2),
              Text(
                master.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: _nameStyle,
              ),
              const SizedBox(height: 1),
              Text(
                master.lastServiceName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _serviceStyle,
              ),
              const SizedBox(height: 1),
              Row(
                children: <Widget>[
                  RatingStar(rating: master.rating, size: 13, showLabel: false),
                  const SizedBox(width: 2),
                  Flexible(
                    child: Text(
                      '${master.rating.toStringAsFixed(1)} (${master.reviewCount})',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _ratingStyle,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
