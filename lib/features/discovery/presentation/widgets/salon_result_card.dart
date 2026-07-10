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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';

import '../../../booking/application/pending_service_preselection_provider.dart';
import '../../../favorites/domain/favorite_target.dart';
import '../../domain/salon_search_item.dart';
import '../../domain/search_filters.dart';
import 'favorite_heart_button.dart';
import 'result_address_block.dart';
import 'result_card_text.dart';
import 'result_thumbnail.dart';
import 'search_preselection.dart';

/// A single salon result card.
class SalonResultCard extends ConsumerWidget {
  const SalonResultCard({
    super.key,
    required this.salon,
    this.activeFilters,
    this.onFavoriteError,
  });

  final SalonSearchItem salon;

  /// The filter set the results list was fetched with. When it carries an
  /// active service filter ([SearchFilters.serviceTypeSlugs] non-empty), the
  /// matching service(s) are handed to the salon booking flow so they arrive
  /// pre-checked. Null (or no service filter) → nothing is pre-selected.
  final SearchFilters? activeFilters;

  final void Function(Failure failure)? onFavoriteError;

  /// Records the search service pre-selection for this salon (if a service
  /// filter is active) so the salon booking Step 1 catalogue starts with those
  /// service(s) pre-checked, then navigates to the public salon profile.
  void _openProfile(WidgetRef ref) {
    final SearchFilters? filters = activeFilters;
    if (filters != null && filters.serviceTypeSlugs.isNotEmpty) {
      ref
          .read(pendingServicePreselectionControllerProvider.notifier)
          .set(
            targetId: salon.salonId,
            serviceTypeSlugs: filters.serviceTypeSlugs,
            serviceTypeLabels: resolveServiceTypeLabels(ref, filters),
          );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final String name = salon.name.isEmpty
        ? l10n.searchResultSalonFallbackName
        : salon.name;
    // The full address renders as two muted lines (see [ResultAddressBlock]):
    //   1. locality = city · district, composed AT RENDER (l10n/presentation);
    //   2. street detail = the auth-gated «street, buildingNo · note» line,
    //      PRECOMPUTED at map time (SalonSearchMapper → addressLine).
    // Anonymous callers have a null street line → only the locality shows. No
    // region/oblast is ever part of either line — the search contract omits it.
    final String? locality = formatLocality(
      salon.cityLabel,
      salon.districtLabel,
    );
    // When a per-service filter is active the backend sends the MATCHED names
    // (matchedServicesLine) — prefer those so the card surfaces the service(s)
    // that actually matched; else fall back to the generic top-3.
    final String? services = salon.matchedServicesLine ?? salon.servicesLine;
    final String? price = _priceLabel(l10n, salon.priceMin, salon.priceMax);

    // Phase 13.6: /salons/:id is now registered — the card navigates to the
    // public salon profile. The favourite heart (FavoriteHeartButton below)
    // has its own independent tap target, so the outer GestureDetector must
    // not swallow it — HitTestBehavior.opaque on the outer Semantics/tap
    // target is unnecessary here since NeumorphicCard already fills the row.
    return Semantics(
      button: true,
      label: name,
      child: GestureDetector(
        key: Key('salon_card_${salon.salonId}'),
        onTap: () {
          _openProfile(ref);
          context.push(RouteNames.salonPublicProfile(salon.salonId));
        },
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
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: VelvetText.subheading(),
                    ),
                    ResultAddressBlock(
                      locality: locality,
                      streetLine: salon.addressLine,
                    ),
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
