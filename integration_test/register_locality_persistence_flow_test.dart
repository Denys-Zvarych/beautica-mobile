// E2E: Registration locality persistence across a LOST in-memory draft.
//
// JOURNEY (the user-flow this guards — Step 3b end-to-end coverage)
// -----------------------------------------------------------------
//   /register/role (CLIENT) → step1 → step2 →
//   step3: pick a CITY via the real locality cascade → submit (register) →
//   ── SIMULATE OS-KILL: the in-memory RegisterDraft is wiped to null ── →
//   /verification: enter OTP → submit →
//   ASSERT: the fake backend received PATCH /api/v1/users/me carrying the
//           picked cityId.
//
// WHY THIS EXISTS
// ---------------
// The register Step-3 locality used to live ONLY in the in-memory keepAlive
// RegisterDraft. When the app is backgrounded to read the emailed OTP (or
// OS-killed under memory pressure), that draft is back to `null` at OTP time,
// so the post-OTP PATCH /users/me NEVER fired and the CLIENT's chosen city was
// silently lost. The fix mirrors the Step-3 locality into a durable
// PendingLocality blob (secure storage) that the verification screen
// re-hydrates when the draft is gone.
//
// This flow reproduces the lost-draft state DELIBERATELY (resets the draft to
// null after register, before OTP) and proves the durable blob path drives the
// PATCH end-to-end against the fake backend — the real go_router, real Riverpod
// notifiers, real repositories, real PendingLocalityStore over the fake secure
// storage.
//
// HEADLESS NOTE
// -------------
// integration_test/ runs against a real emulator (it is NOT part of the CI
// `flutter test` gate — GitHub-hosted runners cannot start the Android
// emulator). It is wired into integration_test/all_tests.dart and validated by
// `flutter analyze integration_test/`. Run locally with:
//   flutter test integration_test/register_locality_persistence_flow_test.dart -d emulator-5554
//
// All navigation taps are key-based per the AppHarness policy.

import 'package:beautica_mobile/features/auth/state/register_draft_notifier.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  void expectLocation(GoRouter router, String expected) {
    final String current = router.routerDelegate.currentConfiguration.uri
        .toString();
    expect(
      current,
      startsWith(expected),
      reason: 'Expected router location to start with $expected, got $current',
    );
  }

  testWidgets('CLIENT picks a city → register → draft lost (OS-kill) → OTP → '
      'PATCH /users/me carries the picked cityId', (tester) async {
    final fb = FakeBackend();
    final GoRouter router = await AppHarness.boot(tester, fb);

    // The live ProviderContainer — used to simulate the OS-kill draft loss.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );

    // ── Navigate to the wizard and pick CLIENT ──────────────────────────
    expect(find.byKey(const ValueKey<String>('login_email')), findsOneWidget);
    router.go(RouteNames.registerRole);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('role_client')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('role_continue')));
    await tester.pumpAndSettle();
    expectLocation(router, RouteNames.register);

    // ── Step 1 — credentials ────────────────────────────────────────────
    await tester.enterText(
      find.byKey(const ValueKey<String>('step1_email')),
      'new@beautica.ua',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('step1_password')),
      'Secret1234',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('step1_confirm')),
      'Secret1234',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('step1_submit')));
    await tester.pumpAndSettle();
    expectLocation(router, RouteNames.registerStep2);

    // ── Step 2 — profile ────────────────────────────────────────────────
    await tester.enterText(
      find.byKey(const ValueKey<String>('step2_first_name')),
      'Тест',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('step2_last_name')),
      'Клієнт',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('step2_phone')),
      '+380501234567',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('step2_submit')));
    await tester.pumpAndSettle();
    expectLocation(router, RouteNames.registerStep3);

    // ── Step 3 — pick a city via the REAL locality cascade ──────────────
    // Open the Oblast picker → pick the seeded Kyiv oblast.
    await tester.tap(find.byKey(const Key('locality_row_oblast')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('locality_picker_tile_oblast-kyiv')),
    );
    await tester.pumpAndSettle();

    // Open the City picker → pick the seeded Kyiv city.
    await tester.tap(find.byKey(const Key('locality_row_city')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('locality_picker_tile_city-kyiv')),
    );
    await tester.pumpAndSettle();

    // Submit Step 3 (CLIENT "Далі") — runs register() AND stashes the durable
    // PendingLocality blob (city-kyiv) keyed by the returned email.
    await tester.tap(find.byKey(const ValueKey<String>('address_submit')));
    await tester.pumpAndSettle();

    // Register fired and we are on /verification.
    expect(fb.registerCalls, greaterThanOrEqualTo(1));
    expectLocation(router, RouteNames.verification);

    // ── SIMULATE OS-KILL: wipe the in-memory draft to null ──────────────
    // After this the verification screen MUST re-hydrate the locality from
    // the durable blob — exactly the path the silent-data-loss fix added.
    container.read(registerDraftProvider.notifier).reset();
    await tester.pump();
    expect(
      container.read(registerDraftProvider),
      isNull,
      reason:
          'Draft must be null to reproduce the lost-draft / OS-kill state '
          'that the durable blob re-hydration is designed to recover from.',
    );

    // ── Enter the OTP and submit ────────────────────────────────────────
    await tester.enterText(
      find.byKey(const ValueKey<String>('verify_code_input')),
      '123456',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('verify_submit')));
    await tester.pumpAndSettle();

    // ── ASSERT: the post-OTP PATCH /users/me fired with the picked city ─
    expect(fb.verifyEmailCalls, equals(1));
    expect(
      fb.patchMeCalls,
      equals(1),
      reason:
          'Pre-fix this is 0 — the null draft short-circuited the post-OTP '
          'PATCH and the CLIENT city was silently lost. The durable blob '
          're-hydration must drive exactly one PATCH /users/me.',
    );
    expect(
      fb.lastPatchMeBody?['cityId'],
      equals('city-kyiv'),
      reason:
          'The PATCH /users/me body must carry the cityId the user picked on '
          'Step 3, recovered from the durable PendingLocality blob after the '
          'in-memory draft was lost.',
    );

    // The flow completes — we reach /done.
    expectLocation(router, RouteNames.done);
  });
}
