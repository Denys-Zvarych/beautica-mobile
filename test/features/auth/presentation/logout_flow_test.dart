// Phase 2.8 — Unit tests for the logout flow in AuthNotifier.
//
// Uses a ProviderContainer with FakeSecureStorage + FakeAuthRepository.
// No Dio, no platform channels.
//
// Covered scenarios:
//   1. logout() wipes tokens; state becomes Unauthenticated.
//   2. logout() tolerates server 4xx (repo throws UnauthorizedFailure);
//      state still becomes Unauthenticated and deleteAll is still called.
//   3. Calling logout() twice is idempotent (no crash, no duplicate side effects
//      that could break tests). Asserts logoutCallCount == 2.
//   4. SettingsScreen widget-layer: tap Key('btn-logout') → logout() called →
//      navigate to /login.
//
// Phase 2.16 HIGH-1 regression tests for reset() callers:
//   5. logout-clears-draft — populated [registerDraftProvider] is wiped to
//      null by logout().
//   6. /done-clears-draft — pumping the production [DoneScreen] with a seeded
//      draft yields a null draft after the first frame. Phase 2.12 migrated
//      the post-frame reset from the old `DonePlaceholderScreen` to the real
//      celebration screen; the contract is unchanged.
//   7. login-link-clears-draft (Step 1) — tapping `btn-go-to-login` on Step 1
//      clears the draft.
//   8. login-link-clears-draft (role-selection) — tapping
//      `btn-go-to-login-from-intent` on the role-selection screen clears the
//      draft (covers MEDIUM-security-1).

import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/auth_tokens.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/auth/presentation/done_screen.dart';
import 'package:beautica_mobile/features/auth/presentation/register_step_1_screen.dart';
import 'package:beautica_mobile/features/auth/presentation/role_selection_screen.dart';
import 'package:beautica_mobile/features/auth/state/register_draft_notifier.dart';
import 'package:beautica_mobile/features/settings/presentation/settings_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _testUser = User(
  id: 'u1',
  email: 'master@beautica.test',
  role: UserRole.independentMaster,
  firstName: 'Test',
  lastName: 'User',
);

const _testTokens = AuthTokens(
  accessToken: 'access-token',
  refreshToken: 'refresh-token',
);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ProviderContainer _makeContainer({
  required FakeSecureStorage storage,
  required FakeAuthRepository repo,
}) {
  final container = ProviderContainer(
    overrides: [
      secureStorageProvider.overrideWith((_) => storage),
      authRepositoryProvider.overrideWith((_) => repo),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Seeds storage and repo so cold-start resolves to Authenticated.
///
/// Returns both the [ProviderContainer] and the [FakeAuthRepository] so that
/// callers can assert on [FakeAuthRepository.logoutCallCount] without
/// re-reading from the container (which would require a cast).
Future<(ProviderContainer, FakeAuthRepository)>
_makeAuthenticatedContainer() async {
  final storage = FakeSecureStorage();
  await storage.writeRefreshToken('stored-refresh');

  final repo = FakeAuthRepository()
    ..refreshResult = _testTokens
    ..meResult = _testUser;

  final container = _makeContainer(storage: storage, repo: repo);
  // F4 — build() returns Unauthenticated synchronously; the background restore
  // then flips state to Authenticated. Drain microtasks + Futures so callers
  // see the post-restore (Authenticated) state.
  await container.read(authProvider.future);
  await pumpEventQueue();

  return (container, repo);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('AuthNotifier.logout', () {
    // -----------------------------------------------------------------------
    // Test 1 — logout wipes tokens; state becomes Unauthenticated
    // -----------------------------------------------------------------------
    test('should wipe tokens and set state to Unauthenticated', () async {
      final (container, _) = await _makeAuthenticatedContainer();

      // Verify we start Authenticated.
      expect(container.read(authProvider).value, isA<Authenticated>());

      // Verify refresh token is in storage.
      final storage = container.read(secureStorageProvider);
      expect(await storage.readRefreshToken(), isNotNull);

      await container.read(authProvider.notifier).logout();

      // State must be Unauthenticated.
      final afterState = container.read(authProvider);
      expect(afterState, isA<AsyncData<AuthSession>>());
      expect(afterState.value, equals(const AuthSession.unauthenticated()));

      // Storage must be empty.
      expect(await storage.readRefreshToken(), isNull);
    });

    // -----------------------------------------------------------------------
    // Test 2 — logout tolerates server 4xx; state still Unauthenticated
    // -----------------------------------------------------------------------
    test(
      'should tolerate server error on logout; state still becomes Unauthenticated',
      () async {
        final storage = FakeSecureStorage();
        await storage.writeRefreshToken('stored-refresh');

        final repo = FakeAuthRepository()
          ..refreshResult = _testTokens
          ..meResult = _testUser
          ..logoutThrows = true; // repo.logout() will throw UnauthorizedFailure

        final container = _makeContainer(storage: storage, repo: repo);
        // F4 — drain microtasks so the background restore settles to
        // Authenticated before logout() is invoked.
        await container.read(authProvider.future);
        await pumpEventQueue();

        // Logout must NOT throw despite repo throwing.
        // Direct await — if logout() throws, the test fails.
        await container.read(authProvider.notifier).logout();

        // State must still be Unauthenticated.
        final afterState = container.read(authProvider);
        expect(afterState.value, equals(const AuthSession.unauthenticated()));

        // Storage must still be wiped.
        expect(await storage.readRefreshToken(), isNull);
      },
    );

    // -----------------------------------------------------------------------
    // Test 3 — logout is idempotent (calling twice doesn't crash)
    // -----------------------------------------------------------------------
    test('calling logout twice is idempotent', () async {
      final (container, repo) = await _makeAuthenticatedContainer();

      await container.read(authProvider.notifier).logout();
      // Second call on already-unauthenticated state must be safe.
      await expectLater(
        () => container.read(authProvider.notifier).logout(),
        returnsNormally,
      );

      expect(
        container.read(authProvider).value,
        equals(const AuthSession.unauthenticated()),
      );

      // Repository must have been called both times — no idempotency short-circuit.
      expect(repo.logoutCallCount, equals(2));
    });

    // -----------------------------------------------------------------------
    // Test 4 — SettingsScreen widget-layer logout
    // -----------------------------------------------------------------------
    testWidgets(
      'tapping btn-logout in SettingsScreen calls logout and navigates to /login',
      (tester) async {
        final storage = FakeSecureStorage();
        await storage.writeRefreshToken('stored-refresh');

        final repo = FakeAuthRepository()
          ..refreshResult = _testTokens
          ..meResult = _testUser;

        final router = GoRouter(
          initialLocation: RouteNames.settings,
          redirect: (context, state) => null,
          routes: [
            GoRoute(
              path: RouteNames.settings,
              builder: (context, state) => const SettingsScreen(),
            ),
            GoRoute(
              path: RouteNames.login,
              builder: (context, state) =>
                  const Scaffold(body: Center(child: Text('login'))),
            ),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              secureStorageProvider.overrideWith((_) => storage),
              authRepositoryProvider.overrideWith((_) => repo),
            ],
            child: MaterialApp.router(
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('uk'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tap the logout tile — this opens the confirmation dialog.
        await tester.tap(find.byKey(const Key('btn-logout')));
        await tester.pumpAndSettle(); // dialog animates in

        // Confirm the dialog — tap the confirm button.
        await tester.tap(find.byKey(const Key('btn-logout-confirm')));
        await tester.pumpAndSettle(); // logout completes + router navigates

        // The router must have navigated to /login.
        expect(find.text('login'), findsOneWidget);

        // The repository logout method must have been called once.
        expect(repo.logoutCallCount, equals(1));
      },
    );

    // -----------------------------------------------------------------------
    // Phase 2.16 HIGH-1 — logout clears the in-flight registration draft.
    // -----------------------------------------------------------------------
    test('logout-clears-draft — populated registerDraftProvider is wiped to '
        'null by logout()', () async {
      final (container, _) = await _makeAuthenticatedContainer();

      // Seed a populated draft (as if the user were mid-wizard when they
      // hit logout from an outer surface).
      final draft = container.read(registerDraftProvider.notifier)
        ..start(UserRole.independentMaster)
        ..updateStep1(
          email: 'leaks@example.com',
          password: 'StillInMemory1',
          confirmPassword: 'StillInMemory1',
        );
      // Sanity check — the draft is populated.
      expect(container.read(registerDraftProvider), isNotNull);
      expect(
        container.read(registerDraftProvider)!.password,
        equals('StillInMemory1'),
      );

      await container.read(authProvider.notifier).logout();

      // The draft must be wiped.
      expect(
        container.read(registerDraftProvider),
        isNull,
        reason:
            'logout() must call registerDraftProvider.reset() — leaving '
            'the password in memory after explicit sign-out is HIGH-1.',
      );
      // Defensive — keep the local handle from being elided.
      expect(draft, isNotNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Phase 2.16 HIGH-1 — /done route clears the draft on arrival.
  // ---------------------------------------------------------------------------

  group('Phase 2.16 HIGH-1 — register-draft hygiene', () {
    testWidgets(
      '/done-clears-draft — mounting DoneScreen resets the draft to null on '
      'the first frame (HIGH-1)',
      (tester) async {
        final storage = FakeSecureStorage();
        final repo = FakeAuthRepository();

        final container = ProviderContainer(
          overrides: [
            secureStorageProvider.overrideWith((_) => storage),
            authRepositoryProvider.overrideWith((_) => repo),
          ],
        );
        addTearDown(container.dispose);

        // Pre-populate the draft so the test can assert the reset happened
        // when the /done route mounts.
        container.read(registerDraftProvider.notifier)
          ..start(UserRole.salonOwner)
          ..updateStep1(
            email: 'leaks@example.com',
            password: 'StillInMemory1',
            confirmPassword: 'StillInMemory1',
          );
        expect(container.read(registerDraftProvider), isNotNull);

        // Drive a minimal GoRouter that mounts the production [DoneScreen].
        // Avoids pulling in the full production router (AuthRefreshNotifier
        // + auth_redirect) which would require a settled AuthNotifier with
        // a session. The DoneScreen falls back to the localised "друже"
        // placeholder when no authenticated user is present — fine for a
        // reset-contract regression test.
        final router = GoRouter(
          initialLocation: RouteNames.done,
          redirect: (context, state) => null,
          routes: [
            GoRoute(
              path: RouteNames.done,
              builder: (context, state) => const DoneScreen(),
            ),
            GoRoute(
              path: RouteNames.home,
              builder: (context, state) =>
                  const Scaffold(body: Center(child: Text('home'))),
            ),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('uk'),
            ),
          ),
        );
        // First frame mounts DoneScreen; the post-frame callback fires
        // ref.read(registerDraftProvider.notifier).reset(). One additional
        // pump drains the microtask queue.
        await tester.pump();

        // The draft is cleared after the post-frame callback runs.
        expect(
          container.read(registerDraftProvider),
          isNull,
          reason:
              'mounting /done must call registerDraftProvider.reset() in its '
              'post-frame callback — leaving the password in memory after '
              'wizard completion is HIGH-1.',
        );
      },
    );

    testWidgets(
      'login-link-clears-draft — tapping btn-go-to-login on Step 1 resets '
      'the draft to null before navigating away',
      (tester) async {
        final storage = FakeSecureStorage();
        final repo = FakeAuthRepository();

        final container = ProviderContainer(
          overrides: [
            secureStorageProvider.overrideWith((_) => storage),
            authRepositoryProvider.overrideWith((_) => repo),
          ],
        );
        addTearDown(container.dispose);

        // Seed the draft with credentials, as if the user filled the form
        // before deciding to log in instead.
        container.read(registerDraftProvider.notifier)
          ..start(UserRole.client)
          ..updateStep1(
            email: 'leaks@example.com',
            password: 'StillInMemory1',
            confirmPassword: 'StillInMemory1',
          );
        expect(container.read(registerDraftProvider), isNotNull);

        final router = GoRouter(
          initialLocation: RouteNames.register,
          redirect: (context, state) => null,
          routes: [
            GoRoute(
              path: RouteNames.register,
              // RegisterStep1Screen now returns its own AuthScaffold — no wrapper.
              builder: (context, state) => const RegisterStep1Screen(),
            ),
            GoRoute(
              path: RouteNames.login,
              builder: (context, state) =>
                  const Scaffold(body: Center(child: Text('login'))),
            ),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('uk'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tap the "Sign in" link on Step 1.
        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('step1_login_link')),
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('step1_login_link')),
        );
        await tester.pumpAndSettle();

        // Draft is cleared.
        expect(
          container.read(registerDraftProvider),
          isNull,
          reason:
              '_LoginLinkRow.onTap on Step 1 must call '
              'registerDraftProvider.reset() before navigating away.',
        );
        // And the router actually navigated to /login.
        expect(find.text('login'), findsOneWidget);
      },
    );

    testWidgets('login-link-from-role-selection-clears-draft — tapping '
        'btn-go-to-login-from-intent on the role-selection screen resets the '
        'draft to null before navigating away (MEDIUM-security-1)', (
      tester,
    ) async {
      final storage = FakeSecureStorage();
      final repo = FakeAuthRepository();

      final container = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWith((_) => storage),
          authRepositoryProvider.overrideWith((_) => repo),
        ],
      );
      addTearDown(container.dispose);

      // Seed the draft with role + credentials, as if the user came back
      // to the role-selection gate from Step 1 via the back link.
      container.read(registerDraftProvider.notifier)
        ..start(UserRole.salonOwner)
        ..updateStep1(
          email: 'leaks@example.com',
          password: 'StillInMemory1',
          confirmPassword: 'StillInMemory1',
        );
      expect(container.read(registerDraftProvider), isNotNull);

      final router = GoRouter(
        initialLocation: RouteNames.registerRole,
        redirect: (context, state) => null,
        routes: [
          GoRoute(
            path: RouteNames.registerRole,
            builder: (context, state) => const RoleSelectionScreen(),
          ),
          GoRoute(
            path: RouteNames.login,
            builder: (context, state) =>
                const Scaffold(body: Center(child: Text('login'))),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('uk'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap the "Sign in" link on the role-selection screen.
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('role_login_link')),
      );
      await tester.tap(find.byKey(const ValueKey<String>('role_login_link')));
      await tester.pumpAndSettle();

      // Draft is cleared.
      expect(
        container.read(registerDraftProvider),
        isNull,
        reason:
            '_LoginLinkRow.onTap on the role-selection screen must call '
            'registerDraftProvider.reset() before navigating away.',
      );
      // And the router actually navigated to /login.
      expect(find.text('login'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // (continuation of the original AuthNotifier.logout group)
  // ---------------------------------------------------------------------------

  group('AuthNotifier.logout — settings dialog', () {
    // -----------------------------------------------------------------------
    // Test 5 — SettingsScreen widget-layer: cancel dialog stays on settings
    // -----------------------------------------------------------------------
    testWidgets(
      'tapping btn-logout-cancel in the dialog stays on settings and does not call logout',
      (tester) async {
        final storage = FakeSecureStorage();
        await storage.writeRefreshToken('stored-refresh');

        final repo = FakeAuthRepository()
          ..refreshResult = _testTokens
          ..meResult = _testUser;

        final router = GoRouter(
          initialLocation: RouteNames.settings,
          redirect: (context, state) => null,
          routes: [
            GoRoute(
              path: RouteNames.settings,
              builder: (context, state) => const SettingsScreen(),
            ),
            GoRoute(
              path: RouteNames.login,
              builder: (context, state) =>
                  const Scaffold(body: Center(child: Text('login'))),
            ),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              secureStorageProvider.overrideWith((_) => storage),
              authRepositoryProvider.overrideWith((_) => repo),
            ],
            child: MaterialApp.router(
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('uk'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tap the logout tile — opens the confirmation dialog.
        await tester.tap(find.byKey(const Key('btn-logout')));
        await tester.pumpAndSettle(); // dialog animates in

        // Dismiss the dialog via the cancel button.
        await tester.tap(find.byKey(const Key('btn-logout-cancel')));
        await tester.pumpAndSettle(); // dialog dismisses

        // The router must NOT have navigated — settings content still visible.
        expect(find.text('login'), findsNothing);

        // Repository logout must NOT have been called.
        expect(repo.logoutCallCount, equals(0));
      },
    );
  });
}
