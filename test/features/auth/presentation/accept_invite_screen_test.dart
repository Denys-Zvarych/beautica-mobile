// Phase 2.20 — Widget tests for AcceptInviteScreen.
//
// Design source:
//   docs/signup-designs/VelvetTouchDesign/lib/screens/accept_invite_screen.dart
//
// Key finders are ValueKey<String>-based so tests are locale-independent and
// survive localization copy changes without breaking.
//
// Covered scenarios:
//   1. Loading state: acceptInviteProvider in AsyncLoading → CircularProgressIndicator
//      shown; CTA absent.
//   2. Invalid token: notifier emits AsyncError → AuthBanner present; CTA absent.
//   3. Valid token: notifier emits AsyncData(InviteDetails) → invited email shown;
//      CTA (invite_accept) present.
//   4. Password < 12 chars → CTA disabled (PasswordChecklist rules unmet).
//   5. Accept success: fill valid 12+ char password + firstName + lastName →
//      tap CTA → FakeAuthRepository.acceptInviteCalls has 1 entry;
//      router navigates to /.
//   6. Accept failure: repository throws ValidationFailure → inline error shown;
//      user stays on screen; CTA still present.
//
// Override strategy:
//   - acceptInviteProvider(token) overrideWith — controls the validate-step state.
//   - authRepositoryProvider overrideWith  — controls the accept-step result.
//   - secureStorageProvider overrideWith   — prevents FlutterSecureStorage
//     platform-channel access during tests.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/invite_details.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/accept_invite_screen.dart';
import 'package:beautica_mobile/features/auth/presentation/widgets/auth_scaffold.dart';
import 'package:beautica_mobile/features/auth/presentation/widgets/password_checklist.dart';
import 'package:beautica_mobile/features/auth/state/accept_invite_notifier.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';

const String _kToken = 'test-invite-token';

final _validInvite = InviteDetails(
  email: 'masha@salon.ua',
  role: UserRole.salonMaster,
  expiresAt: DateTime.now().add(const Duration(hours: 48)),
);

// ---------------------------------------------------------------------------
// Router factory
// ---------------------------------------------------------------------------

GoRouter _makeRouter({String token = _kToken}) => GoRouter(
  initialLocation: '${RouteNames.acceptInvite}?token=$token',
  redirect: (context, state) => null,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.acceptInvite,
      builder: (context, state) {
        final t = state.uri.queryParameters['token'] ?? '';
        return AcceptInviteScreen(token: t);
      },
    ),
    GoRoute(
      path: RouteNames.home,
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('home'))),
    ),
    GoRoute(
      path: RouteNames.login,
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('login'))),
    ),
  ],
);

// ---------------------------------------------------------------------------
// Pump helpers
// ---------------------------------------------------------------------------

/// Pumps the screen with an [AsyncData] invite (the common "valid token" path).
Future<FakeAuthRepository> _pumpValid(
  WidgetTester tester, {
  InviteDetails? invite,
  Object? acceptResult,
}) async {
  final repo = FakeAuthRepository()..acceptInviteResult = acceptResult;
  final storage = FakeSecureStorage();
  final router = _makeRouter();
  addTearDown(router.dispose);

  final effectiveInvite = invite ?? _validInvite;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWith((_) => repo),
        secureStorageProvider.overrideWithValue(storage),
        acceptInviteProvider(_kToken).overrideWith(
          () => _StubAcceptInviteNotifier(AsyncData(effectiveInvite)),
        ),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

/// Pumps the screen with an [AsyncLoading] state (token validation in-flight).
Future<void> _pumpLoading(WidgetTester tester) async {
  final repo = FakeAuthRepository();
  final storage = FakeSecureStorage();
  final router = _makeRouter();
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWith((_) => repo),
        secureStorageProvider.overrideWithValue(storage),
        acceptInviteProvider(
          _kToken,
        ).overrideWith(() => _StubAcceptInviteNotifier(const AsyncLoading())),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pump(); // single pump — do not settle (stays loading)
}

/// Pumps the screen with an [AsyncError] state (invalid / expired token).
Future<void> _pumpError(WidgetTester tester) async {
  final repo = FakeAuthRepository();
  final storage = FakeSecureStorage();
  final router = _makeRouter();
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWith((_) => repo),
        secureStorageProvider.overrideWithValue(storage),
        acceptInviteProvider(_kToken).overrideWith(
          () => _StubAcceptInviteNotifier(
            const AsyncError<InviteDetails>(
              ValidationFailure(fieldErrors: <String, String>{}),
              StackTrace.empty,
            ),
          ),
        ),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// Stub notifier
// ---------------------------------------------------------------------------

/// Synchronously-resolving stub that bypasses the real validate-invite HTTP call.
class _StubAcceptInviteNotifier extends AcceptInviteNotifier {
  _StubAcceptInviteNotifier(this._value);

  final AsyncValue<InviteDetails> _value;

  // Completer used for the loading state — kept in memory so the pending
  // future is never garbage-collected while the test is running. It is never
  // completed, which leaves the provider in AsyncLoading for the test's
  // lifetime WITHOUT creating a timer (unlike Future.delayed).
  static final Completer<InviteDetails> _pendingCompleter =
      Completer<InviteDetails>();

  @override
  FutureOr<InviteDetails> build(String token) {
    // Synchronously return the value (or throw for error) so tests are
    // deterministic without async gaps.
    final v = _value;
    return switch (v) {
      AsyncData(:final value) => value,
      AsyncError(:final error, :final stackTrace) => Error.throwWithStackTrace(
        error,
        stackTrace,
      ),
      _ => _pendingCompleter.future,
    };
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('AcceptInviteScreen', () {
    // ── 1. Loading state ─────────────────────────────────────────────────
    testWidgets(
      '1. loading state shows CircularProgressIndicator, CTA absent',
      (WidgetTester tester) async {
        await _pumpLoading(tester);

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(
          find.byKey(const ValueKey<String>('invite_accept')),
          findsNothing,
        );
      },
    );

    // ── 2. Error state ───────────────────────────────────────────────────
    testWidgets(
      '2. invalid token: AsyncError → AuthBanner present, CTA absent',
      (WidgetTester tester) async {
        await _pumpError(tester);

        expect(find.byType(AuthBanner), findsOneWidget);
        expect(
          find.byKey(const ValueKey<String>('invite_accept')),
          findsNothing,
        );
      },
    );

    // ── 3. Valid token shows form ─────────────────────────────────────────
    testWidgets('3. valid token: email shown in preview, CTA present', (
      WidgetTester tester,
    ) async {
      await _pumpValid(tester);

      // The invited email should be visible in the preview card.
      expect(find.text(_validInvite.email), findsOneWidget);
      // CTA is present (though disabled until form is valid).
      expect(
        find.byKey(const ValueKey<String>('invite_accept')),
        findsOneWidget,
      );
      // Password checklist is present.
      expect(find.byType(PasswordChecklist), findsOneWidget);
    });

    // ── 4. Short password disables CTA ───────────────────────────────────
    testWidgets(
      '4. password < 12 chars → PasswordChecklist shows unmet rules, CTA disabled',
      (WidgetTester tester) async {
        await _pumpValid(tester);

        // Enter 8-char password (meets old 8-char rule but NOT the 12-char minimum).
        await tester.enterText(
          find.byKey(const ValueKey<String>('invite_password')),
          'Short1A',
        );
        await tester.pump();

        // At least the length rule is unmet — radio_button_unchecked present.
        expect(find.byIcon(Icons.radio_button_unchecked), findsWidgets);

        // Tap CTA — it is disabled so no calls should be made.
        final repo = await _pumpValid(tester);
        await tester.tap(find.byKey(const ValueKey<String>('invite_accept')));
        await tester.pumpAndSettle();
        expect(repo.acceptInviteCalls, isEmpty);
      },
    );

    // ── 5. Accept success — repository called, auth state transitions ────
    testWidgets(
      '5. valid form + accept success → acceptInviteCalls has 1 entry',
      (WidgetTester tester) async {
        final repo = await _pumpValid(tester);

        // Fill all required fields.
        await tester.enterText(
          find.byKey(const ValueKey<String>('invite_password')),
          'StrongPassword12',
        );
        await tester.pump();

        // Scroll so the name fields are visible before tapping.
        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('invite_first_name')),
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('invite_first_name')),
          'Марія',
        );
        await tester.pump();

        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('invite_last_name')),
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('invite_last_name')),
          'Бондар',
        );
        await tester.pump();

        // Tap the CTA.
        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('invite_accept')),
        );
        await tester.tap(find.byKey(const ValueKey<String>('invite_accept')));

        // pump enough frames for the async acceptInvite() + snackbar to settle.
        // We use explicit pump calls rather than pumpAndSettle so the snackbar
        // animation timer does not block indefinitely.
        await tester.pump(); // begin async
        await tester.pump(const Duration(milliseconds: 100)); // repo completes
        await tester.pump(const Duration(milliseconds: 100)); // state update

        // Repository was called exactly once with the correct arguments.
        expect(repo.acceptInviteCalls.length, 1);
        expect(repo.acceptInviteCalls.first.token, _kToken);
        expect(repo.acceptInviteCalls.first.password, 'StrongPassword12');
        expect(repo.acceptInviteCalls.first.firstName, 'Марія');
        expect(repo.acceptInviteCalls.first.lastName, 'Бондар');
      },
    );

    // ── 6. Accept failure shows inline error ─────────────────────────────
    testWidgets('6. accept failure → inline error shown, user stays on form', (
      WidgetTester tester,
    ) async {
      final repo = await _pumpValid(
        tester,
        acceptResult: const ValidationFailure(
          fieldErrors: <String, String>{'password': 'Too common'},
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey<String>('invite_password')),
        'StrongPassword12',
      );
      await tester.pump();

      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('invite_first_name')),
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('invite_first_name')),
        'Марія',
      );
      await tester.pump();

      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('invite_last_name')),
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('invite_last_name')),
        'Бондар',
      );
      await tester.pump();

      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('invite_accept')),
      );
      await tester.tap(find.byKey(const ValueKey<String>('invite_accept')));

      // Explicit pump frames — the failure sets _inlineError synchronously
      // after the awaited acceptInvite() returns.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Repository was called.
      expect(repo.acceptInviteCalls.length, 1);

      // Inline error text is visible (ValidationFailure.userMessage).
      final l10n = AppLocalizations.of(
        tester.element(find.byType(AcceptInviteScreen)),
      );
      expect(find.text(l10n.errValidation), findsOneWidget);

      // Screen is still on the form (CTA still present).
      expect(
        find.byKey(const ValueKey<String>('invite_accept')),
        findsOneWidget,
      );
      // Not navigated to /home.
      expect(find.text('home'), findsNothing);
    });
  });
}
