// Phase 13.4 — Hoisted text styles + helpers shared by the result cards.
//
// All TextStyles are computed once at class-load (perf house-rule: never
// allocate a TextStyle per build inside a scrolling list).

import 'package:beautica_mobile/core/theme/brand_colors.dart';
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
  static final TextStyle locality = VelvetText.body().copyWith(
    fontSize: 12.5,
    color: BrandColors.muted,
  );

  /// Bold numeric rating value (13sp).
  static final TextStyle ratingValue = VelvetText.bodyStrong().copyWith(
    fontSize: 13,
  );

  /// «від N грн» / price-range accent line (14sp accentDeep).
  static final TextStyle price = VelvetText.bodyStrong().copyWith(
    fontSize: 14,
    color: BrandColors.accentDeep,
  );

  /// Procedure / service-names preview line on the master card (e.g.
  /// «Манікюр · Педикюр»). A touch smaller than the name, in the secondary tone
  /// so it reads as supporting detail rather than competing with the name.
  static final TextStyle services = VelvetText.body().copyWith(
    fontSize: 12.5,
    color: BrandColors.textSecondary,
  );
}

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
