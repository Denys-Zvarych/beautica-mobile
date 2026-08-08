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
    );
  }
}
