// Phase 13.6 — Salon public service catalogue accordion ("Послуги" tab).
//
// Ported from the approved preview app at
// `docs/signup-designs/PublicSalonProfile/lib/widgets/salon_services.dart`,
// wired to the real [SalonServiceCategoryEntry] / [SalonCatalogService]
// domain models loaded from `GET /salons/{salonId}/services` instead of the
// preview's static mock catalogue.
//
// Reproduces the BookingServiceSelection vocabulary (carved-card category
// header + raised count badge + camel chevron + `AnimatedSize` expand) MINUS
// all selection machinery — no checkboxes, no selected-count badge, no
// pinned summary bar. NOTE: the real booking service-selection screen
// (Phase 14.1) has not shipped yet in this codebase (only a placeholder route
// exists), so this accordion is transcribed directly from the preview rather
// than mirrored from a live sibling widget.
//
// On load the first category is expanded and the rest collapsed.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

import '../../domain/salon_service_catalog.dart';

/// The READ-ONLY categories + services accordion.
///
/// A plain [StatelessWidget] over a [ListView.builder] of [_SalonCategoryGroup]
/// rows (mobile-perf MEDIUM fix, Phase 13.6 audit): each category owns its own
/// `_expanded` bool in its own [State], so toggling one category's disclosure
/// only rebuilds THAT category's subtree instead of every category group in
/// the accordion (the previous top-level `setState` regenerated the whole
/// widget list on every toggle).
class SalonServicesAccordion extends StatelessWidget {
  const SalonServicesAccordion({super.key, required this.categories});

  final List<SalonServiceCategoryEntry> categories;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int i = 0; i < categories.length; i++) ...<Widget>[
            _SalonCategoryGroup(
              category: categories[i],
              // Seeds the first category open on load; the rest start
              // collapsed. Each group's own State owns this after the
              // first build, so re-builds of THIS StatelessWidget (e.g. a
              // sibling category toggling) never reset an already-toggled
              // group back to its initial value.
              initiallyExpanded: i == 0,
            ),
            if (i < categories.length - 1)
              const SizedBox(height: VelvetSpacing.md),
          ],
        ],
      ),
    );
  }
}

/// One category's disclosure header + its (collapsible) service rows.
/// Owns its own expand/collapse state so toggling it never rebuilds sibling
/// category groups.
class _SalonCategoryGroup extends StatefulWidget {
  const _SalonCategoryGroup({
    required this.category,
    required this.initiallyExpanded,
  });

  final SalonServiceCategoryEntry category;
  final bool initiallyExpanded;

  @override
  State<_SalonCategoryGroup> createState() => _SalonCategoryGroupState();
}

class _SalonCategoryGroupState extends State<_SalonCategoryGroup> {
  late bool _expanded = widget.initiallyExpanded;

  void _toggleExpand() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final SalonServiceCategoryEntry cat = widget.category;

    final Widget rows = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final SalonCatalogService s in cat.services)
          Padding(
            padding: const EdgeInsets.only(top: VelvetSpacing.md),
            child: _SalonServiceRow(
              name: s.name,
              duration: s.durationLabel,
              price: s.priceDisplay,
            ),
          ),
      ],
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SalonCategoryHeader(
          label: cat.displayName,
          count: cat.count,
          expanded: _expanded,
          onTap: _toggleExpand,
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _expanded
              ? rows
              : const SizedBox(width: double.infinity, height: 0),
        ),
      ],
    );
  }
}

/// A category disclosure header — an EXTRUDED card pillow carrying the
/// category title on the left, a small RAISED count badge on the right, and a
/// camel chevron that rotates from "points right" (collapsed) to "points
/// down" (expanded).
class _SalonCategoryHeader extends StatelessWidget {
  const _SalonCategoryHeader({
    required this.label,
    required this.count,
    required this.expanded,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool expanded;
  final VoidCallback onTap;

  static final TextStyle _headerStyle = VelvetText.subheading().copyWith(
    fontSize: 16,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      header: true,
      expanded: expanded,
      label: l10n.salonServiceCategoryHeaderSemanticLabel(
        label,
        count,
        expanded
            ? l10n.salonServiceCategoryExpanded
            : l10n.salonServiceCategoryCollapsed,
      ),
      child: GestureDetector(
        key: Key('salon-service-category-$label'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: VelvetSpacing.md,
            vertical: VelvetSpacing.sm + 2,
          ),
          decoration: BoxDecoration(
            color: BrandColors.base,
            borderRadius: BorderRadius.circular(VelvetRadii.card),
            boxShadow: VelvetShadows.extrudedCard,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: _headerStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: VelvetSpacing.sm),
              _CountBadge(count: count),
              const SizedBox(width: VelvetSpacing.sm),
              AnimatedRotation(
                turns: expanded ? 0.0 : -0.25,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 22,
                  color: BrandColors.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small RAISED count pill on the right of a category header.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: VelvetSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: BrandColors.base,
        borderRadius: BorderRadius.circular(999),
        boxShadow: VelvetShadows.extrudedSmall,
      ),
      child: Text(
        '$count',
        style: VelvetText.feedback(
          BrandColors.textSecondary,
        ).copyWith(fontSize: 12.5, fontWeight: FontWeight.w800),
      ),
    );
  }
}

/// A read-only service row: a raised neumorphic tile carrying the service
/// name + a muted duration on the left and the camel price on the right. No
/// check control, no selection state, no `onTap` (browse-only; a future
/// phase routes this into the booking flow).
class _SalonServiceRow extends StatelessWidget {
  const _SalonServiceRow({
    required this.name,
    required this.duration,
    required this.price,
  });

  final String name;
  final String duration;

  /// Display price — single ("500 грн") or en-dash range ("200–600 грн").
  final String price;

  /// Compact metadata scale (12.5 sp) matching the reference screen's
  /// `_MetaItem._valueStyle` in `services_list_screen.dart` — NOT the 15 sp
  /// `bodyStrong()` base, which visibly overpowers the 12 sp duration label
  /// next to it. Hoisted to a static so build() never allocates a new
  /// [TextStyle] per frame (matches the perf pattern used throughout
  /// `VelvetText` call sites in this codebase).
  static final TextStyle _priceStyle = VelvetText.pill().copyWith(
    fontSize: 12.5,
    color: BrandColors.accentDeep,
    fontWeight: FontWeight.w800,
  );

  /// Name scale matching the reference screen's `_ServiceInfo._nameStyle` in
  /// `services_list_screen.dart` — Comfortaa `cardTitle()` at 15 sp with a
  /// tight 1.15 line-height (NOT the 1.5 line-height of `bodyStrong()`,
  /// which visibly bulks up each row). Hoisted to a static so build() never
  /// allocates a new [TextStyle] per frame.
  static final TextStyle _nameStyle = VelvetText.cardTitle().copyWith(
    fontSize: 15,
    height: 1.15,
  );

  /// Duration meta scale matching the reference screen's
  /// `_MetaItem._valueStyle` in `services_list_screen.dart` — `pill()` at
  /// 12.5 sp (bold, camel `accentDeep`, baked into the `pill()` base) — NOT
  /// a muted `feedback()` 12 sp label. The name and price scales were
  /// already migrated to the reference in earlier fixes (9f8011e, 541a71e);
  /// this one was missed. Hoisted to a static so build() never allocates a
  /// new [TextStyle] per frame.
  static final TextStyle _durationStyle = VelvetText.pill().copyWith(
    fontSize: 12.5,
  );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$name, $duration, $price',
      child: Container(
        decoration: BoxDecoration(
          color: BrandColors.base,
          borderRadius: BorderRadius.circular(VelvetRadii.field),
          boxShadow: VelvetShadows.extrudedSmall,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: VelvetSpacing.sm + 4,
          vertical: VelvetSpacing.sm + 2,
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    name,
                    style: _nameStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(
                        Icons.schedule_outlined,
                        size: 13,
                        color: BrandColors.accent,
                      ),
                      const SizedBox(width: VelvetSpacing.xs),
                      Flexible(
                        child: Text(
                          duration,
                          style: _durationStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: VelvetSpacing.sm),
            Text(price, style: _priceStyle),
          ],
        ),
      ),
    );
  }
}
