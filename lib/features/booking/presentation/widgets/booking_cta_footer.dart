// Shared pinned booking-CTA footer.
//
// Extracted from the byte-identical private `_CtaFooter` in BOTH
// `booking_confirm_screen.dart` and `salon_booking_confirm_screen.dart`: a
// base-tone [DecoratedBox] with the upward shelf shadows over a [SafeArea] +
// full-width [NeumorphicButton].
//
// [label] is ALWAYS driven by the caller — the salon flow flips it from
// «Записатись» to «Повторити» on a partial-failure retry, and both flows swap
// in the loading caption while submitting. The check glyph is hidden whenever
// [loading] is true (spinner takes over). The salon screen's `PopScope`
// back-guard stays on the screen, NOT here.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';

/// Pinned bottom footer carrying the full-width submit/retry CTA.
class BookingCtaFooter extends StatelessWidget {
  const BookingCtaFooter({
    super.key,
    required this.label,
    required this.enabled,
    required this.loading,
    required this.onPressed,
    required this.buttonKey,
    this.icon = Icons.check_circle_outline_rounded,
  });

  /// CTA caption — caller-driven (e.g. «Записатись» / «Повторити» / loading).
  final String label;

  /// Whether the CTA is tappable.
  final bool enabled;

  /// In-flight submit — swaps the glyph for a spinner and (via
  /// [NeumorphicButton]) blocks re-taps.
  final bool loading;

  final VoidCallback onPressed;

  /// Key applied to the inner [NeumorphicButton] — distinct per flow
  /// (`booking-confirm-submit-cta` / `salon-confirm-submit-cta`).
  final Key buttonKey;

  /// Leading glyph on the CTA. Defaults to the confirm/submit check, so every
  /// pre-existing caller (all four submit footers) renders exactly as before.
  /// The master «Новий запис» wizard's mid-flow «Далі» footers pass
  /// [Icons.arrow_forward_rounded] instead — a check on a step that only moves
  /// forward would claim the booking was made. Hidden entirely while
  /// [loading] (the spinner takes over), same as before.
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: BrandColors.base,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: BrandColors.shadowDarkCard,
            offset: Offset(0, -8),
            blurRadius: 20,
          ),
          BoxShadow(
            color: BrandColors.shadowLightStrong,
            offset: Offset(0, -1),
            blurRadius: 3,
            spreadRadius: -1,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            VelvetSpacing.lg,
            VelvetSpacing.sm + 2,
            VelvetSpacing.lg,
            VelvetSpacing.sm + 2,
          ),
          child: NeumorphicButton(
            key: buttonKey,
            label: label,
            icon: loading ? null : icon,
            loading: loading,
            onPressed: enabled ? onPressed : null,
          ),
        ),
      ),
    );
  }
}
