// Phase 13.4 — Master result card.
//
// A neumorphic raised card for one [MasterSearchItem]: 72dp photo thumbnail,
// name, locality (city · district), ★ rating + «(N відгуків)», «від N ₴», and
// a favourite heart. Tapping the card opens the public master profile (13.5)
// via go_router (never Navigator).
//
// Procedure-name line: `MasterSearchResult.serviceNames` (≤3 custom-preferred
// names) drives the preview's per-card "Манікюр · Педикюр" services line. When
// the list is empty (master has no active priced services) the line is omitted
// entirely — no placeholder.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/booking_price_labels.dart';

import '../../../booking/application/pending_service_preselection_provider.dart';
import '../../../favorites/domain/favorite_target.dart';
import '../../domain/master_search_item.dart';
import '../../domain/search_filters.dart';
import 'favorite_heart_overlay.dart';
import 'result_address_block.dart';
import 'result_card_text.dart';
import 'result_thumbnail.dart';
import 'search_preselection.dart';

/// A single master result card.
class MasterResultCard extends ConsumerWidget {
  const MasterResultCard({
    super.key,
    required this.master,
    this.activeFilters,
    this.onFavoriteError,
  });

  final MasterSearchItem master;

  /// The filter set the results list was fetched with. When it carries an
  /// active service filter ([SearchFilters.serviceTypeSlugs] non-empty), the
  /// matching service(s) are handed to the booking flow so they arrive
  /// pre-checked. Null (or no service filter) → nothing is pre-selected.
  final SearchFilters? activeFilters;

  /// Forwarded to the heart so the host screen can surface a snackbar on a
  /// failed favorite toggle.
  final void Function(Failure failure)? onFavoriteError;

  /// Records the search service pre-selection for this master (if a service
  /// filter is active) so the booking Step 1 catalogue starts with those
  /// service(s) pre-checked, then navigates to the public master profile.
  void _openProfile(WidgetRef ref) {
    final SearchFilters? filters = activeFilters;
    if (filters != null && filters.serviceTypeSlugs.isNotEmpty) {
      ref
          .read(pendingServicePreselectionControllerProvider.notifier)
          .set(
            targetId: master.masterId,
            serviceTypeSlugs: filters.serviceTypeSlugs,
            serviceTypeLabels: resolveServiceTypeLabels(ref, filters),
          );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

    // Phase 13.5 — the card navigates to the public master profile. The
    // `/masters/:id` route is registered (CLIENT-guarded) so the tap is safe.
    // The favourite heart is rendered by [FavoriteHeartOverlay] (below)
    // rather than inline in the `Row` — a genuine 48×48 tap target inline
    // would eat into the `Expanded` name/meta column dp-for-dp, since the
    // heart is the Row's last child. The `Row` keeps only an inert
    // placeholder sized to the heart's OLD inline footprint
    // (`FavoriteHeartOverlay.slotWidth`) so that column's width is
    // unaffected; the overlay renders the real, tappable heart on top,
    // spilling into the card's own padding instead. See
    // `favorite_heart_overlay.dart`'s file header for the full contract —
    // same fix `CatalogueServiceTile` (`service_catalogue_accordion.dart`)
    // uses.
    //
    // The `Semantics` annotation lives HERE, wrapping the card's own
    // `GestureDetector`, and NOT around the `FavoriteHeartOverlay` below.
    // Above the overlay it would take this gesture and the heart's into one
    // merge group, which Flutter resolves by refusing to merge either —
    // leaving this annotation with `isButton` but no `tap` action, and the
    // node that IS tappable with no role. See
    // `favorite_heart_overlay.dart`'s "SEMANTICS CONTRACT" header section.
    //
    // It carries `button: true` and NOTHING ELSE — deliberately no
    // `label: name`. The merged descendants already announce the name once
    // (the name `Text` is the first child of the column below), so an
    // explicit label here is announced a SECOND time: «Олена Коваль, Олена
    // Коваль, Печерський, Київ, …». That stutter is PRE-EXISTING, not
    // something this change armed: re-dumping the semantics tree from this
    // file at `HEAD` shows the committed tree ALREADY merged and ALREADY
    // stuttered on a node that ALREADY carried `actions: tap` + `isButton`.
    // (An earlier revision of this note claimed the heart's gesture had
    // suppressed the merge on `main`, leaving the duplicate dormant — that
    // was measured on this change's intermediate draft, where the annotation
    // sat ABOVE the overlay, and is false of `main`.) Let the content supply
    // the label — the standard Flutter pattern. Guarded by
    // `master_result_card_test.dart`'s single-occurrence assertion.
    final Widget cardBody = Semantics(
      button: true,
      child: GestureDetector(
        onTap: () {
          _openProfile(ref);
          context.push(RouteNames.masterPublicProfile(master.masterId));
        },
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
                      // Keyed so a test can measure the name column's
                      // laid-out width without locating it by its (fixture)
                      // text — see `master_result_card_favorite_heart_
                      // tap_target_test.dart`'s "name column is unchanged"
                      // group, which pins that width against the heart
                      // overlay's reserved slot.
                      key: const Key('master_card_name'),
                      maxLines: 2,
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
              // Inert placeholder — reserves the heart's OLD inline footprint
              // so the `Expanded` column above is unaffected. The real,
              // tappable heart is the `FavoriteHeartOverlay` below, NOT this
              // box (it paints nothing and has no gesture).
              const SizedBox(width: FavoriteHeartOverlay.slotWidth),
            ],
          ),
        ),
      ),
    );

    // BARE — no outer `Semantics`. `cardBody` already carries it (above).
    return FavoriteHeartOverlay(
      body: cardBody,
      containerPad: VelvetSpacing.md,
      heartKey: Key('favorite_master_${master.masterId}'),
      target: FavoriteTarget(
        type: FavoriteTargetType.master,
        id: master.masterId,
      ),
      semanticAddLabel: l10n.favoriteAddLabel,
      semanticRemoveLabel: l10n.favoriteRemoveLabel,
      onError: onFavoriteError,
    );
  }

  /// Price rendering — mirrors [SalonResultCard]'s decision-5 logic, using the
  /// master's [MasterSearchItem.minEffectivePrice] as the floor and
  /// [MasterSearchItem.priceMax] as the ceiling:
  ///   floor null            → null (no priced services → hide the line)
  ///   max null / == floor    → exact fixed price «N ₴» (NO «від»)
  ///   floor < max           → «N–M ₴» range
  ///
  /// Both bounds arrive off the wire as unclamped doubles (`search_mapper.dart`
  /// passes the decoded values straight through) and the ARB placeholders here
  /// are `"type": "int"`, so each is coerced through [renderableWholePrice]
  /// rather than a bare `.round()` — see that function for why the bare call
  /// THROWS out of this `build()` on `Infinity`/`NaN` and saturates to
  /// «9223372036854775807 ₴» on a merely-large figure.
  ///
  /// An unrenderable bound is treated as ABSENT, which needs no new branch: an
  /// unrenderable ceiling lands in the `max null` case above (the exact price
  /// the card already renders correctly), and an unrenderable floor lands in
  /// the `floor null` case — the price line is omitted entirely, exactly as for
  /// a master with no priced services. Deliberately NOT [priceUnavailableLabel]:
  /// this card has an established, honest "no price known" state and shows no
  /// «—» anywhere else.
  static String? _priceLabel(
    AppLocalizations l10n,
    double? floor,
    double? max,
  ) {
    final int? lo = renderableWholePrice(floor);
    final int? hi = renderableWholePrice(max);
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
