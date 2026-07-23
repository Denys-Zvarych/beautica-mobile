// Phase 14.3 — «Деталі запису»'s static hero medallion.
//
// The shipped `SuccessLottieBadge`'s hero slot, filled with a STATIC
// [StatusMedallion] instead of the celebratory Lottie.
//
// ## Why no Lottie — on ANY status, not just the bad ones
//
//   * On CANCELLED / DECLINED / NOT_COMPLETED a celebration animation is
//     obviously wrong: an animated flourish on the page a client opens to
//     find out why an appointment fell through. The no-show case is worst —
//     the one surface already carrying an implicit accusation, and a Lottie
//     would be *performing* at the client.
//   * On CONFIRMED / COMPLETED it is *subtly* wrong, which is worse: a
//     celebration is a MOMENT, and a moment can only happen once — it fired
//     when the booking was made. Replaying it every time the client opens
//     the record cheapens the original and makes a reference page feel like
//     it's selling them something.
//
// So the medallion is static on all five statuses, and it settles with one
// scale+fade entrance — landing, not performing.

import 'package:flutter/material.dart';

import 'booking_status_badge.dart';
import 'success_lottie_badge.dart';

/// A static [StatusMedallion], entering with a single settling scale+fade
/// over the first 45% of [controller] — the most animation a *reference*
/// view should ever do (contrast the success screens' drawn-in Lottie
/// check, which is a one-time celebration, not a settle).
class BookingStatusMedallion extends StatelessWidget {
  const BookingStatusMedallion({
    super.key,
    required this.visual,
    required this.controller,
    this.size = 80,
  });

  final BookingStatusVisual visual;

  /// The scaffold's own staggered-reveal controller (0..1 over its full
  /// 1350ms run) — NOT a Lottie controller. This widget derives its own
  /// sub-interval from it via [AnimationController.drive].
  final AnimationController controller;

  /// 80 dp — the shipped [SuccessLottieBadge]'s size, not the 112 dp the
  /// original design mock used.
  final double size;

  @override
  Widget build(BuildContext context) {
    final Animation<double> entrance = controller.drive(
      CurveTween(curve: const Interval(0.0, 0.45, curve: Curves.easeOutBack)),
    );

    return Semantics(
      label: visual.label,
      excludeSemantics: true,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: entrance,
          builder: (BuildContext context, Widget? child) {
            final double t = entrance.value.clamp(0.0, 1.0);
            return Opacity(
              opacity: t,
              child: Transform.scale(scale: 0.86 + 0.14 * t, child: child),
            );
          },
          child: StatusMedallion(
            color: visual.accent,
            icon: visual.icon,
            size: size,
          ),
        ),
      ),
    );
  }
}
