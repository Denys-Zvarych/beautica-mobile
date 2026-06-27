// Phase 13.4 — Master result card.
//
// A neumorphic raised card for one [MasterSearchItem]: 72dp photo thumbnail,
// name, locality (city · district), ★ rating + «(N відгуків)», «від N грн», and
// a favourite heart. Tapping the card opens the public master profile (13.5)
// via go_router (never Navigator).
//
// Procedure-name line: `MasterSearchResult.serviceNames` (≤3 custom-preferred
// names) drives the preview's per-card "Манікюр · Педикюр" services line. When
// the list is empty (master has no active priced services) the line is omitted
// entirely — no placeholder.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
// TODO(13.5): re-import go_router + routing/route_names.dart and restore the
// RouteNames.masterPublicProfile push when /masters/:id is registered.

import '../../../favorites/domain/favorite_target.dart';
import '../../domain/master_search_item.dart';
import 'favorite_heart_button.dart';
import 'result_address_block.dart';
import 'result_card_text.dart';
import 'result_thumbnail.dart';

/// A single master result card.
class MasterResultCard extends StatelessWidget {
  const MasterResultCard({
    super.key,
    required this.master,
    this.onFavoriteError,
  });

  final MasterSearchItem master;

  /// Forwarded to the heart so the host screen can surface a snackbar on a
  /// failed favorite toggle.
  final void Function(Failure failure)? onFavoriteError;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String name = _displayName(master, l10n);
    // The full address renders as two muted lines (see [ResultAddressBlock]):
    //   1. locality = city · district, composed AT RENDER (l10n/presentation);
    //   2. street detail = the auth-gated «street, buildingNo · note» line,
    //      PRECOMPUTED at map time (MasterSearchMapper → addressLine).
    // Anonymous callers have a null street line → only the locality shows. No
    // region/oblast is ever part of either line — the search contract omits it.
    final String? locality = formatLocality(
      master.cityLabel,
      master.districtLabel,
    );
    // Pre-joined at map time (MasterSearchMapper.fromDto): the ≤3 service names
    // as one preview line, or null when the master has none (line omitted — no
    // placeholder). Never join() here — this card builds per row in a scrolling
    // list. When a per-service filter is active the backend sends the MATCHED
    // names (matchedServicesLine) — prefer those so the card surfaces the
    // service(s) that actually matched; else fall back to the generic top-3.
    final String? services = master.matchedServicesLine ?? master.servicesLine;
    final String? priceLabel = _priceLabel(
      l10n,
      master.minEffectivePrice,
      master.priceMax,
    );

    // TODO(13.5): re-enable masterPublicProfile push once /masters/:id route is
    // registered. Until then the card MUST NOT navigate — the route is
    // unregistered and a tap would throw GoException → "Page Not Found". The card
    // is therefore a silent non-button (no onTap, no Semantics(button: true));
    // re-enabling = wrap the NeumorphicCard back in
    //   Semantics(button: true, label: name, child: GestureDetector(
    //     onTap: () => context.push(RouteNames.masterPublicProfile(master.masterId)), ...
    // The favourite heart (FavoriteHeartButton below) stays interactive regardless.
    return Semantics(
      label: name,
      child: NeumorphicCard(
        padding: const EdgeInsets.all(VelvetSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ResultThumbnail(avatarUrl: master.avatarUrl, isSalon: false),
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
                  ResultAddressBlock(
                    locality: locality,
                    streetLine: master.addressLine,
                  ),
                  if (services != null) ...<Widget>[
                    const SizedBox(height: 3),
                    Text(
                      services,
                      key: const Key('master_card_services'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: ResultCardText.services,
                    ),
                  ],
                  const SizedBox(height: VelvetSpacing.sm),
                  _RatingRow(
                    rating: master.avgRating,
                    reviewCount: master.reviewCount,
                  ),
                  if (priceLabel != null) ...<Widget>[
                    const SizedBox(height: 3),
                    Text(priceLabel, style: ResultCardText.price),
                  ],
                ],
              ),
            ),
            FavoriteHeartButton(
              key: Key('favorite_master_${master.masterId}'),
              target: FavoriteTarget(
                type: FavoriteTargetType.master,
                id: master.masterId,
              ),
              semanticAddLabel: l10n.favoriteAddLabel,
              semanticRemoveLabel: l10n.favoriteRemoveLabel,
              onError: onFavoriteError,
            ),
          ],
        ),
      ),
    );
  }

  /// Price rendering — mirrors [SalonResultCard]'s decision-5 logic, using the
  /// master's [MasterSearchItem.minEffectivePrice] as the floor and
  /// [MasterSearchItem.priceMax] as the ceiling:
  ///   floor null            → null (no priced services → hide the line)
  ///   max null / == floor    → exact fixed price «N грн» (NO «від»)
  ///   floor < max           → «N–M грн» range
  static String? _priceLabel(
    AppLocalizations l10n,
    double? floor,
    double? max,
  ) {
    final int? lo = floor?.round();
    final int? hi = max?.round();
    if (lo == null) return null;
    if (hi == null || hi == lo) return l10n.searchResultPriceExact(lo);
    return l10n.searchResultPriceRange(lo, hi);
  }

  /// Builds a display name from first + last, falling back to a placeholder
  /// when the backend omits both.
  static String _displayName(MasterSearchItem m, AppLocalizations l10n) {
    final String name = '${m.firstName} ${m.lastName}'.trim();
    return name.isEmpty ? l10n.searchResultMasterFallbackName : name;
  }
}

/// The ★ rating + «(N відгуків)» row. Hidden entirely when the master has no
/// reviews (rating 0 / null count) — an empty star is misleading.
class _RatingRow extends StatelessWidget {
  const _RatingRow({required this.rating, required this.reviewCount});

  final double? rating;
  final int? reviewCount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final double? r = rating;
    final int count = reviewCount ?? 0;

    // No reviews yet → render a calm "Без відгуків" note instead of ★ 0.0.
    if (r == null || r <= 0 || count <= 0) {
      return Text(l10n.searchResultNoReviews, style: ResultCardText.locality);
    }

    return Row(
      children: <Widget>[
        const Icon(Icons.star_rounded, color: BrandColors.accent, size: 17),
        const SizedBox(width: 3),
        Text(r.toStringAsFixed(1), style: ResultCardText.ratingValue),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            l10n.searchResultReviewCount(count),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ResultCardText.locality,
          ),
        ),
      ],
    );
  }
}
