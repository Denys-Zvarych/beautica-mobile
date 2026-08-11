// Phase 238 — the wish list's un-favourite affordance.
//
// Transcribed from the approved preview
// `docs/signup-designs/BeautyPassport/lib/widgets/passport_widgets.dart`
// (`WishlistHeartButton`), with the preview's `PreviewSizes`/`PreviewMotion`
// values resolved to this file's own named constants and its hardcoded
// Ukrainian semantics label routed through the ARB.
//
// ## Why this one control gets a micro-interaction
//
// It is the ONLY genuinely destructive, genuinely user-managed action on the
// passport page — everything else there is derived and read-only. The pop is
// what tells the client the tap landed, in the beat before the entry animates
// away and the list re-flows underneath it. Per-row motion was deliberately not
// added anywhere else on the page; boldness is spent here and nowhere else.
//
// ## The pop is FIRE-AND-FORGET, and the widget survives its own removal
//
// [onTap] fires from inside an async gap, and this widget's host is a list entry
// that the very same tap is about to unmount. So the `mounted` guard after the
// await is load-bearing rather than ceremonial: without it, the second
// `setState` runs against a disposed `State` whenever the parent rebuilds fast
// enough to drop the row before the pop finishes.
//
// The callback fires AFTER the over-scale and with the shrink already
// scheduled, so the removal reads as "pressed, then gone" rather than as a
// widget vanishing under the finger with no acknowledgement.
//
// ## The 48dp tap target does not overlap a neighbour at either call site
//
// This widget's hit area is 16dp bigger than its painted 32dp icon on every
// edge combined (see `_kTapPad` below), and it always renders inside a
// `Row` alongside other content, so growing it is only safe because BOTH
// call sites were checked, not assumed:
//
//   * `wishlist_row.dart` — last child of the header `Row`, after the
//     avatar + `Expanded` text column. That `Row` sits inside a bare
//     `HubFlatCard(child: ...)` with no `onTap` supplied, so the card is
//     NOT itself tappable — there is no container-level gesture for an
//     expanded heart to steal taps from. The only cost is 16dp less width
//     for the `Expanded` service/master-name column, which
//     `wishlist_row_test.dart`'s pinned column-width arithmetic accounts
//     for (`_kNameColumn360` moved from 202 to 186 — see that file).
//   * `wishlist_compact_card.dart` — header `Row` is `[HubAvatar, Spacer,
//     WishlistHeartButton]`, also inside a bare, non-tappable `HubFlatCard`.
//     The `Spacer` absorbs the extra 16dp; nothing below the header row is
//     tappable at that same horizontal band either (the title/attribution
//     text and duration/price `Wrap` carry no gesture of their own).
//
// Neither row has a sibling `GestureDetector`/`InkWell` for the expanded box
// to encroach on, which is what makes this widget's INLINE `Padding` fix
// affordable. Contrast `FavoriteHeartButton`
// (`features/discovery/presentation/widgets/favorite_heart_button.dart`):
// all three of its callers (`salon_result_card.dart`,
// `master_result_card.dart`, and `CatalogueServiceTile` in the booking flow)
// sit as the LAST child of a Row whose `Expanded` sibling would pay
// dp-for-dp for any inline growth, so none of them can take this widget's
// approach. They reach the SAME full 48×48 by a different mechanism — a
// `Stack` overlay outside the row's normal flow, floating over an inert
// placeholder sized to the heart's historical inline footprint. See that
// button's own file header for the full derivation, including why the
// intermediate "grow it inline a little" variant was reverted.

import 'package:flutter/material.dart';

import '../../../../core/theme/brand_colors.dart';
import '../../../../l10n/app_localizations.dart';

/// The filled heart that removes an entry from the wish list.
///
/// Filled because the service *is* favourited: tapping it turns the favourite
/// off. There is no unfilled state here — an entry that is not favourited is
/// not in this list at all.
class WishlistHeartButton extends StatefulWidget {
  const WishlistHeartButton({super.key, required this.onTap, this.buttonKey});

  /// Un-favourites this entry. Fired once the over-scale has played.
  final VoidCallback onTap;

  /// Key placed on the tappable region so tests can target ONE row's heart in
  /// a list of otherwise identical ones.
  ///
  /// Not `super.key`: that would key the widget itself, and a widget key on a
  /// list entry participates in element reuse — re-keying rows mid-removal is
  /// exactly how an `AnimatedSize` collapse gets attached to the wrong child.
  final Key? buttonKey;

  /// Tap-target extent. 32 dp square, matching the preview's `heartTarget`,
  /// which is itself aliased to the shipped `VelvetSizes.snackIconHolder`.
  static const double target = 32;

  /// The glyph inside that target.
  static const double glyph = 20;

  /// One beat of the pop, used for BOTH halves (over-scale, then shrink) and as
  /// the `AnimatedScale` duration, so the two never fall out of step.
  static const Duration popDuration = Duration(milliseconds: 110);

  @override
  State<WishlistHeartButton> createState() => _WishlistHeartButtonState();
}

// mobile-security finding (MEDIUM): `WishlistHeartButton.target` (32dp) was
// this button's ENTIRE tap target, not just its painted size — below both
// the Android 48dp and iOS 44pt tap-target floor (WCAG 2.5.5 / Material /
// HIG). Identical defect and identical fix shape to `hub_widgets.dart`'s
// `HubFilledButton`/`HubOutlineButton` (see that file's own
// `_kMinTapExtent`/`_kTapPad`): grow the INVISIBLE hit area via
// `Padding` inside the `GestureDetector`, never the painted control.
//
// Defined LOCALLY rather than importing `hub_widgets.dart`'s constants:
// those are private to that file (can't be imported even if we wanted to),
// and reaching from this feature's widget into `features/home/`'s private
// implementation would be a worse layering problem than re-stating a
// universal platform floor. This is the same situation `hub_widgets.dart`
// itself is in relative to `IconButton`'s own internal tap-target padding —
// re-deriving a fixed spec number is not the "don't duplicate a magic
// number" case that rule targets.
//
// Symmetric on BOTH axes (unlike the hub buttons, which only needed
// vertical padding): this heart is a 32×32 SQUARE, short on both axes, not
// a wide pill short on only one. See `_WishlistHeartButtonState.build`'s
// doc comment for the call-site overlap check this pad size assumes.
const double _kMinTapExtent = 48;
const double _kTapPad = (_kMinTapExtent - WishlistHeartButton.target) / 2;

class _WishlistHeartButtonState extends State<WishlistHeartButton> {
  /// The over-scale peak and the shrink the entry leaves on. Named rather than
  /// inline so the two ends of one gesture read as a pair.
  static const double _kRest = 1;
  static const double _kPop = 1.28;
  static const double _kCollapse = 0.82;

  double _scale = _kRest;

  Future<void> _handleTap() async {
    setState(() => _scale = _kPop);
    await Future<void>.delayed(WishlistHeartButton.popDuration);
    // The tap this method is servicing removes this row, so by here the host
    // may already have unmounted us. See the file header.
    if (!mounted) return;
    setState(() => _scale = _kCollapse);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: l10n.wishlistRemoveSemantics,
      child: GestureDetector(
        key: widget.buttonKey,
        onTap: _handleTap,
        behavior: HitTestBehavior.opaque,
        // `Padding`, not `ConstrainedBox(minHeight/minWidth: _kMinTapExtent)`
        // or `Align`/`Center`: the `SizedBox` below is a TIGHT 32×32
        // constraint, and `BoxConstraints.enforce` clamps a tight value that
        // falls below an outer floor UP to that floor — a `ConstrainedBox`
        // here would silently re-render the heart itself at 48dp instead of
        // just widening the invisible margin around it. `Align`/`Center`
        // fails differently: `RenderPositionedBox` fills to any finite loose
        // max on an unconstrained axis, which is exactly the failure mode
        // `wishlist_row.dart`'s own `IntrinsicWidth` exists to fight for
        // `HubFilledButton` today. `Padding` has neither problem — it
        // deflates the constraints it hands its child (never raises a
        // floor) and adds a FIXED inset to whatever comes back, so the
        // `SizedBox` still lands on its own tight 32dp in every caller.
        child: Padding(
          padding: const EdgeInsets.all(_kTapPad),
          child: SizedBox(
            height: WishlistHeartButton.target,
            width: WishlistHeartButton.target,
            child: Center(
              child: AnimatedScale(
                scale: _scale,
                duration: WishlistHeartButton.popDuration,
                curve: Curves.easeOutBack,
                child: const Icon(
                  Icons.favorite_rounded,
                  size: WishlistHeartButton.glyph,
                  color: BrandColors.accent,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
