// Phase 351 gap-fix (mobile-qa, 2026-09-25) — E2E: INDEPENDENT_MASTER with an
// empty bio taps «Додати опис» on their OWN profile, saves a bio through the
// REAL `PersonalInfoEditScreen` editor, and the profile shows it on return.
//
// WHY THIS FILE EXISTS
// ---------------------
// Acceptance #10 (phase doc): "Empty bio. Expected: «Додати опис» opens the
// editor. After saving, the bio shows here [...]". The widget tier
// (`master_profile_screen_test.dart`'s "empty bio" group) proves the AddLink
// pushes `RouteNames.masterEditPersonal` against a STUBBED destination route
// — it never drives the real editor, never types into `field-bio`, never taps
// `btn-save-personal`, and never asserts the merged `PATCH
// /independent-masters/me/profile` body or the profile re-rendering the saved
// bio after the pop. That whole round trip — AddLink -> real editor -> real
// save -> real provider invalidation -> the bio card replacing the AddLink —
// is unexercised by anything before this file.
//
// LOCAL-EMULATOR CAVEAT: like every integration_test flow, this drives the
// real VM-service websocket and may not run green headlessly from the
// VirtualBox VM without the host-only adapter UP. Authored + `flutter
// analyze`-clean; confirm the green run on CI / a directly-driven emulator.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_screen.dart';
import 'package:beautica_mobile/features/master/presentation/personal_info_edit_screen.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'INDEPENDENT_MASTER with no bio: the profile shows «Додати опис» -> the '
    'real editor opens -> typing + saving a bio -> the profile shows the '
    'saved bio card, no AddLink, on return',
    (tester) async {
      final fb = FakeBackend()
        ..currentRole = UserRole.independentMaster
        ..masterBio =
            ''; // empty, not the seeded default — the crux of the flow

      await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
      // fixed-wait-ok: settles the real async login/route-transition + profile load + entrance animation; not a total-wait guess.
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.byType(MasterProfileScreen), findsOneWidget);

      // ── The empty-bio AddLink renders, not a bio card ─────────────────────
      final Finder addLink = find.byKey(const Key('master-profile-add-bio'));
      expect(addLink, findsOneWidget);

      await tester.ensureVisible(addLink);
      await tester.tap(addLink);
      await tester.pumpAndSettle();

      // ── The REAL editor opened (not a stub route) ─────────────────────────
      expect(find.byType(PersonalInfoEditScreen), findsOneWidget);

      const String newBio = 'Майстриня манікюру, 5 років досвіду.';
      await tester.enterText(find.byKey(const Key('field-bio')), newBio);
      await tester.pumpAndSettle();

      final Finder saveButton = find.byKey(const Key('btn-save-personal'));
      expect(
        tester.widget<NeumorphicButton>(saveButton).onPressed,
        isNotNull,
        reason:
            'typing a bio into an empty field must dirty the form and '
            'enable Save',
      );
      await tester.tap(saveButton);
      // fixed-wait-ok: settles the real async PATCH + provider-invalidate + pop; not a total-wait guess.
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // ── Back on the profile, the editor is gone ────────────────────────────
      expect(find.byType(PersonalInfoEditScreen), findsNothing);
      expect(find.byType(MasterProfileScreen), findsOneWidget);

      // ── The real PATCH carried the typed bio ──────────────────────────────
      expect(fb.patchProfileCalls, greaterThanOrEqualTo(1));
      expect(fb.lastPatchBody?['bio'], newBio);
      expect(
        fb.masterBio,
        newBio,
        reason:
            'the fake backend\'s stored bio (the same field the PUBLIC '
            'master detail endpoint reads for the client-facing profile) '
            'must reflect the save — the regression this flow protects is '
            'the bio failing to persist end to end, not just render locally',
      );

      // ── The profile now shows the bio card, no AddLink ────────────────────
      expect(addLink, findsNothing);
      expect(find.text(newBio), findsOneWidget);
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
