// Phase 19.x (search wire-up) — result sort control.
//
// Two pieces, both within the VelvetTouch / Warm Mocha neumorphic language:
//   • [SortPillButton] — a compact extruded pill in the results top bar showing
//     the active sort label (⇅ + «За рейтингом»). Tapping it opens the sheet.
//   • [SortOptionsSheet] — a base-color modal bottom sheet listing the 4
//     [SearchSort] options. The active row sits in a pressed (inset) neumorphic
//     well with a camel check; the rest are flat. Selecting a row returns it to
//     the caller (the results screen re-queries by re-keying its provider).
//
// No glassmorphism, no raw gradients — the shadow recipes from
// [VelvetShadows] carry all depth, matching NeumorphicCard / NeumorphicInset.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/shared/widgets/velvet_sheet.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

import '../../domain/search_filters.dart';

/// Returns the localised label for [sort].
String sortLabel(AppLocalizations l10n, SearchSort sort) {
  switch (sort) {
    case SearchSort.ratingDesc:
      return l10n.searchSortRatingDesc;
    case SearchSort.priceAsc:
      return l10n.searchSortPriceAsc;
    case SearchSort.priceDesc:
      return l10n.searchSortPriceDesc;
    case SearchSort.reviewsDesc:
      return l10n.searchSortReviewsDesc;
  }
}

/// A square extruded icon control opening [SortOptionsSheet].
///
/// Sits between the title and the filter icon in the results top bar. It is
/// rendered icon-only (matching the sibling [NeumorphicIconButton] filter
/// control) so the top bar never wraps to a second row when the active sort
/// label is long. The active sort value is NOT shown inline — it lives in the
/// sheet's checked row — but is preserved as the control's accessible `value`
/// so screen readers still announce «Сортування: За рейтингом».
class SortPillButton extends StatelessWidget {
  const SortPillButton({
    super.key,
    required this.activeSort,
    required this.onSelected,
  });

  /// The currently-applied ordering, announced as the control's a11y value.
  final SearchSort activeSort;

  /// Invoked with the chosen ordering when the sheet returns a (changed)
  /// selection. Not called when the user dismisses without picking, or re-picks
  /// the already-active option.
  final ValueChanged<SearchSort> onSelected;

  // Square extruded chrome matching NeumorphicIconButton (same extent + radius +
  // shadow recipe), so the sort + filter icons read as one control pair.
  static const BorderRadius _radius = BorderRadius.all(
    Radius.circular(VelvetRadii.field),
  );

  Future<void> _open(BuildContext context) async {
    final SearchSort? picked = await SortOptionsSheet.show(
      context,
      active: activeSort,
    );
    if (picked != null && picked != activeSort) onSelected(picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: l10n.searchSortButtonLabel,
      value: sortLabel(l10n, activeSort),
      child: GestureDetector(
        key: const Key('results_sort_button'),
        onTap: () => _open(context),
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: NeumorphicIconButton.extent,
          width: NeumorphicIconButton.extent,
          decoration: const BoxDecoration(
            color: BrandColors.base,
            borderRadius: _radius,
            boxShadow: VelvetShadows.extrudedSmall,
          ),
          child: const Icon(
            Icons.swap_vert_rounded,
            color: BrandColors.textSecondary,
            size: 22,
          ),
        ),
      ),
    );
  }
}

/// The sort-options modal bottom sheet.
///
/// Renders the 4 [SearchSort] options as full-width rows; the active row is
/// shown in a pressed inset well with a camel check. Returns the tapped option
/// (and pops), or null when dismissed. Chrome + rows are the shared
/// [VelvetSheetChrome] / [VelvetSheetOptionRow] (promoted in Phase 071).
class SortOptionsSheet extends StatelessWidget {
  const SortOptionsSheet({super.key, required this.active});

  /// The currently-applied ordering (rendered in the pressed/checked state).
  final SearchSort active;

  /// Presents the sheet and resolves with the user's pick (or null on dismiss).
  static Future<SearchSort?> show(
    BuildContext context, {
    required SearchSort active,
  }) {
    return showVelvetSheet<SearchSort>(
      context,
      builder: (BuildContext ctx) => SortOptionsSheet(active: active),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return VelvetSheetChrome(
      title: l10n.searchSortSheetTitle,
      children: <Widget>[
        for (final SearchSort option in SearchSort.values)
          VelvetSheetOptionRow(
            tapKey: Key('sort_option_${option.name}'),
            label: sortLabel(l10n, option),
            selected: option == active,
            semanticsLabel: option == active
                ? l10n.searchSortOptionSelected(sortLabel(l10n, option))
                : sortLabel(l10n, option),
            onTap: () => ModalRoute.of(context)?.navigator?.pop(option),
          ),
      ],
    );
  }
}
