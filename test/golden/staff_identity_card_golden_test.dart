// Phase 21.16 — pixel gate for the PROMOTED [StaffIdentityCard]
// (`lib/shared/widgets/staff_identity_card.dart`).
//
// ── WHY THIS FILE EXISTS ──────────────────────────────────────────────────
//
// Phase 21.16 promoted the staff/owner identity card — avatar + display name +
// [RoleChip] (+ an optional self-declared title sub-line) — out of the two
// places that had hand-copied it inline:
//
//   • `owner_own_profile_screen.dart`'s `_OwnerProfileBody` (Phase 21.14),
//   • `salon_staff_profile_screen.dart`'s `_StaffProfileBody` (Phase 21.5),
//
// and added [AdminOwnProfileScreen] as a THIRD caller. The project's
// REUSE-FIRST rule requires the original callers' renders be proven identical
// afterwards — "golden-verified, not eyeballed" — and
// `grep -a -rln "owner_own_profile\|salon_staff_profile" test/golden/`
// returned NO hits before this file: neither screen has a golden anywhere, so
// the two extractions would otherwise have shipped diff-verified only.
//
// ── THE BASELINE IS PRE-PROMOTION, NOT A SELF-PORTRAIT ────────────────────
//
// A golden generated from the POST-promotion widget could only lock the
// rendering going FORWARD; it could never testify that the extraction changed
// nothing, because it would be a picture of the very code under suspicion.
// The committed baselines were therefore produced A/B, exactly as
// `section_header_golden_test.dart` records for its own promotion:
//
//   1. The PRE-promotion inline markup — copied verbatim out of
//      `_OwnerProfileBody.build` and `_StaffProfileBody.build` as they stood
//      at HEAD — was pasted into this file behind a temporary local class and
//      generated the PNGs below with `--update-goldens`.
//   2. This file was then pointed at the promoted
//      `shared/widgets/staff_identity_card.dart` and re-run WITHOUT
//      `--update-goldens`. It passed on the pre-promotion bytes.
//
// Green in step 2 is the acceptance the rule asks for. Recorded here because
// the probe is not reproducible from the committed tree alone.
//
// ── SCENARIOS (all three LIVE configurations, no speculative ones) ────────
//   • owner-with-title  — the Phase 21.14 owner card: «Власник салону» chip
//     plus the `professionalTitle` sub-line. Exercises the ONE additive
//     parameter the promotion introduced.
//   • owner-no-title    — the same owner card with `professionalTitle: null`,
//     i.e. the value EVERY pre-existing caller passes by omission. This is the
//     configuration the additive default has to keep byte-identical.
//   • staff-admin       — the Phase 21.5 staff card for an ADMIN roster entry:
//     «Адміністратор» chip, no sub-line. Same shape as the second scenario,
//     different chip label — which is what keeps the two cells distinguishable
//     under alchemist's CI text obscuring (label length drives block width).

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/staff_identity_card.dart';
import 'package:flutter/material.dart';

import 'helpers/golden_pump.dart';

Widget _host(double width) => ColoredBox(
  color: BrandColors.base,
  child: SizedBox(
    width: width,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Builder(
        builder: (BuildContext context) {
          final AppLocalizations l10n = AppLocalizations.of(context);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // 1 — the Phase 21.14 owner caller, verbatim.
              StaffIdentityCard(
                key: const Key('golden-identity-owner-with-title'),
                displayName: 'Олена Ковальчук',
                roleLabel: l10n.masterRoleSalonOwner,
                professionalTitle: 'Топ-майстер',
              ),
              const SizedBox(height: 24),
              // 2 — the same caller with no self-declared title: the default
              // every pre-existing call site takes by omission.
              StaffIdentityCard(
                key: const Key('golden-identity-owner-no-title'),
                displayName: 'Олена Ковальчук',
                roleLabel: l10n.masterRoleSalonOwner,
              ),
              const SizedBox(height: 24),
              // 3 — the Phase 21.5 staff caller (admin roster entry), verbatim.
              StaffIdentityCard(
                key: const Key('golden-identity-staff-admin'),
                displayName: 'Ірина Адміністратор',
                roleLabel: l10n.salonStaffRoleAdmin,
              ),
            ],
          );
        },
      ),
    ),
  ),
);

void main() {
  const double width = 360;

  for (final double scale in kGoldenTextScales) {
    goldenTest(
      'staff identity card — owner(+title) / owner(no title) / staff-admin '
      '${width.toInt()}dp x$scale',
      fileName: 'staff_identity_card_${widthScaleSuffix(width, scale)}',
      constraints: BoxConstraints.tight(const Size(width, 560)),
      textScaleFactor: scale,
      pumpWidget: goldenPumpWidget(width: width),
      builder: () => _host(width),
    );
  }
}
