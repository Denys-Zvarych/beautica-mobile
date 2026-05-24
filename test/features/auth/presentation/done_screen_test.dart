// Phase 2.12 — Widget tests for DoneScreen (VelvetTouch redesign).
//
// Tests use a minimal GoRouter (initial route = /done → DoneScreen) so that
// `context.go(...)` inside the widget can navigate to /home for the two CTA
// flows. Auth state is controlled via ProviderScope overrides so the screen
// can read [currentUserProvider] for the personalised greeting + chips.
//
// Covered scenarios:
//   1. Personalised greeting renders with the authenticated user's first name.
//   2. Falls back to the l10n placeholder when User has no first name.
//   3. Three summary chips render (done_chip_role / done_chip_email /
//      done_chip_ready) with the expected label text.
//   4. Role chip shows the role-derived label from UserRoleL10n.
//   5. Tapping done_to_app navigates to /home.
//   6. Tapping done_setup_later navigates to /home.
//   7. Mounting /done resets the in-flight registration draft (HIGH-1 regression).
//   8. ScreenProtector is never invoked in widget tests (removed from screen;
//      pump must complete without MissingPluginException).

import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_tokens.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/done_screen.dart';
import 'package:beautica_mobile/features/auth/state/register_draft_notifier.dart';
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

const _userWithName = User(
  id: 'u1',
  email: 'anna@beautica.test',
  role: UserRole.client,
  firstName: 'Анна',
  lastName: 'Коваль',
);

const _userWithoutName = User(
  id: 'u2',
  email: 'noname@beautica.test',
  role: UserRole.independentMaster,
);

const _testTokens = AuthTokens(
  accessToken: 'access-token',
  refreshToken: 'refresh-token',
);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Builds a minimal GoRouter with DoneScreen at /done and a /home placeholder.
GoRouter _makeRouter() => GoRouter(
  initialLocation: RouteNames.done,
  redirect: (context, state) => null,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.done,
      builder: (context, state) => const DoneScreen(),
    ),
    GoRoute(
      path: RouteNames.home,
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('home-route'))),
    ),
  ],
);

/// Pumps the DoneScreen inside a UncontrolledProviderScope.
///
/// When [authenticatedUser] is non-null the FakeAuthRepository is seeded so
/// [currentUserProvider] resolves to that user.
Future<ProviderContainer> _pumpDoneScreen(
  WidgetTester tester, {
  User? authenticatedUser,
  required GoRouter router,
}) async {
  final storage = FakeSecureStorage();
  final repo = FakeAuthRepository();

  if (authenticatedUser != null) {
    await storage.writeRefreshToken('seeded-refresh-token');
    repo
      ..refreshResult = _testTokens
      ..meResult = authenticatedUser;
  }

  final container = ProviderContainer(
    overrides: [
      secureStorageProvider.overrideWith((_) => storage),
      authRepositoryProvider.overrideWith((_) => repo),
    ],
  );
  addTearDown(container.dispose);

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

  // Drain AuthNotifier background restore + done screen post-frame callback.
  await tester.pumpAndSettle();

  return container;
}

/// Convenience: resolves AppLocalizations for the rendered uk locale.
AppLocalizations _l10n(WidgetTester tester) {
  // The VelvetHeader is always present — use its element as the context anchor.
  return AppLocalizations.of(tester.element(find.byType(DoneScreen)));
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('DoneScreen (VelvetTouch)', () {
    // -----------------------------------------------------------------------
    // Test 1 — Personalised greeting renders the user's first name
    // -----------------------------------------------------------------------
    testWidgets(
      '1. renders "Вітаємо, {firstName}!" with the authenticated user\'s '
      'first name',
      (tester) async {
        final router = _makeRouter();
        addTearDown(router.dispose);

        await _pumpDoneScreen(
          tester,
          authenticatedUser: _userWithName,
          router: router,
        );

        final greeting = tester.widget<Text>(
          find.byKey(const Key('done-greeting')),
        );
        expect(
          greeting.data,
          equals(_l10n(tester).registerDoneGreeting('Анна')),
          reason:
              'greeting must interpolate User.firstName from the '
              'authenticated session',
        );

        // Italic-camel subtitle is present.
        final subtitle = tester.widget<Text>(
          find.byKey(const Key('done-subtitle')),
        );
        expect(subtitle.data, equals(_l10n(tester).registerDoneSubtitle));
      },
    );

    // -----------------------------------------------------------------------
    // Test 2 — Fallback greeting when User has no first name
    // -----------------------------------------------------------------------
    testWidgets(
      '2. falls back to the localised placeholder when User.firstName is null',
      (tester) async {
        final router = _makeRouter();
        addTearDown(router.dispose);

        await _pumpDoneScreen(
          tester,
          authenticatedUser: _userWithoutName,
          router: router,
        );

        final greeting = tester.widget<Text>(
          find.byKey(const Key('done-greeting')),
        );
        final l10n = _l10n(tester);
        expect(
          greeting.data,
          equals(l10n.registerDoneGreeting(l10n.registerDoneGreetingFallback)),
          reason:
              'when User.firstName is null/empty the greeting must use '
              'the registerDoneGreetingFallback placeholder',
        );
      },
    );

    // -----------------------------------------------------------------------
    // Test 3 — Three summary chips are rendered
    // -----------------------------------------------------------------------
    testWidgets(
      '3. renders exactly 3 summary chips (done_chip_role, done_chip_email, '
      'done_chip_ready)',
      (tester) async {
        final router = _makeRouter();
        addTearDown(router.dispose);

        await _pumpDoneScreen(
          tester,
          authenticatedUser: _userWithName,
          router: router,
        );

        expect(
          find.byKey(const ValueKey<String>('done_chip_role')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('done_chip_email')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('done_chip_ready')),
          findsOneWidget,
        );
      },
    );

    // -----------------------------------------------------------------------
    // Test 4 — Role chip shows the user's role label
    // -----------------------------------------------------------------------
    testWidgets(
      '4. role chip displays the role label derived from UserRoleL10n',
      (tester) async {
        final router = _makeRouter();
        addTearDown(router.dispose);

        await _pumpDoneScreen(
          tester,
          authenticatedUser: _userWithName,
          router: router,
        );

        final l10n = _l10n(tester);

        // _userWithName has UserRole.client → l10n.roleClient.
        expect(
          find.descendant(
            of: find.byKey(const ValueKey<String>('done_chip_role')),
            matching: find.text(l10n.roleClient),
          ),
          findsOneWidget,
          reason: 'role chip must display the localised role label',
        );

        // Email-verified chip displays the l10n string.
        expect(
          find.descendant(
            of: find.byKey(const ValueKey<String>('done_chip_email')),
            matching: find.text(l10n.registerDoneChipEmailVerified),
          ),
          findsOneWidget,
        );

        // Ready chip displays the marketing line.
        expect(
          find.descendant(
            of: find.byKey(const ValueKey<String>('done_chip_ready')),
            matching: find.text(l10n.registerDoneChipReadyFast),
          ),
          findsOneWidget,
        );
      },
    );

    // -----------------------------------------------------------------------
    // Test 5 — Primary CTA navigates to /home
    // -----------------------------------------------------------------------
    testWidgets('5. tapping done_to_app navigates the router to /home', (
      tester,
    ) async {
      final router = _makeRouter();
      addTearDown(router.dispose);

      await _pumpDoneScreen(
        tester,
        authenticatedUser: _userWithName,
        router: router,
      );

      expect(find.text('home-route'), findsNothing);

      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('done_to_app')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey<String>('done_to_app')));
      await tester.pumpAndSettle();

      expect(
        find.text('home-route'),
        findsOneWidget,
        reason: 'done_to_app must call context.go(RouteNames.home)',
      );
    });

    // -----------------------------------------------------------------------
    // Test 6 — Secondary link navigates to /home
    // -----------------------------------------------------------------------
    testWidgets('6. tapping done_setup_later navigates the router to /home', (
      tester,
    ) async {
      final router = _makeRouter();
      addTearDown(router.dispose);

      await _pumpDoneScreen(
        tester,
        authenticatedUser: _userWithName,
        router: router,
      );

      expect(find.text('home-route'), findsNothing);

      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('done_setup_later')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey<String>('done_setup_later')));
      await tester.pumpAndSettle();

      expect(
        find.text('home-route'),
        findsOneWidget,
        reason: 'done_setup_later must call context.go(RouteNames.home)',
      );
    });

    // -----------------------------------------------------------------------
    // Test 7 — /done resets the registration draft (HIGH-1 regression)
    // -----------------------------------------------------------------------
    testWidgets(
      '7. mounting /done resets the in-flight registration draft to null '
      '(Phase 2.16 HIGH-1)',
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

        // Seed the draft as if the user were mid-wizard.
        container.read(registerDraftProvider.notifier)
          ..start(UserRole.client)
          ..updateStep1(
            email: 'leaks@example.com',
            password: 'StillInMemory1',
            confirmPassword: 'StillInMemory1',
          );
        expect(container.read(registerDraftProvider), isNotNull);

        final router = _makeRouter();
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
        // First frame mounts DoneScreen; addPostFrameCallback fires on pump.
        await tester.pump();

        expect(
          container.read(registerDraftProvider),
          isNull,
          reason:
              'mounting /done must call registerDraftProvider.reset() in '
              'its post-frame callback — leaving the password in memory '
              'after wizard completion is HIGH-1',
        );
      },
    );

    // -----------------------------------------------------------------------
    // Test 9 — currentUserProvider null at render time: DoneScreen must not
    //          crash and must render the fallback greeting + client role label.
    //          Covers the branch `user?.firstName` == null AND `user?.role` == null
    //          in the build method (e.g. session expired between verification
    //          and navigation to /done, or deep-link edge case).
    // -----------------------------------------------------------------------
    testWidgets(
      '9. no authenticated user: DoneScreen renders fallback greeting and '
      'client role label without crashing',
      (tester) async {
        final router = _makeRouter();
        addTearDown(router.dispose);

        // Pump with no authenticatedUser → authProvider stays Unauthenticated
        // → currentUserProvider returns null.
        await _pumpDoneScreen(tester, router: router);

        final l10n = _l10n(tester);

        // Fallback greeting must be used (not a crash or empty string).
        final greeting = tester.widget<Text>(
          find.byKey(const Key('done-greeting')),
        );
        expect(
          greeting.data,
          equals(l10n.registerDoneGreeting(l10n.registerDoneGreetingFallback)),
          reason:
              'When currentUserProvider returns null the greeting must use '
              'the registerDoneGreetingFallback placeholder (no crash).',
        );

        // Role chip must show the fallback client label (not null or empty).
        final roleChip = find.byKey(const ValueKey<String>('done_chip_role'));
        expect(roleChip, findsOneWidget);
        expect(
          find.descendant(
            of: roleChip,
            matching: find.text(l10n.registerDoneChipRoleClient),
          ),
          findsOneWidget,
          reason:
              'When user is null the role chip must fall back to '
              'registerDoneChipRoleClient — not crash or show empty text.',
        );

        // No exception was thrown during render.
        expect(tester.takeException(), isNull);
      },
    );

    // -----------------------------------------------------------------------
    // Test 10 — independentMaster role chip label is explicitly asserted.
    //           Complements test 4 (client role); ensures all role-chip paths
    //           through UserRoleL10n.label() are exercised in the suite.
    // -----------------------------------------------------------------------
    testWidgets('10. independentMaster role chip shows the roleIndependentMaster '
        'localised label', (tester) async {
      final router = _makeRouter();
      addTearDown(router.dispose);

      // _userWithoutName has UserRole.independentMaster.
      await _pumpDoneScreen(
        tester,
        authenticatedUser: _userWithoutName,
        router: router,
      );

      final l10n = _l10n(tester);

      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('done_chip_role')),
          matching: find.text(l10n.roleIndependentMaster),
        ),
        findsOneWidget,
        reason:
            'For UserRole.independentMaster the role chip must show '
            'l10n.roleIndependentMaster — not null, empty, or any other label.',
      );
    });

    // -----------------------------------------------------------------------
    // Test 8 — Screen pumps cleanly without platform-channel exceptions
    //
    // ScreenProtector has been removed from DoneScreen (post-auth screen
    // carries no sensitive data). The test verifies no exceptions are thrown
    // during a full pump-and-settle cycle.
    // -----------------------------------------------------------------------
    testWidgets('8. DoneScreen pumps without any exception (no ScreenProtector '
        'platform-channel call)', (tester) async {
      final router = _makeRouter();
      addTearDown(router.dispose);

      await _pumpDoneScreen(
        tester,
        authenticatedUser: _userWithName,
        router: router,
      );

      expect(
        tester.takeException(),
        isNull,
        reason:
            'DoneScreen must pump cleanly — no platform channel calls '
            'that require a mock binding',
      );
    });
  });
}
