// Phase 13.x (Variant A — «Рейка + послуги») — second-level service chips +
// the recessed drawer that holds them.
//
// Transcribed verbatim from the approved preview
// `docs/signup-designs/SearchCategoryDisplay/lib/widgets/category_widgets.dart`
// (`ServiceChip`) and `screens/rail_variant_screen.dart` (`_ServiceDrawer`),
// swapping the preview's local `VelvetColors.*` for the in-app `BrandColors.*`.
// Heights, paddings, radii, gradient, and the 160 ms select animation are
// reproduced exactly.
//
// The drawer is a recessed (inset-neumorphic) well so it reads as a distinct
// SECOND layer beneath the raised category rail. Inside, each service is a chip:
// resting = raised soft pill; selected = camel→mocha gradient fill with cream
// text + a check, so a chosen service reads as unmistakably "on".

import 'package:flutter/material.dart';

import '../../../../core/theme/brand_colors.dart';
import '../../../../core/theme/velvet_geometry.dart';
import '../../../../core/theme/velvet_text.dart';
import '../../../../core/widgets/neumorphic.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/category_service_option.dart';

/// A selectable service chip (the SECOND level). Resting = raised soft pill;
/// selected = camel/mocha gradient fill with cream text + a check.
class ServiceChip extends StatelessWidget {
  const ServiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.md),
          decoration: BoxDecoration(
            color: selected ? null : BrandColors.base,
            gradient: selected
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      BrandColors.accentLatte,
                      BrandColors.accentDeep,
                    ],
                  )
                : null,
            borderRadius: BorderRadius.circular(20),
            boxShadow: selected
                ? VelvetShadows.extrudedButtonAccent
                : VelvetShadows.extrudedSmall,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (selected) ...<Widget>[
                const Icon(
                  Icons.check_rounded,
                  color: BrandColors.white,
                  size: 16,
                ),
                const SizedBox(width: VelvetSpacing.xs + 2),
              ],
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: VelvetText.discChipLabel.copyWith(
                  color: selected ? BrandColors.white : BrandColors.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The in-place service drawer: a labelled block of selectable service chips for
/// the chosen category. Anchored as a recessed well so it reads as a distinct
/// second layer beneath the raised category rail.
class ServiceChipDrawer extends StatelessWidget {
  const ServiceChipDrawer({
    super.key,
    required this.label,
    required this.services,
    required this.selectedKeys,
    required this.onToggle,
  });

  /// Pre-formatted «Послуги · {category}» drawer label.
  final String label;

  final List<CategoryServiceOption> services;
  final Set<String> selectedKeys;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final int selectedCount = selectedKeys.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Row(
            children: <Widget>[
              Flexible(child: Text(label, style: VelvetText.label())),
              // Active-service count badge — reflects how many service chips are
              // selected, mirroring how other active filters are surfaced.
              // Collapses to nothing at zero (and so resets on a category change,
              // which clears the selection upstream).
              if (selectedCount > 0) ...<Widget>[
                const SizedBox(width: VelvetSpacing.sm),
                _SelectedCountBadge(
                  label: l10n.searchServicesSelectedCount(selectedCount),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: VelvetSpacing.sm),
        NeumorphicInset(
          radius: VelvetRadii.card,
          child: Padding(
            padding: const EdgeInsets.all(VelvetSpacing.md),
            child: Wrap(
              spacing: VelvetSpacing.sm,
              runSpacing: VelvetSpacing.sm,
              children: <Widget>[
                for (final CategoryServiceOption s in services)
                  ServiceChip(
                    key: Key('search_service_chip_${s.key}'),
                    label: s.displayName,
                    selected: selectedKeys.contains(s.key),
                    onTap: () => onToggle(s.key),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A small accent pill carrying the active-service count beside the drawer
/// label (e.g. «Обрано 2»). Reads as the same camel→mocha "on" treatment as a
/// selected chip so it ties visually to the selection it summarises.
class _SelectedCountBadge extends StatelessWidget {
  const _SelectedCountBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: Container(
        key: const Key('search_services_selected_count'),
        padding: const EdgeInsets.symmetric(
          horizontal: VelvetSpacing.sm,
          vertical: VelvetSpacing.xs,
        ),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[BrandColors.accentLatte, BrandColors.accentDeep],
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: VelvetText.label().copyWith(
            color: BrandColors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
