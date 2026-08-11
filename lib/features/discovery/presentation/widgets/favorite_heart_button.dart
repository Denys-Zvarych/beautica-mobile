// Phase 13.4 — Favorite heart toggle (shared by master + salon result cards).
//
// Watches the [favoriteToggleProvider] slice for ONE target and renders
// a filled/outlined heart that scales on toggle (ported from the approved
// preview's `_HeartButton`). Tapping flips the flag optimistically via the
// notifier; on error the notifier reverts the flag and this widget calls
// [onError] so the host screen can show a snackbar.
//
// It primes the notifier with [initialIsFavorite] on first build (the search
// payload carries no favorited flag yet, so cards seed `false`) — a later seed
// never stomps a user toggle (see [FavoriteToggleNotifier.primeIfAbsent]).
//
// ## Tap-target floor — fixed, by the overlay technique ONLY
//
// mobile-security finding (MEDIUM): this heart's hit area used to be its
// painted 24dp icon plus a `VelvetSpacing.xs` (4dp) LEFT-only pad —
// exactly 28×24dp, ASYMMETRIC (padding on one edge only), and below the
// Android 48dp / iOS 44pt floor (WCAG 2.5.5 / Material / HIG). Same defect
// `wishlist_heart_button.dart`'s `WishlistHeartButton` had, fixed there by
// growing to a full 48×48 via `Padding`.
//
// That 28×24 is this widget's HISTORICAL INLINE FOOTPRINT — the baseline
// every caller's placeholder slot is sized against (see below). It is the
// shape committed to `main`, i.e. what the golden baselines in
// `test/golden/discovery_result_card_golden_test.dart` were captured from.
//
// Growing the pad INLINE is not available to any caller this widget has:
// each renders it as the LAST child of a `Row` whose `Expanded` name/meta
// column pays dp-for-dp for the growth (the heart's right edge is already
// pinned to the row's own right bound, so no sibling follows it to absorb
// the extra width). An earlier attempt did exactly that — a partial 32×36
// inline pad, sold as "free" — and it silently cost every one of those
// columns 4dp, wrapping the master result card's name onto a SECOND LINE at
// 320dp. Caught only by the discovery golden suite, and only after the fact.
// Do not reintroduce it, and do not size any placeholder against it.
//
// The shipped fix takes this widget OUT of the `Row` entirely. Each caller
// leaves an inert placeholder of the ORIGINAL 28×24 footprint as that Row's
// last child — so the `Expanded` column's width is byte-identical to the
// committed pre-fix tree, not merely to some intermediate draft — and
// renders this widget in a `Stack` overlay floating over that slot. The
// extra 20dp/24dp the full box needs spills into the caller's OWN padding
// instead of coming out of a sibling. Two implementations of that single
// technique:
//   - `favorite_heart_overlay.dart`'s `FavoriteHeartOverlay` — the shared
//     widget, used by `salon_result_card.dart` and `master_result_card.dart`.
//   - `service_catalogue_accordion.dart`'s `CatalogueServiceTile` — its own
//     inline `Stack` (which the shared widget was factored out of), proven
//     by `catalogue_service_tile_favorite_heart_tap_target_test.dart`:
//     48×48 box, all four edges hittable, row selection still wins
//     everywhere outside it.
//
// Consequently this widget has ONE mode. It ALWAYS pads symmetrically to
// `_kFullMinTapExtent` (48dp) on both axes — same shape as
// `WishlistHeartButton`'s fix, just against this button's own 24dp icon
// instead of that one's 32dp target. There is deliberately no opt-out flag:
// a caller that cannot afford a 48dp box in its Row must use the overlay,
// not a smaller heart.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';

import '../../../favorites/application/favorite_toggle_notifier.dart';
import '../../../favorites/domain/favorite_target.dart';

// The one and only tap target this widget renders — see the file header.
// Symmetric on both axes, same shape as `WishlistHeartButton`'s `_kTapPad`,
// just against this button's own icon size.
const double _kFullMinTapExtent = 48;
const double _kFullTapPad =
    (_kFullMinTapExtent - FavoriteHeartButton.iconSize) / 2;

/// A tappable favourite heart bound to [target] via the toggle notifier.
class FavoriteHeartButton extends ConsumerStatefulWidget {
  const FavoriteHeartButton({
    super.key,
    required this.target,
    required this.semanticAddLabel,
    required this.semanticRemoveLabel,
    this.initialIsFavorite = false,
    this.onError,
  });

  /// The master/salon this heart toggles.
  final FavoriteTarget target;

  /// Accessibility label when the heart is currently NOT favorited (tapping
  /// adds it).
  final String semanticAddLabel;

  /// Accessibility label when the heart IS favorited (tapping removes it).
  final String semanticRemoveLabel;

  /// Seed flag used the first time this target is seen by the notifier.
  final bool initialIsFavorite;

  /// Invoked with the localized error message when a toggle fails (and the
  /// notifier has already reverted the optimistic flag).
  final void Function(Failure failure)? onError;

  /// This button's painted icon size — public so a caller sizing the
  /// placeholder slot its overlay floats over (see `FavoriteHeartOverlay.
  /// slotWidth` / `slotHeight` and `CatalogueServiceTile`'s
  /// `_kHeartSlotWidth`) derives that slot from one source instead of
  /// restating the literal.
  ///
  /// NOTE for anyone computing a slot from this: the historical inline
  /// footprint those slots must reproduce is `iconSize + VelvetSpacing.xs`
  /// wide (LEFT-only pad) by `iconSize` tall (no vertical pad) — NOT this
  /// widget's current [_kFullTapPad]-based rendered size, and NOT the
  /// abandoned 32×36 intermediate. See the file header.
  static const double iconSize = 24;

  @override
  ConsumerState<FavoriteHeartButton> createState() =>
      _FavoriteHeartButtonState();
}

class _FavoriteHeartButtonState extends ConsumerState<FavoriteHeartButton> {
  @override
  void initState() {
    super.initState();
    // Seed the flag after the first frame so we don't mutate a provider during
    // build. primeIfAbsent never overwrites an existing (possibly toggled) flag.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(favoriteToggleProvider.notifier)
          .primeIfAbsent(widget.target, isFavorite: widget.initialIsFavorite);
    });
  }

  Future<void> _onTap() async {
    final Failure? failure = await ref
        .read(favoriteToggleProvider.notifier)
        .toggle(widget.target);
    if (failure != null) widget.onError?.call(failure);
  }

  @override
  Widget build(BuildContext context) {
    // Watch only this target's entry — so an unrelated card's toggle never
    // rebuilds this heart. An absent target reads hard `false`: the notifier
    // prunes settled `false` entries (and skips priming them), so absence
    // unambiguously means "not favorited". The non-false seed is still stored by
    // primeIfAbsent, so a `true` initial flag is honoured until the user toggles.
    final bool isFavorite = ref.watch(
      favoriteToggleProvider.select(
        (Map<FavoriteTarget, FavoriteEntry> m) =>
            m[widget.target]?.isFavorite ?? false,
      ),
    );

    return Semantics(
      button: true,
      label: isFavorite ? widget.semanticRemoveLabel : widget.semanticAddLabel,
      child: GestureDetector(
        onTap: _onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          // Symmetric `_kFullTapPad` on both axes — a genuine 48×48 hit box,
          // unconditionally. Every call site renders this widget inside a
          // `Stack` overlay, so the box costs no sibling any width; see the
          // file header for why no smaller variant exists.
          padding: const EdgeInsets.all(_kFullTapPad),
          child: AnimatedScale(
            scale: isFavorite ? 1.0 : 0.92,
            duration: const Duration(milliseconds: 150),
            child: Icon(
              isFavorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              color: isFavorite ? BrandColors.error : BrandColors.faint,
              size: FavoriteHeartButton.iconSize,
            ),
          ),
        ),
      ),
    );
  }
}
