// Phase 14.13 — SalonBookingComingSoonScreen: salon booking flow step 3
// placeholder.
//
// The per-master time picker (`docs/signup-designs/SalonBookingTime/`) is
// deferred — this minimal screen is where `SalonMasterSelectionScreen`'s
// «Підтвердити» CTA routes instead of crashing or entering the
// independent-master `SlotPickerScreen` (which assumes one master, not the
// salon's N-appointments-per-master model). Reached ONLY via
// `RouteNames.salonBookingComingSoon`, carrying the salon id (a bare
// `String`) in `extra` so the "back to profile" action can return to the
// exact salon the client was booking.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';

/// Salon booking flow step-3 placeholder — stands in for the deferred
/// per-master time picker.
class SalonBookingComingSoonScreen extends StatelessWidget {
  const SalonBookingComingSoonScreen({super.key, required this.salonId});

  final String salonId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: BrandColors.base,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                VelvetSpacing.lg,
                VelvetSpacing.md,
                VelvetSpacing.lg,
                VelvetSpacing.sm,
              ),
              child: SizedBox(
                height: 48,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: NeumorphicIconButton(
                        key: const Key('salon-booking-coming-soon-back'),
                        icon: Icons.arrow_back_ios_new_rounded,
                        semanticLabel: l10n.registerBackStep,
                        onTap: () => context.pop(),
                      ),
                    ),
                    Text(
                      l10n.salonBookingComingSoonTitle,
                      style: VelvetText.subheading(),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(VelvetSpacing.xl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      SizedBox(
                        height: 96,
                        width: 96,
                        child: NeumorphicInset(
                          radius: 48,
                          child: Center(
                            child: Icon(
                              Icons.schedule_rounded,
                              size: 40,
                              color: BrandColors.accent.withValues(alpha: 0.9),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: VelvetSpacing.lg),
                      Text(
                        l10n.salonBookingComingSoonMessage,
                        key: const Key('salon-booking-coming-soon-message'),
                        style: VelvetText.heading20,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: VelvetSpacing.xl),
                      NeumorphicButton(
                        key: const Key('salon-booking-coming-soon-back-cta'),
                        label: l10n.salonBookingComingSoonBackCta,
                        icon: Icons.storefront_rounded,
                        onPressed: () =>
                            context.go(RouteNames.salonPublicProfile(salonId)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
