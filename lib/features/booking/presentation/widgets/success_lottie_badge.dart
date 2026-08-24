// Shared success animation badge.
//
// Extracted verbatim from the byte-identical private `_SuccessLottieBadge`
// (+ its `_SuccessBadgePlaceholder` fallback) that lived in BOTH
// `booking_success_screen.dart` and `salon_booking_success_screen.dart`.
//
// The real designed animation (`assets/lottie/success.json`), rendered at
// [size] dp. Plays once, driven by the caller-owned [controller] (its duration
// is stretched to 1.4x the authored length in `onLoaded` for a deliberately
// slower playback). Honours `MediaQuery.disableAnimations` by leaving the
// controller pinned wherever the caller put it (its last frame) instead of
// playing. Decorative — excluded from the semantics tree (the "Записано!"
// headline right below conveys the success state to screen readers).

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';

/// The shared success Lottie badge. Pass the [controller] that drives playback
/// (see the success scaffold's `_lottieController`); [size] defaults to 80 dp.
class SuccessLottieBadge extends StatelessWidget {
  const SuccessLottieBadge({super.key, this.controller, this.size = 80});

  final AnimationController? controller;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '',
      excludeSemantics: true,
      child: SizedBox(
        width: size,
        height: size,
        // PERF: isolate the Lottie animation's per-frame repaints from the
        // rest of the success scaffold — mirrors NeumorphicButton.build()'s
        // press-animation RepaintBoundary.
        child: RepaintBoundary(
          child: Lottie.asset(
            'assets/lottie/success.json',
            controller: controller,
            repeat: false,
            fit: BoxFit.contain,
            // PERF: the composition decodes asynchronously; without this the
            // slot renders blank for a frame or two before `onLoaded` fires.
            // Swap in a static version of the same circular badge so there's
            // never a blank box, then hand off to the real animation the instant
            // the composition is ready.
            //
            // COLOUR-FLASH FIX (2026-08-20, user-reported): the placeholder
            // used to paint `BrandColors.success` (#5C7A4A, GREEN) — a colour
            // that appears NOWHERE in `assets/lottie/success.json`, whose only
            // two fills are `#B89A7A` (BrandColors.accent, the camel disc) and
            // `#F5EDE0` (BrandColors.white, the cream check). So every success
            // screen flashed a green check for a frame or two and then swapped
            // to a camel one. The placeholder now paints the animation's OWN
            // disc colour, so the hand-off is invisible: same disc colour, same
            // glyph colour, same `size` (no layout jump either). Do NOT restore
            // `BrandColors.success` here — it is the semantic "success" token,
            // not this asset's palette, and the two disagree.
            frameBuilder:
                (
                  BuildContext context,
                  Widget child,
                  LottieComposition? composition,
                ) {
                  if (composition == null) {
                    return StatusMedallion(
                      color: BrandColors.accent,
                      icon: Icons.check_rounded,
                      size: size,
                    );
                  }
                  return child;
                },
            onLoaded: (LottieComposition composition) {
              final AnimationController? c = controller;
              if (c == null) return;
              // Intentional slow-down: the asset's native playback speed reads
              // as rushed at this size, so the controller is stretched to 1.4x
              // the composition's authored duration (same frame count, played
              // back slower) — do not "fix" this back to 1x.
              c.duration = composition.duration * 1.4;
              // Reduced-motion already pinned the controller to the last frame;
              // only play otherwise.
              if (!(MediaQuery.maybeOf(context)?.disableAnimations ?? false)) {
                c.forward(from: 0);
              }
            },
          ),
        ),
      ),
    );
  }
}

/// A solid-colour disc + a centred glyph — the generic "static badge" shape
/// shared by every status this app renders as a circle.
///
/// Promoted from the private `_SuccessBadgePlaceholder` that used to live
/// only here (Phase 14.3): [SuccessLottieBadge] still uses it, unchanged, as
/// its decode-time fallback (`color: BrandColors.accent, icon:
/// Icons.check_rounded` — the Lottie's OWN disc colour, see that call site);
/// «Деталі запису» (`booking_status_medallion.dart`)
/// uses it directly for all five booking statuses, wrapped in its own
/// entrance animation. One widget, two call sites, no new vocabulary — see
/// the Phase 14.3 README's "celebration vs reference" section for why the
/// detail page never gets the Lottie itself.
class StatusMedallion extends StatelessWidget {
  const StatusMedallion({
    super.key,
    required this.color,
    required this.icon,
    this.size = 80,
  });

  final Color color;
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Icon(icon, color: BrandColors.white, size: size * 0.55),
        ),
      ),
    );
  }
}
