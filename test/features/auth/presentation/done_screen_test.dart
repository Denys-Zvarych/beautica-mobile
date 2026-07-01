// Phase 2.12 — Widget tests for DoneScreen (VelvetTouch redesign).
//
// Tests use a minimal GoRouter (initial route = /done → DoneScreen) so that
// `context.go(...)` inside the widget can navigate to /home for the two CTA
// flows. Auth state is controlled via ProviderScope overrides so the screen
// can read [currentUserProvider] for the personalised greeting + chips.
//
// Covered scenarios:
//   1.  Personalised greeting renders with the authenticated user's first name.
//   2.  Falls back to the l10n placeholder when User has no first name.
//   2b. Uses lastName as display name when firstName is null.
//   2c. Uses firstName alone when lastName is null.
//   3.  Three summary chips render (done_chip_role / done_chip_email /
//       done_chip_ready) with the expected label text.
//   4.  Role chip shows the role-derived label from UserRoleL10n (client).
//   5.  Tapping done_to_app navigates to /home.
//   6.  Mounting /done resets the in-flight registration draft (HIGH-1 regression).
//   7.  salonOwner role chip shows l10n.roleSalonOwner.
//   8.  Screen pumps without exceptions; VelvetHeader/VelvetLogo absent;
//       AuthScaffold back button absent (showBack: false);
//       72×72 icon tile present and correctly sized.
//   9.  No authenticated user: DoneScreen renders fallback greeting + client role
//       label without crashing.
//   10. independentMaster role chip shows l10n.roleIndependentMaster.
//   11. All three chips (done_chip_role, done_chip_email, done_chip_ready) are
//       on separate centered lines — each chip has a Center ancestor and no
//       two chips share a Row ancestor.
//   12. _SummaryChip overflow — Flexible wrapper regression guard: no overflow
//       in a 200 dp wide viewport and Flexible is present.
// Note: Test 6 (done_setup_later secondary CTA) was removed — widget no longer exists.

import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
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
      path: RouteNames.clientHome,
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('home-route'))),
    ),
  ],
);

/// Builds a router that additionally includes a /master/profile placeholder.
///
/// Required by Test D — independentMaster CTA navigates to masterProfile.
GoRouter _makeRouterWithMaster() => GoRouter(
  initialLocation: RouteNames.done,
  redirect: (context, state) => null,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.done,
      builder: (context, state) => const DoneScreen(),
    ),
    GoRoute(
      path: RouteNames.clientHome,
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('home-route'))),
    ),
    GoRoute(
      path: RouteNames.masterProfile,
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('master-profile-route'))),
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
  // DoneScreen has no VelvetHeader (intentionally omitted — post-auth screen).
  // Anchor on DoneScreen itself, which is always in the tree.
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
      '1. renders "Вітаємо, {displayName}!" with the authenticated user\'s '
      'full name (first + last) when both fields are present',
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
        // _userWithName has firstName='Анна' AND lastName='Коваль',
        // so _resolveDisplayName returns 'Анна Коваль'.
        expect(
          greeting.data,
          equals(_l10n(tester).registerDoneGreeting('Анна Коваль')),
          reason:
              'greeting must interpolate the full name (first + last) when '
              'both User.firstName and User.lastName are non-empty',
        );

        // Italic-camel subtitle is present.
        final subtitle = tester.widget<Text>(
          find.byKey(const Key('done-subtitle')),
        );
        expect(subtitle.data, equals(_l10n(tester).registerDoneSubtitle));
      },
    );

    // -----------------------------------------------------------------------
    // Test 2 — Fallback greeting when User has neither first nor last name
    // -----------------------------------------------------------------------
    testWidgets(
      '2. falls back to l10n placeholder when User has no firstName and no '
      'lastName (email address must never appear in the greeting)',
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
        // _userWithoutName has no firstName and no lastName.
        // _resolveDisplayName must return the l10n fallback — never the
        // email address or its local-part.
        expect(
          greeting.data,
          equals(l10n.registerDoneGreeting(l10n.registerDoneGreetingFallback)),
          reason:
              'when both User.firstName and User.lastName are null/empty the '
              'greeting must use registerDoneGreetingFallback — the email '
              'address must never appear in the greeting text',
        );
        // Confirm the raw email string does NOT appear anywhere on screen.
        expect(
          find.textContaining('noname@beautica.test'),
          findsNothing,
          reason: 'email address must not appear anywhere in the greeting UI',
        );
      },
    );

    // -----------------------------------------------------------------------
    // Test 2b — last-name-only fallback when firstName is null but lastName
    //           is non-null.
    // -----------------------------------------------------------------------
    testWidgets(
      '2b. uses lastName as display name when firstName is null but lastName '
      'is non-empty',
      (tester) async {
        const userLastNameOnly = User(
          id: 'u3',
          email: 'lastnameonly@beautica.test',
          role: UserRole.client,
          // firstName is intentionally omitted (null).
          lastName: 'Шевченко',
        );

        final router = _makeRouter();
        addTearDown(router.dispose);

        await _pumpDoneScreen(
          tester,
          authenticatedUser: userLastNameOnly,
          router: router,
        );

        final greeting = tester.widget<Text>(
          find.byKey(const Key('done-greeting')),
        );
        expect(
          greeting.data,
          equals(_l10n(tester).registerDoneGreeting('Шевченко')),
          reason:
              'when User.firstName is null but User.lastName is non-empty '
              '_resolveDisplayName must return the lastName alone',
        );
      },
    );

    // -----------------------------------------------------------------------
    // Test 2c — firstName-only path: firstName non-empty, lastName null.
    //           Covers the B3 branch of _resolveDisplayName, which was not
    //           previously exercised by any test in the suite.
    // -----------------------------------------------------------------------
    testWidgets(
      '2c. uses firstName as display name when firstName is non-empty but '
      'lastName is null (email address must never appear on screen)',
      (tester) async {
        const userFirstNameOnly = User(
          id: 'u4',
          email: 'firstnameonly@beautica.test',
          role: UserRole.client,
          firstName: 'Олег',
          // lastName intentionally omitted (null) — exercises B3 branch.
        );

        final router = _makeRouter();
        addTearDown(router.dispose);

        await _pumpDoneScreen(
          tester,
          authenticatedUser: userFirstNameOnly,
          router: router,
        );

        final greeting = tester.widget<Text>(
          find.byKey(const Key('done-greeting')),
        );
        expect(
          greeting.data,
          equals(_l10n(tester).registerDoneGreeting('Олег')),
          reason:
              'when User.firstName is non-empty and User.lastName is null '
              '_resolveDisplayName must return the firstName alone (B3 branch)',
        );

        // Email-safety invariant: the raw email address must not appear
        // anywhere in the UI, even as part of a chip or subtitle widget.
        expect(
          find.textContaining('firstnameonly@beautica.test'),
          findsNothing,
          reason: 'email address must never be surfaced in the greeting UI',
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
    // Test 6 — /done resets the registration draft (HIGH-1 regression)
    // -----------------------------------------------------------------------
    testWidgets(
      '6. mounting /done resets the in-flight registration draft to null '
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
    // Test 7 — salonOwner role chip label
    //
    // salonOwner is an invite-only role — a salonOwner cannot self-register.
    // However, a user with role salonOwner can land on DoneScreen after
    // accepting an invitation. This test exercises the chip label path for
    // that role, confirming UserRoleL10n.label() maps salonOwner correctly.
    // -----------------------------------------------------------------------
    testWidgets(
      '7. salonOwner role chip shows the roleSalonOwner localised label',
      (tester) async {
        const userSalonOwner = User(
          id: 'u5',
          email: 'owner@salon.test',
          role: UserRole.salonOwner,
          firstName: 'Олена',
          lastName: 'Бойко',
        );

        final router = _makeRouter();
        addTearDown(router.dispose);

        await _pumpDoneScreen(
          tester,
          authenticatedUser: userSalonOwner,
          router: router,
        );

        final l10n = _l10n(tester);

        expect(
          find.descendant(
            of: find.byKey(const ValueKey<String>('done_chip_role')),
            matching: find.text(l10n.roleSalonOwner),
          ),
          findsOneWidget,
          reason:
              'For UserRole.salonOwner (invite-only, but reachable via invite '
              'accept flow) the role chip must show l10n.roleSalonOwner.',
        );
      },
    );

    // -----------------------------------------------------------------------
    // Test 8 — Screen pumps cleanly; structural absence/presence guards
    //
    // Verifies four structural invariants in a single pump:
    //  a. No platform-channel exceptions (ScreenProtector removed).
    //  b. VelvetHeader is absent (DoneScreen is post-auth — no brand header).
    //  c. VelvetLogo is absent (same reason as b).
    //  d. AuthScaffold back button is absent (showBack: false).
    //  e. 72×72 icon tile is present and correctly sized.
    // -----------------------------------------------------------------------
    testWidgets(
      '8. DoneScreen pumps without exception; VelvetHeader and VelvetLogo are '
      'absent; back button absent (showBack: false); 72×72 icon tile present',
      (tester) async {
        final router = _makeRouter();
        addTearDown(router.dispose);

        await _pumpDoneScreen(
          tester,
          authenticatedUser: _userWithName,
          router: router,
        );

        // a. No platform-channel exceptions from ScreenProtector.
        expect(
          tester.takeException(),
          isNull,
          reason:
              'DoneScreen must pump cleanly — no platform channel calls '
              'that require a mock binding',
        );

        // b. VelvetHeader must not be present — DoneScreen is post-auth.
        expect(
          find.byType(VelvetHeader),
          findsNothing,
          reason: 'DoneScreen is post-auth — VelvetHeader must not be present',
        );

        // c. VelvetLogo must not be present.
        expect(
          find.byType(VelvetLogo),
          findsNothing,
          reason: 'DoneScreen is post-auth — VelvetLogo must not be present',
        );

        // d. AuthScaffold back button must not be present (showBack: false).
        // AuthScaffold renders a NeumorphicIconButton with key 'auth_scaffold_back'
        // when showBack is true. When false, no BackButton or back affordance
        // is rendered at all.
        expect(
          find.byKey(const ValueKey<String>('auth_scaffold_back')),
          findsNothing,
          reason:
              'DoneScreen passes showBack: false to AuthScaffold — no back '
              'affordance must be present in the widget tree',
        );
        expect(
          find.byType(BackButton),
          findsNothing,
          reason: 'DoneScreen showBack: false — no BackButton must be present',
        );

        // e. 72×72 icon tile is present and correctly sized.
        expect(
          find.byKey(const Key('done-icon-tile')),
          findsOneWidget,
          reason: 'The 72×72 check-mark container must be rendered',
        );
        final tileSize = tester.getSize(
          find.byKey(const Key('done-icon-tile')),
        );
        expect(
          tileSize.width,
          closeTo(72, 1),
          reason: 'Icon tile width must be 72 dp',
        );
        expect(
          tileSize.height,
          closeTo(72, 1),
          reason: 'Icon tile height must be 72 dp',
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
    // Test 11 — Structural assertion: 3-line centered chip layout
    //
    // All three chips (done_chip_role, done_chip_email, done_chip_ready) must
    // each be on their own separate centered line — i.e. every chip must have
    // a Center ancestor and no chip may share a Row ancestor with another chip.
    // -----------------------------------------------------------------------
    testWidgets('11. all three chips are on separate centered lines', (
      tester,
    ) async {
      final router = _makeRouter();
      addTearDown(router.dispose);

      await _pumpDoneScreen(
        tester,
        authenticatedUser: _userWithName,
        router: router,
      );

      final roleElement = tester.element(
        find.byKey(const ValueKey<String>('done_chip_role')),
      );
      final emailElement = tester.element(
        find.byKey(const ValueKey<String>('done_chip_email')),
      );
      final readyElement = tester.element(
        find.byKey(const ValueKey<String>('done_chip_ready')),
      );

      // Each chip must have a Center ancestor.
      bool roleHasCenter = false;
      roleElement.visitAncestorElements((el) {
        if (el.widget is Center) {
          roleHasCenter = true;
          return false;
        }
        return true;
      });
      expect(
        roleHasCenter,
        isTrue,
        reason: 'done_chip_role must be wrapped in Center (line 1)',
      );

      bool emailHasCenter = false;
      emailElement.visitAncestorElements((el) {
        if (el.widget is Center) {
          emailHasCenter = true;
          return false;
        }
        return true;
      });
      expect(
        emailHasCenter,
        isTrue,
        reason: 'done_chip_email must be wrapped in Center (line 2)',
      );

      bool readyHasCenter = false;
      readyElement.visitAncestorElements((el) {
        if (el.widget is Center) {
          readyHasCenter = true;
          return false;
        }
        return true;
      });
      expect(
        readyHasCenter,
        isTrue,
        reason: 'done_chip_ready must be wrapped in Center (line 3)',
      );

      // No two chips may share a Row ancestor — collect each chip's nearest
      // Row ancestor (null if none exists) and verify they are all distinct.
      Element? nearestRow(Element start) {
        Element? found;
        start.visitAncestorElements((el) {
          if (el.widget is Row) {
            found = el;
            return false;
          }
          return true;
        });
        return found;
      }

      final roleRow = nearestRow(roleElement);
      final emailRow = nearestRow(emailElement);
      final readyRow = nearestRow(readyElement);

      // If a chip has no Row ancestor at all the constraint is satisfied for
      // that chip; we only need to verify that no two chips share the same Row.
      if (roleRow != null) {
        expect(
          emailRow,
          isNot(equals(roleRow)),
          reason:
              'done_chip_email must not share a Row ancestor with done_chip_role',
        );
        expect(
          readyRow,
          isNot(equals(roleRow)),
          reason:
              'done_chip_ready must not share a Row ancestor with done_chip_role',
        );
      }
      if (emailRow != null) {
        expect(
          readyRow,
          isNot(equals(emailRow)),
          reason:
              'done_chip_ready must not share a Row ancestor with done_chip_email',
        );
      }
    });

    // -----------------------------------------------------------------------
    // Test A — shows registerDoneDescMaster when role is independentMaster
    // -----------------------------------------------------------------------
    testWidgets('A. shows registerDoneDescMaster description when role is '
        'independentMaster', (tester) async {
      // _userWithoutName has role == UserRole.independentMaster.
      final router = _makeRouter();
      addTearDown(router.dispose);

      await _pumpDoneScreen(
        tester,
        authenticatedUser: _userWithoutName,
        router: router,
      );

      final l10n = _l10n(tester);

      final descWidget = tester.widget<Text>(
        find.byKey(const Key('done-desc')),
      );
      expect(
        descWidget.data,
        equals(l10n.registerDoneDescMaster),
        reason:
            'For UserRole.independentMaster the description must use '
            'registerDoneDescMaster',
      );
      expect(
        descWidget.data,
        isNot(equals(l10n.registerDoneDesc)),
        reason:
            'The client description (registerDoneDesc) must NOT appear '
            'for an independentMaster user',
      );
    });

    // -----------------------------------------------------------------------
    // Test B — shows registerDoneDescMaster when role is salonMaster
    // -----------------------------------------------------------------------
    testWidgets(
      'B. shows registerDoneDescMaster description when role is salonMaster',
      (tester) async {
        const userSalonMaster = User(
          id: 'u6',
          email: 'master@salon.test',
          role: UserRole.salonMaster,
          firstName: 'Марина',
          lastName: 'Петренко',
        );

        final router = _makeRouter();
        addTearDown(router.dispose);

        await _pumpDoneScreen(
          tester,
          authenticatedUser: userSalonMaster,
          router: router,
        );

        final l10n = _l10n(tester);

        final descWidget = tester.widget<Text>(
          find.byKey(const Key('done-desc')),
        );
        expect(
          descWidget.data,
          equals(l10n.registerDoneDescMaster),
          reason:
              'For UserRole.salonMaster the description must use '
              'registerDoneDescMaster (same branch as independentMaster)',
        );
      },
    );

    // -----------------------------------------------------------------------
    // Test C — shows registerDoneDesc for client role
    // -----------------------------------------------------------------------
    testWidgets(
      'C. shows registerDoneDesc (client description) when role is client',
      (tester) async {
        // _userWithName has role == UserRole.client.
        final router = _makeRouter();
        addTearDown(router.dispose);

        await _pumpDoneScreen(
          tester,
          authenticatedUser: _userWithName,
          router: router,
        );

        final l10n = _l10n(tester);

        final descWidget = tester.widget<Text>(
          find.byKey(const Key('done-desc')),
        );
        expect(
          descWidget.data,
          equals(l10n.registerDoneDesc),
          reason:
              'For UserRole.client the description must use registerDoneDesc',
        );
        expect(
          descWidget.data,
          isNot(equals(l10n.registerDoneDescMaster)),
          reason:
              'The master description (registerDoneDescMaster) must NOT '
              'appear for a client user',
        );
      },
    );

    // -----------------------------------------------------------------------
    // Test D — independentMaster CTA navigates to masterProfile
    // -----------------------------------------------------------------------
    testWidgets(
      'D. tapping done_to_app navigates to masterProfile when role is '
      'independentMaster',
      (tester) async {
        // _userWithoutName has role == UserRole.independentMaster.
        final router = _makeRouterWithMaster();
        addTearDown(router.dispose);

        await _pumpDoneScreen(
          tester,
          authenticatedUser: _userWithoutName,
          router: router,
        );

        // masterProfile placeholder must not be visible yet.
        expect(find.text('master-profile-route'), findsNothing);

        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('done_to_app')),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey<String>('done_to_app')));
        await tester.pumpAndSettle();

        expect(
          find.text('master-profile-route'),
          findsOneWidget,
          reason:
              'done_to_app must call context.go(RouteNames.masterProfile) '
              'when the authenticated user has role independentMaster',
        );
        // Home placeholder must not be shown — wrong destination.
        expect(
          find.text('home-route'),
          findsNothing,
          reason:
              'independentMaster CTA must route to masterProfile, not /home',
        );
      },
    );

    // -----------------------------------------------------------------------
    // Test 12 — _SummaryChip overflow regression guard [HIGH]
    //
    // Regression: without the Flexible wrapper the chip's Text overflows its
    // Row when the label is long and the viewport is narrow. This test pumps
    // the done screen inside a 200 dp wide SizedBox so the two side-by-side
    // chips cannot display "Пошта підтверджена" without truncation. The test
    // asserts:
    //   a. No overflow exception is thrown (tester.takeException() is null).
    //   b. At least one Flexible widget exists in the tree that is a descendant
    //      of done_chip_email — proving the Flexible wrapper is present.
    // -----------------------------------------------------------------------
    testWidgets(
      '12. _SummaryChip overflow — Flexible wrapper regression guard: '
      'no overflow in a 200 dp wide viewport and Flexible is present',
      (tester) async {
        // Constrain the viewport to 200 logical pixels — narrow enough that
        // "Пошта підтверджена" would overflow without the Flexible wrapper.
        tester.view.physicalSize = const Size(200 * 3, 800 * 3);
        tester.view.devicePixelRatio = 3.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final router = _makeRouter();
        addTearDown(router.dispose);

        await _pumpDoneScreen(
          tester,
          authenticatedUser: _userWithName,
          router: router,
        );

        // a. No overflow exception must be thrown.
        expect(
          tester.takeException(),
          isNull,
          reason:
              '_SummaryChip must not throw a layout overflow exception '
              'in a narrow (200 dp) viewport — Flexible must prevent it',
        );

        // b. At least one Flexible must be a descendant of done_chip_email,
        //    confirming the Flexible wrapper is present in the chip tree.
        final emailChipFinder = find.byKey(
          const ValueKey<String>('done_chip_email'),
        );
        expect(
          emailChipFinder,
          findsOneWidget,
          reason: 'done_chip_email chip must be rendered',
        );
        expect(
          find.descendant(of: emailChipFinder, matching: find.byType(Flexible)),
          findsAtLeastNWidgets(1),
          reason:
              '_SummaryChip.build() must wrap the label Text in a Flexible '
              'widget to prevent overflow — regression guard for the fix in '
              'lib/features/auth/presentation/done_screen.dart',
        );
      },
    );
  });
}
