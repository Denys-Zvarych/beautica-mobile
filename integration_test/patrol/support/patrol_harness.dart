// Phase 17.5 — patrol harness helpers.
//
// WHAT
// ----
// Mirrors integration_test/support/app_harness.dart, but adapted for patrol's
// `PatrolIntegrationTester` ($) instead of the bare flutter_test
// `WidgetTester`. Patrol wraps the standard tester, so the boot path is
// identical — fake Dio transport, fixed clock, fake SecureStorage, primed
// splash gate — only the pump call goes through `$` so patrol's finders and
// `$.platform.*` automation share the same tree.
//
// WHY A SEPARATE HARNESS
// ----------------------
// AppHarness.boot(tester, ...) takes a WidgetTester and is used by the fast
// pure-Flutter integration_test flows on the headless job. We deliberately do
// NOT import or mutate it here so the fast path stays byte-for-byte unchanged
// (Phase 17.4 aggregator depends on it). This file re-implements the same boot
// for patrol's binding and is compiled ONLY into the patrol native target.
//
// SCOPE
// -----
// Used by the PORTED TEMPLATE flow (auth_login_patrol_test.dart), which runs
// the deterministic fake-backend tree under patrol to demonstrate the
// patrolTest(...) binding. The native-only DEEP-LINK flow
// (deep_link_patrol_test.dart) does NOT use this harness — it drives the REAL
// launched app via `$.platform.mobile.openUrl(...)` and a deep-link intent.

import 'package:beautica_mobile/core/app_start_time.dart';
import 'package:beautica_mobile/core/network/dio_provider.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/core/theme/app_theme.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:patrol/patrol.dart';

import '../../../test/helpers/fakes/fake_secure_storage.dart';
import '../../support/fake_backend.dart';

export '../../support/fake_backend.dart' show FakeBackend, kFixedNow;

/// Shared boot path for patrol-bound flows that run against the fake backend.
abstract final class PatrolHarness {
  PatrolHarness._();

  /// Pumps the REAL app (real go_router + real Riverpod notifiers) with the
  /// fake Dio transport + fixed clock + fake SecureStorage, through patrol's
  /// tester. Returns the live [GoRouter] so tests can assert the current route.
  ///
  /// Mirrors [AppHarness.boot]: primes [AppStartTime] 5 s in the past so the
  /// splash-duration gate is already satisfied and the auth redirect settles to
  /// /login on the first settle.
  static Future<GoRouter> boot(
    PatrolIntegrationTester $,
    FakeBackend fakeBackend,
  ) async {
    AppStartTime.setStartForTest(
      DateTime.now().subtract(const Duration(seconds: 5)),
    );

    final storage = FakeSecureStorage();

    await $.pumpWidgetAndSettle(
      ProviderScope(
        // Cast a plain Object list so this file need not import the internal
        // Override type — mirrors integration_test/support/app_harness.dart.
        // ignore: avoid_dynamic_calls
        overrides: <Object>[
          dioProvider.overrideWithValue(fakeBackend.dio),
          secureStorageProvider.overrideWithValue(storage),
          clockProvider.overrideWithValue(() => kFixedNow),
        ].cast(),
        child: const _PatrolHarnessApp(),
      ),
    );

    final container = ProviderScope.containerOf(
      $.tester.element(find.byType(_PatrolHarnessApp)),
    );
    return container.read(appRouterProvider);
  }

  /// Resets [AppStartTime] to its pre-boot null state. Call in tearDown.
  static void tearDownHarness() => AppStartTime.resetForTest();

  /// Drives the real login form for [role] and taps Submit (key-based).
  static Future<void> loginAs(
    PatrolIntegrationTester $,
    FakeBackend fakeBackend,
    UserRole role,
  ) async {
    fakeBackend.currentRole = role;

    final email = switch (role) {
      UserRole.client => 'client@beautica.ua',
      UserRole.salonOwner => 'owner@beautica.ua',
      UserRole.independentMaster => 'master@beautica.ua',
      _ => 'master@beautica.ua',
    };

    await $.enterText(find.byKey(const ValueKey<String>('login_email')), email);
    await $.enterText(
      find.byKey(const ValueKey<String>('login_password')),
      'Secret1234',
    );
    await $.tap(find.byKey(const ValueKey<String>('login_submit')));
    await $.pumpAndSettle();
  }
}

/// The real MaterialApp.router without main()'s platform-channel side-effects.
/// Identical to integration_test/support/app_harness.dart's _HarnessApp.
class _PatrolHarnessApp extends ConsumerWidget {
  const _PatrolHarnessApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: velvetTheme(),
      themeMode: ThemeMode.light,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('uk', 'UA'),
      routerConfig: router,
    );
  }
}
