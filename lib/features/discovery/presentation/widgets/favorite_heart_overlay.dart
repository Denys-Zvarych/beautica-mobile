// Phase [heart 48dp overlay, result cards] — generic Stage-2 overlay,
// factored out for `salon_result_card.dart` and `master_result_card.dart`.
//
// Both cards have the identical structural problem `CatalogueServiceTile`
// (`service_catalogue_accordion.dart`) solved first: their
// [FavoriteHeartButton] is the trailing child of a `Row` whose `Expanded`
// name/meta column would pay dp-for-dp for any inline width growth (see
// `favorite_heart_button.dart`'s file header, "Stage 2" section, for the full
// derivation this widget restates generically). This widget is that same
// fix, lifted out so the two cards do not each hand-roll their own copy of
// the `Stack`/`Positioned.fill`/`Align`/`Padding` arithmetic.
//
// [body] paints FIRST — its own `GestureDetector` (the card's navigate-on-tap
// gesture) stays the tap target everywhere outside the heart's box — and the
// heart overlay paints LAST (on top), so it wins hit-tests inside its own
// 48×48 box. `clipBehavior: Clip.none` because that box is deliberately wider
// than the placeholder slot it centers on and spills into [body]'s own
// padding — a clipping ancestor would silently defeat this fix. Verified
// absent for both current callers: neither `NeumorphicCard` (`clipContent`
// defaults to false — see `core/widgets/neumorphic.dart`) nor the enclosing
// `ListView.separated` in `search_results_screen.dart` clips per-item
// content, only the scroll viewport itself.
//
// VERTICAL anchor — NOT the tile's shape. `CatalogueServiceTile`'s `Row` has
// no explicit `crossAxisAlignment` (defaults to `center`), so its overlay
// centers the heart vertically. Both `salon_result_card.dart` and
// `master_result_card.dart` set `crossAxisAlignment: CrossAxisAlignment.
// start` on their `Row` — the heart used to be TOP-aligned (flush with the
// name's top edge), not centered on the card. This widget anchors
// `Alignment.topRight` and insets from the top by the same derivation the
// horizontal inset uses (see [build]), so the heart's vertical position is
// preserved exactly — confirmed against the pre-fix golden captures in
// `test/golden/discovery_result_card_golden_test.dart`: an early draft that
// used `centerRight` (this widget's first cut, copied verbatim from the
// tile) visibly dropped the heart to mid-card height, caught only by
// re-running that golden suite, not by any widget test's rect assertions.
//
// CONTRACT for any caller: keep the [FavoriteHeartButton] OUT of the `Row` it
// used to render inline in, replacing it with a
// `SizedBox(width: FavoriteHeartOverlay.slotWidth)` placeholder as that Row's
// last child (so the sibling `Expanded` column's width is byte-identical to
// the COMMITTED pre-fix tree — see [slotWidth]'s doc for why that baseline,
// and not an intermediate draft, is the one that counts), then wrap the WHOLE
// tappable subtree — the `GestureDetector` and everything inside it,
// including the padded container the `Row` lives in — as [body] here. The
// caller's `Row` must use `crossAxisAlignment: CrossAxisAlignment.start` and
// its container must pad ALL FOUR sides equally by [containerPad] — the only
// shape this widget currently supports (both current callers share it via
// `NeumorphicCard(padding: EdgeInsets.all(...))`). [containerPad] must also be
// at least [minContainerPad]; see that constant and the constructor's assert.
//
// SEMANTICS CONTRACT — [body] must carry its OWN `Semantics`; NEVER wrap this
// widget in one.
// ---------------------------------------------------------------------------
// A `Semantics` placed ABOVE this overlay takes the card's tap-carrying
// `GestureDetector` AND the heart's into one merge group. Flutter's
// `_marksConflictsInMergeGroup` then refuses to merge either into the
// annotation and forces both into their own child nodes — stranding the
// ancestor with the `isButton`/`checked` flags and NO action, while the node
// that IS tappable carries no role at all. TalkBack/VoiceOver then announce a
// button that cannot be activated. Verified by semantics dump: with the
// annotation outside, node #4 had `flags: isButton` and no `actions:` line;
// moving the same annotation inside [body] restored the single
// `actions: tap, flags: isButton, label: ...` node plus a separate heart node.
// So: annotate INSIDE [body] (around its `GestureDetector`), and hand this
// widget the already-annotated subtree.
//
// That split existed only in this widget's INTERMEDIATE draft (annotation
// above the overlay) — NOT on `main`. An earlier revision of this note, and
// of both callers', claimed the committed tree's heart gesture had suppressed
// the descendant merge outright, leaving the callers' `label:` stutter
// "dormant" until the overlay armed it. That is disproved: re-dumping the
// semantics tree from the three lib files at `HEAD` shows `main` ALREADY
// merged and ALREADY stuttered («Олена Коваль / Олена Коваль / Печерський,
// Київ / …») on a node that ALREADY carried `actions: tap` + `isButton`. So
// the callers dropping `label:` fixed a PRE-EXISTING defect; it did not clean
// up one this change armed.
//
// ACCEPTED TRADE — the heart's box overlaps the name column by 8dp.
// ---------------------------------------------------------------------------
// The 48dp box is 20dp wider than the [slotWidth] placeholder it centres on;
// 12dp of that spills right into the card's own [containerPad], and the
// remaining 8dp spills LEFT, over the `Expanded` name column's trailing edge
// (on `CatalogueServiceTile` the same arithmetic leaves 4dp). Because the
// overlay paints last it also wins hit-tests there, so a tap on the last ~8dp
// of a long, ellipsised name toggles the favourite instead of opening the
// profile. This is a DELIBERATE decision, not an oversight: the only way to
// remove the overlap is to shrink the box back under the Android 48dp / iOS
// 44pt floor (WCAG 2.5.5), which is the exact defect this widget exists to
// fix. An 8dp strip of an ellipsis tail is a far smaller harm than a
// permanently sub-floor tap target for every motor-impaired user, so the
// overlap is accepted. Do NOT "fix" it by shrinking the box.
//
// LOAD-BEARING INVARIANT — [body] must fill its own width.
// ---------------------------------------------------------------------------
// `Stack` defaults to `StackFit.loose`, which LOOSENS the incoming constraints
// for its non-positioned children — [body] is laid out with `minWidth: 0`
// rather than the tight width it received before this widget was introduced.
// That is inert today ONLY because both callers' [body] bottoms out in a `Row`
// with the default `MainAxisSize.max`, which expands to the incoming
// `maxWidth` regardless. A future caller whose [body] does NOT fill its width
// (a `MainAxisSize.min` row, an `IntrinsicWidth`, a bare `Text`) will silently
// COLLAPSE the card to its intrinsic width — and the overlay, sized off the
// `Stack`, drifts with it. If such a caller ever appears, pass
// `fit: StackFit.passthrough` rather than debugging the collapse downstream.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';

import '../../../favorites/domain/favorite_target.dart';
import 'favorite_heart_button.dart';

/// Wraps [body] in a `Stack` with a floating [FavoriteHeartButton] overlay —
/// a full 48×48 hit box, that widget's only mode — centered on the inline
/// placeholder slot [body] reserves in its own trailing `Row` child.
/// See the file header for the full contract.
class FavoriteHeartOverlay extends StatelessWidget {
  const FavoriteHeartOverlay({
    super.key,
    required this.body,
    required this.containerPad,
    required this.heartKey,
    required this.target,
    required this.semanticAddLabel,
    required this.semanticRemoveLabel,
    this.initialIsFavorite = false,
    this.onError,
  }) : assert(
         containerPad >= minContainerPad,
         'FavoriteHeartOverlay.containerPad is $containerPad, below the '
         'minimum of $minContainerPad. Both insets in build() are '
         '`containerPad + iconSize / 2 - hitExtent / 2`, so a smaller pad '
         'makes them NEGATIVE — which Padding only rejects in debug, and '
         'which would anyway mean the 48dp box cannot fit inside the card '
         'without overhanging its outer edge. Deliberately an assert rather '
         'than a math.max(0, ...) clamp: a clamp would quietly mis-place the '
         'heart for a caller whose shape this technique does not support.',
       );

  /// The card's own tappable content, painted first.
  final Widget body;

  /// The padding, EQUAL on all four sides, between [body]'s own outer
  /// bounding box and the `Row` it wraps — i.e. the inset the placeholder
  /// slot's top-right corner sits behind. Both current callers pass
  /// `VelvetSpacing.md`, matching their shared
  /// `NeumorphicCard(padding: EdgeInsets.all(VelvetSpacing.md))`.
  final double containerPad;

  /// Forwarded to the overlay's [FavoriteHeartButton] as its own [Key].
  final Key heartKey;

  final FavoriteTarget target;
  final String semanticAddLabel;
  final String semanticRemoveLabel;
  final bool initialIsFavorite;
  final void Function(Failure failure)? onError;

  /// The inline placeholder width a caller's `Row` must reserve — the
  /// heart's HISTORICAL inline footprint, i.e. the icon plus the LEFT-ONLY
  /// `VelvetSpacing.xs` pad it shipped with on `main` (28dp), restated as a
  /// formula over already-named tokens rather than a bare literal.
  ///
  /// The baseline here is the COMMITTED tree, deliberately — not the
  /// abandoned 32×36 "partial inline fix" draft. Sizing this slot against
  /// that draft instead cost every caller's `Expanded` column 4dp and
  /// wrapped the master result card's name onto a second line at 320dp;
  /// `test/golden/discovery_result_card_golden_test.dart` is the guard.
  /// Same value as `service_catalogue_accordion.dart`'s private
  /// `_kHeartSlotWidth` — same footprint, same baseline.
  static const double slotWidth =
      FavoriteHeartButton.iconSize + VelvetSpacing.xs;

  // The Android 48dp / iOS 44pt tap-target floor (WCAG 2.5.5 / Material /
  // HIG) — restated locally rather than imported from
  // `favorite_heart_button.dart`'s own private `_kFullMinTapExtent`, same
  // "public spec number, not the widget's own constant" rationale
  // `service_catalogue_accordion.dart`'s `_kHeartHitExtent` already uses.
  static const double _hitExtent = 48;

  /// The smallest [containerPad] this technique supports — the value at which
  /// [build]'s `containerPad + iconSize / 2 - _hitExtent / 2` insets reach
  /// exactly zero (the heart's box flush with the card's outer edge). Below
  /// it the insets go negative; the constructor asserts against this.
  /// = (48 - 24) / 2 = 12dp. Both current callers pass `VelvetSpacing.md`
  /// (16dp), 4dp of headroom.
  static const double minContainerPad =
      (_hitExtent - FavoriteHeartButton.iconSize) / 2;

  @override
  Widget build(BuildContext context) {
    // The box must center on where the ICON HISTORICALLY PAINTED — NOT on
    // the centre of the [slotWidth] placeholder that replaced it. Those two
    // points are not the same, and assuming they were is a bug this file
    // already shipped once:
    //
    //   The heart's committed `Padding` was `EdgeInsets.only(left: xs)` —
    //   LEFT-ONLY. As the `Row`'s last child its right edge was pinned to
    //   the row's right bound, so the ICON painted FLUSH RIGHT inside its
    //   28dp footprint, with all 4dp of slack on the left. The slot's centre
    //   therefore sits 2dp LEFT of the icon's centre. Centering the box on
    //   the slot dragged the painted heart 2dp left of where it shipped —
    //   invisible to every geometric assertion, caught only as an 88-pixel
    //   diff (two 2×22 strips) by
    //   `test/golden/discovery_result_card_golden_test.dart`.
    //
    // So both insets derive from the icon's own historical rect, which is
    // flush to the content box's top-right corner on both axes (top-only
    // because the callers' `Row` is `CrossAxisAlignment.start` and that
    // `Padding` added no vertical pad at all):
    //   icon centre, in from [body]'s right/top edge
    //     = containerPad + iconSize / 2
    //   the box is `_hitExtent` on each axis, so its own right/top edge sits
    //   `_hitExtent / 2` closer to the corner than its centre.
    // [slotWidth] is deliberately absent from this formula — it sizes the
    // `Row`'s placeholder, nothing else.
    //
    // Both are DIRECTION-AWARE (`AlignmentDirectional.topEnd` /
    // `EdgeInsetsDirectional.only(end:)`), because the callers' `Row`s are: a
    // `Row` reverses its children under RTL, so the placeholder slot moves to
    // the visual LEFT while a hard-coded `Alignment.topRight` would leave the
    // heart pinned to the visual right — the overlay and the slot it is
    // supposed to cover landing on opposite sides of the card. Latent today
    // (`supportedLocales` is `uk` + `en`, both LTR) and cheap to keep correct.
    const double iconHalf = FavoriteHeartButton.iconSize / 2;
    final double endInset = containerPad + iconHalf - _hitExtent / 2;
    final double topInset = containerPad + iconHalf - _hitExtent / 2;

    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        body,
        Positioned.fill(
          child: Align(
            alignment: AlignmentDirectional.topEnd,
            child: Padding(
              padding: EdgeInsetsDirectional.only(top: topInset, end: endInset),
              // The heart runs a 150ms `AnimatedScale` on every toggle.
              // Without this boundary that animation dirties the shared layer
              // and repaints [body] underneath it — the card's thumbnail, text
              // runs and neumorphic shadows — once per frame for the whole
              // animation.
              //
              // It sits BELOW the `Align`/`Padding`, directly around the
              // button, deliberately. Above them it was laid out under
              // `Positioned.fill`'s TIGHT constraints and expanded to the
              // whole card — a card-sized isolated layer for a 48×48 payload.
              // Isolation is identical either way (a `markNeedsPaint` from the
              // button walks to the FIRST repaint-boundary ancestor and stops;
              // `Align` and `Padding` are not boundaries, so that ancestor is
              // this node in both placements) — the layer is just exactly
              // sized now. Verified by walking `debugNeedsPaint` up from the
              // button after a toggle: true on this boundary, false on every
              // ancestor above it.
              child: RepaintBoundary(
                child: FavoriteHeartButton(
                  key: heartKey,
                  target: target,
                  initialIsFavorite: initialIsFavorite,
                  semanticAddLabel: semanticAddLabel,
                  semanticRemoveLabel: semanticRemoveLabel,
                  onError: onError,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
