// Phase 13.x (Variant A — «Рейка + послуги») — «Всі категорії» bottom sheet.
//
// Transcribed verbatim from the approved preview
// `docs/signup-designs/SearchCategoryDisplay/lib/widgets/category_widgets.dart`
// (`showAllCategoriesSheet`, `_SheetCategoryTile`), swapping the preview's local
// `VelvetColors.*` for `BrandColors.*` and the inline mock `Catalog.categories`
// for the live category list passed in by the caller (sourced from
// `approvedCategoriesProvider`). All copy flows through AppLocalizations.
//
// The full-catalog sheet opened by «Всі категорії». Lists every category as a
// tappable wrapped tile; tapping pops the chosen [ServiceCategoryOption] back to
// the caller. This is the "path to the full list" that lets the rail stay short.

import 'package:flutter/material.dart';

import '../../../../core/theme/brand_colors.dart';
import '../../../../core/theme/velvet_geometry.dart';
import '../../../../core/theme/velvet_text.dart';
import '../../../../core/widgets/neumorphic.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../services/domain/service_category_option.dart';
import 'service_type_tile.dart' show serviceTypeIcon;

/// Opens the «Всі категорії» sheet over [categories]; resolves to the chosen
/// category, or null if dismissed. [selectedKey] highlights the active row.
Future<ServiceCategoryOption?> showAllCategoriesSheet(
  BuildContext context, {
  required List<ServiceCategoryOption> categories,
  String? selectedKey,
}) {
  final AppLocalizations l10n = AppLocalizations.of(context);
  return showModalBottomSheet<ServiceCategoryOption>(
    context: context,
    backgroundColor: BrandColors.base,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(VelvetRadii.card),
      ),
    ),
    builder: (BuildContext ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            VelvetSpacing.lg,
            VelvetSpacing.md,
            VelvetSpacing.lg,
            VelvetSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
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
              Text(
                l10n.searchAllCategoriesSheetTitle,
                style: VelvetText.heading(),
              ),
              const SizedBox(height: VelvetSpacing.xs),
              Text(
                l10n.searchAllCategoriesSheetSubtitle,
                style: VelvetText.body().copyWith(fontSize: 13),
              ),
              const SizedBox(height: VelvetSpacing.md),
              Flexible(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: VelvetSpacing.sm,
                    runSpacing: VelvetSpacing.sm,
                    children: <Widget>[
                      for (final ServiceCategoryOption c in categories)
                        _SheetCategoryTile(
                          key: Key('search_all_categories_${c.name}'),
                          category: c,
                          selected: c.name == selectedKey,
                          onTap: () => Navigator.of(ctx).pop(c),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _SheetCategoryTile extends StatelessWidget {
  const _SheetCategoryTile({
    super.key,
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final ServiceCategoryOption category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Widget inner = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: VelvetSpacing.md,
        vertical: VelvetSpacing.sm + 2,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            serviceTypeIcon(category.name),
            color: selected ? BrandColors.accent : BrandColors.textSecondary,
            size: 20,
          ),
          const SizedBox(width: VelvetSpacing.sm),
          Text(
            category.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: VelvetText.body().copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: selected ? BrandColors.accentDeep : BrandColors.text,
            ),
          ),
        ],
      ),
    );

    return Semantics(
      button: true,
      selected: selected,
      label: category.displayName,
      child: GestureDetector(
        onTap: onTap,
        child: selected
            ? NeumorphicInset(radius: VelvetRadii.field, child: inner)
            : NeumorphicCard(
                padding: EdgeInsets.zero,
                radius: VelvetRadii.field,
                shadows: VelvetShadows.extrudedSmall,
                child: inner,
              ),
      ),
    );
  }
}
