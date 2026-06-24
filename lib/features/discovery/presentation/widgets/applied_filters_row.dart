// Phase 13.4 — Applied-filters chip row.
//
// A horizontal scroll of neumorphic chips reflecting the active [SearchFilters]:
// locality, category, and the price band. Each chip carries a trailing «×» that
// clears just that field and re-queries (the host screen rebuilds the results
// with the amended filter set). Hidden entirely when no filters are active.
//
// The preview's chips use a chevron («▾») to imply "edit"; the real chips CLEAR
// a filter, so the honest trailing glyph is a close «×». Re-opening the full
// filter controls is the job of the top-bar filter icon.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

import '../../domain/search_filters.dart';

/// Describes one active-filter chip: its label + the field it clears.
@immutable
class _ChipSpec {
  const _ChipSpec({required this.label, required this.field});

  final String label;
  final AppliedFilterField field;
}

/// The filter field an applied chip clears.
enum AppliedFilterField { locality, category, price }

/// A removable filter chip row above the results list.
class AppliedFiltersRow extends StatelessWidget {
  const AppliedFiltersRow({
    super.key,
    required this.filters,
    required this.cityLabel,
    required this.categoryLabel,
    required this.onClear,
  });

  /// The active filter set (drives which chips are shown).
  final SearchFilters filters;

  /// Display label for the selected city, or null.
  final String? cityLabel;

  /// Display label for the selected category, or null.
  final String? categoryLabel;

  /// Invoked with the field to clear when a chip's «×» is tapped.
  final void Function(AppliedFilterField field) onClear;

  List<_ChipSpec> _specs(AppLocalizations l10n) {
    final List<_ChipSpec> specs = <_ChipSpec>[];

    if (cityLabel != null && cityLabel!.isNotEmpty) {
      specs.add(
        _ChipSpec(label: cityLabel!, field: AppliedFilterField.locality),
      );
    }
    if (categoryLabel != null && categoryLabel!.isNotEmpty) {
      specs.add(
        _ChipSpec(label: categoryLabel!, field: AppliedFilterField.category),
      );
    }

    final String? priceLabel = _priceBandLabel(l10n);
    if (priceLabel != null) {
      specs.add(_ChipSpec(label: priceLabel, field: AppliedFilterField.price));
    }
    return specs;
  }

  /// Collapses the active price band into one chip label, or null when no price
  /// filter is set:
  ///   both set → «N–M грн», max only → «до N грн», min only → «від N грн».
  String? _priceBandLabel(AppLocalizations l10n) {
    final int? lo = filters.minPrice?.round();
    final int? hi = filters.maxPrice?.round();
    if (lo == null && hi == null) return null;
    if (lo != null && hi != null) return l10n.searchResultPriceRange(lo, hi);
    if (hi != null) return l10n.searchPriceUpTo(hi);
    return l10n.searchPriceFrom(lo!);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final List<_ChipSpec> specs = _specs(l10n);
    if (specs.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 38,
      child: ListView.separated(
        key: const Key('applied_filters_row'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
        itemCount: specs.length,
        separatorBuilder: (_, _) => const SizedBox(width: VelvetSpacing.sm),
        itemBuilder: (BuildContext context, int i) {
          final _ChipSpec spec = specs[i];
          return _RemovableChip(
            key: Key('filter_chip_${spec.field.name}'),
            label: spec.label,
            clearSemanticLabel: l10n.searchResultClearFilter(spec.label),
            onClear: () => onClear(spec.field),
          );
        },
      ),
    );
  }
}

/// A single neumorphic chip with a trailing «×» clear affordance.
class _RemovableChip extends StatelessWidget {
  const _RemovableChip({
    super.key,
    required this.label,
    required this.clearSemanticLabel,
    required this.onClear,
  });

  final String label;
  final String clearSemanticLabel;
  final VoidCallback onClear;

  static const BorderRadius _radius = BorderRadius.all(Radius.circular(19));

  static final TextStyle _labelStyle = VelvetText.body().copyWith(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    color: BrandColors.text,
  );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: clearSemanticLabel,
      child: GestureDetector(
        onTap: onClear,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.md),
          decoration: const BoxDecoration(
            color: BrandColors.base,
            borderRadius: _radius,
            boxShadow: VelvetShadows.extrudedSmall,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(label, style: _labelStyle),
              const SizedBox(width: VelvetSpacing.xs),
              const Icon(
                Icons.close_rounded,
                color: BrandColors.muted,
                size: 17,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
