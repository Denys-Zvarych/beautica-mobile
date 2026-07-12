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
            frameBuilder:
                (
                  BuildContext context,
                  Widget child,
                  LottieComposition? composition,
                ) {
                  if (composition == null) {
                    return _SuccessBadgePlaceholder(size: size);
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

/// Static stand-in shown for the brief window before the Lottie composition
/// finishes its async decode — same footprint + success colour the finished
/// animation lands on, so the swap is not a visible jump.
class _SuccessBadgePlaceholder extends StatelessWidget {
  const _SuccessBadgePlaceholder({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: BrandColors.success,
        shape: BoxShape.circle,
      ),
      child: SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Icon(
            Icons.check_rounded,
            color: BrandColors.white,
            size: size * 0.55,
          ),
        ),
      ),
    );
  }
}
