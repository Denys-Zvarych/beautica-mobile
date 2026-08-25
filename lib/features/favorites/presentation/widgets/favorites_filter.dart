// Phase 111 (old 13.10) — the «Улюблені» category filter (design variant C).
//
// Ported from `docs/signup-designs/ClientFavorites/lib/widgets/
// favorites_filter.dart`. One pill naming the current state; tapping it lays
// every category out in place, and choosing one collapses it again.
//
// ── WHY NOT A CHIP RAIL ─────────────────────────────────────────────────────
//
// A horizontal rail's options are hidden inside its own scroll: you cannot see
// how many categories exist, or whether the one you want is off-screen, without
// dragging — and that sideways drag sits directly on top of the vertical scroll
// the whole screen is built around. This control costs 2px less permanent
// height than the rail did (44 + 10 gap vs 46 + 10) and never asks for a
// sideways gesture.
//
// ── NOTHING HERE DISPLAYS A NUMBER ──────────────────────────────────────────
//
// Counts are read from the data, but only to decide what to SHOW: a category
// with nothing saved in it is not rendered, so every chip you can see leads
// somewhere. The one exception is the chip you are standing on, which stays put
// even at zero, so unliking the last row in a category never yanks the filter
// out from under you. The «N збережених · N майстрів · N салони» composition
// line that used to sit above this control was removed by user decision
// (2026-08-24); the only digits on this screen are DATA — a rating and a
// building number.
//
// ── THE PANEL OPENS IN PLACE, NEVER OVER THE LIST ───────────────────────────
//
// It pushes the rows down while open and springs back on choose, so the options
// never cover the content they filter. Clearing never needs the panel at all,
// because «Скинути» sits beside the collapsed pill.
//
// ── THE CATEGORY VOCABULARY COMES FROM THE DATA, NOT A CONST LIST ───────────
//
// The preview hardcoded a seven-entry `kFavCategories` with a glyph each. That
// cannot ship: production categories are server-owned and admin-editable (see
// `approvedCategoriesProvider`), so a frozen client-side list would silently
// drop any category an admin adds and mislabel any they rename. [FavoriteChoice]
// is therefore derived from the favourites themselves — every distinct
// (`categoryId`, `categoryLabel`) pair present in the list — which makes the
// "hide empty categories" rule fall out for free rather than being enforced by
// a count comparison.
//
// ONE CONSEQUENCE, FLAGGED RATHER THAN ABSORBED: the chips carry no per-
// category glyph, because a server-owned category has no icon field and this
// app has no shared `categoryIconFor`. It has TWO private, already-drifted
// ones — `booking_card.dart`'s exact-match switch and
// `beauty_timeline_section.dart`'s substring matcher, which disagree on «Вії»
// and on their fallback — so writing a third would fork the glyph vocabulary a
// third time, and unifying them changes what two SHIPPED screens render (a
// visual diff needing its own review, not a move). The collapsed pill keeps a
// single generic `tune_rounded` glyph so the control still reads as a filter
// at rest; the chips are label-only, and selection is carried by depth
// polarity and colour exactly as the preview specified. Re-adding per-category
// glyphs is a follow-up gated on a reconciled shared icon helper.
//
// ── WHAT MAKES THE CONTROL RENDER NOTHING ───────────────────────────────────
//
// Both favourites DTOs carry a category (`categoryCode`/`categoryLabel`,
// mapped onto `categoryId`/`categoryLabel` by `FavoriteMapper` — verified
// against the regenerated client, 2026-08-25), so on a real list [choices] is
// non-empty and this control renders its collapsed pill.
//
// It still renders NOTHING — [FavoritesInlineFilter] returns
// `SizedBox.shrink()` — on a client whose favourites happen to carry no
// category at all (every DTO row missing `categoryCode` or `categoryLabel`,
// which [FavoriteChoice.from] folds to a dropped pair; see
// `FavoriteMapper._categoryOrNull`'s both-or-neither rule). That is the honest
// degradation, not a hedge: a pill that can only ever say «Всі», opening onto
// a panel holding one chip that is already selected, is a control promising a
// choice it cannot deliver — furniture that costs permanent vertical space on
// a scrolling list and answers every tap with nothing. The design's own rule
// already says a category leading nowhere is not drawn; a filter with zero
// categories is that rule at its limit.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

import '../../domain/favorite_item.dart';

/// One selectable category, derived from the favourites actually present.
@immutable
class FavoriteChoice {
  const FavoriteChoice({required this.id, required this.label});

  final String id;
  final String label;

  /// The distinct categories present in [items], in first-seen order.
  ///
  /// First-seen order (not alphabetical) so the chip row mirrors the scroll
  /// order of the list beneath it: the category of the row you can see at the
  /// top is the first chip. Alphabetical would be arbitrary against a list
  /// sorted newest-saved-first.
  ///
  /// A favourite with no `categoryId` contributes nothing, so an all-null list
  /// yields no chips and the filter hides itself. A category with an id but no
  /// label is skipped too: a chip the client cannot read is not a choice.
  /// `FavoriteMapper` already enforces both-or-neither on the item itself
  /// (`_categoryOrNull`), so in practice this only guards against a
  /// half-formed pair reaching this method some other way.
  static List<FavoriteChoice> from(List<FavoriteItem> items) {
    final Map<String, FavoriteChoice> seen = <String, FavoriteChoice>{};
    for (final FavoriteItem item in items) {
      final String? id = item.categoryId;
      final String? label = item.categoryLabel;
      if (id == null || label == null || label.isEmpty) continue;
      seen.putIfAbsent(id, () => FavoriteChoice(id: id, label: label));
    }
    return seen.values.toList(growable: false);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FavoriteChoice && other.id == id && other.label == label;

  @override
  int get hashCode => Object.hash(id, label);
}

/// The inline expanding category filter.
///
/// Renders nothing at all when [choices] is empty — see the file header.
class FavoritesInlineFilter extends StatefulWidget {
  const FavoritesInlineFilter({
    super.key,
    required this.choices,
    required this.selectedId,
    required this.onSelect,
  });

  /// The categories that have at least one favourite in them, plus (kept by
  /// the caller) the one currently selected even if it has just emptied.
  final List<FavoriteChoice> choices;

  /// `null` → «Всі» (no filter).
  final String? selectedId;

  final ValueChanged<String?> onSelect;

  @override
  State<FavoritesInlineFilter> createState() => _FavoritesInlineFilterState();
}

class _FavoritesInlineFilterState extends State<FavoritesInlineFilter> {
  bool _open = false;

  static const Duration _expand = Duration(milliseconds: 220);
  static const Curve _expandCurve = Curves.easeOutCubic;

  void _choose(String? id) {
    widget.onSelect(id);
    setState(() => _open = false);
  }

  @override
  void didUpdateWidget(FavoritesInlineFilter oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A filter that loses every choice while its panel is open (the client
    // unliked the last categorised row) must not keep an empty panel expanded
    // in the tree — it would spring back the moment a chip reappeared.
    if (_open && widget.choices.isEmpty) _open = false;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.choices.isEmpty) return const SizedBox.shrink();

    final AppLocalizations l10n = AppLocalizations.of(context);
    final FavoriteChoice? selected = widget.selectedId == null
        ? null
        : widget.choices
              .where((FavoriteChoice c) => c.id == widget.selectedId)
              .firstOrNull;

    return AnimatedSize(
      duration: _expand,
      curve: _expandCurve,
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                _StatePill(
                  label: selected?.label ?? l10n.favoritesFilterAll,
                  open: _open,
                  onTap: () => setState(() => _open = !_open),
                ),
                const Spacer(),
                // Clearing is one tap from the COLLAPSED state — you never
                // have to open the control to get back to everything.
                if (selected != null)
                  Semantics(
                    button: true,
                    label: l10n.favoritesFilterResetLabel,
                    child: GestureDetector(
                      key: const Key('favorites-filter-reset'),
                      onTap: () => _choose(null),
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.all(VelvetSpacing.sm),
                        child: Text(
                          l10n.favoritesFilterReset,
                          style: VelvetText.link(),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (_open) ...<Widget>[
              const SizedBox(height: VelvetSpacing.sm + 2),
              Wrap(
                spacing: VelvetSpacing.sm + 2,
                runSpacing: VelvetSpacing.sm + 2,
                children: <Widget>[
                  FavoriteCategoryChip(
                    key: const Key('favorites-chip-all'),
                    label: l10n.favoritesFilterAll,
                    selected: widget.selectedId == null,
                    onTap: () => _choose(null),
                  ),
                  for (final FavoriteChoice c in widget.choices)
                    FavoriteCategoryChip(
                      key: Key('favorites-chip-${c.id}'),
                      label: c.label,
                      selected: widget.selectedId == c.id,
                      onTap: () => _choose(c.id),
                    ),
                ],
              ),
              const SizedBox(height: VelvetSpacing.xs),
            ],
          ],
        ),
      ),
    );
  }
}

/// The collapsed control: the active category's name plus a chevron.
///
/// It is the filter's only permanent furniture, so it STATES the current filter
/// rather than offering a choice — «Всі» when nothing is applied.
class _StatePill extends StatelessWidget {
  const _StatePill({
    required this.label,
    required this.open,
    required this.onTap,
  });

  final String label;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Widget content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: VelvetSpacing.md - 2,
        vertical: VelvetSpacing.sm + 1,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.tune_rounded, size: 17, color: BrandColors.accent),
          const SizedBox(width: VelvetSpacing.sm - 1),
          Text(
            label,
            style: VelvetText.favFilterLabel.copyWith(
              color: BrandColors.accentDeep,
            ),
          ),
          const SizedBox(width: VelvetSpacing.sm - 1),
          AnimatedRotation(
            turns: open ? 0.5 : 0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: const Icon(
              Icons.expand_more_rounded,
              size: 18,
              color: BrandColors.muted,
            ),
          ),
        ],
      ),
    );

    return Semantics(
      button: true,
      expanded: open,
      label: l10n.favoritesFilterPillLabel(label),
      child: GestureDetector(
        key: const Key('favorites-filter-pill'),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: BrandColors.base,
            borderRadius: BorderRadius.circular(VelvetRadii.field),
            // Open = pressed IN. The shadow is dropped and the inset painter
            // takes over, so the pill reads as the thing currently being held
            // down rather than as a second raised sibling of its own chips.
            boxShadow: open ? null : VelvetShadows.extrudedSmall,
          ),
          child: open
              ? NeumorphicInset(radius: VelvetRadii.field, child: content)
              : content,
        ),
      ),
    );
  }
}

/// A category chip in the expanded panel: raised pill at rest, pressed INTO the
/// surface when active. Same anatomy as the category chips on the search
/// screens, so the client never meets two chip languages for one concept.
class FavoriteCategoryChip extends StatelessWidget {
  const FavoriteCategoryChip({
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
    final Widget content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: VelvetSpacing.md - 2,
        vertical: VelvetSpacing.sm + 1,
      ),
      child: Text(
        label,
        style: VelvetText.favFilterLabel.copyWith(
          color: selected ? BrandColors.accentDeep : BrandColors.textSecondary,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
        ),
      ),
    );

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: BrandColors.base,
            borderRadius: BorderRadius.circular(VelvetRadii.field),
            boxShadow: selected ? null : VelvetShadows.extrudedSmall,
          ),
          child: selected
              ? NeumorphicInset(radius: VelvetRadii.field, child: content)
              : content,
        ),
      ),
    );
  }
}
