// Promoted (REUSE-FIRST) from `features/favorites/presentation/widgets/
// favorite_cards.dart`'s private `_AffiliationLine` so the salon master's own
// profile screen (`features/master/presentation/salon_master_profile_screen
// .dart`) can render the identical "storefront glyph + salon name" line
// instead of forking a near-duplicate — the same widget now has TWO callers:
// a favourited master's card (third-person: "this master works at X") and
// the SALON_MASTER's own profile (first-person: "I work at X"). Neither
// caller's meaning changes with the rename — both read as plain affiliation
// text, and the class doc below (verbatim from the original) already
// describes the general case, not just the favourites card.
//
// The original file's own doc explains the accent-vs-muted colour contract
// this line is part of (a salon name is a NAVIGABLE entity → accentDeep; an
// address is INERT orientation → muted) — that contract is unchanged by the
// move, only the class's location and its `_`-privacy.
//
// `favorite_cards.dart` now imports and calls this promoted widget verbatim;
// its own golden (`test/golden/favorite_cards_golden_test.dart`) pins the
// exact pixels this file paints, so the promotion is proven non-regressing by
// that suite staying green, not by inspection alone.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';

/// A storefront glyph + a salon's name, one register below whatever identity
/// text sits above it (a person's display name, most commonly).
///
/// Shown only when the caller actually has a salon name to display — omitting
/// this line entirely (rather than rendering it empty) is the caller's
/// decision, not this widget's.
class SalonAffiliationLine extends StatelessWidget {
  const SalonAffiliationLine({super.key, required this.salonName});

  /// The salon's display name. Must be non-empty — callers gate on that
  /// before constructing this widget (mirrors every other "omit when empty"
  /// convention in this codebase).
  final String salonName;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const Icon(
          Icons.storefront_outlined,
          size: 15,
          color: BrandColors.accentDeep,
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            salonName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: VelvetText.favAffiliation,
          ),
        ),
      ],
    );
  }
}
