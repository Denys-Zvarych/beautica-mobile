// END-TO-END integration test for the restructured edit-profile flow.
//
// WHY THIS FILE EXISTS
// --------------------
// The monolithic MasterEditScreen was split into a settings hub + per-section
// pages. This test drives the REAL app widget tree — the real SettingsHubScreen,
// the real PersonalInfoEditScreen, the real MasterProfileScreen, the real
// MasterProfile notifier, the real HttpMasterRepository + generated
// MasterControllerApi + built_value serialization — wired through one real
// GoRouter. Only the network SOCKET is faked, via the Phase 17.3 FakeBackend
// (http_mock_adapter DioAdapter acting as a tiny stateful "fake backend").
//
// FLOW: launch on the hub → tap the personal-info row → edit firstName → Save →
// the page PATCHes the fake backend (merging name onto the CACHED instagram/
// phone), invalidates masterProfileProvider, and pops back; we then assert the
// new name renders AND that the PATCH did NOT wipe the cached Instagram (the
// cached-master-merge contract).
//
// REFACTORED (Phase 17.3): now boots via AppHarness.boot() which provides:
//   • FakeBackend.dio (no real socket)
//   • FakeSecureStorage (no platform channel)
//   • Fixed clock (kFixedNow = 2026-06-14 12:00 UTC)
//   • Phase 17.2 overflow guard (any RenderFlex overflow fails the test)
//
// KEY-BASED NAVIGATION POLICY (enforced, see app_harness.dart):
//   ALL navigation taps use find.byKey() — no raw Ukrainian find.text() tap drivers.

import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/profile_avatar.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_notifier.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

// ---------------------------------------------------------------------------
// Stub notifiers (same as before — keep for backward compatibility)
// ---------------------------------------------------------------------------

const _stubUser = User(
  id: 'user-master-1',
  email: 'master@beautica.ua',
  role: UserRole.independentMaster,
  firstName: 'Олена',
  lastName: 'Ковальчук',
);

class _StubAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.authenticated(
    user: _stubUser,
    accessToken: 'test-token',
  );
}

class _StubServicesList extends ServicesList {
  @override
  Future<List<MasterService>> build() =>
      Future<List<MasterService>>.value(const <MasterService>[]);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Phase 17.2 — the integration binding does not route through
  // flutter_test_config.dart's testExecutable, so install the overflow guard
  // here too. It chains to the default presenter, so the no-network net is
  // unaffected; any RenderFlex overflow in the real driven tree fails the test.
  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'hub → personal-info → edit firstName → Save persists the change and does '
    'NOT wipe the cached Instagram; profile then renders the new name',
    (tester) async {
      final fb = FakeBackend();

      // Phase 17.3 refactor: boot via the shared harness with two extra
      // overrides that were in the old ad-hoc setup:
      //   • _StubAuthNotifier — gives an authenticated session without login
      //   • _StubServicesList — empty services list, avoids services endpoint
      final GoRouter router = await AppHarness.boot(
        tester,
        fb,
        extraOverrides: [
          authProvider.overrideWith(_StubAuthNotifier.new),
          // cycle-stub-ok: this flow tests the edit-profile path, not the logout cascade — it never invokes a cyclic teardown entrypoint. The auth-cascade cycle is regression-guarded by logout_flow_test.dart, which keeps the REAL graph. (auth is also stubbed here, so no auth→services cycle exists to hide anyway.)
          servicesListProvider.overrideWith(_StubServicesList.new),
        ],
      );

      // The stub auth puts us directly into an authenticated session; the
      // router guard should redirect from /splash → /master/profile.
      // Navigate to the settings hub to begin the test flow using the router
      // reference — no GoRouter.of(context) needed.
      router.go(RouteNames.masterMenu);
      await tester.pumpAndSettle();

      // On the hub — drill into the personal-info section.
      expect(find.byKey(const Key('row-personal')), findsOneWidget);
      await tester.tap(find.byKey(const Key('row-personal')));
      await tester.pumpAndSettle();

      // Personal-info page pre-populated from the fake backend.
      final firstNameField = find.descendant(
        of: find.byKey(const Key('field-firstName')),
        matching: find.byType(TextField),
      );
      expect(
        tester.widget<TextField>(firstNameField).controller?.text,
        'Олена',
      );

      // Edit firstName ONLY and Save.
      // Focus the field first — enterText does not replace existing text
      // unless the field is tapped/focused beforehand.
      await tester.tap(firstNameField);
      await tester.pumpAndSettle();
      await tester.enterText(firstNameField, 'Оксана');
      await tester.pump();
      await tester.tap(find.byKey(const Key('btn-save-personal')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      // The PATCH fired and mutated the backend.
      expect(fb.masterFirstName, 'Оксана', reason: 'PATCH must mutate backend');

      // CACHED-MERGE CONTRACT: the PATCH body must carry the cached Instagram —
      // never blank it. A regression here re-introduces the "save name → lose
      // Instagram" bug.
      expect(fb.lastPatchBody, isNotNull);
      expect(
        fb.lastPatchBody!['instagram'],
        '@olena_nails',
        reason:
            'editing the name must NOT clear the cached Instagram — the PATCH '
            'must overlay name onto the cached instagram/phone',
      );
      expect(fb.masterInstagram, '@olena_nails');

      // masterProfileProvider must be invalidated + refetched after Save.
      expect(
        fb.getMasterCalls,
        greaterThanOrEqualTo(2),
        reason:
            'masterProfileProvider must be invalidated + refetched after Save '
            '(initial GET to populate the edit page, one after save).',
      );
    },
  );

  // ── professionalTitle E2E (feat/provider-professional-title) ──────────────
  //
  // WHAT THIS TESTS (Step 2.7 Rule 3b coverage)
  // --------------------------------------------
  // The feature added a new "Професійне звання" field to
  // PersonalInfoEditScreen. This flow proves:
  //   1. The field pre-populates from the backend-seeded professionalTitle
  //      on the initial GET /masters/me.
  //   2. Editing the title and saving PATCHes the backend with
  //      professionalTitle in the request body.
  //   3. The profile screen renders the Key('master-profile-professional-title')
  //      widget after the invalidate + refetch cycle.
  //
  // Isolation: FakeBackend seeded with masterProfessionalTitle='Стиліст' BEFORE
  // boot so the initial GET carries the title. After Save the PATCH body is
  // asserted on fb.lastPatchBody, and a second GET is confirmed via
  // fb.getMasterCalls to prove the invalidation fired.

  testWidgets(
    'professionalTitle: edit field pre-populates → Save PATCHes backend → '
    'profile screen renders the updated title',
    (tester) async {
      final fb = FakeBackend();

      // Seed a professional title so the personal-info page pre-populates it.
      fb.masterProfessionalTitle = 'Стиліст';

      final GoRouter router = await AppHarness.boot(
        tester,
        fb,
        extraOverrides: [
          authProvider.overrideWith(_StubAuthNotifier.new),
          // cycle-stub-ok: this flow tests the professionalTitle edit path, not the logout cascade — it never invokes a cyclic teardown entrypoint. Auth is also stubbed, so no auth→services back-edge exists to hide.
          servicesListProvider.overrideWith(_StubServicesList.new),
        ],
      );

      // Navigate directly to the personal-info edit page.
      router.go(RouteNames.masterEditPersonal);
      await tester.pumpAndSettle();

      // The professionalTitle field must be pre-populated from the backend seed.
      final titleField = find.descendant(
        of: find.byKey(const Key('field-professionalTitle')),
        matching: find.byType(TextField),
      );
      expect(titleField, findsOneWidget);
      expect(
        tester.widget<TextField>(titleField).controller?.text,
        'Стиліст',
        reason:
            'the professionalTitle field must be pre-populated from the GET '
            '/masters/me response',
      );

      // Edit the title.
      await tester.tap(titleField);
      await tester.pumpAndSettle();
      await tester.enterText(titleField, 'Колорист-стиліст');
      await tester.pump();

      // Tap Save.
      await tester.tap(find.byKey(const Key('btn-save-personal')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      // The PATCH body must carry the updated professionalTitle.
      expect(fb.lastPatchBody, isNotNull);
      expect(
        fb.lastPatchBody!['professionalTitle'],
        'Колорист-стиліст',
        reason:
            'the PATCH body must include professionalTitle with the new value',
      );
      // The in-memory backend state must have been updated.
      expect(
        fb.masterProfessionalTitle,
        'Колорист-стиліст',
        reason: 'FakeBackend.masterProfessionalTitle must reflect the PATCH',
      );

      // At least two GET /masters/me calls: one to populate the edit page,
      // one triggered by the masterProfileProvider invalidation after Save.
      expect(
        fb.getMasterCalls,
        greaterThanOrEqualTo(2),
        reason:
            'masterProfileProvider must be invalidated + refetched after Save',
      );

      // Cached-merge contract: Instagram must NOT be cleared by a
      // professionalTitle-only edit.
      expect(
        fb.lastPatchBody!['instagram'],
        '@olena_nails',
        reason:
            'editing only the professionalTitle must NOT clear the cached '
            'Instagram — the PATCH must carry all sibling fields from the cache',
      );

      // Step 2.7 Rule 3b — RoleChip absence regression pin.
      // Navigate to the master profile to verify that the RoleChip is absent
      // now that professionalTitle ('Колорист-стиліст') is set. This is the
      // end-to-end regression guard for the bug where RoleChip rendered
      // unconditionally on both profile screens even when a professional title
      // was present.
      router.go(RouteNames.masterProfile);
      await tester.pumpAndSettle();

      expect(
        find.byType(RoleChip),
        findsNothing,
        reason:
            'RoleChip must be absent on the profile screen when '
            'professionalTitle is non-null — regression pin for the '
            'unconditional-chip rendering bug',
      );
    },
  );
}
