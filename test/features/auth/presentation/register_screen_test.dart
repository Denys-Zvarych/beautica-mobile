// Phase 2.6 — Widget tests for RegisterScreen (two-step intent picker).
//
// Tests use a minimal GoRouter (initial route = /register → RegisterScreen).
//
// Step 1 (intent picker) and Step 2 (form) are tested separately.
//
// Covered scenarios:
//   1. Step 1: three intent cards render without error.
//   2. Step 1: tapping an intent card transitions to Step 2 (form visible).
//   3. Step 2: valid form → submit → register called with correct args incl. role.
//   4. Step 2: ValidationFailure from server with fieldErrors → inline error.
//   5. Step 2: submit button is disabled during AsyncLoading.
//   6. Step 2: empty firstName shows errNameRequired error.
//   7. Step 2: btn-go-to-login key exists.
//   8. Step 2: tapping btn-go-to-login navigates to /login.
//   9. Step 2: tapping the selected badge resets to Step 1.
//  10. Step 1: tapping salonOwner card → submit → register called with role=salonOwner.
//  11. Step 1: btn-go-to-login-from-intent navigates to /login.

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

/// Taps the first intent card (independentMaster) to advance to Step 2.
Future<void> _selectIntent(WidgetTester tester) async {
  // The first intent card contains the intentIndependentTitle text.
  final l10n = lookupAppLocalizations(const Locale('uk'));
  await tester.tap(find.text(l10n.intentIndependentTitle).first);
  await tester.pumpAndSettle();
}

/// Fills all required form fields with valid values and scrolls submit into view.
/// Must be called after [_selectIntent] — form fields are only visible in Step 2.
Future<void> _fillValidForm(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('field-firstName')), 'Іван');
  await tester.enterText(find.byKey(const Key('field-lastName')), 'Петренко');
  await tester.enterText(
    find.byKey(const Key('field-email')),
    'ivan@beautica.test',
  );
  await tester.enterText(
    find.byKey(const Key('field-password')),
    'SecurePass1',
  );
  // Scroll the submit button into view — the form may be taller than the
  // 600px test viewport.
  await tester.ensureVisible(find.byKey(const Key('btn-submit-register')));
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('RegisterScreen', () {
    // -----------------------------------------------------------------------
    // Test 1 — Step 1: three intent cards render without error
    // -----------------------------------------------------------------------
    testWidgets(
      '1. Step 1: three intent cards render and no register call yet',
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

        // All three intent card titles must be present.
        expect(find.text(l10n.intentIndependentTitle), findsOneWidget);
        expect(find.text(l10n.intentSalonTitle), findsOneWidget);
        expect(find.text(l10n.intentClientTitle), findsOneWidget);

        // Form fields are NOT visible in Step 1.
        expect(find.byKey(const Key('field-firstName')), findsNothing);
        expect(find.byKey(const Key('field-email')), findsNothing);

        // No register call without form submission.
        expect(repo.registerCalls, isEmpty);
      },
    );

    // -----------------------------------------------------------------------
    // Test 2 — Step 1 → Step 2: tapping a card shows the form
    // -----------------------------------------------------------------------
    testWidgets(
      '2. tapping an intent card transitions to Step 2 (form is visible)',
      (tester) async {
        final repo = FakeAuthRepository();
        final storage = FakeSecureStorage();
        final router = _makeRouter();
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _buildApp(router: router, repo: repo, storage: storage),
        );
        await tester.pumpAndSettle();

        await _selectIntent(tester);

        // Step 2: form fields must now be visible.
        expect(find.byKey(const Key('field-firstName')), findsOneWidget);
        expect(find.byKey(const Key('field-email')), findsOneWidget);
        expect(find.byKey(const Key('field-password')), findsOneWidget);
        expect(find.byKey(const Key('btn-submit-register')), findsOneWidget);

        // Step 1 cards must no longer be present.
        final l10n = lookupAppLocalizations(const Locale('uk'));
        expect(find.text(l10n.intentSalonTitle), findsNothing);
      },
    );

    // -----------------------------------------------------------------------
    // Test 3 — Valid form → submit → register called with correct args + role
    // -----------------------------------------------------------------------
    testWidgets(
      '3. valid form → submit → register called with correct args incl. role=independentMaster',
      (tester) async {
        final repo = FakeAuthRepository();
        final storage = FakeSecureStorage();
        final router = _makeRouter();
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _buildApp(router: router, repo: repo, storage: storage),
        );
        await tester.pumpAndSettle();

        // Default intent card selected is independentMaster (index 0).
        await _selectIntent(tester);
        await _fillValidForm(tester);
        await tester.tap(find.byKey(const Key('btn-submit-register')));
        await tester.pumpAndSettle();

        expect(repo.registerCalls, hasLength(1));
        final call = repo.registerCalls.first;
        expect(call.email, equals('ivan@beautica.test'));
        expect(call.password, equals('SecurePass1'));
        expect(call.firstName, equals('Іван'));
        expect(call.lastName, equals('Петренко'));
        // Role must match the intent card that was tapped.
        expect(call.role, equals(UserRole.independentMaster));
      },
    );

    // -----------------------------------------------------------------------
    // Test 4 — ValidationFailure from server → error shown under email field
    // -----------------------------------------------------------------------
    testWidgets(
      '4. ValidationFailure with fieldErrors.email → error shown under email field',
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

        await _selectIntent(tester);
        await _fillValidForm(tester);
        await tester.tap(find.byKey(const Key('btn-submit-register')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();

        expect(find.text('already in use'), findsOneWidget);
      },
    );

    // -----------------------------------------------------------------------
    // Test 5 — Submit button is disabled during AsyncLoading
    // -----------------------------------------------------------------------
    testWidgets('5. submit button is disabled during AsyncLoading', (
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
      // pumpAndSettle would hang — the _LoadingAuthNotifier never completes.
      // Use pump() to settle the frame without waiting on the unresolved future.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Tap the independent master intent card to reach Step 2. The tap uses a
      // direct UI interaction rather than pumpAndSettle so the Completer-backed
      // provider never blocks the test (M6 pattern).
      final l10n = lookupAppLocalizations(const Locale('uk'));
      await tester.tap(find.text(l10n.intentIndependentTitle).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // The submit button must now be in the tree. Assert that onPressed is null
      // because isLoading == true disables it.
      final submitButton = tester.widget<ElevatedButton>(
        find.byKey(const Key('btn-submit-register')),
      );
      expect(
        submitButton.onPressed,
        isNull,
        reason: 'Submit button must be disabled while authProvider is loading',
      );
    });

    // -----------------------------------------------------------------------
    // Test 6 — empty firstName shows errNameRequired
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

      await _selectIntent(tester);

      // Fill valid email and password but leave firstName blank.
      await tester.enterText(
        find.byKey(const Key('field-email')),
        'ivan@beautica.test',
      );
      await tester.enterText(
        find.byKey(const Key('field-password')),
        'SecurePass1',
      );
      await tester.enterText(find.byKey(const Key('field-lastName')), 'Коваль');
      // Intentionally leave field-firstName empty.

      await tester.ensureVisible(find.byKey(const Key('btn-submit-register')));
      await tester.tap(find.byKey(const Key('btn-submit-register')));
      await tester.pump();

      final l10n = AppLocalizations.of(
        tester.element(find.byKey(const Key('field-firstName'))),
      );
      expect(find.text(l10n.errNameRequired), findsOneWidget);

      // No register call should have been made.
      expect(repo.registerCalls, isEmpty);
    });

    // -----------------------------------------------------------------------
    // Test 7 — btn-go-to-login key exists in Step 2
    // -----------------------------------------------------------------------
    testWidgets('7. btn-go-to-login key is present in Step 2 widget tree', (
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

      // In Step 1, the login link uses a different key.
      expect(
        find.byKey(const Key('btn-go-to-login-from-intent')),
        findsOneWidget,
      );

      // Advance to Step 2.
      await _selectIntent(tester);

      // btn-go-to-login is the Step 2 key (below the submit button).
      expect(find.byKey(const Key('btn-go-to-login')), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Test 8 — tapping btn-go-to-login navigates to /login
    // -----------------------------------------------------------------------
    testWidgets('8. tapping btn-go-to-login navigates to /login', (
      tester,
    ) async {
      final repo = FakeAuthRepository();
      final storage = FakeSecureStorage();
      final router = _makeRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
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
        ),
      );
      await tester.pumpAndSettle();

      // Advance to Step 2.
      await _selectIntent(tester);

      await tester.ensureVisible(find.byKey(const Key('btn-go-to-login')));
      await tester.tap(find.byKey(const Key('btn-go-to-login')));
      await tester.pumpAndSettle();

      expect(find.text('login'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Test 9 — tapping the badge resets to Step 1
    // -----------------------------------------------------------------------
    testWidgets('9. tapping the selected badge resets to Step 1 intent picker', (
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

      // Advance to Step 2.
      await _selectIntent(tester);
      expect(find.byKey(const Key('field-firstName')), findsOneWidget);

      // Tap the badge to reset to Step 1. The badge displays the intent title.
      final l10n = lookupAppLocalizations(const Locale('uk'));
      // The badge uses the same title text as the card — find by the UA title
      // text that appears inside the badge container.
      final badgeTitleFinder = find.text(l10n.intentIndependentTitle);
      expect(badgeTitleFinder, findsOneWidget);
      await tester.tap(badgeTitleFinder);
      await tester.pumpAndSettle();

      // Back on Step 1 — intent cards should be visible again.
      expect(find.text(l10n.intentSalonTitle), findsOneWidget);
      expect(find.byKey(const Key('field-firstName')), findsNothing);
    });

    // -----------------------------------------------------------------------
    // Test 10 — salonOwner card → submit → register called with role=salonOwner
    // -----------------------------------------------------------------------
    testWidgets(
      '10. tapping salonOwner card then submitting form passes role=salonOwner',
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

        // Tap the salonOwner intent card (index 1).
        await tester.tap(find.text(l10n.intentSalonTitle).first);
        await tester.pumpAndSettle();

        // Salon Step 1: businessName + email + password are visible; no
        // firstName/lastName fields in the salon owner path.
        expect(find.byKey(const Key('field-businessName')), findsOneWidget);
        expect(find.byKey(const Key('field-email')), findsOneWidget);
        expect(find.byKey(const Key('field-password')), findsOneWidget);

        // Fill Step 1 fields.
        await tester.enterText(
          find.byKey(const Key('field-businessName')),
          'Краса Студія',
        );
        await tester.enterText(
          find.byKey(const Key('field-email')),
          'olena@beautica.test',
        );
        await tester.enterText(
          find.byKey(const Key('field-password')),
          'StrongPass2',
        );

        // Advance to salon Step 2 via the Next button.
        await tester.ensureVisible(find.byKey(const Key('btn-salon-next')));
        await tester.tap(find.byKey(const Key('btn-salon-next')));
        await tester.pumpAndSettle();

        // Salon Step 2: address + phone fields.
        expect(find.byKey(const Key('field-address')), findsOneWidget);

        // Fill Step 2 fields.
        await tester.enterText(
          find.byKey(const Key('field-address')),
          'вул. Хрещатик, 1',
        );
        await tester.enterText(
          find.byKey(const Key('field-phone')),
          '+380501234567',
        );

        await tester.ensureVisible(
          find.byKey(const Key('btn-salon-submit-register')),
        );
        await tester.tap(find.byKey(const Key('btn-salon-submit-register')));
        await tester.pumpAndSettle();

        // Exactly one register call with role=salonOwner.
        expect(repo.registerCalls, hasLength(1));
        expect(repo.registerCalls.first.role, equals(UserRole.salonOwner));
        expect(repo.registerCalls.first.email, equals('olena@beautica.test'));
        expect(repo.registerCalls.first.businessName, equals('Краса Студія'));
      },
    );

    // -----------------------------------------------------------------------
    // Test 18 — phone >20 chars shows errPhoneTooLong
    // -----------------------------------------------------------------------
    testWidgets('18. phone number longer than 20 chars shows errPhoneTooLong', (
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

      // Navigate to salon owner flow.
      await tester.tap(find.text(l10n.intentSalonTitle).first);
      await tester.pumpAndSettle();

      // Fill salon Step 1 with valid data.
      await tester.enterText(
        find.byKey(const Key('field-businessName')),
        'Краса Студія',
      );
      await tester.enterText(
        find.byKey(const Key('field-email')),
        'olena@beautica.test',
      );
      await tester.enterText(
        find.byKey(const Key('field-password')),
        'StrongPass2',
      );

      // Advance to Step 2.
      await tester.ensureVisible(find.byKey(const Key('btn-salon-next')));
      await tester.tap(find.byKey(const Key('btn-salon-next')));
      await tester.pumpAndSettle();

      // Enter a phone number with more than 20 characters.
      await tester.enterText(
        find.byKey(const Key('field-phone')),
        '+380501234567890123456', // 22 chars — exceeds the 20-char limit
      );
      // Fill the required address field so the only validation error is for phone.
      await tester.enterText(
        find.byKey(const Key('field-address')),
        'вул. Хрещатик, 1',
      );

      await tester.ensureVisible(
        find.byKey(const Key('btn-salon-submit-register')),
      );
      await tester.tap(find.byKey(const Key('btn-salon-submit-register')));
      // Use pump() rather than pumpAndSettle() to avoid hanging on async state.
      await tester.pump();

      expect(find.text(l10n.errPhoneTooLong), findsOneWidget);

      // The repo must NOT have been called — local validation must block submission.
      expect(repo.registerCalls, isEmpty);
    });

    // -----------------------------------------------------------------------
    // Test 19 — phone with invalid chars shows errPhoneInvalidFormat
    // -----------------------------------------------------------------------
    testWidgets(
      '19. phone number with invalid characters shows errPhoneInvalidFormat',
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

        // Navigate to salon owner flow.
        await tester.tap(find.text(l10n.intentSalonTitle).first);
        await tester.pumpAndSettle();

        // Fill salon Step 1 with valid data.
        await tester.enterText(
          find.byKey(const Key('field-businessName')),
          'Краса Студія',
        );
        await tester.enterText(
          find.byKey(const Key('field-email')),
          'olena@beautica.test',
        );
        await tester.enterText(
          find.byKey(const Key('field-password')),
          'StrongPass2',
        );

        // Advance to Step 2.
        await tester.ensureVisible(find.byKey(const Key('btn-salon-next')));
        await tester.tap(find.byKey(const Key('btn-salon-next')));
        await tester.pumpAndSettle();

        // Enter a phone number that contains invalid characters (letters).
        await tester.enterText(
          find.byKey(const Key('field-phone')),
          'notaphone', // letters are not matched by _rePhone
        );
        // Fill the required address field so the only validation error is for phone.
        await tester.enterText(
          find.byKey(const Key('field-address')),
          'вул. Хрещатик, 1',
        );

        await tester.ensureVisible(
          find.byKey(const Key('btn-salon-submit-register')),
        );
        await tester.tap(find.byKey(const Key('btn-salon-submit-register')));
        // Use pump() rather than pumpAndSettle() to avoid hanging on async state.
        await tester.pump();

        expect(find.text(l10n.errPhoneInvalidFormat), findsOneWidget);

        // The repo must NOT have been called — local validation must block submission.
        expect(repo.registerCalls, isEmpty);
      },
    );

    // -----------------------------------------------------------------------
    // Test 20 — btn-salon-back returns to Step 1 with businessName preserved
    // -----------------------------------------------------------------------
    testWidgets(
      '20. btn-salon-back returns to Step 1 with previously typed businessName preserved',
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

        // Navigate to salon owner flow.
        await tester.tap(find.text(l10n.intentSalonTitle).first);
        await tester.pumpAndSettle();

        // Fill Step 1: type a business name that must survive the round-trip.
        await tester.enterText(
          find.byKey(const Key('field-businessName')),
          'Краса Студія',
        );
        await tester.enterText(
          find.byKey(const Key('field-email')),
          'olena@beautica.test',
        );
        await tester.enterText(
          find.byKey(const Key('field-password')),
          'StrongPass2',
        );

        // Advance to salon Step 2 via the Next button.
        await tester.ensureVisible(find.byKey(const Key('btn-salon-next')));
        await tester.tap(find.byKey(const Key('btn-salon-next')));
        await tester.pumpAndSettle();

        // Step 2 is now visible — go back.
        await tester.ensureVisible(find.byKey(const Key('btn-salon-back')));
        await tester.tap(find.byKey(const Key('btn-salon-back')));
        await tester.pumpAndSettle();

        // We are back on Step 1. The businessName controller must still hold the
        // previously entered value because _retreatSalonStep() only changes
        // _salonStep back to 0 — it never clears the controllers.
        final businessNameField = tester.widget<TextFormField>(
          find.byKey(const Key('field-businessName')),
        );
        expect(
          businessNameField.controller?.text,
          equals('Краса Студія'),
          reason:
              'Going back to Step 1 must not clear the businessName '
              'TextEditingController — user should not re-type it',
        );
      },
    );

    // -----------------------------------------------------------------------
    // Test 17 — on initial mount no intent card carries a selected indicator
    // -----------------------------------------------------------------------
    testWidgets(
      '17. on initial mount no intent card has a selected visual indicator (Icons.check_circle absent)',
      (tester) async {
        final repo = FakeAuthRepository();
        final storage = FakeSecureStorage();
        final router = _makeRouter();
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _buildApp(router: router, repo: repo, storage: storage),
        );
        await tester.pumpAndSettle();

        // The _IntentCard widget renders Icons.check_circle only when isSelected
        // is true. _selectedRole starts as null so no card is pre-highlighted.
        // No Icons.check_circle should be present anywhere in the widget tree.
        expect(
          find.byIcon(Icons.check_circle),
          findsNothing,
          reason:
              '_selectedRole starts null → no intent card is pre-selected → '
              'Icons.check_circle must not appear in the tree',
        );
      },
    );

    // -----------------------------------------------------------------------
    // Test 11 — btn-go-to-login-from-intent (Step 1) navigates to /login
    // -----------------------------------------------------------------------
    testWidgets(
      '11. btn-go-to-login-from-intent in Step 1 navigates to /login',
      (tester) async {
        final repo = FakeAuthRepository();
        final storage = FakeSecureStorage();
        final router = _makeRouter();
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _buildApp(router: router, repo: repo, storage: storage),
        );
        await tester.pumpAndSettle();

        // The sign-in link is visible in Step 1 without selecting any intent.
        expect(
          find.byKey(const Key('btn-go-to-login-from-intent')),
          findsOneWidget,
        );

        await tester.ensureVisible(
          find.byKey(const Key('btn-go-to-login-from-intent')),
        );
        await tester.tap(find.byKey(const Key('btn-go-to-login-from-intent')));
        await tester.pumpAndSettle();

        // Should navigate to the login stub screen.
        expect(find.text('login'), findsOneWidget);
      },
    );

    // -----------------------------------------------------------------------
    // Test 12 — businessName field is absent for independentMaster
    // -----------------------------------------------------------------------
    testWidgets(
      '12. field-businessName is NOT rendered when independentMaster intent is selected',
      (tester) async {
        final repo = FakeAuthRepository();
        final storage = FakeSecureStorage();
        final router = _makeRouter();
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _buildApp(router: router, repo: repo, storage: storage),
        );
        await tester.pumpAndSettle();

        // Select independentMaster (default, index 0).
        await _selectIntent(tester);

        // The AnimatedSize wraps SizedBox.shrink() for non-salonOwner roles —
        // field-businessName must not be findable.
        expect(find.byKey(const Key('field-businessName')), findsNothing);
      },
    );

    // -----------------------------------------------------------------------
    // Test 13 — businessName field appears for salonOwner
    // -----------------------------------------------------------------------
    testWidgets(
      '13. field-businessName IS rendered when salonOwner intent is selected',
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

        // Tap the salonOwner card (index 1).
        await tester.tap(find.text(l10n.intentSalonTitle).first);
        await tester.pumpAndSettle();

        // AnimatedSize must have expanded — field-businessName is present.
        expect(find.byKey(const Key('field-businessName')), findsOneWidget);
      },
    );

    // -----------------------------------------------------------------------
    // Test 14 — blank businessName blocks submission for salonOwner
    // -----------------------------------------------------------------------
    testWidgets(
      '14. empty businessName shows validation error and blocks register call for salonOwner',
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

        // Tap salonOwner intent card.
        await tester.tap(find.text(l10n.intentSalonTitle).first);
        await tester.pumpAndSettle();

        // Salon Step 1: fill email + password but intentionally leave
        // field-businessName blank. firstName/lastName are not collected
        // in the salon owner path.
        await tester.enterText(
          find.byKey(const Key('field-email')),
          'olena@beautica.test',
        );
        await tester.enterText(
          find.byKey(const Key('field-password')),
          'StrongPass2',
        );

        // Tap the Next button — Step 1 validates businessName before advancing.
        await tester.ensureVisible(find.byKey(const Key('btn-salon-next')));
        await tester.tap(find.byKey(const Key('btn-salon-next')));
        await tester.pump();

        // errNameRequired is the validator message for blank businessName.
        expect(find.text(l10n.errNameRequired), findsOneWidget);

        // The register repository must NOT have been called — Step 2 was never
        // reached so no submit was possible.
        expect(repo.registerCalls, isEmpty);
      },
    );

    // -----------------------------------------------------------------------
    // Test 15 — salonOwner registers without businessName passing null to repo
    //           (client-side guard: businessName is only sent when salonOwner)
    // -----------------------------------------------------------------------
    testWidgets(
      '15. independentMaster submit passes null businessName to repo, not empty string',
      (tester) async {
        final repo = FakeAuthRepository();
        final storage = FakeSecureStorage();
        final router = _makeRouter();
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _buildApp(router: router, repo: repo, storage: storage),
        );
        await tester.pumpAndSettle();

        // Select independentMaster.
        await _selectIntent(tester);
        await _fillValidForm(tester);
        await tester.tap(find.byKey(const Key('btn-submit-register')));
        await tester.pumpAndSettle();

        expect(repo.registerCalls, hasLength(1));
        // businessName must be null, not an empty string — the repository
        // must not send an empty businessName key in the request body.
        expect(repo.registerCalls.first.businessName, isNull);
      },
    );

    // -----------------------------------------------------------------------
    // Test 16 — non-ValidationFailure on salonOwner shows snackbar, not inline
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

        // Tap salonOwner intent card.
        await tester.tap(find.text(l10n.intentSalonTitle).first);
        await tester.pumpAndSettle();

        // Salon Step 1: fill businessName + email + password.
        // firstName/lastName are not collected in the salon owner path.
        await tester.enterText(
          find.byKey(const Key('field-businessName')),
          'Краса Студія',
        );
        await tester.enterText(
          find.byKey(const Key('field-email')),
          'olena@beautica.test',
        );
        await tester.enterText(
          find.byKey(const Key('field-password')),
          'StrongPass2',
        );

        // Advance to salon Step 2 via the Next button.
        await tester.ensureVisible(find.byKey(const Key('btn-salon-next')));
        await tester.tap(find.byKey(const Key('btn-salon-next')));
        await tester.pumpAndSettle();

        // Salon Step 2: fill the required address field (phone is optional).
        await tester.enterText(
          find.byKey(const Key('field-address')),
          'вул. Хрещатик, 1',
        );

        await tester.ensureVisible(
          find.byKey(const Key('btn-salon-submit-register')),
        );
        await tester.tap(find.byKey(const Key('btn-salon-submit-register')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();

        // NetworkFailure is not a ValidationFailure → must surface as a SnackBar.
        expect(find.byType(SnackBar), findsOneWidget);
      },
    );
  });
}

// ---------------------------------------------------------------------------
// AuthNotifier stubs
// ---------------------------------------------------------------------------

/// Stays in [AsyncLoading] indefinitely — used to verify that the submit
/// button and all form fields are disabled while a request is in flight.
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
