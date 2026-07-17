// Phase 4.6 — Master reviews sort control (icon button + bottom sheet).
//
// A thin, deliberate copy of the salon reviews `_SortIconButton` / `_SortSheet`
// (`features/salon/presentation/widgets/salon_reviews_section.dart`) rebound to
// the master's own [MasterReviewSort] enum + l10n keys. Per the phase brief the
// sort UI stays per-feature (small, stable) rather than being promoted to the
// shared `review` module, which would churn the shipped salon data path for no
// visual gain.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/master/domain/master_review.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

/// Returns the localised label for [sort].
String masterReviewSortLabel(AppLocalizations l10n, MasterReviewSort sort) {
  switch (sort) {
    case MasterReviewSort.newest:
      return l10n.masterReviewSortNewest;
    case MasterReviewSort.oldest:
      return l10n.masterReviewSortOldest;
    case MasterReviewSort.highest:
      return l10n.masterReviewSortHighest;
    case MasterReviewSort.lowest:
      return l10n.masterReviewSortLowest;
  }
}

/// A square extruded ⇅ icon button that opens [MasterReviewSortSheet].
class MasterReviewSortIconButton extends StatelessWidget {
  const MasterReviewSortIconButton({
    super.key,
    required this.active,
    required this.onSelected,
  });

  final MasterReviewSort active;
  final ValueChanged<MasterReviewSort> onSelected;

  Future<void> _open(BuildContext context) async {
    final MasterReviewSort? picked = await MasterReviewSortSheet.show(
      context,
      active,
    );
    if (picked != null && picked != active) onSelected(picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: l10n.masterReviewSortButtonLabel,
      value: masterReviewSortLabel(l10n, active),
      child: GestureDetector(
        key: const Key('master-reviews-sort-button'),
        onTap: () => _open(context),
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 44,
          width: 44,
          decoration: const BoxDecoration(
            color: BrandColors.base,
            borderRadius: BorderRadius.all(Radius.circular(VelvetRadii.field)),
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
class MasterReviewSortSheet extends StatelessWidget {
  const MasterReviewSortSheet({super.key, required this.active});

  final MasterReviewSort active;

  static Future<MasterReviewSort?> show(
    BuildContext context,
    MasterReviewSort active,
  ) {
    return showModalBottomSheet<MasterReviewSort>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) => MasterReviewSortSheet(active: active),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: BrandColors.base,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(VelvetRadii.card),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
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
                  l10n.masterReviewSortSheetTitle,
                  style: VelvetText.subheading(),
                ),
              ),
              const SizedBox(height: VelvetSpacing.md),
              for (final MasterReviewSort option
                  in MasterReviewSort.values) ...<Widget>[
                _SortRow(
                  option: option,
                  label: masterReviewSortLabel(l10n, option),
                  selected: option == active,
                  onTap: () => context.pop(option),
                ),
                if (option != MasterReviewSort.values.last)
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
/// unselected → raised on the base surface.
class _SortRow extends StatelessWidget {
  const _SortRow({
    required this.option,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final MasterReviewSort option;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Widget row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: VelvetSpacing.md,
        vertical: VelvetSpacing.md,
      ),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: VelvetText.bodyStrong15)),
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
      label: label,
      child: GestureDetector(
        key: Key('master-review-sort-option-${option.name}'),
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: selected
            ? NeumorphicInset(radius: VelvetRadii.field, child: row)
            : DecoratedBox(
                decoration: const BoxDecoration(
                  color: BrandColors.base,
                  borderRadius: BorderRadius.all(
                    Radius.circular(VelvetRadii.field),
                  ),
                  boxShadow: VelvetShadows.extrudedSmall,
                ),
                child: row,
              ),
      ),
    );
  }
}
