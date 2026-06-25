// Phase 13.4 — Salon result card.
//
// A neumorphic raised card for one [SalonSearchItem]: 72dp logo thumbnail, name,
// locality, price range, and a favourite heart (SALON target). Tapping opens the
// public salon profile (13.6) via go_router.
//
// CONTRACT GAPS (intentional):
//   • `SalonSearchResult` carries NO avgRating field → the ★ rating row is
//     OMITTED entirely (never invent a value).
//   • Price range follows decision 5: render `priceMin`–`priceMax`; collapse to
//     a single «від N грн» when the two are equal; hide the price line when both
//     are null.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';

import '../../../favorites/domain/favorite_target.dart';
import '../../domain/salon_search_item.dart';
import 'favorite_heart_button.dart';
import 'result_card_text.dart';
import 'result_thumbnail.dart';

/// A single salon result card.
class SalonResultCard extends StatelessWidget {
  const SalonResultCard({super.key, required this.salon, this.onFavoriteError});

  final SalonSearchItem salon;

  final void Function(Failure failure)? onFavoriteError;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String name = salon.name.isEmpty
        ? l10n.searchResultSalonFallbackName
        : salon.name;
    // Pre-joined at map time (SalonSearchMapper.fromDto): the (auth-gated)
    // «street, buildingNo» line when present, otherwise fall back to the
    // city/district locality line at render.
    final String? locality =
        salon.addressLine ??
        formatLocality(salon.cityLabel, salon.districtLabel);
    final String? services = salon.servicesLine;
    final String? price = _priceLabel(l10n, salon.priceMin, salon.priceMax);

    return Semantics(
      button: true,
      label: name,
      child: GestureDetector(
        onTap: () => context.push(RouteNames.salonPublicProfile(salon.salonId)),
        behavior: HitTestBehavior.opaque,
        child: NeumorphicCard(
          padding: const EdgeInsets.all(VelvetSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ResultThumbnail(avatarUrl: salon.avatarUrl, isSalon: true),
              const SizedBox(width: VelvetSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: VelvetText.subheading(),
                    ),
                    if (locality != null) ...<Widget>[
                      const SizedBox(height: 3),
                      Text(
                        locality,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ResultCardText.locality,
                      ),
                    ],
                    if (services != null) ...<Widget>[
                      const SizedBox(height: 3),
                      Text(
                        services,
                        key: const Key('salon_card_services'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: ResultCardText.services,
                      ),
                    ],
                    if (price != null) ...<Widget>[
                      const SizedBox(height: VelvetSpacing.sm),
                      Text(price, style: ResultCardText.price),
                    ],
                  ],
                ),
              ),
              FavoriteHeartButton(
                key: Key('favorite_salon_${salon.salonId}'),
                target: FavoriteTarget(
                  type: FavoriteTargetType.salon,
                  id: salon.salonId,
                ),
                semanticAddLabel: l10n.favoriteAddLabel,
                semanticRemoveLabel: l10n.favoriteRemoveLabel,
                onError: onFavoriteError,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Decision 5 price rendering. The «від» prefix shows ONLY when the two
  /// bounds differ; an equal (or single) bound renders one fixed price with no
  /// «від»:
  ///   both null      → null (hide the line)
  ///   equal bounds   → exact fixed price «N грн» (NO «від»)
  ///   one bound only → «від N грн» (open-ended on the other side)
  ///   min < max      → «N–M грн» range
  static String? _priceLabel(AppLocalizations l10n, double? min, double? max) {
    final int? lo = min?.round();
    final int? hi = max?.round();
    if (lo == null && hi == null) return null;
    // Only one bound known → genuinely open-ended → keep the «від» prefix.
    if (lo == null) return l10n.searchPriceFrom(hi!);
    if (hi == null) return l10n.searchPriceFrom(lo);
    // Both known: equal ⇒ single fixed price (no «від»); else a range.
    if (hi == lo) return l10n.searchResultPriceExact(lo);
    return l10n.searchResultPriceRange(lo, hi);
  }
}
