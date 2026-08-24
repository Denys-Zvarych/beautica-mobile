// Phase 247 (part 1) — Promoted category / service-card widgets.
//
// PURE MOVE — no behaviour change. These widgets were private to
// `services_list_screen.dart` (Phase 5.2) and are promoted here, verbatim,
// per the REUSE-FIRST rule: Phase 247's master booking wizard needs "exactly
// the same widgets and categories" the INDEPENDENT_MASTER services page
// already uses for its service picker, and copying them would let the two
// screens drift (see this repo's `_selectRailDay` history). Promoting one
// shared source means a future fix to the card / section / badge lands on
// every screen that renders one.
//
// Promoted (dropped the leading underscore, otherwise byte-identical):
//   [CategoryGroup]       — an ordered bucket of services sharing a category.
//   [CategoryGroupEntry]  — a service paired with its continuous entrance-
//                           stagger index (structurally required by
//                           [CategoryGroup.cards] — not itself a widget, but
//                           moved alongside it since [CategoryGroup] cannot
//                           compile without it).
//   [CategorySection]     — the collapsible neumorphic disclosure section.
//   [CategoryCountBadge]  — the small recessed per-category count pill.
//   [ServiceCard]         — the tappable service row (staggered entrance).
//   [PhotoThumbnail]      — the 40×40 recessed photo/icon well.
//   [ServiceInfo]         — the card's name + inline metadata column.
//   [MetaLine]            — the compact duration · price metadata strip.
//   [MetaItem]            — a single icon + value pair inside [MetaLine].
//
// Kept private (implementation details of [ServiceCard] / [MetaLine], no
// external consumer needs them on their own):
//   [_MetaDot] — the separator dot between metadata items.
//   [_EditButton] — the trailing edit-affordance pillow.
//
// `services_list_screen.dart` is the only current caller. Part 2 of Phase 247
// adds the booking-wizard picker as an ADDITIVE consumer of these same public
// types (optional selection state / an alternate tap callback) — nothing in
// this file changes to enable that; see that phase's implementation.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/services/domain/category_slug.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/duration_minutes.dart';
import 'package:beautica_mobile/shared/formatters/service_price_display.dart';

// ---------------------------------------------------------------------------
// Category grouping — promoted from `services_list_screen.dart`'s
// `_LoadedBodyState._group` / `._resolveCategoryLabel` (Phase 247 part 2).
//
// PURE MOVE — no behaviour change. Phase 247 part 2's master booking-wizard
// service picker needs the EXACT SAME category bucketing the services page
// uses (same order, same label-resolution fallback chain), so this is
// promoted to a plain top-level function rather than re-derived — the same
// REUSE-FIRST rationale as the widget promotion above. The per-widget
// memoization cache ([_LoadedBodyState._cachedGroups] etc.) stays local to
// that State — it is a rebuild-avoidance concern specific to that screen's
// own rebuild triggers, not part of the shared algorithm.
// ---------------------------------------------------------------------------

/// Resolves a category wire slug to a display label using the same source the
/// service form uses ([approvedCategoriesProvider] — the caller supplies its
/// already-watched [categoriesAsync]):
///   • match found in the approved list → the Ukrainian `displayName`;
///   • slug absent (inactive/retired) OR the provider is still loading /
///     errored → [humanizeCategorySlug] so the user sees "Brows", never the
///     raw ALL-CAPS wire value "BROWS".
/// Returns null when [slug] is null or empty.
String? resolveCategoryLabel(
  String? slug,
  AsyncValue<List<ServiceCategoryOption>> categoriesAsync,
) {
  if (slug == null || slug.isEmpty) return null;
  final List<ServiceCategoryOption>? options = categoriesAsync.value;
  if (options != null) {
    for (final ServiceCategoryOption option in options) {
      if (categorySlugMatches(slug, option.name)) return option.displayName;
    }
  }
  return humanizeCategorySlug(slug);
}

/// Groups [services] into ordered category buckets, preserving the EXACT
/// creation order the list provider returns.
///
/// - Within a bucket, services keep their original relative order.
/// - Category buckets are ordered by the FIRST appearance of a service in
///   that category in the creation-ordered list (stable, tied to creation
///   order — never alphabetical or by price).
/// - Services with no category share a single trailing bucket keyed on the
///   empty string, labelled [uncategorizedLabel].
///
/// Each bucketed service is paired with a continuous
/// [CategoryGroupEntry.staggerIndex] (counted across section boundaries) so
/// an entrance cascade driven off it stays unbroken.
List<CategoryGroup> groupServicesByCategory({
  required List<MasterService> services,
  required AsyncValue<List<ServiceCategoryOption>> categoriesAsync,
  required String uncategorizedLabel,
}) {
  final Map<String, List<MasterService>> buckets =
      <String, List<MasterService>>{};
  for (final MasterService s in services) {
    final String key = (s.category ?? '').trim().toUpperCase();
    (buckets[key] ??= <MasterService>[]).add(s);
  }
  var cardIndex = 0;
  return buckets.entries
      .map((entry) {
        final bool isUncategorized = entry.key.isEmpty;
        final String label = isUncategorized
            ? uncategorizedLabel
            : resolveCategoryLabel(entry.key, categoriesAsync) ??
                  uncategorizedLabel;
        final List<CategoryGroupEntry> cards = <CategoryGroupEntry>[
          for (final MasterService service in entry.value)
            CategoryGroupEntry(service: service, staggerIndex: cardIndex++),
        ];
        return CategoryGroup(key: entry.key, label: label, cards: cards);
      })
      .toList(growable: false);
}

// ---------------------------------------------------------------------------
// Category grouping (plain data — not widgets)
// ---------------------------------------------------------------------------

/// A single service paired with its continuous entrance-stagger index.
///
/// [staggerIndex] is assigned in first-appearance + creation order across ALL
/// sections so the staggered fade/rise cascade is unbroken across section
/// boundaries — independent of which section the card lives in.
@immutable
class CategoryGroupEntry {
  const CategoryGroupEntry({required this.service, required this.staggerIndex});

  final MasterService service;
  final int staggerIndex;
}

/// An ordered bucket of services that share a category.
///
/// [key] is the upper-cased wire slug (or '' for uncategorized) and is used to
/// derive a stable widget key. [label] is the display-ready Ukrainian header.
/// [cards] preserve their creation order within the bucket and carry the
/// continuous stagger index for the entrance animation.
@immutable
class CategoryGroup {
  const CategoryGroup({
    required this.key,
    required this.label,
    required this.cards,
  });

  final String key;
  final String label;
  final List<CategoryGroupEntry> cards;
}

// ---------------------------------------------------------------------------
// Expandable category section
// ---------------------------------------------------------------------------

/// A soft neumorphic disclosure section: an extruded header pillow (category
/// name + count badge + rotating chevron) over a collapsible body of service
/// cards.
///
/// [initiallyExpanded] controls the initial open/close state of this section:
/// `true` starts expanded, `false` (the default) starts collapsed. The caller
/// applies this only once — the initial value is applied only once in
/// [initState]; the user can toggle freely afterward.
///
/// This is the VelvetTouch analogue of an [ExpansionTile] — no raw Material
/// chrome. The header reuses the same [BrandColors.base] + [VelvetShadows]
/// language as the cards beneath it so the page reads as one carved surface.
class CategorySection extends StatefulWidget {
  const CategorySection({
    super.key,
    required this.title,
    required this.count,
    required this.children,
    this.initiallyExpanded = false,
  });

  final String title;
  final int count;
  final List<Widget> children;

  /// Whether this section starts expanded. Applied once in [initState];
  /// the user can toggle freely afterward. Defaults to `false` (collapsed).
  final bool initiallyExpanded;

  @override
  State<CategorySection> createState() => _CategorySectionState();
}

class _CategorySectionState extends State<CategorySection> {
  // Seeded from widget.initiallyExpanded in initState.
  late bool _expanded;

  // P-M1 fix: hoisted to avoid per-build TextStyle allocation.
  static final TextStyle _headerStyle = VelvetText.subheading16;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          button: true,
          header: true,
          expanded: _expanded,
          label: l10n.servicesCategorySectionSemantics(
            widget.title,
            widget.count,
          ),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggle,
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
                      widget.title,
                      style: _headerStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: VelvetSpacing.sm),
                  CategoryCountBadge(count: widget.count),
                  const SizedBox(width: VelvetSpacing.sm),
                  AnimatedRotation(
                    // 0.25 turns = 90°: chevron points down when expanded,
                    // right when collapsed.
                    turns: _expanded ? 0.0 : -0.25,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: BrandColors.accent,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Collapsible body — AnimatedSize gives a smooth reveal/hide that keeps
        // the cards' own staggered entrance intact on first build.
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _expanded
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: widget.children,
                )
              : const SizedBox(width: double.infinity, height: 0),
        ),
      ],
    );
  }
}

/// A small recessed count badge shown on the right of a category header.
class CategoryCountBadge extends StatelessWidget {
  const CategoryCountBadge({super.key, required this.count});

  final int count;

  // Hoisted to avoid per-build allocation.
  static final TextStyle _style = VelvetText.pillSm;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: VelvetSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: BrandColors.base,
        borderRadius: BorderRadius.circular(VelvetRadii.pill),
        boxShadow: VelvetShadows.extrudedSmall,
      ),
      child: Text('$count', style: _style),
    );
  }
}

// ---------------------------------------------------------------------------
// Service card
// ---------------------------------------------------------------------------

/// A tappable service card. Extrudes at rest; depresses (scale 0.99, shadow
/// removed) on press for tactile "tap-to-edit" affordance.
///
/// Entrance animation: staggered fade + rise driven by [appearDelay].
class ServiceCard extends StatefulWidget {
  const ServiceCard({
    super.key,
    required this.service,
    required this.onEdit,
    this.appearDelay = Duration.zero,
    this.selectable = false,
    this.selected = false,
  });

  final MasterService service;

  /// Opens the edit form for this service and invalidates the category cache
  /// on return. Provided by the caller.
  ///
  /// Additive picker mode (Phase 247 part 2 — [selectable]) reuses this SAME
  /// callback as the tap handler: the master booking wizard's service-picker
  /// step passes a "select this service" callback here instead of an "open
  /// edit form" one. The name stays [onEdit] rather than gaining a second,
  /// parallel `onTap` — both are "the one thing a tap on this card does".
  final VoidCallback onEdit;

  final Duration appearDelay;

  /// Additive (Phase 247 part 2) — when `true`, swaps the trailing
  /// [_EditButton] pencil pillow for a selection indicator (a filled check
  /// when [selected], a hollow ring otherwise) and drops "Редагувати" from
  /// the accessibility label in favour of the selected/unselected state.
  /// Defaults to `false`: every pre-existing caller (the services page)
  /// passes neither this nor [selected] and renders byte-identically to
  /// before this addition.
  final bool selectable;

  /// Additive (Phase 247 part 2) — whether this card is the picker's current
  /// selection. Ignored when [selectable] is `false`. Also brightens the
  /// card's border to the accent colour, mirroring the selected-card
  /// treatment used elsewhere in the app (e.g. the approved booking-wizard
  /// preview's own `_ServiceTile.selected`).
  final bool selected;

  @override
  State<ServiceCard> createState() => _ServiceCardState();
}

class _ServiceCardState extends State<ServiceCard>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;
  late final AnimationController _appear;

  // PERF MEDIUM-1: CurvedAnimation moved from build() to initState() so a
  // new instance is not allocated on every frame. Typed as CurvedAnimation
  // (not Animation<double>) so dispose() is accessible.
  late final CurvedAnimation _curve;

  // P-H1 fix: pre-built SlideTransition offset animation. Derived from
  // _curve so it shares the same timing. FadeTransition + SlideTransition
  // are compositing-friendly — they do not create extra raster layers unlike
  // Opacity + Transform.translate.
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _appear = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
    );
    _curve = CurvedAnimation(parent: _appear, curve: Curves.easeOutCubic);
    // P-H1: derive the slide animation once here (mirrors _ProfileBody._revealWith).
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(_curve);
    if (widget.appearDelay == Duration.zero) {
      _appear.forward();
    } else {
      Future<void>.delayed(widget.appearDelay, () {
        if (mounted) _appear.forward();
      });
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _appear.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final MasterService s = widget.service;
    final durationLabel = DurationMinutes.format(s.durationMinutes);
    // Price label: FIXED renders the server-formatted priceDisplay
    // ("750 ₴"); RANGE is reformatted client-side to a hyphenated band
    // ("200 - 600 ₴") via [ServicePriceDisplay]. Falls back gracefully when
    // priceDisplay is empty (pre-V67 data / broken contract).
    final priceLabel = ServicePriceDisplay.format(s);

    // Card label rule: the master's OPTIONAL custom name REPLACES the platform
    // service-type name. When a custom name is present we show ONLY it; when it
    // is absent we fall back to the service-type name (e.g. "Стрижка"). The two
    // names are never shown together. If both are empty the label is the empty
    // string so a card is never blank / never crashes.
    //
    // M4 (contract correctness): serviceTypeNameUk is read straight off the
    // mapped MasterService; the mapper sources it from
    // MasterServiceResponse.serviceTypeNameUk (top-level, V16.3+) with a
    // ServiceDefinitionResponse.serviceTypeNameUk fallback — both confirmed
    // present in the generated DTOs. A null here means no type is assigned,
    // NOT a dropped field.
    final String typeName = (s.serviceTypeNameUk ?? '').trim();
    final String customName = s.name.trim();
    final String primaryLabel = customName.isNotEmpty ? customName : typeName;

    // P-H1 fix: FadeTransition + SlideTransition replace Opacity +
    // Transform.translate. Both transitions are compositing-friendly and
    // do not force an extra GPU raster layer per card.
    //
    // PERF: RepaintBoundary isolates this card's staggered entrance repaints so
    // the per-frame fade/slide does not invalidate sibling cards in the section.
    return RepaintBoundary(
      child: FadeTransition(
        opacity: _curve,
        child: SlideTransition(
          position: _slide,
          child: Semantics(
            button: true,
            selected: widget.selectable ? widget.selected : null,
            label: widget.selectable
                ? '$primaryLabel. $durationLabel, $priceLabel.'
                : '$primaryLabel. $durationLabel, $priceLabel. Редагувати',
            // priceLabel renders from priceDisplay (server-formatted) so the
            // accessibility label always matches what the user sees in the card.
            child: GestureDetector(
              onTapDown: (_) => setState(() => _pressed = true),
              onTapCancel: () => setState(() => _pressed = false),
              onTapUp: (_) {
                setState(() => _pressed = false);
                widget.onEdit();
              },
              child: AnimatedScale(
                scale: _pressed ? 0.99 : 1.0,
                duration: const Duration(milliseconds: 110),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    color: BrandColors.base,
                    borderRadius: BorderRadius.circular(VelvetRadii.card),
                    // FIX B (mobile-debugger, this session) — DIM, never
                    // fully remove, the shadow on press: see
                    // `VelvetShadows.extrudedCardPressed`'s doc for why a
                    // `null` target here produced a visible background
                    // flicker on a normal (sub-150ms) tap.
                    boxShadow: _pressed
                        ? VelvetShadows.extrudedCardPressed
                        : VelvetShadows.extrudedCard,
                    // Additive (Phase 247 part 2): a picker-mode selected card
                    // gets an accent hairline, mirroring the selected-card
                    // treatment used elsewhere in the app. `null` (every
                    // pre-existing caller) renders no border at all.
                    border: (widget.selectable && widget.selected)
                        ? Border.all(color: BrandColors.accent, width: 1.5)
                        : null,
                  ),
                  // Compact dense row: tighter vertical padding (~halved height)
                  // versus the original VelvetSpacing.sm + 2 with a stacked pill
                  // Wrap below the title.
                  padding: const EdgeInsets.fromLTRB(
                    VelvetSpacing.sm + 2,
                    VelvetSpacing.sm,
                    VelvetSpacing.sm + 2,
                    VelvetSpacing.sm,
                  ),
                  child: Row(
                    children: <Widget>[
                      PhotoThumbnail(key: Key('thumb_${s.id}')),
                      const SizedBox(width: VelvetSpacing.sm + 2),
                      Expanded(
                        child: ServiceInfo(
                          name: primaryLabel,
                          durationLabel: durationLabel,
                          priceLabel: priceLabel,
                        ),
                      ),
                      const SizedBox(width: VelvetSpacing.sm),
                      widget.selectable
                          ? _SelectIndicator(
                              key: Key('service_card_check_${s.id}'),
                              selected: widget.selected,
                            )
                          : const _EditButton(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Photo thumbnail (no-photo placeholder — service photo deferred to Phase 9.x)
// ---------------------------------------------------------------------------

/// 40×40 recessed inset well with a centred camel spa icon.
///
/// Compact-row sizing (was 48×48) so the dense list fits more rows on screen.
/// When actual photo upload is implemented (Phase 9.x), this widget will
/// accept a `photoUrl` and render an [Image.network] inside the same
/// 40×40 rounded [ClipRRect]. Until then, every service shows the icon
/// placeholder so depth always comes from shadows, never a flat grey box.
class PhotoThumbnail extends StatelessWidget {
  const PhotoThumbnail({super.key});

  static const double _size = 40;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _size,
      width: _size,
      child: NeumorphicInset(
        radius: VelvetRadii.field,
        child: Center(
          child: Icon(
            Icons.spa_rounded,
            size: 18,
            color: BrandColors.accent.withValues(alpha: 0.9),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Service info (name + pills)
// ---------------------------------------------------------------------------

class ServiceInfo extends StatelessWidget {
  const ServiceInfo({
    super.key,
    required this.name,
    required this.durationLabel,
    required this.priceLabel,
  });

  /// Card label — the master's custom name when present, otherwise the platform
  /// service-type name. The two names are never shown together.
  final String name;

  final String durationLabel;
  final String priceLabel;

  // Hoisted to avoid per-build allocation (MEDIUM-3).
  static final TextStyle _nameStyle = VelvetText.svcCardName;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          name,
          // Compact row: single line, slightly smaller than the full cardTitle
          // so the dense list reads as rows rather than tall cards.
          style: _nameStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: VelvetSpacing.xs),
        // Inline duration · price metadata line. The category is shown as the
        // section header the card lives under, not here.
        MetaLine(durationLabel: durationLabel, priceLabel: priceLabel),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Inline metadata line (replaces the stacked inset pills for density)
// ---------------------------------------------------------------------------

/// A compact, single-line metadata strip: a duration glyph + value, a thin
/// divider dot, and a price glyph + value.
///
/// Overflow-safe: the whole strip clips with an ellipsis if the row is narrow.
class MetaLine extends StatelessWidget {
  const MetaLine({
    super.key,
    required this.durationLabel,
    required this.priceLabel,
  });

  final String durationLabel;
  final String priceLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        MetaItem(icon: Icons.schedule_rounded, value: durationLabel),
        const _MetaDot(),
        Flexible(
          child: MetaItem(icon: Icons.sell_rounded, value: priceLabel),
        ),
      ],
    );
  }
}

/// A small icon + value pair used inside [MetaLine]. Compact glyph (13) and
/// the existing [VelvetText.pill] tone, but flat (no inset well).
class MetaItem extends StatelessWidget {
  const MetaItem({super.key, required this.icon, required this.value});

  final IconData icon;
  final String value;

  // Hoisted to avoid per-build allocation (MEDIUM-3).
  static final TextStyle _valueStyle = VelvetText.pillSm;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 13, color: BrandColors.accent),
        const SizedBox(width: VelvetSpacing.xs),
        Flexible(
          child: Text(
            value,
            style: _valueStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// A thin separator dot between metadata items.
class _MetaDot extends StatelessWidget {
  const _MetaDot();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.sm - 2),
      child: Container(
        width: 3,
        height: 3,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: BrandColors.accent.withValues(alpha: 0.55),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Trailing edit button
// ---------------------------------------------------------------------------

/// 30×30 neumorphic raised pillow with the edit icon. Signals tap-to-edit.
///
/// Compact-row sizing (was 32×32). The whole row remains the tap target for
/// edit, so this remains a non-interactive affordance glyph.
class _EditButton extends StatelessWidget {
  const _EditButton();

  // Hoisted: VelvetRadii.field is a compile-time constant.
  static const BorderRadius _radius = BorderRadius.all(
    Radius.circular(VelvetRadii.field),
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      width: 30,
      decoration: const BoxDecoration(
        color: BrandColors.base,
        borderRadius: _radius,
        boxShadow: VelvetShadows.extrudedSmall,
      ),
      child: const Icon(
        Icons.edit_outlined,
        color: BrandColors.accent,
        size: 16,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Picker-mode selection indicator (Phase 247 part 2)
// ---------------------------------------------------------------------------

/// Additive [ServiceCard] trailing glyph for picker mode ([ServiceCard.
/// selectable]) — a filled accent check when [selected], a hollow ring
/// otherwise. Replaces [_EditButton] one-for-one so the trailing slot never
/// changes size between the two modes.
class _SelectIndicator extends StatelessWidget {
  const _SelectIndicator({super.key, required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    if (selected) {
      return const Icon(
        Icons.check_circle_rounded,
        color: BrandColors.accentDeep,
        size: 26,
      );
    }
    return Container(
      height: 22,
      width: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: BrandColors.accent.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
    );
  }
}
