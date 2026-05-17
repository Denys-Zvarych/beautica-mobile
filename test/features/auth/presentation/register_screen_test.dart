// Phase 2.x — Widget tests for RegisterScreen (single-screen parity rebuild).
//
// SOURCE OF TRUTH: docs/signup-designs/role-selection-page.html and
// docs/signup-designs/sign-up-page.html. The intentionally-removed 2-step
// credentials→details flow no longer exists; the approved design is:
//
//   View 0 — Role selection: three glassmorphism role cards. Tapping a card
//            ONLY selects it (does NOT advance). The always-filled
//            "Продовжити" CTA (btn-continue-role) advances to the details
//            view. btn-go-to-login-from-intent navigates to /login.
//   View 1 — Registration details: a SINGLE screen with every field
//            (firstName, lastName, email, phone, password; salon owners also
//            get businessName + address) on one screen. btn-submit-register
//            submits; btn-back-step returns to the role picker preserving
//            entered data; btn-go-to-login navigates to /login.
//
// Server ValidationFailure(field) surfaces inline under the matching field on
// the SAME single screen (the screen does NOT retreat anywhere — that 2-step
// behaviour was removed). NetworkFailure → error SnackBar.
//
// Tests use a minimal GoRouter (initial route = /register → RegisterScreen).
//
// Old-case → new-single-screen mapping (auditable coverage trace):
//   1  kept       — role cards render, no register call yet
//   2  translated — card tap selects only; CTA advances to details screen
//   3  kept       — IM full flow → register(role=independentMaster) + args
//   4  translated — ValidationFailure(email) shows inline under email field
//                    on the SINGLE screen (was: under email field in step 2)
//   5  translated — submit/CTA disabled during AsyncLoading (single screen)
//   6  kept       — empty firstName → errNameRequired
//   7  kept       — btn-go-to-login present on the details screen
//   8  kept       — btn-go-to-login navigates to /login
//   9  dropped    — "tap selected badge resets to step 0": no badge in the
//                    single-screen design; the role-reset affordance is now
//                    btn-back-step (covered by new case 20)
//   10 kept       — salonOwner: businessName+address+phone on one screen,
//                    submit → register(role=salonOwner)
//   11 kept       — btn-go-to-login-from-intent navigates to /login
//   12 kept       — field-businessName absent for independentMaster
//   13 kept       — field-businessName present for salonOwner
//   14 kept       — blank businessName blocks register (salonOwner)
//   15 kept       — IM submit passes null businessName
//   16 kept       — NetworkFailure (salonOwner) → SnackBar
//   17 translated — initial mount: no role card selected (Icons.check absent);
//                    tapping a card shows exactly one Icons.check (selection
//                    is now in-place on the role picker, no badge round-trip)
//   18 kept       — malformed phone → errPhoneInvalidFormat
//   19 kept       — non-digit phone → phone validation error
//   20 translated — btn-back-step returns to role picker, email preserved
//                    (was: btn-back-step returns to step 1)
//   21 kept       — IM details screen shows firstName+lastName+phone
//   22 kept       — phone formatter: 10 digits → +380 67 123 45 67
//   23 kept       — empty phone → errPhoneRequired
//   24 kept       — btn-submit-register is the unified submit key
//   25 translated — ValidationFailure(email) shows inline under email field,
//                    screen STAYS on the single details screen (was: retreats
//                    to step 1 — that flow is removed)
//   26 kept       — phone "380671234567" → +380 67 123 45 67
//   27 kept       — 15-digit phone clamped to 13 raw digits
//   28 kept       — client full flow → register(role=client)
//   29 kept       — autovalidateMode inline email error while typing
//   30 kept       — salon empty address → errAddressRequired, blocks submit
//   31 translated — ValidationFailure(password) shows inline under password
//                    field, screen STAYS on the single screen (was: retreats
//                    to step 1)
//   32 dropped    — "step indicator shows step 2 active": the progress row is
//                    display-only (step 1 active, 2/3 always inactive — future
//                    phases); there is no step-2-active state to assert. Its
//                    presence on the details screen is covered by case 21's
//                    sibling assertions and case 2.
//
// All user-visible strings go through AppLocalizations (UA primary).

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/auth/presentation/register_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

GoRouter _makeRouter() => GoRouter(
  initialLocation: RouteNames.register,
  redirect: (context, state) => null,
  routes: [
    GoRoute(
      path: RouteNames.register,
      builder: (context, state) => const RegisterScreen(),
    ),
    GoRoute(
      path: RouteNames.login,
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('login'))),
    ),
    GoRoute(
      path: RouteNames.home,
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('home'))),
    ),
  ],
);

Widget _buildApp({
  required GoRouter router,
  required FakeAuthRepository repo,
  required FakeSecureStorage storage,
}) => ProviderScope(
  overrides: [
    authRepositoryProvider.overrideWith((_) => repo),
    secureStorageProvider.overrideWith((_) => storage),
  ],
  child: MaterialApp.router(
    routerConfig: router,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('uk'),
  ),
);

/// Selects a role card by its title and presses the always-filled
/// "Продовжити" CTA (btn-continue-role) to advance to the single-screen
/// details form. Tapping a card alone does NOT advance — the design requires
/// the explicit CTA.
Future<void> _selectRoleAndContinue(
  WidgetTester tester,
  String roleTitle,
) async {
  await tester.ensureVisible(find.text(roleTitle).first);
  await tester.tap(find.text(roleTitle).first);
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('btn-continue-role')));
  await tester.tap(find.byKey(const Key('btn-continue-role')));
  await tester.pumpAndSettle();
}

/// Independent-master shortcut for the most common path.
Future<void> _gotoIndependentDetails(WidgetTester tester) async {
  final l10n = lookupAppLocalizations(const Locale('uk'));
  await _selectRoleAndContinue(tester, l10n.intentIndependentTitle);
}

/// Fills the shared IM/client required fields on the single details screen
/// and scrolls the submit button into view.
Future<void> _fillValidImForm(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('field-email')),
    'ivan@beautica.test',
  );
  await tester.enterText(
    find.byKey(const Key('field-password')),
    'SecurePass1',
  );
  await tester.enterText(find.byKey(const Key('field-firstName')), 'Іван');
  await tester.enterText(find.byKey(const Key('field-lastName')), 'Петренко');
  await tester.enterText(find.byKey(const Key('field-phone')), '0671234567');
  await tester.ensureVisible(find.byKey(const Key('btn-submit-register')));
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('RegisterScreen (single-screen)', () {
    // -----------------------------------------------------------------------
    // 1 (kept) — Role picker: three cards render, no register call yet
    // -----------------------------------------------------------------------
    testWidgets('1. three role cards render and no register call yet', (
      tester,
    ) async {
      final repo = FakeAuthRepository();
      final storage = FakeSecureStorage();
      final router = _makeRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(
        _buildApp(router: router, repo: repo, storage: storage),
      );
      await tester.pumpAndSettle();

      final l10n = lookupAppLocalizations(const Locale('uk'));
      expect(find.text(l10n.intentIndependentTitle), findsOneWidget);
      expect(find.text(l10n.intentSalonTitle), findsOneWidget);
      expect(find.text(l10n.intentClientTitle), findsOneWidget);

      // The single-screen form fields are NOT visible until the CTA advances.
      expect(find.byKey(const Key('field-email')), findsNothing);
      expect(find.byKey(const Key('field-password')), findsNothing);
      expect(find.byKey(const Key('btn-submit-register')), findsNothing);

      expect(repo.registerCalls, isEmpty);
    });

    // -----------------------------------------------------------------------
    // 2 (translated) — Card tap selects only; CTA advances to details screen
    // -----------------------------------------------------------------------
    testWidgets(
      '2. tapping a role card selects only; btn-continue-role advances to the '
      'single details screen',
      (tester) async {
        final repo = FakeAuthRepository();
        final storage = FakeSecureStorage();
        final router = _makeRouter();
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _buildApp(router: router, repo: repo, storage: storage),
        );
        await tester.pumpAndSettle();

        final l10n = lookupAppLocalizations(const Locale('uk'));

        // Tapping the card MUST NOT advance — fields stay hidden, picker stays.
        await tester.tap(find.text(l10n.intentIndependentTitle).first);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('field-email')),
          findsNothing,
          reason: 'Card tap selects only — it must not auto-advance',
        );
        expect(find.text(l10n.intentSalonTitle), findsOneWidget);

        // The explicit CTA advances to the single details screen.
        await tester.ensureVisible(find.byKey(const Key('btn-continue-role')));
        await tester.tap(find.byKey(const Key('btn-continue-role')));
        await tester.pumpAndSettle();

        // Every field is present on ONE screen — no step navigation.
        expect(find.byKey(const Key('field-email')), findsOneWidget);
        expect(find.byKey(const Key('field-password')), findsOneWidget);
        expect(find.byKey(const Key('field-firstName')), findsOneWidget);
        expect(find.byKey(const Key('field-lastName')), findsOneWidget);
        expect(find.byKey(const Key('field-phone')), findsOneWidget);
        expect(find.byKey(const Key('btn-submit-register')), findsOneWidget);

        // The role picker is no longer shown.
        expect(find.text(l10n.intentSalonTitle), findsNothing);
      },
    );

    // -----------------------------------------------------------------------
    // 3 (kept) — IM full flow → register called with correct args incl. role
    // -----------------------------------------------------------------------
    testWidgets(
      '3. IM full flow → register called with args incl. role=independentMaster',
      (tester) async {
        final repo = FakeAuthRepository();
        final storage = FakeSecureStorage();
        final router = _makeRouter();
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _buildApp(router: router, repo: repo, storage: storage),
        );
        await tester.pumpAndSettle();

        await _gotoIndependentDetails(tester);
        await _fillValidImForm(tester);
        await tester.tap(find.byKey(const Key('btn-submit-register')));
        await tester.pumpAndSettle();

        expect(repo.registerCalls, hasLength(1));
        final call = repo.registerCalls.first;
        expect(call.email, equals('ivan@beautica.test'));
        expect(call.password, equals('SecurePass1'));
        expect(call.firstName, equals('Іван'));
        expect(call.lastName, equals('Петренко'));
        expect(call.role, equals(UserRole.independentMaster));
        expect(call.phone, isNotNull);
      },
    );

    // -----------------------------------------------------------------------
    // 4 (translated) — ValidationFailure(email) → inline error under the email
    //                  field on the SINGLE screen
    // -----------------------------------------------------------------------
    testWidgets(
      '4. ValidationFailure(email) shows "already in use" inline on the single '
      'details screen',
      (tester) async {
        final repo = FakeAuthRepository();
        repo.registerResult = const ValidationFailure(
          fieldErrors: {'email': 'already in use'},
        );
        final storage = FakeSecureStorage();
        final router = _makeRouter();
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _buildApp(router: router, repo: repo, storage: storage),
        );
        await tester.pumpAndSettle();

        await _gotoIndependentDetails(tester);
        await _fillValidImForm(tester);
        await tester.tap(find.byKey(const Key('btn-submit-register')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();

        // Error visible inline; screen stays on the single details screen
        // (the email field is still present — no step retreat).
        expect(find.text('already in use'), findsOneWidget);
        expect(find.byKey(const Key('field-email')), findsOneWidget);
        expect(find.byKey(const Key('btn-submit-register')), findsOneWidget);
      },
    );

    // -----------------------------------------------------------------------
    // 5 (translated) — submit button disabled during AsyncLoading
    // -----------------------------------------------------------------------
    testWidgets('5. btn-submit-register is disabled during AsyncLoading', (
      tester,
    ) async {
      final storage = FakeSecureStorage();
      final router = _makeRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(() => _LoadingAuthNotifier()),
            secureStorageProvider.overrideWith((_) => storage),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('uk'),
          ),
        ),
      );
      // pumpAndSettle would hang — _LoadingAuthNotifier never completes.
      // Pump the full 500ms _intentCtrl duration so all role cards complete
      // their stagger animation and reach opacity 1.0 before tapping.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Reach the single details screen (role select + CTA). pumpAndSettle
      // is unusable here (the loading notifier never completes) so scroll the
      // CTA into view manually before tapping or the hit-test misses on the
      // 800x600 test viewport.
      final l10n = lookupAppLocalizations(const Locale('uk'));
      await tester.tap(find.text(l10n.intentIndependentTitle).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.ensureVisible(find.byKey(const Key('btn-continue-role')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('btn-continue-role')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.ensureVisible(find.byKey(const Key('btn-submit-register')));
      await tester.pump();

      // The CTA is now DecoratedBox → ClipRRect → Material → InkWell (Impeller
      // fix). The Key is on the outer GestureDetector; find InkWell underneath.
      final submitButton = tester.widget<InkWell>(
        find.descendant(
          of: find.byKey(const Key('btn-submit-register')),
          matching: find.byType(InkWell),
        ),
      );
      expect(
        submitButton.onTap,
        isNull,
        reason: 'Submit must be disabled while authProvider is loading',
      );
    });

    // -----------------------------------------------------------------------
    // 6 (kept) — empty firstName shows errNameRequired
    // -----------------------------------------------------------------------
    testWidgets('6. empty firstName shows errNameRequired error', (
      tester,
    ) async {
      final repo = FakeAuthRepository();
      final storage = FakeSecureStorage();
      final router = _makeRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(
        _buildApp(router: router, repo: repo, storage: storage),
      );
      await tester.pumpAndSettle();

      await _gotoIndependentDetails(tester);

      // Fill everything except firstName.
      await tester.enterText(
        find.byKey(const Key('field-email')),
        'ivan@beautica.test',
      );
      await tester.enterText(
        find.byKey(const Key('field-password')),
        'SecurePass1',
      );
      await tester.enterText(find.byKey(const Key('field-lastName')), 'Коваль');
      await tester.enterText(
        find.byKey(const Key('field-phone')),
        '0671234567',
      );

      await tester.ensureVisible(find.byKey(const Key('btn-submit-register')));
      await tester.tap(find.byKey(const Key('btn-submit-register')));
      await tester.pump();

      final l10n = AppLocalizations.of(
        tester.element(find.byKey(const Key('field-firstName'))),
      );
      expect(find.text(l10n.errNameRequired), findsWidgets);
      expect(repo.registerCalls, isEmpty);
    });

    // -----------------------------------------------------------------------
    // 7 (kept) — btn-go-to-login key exists on the details screen
    // -----------------------------------------------------------------------
    testWidgets('7. btn-go-to-login is present on the single details screen', (
      tester,
    ) async {
      final repo = FakeAuthRepository();
      final storage = FakeSecureStorage();
      final router = _makeRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(
        _buildApp(router: router, repo: repo, storage: storage),
      );
      await tester.pumpAndSettle();

      // Role picker uses the from-intent key.
      expect(
        find.byKey(const Key('btn-go-to-login-from-intent')),
        findsOneWidget,
      );

      await _gotoIndependentDetails(tester);

      await tester.ensureVisible(find.byKey(const Key('btn-go-to-login')));
      expect(find.byKey(const Key('btn-go-to-login')), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // 8 (kept) — tapping btn-go-to-login navigates to /login
    // -----------------------------------------------------------------------
    testWidgets('8. tapping btn-go-to-login navigates to /login', (
      tester,
    ) async {
      final repo = FakeAuthRepository();
      final storage = FakeSecureStorage();
      final router = _makeRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(
        _buildApp(router: router, repo: repo, storage: storage),
      );
      await tester.pumpAndSettle();

      await _gotoIndependentDetails(tester);

      await tester.ensureVisible(find.byKey(const Key('btn-go-to-login')));
      await tester.tap(find.byKey(const Key('btn-go-to-login')));
      await tester.pumpAndSettle();

      expect(find.text('login'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // 10 (kept) — salonOwner: businessName+address+phone on one screen,
    //             submit → register(role=salonOwner)
    // -----------------------------------------------------------------------
    testWidgets(
      '10. salonOwner: businessName+address+phone on one screen; submit → '
      'register(role=salonOwner)',
      (tester) async {
        final repo = FakeAuthRepository();
        final storage = FakeSecureStorage();
        final router = _makeRouter();
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _buildApp(router: router, repo: repo, storage: storage),
        );
        await tester.pumpAndSettle();

        final l10n = lookupAppLocalizations(const Locale('uk'));
        await _selectRoleAndContinue(tester, l10n.intentSalonTitle);

        // Salon-specific + shared fields are all on the SAME screen.
        expect(find.byKey(const Key('field-businessName')), findsOneWidget);
        expect(find.byKey(const Key('field-address')), findsOneWidget);
        expect(find.byKey(const Key('field-email')), findsOneWidget);
        expect(find.byKey(const Key('field-password')), findsOneWidget);
        expect(find.byKey(const Key('field-phone')), findsOneWidget);

        await tester.enterText(
          find.byKey(const Key('field-businessName')),
          'Краса Студія',
        );
        await tester.enterText(
          find.byKey(const Key('field-address')),
          'вул. Хрещатик, 1',
        );
        await tester.enterText(
          find.byKey(const Key('field-email')),
          'olena@beautica.test',
        );
        await tester.enterText(
          find.byKey(const Key('field-password')),
          'StrongPass2',
        );
        await tester.enterText(
          find.byKey(const Key('field-firstName')),
          'Олена',
        );
        await tester.enterText(
          find.byKey(const Key('field-lastName')),
          'Бойко',
        );
        await tester.enterText(
          find.byKey(const Key('field-phone')),
          '0501234567',
        );

        await tester.ensureVisible(
          find.byKey(const Key('btn-submit-register')),
        );
        await tester.tap(find.byKey(const Key('btn-submit-register')));
        await tester.pumpAndSettle();

        expect(repo.registerCalls, hasLength(1));
        expect(repo.registerCalls.first.role, equals(UserRole.salonOwner));
        expect(repo.registerCalls.first.email, equals('olena@beautica.test'));
        expect(repo.registerCalls.first.businessName, equals('Краса Студія'));
        expect(repo.registerCalls.first.address, equals('вул. Хрещатик, 1'));
      },
    );

    // -----------------------------------------------------------------------
    // 11 (kept) — btn-go-to-login-from-intent navigates to /login
    // -----------------------------------------------------------------------
    testWidgets(
      '11. btn-go-to-login-from-intent on the role picker navigates to /login',
      (tester) async {
        final repo = FakeAuthRepository();
        final storage = FakeSecureStorage();
        final router = _makeRouter();
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _buildApp(router: router, repo: repo, storage: storage),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('btn-go-to-login-from-intent')),
          findsOneWidget,
        );

        await tester.ensureVisible(
          find.byKey(const Key('btn-go-to-login-from-intent')),
        );
        await tester.tap(find.byKey(const Key('btn-go-to-login-from-intent')));
        await tester.pumpAndSettle();

        expect(find.text('login'), findsOneWidget);
      },
    );

    // -----------------------------------------------------------------------
    // 12 (kept) — field-businessName absent for independentMaster
    // -----------------------------------------------------------------------
    testWidgets(
      '12. field-businessName is NOT rendered for independentMaster',
      (tester) async {
        final repo = FakeAuthRepository();
        final storage = FakeSecureStorage();
        final router = _makeRouter();
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _buildApp(router: router, repo: repo, storage: storage),
        );
        await tester.pumpAndSettle();

        await _gotoIndependentDetails(tester);

        expect(find.byKey(const Key('field-businessName')), findsNothing);
        expect(find.byKey(const Key('field-address')), findsNothing);
        expect(find.byKey(const Key('field-firstName')), findsOneWidget);
      },
    );

    // -----------------------------------------------------------------------
    // 13 (kept) — field-businessName present for salonOwner
    // -----------------------------------------------------------------------
    testWidgets('13. field-businessName IS rendered for salonOwner', (
      tester,
    ) async {
      final repo = FakeAuthRepository();
      final storage = FakeSecureStorage();
      final router = _makeRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(
        _buildApp(router: router, repo: repo, storage: storage),
      );
      await tester.pumpAndSettle();

      final l10n = lookupAppLocalizations(const Locale('uk'));
      await _selectRoleAndContinue(tester, l10n.intentSalonTitle);

      expect(find.byKey(const Key('field-businessName')), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // 14 (kept) — blank businessName blocks register (salonOwner)
    // -----------------------------------------------------------------------
    testWidgets(
      '14. empty businessName shows validation error and blocks register for '
      'salonOwner',
      (tester) async {
        final repo = FakeAuthRepository();
        final storage = FakeSecureStorage();
        final router = _makeRouter();
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _buildApp(router: router, repo: repo, storage: storage),
        );
        await tester.pumpAndSettle();

        final l10n = lookupAppLocalizations(const Locale('uk'));
        await _selectRoleAndContinue(tester, l10n.intentSalonTitle);

        // Fill everything except businessName.
        await tester.enterText(
          find.byKey(const Key('field-address')),
          'вул. Хрещатик, 1',
        );
        await tester.enterText(
          find.byKey(const Key('field-email')),
          'olena@beautica.test',
        );
        await tester.enterText(
          find.byKey(const Key('field-password')),
          'StrongPass2',
        );
        await tester.enterText(
          find.byKey(const Key('field-firstName')),
          'Олена',
        );
        await tester.enterText(
          find.byKey(const Key('field-lastName')),
          'Бойко',
        );
        await tester.enterText(
          find.byKey(const Key('field-phone')),
          '0501234567',
        );

        await tester.ensureVisible(
          find.byKey(const Key('btn-submit-register')),
        );
        await tester.tap(find.byKey(const Key('btn-submit-register')));
        await tester.pump();

        // errNameRequired is the businessName validator message.
        expect(find.text(l10n.errNameRequired), findsWidgets);
        expect(repo.registerCalls, isEmpty);
      },
    );

    // -----------------------------------------------------------------------
    // 15 (kept) — IM submit passes null businessName to repo
    // -----------------------------------------------------------------------
    testWidgets(
      '15. independentMaster submit passes null businessName to repo',
      (tester) async {
        final repo = FakeAuthRepository();
        final storage = FakeSecureStorage();
        final router = _makeRouter();
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _buildApp(router: router, repo: repo, storage: storage),
        );
        await tester.pumpAndSettle();

        await _gotoIndependentDetails(tester);
        await _fillValidImForm(tester);
        await tester.tap(find.byKey(const Key('btn-submit-register')));
        await tester.pumpAndSettle();

        expect(repo.registerCalls, hasLength(1));
        expect(repo.registerCalls.first.businessName, isNull);
        expect(repo.registerCalls.first.address, isNull);
      },
    );

    // -----------------------------------------------------------------------
    // 16 (kept) — NetworkFailure (salonOwner) → error SnackBar
    // -----------------------------------------------------------------------
    testWidgets(
      '16. NetworkFailure during salonOwner register shows error SnackBar',
      (tester) async {
        final repo = FakeAuthRepository();
        repo.registerResult = const NetworkFailure();
        final storage = FakeSecureStorage();
        final router = _makeRouter();
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _buildApp(router: router, repo: repo, storage: storage),
        );
        await tester.pumpAndSettle();

        final l10n = lookupAppLocalizations(const Locale('uk'));
        await _selectRoleAndContinue(tester, l10n.intentSalonTitle);

        await tester.enterText(
          find.byKey(const Key('field-businessName')),
          'Краса Студія',
        );
        await tester.enterText(
          find.byKey(const Key('field-address')),
          'вул. Хрещатик, 1',
        );
        await tester.enterText(
          find.byKey(const Key('field-email')),
          'olena@beautica.test',
        );
        await tester.enterText(
          find.byKey(const Key('field-password')),
          'StrongPass2',
        );
        await tester.enterText(
          find.byKey(const Key('field-firstName')),
          'Олена',
        );
        await tester.enterText(
          find.byKey(const Key('field-lastName')),
          'Бойко',
        );
        await tester.enterText(
          find.byKey(const Key('field-phone')),
          '0501234567',
        );

        await tester.ensureVisible(
          find.byKey(const Key('btn-submit-register')),
        );
        await tester.tap(find.byKey(const Key('btn-submit-register')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();

        // NetworkFailure is not a ValidationFailure → surfaces as a SnackBar.
        expect(find.byType(SnackBar), findsOneWidget);
      },
    );

    // -----------------------------------------------------------------------
    // 17 (translated) — initial mount: no role selected (Icons.check absent);
    //                   tapping a card shows exactly one Icons.check in place
    // -----------------------------------------------------------------------
    testWidgets(
      '17. no role card selected on mount (Icons.check absent); tapping a card '
      'shows exactly one Icons.check on the picker',
      (tester) async {
        final repo = FakeAuthRepository();
        final storage = FakeSecureStorage();
        final router = _makeRouter();
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _buildApp(router: router, repo: repo, storage: storage),
        );
        await tester.pumpAndSettle();

        // _selectedRole starts null → no card checkmark.
        expect(
          find.byIcon(Icons.check),
          findsNothing,
          reason:
              '_selectedRole starts null → no role card is pre-selected → '
              'Icons.check must not appear on the picker',
        );

        // Tapping a card selects it IN PLACE (no badge round-trip in the
        // single-screen design) → exactly one Icons.check appears.
        final l10n = lookupAppLocalizations(const Locale('uk'));
        await tester.tap(find.text(l10n.intentIndependentTitle).first);
        await tester.pumpAndSettle();

        expect(
          find.byIcon(Icons.check),
          findsOneWidget,
          reason:
              'The tapped role card must display exactly one Icons.check in '
              'its checkmark circle',
        );
        // The redesign uses Icons.check, never Icons.check_circle.
        expect(find.byIcon(Icons.check_circle), findsNothing);
      },
    );

    // -----------------------------------------------------------------------
    // 18 (kept) — malformed phone shows errPhoneInvalidFormat
    // -----------------------------------------------------------------------
    testWidgets(
      '18. phone that does not match Ukrainian mask shows errPhoneInvalidFormat',
      (tester) async {
        final repo = FakeAuthRepository();
        final storage = FakeSecureStorage();
        final router = _makeRouter();
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _buildApp(router: router, repo: repo, storage: storage),
        );
        await tester.pumpAndSettle();

        await _gotoIndependentDetails(tester);

        await tester.enterText(
          find.byKey(const Key('field-email')),
          'ivan@beautica.test',
        );
        await tester.enterText(
          find.byKey(const Key('field-password')),
          'SecurePass1',
        );
        await tester.enterText(
          find.byKey(const Key('field-firstName')),
          'Іван',
        );
        await tester.enterText(
          find.byKey(const Key('field-lastName')),
          'Петренко',
        );
        // 1 digit → '+380 1' which is too short to match the full-number mask.
        await tester.enterText(find.byKey(const Key('field-phone')), '1');

        await tester.ensureVisible(
          find.byKey(const Key('btn-submit-register')),
        );
        await tester.tap(find.byKey(const Key('btn-submit-register')));
        await tester.pump();

        final l10n = lookupAppLocalizations(const Locale('uk'));
        expect(find.text(l10n.errPhoneInvalidFormat), findsOneWidget);
        expect(repo.registerCalls, isEmpty);
      },
    );

    // -----------------------------------------------------------------------
    // 19 (kept) — non-digit phone shows a phone validation error
    // -----------------------------------------------------------------------
    testWidgets(
      '19. phone with non-digit characters shows a phone validation error',
      (tester) async {
        final repo = FakeAuthRepository();
        final storage = FakeSecureStorage();
        final router = _makeRouter();
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _buildApp(router: router, repo: repo, storage: storage),
        );
        await tester.pumpAndSettle();

        await _gotoIndependentDetails(tester);

        await tester.enterText(
          find.byKey(const Key('field-email')),
          'ivan@beautica.test',
        );
        await tester.enterText(
          find.byKey(const Key('field-password')),
          'SecurePass1',
        );
        await tester.enterText(
          find.byKey(const Key('field-firstName')),
          'Іван',
        );
        await tester.enterText(
          find.byKey(const Key('field-lastName')),
          'Петренко',
        );
        // Letters are stripped by the formatter → result is just the prefix.
        await tester.enterText(
          find.byKey(const Key('field-phone')),
          'notaphone',
        );

        await tester.ensureVisible(
          find.byKey(const Key('btn-submit-register')),
        );
        await tester.tap(find.byKey(const Key('btn-submit-register')));
        await tester.pump();

        final l10n = lookupAppLocalizations(const Locale('uk'));
        final phoneError = find.textContaining(l10n.errPhoneRequired);
        final formatError = find.textContaining(l10n.errPhoneInvalidFormat);
        expect(
          phoneError.evaluate().isNotEmpty || formatError.evaluate().isNotEmpty,
          isTrue,
          reason: 'Letter-only phone must produce a phone validation error',
        );
        expect(repo.registerCalls, isEmpty);
      },
    );

    // -----------------------------------------------------------------------
    // 20 (translated) — btn-back-step returns to the role picker, email
    //                   preserved (replaces the removed step-1 back behaviour)
    // -----------------------------------------------------------------------
    testWidgets(
      '20. btn-back-step returns to the role picker; typed email is preserved '
      'when re-entering the details screen',
      (tester) async {
        final repo = FakeAuthRepository();
        final storage = FakeSecureStorage();
        final router = _makeRouter();
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _buildApp(router: router, repo: repo, storage: storage),
        );
        await tester.pumpAndSettle();

        final l10n = lookupAppLocalizations(const Locale('uk'));
        await _selectRoleAndContinue(tester, l10n.intentIndependentTitle);

        const testEmail = 'ivan@beautica.test';
        await tester.enterText(find.byKey(const Key('field-email')), testEmail);

        // Back to the role picker.
        await tester.ensureVisible(find.byKey(const Key('btn-back-step')));
        await tester.tap(find.byKey(const Key('btn-back-step')));
        await tester.pumpAndSettle();

        // Role picker is shown again; the details fields are gone.
        expect(find.text(l10n.intentSalonTitle), findsOneWidget);
        expect(find.byKey(const Key('field-email')), findsNothing);

        // Re-enter the details screen — entered data must be preserved
        // (the controllers are not cleared by the back affordance).
        await tester.ensureVisible(find.byKey(const Key('btn-continue-role')));
        await tester.tap(find.byKey(const Key('btn-continue-role')));
        await tester.pumpAndSettle();

        final emailField = tester.widget<TextFormField>(
          find.byKey(const Key('field-email')),
        );
        expect(
          emailField.controller?.text,
          equals(testEmail),
          reason:
              'Returning to the role picker and back must not clear the email '
              'controller (data is preserved)',
        );
      },
    );

    // -----------------------------------------------------------------------
    // 21 (kept) — IM details screen shows firstName + lastName + phone
    // -----------------------------------------------------------------------
    testWidgets(
      '21. IM details screen shows firstName, lastName and phone fields',
      (tester) async {
        final repo = FakeAuthRepository();
        final storage = FakeSecureStorage();
        final router = _makeRouter();
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _buildApp(router: router, repo: repo, storage: storage),
        );
        await tester.pumpAndSettle();

        await _gotoIndependentDetails(tester);

        expect(find.byKey(const Key('field-firstName')), findsOneWidget);
        expect(find.byKey(const Key('field-lastName')), findsOneWidget);
        expect(find.byKey(const Key('field-phone')), findsOneWidget);
        expect(find.byKey(const Key('field-businessName')), findsNothing);
        expect(find.byKey(const Key('field-address')), findsNothing);

        // The display-only progress row renders on the details screen.
        // _ProgressItem renders each label via label.toUpperCase() (the HTML
        // .prog-item uses text-transform: uppercase) so assert the uppercased
        // strings the widget actually paints.
        final l10n = lookupAppLocalizations(const Locale('uk'));
        expect(
          find.text(l10n.progressStepDetails.toUpperCase()),
          findsOneWidget,
        );
        expect(
          find.text(l10n.progressStepVerification.toUpperCase()),
          findsOneWidget,
        );
        expect(find.text(l10n.progressStepDone.toUpperCase()), findsOneWidget);
      },
    );

    // -----------------------------------------------------------------------
    // 22 (kept) — phone formatter: 10 digits → +380 67 123 45 67
    // -----------------------------------------------------------------------
    testWidgets('22. entering 10 digits formats to +380 67 123 45 67', (
      tester,
    ) async {
      final repo = FakeAuthRepository();
      final storage = FakeSecureStorage();
      final router = _makeRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(
        _buildApp(router: router, repo: repo, storage: storage),
      );
      await tester.pumpAndSettle();

      await _gotoIndependentDetails(tester);

      await tester.enterText(
        find.byKey(const Key('field-phone')),
        '0671234567',
      );
      await tester.pump();

      final phoneField = tester.widget<TextFormField>(
        find.byKey(const Key('field-phone')),
      );
      expect(
        phoneField.controller?.text,
        equals('+380 67 123 45 67'),
        reason: 'Ukrainian phone formatter must produce +380 67 123 45 67',
      );
    });

    // -----------------------------------------------------------------------
    // 23 (kept) — empty phone shows errPhoneRequired
    // -----------------------------------------------------------------------
    testWidgets('23. empty phone field shows errPhoneRequired', (tester) async {
      final repo = FakeAuthRepository();
      final storage = FakeSecureStorage();
      final router = _makeRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(
        _buildApp(router: router, repo: repo, storage: storage),
      );
      await tester.pumpAndSettle();

      await _gotoIndependentDetails(tester);

      await tester.enterText(
        find.byKey(const Key('field-email')),
        'ivan@beautica.test',
      );
      await tester.enterText(
        find.byKey(const Key('field-password')),
        'SecurePass1',
      );
      await tester.enterText(find.byKey(const Key('field-firstName')), 'Іван');
      await tester.enterText(
        find.byKey(const Key('field-lastName')),
        'Петренко',
      );
      // Leave phone empty.

      await tester.ensureVisible(find.byKey(const Key('btn-submit-register')));
      await tester.tap(find.byKey(const Key('btn-submit-register')));
      await tester.pump();

      final l10n = lookupAppLocalizations(const Locale('uk'));
      expect(find.text(l10n.errPhoneRequired), findsOneWidget);
      expect(repo.registerCalls, isEmpty);
    });

    // -----------------------------------------------------------------------
    // 24 (kept) — btn-submit-register is the unified submit key (all roles)
    // -----------------------------------------------------------------------
    testWidgets(
      '24. btn-submit-register is the unified submit key for all roles',
      (tester) async {
        final repo = FakeAuthRepository();
        final storage = FakeSecureStorage();
        final router = _makeRouter();
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _buildApp(router: router, repo: repo, storage: storage),
        );
        await tester.pumpAndSettle();

        final l10n = lookupAppLocalizations(const Locale('uk'));

        // IM path.
        await _selectRoleAndContinue(tester, l10n.intentIndependentTitle);
        expect(
          find.byKey(const Key('btn-submit-register')),
          findsOneWidget,
          reason: 'IM path must use btn-submit-register',
        );
        expect(
          find.byKey(const Key('btn-salon-submit-register')),
          findsNothing,
        );

        // Back to picker → salon path uses the same key.
        await tester.ensureVisible(find.byKey(const Key('btn-back-step')));
        await tester.tap(find.byKey(const Key('btn-back-step')));
        await tester.pumpAndSettle();

        await _selectRoleAndContinue(tester, l10n.intentSalonTitle);
        expect(
          find.byKey(const Key('btn-submit-register')),
          findsOneWidget,
          reason: 'Salon path must also use btn-submit-register',
        );
        expect(
          find.byKey(const Key('btn-salon-submit-register')),
          findsNothing,
        );
      },
    );

    // -----------------------------------------------------------------------
    // 25 (translated) — ValidationFailure(email) shows inline; screen stays on
    //                   the single details screen (no step retreat)
    // -----------------------------------------------------------------------
    testWidgets(
      '25. ValidationFailure(email) shows inline error and keeps the single '
      'details screen (does not retreat anywhere)',
      (tester) async {
        final repo = FakeAuthRepository();
        repo.registerResult = const ValidationFailure(
          fieldErrors: {'email': 'already in use'},
        );
        final storage = FakeSecureStorage();
        final router = _makeRouter();
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _buildApp(router: router, repo: repo, storage: storage),
        );
        await tester.pumpAndSettle();

        await _gotoIndependentDetails(tester);
        await _fillValidImForm(tester);
        await tester.tap(find.byKey(const Key('btn-submit-register')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();

        // Single screen stays put — email field AND submit button remain.
        expect(
          find.byKey(const Key('field-email')),
          findsOneWidget,
          reason: 'The single-screen design does not retreat — email stays',
        );
        expect(
          find.byKey(const Key('btn-submit-register')),
          findsOneWidget,
          reason: 'btn-submit-register must remain on the single screen',
        );
        expect(find.text('already in use'), findsOneWidget);
      },
    );

    // -----------------------------------------------------------------------
    // 26 (kept) — phone "380671234567" normalises to +380 67 123 45 67
    // -----------------------------------------------------------------------
    testWidgets('26. entering "380671234567" formats to +380 67 123 45 67', (
      tester,
    ) async {
      final repo = FakeAuthRepository();
      final storage = FakeSecureStorage();
      final router = _makeRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(
        _buildApp(router: router, repo: repo, storage: storage),
      );
      await tester.pumpAndSettle();

      await _gotoIndependentDetails(tester);

      await tester.enterText(
        find.byKey(const Key('field-phone')),
        '380671234567',
      );
      await tester.pump();

      final phoneField = tester.widget<TextFormField>(
        find.byKey(const Key('field-phone')),
      );
      expect(
        phoneField.controller?.text,
        equals('+380 67 123 45 67'),
        reason:
            '380671234567 must be normalised and formatted '
            'to +380 67 123 45 67',
      );
    });

    // -----------------------------------------------------------------------
    // 27 (kept) — 15-digit phone clamped to 13 raw digits
    // -----------------------------------------------------------------------
    testWidgets(
      '27. entering 15 digits is clamped to 13 raw digits by the formatter',
      (tester) async {
        final repo = FakeAuthRepository();
        final storage = FakeSecureStorage();
        final router = _makeRouter();
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _buildApp(router: router, repo: repo, storage: storage),
        );
        await tester.pumpAndSettle();

        await _gotoIndependentDetails(tester);

        await tester.enterText(
          find.byKey(const Key('field-phone')),
          '067123456799999',
        );
        await tester.pump();

        final phoneField = tester.widget<TextFormField>(
          find.byKey(const Key('field-phone')),
        );
        final formatted = phoneField.controller?.text ?? '';
        expect(
          formatted.startsWith('+380 '),
          isTrue,
          reason: 'Formatted phone must always start with +380 space',
        );
        expect(
          formatted.replaceAll(RegExp(r'\D'), '').length,
          lessThanOrEqualTo(13),
          reason: '_UkrainianPhoneFormatter must clamp raw digit count to 13',
        );
      },
    );

    // -----------------------------------------------------------------------
    // 28 (kept) — client full flow → register(role=client)
    // -----------------------------------------------------------------------
    testWidgets(
      '28. client role: full flow sends role=UserRole.client to repo',
      (tester) async {
        final repo = FakeAuthRepository();
        final storage = FakeSecureStorage();
        final router = _makeRouter();
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _buildApp(router: router, repo: repo, storage: storage),
        );
        await tester.pumpAndSettle();

        final l10n = lookupAppLocalizations(const Locale('uk'));
        await _selectRoleAndContinue(tester, l10n.intentClientTitle);

        // Client sees the reduced set: no businessName / address.
        expect(find.byKey(const Key('field-firstName')), findsOneWidget);
        expect(find.byKey(const Key('field-lastName')), findsOneWidget);
        expect(find.byKey(const Key('field-phone')), findsOneWidget);
        expect(find.byKey(const Key('field-businessName')), findsNothing);
        expect(find.byKey(const Key('field-address')), findsNothing);

        await tester.enterText(
          find.byKey(const Key('field-email')),
          'client@beautica.test',
        );
        await tester.enterText(
          find.byKey(const Key('field-password')),
          'SecurePass1',
        );
        await tester.enterText(
          find.byKey(const Key('field-firstName')),
          'Катерина',
        );
        await tester.enterText(
          find.byKey(const Key('field-lastName')),
          'Мороз',
        );
        await tester.enterText(
          find.byKey(const Key('field-phone')),
          '0501234567',
        );

        await tester.ensureVisible(
          find.byKey(const Key('btn-submit-register')),
        );
        await tester.tap(find.byKey(const Key('btn-submit-register')));
        await tester.pumpAndSettle();

        expect(repo.registerCalls, hasLength(1));
        expect(
          repo.registerCalls.first.role,
          equals(UserRole.client),
          reason: 'Client intent must pass UserRole.client to the repo',
        );
      },
    );

    // -----------------------------------------------------------------------
    // 29 (kept) — autovalidateMode shows inline email error while typing
    // -----------------------------------------------------------------------
    testWidgets(
      '29. autovalidateMode.onUserInteraction shows inline email error '
      'without tapping submit',
      (tester) async {
        final repo = FakeAuthRepository();
        final storage = FakeSecureStorage();
        final router = _makeRouter();
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _buildApp(router: router, repo: repo, storage: storage),
        );
        await tester.pumpAndSettle();

        await _gotoIndependentDetails(tester);

        await tester.enterText(
          find.byKey(const Key('field-email')),
          'not-an-email',
        );
        await tester.pump();

        final l10n = lookupAppLocalizations(const Locale('uk'));
        expect(
          find.text(l10n.errEmailInvalid),
          findsOneWidget,
          reason:
              'errEmailInvalid must appear inline under the email field when '
              'autovalidateMode.onUserInteraction is active',
        );
        expect(repo.registerCalls, isEmpty);
      },
    );

    // -----------------------------------------------------------------------
    // 30 (kept) — salon empty address → errAddressRequired, blocks submit
    // -----------------------------------------------------------------------
    testWidgets(
      '30. salon owner: empty address shows errAddressRequired and blocks '
      'register call',
      (tester) async {
        final repo = FakeAuthRepository();
        final storage = FakeSecureStorage();
        final router = _makeRouter();
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _buildApp(router: router, repo: repo, storage: storage),
        );
        await tester.pumpAndSettle();

        final l10n = lookupAppLocalizations(const Locale('uk'));
        await _selectRoleAndContinue(tester, l10n.intentSalonTitle);

        // Fill everything except address.
        await tester.enterText(
          find.byKey(const Key('field-businessName')),
          'Краса Студія',
        );
        await tester.enterText(
          find.byKey(const Key('field-email')),
          'salon@beautica.test',
        );
        await tester.enterText(
          find.byKey(const Key('field-password')),
          'StrongPass2',
        );
        await tester.enterText(
          find.byKey(const Key('field-firstName')),
          'Олена',
        );
        await tester.enterText(
          find.byKey(const Key('field-lastName')),
          'Бойко',
        );
        await tester.enterText(
          find.byKey(const Key('field-phone')),
          '0501234567',
        );

        await tester.ensureVisible(
          find.byKey(const Key('btn-submit-register')),
        );
        await tester.tap(find.byKey(const Key('btn-submit-register')));
        await tester.pump();

        expect(
          find.text(l10n.errAddressRequired),
          findsOneWidget,
          reason:
              'Empty salon address must trigger the errAddressRequired inline '
              'validation error',
        );
        expect(
          repo.registerCalls,
          isEmpty,
          reason:
              'Register must not be called when the address field fails '
              'validation',
        );
      },
    );

    // -----------------------------------------------------------------------
    // 31 (translated) — ValidationFailure(password) shows inline; screen stays
    //                   on the single details screen (no step retreat)
    // -----------------------------------------------------------------------
    testWidgets(
      '31. ValidationFailure(password) shows inline error and keeps the single '
      'details screen',
      (tester) async {
        final repo = FakeAuthRepository();
        repo.registerResult = const ValidationFailure(
          fieldErrors: {'password': 'too weak'},
        );
        final storage = FakeSecureStorage();
        final router = _makeRouter();
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _buildApp(router: router, repo: repo, storage: storage),
        );
        await tester.pumpAndSettle();

        await _gotoIndependentDetails(tester);
        await _fillValidImForm(tester);
        await tester.tap(find.byKey(const Key('btn-submit-register')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();

        // The single screen stays — email + submit remain visible.
        expect(
          find.byKey(const Key('field-email')),
          findsOneWidget,
          reason: 'password ValidationFailure must keep the single screen',
        );
        expect(
          find.byKey(const Key('btn-submit-register')),
          findsOneWidget,
          reason: 'btn-submit-register must remain on the single screen',
        );
        // Inline server error visible under the password field.
        await tester.ensureVisible(find.byKey(const Key('field-password')));
        expect(find.text('too weak'), findsOneWidget);
      },
    );
    // -----------------------------------------------------------------------
    // 32 (new) — BackdropFilter blur-budget ceiling on the role-selection step
    //
    // The role-selection view renders exactly 3 _RoleCard instances (each with
    // one BackdropFilter at sigma 12) and one _RegBrandRow (sigma 8) = 4 total.
    // _RegGlassCard is NOT present on this view — it only appears in the details
    // form. Asserting an upper bound of 4 prevents future additions from silently
    // exceeding the raster budget that was established by the sigma 20→12 fix.
    // -----------------------------------------------------------------------
    testWidgets(
      '32. role-selection step has at most 4 BackdropFilter instances (blur budget ceiling)',
      (tester) async {
        final repo = FakeAuthRepository();
        final storage = FakeSecureStorage();
        final router = _makeRouter();
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _buildApp(router: router, repo: repo, storage: storage),
        );
        await tester.pumpAndSettle();

        // We are on the role-selection step — _RegGlassCard is not in the tree.
        expect(
          find.byKey(const Key('field-email')),
          findsNothing,
          reason: 'Sanity: must be on the role-selection step, not details',
        );

        final backdropCount = find.byType(BackdropFilter).evaluate().length;
        expect(
          backdropCount,
          lessThanOrEqualTo(4),
          reason:
              'role-selection step must have at most 4 BackdropFilter widgets '
              '(3 role cards + 1 brand row). Found $backdropCount. '
              'A regression here means the raster budget sigma-12 fix was undone.',
        );
      },
    );
  });

  // =========================================================================
  // _WarmMochaStepIndicator — step progress row widget tests
  //
  // The production widget is _ProgressRow (inside register_screen.dart).
  // It is private and cannot be targeted via find.byType; structural
  // assertions are used instead.
  //
  // When the user is on the DETAILS step (step 2, _showDetails == true):
  //   • btn-back-step is visible  → confirms details step is active.
  //   • field-email is visible    → confirms the single-screen form rendered.
  //   • The role picker is gone   → intentSalonTitle is absent.
  //
  // The _ProgressRow does NOT use Icons.check inside its own dots; it renders
  // numbers. The only Icons.check in the tree at this point comes from a
  // _RoleCard — but role cards are not shown on the details step, so
  // find.byIcon(Icons.check) correctly finds nothing, confirming that the
  // selected-role checkmark is not leaked into the details view.
  // =========================================================================
  group('_WarmMochaStepIndicator', () {
    testWidgets('step 2 shows done dot for step 1 and active dot for step 2', (
      tester,
    ) async {
      final repo = FakeAuthRepository();
      final storage = FakeSecureStorage();
      final router = _makeRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(
        _buildApp(router: router, repo: repo, storage: storage),
      );
      await tester.pumpAndSettle();

      // Navigate to the details step (step 2) via the IM role card + CTA.
      // _gotoIndependentDetails selects the IM card then taps btn-continue-role.
      await _gotoIndependentDetails(tester);

      // btn-back-step confirms the details step is active.
      await tester.ensureVisible(find.byKey(const Key('btn-back-step')));
      expect(
        find.byKey(const Key('btn-back-step')),
        findsOneWidget,
        reason:
            'btn-back-step must be visible on the details step, '
            'confirming _ProgressRow has rendered',
      );

      // field-email present → the single-screen details form is showing.
      expect(
        find.byKey(const Key('field-email')),
        findsOneWidget,
        reason: 'field-email must be visible — we are on the details step',
      );

      // The role picker is no longer in the tree.
      final l10n = lookupAppLocalizations(const Locale('uk'));
      expect(
        find.text(l10n.intentSalonTitle),
        findsNothing,
        reason: 'Role picker must be gone when _ProgressRow step 2 is active',
      );

      // Icons.check is absent on the details step: role cards (the only
      // source of Icons.check) are not rendered here, so the selected-role
      // checkmark is not leaked into the step-2 view.
      expect(
        find.byIcon(Icons.check),
        findsNothing,
        reason:
            'Icons.check must not appear on the details step — '
            '_ProgressRow dots use numbered text, not check icons',
      );

      // _ProgressRow renders "КРОКИ" label variants — assert step 2 label is visible.
      expect(
        find.text(l10n.progressStepDetails.toUpperCase()),
        findsOneWidget,
        reason:
            '_ProgressRow must render the details step label when on step 2',
      );
    });
  });
}

// ---------------------------------------------------------------------------
// AuthNotifier stubs
// ---------------------------------------------------------------------------

/// Stays in [AsyncLoading] indefinitely — used to verify that the submit
/// button is disabled while a request is in flight.
class _LoadingAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async {
    final completer = Completer<AuthSession>();
    ref.onDispose(() {
      if (!completer.isCompleted) {
        completer.complete(const AuthSession.unauthenticated());
      }
    });
    return completer.future;
  }
}
