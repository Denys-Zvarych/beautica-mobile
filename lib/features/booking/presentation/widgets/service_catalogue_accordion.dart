// Shared catalogue accordion — extracted from `ServiceSelectorSheet` (Phase
// 14.1, independent-master booking flow) and `SalonServiceSelectionScreen`
// (Phase 14.12, salon booking flow), which had hand-copied near-identical
// `_CategorySection` / `_CategoryHeader` / `_CheckControl` /
// `_ServiceSelectTile` implementations differing only in:
//   - the domain model each operated on (`MasterService` vs
//     `SalonCatalogService`) — replaced here with the domain-agnostic
//     [CatalogueRow] projection; each screen owns a small `_toCatalogueRow`
//     mapper instead.
//   - whether the header shows a plain count / selected-count badge
//     (independent-master flow, always) or nothing in that slot (salon flow
//     — that slot used to hold a per-category tri-state "select all" pill,
//     DELETED as part of this refactor; see `showCountBadges`).
//   - a 2dp header vertical-padding difference between the two screens
//     (pre-existing, preserved via [headerVerticalPadding] rather than
//     silently normalized).
//   - whether the header's own gesture area carries a dedicated test [Key]
//     (salon flow: `salon-booking-category-<label>`; independent-master
//     flow: none — only the whole section is keyed) — see [headerKey].
//
// This file is domain-agnostic: no import of `MasterService` or
// `SalonCatalogService`. It DOES import `AppLocalizations` because the
// service-tile's accessibility label uses the SAME ICU key
// (`bookingServiceTileSemantics`) on both screens — that is not a
// screen-specific branch, just a shared string. Header semantics DO differ
// per screen (different ICU sentences entirely) and stay screen-owned via
// [CategoryHeaderSemanticsBuilder].
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

// ---------------------------------------------------------------------------
// Domain-agnostic row + category-group models
// ---------------------------------------------------------------------------

/// A single selectable catalogue row, already resolved to display strings by
/// the owning screen's mapper (`_toCatalogueRow`) — this widget tree never
/// touches `MasterService` / `SalonCatalogService` directly.
@immutable
class CatalogueRow {
  const CatalogueRow({
    required this.id,
    required this.name,
    required this.categoryLabel,
    required this.durationLabel,
    required this.priceLabel,
  });

  /// Stable selection id — the master-service assignment id for the
  /// independent-master flow, the salon catalogue service id for the salon
  /// flow. Both are booking-write-path ids already, never re-derived here.
  final String id;

  /// Fully-resolved display name (fallback-to-service-type logic, if any,
  /// already applied by the mapper).
  final String name;

  /// The category this row belongs to, kept for parity with the shape the
  /// mapper produces — not rendered inline by [CatalogueServiceTile] (the
  /// category is already conveyed by the enclosing [CatalogueCategoryGroup]).
  final String categoryLabel;

  /// Pre-formatted short duration label (e.g. "1 год 30 хв").
  final String durationLabel;

  /// Pre-formatted display price — single or a range. Always render as-is.
  final String priceLabel;
}

/// One accordion category — a stable [key] (used for expansion tracking +
/// widget keys, never re-translated) plus its display [label] and [rows].
@immutable
class CatalogueCategoryGroup {
  const CatalogueCategoryGroup({
    required this.key,
    required this.label,
    required this.rows,
  });

  final String key;
  final String label;
  final List<CatalogueRow> rows;
}

/// Builds the header's Semantics label from the section's current
/// count / selected-count / expanded state. Screen-owned because the two
/// booking flows use entirely different ICU sentences for this.
typedef CategoryHeaderSemanticsBuilder =
    String Function({
      required String label,
      required int count,
      required int selectedCount,
      required bool expanded,
    });

// ---------------------------------------------------------------------------
// Shared selection controller
// ---------------------------------------------------------------------------

/// Shared `Set<String>` selection store for a catalogue accordion screen.
/// Replaces the two screens' hand-copied `ValueNotifier<Set<String>>` field +
/// `_toggleService` method pair with one reusable primitive. Still a plain
/// [ValueNotifier], so every existing `ValueListenable<Set<String>>` /
/// `ValueListenableBuilder<Set<String>>` call site (e.g. the pinned
/// `BookingSummaryBar` shelf) keeps working unchanged.
class CatalogueSelectionController extends ValueNotifier<Set<String>> {
  CatalogueSelectionController() : super(<String>{});

  /// Toggles [id] in/out of the current selection as one atomic update.
  void toggleService(String id) {
    final Set<String> next = Set<String>.of(value);
    if (!next.remove(id)) next.add(id);
    value = next;
  }

  bool isSelected(String id) => value.contains(id);

  /// Replaces the whole selection set in one step — used by
  /// `ServiceSelectorSheet._seedOnce`'s single-service pre-selection.
  void replaceAll(Set<String> next) => value = next;

  /// Count of [ids] currently selected, without scanning the whole set.
  int selectedCountAmong(Iterable<String> ids) =>
      ids.where(value.contains).length;
}

// ---------------------------------------------------------------------------
// Category accordion section
// ---------------------------------------------------------------------------

/// One expandable category — header pillow + (while expanded) its rows.
class CatalogueCategorySection extends StatefulWidget {
  const CatalogueCategorySection({
    super.key,
    required this.category,
    required this.expanded,
    required this.selectedIdsListenable,
    required this.onToggleExpand,
    required this.onToggleService,
    required this.headerSemanticsLabel,
    required this.tileKeyForId,
    required this.headerVerticalPadding,
    this.headerKey,
    this.showCountBadges = true,
  });

  final CatalogueCategoryGroup category;
  final bool expanded;
  final ValueListenable<Set<String>> selectedIdsListenable;
  final VoidCallback onToggleExpand;
  final ValueChanged<String> onToggleService;
  final CategoryHeaderSemanticsBuilder headerSemanticsLabel;

  /// Builds this category's per-row test [Key] from a row id — the two
  /// screens use different literal prefixes (`salon_booking_service_tile_`
  /// vs `booking_service_tile_`), preserved exactly via this builder rather
  /// than normalized to one shared prefix (which would break existing test
  /// finders).
  final Key Function(String id) tileKeyForId;

  /// Vertical padding inside the header pillow — the two screens use
  /// slightly different values (pre-existing, not unified by this refactor).
  final double headerVerticalPadding;

  /// Test-facing key on the header's own gesture area. Null for the
  /// independent-master flow (only the whole section is keyed there); set to
  /// `Key('salon-booking-category-<label>')` by the salon flow.
  final Key? headerKey;

  /// Whether to render the count / selected-count badges in the header's
  /// trailing slot before the chevron. The salon flow renders `false` — that
  /// slot used to hold a per-category tri-state "select all" pill, deleted
  /// as part of this refactor, and never showed a plain count either.
  final bool showCountBadges;

  @override
  State<CatalogueCategorySection> createState() =>
      _CatalogueCategorySectionState();
}

class _CatalogueCategorySectionState extends State<CatalogueCategorySection> {
  // mobile-perf pattern (both source screens): this section only rebuilds
  // itself (via its OWN setState) when the subset of ITS OWN rows that are
  // selected actually changed — a toggle inside a sibling category is a
  // no-op here, so sibling sections never rebuild for it.
  late Set<String> _selectedInGroup;

  @override
  void initState() {
    super.initState();
    _selectedInGroup = _computeSelectedInGroup();
    widget.selectedIdsListenable.addListener(_handleSelectionChanged);
  }

  @override
  void didUpdateWidget(covariant CatalogueCategorySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIdsListenable != widget.selectedIdsListenable) {
      oldWidget.selectedIdsListenable.removeListener(_handleSelectionChanged);
      widget.selectedIdsListenable.addListener(_handleSelectionChanged);
      _selectedInGroup = _computeSelectedInGroup();
    } else if (!identical(oldWidget.category, widget.category)) {
      _selectedInGroup = _computeSelectedInGroup();
    }
  }

  @override
  void dispose() {
    widget.selectedIdsListenable.removeListener(_handleSelectionChanged);
    super.dispose();
  }

  Set<String> _computeSelectedInGroup() {
    final Set<String> selected = widget.selectedIdsListenable.value;
    return <String>{
      for (final CatalogueRow r in widget.category.rows)
        if (selected.contains(r.id)) r.id,
    };
  }

  void _handleSelectionChanged() {
    final Set<String> next = _computeSelectedInGroup();
    if (setEquals(next, _selectedInGroup)) return;
    setState(() => _selectedInGroup = next);
  }

  @override
  Widget build(BuildContext context) {
    final CatalogueCategoryGroup group = widget.category;
    final bool expanded = widget.expanded;
    final int selectedInCat = _selectedInGroup.length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        CatalogueCategoryHeader(
          key: widget.headerKey,
          label: group.label,
          count: group.rows.length,
          selectedCount: selectedInCat,
          expanded: expanded,
          onTap: widget.onToggleExpand,
          verticalPadding: widget.headerVerticalPadding,
          showCountBadges: widget.showCountBadges,
          semanticsLabel: widget.headerSemanticsLabel(
            label: group.label,
            count: group.rows.length,
            selectedCount: selectedInCat,
            expanded: expanded,
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          // Rows are only constructed while expanded — a collapsed category
          // pays no `CatalogueServiceTile` build cost at all.
          child: expanded
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (final CatalogueRow row in group.rows)
                      Padding(
                        padding: const EdgeInsets.only(top: VelvetSpacing.md),
                        child: CatalogueServiceTile(
                          key: widget.tileKeyForId(row.id),
                          row: row,
                          selected: _selectedInGroup.contains(row.id),
                          onToggle: () => widget.onToggleService(row.id),
                        ),
                      ),
                  ],
                )
              : const SizedBox(width: double.infinity, height: 0),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Category header + chevron
// ---------------------------------------------------------------------------

class CatalogueCategoryHeader extends StatelessWidget {
  const CatalogueCategoryHeader({
    super.key,
    required this.label,
    required this.count,
    required this.selectedCount,
    required this.expanded,
    required this.onTap,
    required this.semanticsLabel,
    required this.verticalPadding,
    this.showCountBadges = true,
  });

  final String label;
  final int count;
  final int selectedCount;
  final bool expanded;
  final VoidCallback onTap;
  final String semanticsLabel;
  final double verticalPadding;
  final bool showCountBadges;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      header: true,
      expanded: expanded,
      label: semanticsLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: VelvetSpacing.md,
            vertical: verticalPadding,
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
                  style: VelvetText.subheading().copyWith(fontSize: 16),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: VelvetSpacing.sm),
              if (showCountBadges) ...<Widget>[
                if (selectedCount > 0) ...<Widget>[
                  _SelectedBadge(count: selectedCount),
                  const SizedBox(width: VelvetSpacing.sm),
                ],
                _CountBadge(count: count),
                const SizedBox(width: VelvetSpacing.sm),
              ],
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

/// Plain "N services in this category" badge — independent-master flow only
/// (`showCountBadges: true`). Ported verbatim from
/// `ServiceSelectorSheet`'s former private `_CountBadge`.
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
        borderRadius: BorderRadius.circular(VelvetRadii.pill),
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

/// "N selected" badge — independent-master flow only (`showCountBadges:
/// true`). Ported verbatim from `ServiceSelectorSheet`'s former private
/// `_SelectedBadge`.
class _SelectedBadge extends StatelessWidget {
  const _SelectedBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[BrandColors.accentLatte, BrandColors.accentDeep],
        ),
        borderRadius: BorderRadius.all(Radius.circular(VelvetRadii.pill)),
        boxShadow: VelvetShadows.extrudedSmall,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: VelvetSpacing.sm,
        vertical: 3,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.check_rounded, size: 12, color: BrandColors.white),
          const SizedBox(width: 3),
          Text(
            '$count',
            style: VelvetText.feedback(
              BrandColors.white,
            ).copyWith(fontSize: 11, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Selectable service tile + depth check control
// ---------------------------------------------------------------------------

class CatalogueCheckControl extends StatelessWidget {
  const CatalogueCheckControl({super.key, required this.selected});

  final bool selected;

  static const double _size = 30;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _size,
      width: _size,
      child: selected
          ? AnimatedScale(
              scale: 1,
              duration: const Duration(milliseconds: 260),
              curve: Curves.elasticOut,
              child: Container(
                key: const ValueKey<bool>(true),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      BrandColors.accentLatte,
                      BrandColors.accentDeep,
                    ],
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Color(0xFF8C6A44),
                      offset: Offset(2, 2),
                      blurRadius: 5,
                      spreadRadius: -1,
                    ),
                    BoxShadow(
                      color: BrandColors.shadowLightStrong,
                      offset: Offset(-2, -2),
                      blurRadius: 5,
                      spreadRadius: -1,
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: BrandColors.white,
                  ),
                ),
              ),
            )
          : const NeumorphicInset(
              radius: 999,
              child: SizedBox(height: _size, width: _size),
            ),
    );
  }
}

class CatalogueServiceTile extends StatefulWidget {
  const CatalogueServiceTile({
    super.key,
    required this.row,
    required this.selected,
    required this.onToggle,
  });

  final CatalogueRow row;
  final bool selected;
  final VoidCallback onToggle;

  @override
  State<CatalogueServiceTile> createState() => _CatalogueServiceTileState();
}

class _CatalogueServiceTileState extends State<CatalogueServiceTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final CatalogueRow row = widget.row;
    final bool sel = widget.selected;

    return Semantics(
      button: true,
      checked: sel,
      label: l10n.bookingServiceTileSemantics(
        row.name,
        row.durationLabel,
        row.priceLabel,
      ),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onToggle();
        },
        child: AnimatedScale(
          scale: _pressed ? 0.985 : 1,
          duration: const Duration(milliseconds: 110),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: sel ? const Color(0xFFEDE4D5) : BrandColors.base,
              borderRadius: BorderRadius.circular(VelvetRadii.field),
              boxShadow: _pressed ? null : VelvetShadows.extrudedSmall,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: VelvetSpacing.sm + 4,
              vertical: VelvetSpacing.sm + 2,
            ),
            child: Row(
              children: <Widget>[
                CatalogueCheckControl(selected: sel),
                const SizedBox(width: VelvetSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        row.name,
                        style: VelvetText.bodyStrong(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(
                            Icons.schedule_outlined,
                            size: 12,
                            color: BrandColors.muted,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            row.durationLabel,
                            style: VelvetText.feedback(
                              BrandColors.muted,
                            ).copyWith(fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: VelvetSpacing.sm),
                Text(
                  row.priceLabel,
                  style: VelvetText.bodyStrong().copyWith(
                    color: BrandColors.accentDeep,
                    fontWeight: FontWeight.w800,
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
