// Phase 21.16 — the shared "one section of a staggered entrance" wrapper.
//
// PROMOTED, NOT WRITTEN. This is the `static Widget _reveal(fade, slide, child)`
// helper that existed as SIX hand-copies, lifted into `core/widgets/` and made
// public. The copies it replaces:
//
//   * `salon/presentation/salon_staff_profile_screen.dart`
//   * `salon/presentation/public_salon_profile_screen.dart`
//   * `salon/presentation/admin_own_profile_screen.dart`
//   * `salon/presentation/owner_own_profile_screen.dart`
//   * `master/presentation/salon_master_profile_screen.dart`
//   * `master/presentation/public_master_profile_screen.dart`
//
// Two of the six had already been corrected (boundary inside), four still
// carried the bug below. That split is exactly what a fork costs: one fix
// landed twice and drifted away from the other four, which sat two directories
// apart. There is now one implementation and one place to fix it.
//
// ## Why the [RepaintBoundary] is the transitions' CHILD, never their parent
//
// `RenderAnimatedOpacity.paint` (via `pushOpacity`) and
// `RenderFractionalTranslation.paint` both call `paintChild` on EVERY frame, so
// a boundary placed ABOVE them isolates nothing — it sits on the outside of the
// thing that is animating. With the boundary INSIDE, the section subtree
// (`NeumorphicCard`'s shadow pass, an avatar's two `MaskFilter.blur` ops,
// `SalonLogo`'s gradient) rasterizes ONCE and the transitions merely
// re-composite that layer across the ~60 frames of the 1000 ms entrance.
//
// ## The shape is UNCONDITIONAL — never branch on "the entrance finished"
//
// Same contract as [StaggeredReveal] (`staggered_reveal.dart`): this must
// return the same widget SHAPE for the whole life of the host. `Widget.canUpdate`
// compares `runtimeType`, so short-circuiting to the bare `child` once the
// animation completes unmounts every `State` beneath it. A completed
// `FadeTransition` sits at opacity 1.0 (no save layer) and the slide collapses
// to zero, so keeping the wrappers costs nothing at steady state.
//
// ## Why a widget CLASS and not a top-level function
//
// The reveal pairs have to be pinnable from a widget test. A loaded profile
// tree carries several unrelated `SlideTransition`s and nested
// `RepaintBoundary`s, so no type-based finder over those two types can isolate
// a reveal — every candidate assertion stayed green with the boundary hoisted.
// `find.byType(RevealTransition)` isolates them exactly, and each call site
// also passes a stable [Key] so an individual section can be addressed.

import 'package:flutter/material.dart';

/// One section of a screen's staggered fade-up entrance.
///
/// Wraps [child] in the [fade] opacity and [slide] offset segments the host
/// screen already derived from its single entrance controller, with a
/// [RepaintBoundary] between the transitions and [child] so the subtree
/// rasterizes once instead of once per frame.
///
/// The host owns the animations; this widget owns only the shape. Give every
/// call site a stable [key] — widget tests address reveals by key, and the
/// boundary's placement is only assertable through one.
class RevealTransition extends StatelessWidget {
  const RevealTransition({
    super.key,
    required this.fade,
    required this.slide,
    required this.child,
  });

  /// Opacity segment for this section, from the host's entrance controller.
  final Animation<double> fade;

  /// Upward slide segment for this section, as a fraction of its own height.
  final Animation<Offset> slide;

  /// The section itself. Everything below the boundary.
  final Widget child;

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: fade,
    child: SlideTransition(
      position: slide,
      // INSIDE, not outside — see this file's header.
      child: RepaintBoundary(child: child),
    ),
  );
}
