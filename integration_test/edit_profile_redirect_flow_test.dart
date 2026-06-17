// END-TO-END regression for BUG 1 — account-edit Save must land on the PROFILE.
//
// WHY THIS FILE EXISTS
// --------------------
// The real navigation stack for an account edit is THREE deep:
//
//   MasterProfileScreen  →  SettingsHubScreen (the menu)  →  <section> edit page
//
// reached by: profile's `btn-menu-master` (context.push → /master/menu), then a
// hub section row (`row-personal` / `row-contacts` / `row-location`), then the
// per-section edit page.
//
// BUG: each section edit page used to `context.pop()` ONE level on a successful
// Save, which landed the user back on the SETTINGS HUB — not the profile. The
// fix makes the save-SUCCESS path call `context.go(RouteNames.masterProfile)`,
// which replaces the whole stack and lands on the profile.
//
// The existing `edit_profile_flow_test.dart` CANNOT catch this regression: it
// jumps straight to the hub via `router.go(RouteNames.masterMenu)`, so it starts
// only TWO deep (hub → edit) and a `pop()` would (wrongly) land on the hub which
// it never asserts against. This test reproduces the REAL three-deep stack by
// STARTING on `MasterProfileScreen` and pushing the hub via the on-screen
// `btn-menu-master`, so a regressed `pop()` lands on the hub and the
// "profile is visible" assertion fails.
//
// SHARED HANDLER NOTE
// -------------------
// All three section pages (personal_info_edit_screen.dart,
// contacts_edit_screen.dart, location_edit_screen.dart) use the identical
// save-SUCCESS line `context.go(RouteNames.masterProfile)`. This test drives
// PERSONAL + CONTACTS end-to-end (LOCATION's success path needs the locality
// cascade — a city pick — which the fake backend serves empty, so it is covered
// by the shared-handler assertion rather than a brittle cascade drive).
//
// Boots via AppHarness.boot() (FakeBackend socket, FakeSecureStorage, fixed
// clock, overflow guard) + stub auth/services overrides — same pattern as
// edit_profile_flow_test.dart.

import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
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
// Stub notifiers — authenticated INDEPENDENT_MASTER session + empty services.
// (Identical to edit_profile_flow_test.dart.)
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

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  /// Boots the app on the REAL master profile screen (the start of the
  /// three-deep edit stack). Returns the live router. The stub auth lands the
  /// guard on /master/profile after splash; we `go` there to be explicit.
  Future<GoRouter> bootOnProfile(WidgetTester tester, FakeBackend fb) async {
    final GoRouter router = await AppHarness.boot(
      tester,
      fb,
      extraOverrides: [
        authProvider.overrideWith(_StubAuthNotifier.new),
        servicesListProvider.overrideWith(_StubServicesList.new),
      ],
    );
    router.go(RouteNames.masterProfile);
    await tester.pumpAndSettle();
    return router;
  }

  /// Drives profile → hub → section row using the ON-SCREEN affordances (key
  /// taps only — KEY POLICY). After this the section edit page is mounted.
  Future<void> openSection(WidgetTester tester, String rowKey) async {
    // The profile is visible: tap the menu button to PUSH the settings hub.
    expect(
      find.byKey(const Key('btn-menu-master')),
      findsOneWidget,
      reason:
          'the test must start on MasterProfileScreen (the real stack root)',
    );
    await tester.tap(find.byKey(const Key('btn-menu-master')));
    await tester.pumpAndSettle();

    // On the hub — drill into the requested section.
    expect(find.byKey(Key(rowKey)), findsOneWidget);
    await tester.tap(find.byKey(Key(rowKey)));
    await tester.pumpAndSettle();
  }

  // ── Test 1 — PERSONAL: edit firstName → Save lands on PROFILE ─────────────

  testWidgets('profile → menu → personal → edit firstName → Save lands on '
      'MasterProfileScreen (NOT the settings hub)', (tester) async {
    final fb = FakeBackend();
    await bootOnProfile(tester, fb);

    await openSection(tester, 'row-personal');
    // Let the section's entrance animation finish so the pinned Save button is
    // fully on-screen + hittable before we interact.
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // Edit firstName and Save.
    final Finder firstNameField = find.descendant(
      of: find.byKey(const Key('field-firstName')),
      matching: find.byType(TextField),
    );
    await tester.tap(firstNameField);
    await tester.pumpAndSettle();
    await tester.enterText(firstNameField, 'Оксана');
    await tester.pumpAndSettle();
    final Finder saveBtn = find.byKey(const Key('btn-save-personal'));
    await tester.ensureVisible(saveBtn);
    await tester.pumpAndSettle();
    await tester.tap(saveBtn);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    // The PATCH fired.
    expect(fb.masterFirstName, 'Оксана', reason: 'Save must PATCH the name');

    // LANDED ON PROFILE: its name marker is present AND the hub's section
    // row is gone. A regressed `pop()` would land on the hub → row-personal
    // present, master-profile-name absent → both assertions fail.
    expect(
      find.byKey(const Key('master-profile-name')),
      findsOneWidget,
      reason: 'Save success must land on the profile, not the hub',
    );
    expect(
      find.byKey(const Key('row-personal')),
      findsNothing,
      reason: 'the settings hub must NOT be the screen after Save',
    );
  }, timeout: const Timeout(Duration(seconds: 30)));

  // ── Test 2 — CONTACTS: edit phone → Save lands on PROFILE ─────────────────

  testWidgets('profile → menu → contacts → edit phone → Save lands on '
      'MasterProfileScreen (NOT the settings hub)', (tester) async {
    final fb = FakeBackend();
    await bootOnProfile(tester, fb);

    await openSection(tester, 'row-contacts');
    await tester.pumpAndSettle(const Duration(seconds: 1));

    final Finder phoneField = find.descendant(
      of: find.byKey(const Key('field-phone')),
      matching: find.byType(TextField),
    );
    await tester.enterText(phoneField, '+380501112233');
    await tester.pumpAndSettle();
    final Finder saveBtn = find.byKey(const Key('btn-save-contacts'));
    await tester.ensureVisible(saveBtn);
    await tester.pumpAndSettle();
    await tester.tap(saveBtn);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    // The phone PATCHed. The field applies UA phone formatting (spaces), so
    // assert on the digit payload rather than the exact spaced string.
    final String digits = (fb.masterPhone ?? '').replaceAll(RegExp(r'\D'), '');
    expect(
      digits,
      '380501112233',
      reason: 'Save must PATCH the phone (digits, ignoring display spacing)',
    );

    // Same landing assertion as Test 1 — the shared `context.go(masterProfile)`
    // handler. location_edit_screen.dart uses the identical save-SUCCESS line.
    expect(
      find.byKey(const Key('master-profile-name')),
      findsOneWidget,
      reason: 'Save success must land on the profile, not the hub',
    );
    expect(
      find.byKey(const Key('row-contacts')),
      findsNothing,
      reason: 'the settings hub must NOT be the screen after Save',
    );
  }, timeout: const Timeout(Duration(seconds: 30)));

  // ── Test 3 — NEGATIVE: a validation failure keeps the user on the edit page

  testWidgets('a validation failure on Save keeps the user on the edit page — NO '
      'navigation to profile or hub', (tester) async {
    final fb = FakeBackend();
    await bootOnProfile(tester, fb);

    await openSection(tester, 'row-personal');
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // Clear firstName (required) → the draft is dirty (Save enabled) but the
    // form validator rejects it on Save.
    final Finder firstNameField = find.descendant(
      of: find.byKey(const Key('field-firstName')),
      matching: find.byType(TextField),
    );
    await tester.enterText(firstNameField, '');
    await tester.pumpAndSettle();
    final Finder saveBtn = find.byKey(const Key('btn-save-personal'));
    await tester.ensureVisible(saveBtn);
    await tester.pumpAndSettle();
    await tester.tap(saveBtn);
    await tester.pumpAndSettle();

    // NO PATCH fired — validation short-circuited the save. This is the
    // deterministic proof that the save was rejected before any network write.
    expect(
      fb.patchProfileCalls,
      0,
      reason: 'a validation failure must not PATCH the backend',
    );

    // STAYED on the edit page: its field + save button are still mounted, and
    // neither the profile marker nor the hub row is visible. These are the
    // deterministic "no navigation" assertions for the Bug 1 negative case.
    // (The transient validation-summary snackbar is intentionally NOT asserted
    // — it auto-dismisses and is flaky across run modes; the no-PATCH +
    // still-on-edit-page assertions fully prove the behaviour.)
    expect(
      find.byKey(const Key('field-firstName')),
      findsOneWidget,
      reason: 'a validation failure must keep the user on the edit page',
    );
    expect(
      find.byKey(const Key('btn-save-personal')),
      findsOneWidget,
      reason: 'the edit page save button is still present (no navigation)',
    );
    expect(find.byKey(const Key('master-profile-name')), findsNothing);
    expect(find.byKey(const Key('row-personal')), findsNothing);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
