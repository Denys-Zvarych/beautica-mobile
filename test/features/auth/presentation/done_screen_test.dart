// Phase 2.12 — Widget tests for DoneScreen.
//
// Tests use a minimal GoRouter (initial route = /done → DoneScreen) so that
// `context.go(...)` inside the widget can navigate to /home for the two CTA
// flows. Auth state is controlled via ProviderScope overrides so the screen
// can read [currentUserProvider] for the personalised greeting + chips.
//
// Covered scenarios:
//   1. Renders the 4-dot progress with the "Готово" active label under dot 4.
//   2. Renders the personalised greeting with the authenticated user's first
//      name ("Вітаємо, Анна!").
//   3. Falls back to "Вітаємо, друже!" when the User has no first name.
//   4. Renders the 3 summary chips with role / email / ready label.
//   5. Tapping btn-go-to-app navigates to /home.
//   6. Tapping btn-setup-later navigates to /home.
//   7. Mounting /done resets the in-flight registration draft (HIGH-1
//      regression — duplicates logout_flow_test coverage on the production
//      screen surface, kept here so the contract sits next to the screen it
//      protects).
//   8. ScreenProtector is never invoked in widget tests (release-only path
//      guarded by `!kDebugMode`).

import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_tokens.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/done_screen.dart';
import 'package:beautica_mobile/features/auth/presentation/widgets/registration_progress.dart';
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

/// Builds a minimal GoRouter with the DoneScreen at /done and a /home
/// scaffold that the two CTAs navigate to.
GoRouter _makeRouter() => GoRouter(
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
          const Scaffold(body: Center(child: Text('home-route'))),
    ),
  ],
);

/// Pumps the DoneScreen inside a UncontrolledProviderScope so that callers
/// can pre-seed and later read the [registerDraftProvider] across the test.
///
/// When [authenticatedUser] is non-null, the FakeAuthRepository is wired to
/// resolve cold-start refresh into an Authenticated session — that's how
/// [currentUserProvider] picks up the user the screen renders.
Future<ProviderContainer> _pumpDoneScreen(
  WidgetTester tester, {
  User? authenticatedUser,
  required GoRouter router,
}) async {
  final storage = FakeSecureStorage();
  final repo = FakeAuthRepository();

  if (authenticatedUser != null) {
    // Seed the secure-storage refresh token so AuthNotifier's background
    // restore picks up the session, then point the fake repo at our test
    // user + tokens.
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

  // Drain the AuthNotifier background restore so the screen sees the
  // settled Authenticated session (when seeded). The DoneScreen's own
  // post-frame draft-reset callback also fires during pumpAndSettle.
  await tester.pumpAndSettle();

  return container;
}

/// Convenience: looks up the AppLocalizations for the rendered uk locale.
AppLocalizations _l10n(WidgetTester tester) {
  return AppLocalizations.of(
    tester.element(find.byKey(const Key('brand-row'))),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('DoneScreen', () {
    // -----------------------------------------------------------------------
    // Test 1 — 4-dot progress renders with "Готово" under dot 4
    // -----------------------------------------------------------------------
    testWidgets('1. renders RegistrationProgress with currentStep=done and the '
        '"Готово" active label under dot 4', (tester) async {
      final router = _makeRouter();
      addTearDown(router.dispose);

      await _pumpDoneScreen(
        tester,
        authenticatedUser: _userWithName,
        router: router,
      );

      // The shared widget is mounted.
      final progress = tester.widget<RegistrationProgress>(
        find.byKey(const Key('registration-progress')),
      );
      expect(progress.currentStep, equals(RegistrationStep.done));
      expect(
        progress.activeStepLabel,
        equals(_l10n(tester).registerProgressDone),
      );

      // The active label text is rendered exactly once under dot 4.
      expect(find.byKey(const Key('progress-active-label')), findsOneWidget);

      // All four progress dots are present.
      for (var i = 1; i <= 4; i++) {
        expect(find.byKey(Key('progress-step-$i')), findsOneWidget);
      }
    });

    // -----------------------------------------------------------------------
    // Test 2 — Personalised greeting renders the user's first name
    // -----------------------------------------------------------------------
    testWidgets(
      '2. renders "Вітаємо, {firstName}!" with the authenticated user\'s '
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
              'authenticated session — fallback is reserved for the '
              'no-name case',
        );

        // The italic-camel subtitle is the second visible line.
        final subtitle = tester.widget<Text>(
          find.byKey(const Key('done-subtitle')),
        );
        expect(subtitle.data, equals(_l10n(tester).registerDoneSubtitle));
      },
    );

    // -----------------------------------------------------------------------
    // Test 3 — Fallback greeting when User has no first name
    // -----------------------------------------------------------------------
    testWidgets(
      '3. falls back to the localised placeholder when User.firstName is null',
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
              'when User.firstName is null/empty the greeting must use the '
              'registerDoneGreetingFallback placeholder',
        );
      },
    );

    // -----------------------------------------------------------------------
    // Test 4 — Three summary chips render with role / email / ready labels
    // -----------------------------------------------------------------------
    testWidgets(
      '4. renders 3 summary chips with role / email / ready-fast text',
      (tester) async {
        final router = _makeRouter();
        addTearDown(router.dispose);

        await _pumpDoneScreen(
          tester,
          authenticatedUser: _userWithName,
          router: router,
        );

        // All three chip keys resolve.
        expect(find.byKey(const Key('done-chip-role')), findsOneWidget);
        expect(find.byKey(const Key('done-chip-email')), findsOneWidget);
        expect(find.byKey(const Key('done-chip-ready')), findsOneWidget);

        final l10n = _l10n(tester);

        // Role chip displays the user's role label (Client for _userWithName).
        expect(
          find.descendant(
            of: find.byKey(const Key('done-chip-role')),
            matching: find.text(l10n.roleClient),
          ),
          findsOneWidget,
        );

        // Email chip displays the user's email.
        expect(
          find.descendant(
            of: find.byKey(const Key('done-chip-email')),
            matching: find.text(_userWithName.email),
          ),
          findsOneWidget,
        );

        // Ready-fast chip displays the marketing line.
        expect(
          find.descendant(
            of: find.byKey(const Key('done-chip-ready')),
            matching: find.text(l10n.registerDoneChipReadyFast),
          ),
          findsOneWidget,
        );
      },
    );

    // -----------------------------------------------------------------------
    // Test 5 — Primary CTA navigates to /home
    // -----------------------------------------------------------------------
    testWidgets('5. tapping btn-go-to-app navigates the router to /home', (
      tester,
    ) async {
      final router = _makeRouter();
      addTearDown(router.dispose);

      await _pumpDoneScreen(
        tester,
        authenticatedUser: _userWithName,
        router: router,
      );

      // Sanity — the home route is not yet visible.
      expect(find.text('home-route'), findsNothing);

      // Scroll the CTA into the test viewport before tapping (800×600).
      await tester.ensureVisible(find.byKey(const Key('btn-go-to-app')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn-go-to-app')));
      await tester.pumpAndSettle();

      expect(
        find.text('home-route'),
        findsOneWidget,
        reason:
            'btn-go-to-app must call context.go(RouteNames.home) — the '
            'router lands on the /home placeholder scaffold',
      );
    });

    // -----------------------------------------------------------------------
    // Test 6 — Secondary link navigates to /home
    // -----------------------------------------------------------------------
    testWidgets('6. tapping btn-setup-later navigates the router to /home '
        '(Phase 4.x will divert this to /profile-setup)', (tester) async {
      final router = _makeRouter();
      addTearDown(router.dispose);

      await _pumpDoneScreen(
        tester,
        authenticatedUser: _userWithName,
        router: router,
      );

      expect(find.text('home-route'), findsNothing);

      await tester.ensureVisible(find.byKey(const Key('btn-setup-later')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn-setup-later')));
      await tester.pumpAndSettle();

      expect(
        find.text('home-route'),
        findsOneWidget,
        reason:
            'btn-setup-later must call context.go(RouteNames.home) until '
            'Phase 4.x adds a profile-setup screen',
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
        // First frame mounts DoneScreen; the post-frame callback fires
        // ref.read(registerDraftProvider.notifier).reset(). One pump drains
        // the microtask queue.
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
    // Test 8 — ScreenProtector is not invoked in widget tests
    //
    // The screen-protector plugin only fires in release builds via the
    // `!kDebugMode` guard. In widget tests kDebugMode is true, so the
    // method-channel call (which would throw MissingPluginException without
    // a mock binding) is skipped. The check below verifies the screen pumps
    // cleanly without us having to register a plugin mock.
    // -----------------------------------------------------------------------
    testWidgets('8. ScreenProtector is not invoked under kDebugMode (no '
        'MissingPluginException from the platform channel)', (tester) async {
      final router = _makeRouter();
      addTearDown(router.dispose);

      await _pumpDoneScreen(
        tester,
        authenticatedUser: _userWithName,
        router: router,
      );

      // If ScreenProtector.preventScreenshotOn had been called, the
      // platform channel would have logged a MissingPluginException and
      // the pump above would have thrown. Reaching this expect means the
      // !kDebugMode guard suppressed the call.
      expect(
        tester.takeException(),
        isNull,
        reason:
            'ScreenProtector must be guarded by !kDebugMode so widget '
            'tests do not hit the platform channel',
      );
    });
  });
}
