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
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
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
/// (and pops), or null when dismissed.
class SortOptionsSheet extends StatelessWidget {
  const SortOptionsSheet({super.key, required this.active});

  /// The currently-applied ordering (rendered in the pressed/checked state).
  final SearchSort active;

  /// Presents the sheet and resolves with the user's pick (or null on dismiss).
  static Future<SearchSort?> show(
    BuildContext context, {
    required SearchSort active,
  }) {
    return showModalBottomSheet<SearchSort>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: false,
      builder: (BuildContext ctx) => SortOptionsSheet(active: active),
    );
  }

  static const BorderRadius _sheetRadius = BorderRadius.vertical(
    top: Radius.circular(VelvetRadii.card),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: BrandColors.base,
        borderRadius: _sheetRadius,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            VelvetSpacing.lg,
            VelvetSpacing.md,
            VelvetSpacing.lg,
            VelvetSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Drag handle.
              Center(
                child: Container(
                  height: 4,
                  width: 44,
                  decoration: BoxDecoration(
                    color: BrandColors.faint,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: VelvetSpacing.md),
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text(
                  l10n.searchSortSheetTitle,
                  style: VelvetText.subheading(),
                ),
              ),
              const SizedBox(height: VelvetSpacing.md),
              for (final SearchSort option in SearchSort.values) ...<Widget>[
                _SortRow(
                  option: option,
                  label: sortLabel(l10n, option),
                  selected: option == active,
                  selectedSemanticsLabel: l10n.searchSortOptionSelected(
                    sortLabel(l10n, option),
                  ),
                  onTap: () => ModalRoute.of(context)?.navigator?.pop(option),
                ),
                if (option != SearchSort.values.last)
                  const SizedBox(height: VelvetSpacing.sm),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One selectable sort row. Selected → pressed inset well + camel check;
/// unselected → flat on the base surface.
class _SortRow extends StatelessWidget {
  const _SortRow({
    required this.option,
    required this.label,
    required this.selected,
    required this.selectedSemanticsLabel,
    required this.onTap,
  });

  final SearchSort option;
  final String label;
  final bool selected;
  final String selectedSemanticsLabel;
  final VoidCallback onTap;

  static const BorderRadius _radius = BorderRadius.all(
    Radius.circular(VelvetRadii.field),
  );

  static final TextStyle _labelStyle = VelvetText.body().copyWith(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: BrandColors.text,
  );

  @override
  Widget build(BuildContext context) {
    final Widget row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: VelvetSpacing.md,
        vertical: VelvetSpacing.md,
      ),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: _labelStyle)),
          if (selected)
            const Icon(
              Icons.check_rounded,
              color: BrandColors.accent,
              size: 22,
            ),
        ],
      ),
    );

    return Semantics(
      button: true,
      selected: selected,
      label: selected ? selectedSemanticsLabel : label,
      child: GestureDetector(
        key: Key('sort_option_${option.name}'),
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: selected
            ? NeumorphicInset(radius: VelvetRadii.field, child: row)
            : DecoratedBox(
                decoration: const BoxDecoration(
                  color: BrandColors.base,
                  borderRadius: _radius,
                  boxShadow: VelvetShadows.extrudedSmall,
                ),
                child: row,
              ),
      ),
    );
  }
}
