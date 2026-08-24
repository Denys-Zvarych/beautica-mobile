// Phase 13.4 — Hoisted text styles + helpers shared by the result cards.
//
// All TextStyles are computed once at class-load (perf house-rule: never
// allocate a TextStyle per build inside a scrolling list).

import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:flutter/widgets.dart';

// The service-names separator now lives in the (pure-Dart) domain layer so the
// data-layer mapper can pre-join the preview line without importing
// `presentation/`. Re-exported here to keep existing presentation/test call
// sites (`kServiceNamesSeparator`) working unchanged.
export '../../domain/master_search_item.dart' show kServiceNamesSeparator;

/// Pre-composed card text styles (master + salon cards).
abstract final class ResultCardText {
  /// Locality / muted secondary line (12.5sp muted).
  static final TextStyle locality = VelvetText.discLocality;

  /// The auth-gated street-detail line under the locality (street, building,
  /// note). A hair smaller than [locality] so the city reads first and the
  /// precise street reads as supporting detail — same muted tone, no new color.
  static final TextStyle addressDetail = VelvetText.discCaptionMuted;

  /// The provider's free-text arrival note — the third, wrapping row of
  /// [ResultAddressBlock] (Phase 111, «Улюблені» only). Quieter than
  /// [addressDetail] and on a looser line-height, so a sentence reads as prose
  /// rather than as another form field.
  static final TextStyle addressNote = VelvetText.discAddressNote;

  /// Bold numeric rating value (13sp).
  static final TextStyle ratingValue = VelvetText.discRatingValue;

  /// «від N ₴» / price-range accent line (14sp accentDeep).
  static final TextStyle price = VelvetText.discPriceAccent;

  /// Procedure / service-names preview line on the master card (e.g.
  /// «Манікюр · Педикюр»). A touch smaller than the name, in the secondary tone
  /// so it reads as supporting detail rather than competing with the name.
  static final TextStyle services = VelvetText.discServicesPreview;
}

// NOTE (2026-06-25): the former `formatAddress(street, buildingNo)` helper was
// removed. The «street, buildingNo» line is now PRECOMPUTED ONCE at map time in
// `SearchMapper` (`MasterSearchItem.addressLine` / `SalonSearchItem.addressLine`)
// so the scrolling result list never re-joins the street per card `build()`.
// The cards read the precomputed field and keep ONLY the locality fallback
// ([formatLocality]) at render. The single source of truth for the street join
// is `_formatAddressLine` in `data/search_mapper.dart`.

/// Joins a city + district label into one «district, city» / «city» string, or
/// returns null when both are absent. Shared by both cards.
String? formatLocality(String? cityLabel, String? districtLabel) {
  final String? city = (cityLabel != null && cityLabel.isNotEmpty)
      ? cityLabel
      : null;
  final String? district = (districtLabel != null && districtLabel.isNotEmpty)
      ? districtLabel
      : null;
  if (city == null && district == null) return null;
  if (city != null && district != null) return '$district, $city';
  return city ?? district;
}
