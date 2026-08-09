// Phase 239 — the wish-list row's removal animation.
//
// Transcribed from the approved preview
// `docs/signup-designs/BeautyPassport/lib/widgets/passport_widgets.dart`
// (`WishlistRemovable`).
//
// A row whose heart was tapped off collapses its own height — INCLUDING its
// bottom gap — so the list re-flows and, when the last entry goes, the empty
// state arrives naturally instead of snapping in.
//
// ## The bottom gap belongs to the ROW, not to the list
//
// This widget owns the inter-row spacing rather than the page emitting
// `SizedBox`es between children. If the gap lived outside, a collapsing row
// would shrink to zero height and leave its gap behind — the list would close
// up to a stack of blank 12 dp bands, one per removal. Owning it is what makes
// the collapse look like the row leaving rather than the row emptying.
//
// ## Height-collapse here, opacity on the compact cards
//
// The passport page's two-card line does NOT use this. Those cards get a TIGHT
// height from their `IntrinsicHeight` row, so there is no height for an
// `AnimatedSize` to animate; they fade instead and the line re-flows as the
// next favourite promotes into the freed slot. Same duration, so the two
// surfaces stay in step.

import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';

/// Collapses [child] (and its bottom gap) out of a list when [removing] flips.
class WishlistRemovable extends StatelessWidget {
  const WishlistRemovable({
    super.key,
    required this.removing,
    required this.child,
  });

  /// True once the entry's removal has been requested and it should animate out.
  final bool removing;

  final Widget child;

  /// How long the collapse takes. Shared with the compact cards' fade so a
  /// removal reads at the same speed on both surfaces.
  static const Duration duration = Duration(milliseconds: 260);

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: duration,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: removing
          // `width: double.infinity`, not `SizedBox.shrink()`: the collapse must
          // be vertical only. Shrinking horizontally too would drag the row's
          // siblings inward for the duration of the animation.
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: child,
            ),
    );
  }
}
