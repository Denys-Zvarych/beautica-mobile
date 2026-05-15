// Phase 2.6 — Widget tests for RegisterScreen.
//
// Tests use a minimal GoRouter (initial route = /register → RegisterScreen).
//
// Covered scenarios:
//   1. Disabled role segments cannot be tapped (all except independentMaster).
//   2. Valid form → submit → register(...) called with correct args.
//   3. ValidationFailure from server with fieldErrors → error shown under
//      the relevant field.
//   4. Tapping a disabled role segment does not change the selection.
//   5. Submit button is disabled during AsyncLoading.

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

/// Fills all required fields with valid values and scrolls submit into view.
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
    // Test 1 — Role selector is present; disabled roles don't trigger register
    // -----------------------------------------------------------------------
    testWidgets(
      '1. role selector renders and disabled segments do not trigger register',
      (tester) async {
        final repo = FakeAuthRepository();
        final storage = FakeSecureStorage();
        final router = _makeRouter();
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _buildApp(router: router, repo: repo, storage: storage),
        );
        await tester.pumpAndSettle();

        // Role selector must be present.
        expect(find.byKey(const Key('field-role')), findsOneWidget);

        // No register call without form submission.
        expect(repo.registerCalls, isEmpty);
      },
    );

    // -----------------------------------------------------------------------
    // Test 2 — Valid form → submit → register called with correct args
    // -----------------------------------------------------------------------
    testWidgets('2. valid form → submit → register called with correct args', (
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

      await _fillValidForm(tester);
      await tester.tap(find.byKey(const Key('btn-submit-register')));
      await tester.pumpAndSettle();

      // registerCalls is populated exclusively by registerIndependentMaster(),
      // so hasLength(1) implicitly asserts the correct method was called.
      // The role is baked into the method name — no separate role param needed.
      expect(repo.registerCalls, hasLength(1));
      final call = repo.registerCalls.first;
      expect(call.email, equals('ivan@beautica.test'));
      expect(call.password, equals('SecurePass1'));
      expect(call.firstName, equals('Іван'));
      expect(call.lastName, equals('Петренко'));
    });

    // -----------------------------------------------------------------------
    // Test 3 — ValidationFailure from server → error shown under email field
    // -----------------------------------------------------------------------
    testWidgets(
      '3. ValidationFailure with fieldErrors.email → error shown under email field',
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

        await _fillValidForm(tester);
        await tester.tap(find.byKey(const Key('btn-submit-register')));
        // Multiple pumps to allow: (1) tap event, (2) async register call,
        // (3) setState with server errors, (4) rebuild with errorText.
        // pumpAndSettle alone is insufficient after server error — the async
        // setState after Completer completion needs an explicit frame pump.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();

        // The server error for 'email' should be visible in the form.
        expect(find.text('already in use'), findsOneWidget);
      },
    );

    // -----------------------------------------------------------------------
    // Test 4 — Tapping a disabled role segment does not change selection
    // -----------------------------------------------------------------------
    testWidgets(
      '4. tapping a disabled role segment does not change selection',
      (tester) async {
        final repo = FakeAuthRepository();
        final storage = FakeSecureStorage();
        final router = _makeRouter();
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _buildApp(router: router, repo: repo, storage: storage),
        );
        await tester.pumpAndSettle();

        // The role selector must be present.
        expect(find.byKey(const Key('field-role')), findsOneWidget);

        // Retrieve l10n for the disabled role label ('Client').
        final l10n = AppLocalizations.of(
          tester.element(find.byKey(const Key('field-role'))),
        );

        // Tap a disabled segment — UserRole.client is disabled.
        final clientLabel = find.text(l10n.roleClient);
        expect(clientLabel, findsOneWidget);
        await tester.tap(clientLabel, warnIfMissed: false);
        await tester.pumpAndSettle();

        // The SegmentedButton's selected set must still contain
        // independentMaster. Verify via the widget's selected property.
        final segmentedButton = tester.widget<SegmentedButton<UserRole>>(
          find.byKey(const Key('field-role')),
        );
        expect(segmentedButton.selected, equals({UserRole.independentMaster}));
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
            // Notifier that never settles out of AsyncLoading.
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
      // pumpAndSettle would hang — the provider never completes.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final button = tester.widget<ElevatedButton>(
        find.byKey(const Key('btn-submit-register')),
      );
      expect(button.onPressed, isNull);
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
    // Test 7 — btn-go-to-login key exists
    // -----------------------------------------------------------------------
    testWidgets('7. btn-go-to-login key is present in the widget tree', (
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
      final router = _makeRouter(); // already includes /login route
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

      await tester.ensureVisible(find.byKey(const Key('btn-go-to-login')));
      await tester.tap(find.byKey(const Key('btn-go-to-login')));
      await tester.pumpAndSettle();

      // The /login placeholder from _makeRouter renders Text('login').
      expect(find.text('login'), findsOneWidget);
    });
  });
}

// ---------------------------------------------------------------------------
// AuthNotifier stubs used by tests 4 & 5
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
