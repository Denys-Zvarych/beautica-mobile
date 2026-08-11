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
//
// Phase 240 — per-row favourite heart, MASTER FLOW ONLY (at the time). Added
// `showFavoriteHeart` to [CatalogueCategorySection], following the EXACT
// precedent `showCountBadges` already set for a per-flow trailing-slot
// difference: `ServiceSelectorSheet` (independent-master flow) turned it on
// because its [CatalogueRow.id] IS a real `master_services` row id;
// `SalonServiceSelectionScreen` left it `false` (the default) because its rows
// were the SALON's catalogue mapped into the same shape, whose id is a
// salon-catalogue-service id — not a real `master_services` id, and favouriting
// with the wrong target type would send an id/type pair the backend had never
// heard of.
//
// Phase E — the backend now supports a distinct `SALON_SERVICE` favorite
// target type keyed to `service_definitions.id` (which the salon flow's row
// id already IS, per `salon_mapper.dart`), so the salon flow can now turn the
// heart on too. Added `favoriteTargetType` (defaulting to
// `FavoriteTargetType.service`, the master flow's existing behaviour) to both
// [CatalogueServiceTile] and [CatalogueCategorySection] so each flow's rows
// favourite against the correct target type; `showFavoriteHeart` still gates
// whether the heart renders at all.
//
// This pulls in [FavoriteHeartButton] from `features/discovery/presentation/
// widgets/` — a cross-feature PRESENTATION import, which the repo's usual rule
// reserves for `domain/`/`shared/` only. Deliberate exception: the alternative
// (moving or forking the button) was explicitly ruled out — reuse it verbatim,
// unmodified, from wherever it already lives. [FavoriteTarget] is a `domain/`
// import and needs no such carve-out.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/discovery/presentation/widgets/favorite_heart_button.dart';
import 'package:beautica_mobile/features/favorites/domain/favorite_target.dart';
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
    this.showFavoriteHeart = false,
    this.favoriteTargetType = FavoriteTargetType.service,
    this.favoriteServiceIds = const <String>{},
    this.onFavoriteError,
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

  /// Whether each row in this category renders a [FavoriteHeartButton] in its
  /// trailing slot. OPT-IN per flow, mirroring [showCountBadges]. Ignored
  /// (never renders) unless true.
  final bool showFavoriteHeart;

  /// The [FavoriteTarget.type] each row's heart favourites against. Defaults
  /// to [FavoriteTargetType.service] (the independent-master flow's row id —
  /// a `master_services` assignment id). The salon flow passes
  /// [FavoriteTargetType.salonService] — see the file header. Ignored when
  /// [showFavoriteHeart] is false.
  final FavoriteTargetType favoriteTargetType;

  /// Row ids ([CatalogueRow.id]) already in the wish list, used to prime each
  /// row's heart to its filled state on first build. Ignored when
  /// [showFavoriteHeart] is false.
  final Set<String> favoriteServiceIds;

  /// Forwarded to every row's [FavoriteHeartButton.onError]. Ignored when
  /// [showFavoriteHeart] is false.
  final void Function(Failure failure)? onFavoriteError;

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
                        // Isolates each row's PRESS/SELECT animations from its
                        // siblings. `CatalogueServiceTile`'s outermost widget
                        // is an `AnimatedScale` (0.985 on press) wrapping an
                        // `AnimatedContainer` (200ms decoration on select);
                        // without a boundary here their `markNeedsPaint` walks
                        // straight past this `Column` and up to the enclosing
                        // `SliverList`'s per-SECTION boundary (see the layer
                        // -cost note below, which states the same fact),
                        // repainting every sibling row's blurred
                        // `extrudedSmall` shadow.
                        //
                        // MEASURED with `debugOnProfilePaint`, 3 rows, one row
                        // pressed, 14 frames:
                        //   without: siblings 13/14 frames, 1443 nodes painted
                        //   with:    siblings  0/14 frames,  351 nodes painted
                        //
                        // NOT for the favourite heart — that was the finding as
                        // originally filed, and it is already false: the heart's
                        // own `RepaintBoundary` (in the `Stack` overlay below)
                        // stops its 150ms `AnimatedScale` three hops above the
                        // button, so no tile repaints at all. Measured 0/14 for
                        // every row, animating one included. This boundary would
                        // have bought nothing for that case; it earns its layer
                        // on the press/select path instead.
                        //
                        // Layer cost is bounded: sections already sit in a
                        // `SliverList.separated`, which wraps each SECTION in
                        // its own `RepaintBoundary`, so this adds one layer per
                        // ROW of an expanded category — a handful, not a list.
                        child: RepaintBoundary(
                          child: CatalogueServiceTile(
                            key: widget.tileKeyForId(row.id),
                            row: row,
                            selected: _selectedInGroup.contains(row.id),
                            onToggle: () => widget.onToggleService(row.id),
                            showFavoriteHeart: widget.showFavoriteHeart,
                            favoriteTargetType: widget.favoriteTargetType,
                            isFavorite: widget.favoriteServiceIds.contains(
                              row.id,
                            ),
                            onFavoriteError: widget.onFavoriteError,
                          ),
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
                  style: VelvetText.subheading16,
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
        style: VelvetText.bookFeedback125w800.copyWith(
          color: BrandColors.textSecondary,
        ),
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
          Text('$count', style: VelvetText.bookFeedbackWhite11w800),
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

// Phase [heart 48dp overlay] — `CatalogueServiceTile`'s favourite heart
// needs a genuine 48×48 tap target (Android floor / iOS 44pt) WITHOUT
// shrinking the name/meta `Expanded` column, which growing the heart
// INLINE in the `Row` cannot avoid (it is the Row's last child — see
// `favorite_heart_button.dart`'s own file header for the full cost
// accounting). The fix: the `Row` keeps a plain placeholder sized to the
// heart's OLD inline footprint (so the `Expanded` column's width is
// byte-identical to before), and the real, tappable heart is rendered by a
// `Stack` overlay ON TOP of the tile, positioned over that placeholder's
// slot — see `_CatalogueServiceTileState.build`.
//
// `_kHeartSlotWidth` restates the heart's HISTORICAL inline footprint
// (painted icon + its LEFT-ONLY `VelvetSpacing.xs` pad) as a formula over
// already-named tokens, not a bare literal — this is the width value the
// `Row`'s placeholder must reserve, regardless of what tap-target size the
// overlay itself now uses.
//
// Mirrors `FavoriteHeartOverlay.slotWidth`
// (`features/discovery/presentation/widgets/favorite_heart_overlay.dart`) —
// that is the shared source for this formula; restated rather than imported
// so this booking-flow file does not pull a discovery *widget* in just for a
// constant (it already imports `favorite_heart_button.dart` for the button
// and [FavoriteHeartButton.iconSize], which is enough).
//
// The baseline is the COMMITTED tree, deliberately. An abandoned draft
// widened this heart's inline pad to a symmetric `xs` (32dp footprint) and
// this slot followed it — silently costing the `Expanded` name column 4dp.
// Its sibling result cards had a golden suite that caught the equivalent
// loss; this tile did not, so the regression here was invisible. See
// `favorite_heart_button.dart`'s file header.
const double _kHeartSlotWidth = FavoriteHeartButton.iconSize + VelvetSpacing.xs;

// The Android 48dp / iOS 44pt tap-target floor (WCAG 2.5.5 / Material /
// HIG) — restated locally rather than imported from
// `favorite_heart_button.dart`'s own private `_kFullMinTapExtent`, same
// "public spec number, not the widget's own constant" rationale that
// constant's neighbouring test files already use.
const double _kHeartHitExtent = 48;

// The tile's own `AnimatedContainer` horizontal padding (see
// `_CatalogueServiceTileState.build`'s `padding:` below) — named here too
// so the overlay's centering formula below reads as a derivation, not a
// coincidence.
const double _kTileHorizontalPad = VelvetSpacing.sm + 4;

// How far the overlay's 48dp box's RIGHT edge sits from the Stack's own
// right edge, so the box's CENTER lands exactly where the heart's ICON used
// to paint inline.
//
// The anchor is the ICON's historical centre, NOT the centre of the
// [_kHeartSlotWidth] placeholder that replaced it — those are 2dp apart and
// conflating them is a bug this file already shipped once. The heart's
// committed `Padding` was `EdgeInsets.only(left: xs)`, LEFT-ONLY, and as the
// `Row`'s last child its right edge was pinned to the row's right bound: the
// icon painted FLUSH RIGHT inside its 28dp footprint with all 4dp of slack on
// the left. Centering the box on the slot instead drags the painted heart 2dp
// left of where it shipped — geometrically invisible (every rect assertion
// still passes), caught on the sibling result cards only as an 88-pixel
// golden diff. This tile has no golden, so the derivation below is its only
// guard; see `favorite_heart_overlay.dart`'s `build` for the same reasoning.
//
//   icon centre, measured from the tile's right edge
//     = _kTileHorizontalPad + FavoriteHeartButton.iconSize / 2
//   box centre must equal that, and the box is `_kHeartHitExtent` wide, so
//   its right edge sits `_kHeartHitExtent / 2` closer to the tile's edge
//   than its own centre:
//
// This currently evaluates to 12 + 12 - 24 = EXACTLY 0.0 — the box is flush
// with the tile's trailing edge, which is correct here (and is why the tap-
// target test pins the right edge geometrically instead of probing 2dp
// outside it: there is no room left on that side). But it is one dp of slack
// away from going NEGATIVE: any future shrink of [_kTileHorizontalPad] yields
// a negative const that `Padding` rejects only in debug. [_kMinTileHorizontalPad]
// names that floor and `_CatalogueServiceTileState.build` asserts it.
const double _kHeartOverlayRightInset =
    _kTileHorizontalPad +
    FavoriteHeartButton.iconSize / 2 -
    _kHeartHitExtent / 2;

// The smallest [_kTileHorizontalPad] the overlay technique above supports —
// the value at which [_kHeartOverlayRightInset] reaches exactly zero.
// = (48 - 24) / 2 = 12dp, which is precisely what the tile pads today.
// Mirrors `FavoriteHeartOverlay.minContainerPad`, restated locally for the
// same reason `_kHeartHitExtent` is.
const double _kMinTileHorizontalPad =
    (_kHeartHitExtent - FavoriteHeartButton.iconSize) / 2;

class CatalogueServiceTile extends StatefulWidget {
  const CatalogueServiceTile({
    super.key,
    required this.row,
    required this.selected,
    required this.onToggle,
    this.showFavoriteHeart = false,
    this.favoriteTargetType = FavoriteTargetType.service,
    this.isFavorite = false,
    this.onFavoriteError,
  });

  final CatalogueRow row;
  final bool selected;
  final VoidCallback onToggle;

  /// Renders a [FavoriteHeartButton] targeting `(favoriteTargetType, row.id)`
  /// in the row's trailing slot when true — see
  /// [CatalogueCategorySection.showFavoriteHeart].
  final bool showFavoriteHeart;

  /// The [FavoriteTarget.type] this row's heart favourites against. See
  /// [CatalogueCategorySection.favoriteTargetType]. Ignored when
  /// [showFavoriteHeart] is false.
  final FavoriteTargetType favoriteTargetType;

  /// Primes the heart's initial filled/outline state. Ignored when
  /// [showFavoriteHeart] is false.
  final bool isFavorite;

  /// Forwarded to [FavoriteHeartButton.onError]. Ignored when
  /// [showFavoriteHeart] is false.
  final void Function(Failure failure)? onFavoriteError;

  @override
  State<CatalogueServiceTile> createState() => _CatalogueServiceTileState();
}

class _CatalogueServiceTileState extends State<CatalogueServiceTile> {
  bool _pressed = false;

  // Hoisted so `build()` — which re-runs on every `_pressed` setState, i.e.
  // twice per tap — does not allocate a fresh TextStyle each time.
  //
  // Phase [meta-line price relocation]: the price used to sit in the top row
  // at `VelvetText.bodyStrong()` weight (visually a peer of the service
  // name). It now lives on the meta line ahead of the duration, so it takes
  // the duration's own style (`VelvetText.feedbackMutedSm` — same family,
  // weight, size as the clock-icon label right next to it, per the user's
  // explicit "font as on time" ask) and keeps ONLY an accent recolour via
  // `.copyWith(color:)` so the figure stays legible against the plain
  // duration text beside it.
  static final TextStyle _priceStyle = VelvetText.feedbackMutedSm.copyWith(
    color: BrandColors.accentDeep,
  );

  // perf/security audit, ROUND 2 (2026-08-10), on the `Text.rich` meta line
  // the round-1 fix (see below, kept for history) landed:
  //   - finding 1 (MEDIUM, mobile-security, empirically reproduced): a
  //     single `maxLines: 1` paragraph gives the WHOLE line one shared
  //     truncation budget. Duration sits LAST in span order, so under real
  //     pressure (240dp width, textScale 1.6, a long RANGE price) it isn't
  //     partially clipped — `getBoxesForSelection` for the duration
  //     substring returns `[]`: the duration paints ZERO glyphs. A client
  //     is shown a price and an ellipsis with no duration at all for a
  //     service they are about to book.
  //   - finding 2 (LOW, mobile-perf): any `WidgetSpan` in a paragraph forces
  //     `RenderParagraph`'s two-pass inline-placeholder layout (measure
  //     placeholder intrinsics, then re-run line-breaking) — strictly more
  //     work than a plain `Icon` sibling, paid on every tile the
  //     `ListView.builder` recycles during scroll, not just on tap. The old
  //     `Row` never paid this.
  // Fixed by replacing the merged `Text.rich` with a `Wrap` holding two
  // independent children — [price] and an [icon, duration] group. In the
  // normal (unconstrained) case both fit on one run and `Wrap.spacing`
  // supplies the "visual separation" the design calls for, so the ` · `
  // glyph is dropped entirely rather than kept and suppressed — this also
  // permanently closes round 1's finding 2 (the bare-separator semantics
  // announcement) instead of merely working around it, since there is no
  // longer a separator TEXT NODE of any kind to announce. Under pressure,
  // the icon+duration group drops to its OWN run instead of sharing a line
  // budget with price: whichever child doesn't fit the current run starts a
  // fresh one and is then the ONLY thing on it, so it gets the run's full
  // width. The price `Text` is a DIRECT `Wrap` child, so `Wrap` itself
  // constrains it to the run's available width and its own `maxLines: 1`/
  // `ellipsis` engages as a per-figure safety valve (a price that alone
  // still overflows the tile's full width ellipsises independently instead
  // of throwing). The duration `Text` sits one level deeper, inside the
  // icon-pairing `Row`; without a `Flexible` wrapper that inner `Row` would
  // hand it UNBOUNDED width (a `Row(mainAxisSize: min)` with no
  // `Expanded`/`Flexible` child reports its unconstrained natural size, not
  // the `Wrap` run's constraint) and `maxLines`/`ellipsis` would never have
  // a finite width to truncate against — so the duration `Text` is wrapped
  // in `Flexible` to receive the same bounded-width treatment as price. No
  // figure can be squeezed to zero by the OTHER figure the way a shared
  // paragraph budget allowed — see
  // `service_catalogue_accordion_overflow_test.dart`'s
  // `'duration still paints when the price is long and pressure is high'`
  // and `'pathologically long duration ellipsises instead of overflowing'`.
  // No `WidgetSpan` anywhere, so `RenderParagraph`'s placeholder pass never
  // runs for this line — one plain `Icon` render object, same as the old
  // `Row`.
  //
  // Round-1 rationale (kept for history — the ONE-`Text.rich` fix that
  // introduced the two findings above): the meta line used to be a
  // `Row(mainAxisSize: min)` with NO `Expanded`/`Flexible` child and no
  // `maxLines`/`overflow` on either `Text` — a wide RANGE price or long
  // duration at a high textScaleFactor could throw a genuine `RenderFlex`
  // overflow (mobile-perf, mobile-security both flagged it independently).
  // Folding price + separator + duration into one bounded text box traded
  // that RenderFlex-overflow crash for TextPainter truncation and dropped
  // the separator's own semantics fragment — at the cost of the two
  // problems fixed above. Rejected this round: going back to that bare
  // `Row` verbatim — it is the ORIGINAL bug (an unweighted `Row` can starve
  // either figure to nothing depending on which happens to be longer);
  // `Flexible` on both `Text`s in a `Row` was considered too (both shrink
  // together, neither vanishes) but `Wrap` was preferred because dropping a
  // whole figure to its own line at extreme widths keeps it at FULL
  // available width rather than a shrunk share of a shared line, and it
  // removes the separator glyph's semantics question outright instead of
  // requiring an `ExcludeSemantics` wrapper to re-suppress it.
  Widget _metaLine(CatalogueRow row) {
    return Wrap(
      // Test-support key — see the sibling note on the name `Text` above;
      // lets the overflow-guard regression test locate this line
      // independently of the name.
      key: Key('catalogue-service-meta-${row.id}'),
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: VelvetSpacing.xs,
      runSpacing: 2,
      children: <Widget>[
        Text(
          row.priceLabel,
          style: _priceStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.only(right: 3),
              child: Icon(
                Icons.schedule_outlined,
                size: 12,
                color: BrandColors.muted,
              ),
            ),
            // `Flexible` (not a bare `Text`) is load-bearing here: a
            // `Row(mainAxisSize: min)` with no flex child hands its `Text`
            // UNBOUNDED width, so `maxLines: 1`/`ellipsis` below never gets
            // a finite width to truncate against and a pathological
            // duration throws `RenderFlex overflowed` instead of
            // ellipsising — see the class-level comment above `_metaLine`.
            Flexible(
              child: Text(
                row.durationLabel,
                style: VelvetText.feedbackMutedSm,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final CatalogueRow row = widget.row;
    final bool sel = widget.selected;

    // Row selection + the tile's own visuals — UNCHANGED shape from before
    // this fix, except the favourite heart's trailing slot is now a plain,
    // inert placeholder (see `_kHeartSlotWidth`'s doc comment above) rather
    // than the `FavoriteHeartButton` itself. This keeps the Expanded name/
    // meta column's width byte-identical to the pre-overlay tree.
    //
    // The `Semantics` annotation lives HERE, wrapping the tile's own
    // `GestureDetector`, and NOT around the `Stack` below. Above the `Stack`
    // it would take this gesture and the heart's into one merge group, which
    // Flutter resolves by refusing to merge either — leaving this annotation
    // with `isButton`/`hasCheckedState` but no `tap` action, and the node
    // that IS tappable with no role and no checked state. Verified by
    // semantics dump against the `showFavoriteHeart: false` control, which
    // renders the single correct node. See `favorite_heart_overlay.dart`'s
    // "SEMANTICS CONTRACT" header section.
    //
    // It carries `button` + `checked` and NOTHING ELSE — deliberately no
    // `label:`. This annotation merges its descendants, which already
    // announce every field, so an explicit label repeated the whole tile:
    // «Стрижка жіноча, 1 год 30 хв, 850 ₴ / Стрижка жіноча / 850 ₴ / 1 год
    // 30 хв» (verified by semantics dump, both here and at `HEAD` — this is
    // a PRE-EXISTING defect, not one this change introduced; it is
    // byte-identical with `showFavoriteHeart: false`). Let the content
    // supply the label — the standard Flutter pattern, and the same fix the
    // two result cards took. Guarded by
    // `catalogue_service_tile_favorite_heart_tap_target_test.dart`'s
    // single-occurrence assertion.
    //
    // ANNOUNCEMENT ORDER — deliberately source order: name → PRICE →
    // duration, where the dropped label read name → duration → price. The
    // two are not reconcilable without either (a) reordering `_metaLine`'s
    // `Wrap` children, which would move the price BEHIND the duration
    // visually — the exact opposite of the locked design decision recorded
    // above `_priceStyle` («price ahead of the duration», the user's own
    // "font as on time" ask) and a guaranteed golden diff; or (b) bolting
    // `OrdinalSortKey`s onto the column's children purely to re-sequence a
    // merged label. Neither is worth it: the merged announcement is
    // complete and unambiguous either way, and every field is still stated
    // exactly once. `bookingServiceTileSemantics` itself stays — it is still
    // the label source for `booking_recap.dart` and
    // `selected_services_shelf.dart`, which do NOT merge a descendant tree.
    final Widget tileBody = Semantics(
      button: true,
      checked: sel,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onToggle();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: sel ? const Color(0xFFEDE4D5) : BrandColors.base,
            borderRadius: BorderRadius.circular(VelvetRadii.field),
            boxShadow: _pressed ? null : VelvetShadows.extrudedSmall,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: _kTileHorizontalPad,
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
                      // Test-support key (same precedent as
                      // `booking_card.dart`'s `ValueKey('service-$id')`) —
                      // lets the overflow-guard regression test measure
                      // this Text's laid-out width directly, to prove the
                      // favourite heart's trailing slot costs the name
                      // ONLY its own footprint now that price no longer
                      // shares this row (see
                      // `service_catalogue_accordion_overflow_test.dart`).
                      key: Key('catalogue-service-name-${row.id}'),
                      style: VelvetText.bodyStrong(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    _metaLine(row),
                  ],
                ),
              ),
              if (widget.showFavoriteHeart) ...<Widget>[
                const SizedBox(width: VelvetSpacing.xs),
                // Inert placeholder — reserves the heart's OLD inline
                // footprint so the `Expanded` column above is unaffected.
                // The real, tappable heart is the `Stack` overlay below,
                // NOT this box (it paints nothing and has no gesture).
                const SizedBox(width: _kHeartSlotWidth),
              ],
            ],
          ),
        ),
      ),
    );

    // `Stack`, not the `Row` above, is where the heart actually lives now —
    // see `_kHeartSlotWidth`'s doc comment. `tileBody` paints FIRST (so its
    // own `GestureDetector` stays the row-selection tap target everywhere)
    // and the heart paints LAST (on top), so it wins hit-tests inside its own
    // 48×48 box. `clipBehavior: Clip.none` because that box is deliberately
    // wider than the placeholder slot it centers on and spills into the
    // tile's own padding — a clipped hit area would silently defeat this fix
    // (see `catalogue_service_tile_favorite_heart_tap_target_test.dart`).
    //
    // NOTE the `Stack` carries NO `Semantics` — `tileBody` already does. See
    // that annotation above, and `favorite_heart_overlay.dart`'s "SEMANTICS
    // CONTRACT" header section, for why an annotation here instead strands
    // the tile's own `tap` action.
    //
    // The message is BRANCHED on which clause actually tripped. It used to
    // state both causes unconditionally ("... is negative. ... is below the
    // minimum ..."), so whichever half did not fire read as a false claim
    // about the live constants — half-wrong every single time it fired.
    assert(
      !widget.showFavoriteHeart ||
          (_kHeartOverlayRightInset >= 0 &&
              _kTileHorizontalPad >= _kMinTileHorizontalPad),
      _kHeartOverlayRightInset < 0
          ? '_kHeartOverlayRightInset is $_kHeartOverlayRightInset — '
                'negative. Padding rejects a negative inset in debug only, '
                'and it would anyway mean the 48dp hit box cannot sit inside '
                'the tile without overhanging its outer edge. Deliberately '
                'an assert rather than a math.max(0, ...) clamp: a clamp '
                'would quietly mis-place the heart instead of naming the '
                'unsupported geometry.'
          : '_kTileHorizontalPad is $_kTileHorizontalPad, below the minimum '
                'of $_kMinTileHorizontalPad. A pad that small cannot fit the '
                '48dp hit box inside the tile without overhanging its outer '
                'edge. Deliberately an assert rather than a math.max(0, ...) '
                'clamp: a clamp would quietly mis-place the heart instead of '
                'naming the unsupported padding.',
    );

    final Widget pressTarget = widget.showFavoriteHeart
        ? Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              tileBody,
              Positioned.fill(
                child: Align(
                  // Direction-aware: the `Row` above reverses under RTL, so
                  // the placeholder slot moves to the visual left. A
                  // hard-coded `Alignment.centerRight` would leave the heart
                  // pinned to the visual right, on the opposite side of the
                  // tile from the slot it is meant to cover. Latent today
                  // (`uk` + `en` are both LTR) and cheap to keep correct.
                  alignment: AlignmentDirectional.centerEnd,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(
                      end: _kHeartOverlayRightInset,
                    ),
                    // The heart runs a 150ms `AnimatedScale` on every toggle.
                    // Without this boundary that animation dirties the shared
                    // layer and repaints the whole tile beneath it — its
                    // `AnimatedContainer` decoration, blurred `extrudedSmall`
                    // shadow and both text runs — once per frame for the whole
                    // animation.
                    //
                    // It sits BELOW the `Align`/`Padding`, directly around the
                    // button, deliberately. Above them it was laid out under
                    // `Positioned.fill`'s TIGHT constraints and expanded to
                    // the whole tile — a tile-sized isolated layer for a 48×48
                    // payload. Isolation is identical either way (a
                    // `markNeedsPaint` from the button walks to the FIRST
                    // repaint-boundary ancestor and stops; `Align` and
                    // `Padding` are not boundaries, so that ancestor is this
                    // node in both placements) — the layer is just exactly
                    // sized now. Verified by walking `debugNeedsPaint` up from
                    // the button after a toggle: true on this boundary, false
                    // on every ancestor above it.
                    child: RepaintBoundary(
                      child: FavoriteHeartButton(
                        key: Key('booking_service_heart_${row.id}'),
                        target: FavoriteTarget(
                          type: widget.favoriteTargetType,
                          id: row.id,
                        ),
                        initialIsFavorite: widget.isFavorite,
                        semanticAddLabel: l10n.favoriteServiceAddLabel,
                        semanticRemoveLabel: l10n.favoriteServiceRemoveLabel,
                        onError: widget.onFavoriteError,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          )
        : tileBody;

    // The press animation wraps the `Stack` — body AND heart — rather than
    // sitting inside `tileBody`. Moving the heart into a `Stack` sibling had
    // left it OUTSIDE this `AnimatedScale`, so pressing the row visibly
    // shrank the tile to 0.985 while the heart stayed put: a cosmetic drift
    // from the pre-overlay look, in which the heart was an inline `Row` child
    // and scaled with everything else. Hoisting the scale restores that.
    // Safe for the overlay's hit box: a `Transform` does not affect LAYOUT at
    // all (so the 218.0/250.0dp name-column pins and the box's derived right
    // inset are untouched), and it only alters hit-test coordinates while
    // `_pressed` is true — i.e. while a finger is already down on the tile
    // body, never at rest, which is the only state the heart's 48×48 probes
    // measure.
    return AnimatedScale(
      scale: _pressed ? 0.985 : 1,
      duration: const Duration(milliseconds: 110),
      child: pressTarget,
    );
  }
}
