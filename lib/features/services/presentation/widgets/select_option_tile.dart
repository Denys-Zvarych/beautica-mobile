// Phase 352 D8 — `_SelectOptionTile` PROMOTED out of `searchable_select_field
// .dart` (dropped the leading underscore, no other change) so the «Пошук»
// suggestion rows (`search_suggestion_list.dart`) can reuse the exact row the
// category/service-type sheets already render, instead of forking a
// near-identical tile. `SearchableSelectField`'s sheet is rewired onto this
// promoted widget; its own rendering is unchanged (byte-for-byte — same
// `Material` > `InkWell` > `Semantics` > `Padding` > `Row` > `Text` shape, same
// styles, same padding), which the golden + widget tests for that sheet prove.

import 'package:flutter/material.dart';

import '../../../../core/theme/brand_colors.dart';
import '../../../../core/theme/velvet_geometry.dart';
import '../../../../core/theme/velvet_text.dart';

/// A single selectable option row — the shared "one label, tappable, ≥48dp"
/// tile used inside a searchable-select sheet's option list AND (Phase 352)
/// the «Пошук» suggestion list under the search field.
class SelectOptionTile extends StatelessWidget {
  const SelectOptionTile({
    super.key,
    required this.label,
    required this.onTap,
    this.maxLines = 1,
  });

  final String label;
  final VoidCallback onTap;

  /// Lines one row may occupy before ellipsising — see
  /// `SearchableSelectField.optionMaxLines`.
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: BrandColors.accent.withValues(alpha: 0.12),
        highlightColor: BrandColors.accent.withValues(alpha: 0.08),
        child: Semantics(
          button: true,
          label: label,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: VelvetSpacing.md,
              vertical: VelvetSpacing.md,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    label,
                    maxLines: maxLines,
                    overflow: TextOverflow.ellipsis,
                    style: VelvetText.body(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
