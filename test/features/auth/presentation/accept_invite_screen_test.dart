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
//   4. Password < 8 chars → CTA disabled (PasswordChecklist rules unmet).
//      The invite path shares the SAME 8-char minimum as register/reset —
//      see `passwordRules`'s default (fixed 2026-09-01; it used to override
//      minLength to 12, diverging from the backend's @StrongPassword policy).
//   5. Accept success: fill valid 8+ char password + firstName + lastName +
//      phone (REQUIRED — InviteAcceptRequest.phoneNumber is @NotBlank) →
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

import 'package:beautica_mobile/features/auth/state/login_notice_notifier.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

const String _kToken = 'test-invite-token';

final _validInvite = InviteDetails(
  email: 'masha@salon.ua',
  role: UserRole.salonMaster,
  expiresAt: DateTime.now().add(const Duration(hours: 48)),
);

// ---------------------------------------------------------------------------
// Router factory
// ---------------------------------------------------------------------------

// Invite-accept post-success failure design (2026-09-01), item 14 — distinct
// marker TYPES (not a shared generic Scaffold+Text('login')) for the home
// and login destinations. go_router's literal-vs-dynamic route shadowing can
// make declaration order alone resolve the wrong builder while still
// rendering matching-looking output; asserting `find.byType(_LoginProbe)`
// pins that the LOGIN route's own builder actually ran, not merely that a
// Text widget with the string 'login' exists somewhere in the tree.
class _LoginProbe extends StatelessWidget {
  const _LoginProbe();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('login')));
}

class _HomeProbe extends StatelessWidget {
  const _HomeProbe();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('home')));
}

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
      builder: (context, state) => const _HomeProbe(),
    ),
    GoRoute(
      path: RouteNames.login,
      builder: (context, state) => const _LoginProbe(),
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
      retry: beauticaProviderRetry,
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
      retry: beauticaProviderRetry,
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
      retry: beauticaProviderRetry,
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
      '4. password < 8 chars → PasswordChecklist shows unmet rules, CTA disabled',
      (WidgetTester tester) async {
        await _pumpValid(tester);

        // 7-char password — below the shared 8-char minimum (passwordRules'
        // default, matching register/reset and the backend's @StrongPassword
        // policy).
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

        // Phone is REQUIRED (InviteAcceptRequest.phoneNumber is @NotBlank) —
        // without it _formValid stays false and the CTA never enables.
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
    // The invite path enforces the same 3 rules as register/reset: length >= 8,
    // has digit, has uppercase. A 13-char lowercase-only string with a digit
    // meets the length rule but fails the uppercase rule — the PasswordChecklist
    // must show at least one
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

        // 13 chars (well over the 8-char minimum), has a digit, but ALL
        // LOWERCASE — fails the uppercase rule.
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

      // Phone is REQUIRED — without it _formValid stays false and the CTA
      // never enables.
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('invite_phone')),
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('invite_phone')),
        '0671234567',
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

    // ── 9. Empty fieldErrors + serverMessage → LOCALIZED banner, never raw ───
    // mobile-security, 2026-08: the inline banner must never render the raw
    // backend serverMessage — it's untrusted/untranslated text on a
    // `Semantics(liveRegion: true)` surface.
    //
    // SUPERSEDED by the invite-accept post-success design (2026-09-01): a
    // 400 with an EMPTY fieldErrors map is, on this endpoint, the backend's
    // generic "invite already used / expired / not found" BusinessException
    // — exactly the case that used to dead-end on a "try again" banner even
    // though the single-use token can never succeed on retry (the reported
    // incident). It is now mapped to InviteHandoffReason.inviteNoLongerValid
    // and the screen hands off to /login instead of showing any banner here
    // — see `AuthNotifier._inviteHandoffReason` and
    // `accept_invite_screen.dart`'s `error:` branch. The raw serverMessage
    // guarantee still holds (it is never shown, on either surface).
    testWidgets(
      '9. ValidationFailure with empty fieldErrors hands off to /login '
      'instead of a dead-end banner, and never leaks the raw serverMessage',
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
        // Phone is REQUIRED — without it _formValid stays false and the CTA
        // never enables.
        await tester.enterText(
          find.byKey(const ValueKey<String>('invite_phone')),
          '0671234567',
        );
        await tester.pump();

        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('invite_accept')),
        );
        await tester.tap(find.byKey(const ValueKey<String>('invite_accept')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();

        expect(repo.acceptInviteCalls.length, 1);

        // The screen hands off to /login — pin the resolved page TYPE
        // (_LoginProbe), not just matching text, per the go_router
        // literal-vs-dynamic shadowing trap.
        expect(find.byType(_LoginProbe), findsOneWidget);
        expect(find.byType(_HomeProbe), findsNothing);
        expect(find.byType(AcceptInviteScreen), findsNothing);

        // item 14: loginNoticeProvider holds the matching reason AND the
        // invited email sourced from acceptInviteProvider (masha@salon.ua —
        // _validInvite's email, the default seed for _pumpValid).
        final container = ProviderScope.containerOf(
          tester.element(find.byType(MaterialApp)),
        );
        final notice = container.read(loginNoticeProvider);
        expect(notice, isNotNull);
        expect(notice!.reason, InviteHandoffReason.inviteNoLongerValid);
        expect(notice.email, _validInvite.email);

        // item 15: the generic banner never renders on any invite-terminal
        // path — neither errUnknown nor errValidation copy anywhere.
        final l10n = lookupAppLocalizations(const Locale('uk'));
        expect(find.text(l10n.errUnknown), findsNothing);
        expect(find.text(l10n.errValidation), findsNothing);

        // Never leak the raw backend serverMessage, on either surface.
        expect(find.text(serverMsg), findsNothing);
      },
    );

    // ── 14b. ResponseUnusableFailure → hand-off (accountReady reason) ────
    //
    // Distinct from test 9 (ValidationFailure/inviteNoLongerValid): a 2xx
    // response the client could not parse must hand off with reason
    // accountReady — the account WAS created, only the mapping failed.
    testWidgets('14b. ResponseUnusableFailure hands off to /login with reason '
        'accountReady and the invited email', (WidgetTester tester) async {
      final repo = await _pumpValid(
        tester,
        acceptResult: const ResponseUnusableFailure(),
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
      await tester.enterText(
        find.byKey(const ValueKey<String>('invite_phone')),
        '0671234567',
      );
      await tester.pump();

      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('invite_accept')),
      );
      await tester.tap(find.byKey(const ValueKey<String>('invite_accept')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(repo.acceptInviteCalls.length, 1);
      expect(find.byType(_LoginProbe), findsOneWidget);
      expect(find.byType(AcceptInviteScreen), findsNothing);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
      );
      final notice = container.read(loginNoticeProvider);
      expect(notice, isNotNull);
      expect(notice!.reason, InviteHandoffReason.accountReady);
      expect(notice.email, _validInvite.email);
    });

    // ── 16. Preview error branch: loginSubmit action on the invite-invalid
    //        banner hands off with reason inviteNoLongerValid ──────────────
    //
    // This is the OTHER hand-off entry point: acceptInviteProvider's OWN
    // error: branch (invalid/expired token discovered on screen load, before
    // any form submit), not AuthNotifier.acceptInvite's. No email is known
    // here — the invite was never successfully loaded.
    testWidgets(
      '16. tapping the invite-invalid banner\'s loginSubmit action navigates '
      'to /login with inviteNoLongerValid set',
      (WidgetTester tester) async {
        await _pumpError(tester);

        expect(find.byType(AuthBanner), findsOneWidget);
        final actionFinder = find.byKey(
          const ValueKey<String>('auth_banner_action'),
        );
        expect(actionFinder, findsOneWidget);

        await tester.tap(actionFinder);
        await tester.pumpAndSettle();

        expect(find.byType(_LoginProbe), findsOneWidget);
        expect(find.byType(AcceptInviteScreen), findsNothing);

        final container = ProviderScope.containerOf(
          tester.element(find.byType(MaterialApp)),
        );
        final notice = container.read(loginNoticeProvider);
        expect(notice, isNotNull);
        expect(notice!.reason, InviteHandoffReason.inviteNoLongerValid);
        expect(
          notice.email,
          isNull,
          reason:
              'no invite was ever successfully loaded on this path, so no '
              'email can be prefilled',
        );
      },
    );

    // ── Validation alignment (2026-09-01 pass, beyond the 18-item plan) ──
    //
    // The invite path now shares the register/reset password policy
    // (min 8, max 128, ≥1 digit, ≥1 uppercase — validateNewPassword) instead
    // of its old 12-char-minimum override, and phone is now REQUIRED end to
    // end. These pin the two behaviour changes at the SCREEN level (the
    // shared validator functions themselves are unit-tested in
    // test/shared/validators/).
    group('validation alignment (password 8/128, empty-phone gate)', () {
      testWidgets(
        'exactly 8-char password (the new minimum) is ACCEPTED — would have '
        'been rejected under the old 12-char minimum',
        (WidgetTester tester) async {
          final repo = await _pumpValid(tester);

          // Exactly 8 chars, 1 digit, 1 uppercase — meets validateNewPassword
          // AND the checklist's 3 rules.
          await tester.enterText(
            find.byKey(const ValueKey<String>('invite_password')),
            'Passwo1d',
          );
          // The checklist row icon crossfades via AnimatedSwitcher (180ms) —
          // settle so the outgoing "unmet" icon has fully left the tree
          // before asserting on it.
          await tester.pumpAndSettle();

          // No unmet-rule icon should remain.
          expect(find.byIcon(Icons.radio_button_unchecked), findsNothing);

          await tester.enterText(
            find.byKey(const ValueKey<String>('invite_first_name')),
            'Марія',
          );
          await tester.enterText(
            find.byKey(const ValueKey<String>('invite_last_name')),
            'Бондар',
          );
          await tester.enterText(
            find.byKey(const ValueKey<String>('invite_phone')),
            '0671234567',
          );
          await tester.pump();

          await tester.ensureVisible(
            find.byKey(const ValueKey<String>('invite_accept')),
          );
          await tester.tap(find.byKey(const ValueKey<String>('invite_accept')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          await tester.pump(const Duration(milliseconds: 100));

          expect(
            repo.acceptInviteCalls.length,
            1,
            reason: 'an exactly-8-char strong password must be accepted',
          );
        },
      );

      testWidgets(
        'invite_password field caps input at 128 chars (its own maxLength — '
        'pre-existing, unchanged by this pass) — a 129-char typed/pasted '
        'value is silently truncated to 128 before any validator runs, so '
        'the field is never UI-reachably >128 chars; the resulting 128-char '
        'password (digit+upper preserved) is ACCEPTED end-to-end, proving '
        'the new validateNewPassword submit gate does not reject the exact '
        'boundary. See FINDING (INFO) in the QA report: the max-128 check '
        'newly wired into _passwordError/_accept is unreachable through this '
        'field\'s own UI and is defense-in-depth only (e.g. against '
        'autofill/programmatic text that bypasses input formatters) — the '
        '>128-rejection behaviour of validateNewPassword itself is unit-'
        'tested directly in test/shared/validators/password_validator_test'
        '.dart, with no formatter in the way.',
        (WidgetTester tester) async {
          final repo = await _pumpValid(tester);
          final longPassword = 'Aa1${'x' * 126}'; // 129 chars, has digit+upper

          await tester.enterText(
            find.byKey(const ValueKey<String>('invite_password')),
            longPassword,
          );
          await tester.pumpAndSettle();

          final field = tester.widget<TextField>(
            find.descendant(
              of: find.byKey(const ValueKey<String>('invite_password')),
              matching: find.byType(TextField),
            ),
          );
          expect(
            field.controller!.text.length,
            128,
            reason:
                'the field\'s own maxLength: 128 truncates input before it '
                'ever reaches _passwordValue/validateNewPassword',
          );
          expect(
            find.byIcon(Icons.radio_button_unchecked),
            findsNothing,
            reason:
                'the truncated 128-char value still has a digit + '
                'uppercase, so all 3 checklist rules stay met',
          );

          await tester.enterText(
            find.byKey(const ValueKey<String>('invite_first_name')),
            'Марія',
          );
          await tester.enterText(
            find.byKey(const ValueKey<String>('invite_last_name')),
            'Бондар',
          );
          await tester.enterText(
            find.byKey(const ValueKey<String>('invite_phone')),
            '0671234567',
          );
          await tester.pump();

          await tester.ensureVisible(
            find.byKey(const ValueKey<String>('invite_accept')),
          );
          await tester.tap(find.byKey(const ValueKey<String>('invite_accept')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          await tester.pump(const Duration(milliseconds: 100));

          expect(
            repo.acceptInviteCalls.length,
            1,
            reason:
                'exactly 128 chars is the boundary, not over it — must be '
                'accepted, not rejected by an off-by-one in the new gate',
          );
        },
      );

      testWidgets(
        'empty phone blocks submission — CTA stays disabled with password + '
        'names filled, acceptInvite is never called and phoneNumber is '
        'never sent as null (the shipped regression: the old gate let an '
        'empty phone through to a guaranteed backend 400)',
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
          // invite_phone deliberately left empty.
          await tester.pump();

          await tester.ensureVisible(
            find.byKey(const ValueKey<String>('invite_accept')),
          );
          // CTA is disabled (_formValid requires non-empty phone) — a tap
          // on a disabled NeumorphicButton is a no-op.
          await tester.tap(
            find.byKey(const ValueKey<String>('invite_accept')),
            warnIfMissed: false,
          );
          await tester.pump(const Duration(milliseconds: 100));

          expect(
            repo.acceptInviteCalls,
            isEmpty,
            reason: 'an empty phone must never reach the repository',
          );
        },
      );
    });

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
            retry: beauticaProviderRetry,
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
