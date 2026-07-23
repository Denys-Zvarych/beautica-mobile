// MO-5 — the route SEAM for reviewing a multi-service VISIT.
//
// The visit detail's «Залишити відгук» CTA routes here — `/bookings/visit/
// :appointmentId/review` — carrying the appointmentId so a visit is reviewed
// ONCE, as a whole, via `AppointmentRepository.createAppointmentReview`, never
// the per-booking review of a child (which the backend would reject).
//
// MO-6 fills in the actual leave-review form + submit wiring (the visit analogue
// of `leave_review_screen.dart`). Until then this renders an honest informative
// state rather than a broken form — the CTA still routes correctly with the
// appointmentId, which is all MO-5 owns.
//
// SEC: renders identity/form-adjacent content — acquires the app-wide
// [ScreenProtectionManager] for its lifetime, like every other PII screen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

/// The «ВІДГУК ПРО МАЙСТРА» screen for the visit identified by [appointmentId].
/// MO-5 seam; MO-6 completes the form + submit.
class AppointmentReviewScreen extends ConsumerStatefulWidget {
  const AppointmentReviewScreen({super.key, required this.appointmentId});

  final String appointmentId;

  @override
  ConsumerState<AppointmentReviewScreen> createState() =>
      _AppointmentReviewScreenState();
}

class _AppointmentReviewScreenState
    extends ConsumerState<AppointmentReviewScreen> {
  late final ScreenProtectionManager _screenProtection;

  @override
  void initState() {
    super.initState();
    _screenProtection = ref.read(screenProtectionProvider)..acquire();
  }

  @override
  void dispose() {
    _screenProtection.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: BrandColors.base,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            VelvetSpacing.lg,
            VelvetSpacing.lg,
            VelvetSpacing.lg,
            VelvetSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              NeumorphicIconButton(
                key: const Key('visit-review-back'),
                icon: Icons.arrow_back_ios_new_rounded,
                semanticLabel: l10n.reviewBackSemantics,
                onTap: () {
                  if (context.canPop()) context.pop();
                },
              ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Container(
                          height: 88,
                          width: 88,
                          decoration: const BoxDecoration(
                            color: BrandColors.base,
                            shape: BoxShape.circle,
                            boxShadow: VelvetShadows.extrudedCard,
                          ),
                          child: const Icon(
                            Icons.rate_review_outlined,
                            size: 38,
                            color: BrandColors.accent,
                          ),
                        ),
                        const SizedBox(height: VelvetSpacing.lg),
                        Text(
                          l10n.visitReviewComingSoonTitle,
                          textAlign: TextAlign.center,
                          style: VelvetText.headingSm,
                        ),
                        const SizedBox(height: VelvetSpacing.sm),
                        Text(
                          l10n.visitReviewComingSoonBody,
                          textAlign: TextAlign.center,
                          style: VelvetText.body(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
