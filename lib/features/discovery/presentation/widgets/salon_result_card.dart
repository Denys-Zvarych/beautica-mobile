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
//     a single exact «N ₴» (no prefix) when the two are equal; render the
//     open end of the surviving DIRECTION when only one bound is known
//     («від N ₴» for a floor, «до N ₴» for a ceiling — never substituted for
//     each other); hide the price line when both are null.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/booking_price_labels.dart';

import '../../../booking/application/pending_service_preselection_provider.dart';
import '../../../favorites/domain/favorite_target.dart';
import '../../domain/salon_search_item.dart';
import '../../domain/search_filters.dart';
import 'favorite_heart_overlay.dart';
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
    // public salon profile. The favourite heart is rendered by
    // [FavoriteHeartOverlay] (below) rather than inline in the `Row` — a
    // genuine 48×48 tap target inline would eat into the `Expanded` name/
    // meta column dp-for-dp, since the heart is the Row's last child. The
    // `Row` keeps only an inert placeholder sized to the heart's OLD inline
    // footprint (`FavoriteHeartOverlay.slotWidth`) so that column's width is
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
    // explicit label here is announced a SECOND time: «Beauty Studio, Beauty
    // Studio, Галицький, Львів, …». That stutter is PRE-EXISTING, not
    // something this change armed: re-dumping the semantics tree from this
    // file at `HEAD` shows the committed tree ALREADY merged and ALREADY
    // stuttered on a node that ALREADY carried `actions: tap` + `isButton`.
    // (An earlier revision of this note claimed the heart's gesture had
    // suppressed the merge on `main`, leaving the duplicate dormant — that
    // was measured on this change's intermediate draft, where the annotation
    // sat ABOVE the overlay, and is false of `main`.) Let the content supply
    // the label — the standard Flutter pattern. Guarded by
    // `salon_result_card_test.dart`'s single-occurrence assertion.
    final Widget cardBody = Semantics(
      button: true,
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
                      // Keyed so a test can measure the name column's
                      // laid-out width without locating it by its (fixture)
                      // text — see `salon_result_card_favorite_heart_
                      // tap_target_test.dart`'s "name column is unchanged"
                      // group, which pins that width against the heart
                      // overlay's reserved slot.
                      key: const Key('salon_card_name'),
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
      heartKey: Key('favorite_salon_${salon.salonId}'),
      target: FavoriteTarget(type: FavoriteTargetType.salon, id: salon.salonId),
      semanticAddLabel: l10n.favoriteAddLabel,
      semanticRemoveLabel: l10n.favoriteRemoveLabel,
      onError: onFavoriteError,
    );
  }

  /// Decision 5 price rendering. An open-ended prefix shows ONLY when the two
  /// bounds differ; an equal (or single) bound renders one fixed price with no
  /// prefix:
  ///   both null      → null (hide the line)
  ///   equal bounds   → exact fixed price «N ₴» (NO prefix)
  ///   floor only     → «від N ₴» (open-ended ABOVE the known floor)
  ///   ceiling only   → «до N ₴»  (open-ended BELOW the known ceiling)
  ///   min < max      → «N–M ₴» range
  ///
  /// The two single-bound directions are NOT interchangeable, and picking the
  /// wrong one is a false claim rather than a cosmetic slip. «від N ₴» asserts
  /// N is the salon's CHEAPEST service; «до N ₴» asserts N is its dearest. A
  /// missing floor with a known ceiling must therefore render «до», never
  /// «від» — the latter would quote the ceiling as the minimum, inflating the
  /// advertised entry price (a salon with `priceMax` 800 would read «від
  /// 800 ₴»). Each label states only the bound it actually has.
  ///
  /// Both bounds arrive off the wire as unclamped doubles (`search_mapper.dart`
  /// passes the decoded values straight through) and the ARB placeholders here
  /// are `"type": "int"`, so each is coerced through [renderableWholePrice]
  /// rather than a bare `.round()` — see that function for why the bare call
  /// THROWS out of this `build()` on `Infinity`/`NaN` and saturates to
  /// «9223372036854775807 ₴» on a merely-large figure.
  ///
  /// An unrenderable bound is treated as ABSENT, which needs no new branch —
  /// "this bound is not known" is already first-class here: one unrenderable
  /// bound leaves the open-ended label of the DIRECTION that survived, and two
  /// land in the `both null` case that omits the price line entirely.
  /// Deliberately NOT [priceUnavailableLabel]: this card has an established,
  /// honest "no price known" state and shows no «—» anywhere else.
  static String? _priceLabel(AppLocalizations l10n, double? min, double? max) {
    final int? lo = renderableWholePrice(min);
    final int? hi = renderableWholePrice(max);
    // Only one bound known → genuinely open-ended → prefix it in the direction
    // that bound actually constrains. Never substitute the other bound: a
    // ceiling quoted as «від» would state an inflated, false minimum.
    if (lo == null) return hi == null ? null : l10n.searchPriceUpTo(hi);
    if (hi == null) return l10n.searchPriceFrom(lo);
    // Both known: equal ⇒ single fixed price (no «від»); else a range.
    if (hi == lo) return l10n.searchResultPriceExact(lo);
    return l10n.searchResultPriceRange(lo, hi);
  }
}
