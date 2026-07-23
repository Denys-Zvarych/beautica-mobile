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

        // Navigation to / is triggered by the router redirect reacting to the
        // AuthSession becoming Authenticated. In this test router the redirect
        // is stubbed to null (the full redirect path is covered by NL-22).
        //
        // The observable proxy here is the success snackbar that the screen
        // shows immediately before the router fires — its presence confirms
        // the success branch (data state) was reached and that the screen
        // *would* navigate to / in the production router.
        await tester.pump(const Duration(milliseconds: 50));
        final l10n = AppLocalizations.of(
          tester.element(find.byType(AcceptInviteScreen)),
        );
        expect(
          find.text(l10n.inviteSuccessSnackbar),
          findsOneWidget,
          reason:
              'Successful invite accept must show the success snackbar, '
              'which is the on-screen indicator that the screen is about '
              'to navigate to home (/)',
        );
      },
    );

    // ── 7. Password rules partially unmet → CTA disabled ────────────────
    //
    // The invite path enforces 3 rules: length >= 12, has digit, has uppercase.
    // A 12-char lowercase-only string with a digit meets the length rule but
    // fails the uppercase rule — the PasswordChecklist must show at least one
    // unmet row, the _formValid getter returns false, and the CTA stays
    // disabled (onPressed == null), so no acceptInvite call is made.
    //
    // This replaces the originally-planned "confirm-password mismatch" test:
    // AcceptInviteScreen has no confirm-password field — password policy rules
    // are the sole pre-submit gate. Testing a password that satisfies length but
    // not all rules is the equivalent "partial input" coverage for this screen.
    testWidgets(
      '7. password meets length but not all rules → checklist unmet row shown, '
      'CTA disabled, no submit call',
      (WidgetTester tester) async {
        final repo = await _pumpValid(tester);

        // 12 chars, has a digit, but ALL LOWERCASE — fails the uppercase rule.
        await tester.enterText(
          find.byKey(const ValueKey<String>('invite_password')),
          'weakpassword1',
        );
        await tester.pump();

        // At least one unmet rule must be visible (radio_button_unchecked).
        expect(find.byIcon(Icons.radio_button_unchecked), findsWidgets);

        // Fill first + last name so those fields are not blocking the gate.
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

        // Attempt to tap the CTA — it is disabled (onPressed == null on the
        // NeumorphicButton). A tap on a disabled GestureDetector is a no-op.
        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('invite_accept')),
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('invite_accept')),
          warnIfMissed: false,
        );
        await tester.pump(const Duration(milliseconds: 100));

        // The repository must not have been called.
        expect(repo.acceptInviteCalls, isEmpty);
      },
    );

    // ── 8. Phone formatter wires +380 mask to invite_phone ───────────────
    //
    // UaPhoneInputFormatter is attached to the invite_phone field.
    // Typing the 10-digit local number '0671234567' must produce the formatted
    // string '+380 67 123 45 67' in the field.
    testWidgets(
      '8. entering 0671234567 in invite_phone formats to +380 67 123 45 67',
      (WidgetTester tester) async {
        await _pumpValid(tester);

        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('invite_phone')),
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('invite_phone')),
          '0671234567',
        );
        await tester.pump();

        // The formatter converts the raw digits to the masked format.
        expect(
          find.text('+380 67 123 45 67'),
          findsOneWidget,
          reason:
              'UaPhoneInputFormatter must reformat "0671234567" to '
              '"+380 67 123 45 67" in the invite_phone field',
        );
      },
    );

    // ── 9. Formatted phone passed through to repository ──────────────────
    //
    // After UaPhoneInputFormatter formats the input, the formatted string
    // must be submitted to the repository unchanged so that the backend
    // receives the canonical +380 XX XXX XX XX value.
    testWidgets(
      '9. submit with formatted phone → repo.acceptInviteCalls.first.phoneNumber '
      '== "+380 67 123 45 67"',
      (WidgetTester tester) async {
        final repo = await _pumpValid(tester);

        // Enter a strong password that satisfies all 3 checklist rules:
        //   length >= 12 ✓  |  has digit ✓  |  has uppercase ✓
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

        // Enter the local-format phone — formatter converts it to +380 mask.
        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('invite_phone')),
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('invite_phone')),
          '0671234567',
        );
        await tester.pump();

        // Tap the CTA.
        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('invite_accept')),
        );
        await tester.tap(find.byKey(const ValueKey<String>('invite_accept')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        // The repository received the formatted phone number, not the raw input.
        expect(repo.acceptInviteCalls.length, 1);
        expect(
          repo.acceptInviteCalls.first.phoneNumber,
          '+380 67 123 45 67',
          reason:
              'The accept call must carry the formatter output '
              '"+380 67 123 45 67", not the raw "0671234567"',
        );
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

      // A ValidationFailure with a non-empty fieldErrors map maps each message
      // onto the matching field's inline errorText — no generic banner.
      // The 'password' field error surfaces inline as 'Too common'.
      expect(find.text('Too common'), findsOneWidget);

      // The generic validation banner must NOT appear in this path.
      final l10n = AppLocalizations.of(
        tester.element(find.byType(AcceptInviteScreen)),
      );
      expect(find.text(l10n.errValidation), findsNothing);

      // Screen is still on the form (CTA still present).
      expect(
        find.byKey(const ValueKey<String>('invite_accept')),
        findsOneWidget,
      );
      // Not navigated to /home.
      expect(find.text('home'), findsNothing);
    });

    // ── 7. Multi-field server errors map inline under each field ─────────────
    testWidgets(
      '7. ValidationFailure{firstName, phone} maps each message inline under '
      'its OWN field (no generic banner)',
      (WidgetTester tester) async {
        const firstNameMsg = 'Імʼя недопустиме';
        const phoneMsg = 'Невірний номер';
        final repo = await _pumpValid(
          tester,
          acceptResult: const ValidationFailure(
            fieldErrors: <String, String>{
              'firstName': firstNameMsg,
              'phone': phoneMsg,
            },
          ),
        );

        await tester.enterText(
          find.byKey(const ValueKey<String>('invite_password')),
          'StrongPassword12',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('invite_first_name')),
          'Марія',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('invite_last_name')),
          'Бондар',
        );
        // Valid phone so the client check passes and the server error returns.
        await tester.enterText(
          find.byKey(const ValueKey<String>('invite_phone')),
          '+380671234567',
        );
        await tester.pump();

        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('invite_accept')),
        );
        await tester.tap(find.byKey(const ValueKey<String>('invite_accept')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        expect(repo.acceptInviteCalls.length, 1);

        // firstName error renders inline under the first-name field.
        expect(
          find.descendant(
            of: find.byKey(const ValueKey<String>('invite_first_name')),
            matching: find.text(firstNameMsg),
          ),
          findsOneWidget,
        );
        // phone error renders inline under the phone field.
        expect(
          find.descendant(
            of: find.byKey(const ValueKey<String>('invite_phone')),
            matching: find.text(phoneMsg),
          ),
          findsOneWidget,
        );

        final l10n = AppLocalizations.of(
          tester.element(find.byType(AcceptInviteScreen)),
        );
        expect(find.text(l10n.errValidation), findsNothing);
      },
    );

    // ── 8. Client-side phone format validation blocks before the network ─────
    testWidgets(
      '8. an invalid phone format blocks submit client-side (acceptInvite '
      'never called, inline phone error shown)',
      (WidgetTester tester) async {
        final repo = await _pumpValid(tester);

        await tester.enterText(
          find.byKey(const ValueKey<String>('invite_password')),
          'StrongPassword12',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('invite_first_name')),
          'Марія',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('invite_last_name')),
          'Бондар',
        );
        // Partial phone — formatter yields a too-short number that fails
        // validatePhone's structural check.
        await tester.enterText(
          find.byKey(const ValueKey<String>('invite_phone')),
          '067',
        );
        await tester.pump();

        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('invite_accept')),
        );
        await tester.tap(find.byKey(const ValueKey<String>('invite_accept')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Client-side validation blocked the network call entirely.
        expect(
          repo.acceptInviteCalls,
          isEmpty,
          reason:
              'An invalid phone must block the accept call client-side before '
              'any network request.',
        );

        // Inline phone error is shown.
        final l10n = AppLocalizations.of(
          tester.element(find.byType(AcceptInviteScreen)),
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey<String>('invite_phone')),
            matching: find.text(l10n.errPhoneInvalid),
          ),
          findsOneWidget,
        );
        expect(find.text('home'), findsNothing);
      },
    );

    // ── 9. Empty fieldErrors + serverMessage → banner fallback ───────────────
    testWidgets(
      '9. ValidationFailure with empty fieldErrors falls back to serverMessage '
      'in the inline banner',
      (WidgetTester tester) async {
        const serverMsg = 'Запрошення недійсне';
        final repo = await _pumpValid(
          tester,
          acceptResult: const ValidationFailure(
            fieldErrors: <String, String>{},
            serverMessage: serverMsg,
          ),
        );

        await tester.enterText(
          find.byKey(const ValueKey<String>('invite_password')),
          'StrongPassword12',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('invite_first_name')),
          'Марія',
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
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        expect(repo.acceptInviteCalls.length, 1);

        // The banner shows the serverMessage, not the generic errValidation.
        final l10n = AppLocalizations.of(
          tester.element(find.byType(AcceptInviteScreen)),
        );
        expect(find.text(serverMsg), findsOneWidget);
        expect(find.text(l10n.errValidation), findsNothing);
      },
    );

    // ── 10. Name no-digit validation (Step 2.7 Rule 3 regression) ────────────
    //
    // The first/last name fields delegate to the shared validateName, which
    // now rejects any Unicode decimal digit (mirrors backend @NoDigits). The
    // inline errorText is computed live from validateName, and _clientSideValid
    // gates the accept call on validateName(...) == null, so a digit blocks the
    // network request entirely. A hyphen / apostrophe name is accepted.
    testWidgets(
      '10a. first name with a digit shows errNameHasDigit inline and blocks the '
      'accept call client-side',
      (WidgetTester tester) async {
        final repo = await _pumpValid(tester);

        await tester.enterText(
          find.byKey(const ValueKey<String>('invite_password')),
          'StrongPassword12',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('invite_first_name')),
          'John2',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('invite_last_name')),
          'Бондар',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('invite_phone')),
          '+380671234567',
        );
        await tester.pump();

        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('invite_accept')),
        );
        await tester.tap(find.byKey(const ValueKey<String>('invite_accept')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        final l10n = AppLocalizations.of(
          tester.element(find.byType(AcceptInviteScreen)),
        );
        // Inline digit error under the first-name field.
        expect(
          find.descendant(
            of: find.byKey(const ValueKey<String>('invite_first_name')),
            matching: find.text(l10n.errNameHasDigit),
          ),
          findsOneWidget,
        );
        // The digit blocked the network call client-side.
        expect(
          repo.acceptInviteCalls,
          isEmpty,
          reason: 'a digit in the name must block the accept call client-side',
        );
        expect(find.text('home'), findsNothing);
      },
    );

    testWidgets(
      '10b. last name with a digit shows errNameHasDigit inline and blocks the '
      'accept call client-side',
      (WidgetTester tester) async {
        final repo = await _pumpValid(tester);

        await tester.enterText(
          find.byKey(const ValueKey<String>('invite_password')),
          'StrongPassword12',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('invite_first_name')),
          'Марія',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('invite_last_name')),
          'Kov4l',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('invite_phone')),
          '+380671234567',
        );
        await tester.pump();

        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('invite_accept')),
        );
        await tester.tap(find.byKey(const ValueKey<String>('invite_accept')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        final l10n = AppLocalizations.of(
          tester.element(find.byType(AcceptInviteScreen)),
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey<String>('invite_last_name')),
            matching: find.text(l10n.errNameHasDigit),
          ),
          findsOneWidget,
        );
        expect(
          repo.acceptInviteCalls,
          isEmpty,
          reason: 'a digit in the name must block the accept call client-side',
        );
      },
    );

    testWidgets(
      '10c. hyphen / apostrophe names are accepted → no digit error, accept '
      'call fires',
      (WidgetTester tester) async {
        final repo = await _pumpValid(tester);

        await tester.enterText(
          find.byKey(const ValueKey<String>('invite_password')),
          'StrongPassword12',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('invite_first_name')),
          'Anne-Marie',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('invite_last_name')),
          "O'Brien",
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('invite_phone')),
          '+380671234567',
        );
        await tester.pump();

        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('invite_accept')),
        );
        await tester.tap(find.byKey(const ValueKey<String>('invite_accept')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        final l10n = AppLocalizations.of(
          tester.element(find.byType(AcceptInviteScreen)),
        );
        expect(find.text(l10n.errNameHasDigit), findsNothing);
        expect(
          repo.acceptInviteCalls.length,
          1,
          reason: 'a hyphen/apostrophe name must pass the no-digit guard',
        );
        expect(repo.acceptInviteCalls.first.firstName, 'Anne-Marie');
        expect(repo.acceptInviteCalls.first.lastName, "O'Brien");
      },
    );
  });

  // ─────────────────────────────────────────────────────────────────────────
  // REGRESSION: 'accept_invite_screen' mount-key (patrol CI-hang guard)
  // ─────────────────────────────────────────────────────────────────────────
  //
  // Headless pre-push mirror of the CI-only native patrol test
  // (integration_test/patrol/deep_link_patrol_test.dart). Patrol cannot run on
  // the dev VM (no emulator), so this widget/router tier is the pre-push guard.
  //
  // THE BUG (fixed on feat/master-my-bookings-data-layer): the native deep-link
  // patrol test fired /reset-password, which NO manifest intent-filter matches →
  // Android opened it in the browser → the app backgrounded → the Flutter engine
  // stopped producing frames → `pumpUntilFound` hung for the full 900s CI
  // timeout. The fix retargets the patrol test to /invite/accept (the ONLY
  // approved App Link) and wraps AcceptInviteScreen.build() in a
  // KeyedSubtree(key: ValueKey('accept_invite_screen')) so the screen-container
  // key mounts on the FIRST FRAME in every async state — independent of the
  // token-validation network call.
  //
  // The load-bearing property that prevents the hang is: the mount-key renders
  // in the LOADING state, before (and without) any network completion. A fake
  // token settles loading→error and never reaches the `data` form, so the
  // patrol test asserts the CONTAINER key, not the form 'invite_accept' key.
  // These tests pin exactly that property at the Dart level.
  group('accept_invite_screen mount-key (patrol CI-hang regression)', () {
    const ValueKey<String> mountKey = ValueKey<String>('accept_invite_screen');

    // ── LOADING: key mounts on the first frame with NO network dependency ────
    // This is THE anti-regression assertion. The provider is left in a pending
    // (never-completing) future — the network never resolves — yet the
    // screen-container key must already be present. This is the exact property
    // that keeps the patrol `pumpUntilFound` from hanging: the key it polls is
    // available the instant go_router mounts the screen, no round-trip required.
    testWidgets(
      'R1. LOADING (pending future, no network) → accept_invite_screen key '
      'present on first frame',
      (WidgetTester tester) async {
        await _pumpLoading(tester);

        expect(
          find.byKey(mountKey),
          findsOneWidget,
          reason:
              'The mount-key MUST render on the loading frame, before any '
              'network completion — this is the property that prevents the '
              'patrol pumpUntilFound CI hang.',
        );
        // Proves we are genuinely in the loading state (not data): spinner
        // present, form CTA absent.
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(
          find.byKey(const ValueKey<String>('invite_accept')),
          findsNothing,
        );
      },
    );

    // ── ERROR: a fake/invalid token keeps the screen mounted (never data) ────
    testWidgets(
      'R2. ERROR (invalid token → AsyncError) → accept_invite_screen key still '
      'present; never reaches the data form',
      (WidgetTester tester) async {
        await _pumpError(tester);

        expect(
          find.byKey(mountKey),
          findsOneWidget,
          reason:
              'A fake token settles loading→error but the screen-container key '
              'must stay mounted; the patrol test targets this key precisely '
              'because a fake token never reaches the data form.',
        );
        // Error branch rendered, not the data form.
        expect(find.byType(AuthBanner), findsOneWidget);
        expect(
          find.byKey(const ValueKey<String>('invite_accept')),
          findsNothing,
        );
      },
    );

    // ── PRECONDITION: key absent on a non-/invite/accept route ───────────────
    // Mirrors the patrol precondition (cold start settles to /login → the key
    // is findsNothing before the deep link fires). Guards against the key
    // leaking onto unrelated routes, which would make the patrol precondition
    // and destination assertions indistinguishable.
    testWidgets(
      'R3. PRECONDITION: on /login cold start the accept_invite_screen key is '
      'absent',
      (WidgetTester tester) async {
        final FakeAuthRepository repo = FakeAuthRepository();
        final FakeSecureStorage storage = FakeSecureStorage();
        final GoRouter router = GoRouter(
          initialLocation: RouteNames.login,
          redirect: (BuildContext context, GoRouterState state) => null,
          routes: <RouteBase>[
            GoRoute(
              path: RouteNames.acceptInvite,
              builder: (BuildContext context, GoRouterState state) =>
                  AcceptInviteScreen(
                    token: state.uri.queryParameters['token'] ?? '',
                  ),
            ),
            GoRoute(
              path: RouteNames.login,
              builder: (BuildContext context, GoRouterState state) =>
                  const Scaffold(body: Center(child: Text('login'))),
            ),
            GoRoute(
              path: RouteNames.home,
              builder: (BuildContext context, GoRouterState state) =>
                  const Scaffold(body: Center(child: Text('home'))),
            ),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authRepositoryProvider.overrideWith((_) => repo),
              secureStorageProvider.overrideWithValue(storage),
            ],
            child: MaterialApp.router(
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(mountKey),
          findsNothing,
          reason:
              'Before the deep link fires (cold start on /login) the '
              'accept_invite_screen key must be absent — this is the patrol '
              'precondition that makes the post-openUrl assertion meaningful.',
        );
      },
    );
  });
}
