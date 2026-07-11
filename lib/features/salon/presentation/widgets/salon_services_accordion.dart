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

/// The categories + services accordion.
///
/// A plain [StatelessWidget] over a [ListView.builder] of [_SalonCategoryGroup]
/// rows (mobile-perf MEDIUM fix, Phase 13.6 audit): each category owns its own
/// `_expanded` bool in its own [State], so toggling one category's disclosure
/// only rebuilds THAT category's subtree instead of every category group in
/// the accordion (the previous top-level `setState` regenerated the whole
/// widget list on every toggle).
///
/// When [onServiceTap] is supplied the service rows become tappable — tapping
/// one picks it as the "filter the masters grid by this service" selection
/// (see `salon_service_filter_notifier.dart`); the row whose id matches
/// [selectedServiceId] renders in its selected (camel-outlined) state. When
/// [onServiceTap] is null the rows are inert (the original browse-only
/// behaviour).
class SalonServicesAccordion extends StatelessWidget {
  const SalonServicesAccordion({
    super.key,
    required this.categories,
    this.selectedServiceId,
    this.onServiceTap,
  });

  final List<SalonServiceCategoryEntry> categories;

  /// The catalog id of the currently-selected service, or null when no service
  /// filter is active.
  final String? selectedServiceId;

  /// Called with the tapped service. Null makes the rows inert.
  final ValueChanged<SalonCatalogService>? onServiceTap;

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
              selectedServiceId: selectedServiceId,
              onServiceTap: onServiceTap,
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
    required this.selectedServiceId,
    required this.onServiceTap,
  });

  final SalonServiceCategoryEntry category;
  final bool initiallyExpanded;
  final String? selectedServiceId;
  final ValueChanged<SalonCatalogService>? onServiceTap;

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
              service: s,
              selected: widget.selectedServiceId == s.id,
              onTap: widget.onServiceTap == null
                  ? null
                  : () => widget.onServiceTap!(s),
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

  static final TextStyle _headerStyle = VelvetText.subheading16;

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
        style: VelvetText.bookFeedback125w800.copyWith(
          color: BrandColors.textSecondary,
        ),
      ),
    );
  }
}

/// A service row: a raised neumorphic tile carrying the service name + a muted
/// duration on the left and the camel price on the right.
///
/// When [onTap] is non-null the row is a selectable filter control: tapping it
/// picks (or, if already picked, clears) this service as the "show only masters
/// who perform it" filter for the "Майстри" grid. [selected] drives the active
/// state — a camel outline over a subtle camel wash, the name recoloured to
/// [BrandColors.accentDeep], and a camel check badge that grows in to the left
/// of the price (the row's height is unchanged, so the accordion never jumps).
/// When [onTap] is null the row is inert (browse-only), matching the original
/// read-only behaviour.
class _SalonServiceRow extends StatelessWidget {
  const _SalonServiceRow({
    required this.service,
    required this.selected,
    required this.onTap,
  });

  final SalonCatalogService service;
  final bool selected;
  final VoidCallback? onTap;

  /// Subtle camel wash for the selected row's fill — the accent at low alpha
  /// blended over the base so the tile stays a solid neumorphic surface (no
  /// translucency) while reading as "active".
  static final Color _selectedFill = Color.alphaBlend(
    BrandColors.accent.withValues(alpha: 0.16),
    BrandColors.base,
  );

  /// Compact metadata scale (12.5 sp) matching the reference screen's
  /// `_MetaItem._valueStyle` in `services_list_screen.dart` — NOT the 15 sp
  /// `bodyStrong()` base, which visibly overpowers the 12 sp duration label
  /// next to it. Hoisted to a static so build() never allocates a new
  /// [TextStyle] per frame (matches the perf pattern used throughout
  /// `VelvetText` call sites in this codebase).
  static final TextStyle _priceStyle = VelvetText.pillSm;

  /// Name scale matching the reference screen's `_ServiceInfo._nameStyle` in
  /// `services_list_screen.dart` — Comfortaa `cardTitle()` at 15 sp with a
  /// tight 1.15 line-height (NOT the 1.5 line-height of `bodyStrong()`,
  /// which visibly bulks up each row). Hoisted to a static so build() never
  /// allocates a new [TextStyle] per frame.
  static final TextStyle _nameStyle = VelvetText.svcCardName;

  /// Selected-row variant of [_nameStyle] — invariant, so hoisted to a static
  /// so build() never allocates a new [TextStyle] per frame for the selected
  /// branch.
  static final TextStyle _nameStyleSelected = _nameStyle.copyWith(
    color: BrandColors.accentDeep,
  );

  /// Duration meta scale matching the reference screen's
  /// `_MetaItem._valueStyle` in `services_list_screen.dart` — `pill()` at
  /// 12.5 sp (bold, camel `accentDeep`, baked into the `pill()` base) — NOT
  /// a muted `feedback()` 12 sp label. The name and price scales were
  /// already migrated to the reference in earlier fixes (9f8011e, 541a71e);
  /// this one was missed. Hoisted to a static so build() never allocates a
  /// new [TextStyle] per frame.
  static final TextStyle _durationStyle = VelvetText.pillSm;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String name = service.name;
    final String duration = service.durationLabel;
    final String price = service.priceDisplay;

    final Widget tile = Container(
      decoration: BoxDecoration(
        color: selected ? _selectedFill : BrandColors.base,
        borderRadius: BorderRadius.circular(VelvetRadii.field),
        boxShadow: VelvetShadows.extrudedSmall,
        border: selected
            ? Border.all(color: BrandColors.accent, width: 1.5)
            : null,
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
                  style: selected ? _nameStyleSelected : _nameStyle,
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
          // Selected check badge. Wrapped in an [AnimatedSize] so it grows in
          // horizontally to the left of the price without ever changing the
          // row's height — the accordion never jumps as the selection moves.
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.centerRight,
            child: selected ? const _SelectedCheckBadge() : const SizedBox(),
          ),
          Text(price, style: _priceStyle),
        ],
      ),
    );

    // Inert (browse-only) when no tap handler is supplied — the original
    // read-only behaviour. Otherwise the whole tile is a selectable filter
    // control with a button/selected semantics node.
    if (onTap == null) {
      return Semantics(label: '$name, $duration, $price', child: tile);
    }
    return Semantics(
      button: true,
      selected: selected,
      label: '$name, $duration, $price',
      hint: selected
          ? l10n.salonServiceFilterClearHint
          : l10n.salonServiceFilterSelectHint,
      child: GestureDetector(
        key: Key('salon-service-row-${service.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: tile,
      ),
    );
  }
}

/// The small camel check badge that marks the selected service row. A raised
/// [BrandColors.accentDeep] circle with a white tick — the same accent-on-camel
/// vocabulary as the profile's other active affordances.
class _SelectedCheckBadge extends StatelessWidget {
  const _SelectedCheckBadge();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: VelvetSpacing.sm),
      child: Container(
        width: 20,
        height: 20,
        decoration: const BoxDecoration(
          color: BrandColors.accentDeep,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.check_rounded,
          size: 14,
          color: BrandColors.white,
        ),
      ),
    );
  }
}
