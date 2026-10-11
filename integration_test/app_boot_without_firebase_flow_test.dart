// Phase 066 — E2E: the app boots and works with Firebase UNAVAILABLE.
//
// Phase 066 added `firebase_core` and a keep-alive `pushAvailableProvider`
// that `main.dart` kicks off (unawaited) right after `runApp`. A build without
// `android/app/google-services.json` (CI, a fresh clone, BEAUTICA_SKIP_FIREBASE=1)
// must still boot to its first real screen and run a normal flow, with push
// simply reported as unavailable. Three shapes of "Firebase unavailable":
//
//   1. The REAL provider on the flutter-tester host (not Android) → `false`
//      without touching Firebase at all.
//   2. The Android no-config path: `Firebase.initializeApp()` throws (what a
//      build without google-services.json does on a device) → `false`, never
//      an `AsyncError`.
//   3. A HUNG init (never completes) — the cold start and login must not wait
//      on it (067/068 await `.future`; nothing on the auth/first-screen path may).
//
// Out of scope (stated explicitly): native FCM token / permission / message /
// tap coverage belongs to the patrol tier in phases 067–069. The FCM cases in
// `integration_test/patrol/deep_link_patrol_test.dart` stay skip-marked until
// then.
//
// Runs headless: `flutter test integration_test/app_boot_without_firebase_flow_test.dart
// -d flutter-tester`.

import 'dart:async';

import 'package:beautica_mobile/core/push/firebase_bootstrap.dart';
import 'package:beautica_mobile/core/push/push_available_provider.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';
import 'support/e2e_boot_policy.dart';

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(E2eHarnessApp)));

/// Mirrors `main.dart`: start the keep-alive provider unawaited, off the
/// first-screen path.
void _kickPushInit(ProviderContainer container) {
  unawaited(container.read(pushAvailableProvider.future));
}

void _expectLoginScreen() {
  expect(
    find.byKey(const ValueKey<String>('login_email')),
    findsOneWidget,
    reason: 'cold start without Firebase must reach the login screen',
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets('real pushAvailableProvider resolves false on a host without '
      'Firebase, and CLIENT login lands on /home', (tester) async {
    final FakeBackend fb = FakeBackend()..currentRole = UserRole.client;
    final GoRouter router = await AppHarness.boot(tester, fb);
    final ProviderContainer container = _container(tester);
    _kickPushInit(container);
    _expectLoginScreen();

    await AppHarness.loginAs(tester, fb, UserRole.client);

    AppHarness.expectLocation(router, RouteNames.clientHome);
    expect(fb.loginCalls, 1);
    final AsyncValue<bool> push = container.read(pushAvailableProvider);
    expect(push, isA<AsyncData<bool>>());
    expect(push.value, isFalse);
  });

  testWidgets('Android without google-services.json: initializeApp throws → '
      'push false (AsyncData, not AsyncError) and master login works', (
    tester,
  ) async {
    final FakeBackend fb = FakeBackend()
      ..currentRole = UserRole.independentMaster;
    final GoRouter router = await AppHarness.boot(
      tester,
      fb,
      extraOverrides: <Object>[
        pushAvailableProvider.overrideWith(
          (_) => initFirebaseSafely(
            isAndroid: true,
            initializer: () async => throw FirebaseException(
              plugin: 'core',
              code: 'not-initialized',
            ),
          ),
        ),
      ],
    );
    final ProviderContainer container = _container(tester);
    _kickPushInit(container);
    _expectLoginScreen();

    await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

    AppHarness.expectLocation(router, RouteNames.masterProfile);
    final AsyncValue<bool> push = container.read(pushAvailableProvider);
    expect(push, isA<AsyncData<bool>>());
    expect(push.value, isFalse);
  });

  testWidgets('a hung Firebase init blocks neither cold start nor login', (
    tester,
  ) async {
    final Completer<bool> never = Completer<bool>();
    final FakeBackend fb = FakeBackend()..currentRole = UserRole.client;
    final GoRouter router = await AppHarness.boot(
      tester,
      fb,
      extraOverrides: <Object>[
        pushAvailableProvider.overrideWith((_) => never.future),
      ],
    );
    final ProviderContainer container = _container(tester);
    _kickPushInit(container);
    _expectLoginScreen();

    await AppHarness.loginAs(tester, fb, UserRole.client);

    AppHarness.expectLocation(router, RouteNames.clientHome);
    expect(container.read(pushAvailableProvider).isLoading, isTrue);
  });
}
