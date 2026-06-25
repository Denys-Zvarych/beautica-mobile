// Phase 13.4 — Full-address block shared by the master + salon result cards.
//
// Renders the result's location as up to two muted lines, led by a small
// place-pin glyph so the address group reads apart from the services line:
//
//   📍 Печерський район, Київ           ← locality (city · district), line 1
//      вул. Хрещатик, 22 · вхід з двору  ← street + building + note,  line 2
//
// The address NEVER contains region/oblast — the search contract does not carry
// it, so there is nothing to render or strip here.
//
// Composition split (see SearchMapper):
//   - [locality] is composed AT RENDER via `formatLocality(cityLabel,
//     districtLabel)` because the district/city join is l10n/presentation
//     concern.
//   - [streetLine] is the auth-gated «street, buildingNo · note» line,
//     PRECOMPUTED once at map time (MasterSearchMapper/SalonSearchMapper →
//     `addressLine`) so this list-row widget never re-joins per build().
//
// Null-handling (clean in every state):
//   - anonymous browse → street/building/note null → [streetLine] null → only
//     the locality line renders (pin + city · district);
//   - no locality either → the whole block collapses to a zero-size
//     `SizedBox.shrink()` (no orphan pin);
//   - authed with street but no note → just «street, buildingNo» (the mapper
//     drops the dangling separator).

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';

import 'result_card_text.dart';

/// The location block on a master/salon result card: a leading pin glyph and up
/// to two muted lines (locality, then the auth-gated street detail). Renders
/// nothing when both [locality] and [streetLine] are absent.
class ResultAddressBlock extends StatelessWidget {
  const ResultAddressBlock({
    super.key,
    required this.locality,
    required this.streetLine,
  });

  /// The city · district line composed at render via [formatLocality], or null
  /// when neither a city nor a district is known.
  final String? locality;

  /// The precomputed auth-gated «street, buildingNo · note» detail line, or
  /// null for an anonymous caller / a result with no recorded street.
  final String? streetLine;

  @override
  Widget build(BuildContext context) {
    final String? primary = locality ?? streetLine;
    // Nothing to show at all → take up no space (no orphan pin / empty line).
    if (primary == null) return const SizedBox.shrink();

    // When there is no locality, the street line is promoted to the primary
    // line so it still sits beside the pin (rather than leaving a blank line 1).
    final String? secondary = locality == null ? null : streetLine;

    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(top: 1, right: 4),
            child: Icon(
              Icons.place_outlined,
              size: 13,
              color: BrandColors.muted,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  primary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ResultCardText.locality,
                ),
                if (secondary != null) ...<Widget>[
                  // 3dp matches the card's established intra-line micro-gap.
                  const SizedBox(height: 3),
                  Text(
                    secondary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ResultCardText.addressDetail,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
