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
// is therefore derived from the favourites themselves — the UNION of every
// distinct [FavoriteCategory] across every item's `categories` list — which
// makes the "hide empty categories" rule fall out for free rather than being
// enforced by a count comparison.
//
// ── ONE PROVIDER, SEVERAL CHIPS ──────────────────────────────────────────
//
// Since backend commit `b0c924f`, `FavoriteItem.categories` is every distinct
// platform category the provider offers, not the single category the client
// most recently booked with them. A master offering both manicure and
// pedicure therefore appears under BOTH chips when either is selected —
// `from` unions across items, and the screen's membership test
// (`_FavoritesScreenState._viewModelFor`) checks whether the selected id is
// ANYWHERE in the item's list, not whether it equals a single scalar.
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
// Both favourites DTOs carry a `categories` list (mapped onto
// `FavoriteItem.categories` by `FavoriteMapper` — verified against the
// regenerated client, 2026-08-25), so on a real list [choices] is non-empty
// and this control renders its collapsed pill.
//
// It still renders NOTHING — [FavoritesInlineFilter] returns
// `SizedBox.shrink()` — on a client whose favourites happen to carry no
// category at all (every DTO row's `categories` empty, or every element
// missing `code` or `label`, which [FavoriteChoice.from] skips element-by-
// element; see `FavoriteMapper._categoriesFromDto`'s both-or-neither rule).
// That is the honest degradation, not a hedge: a pill that can only ever say
// «Всі», opening onto a panel holding one chip that is already selected, is a
// control promising a choice it cannot deliver — furniture that costs
// permanent vertical space on a scrolling list and answers every tap with
// nothing. The design's own rule already says a category leading nowhere is
// not drawn; a filter with zero categories is that rule at its limit.
//
// The one case this does NOT cover: a category the client is currently
// FILTERED TO that has just gone empty (its last favourite unliked, or
// pushed past `FavoriteChoice._kMaxChoices` by a reorder) while it is the
// ONLY category left in `items`. There the raw union is empty but the filter
// is still meaningfully applied, so [choices] itself still carries one entry
// — the caller (`_FavoritesScreenState._withRetainedSelection`) retains the
// selected [FavoriteChoice] past its own emptying, so this widget never has
// to special-case "selected but not really there". See that method and
// mobile-security re-audit finding 2.

import 'dart:developer';

import 'package:flutter/foundation.dart';
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

  static const String _tag = 'feature.favorites.filter';

  /// Hard ceiling on how many distinct chips [from] will ever return.
  ///
  /// `FavoriteMapper._categoriesFromDto` dedupes per item, but nothing on the
  /// wire bounds how many DISTINCT codes a buggy or hostile response can claim
  /// across every item — and every distinct choice this method returns becomes
  /// one chip inside an unconditional [Wrap] under an [AnimatedSize]
  /// (`_FavoritesInlineFilterState.build`), so an unbounded [choices] list is
  /// unbounded layout work re-run on every open/close, not merely a longer
  /// list. The bound belongs HERE rather than in the mapper: a per-item cap
  /// there would not stop the union across many items from still growing
  /// without limit, and `categories` is never rendered per-item on its own —
  /// only this union ever reaches a `Wrap`. 50 is generous against the real
  /// vocabulary (Beautica's category taxonomy is small and admin-curated) while
  /// still keeping the worst case a bounded number of chips rather than
  /// thousands.
  ///
  /// This cap bounds what THIS method returns, not what ever reaches the
  /// `Wrap`: `_FavoritesScreenState._withRetainedSelection` adds back the
  /// currently-selected choice when a reorder pushes it past this cap
  /// (mobile-security re-audit finding 2, LOW), so the actual worst case
  /// rendered is N+1, not N. One extra chip for the row the client is
  /// standing on is not the unbounded growth this cap exists to stop.
  static const int _kMaxChoices = 50;

  /// The distinct categories present across every item's [FavoriteItem.
  /// categories], unioned and deduped by id, in first-seen order.
  ///
  /// A provider can carry several categories — a master offering both
  /// manicure and pedicure contributes one chip for each. First-seen order
  /// (not alphabetical) means "first-seen across the flattened traversal": for
  /// item 0's categories, then item 1's, and so on, so the chip row still
  /// mirrors the scroll order of the list beneath it — the first NEW category
  /// encountered while scanning top to bottom is the first chip. Alphabetical
  /// would be arbitrary against a list sorted newest-saved-first.
  ///
  /// An item with an empty `categories` list contributes nothing — reachable
  /// only under «Всі» — so a list where every item carries no category yields
  /// no chips and the filter hides itself. `FavoriteMapper` already enforces
  /// both-or-neither and dedupe-by-id per element on the item itself
  /// (`_categoriesFromDto`), so this method's own dedupe only guards the
  /// cross-item union.
  static List<FavoriteChoice> from(List<FavoriteItem> items) {
    final Map<String, FavoriteChoice> seen = <String, FavoriteChoice>{};
    bool truncated = false;
    outer:
    for (final FavoriteItem item in items) {
      for (final FavoriteCategory category in item.categories) {
        if (seen.containsKey(category.id)) continue;
        if (seen.length >= _kMaxChoices) {
          // Stop scanning entirely, not just stop adding: once the cap is
          // hit there is no more layout work left to bound, only union work
          // left to skip.
          truncated = true;
          break outer;
        }
        seen[category.id] = FavoriteChoice(
          id: category.id,
          label: category.label,
        );
      }
    }
    if (truncated && kDebugMode) {
      log(
        'FavoriteChoice.from truncated at $_kMaxChoices distinct categories — '
        'the favourites response claims more distinct category codes than '
        'that across the visible items.',
        name: _tag,
        level: 900,
      );
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
  /// the caller — `_FavoritesScreenState._withRetainedSelection` — see that
  /// method) the one currently selected even if it has just emptied or been
  /// truncated past `FavoriteChoice._kMaxChoices`. This widget trusts that
  /// promise and does no retention of its own: every lookup below is a plain
  /// `choices.where(id == selectedId)`.
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
    // unliked the last categorised row, with no filter applied to retain it)
    // must not keep an empty panel expanded in the tree — it would spring
    // back the moment a chip reappeared.
    if (_open && widget.choices.isEmpty) _open = false;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.choices.isEmpty) return const SizedBox.shrink();

    final AppLocalizations l10n = AppLocalizations.of(context);
    // `widget.choices` already carries the retained selection when it has
    // dropped out of the live union — see that field's doc and
    // `_FavoritesScreenState._withRetainedSelection` — so a plain lookup is
    // enough here; this widget does no retention of its own.
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
                      // `-cat-` keeps this namespace disjoint from the
                      // hardcoded `favorites-chip-all` sentinel above: a real
                      // category code of literally `all` would otherwise
                      // collide with it.
                      key: Key('favorites-chip-cat-${c.id}'),
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
            // Same defect, worse exposure: this renders `selected?.label` —
            // the identical untrusted [FavoriteChoice.label] the chip caps
            // (`FavoriteCategoryChip`, below) — but the PILL is always
            // visible, where the chip only renders while the panel is open.
            // `sanitizeDisplayText` strips the bidi/zero-width class but not
            // `\n`/U+2028/U+2029 (a separate, recorded backlog gap; not
            // touched here), so an unbounded label would otherwise stretch
            // this pill's height (mobile-security re-audit finding 1, MEDIUM).
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
        // One line, ellipsized — matches the address block's `note`
        // convention (`ResultAddressBlock`/`favorite_cards.dart`).
        // `sanitizeDisplayText` strips the bidi/zero-width class but not
        // `\n`/U+2028/U+2029, so an unbounded label would otherwise stretch
        // this chip's height inside the `AnimatedSize` panel above.
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
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
