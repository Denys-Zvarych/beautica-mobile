// Phase 21.11 mobile-qa gap-closure — pixel coverage for the PROMOTED
// [SectionHeader] (`lib/shared/widgets/section_header.dart`).
//
// ── WHY THIS FILE EXISTS ──────────────────────────────────────────────────
//
// Phase 21.11 promoted `SectionHeader` out of
// `features/schedule/presentation/widgets/schedule_widgets.dart` into
// `lib/shared/widgets/` (re-exported from its old home) and added ONE
// additive parameter, `titleStyle`, defaulting to `null`. The project's
// REUSE-FIRST rule for promoting a private/feature-local widget requires the
// ORIGINAL caller's render be proven identical afterwards — "golden-verified,
// not eyeballed".
//
// `grep -a -rln "SectionHeader" test/golden/` returned NO hits before this
// file, and `test/golden/` holds no MasterScheduleScreen capture at all
// (`calendar_working_hours_golden_test.dart` is WorkingHoursScreen, a
// different screen). So the promotion shipped diff-verified only, and — more
// importantly going forward — the widget went from ONE feature-local consumer
// to THREE across two features (`master_schedule_screen.dart`'s «Календар»
// heading, `salon_pending_invites_screen.dart`'s count header, and
// `invite_staff_screen.dart`'s appended pending block) with no pixel gate
// anywhere. A single edit here now lands on three screens.
//
// ── THE BASELINE IS PRE-PROMOTION, NOT A SELF-PORTRAIT ────────────────────
//
// A golden generated from the POST-promotion widget could only lock the
// rendering going FORWARD; it could never testify that the promotion changed
// nothing, because it would be a picture of the very code under suspicion.
// (The standing "a self-generated golden is not acceptance" rule is about
// visual BUGS; this is a no-visual-change promotion, a different case — but
// the self-reference trap is identical and had to be broken the same way.)
//
// So the committed baselines were produced A/B:
//   1. `git show HEAD:lib/features/schedule/presentation/widgets/
//      schedule_widgets.dart` — the PRE-promotion `SectionHeader` class body,
//      copied verbatim into this file behind a temporary alias — generated
//      the PNGs below with `--update-goldens`.
//   2. This file was then pointed back at the promoted
//      `shared/widgets/section_header.dart` and re-run WITHOUT
//      `--update-goldens`. It passed on the pre-promotion bytes.
//
// Green in step 2 is the acceptance the rule asks for: the two
// implementations paint the same pixels for the schedule caller's exact
// configuration. Recorded here because the probe is not reproducible from the
// committed tree alone.
//
// ── SCENARIOS (both LIVE configurations, no speculative ones) ─────────────
//   • «Календар» — `title` only, every other parameter omitted. THE schedule
//     caller, byte-for-byte (`master_schedule_screen.dart:613`), and the only
//     one the A/B above could cover (the pre-promotion class has no
//     `titleStyle` parameter to pass).
//   • «Очікують підтвердження» — `titleStyle: VelvetText.sectionLabel()` plus
//     a trailing count `Text`. The Phase 21.11 configuration, shared verbatim
//     by BOTH new consumers. Not A/B-able (the parameter is new), but it is
//     the configuration the additive default has to keep DISTINCT from the
//     first one — two scenarios that rendered identically would mean
//     `titleStyle` was being ignored.

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/section_header.dart';
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
              // The schedule caller, verbatim — no titleStyle, no info, no
              // trailing.
              SectionHeader(
                key: const Key('golden-section-header-schedule'),
                title: l10n.scheduleCalendarSection,
              ),
              const SizedBox(height: 24),
              // The Phase 21.11 caller, verbatim — this is the invite HISTORY
              // header on `salon_pending_invites_screen.dart`, whose label
              // became «Історія запрошень» when that screen widened from
              // pending-only to full history.
              //
              // NOTE: `invite_staff_screen.dart`'s appended pending block is a
              // SEPARATE caller and is NOT captured here — it kept the
              // pending-only wording under its own `inviteStaffPendingSectionLabel`
              // key, and has no golden of its own.
              SectionHeader(
                key: const Key('golden-section-header-pending-invites'),
                title: l10n.salonPendingInvitesSectionLabel,
                titleStyle: VelvetText.sectionLabel(),
                trailing: Text('3', style: VelvetText.feedbackMutedSm),
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
      'section header — schedule default + 21.11 sectionLabel/count '
      '${width.toInt()}dp x$scale',
      fileName: 'section_header_${widthScaleSuffix(width, scale)}',
      constraints: BoxConstraints.tight(const Size(width, 160)),
      textScaleFactor: scale,
      pumpWidget: goldenPumpWidget(width: width),
      builder: () => _host(width),
    );
  }
}
