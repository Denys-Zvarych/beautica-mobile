// Phase 2.21 — Widget tests for [RegisterStep2Screen] — VelvetTouch redesign.
// (Updated from Phase 2.17: phone field now uses UaPhoneInputFormatter — entered
// phone text is auto-formatted to "+380 XX XXX XX XX". Draft.phone assertions
// and format-validation tests updated accordingly.)
//
// Design source: docs/signup-designs/VelvetTouchDesign/lib/screens/sign_up_screen.dart
// (profile-fields section only).
//
// Key changes from the glassmorphism version:
//   - Field keys updated: step2_first_name, step2_last_name, step2_phone,
//     step2_salon_name, step2_submit (ValueKey<String>).
//   - No Form/TextFormField — validation is inline (phone touched-driven).
//   - No SubStepIndicator, no sub-step dots (shell owns progress).
//   - No BackdropFilter, no glassmorphism in the widget tree.
//   - AuthScaffold owns the Scaffold — router must NOT add a second Scaffold.
//
// Covered scenarios:
//   1. CLIENT: firstName, lastName, phone fields present; salon_name absent.
//   2. SALON_OWNER: all four fields present.
//   3. Phone required validation fires after _phoneTouched (inline error).
//   4. Name required validation — first/last name are REQUIRED for all roles;
//      the blank-name gate runs before the phone checks and blocks navigation
//      (errNameRequired surfaced). Phone-validation tests fill valid names so
//      they isolate the phone behaviour they assert.
//   5. Pre-fill from draft in initState.
//   6. Navigates to registerStep3 on valid submit (names + phone non-empty).
//   7. updateStep2 called with correct args on submit.
//   8. No BackdropFilter in the widget tree.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/register_step_2_screen.dart';
import 'package:beautica_mobile/features/auth/state/register_draft_notifier.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Builds a router for the test. The Step-2 route renders [RegisterStep2Screen]
/// directly — no outer Scaffold wrapper because [AuthScaffold] owns the
/// Scaffold internally.
GoRouter _makeRouter({String stepThreeLabel = 'step-3'}) => GoRouter(
  initialLocation: RouteNames.registerStep2,
  redirect: (context, state) => null,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.registerStep2,
      builder: (context, state) => const RegisterStep2Screen(),
    ),
    GoRoute(
      path: RouteNames.registerStep3,
      builder: (context, state) =>
          Scaffold(body: Center(child: Text(stepThreeLabel))),
    ),
    GoRoute(
      path: RouteNames.register,
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('step-1'))),
    ),
    GoRoute(
      path: RouteNames.registerRole,
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('role-selection'))),
    ),
  ],
);

/// Wraps the app under test in [UncontrolledProviderScope] and the minimal
/// localisation + routing delegates.
Widget _buildApp({
  required GoRouter router,
  required ProviderContainer container,
}) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp.router(
    routerConfig: router,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('uk'),
  ),
);

/// Creates a fresh [ProviderContainer] with the draft pre-seeded for [role].
ProviderContainer _containerWithRole(UserRole role) {
  final container = ProviderContainer();
  container.read(registerDraftProvider.notifier).start(role);
  return container;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ── Test 1 — CLIENT variant ───────────────────────────────────────────────
  group('CLIENT variant', () {
    late ProviderContainer container;
    late GoRouter router;

    setUp(() {
      container = _containerWithRole(UserRole.client);
      router = _makeRouter();
    });

    tearDown(() => container.dispose());

    testWidgets(
      'renders firstName, lastName, phone fields; salon_name absent',
      (tester) async {
        await tester.pumpWidget(
          _buildApp(router: router, container: container),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('step2_first_name')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('step2_last_name')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('step2_phone')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('step2_salon_name')),
          findsNothing,
        );
      },
    );
  });

  // ── Test 2 — INDEPENDENT_MASTER variant ──────────────────────────────────
  group('INDEPENDENT_MASTER variant', () {
    late ProviderContainer container;
    late GoRouter router;

    setUp(() {
      container = _containerWithRole(UserRole.independentMaster);
      router = _makeRouter();
    });

    tearDown(() => container.dispose());

    testWidgets(
      'renders firstName, lastName, phone fields; salon_name absent',
      (tester) async {
        await tester.pumpWidget(
          _buildApp(router: router, container: container),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('step2_first_name')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('step2_last_name')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('step2_phone')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('step2_salon_name')),
          findsNothing,
        );
      },
    );
  });

  // ── Test 2b — SALON_OWNER variant ────────────────────────────────────────
  group('SALON_OWNER variant', () {
    late ProviderContainer container;
    late GoRouter router;

    setUp(() {
      container = _containerWithRole(UserRole.salonOwner);
      router = _makeRouter();
    });

    tearDown(() => container.dispose());

    testWidgets('renders all four fields', (tester) async {
      await tester.pumpWidget(_buildApp(router: router, container: container));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('step2_first_name')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('step2_last_name')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey<String>('step2_phone')), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('step2_salon_name')),
        findsOneWidget,
      );
    });
  });

  // ── Test 3 — Phone required inline error after touch ─────────────────────
  group('Phone required validation', () {
    testWidgets(
      'shows registerPhoneRequired after tapping submit with empty phone',
      (tester) async {
        final container = _containerWithRole(UserRole.client);
        addTearDown(container.dispose);
        final router = _makeRouter();

        await tester.pumpWidget(
          _buildApp(router: router, container: container),
        );
        await tester.pumpAndSettle();

        // Names are required and gate submit before the phone check — fill
        // valid names so this test isolates the empty-phone behaviour.
        await tester.enterText(
          find.byKey(const ValueKey<String>('step2_first_name')),
          'Аня',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('step2_last_name')),
          'Коваль',
        );

        // Tap submit without entering a phone number.
        await tester.tap(find.byKey(const ValueKey<String>('step2_submit')));
        await tester.pumpAndSettle();

        // Error is surfaced via the inline NeumorphicTextField errorText.
        // Resolve via l10n key so the assertion survives copy changes.
        final l10n = AppLocalizations.of(
          tester.element(find.byKey(const ValueKey<String>('step2_phone'))),
        );
        expect(find.text(l10n.registerPhoneRequired), findsOneWidget);

        // Navigation did NOT occur.
        expect(find.text('step-3'), findsNothing);
      },
    );

    testWidgets(
      'error shown when phone field touched with valid chars then cleared',
      (tester) async {
        final container = _containerWithRole(UserRole.client);
        addTearDown(container.dispose);
        final router = _makeRouter();

        await tester.pumpWidget(
          _buildApp(router: router, container: container),
        );
        await tester.pumpAndSettle();

        final phoneFinder = find.byKey(const ValueKey<String>('step2_phone'));

        // Enter '067' — UaPhoneInputFormatter produces '+380 67' (non-empty),
        // triggering onChanged with a non-empty value → sets _phoneTouched=true
        // and _phoneValue='+380 67'.
        await tester.enterText(phoneFinder, '067');
        await tester.pumpAndSettle();

        // Clear the field — formatter returns empty → onChanged('')
        // → _phoneValue='' (still touched).
        await tester.enterText(phoneFinder, '');
        await tester.pumpAndSettle();

        // _phoneTouched=true, _phoneValue='' → _phoneError is non-null.
        final l10n = AppLocalizations.of(tester.element(phoneFinder));
        expect(find.text(l10n.registerPhoneRequired), findsOneWidget);
      },
    );
  });

  // ── Name required validation (regression) ────────────────────────────────
  //
  // First and last name are now REQUIRED for all roles. The blank-name gate in
  // _onSubmit() runs BEFORE the phone checks: if either name is blank after
  // trim, both touched flags are set and submit returns WITHOUT navigating.
  // These tests pin that behaviour (the bug fixed was empty names advancing to
  // Step 3).
  group('Name required validation', () {
    testWidgets(
      'empty first name (valid last name + phone) blocks submit and shows '
      'errNameRequired',
      (tester) async {
        final container = _containerWithRole(UserRole.client);
        addTearDown(container.dispose);
        final router = _makeRouter();

        await tester.pumpWidget(
          _buildApp(router: router, container: container),
        );
        await tester.pumpAndSettle();

        // First name left blank; last name + phone valid.
        await tester.enterText(
          find.byKey(const ValueKey<String>('step2_last_name')),
          'Коваль',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('step2_phone')),
          '+380671234567',
        );

        await tester.tap(find.byKey(const ValueKey<String>('step2_submit')));
        await tester.pumpAndSettle();

        // Navigation blocked.
        expect(find.text('step-3'), findsNothing);

        // errNameRequired surfaced (under the empty first-name field).
        final l10n = AppLocalizations.of(
          tester.element(
            find.byKey(const ValueKey<String>('step2_first_name')),
          ),
        );
        expect(find.text(l10n.errNameRequired), findsOneWidget);
      },
    );

    testWidgets(
      'empty last name (valid first name + phone) blocks submit and shows '
      'errNameRequired',
      (tester) async {
        final container = _containerWithRole(UserRole.client);
        addTearDown(container.dispose);
        final router = _makeRouter();

        await tester.pumpWidget(
          _buildApp(router: router, container: container),
        );
        await tester.pumpAndSettle();

        // Last name left blank; first name + phone valid.
        await tester.enterText(
          find.byKey(const ValueKey<String>('step2_first_name')),
          'Аня',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('step2_phone')),
          '+380671234567',
        );

        await tester.tap(find.byKey(const ValueKey<String>('step2_submit')));
        await tester.pumpAndSettle();

        // Navigation blocked.
        expect(find.text('step-3'), findsNothing);

        // errNameRequired surfaced (under the empty last-name field).
        final l10n = AppLocalizations.of(
          tester.element(find.byKey(const ValueKey<String>('step2_last_name'))),
        );
        expect(find.text(l10n.errNameRequired), findsOneWidget);
      },
    );

    testWidgets(
      'both names empty (valid phone) blocks submit and shows errNameRequired '
      'under both fields',
      (tester) async {
        final container = _containerWithRole(UserRole.client);
        addTearDown(container.dispose);
        final router = _makeRouter();

        await tester.pumpWidget(
          _buildApp(router: router, container: container),
        );
        await tester.pumpAndSettle();

        // Both names blank; phone valid.
        await tester.enterText(
          find.byKey(const ValueKey<String>('step2_phone')),
          '+380671234567',
        );

        await tester.tap(find.byKey(const ValueKey<String>('step2_submit')));
        await tester.pumpAndSettle();

        // Navigation blocked.
        expect(find.text('step-3'), findsNothing);

        // errNameRequired surfaced under BOTH name fields.
        final l10n = AppLocalizations.of(
          tester.element(
            find.byKey(const ValueKey<String>('step2_first_name')),
          ),
        );
        expect(find.text(l10n.errNameRequired), findsNWidgets(2));
      },
    );

    testWidgets('valid first + last name + valid phone navigates to step-3', (
      tester,
    ) async {
      final container = _containerWithRole(UserRole.client);
      addTearDown(container.dispose);
      final router = _makeRouter();

      await tester.pumpWidget(_buildApp(router: router, container: container));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey<String>('step2_first_name')),
        'Аня',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('step2_last_name')),
        'Коваль',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('step2_phone')),
        '+380671234567',
      );

      await tester.tap(find.byKey(const ValueKey<String>('step2_submit')));
      await tester.pumpAndSettle();

      expect(find.text('step-3'), findsOneWidget);
    });
  });

  // ── Test 4 — Pre-fill from draft in initState ────────────────────────────
  group('Pre-fill from draft', () {
    testWidgets('initState seeds controllers from existing draft', (
      tester,
    ) async {
      final container = _containerWithRole(UserRole.independentMaster);
      addTearDown(container.dispose);

      // Write Step 2 data into the draft directly (simulates returning from
      // Step 3 via the back button).
      container
          .read(registerDraftProvider.notifier)
          .updateStep2(
            firstName: 'Оля',
            lastName: 'Тимченко',
            phone: '+380672345678',
          );

      final router = _makeRouter();
      await tester.pumpWidget(_buildApp(router: router, container: container));
      await tester.pumpAndSettle();

      // Controllers should be pre-filled from the draft.
      final nameEditables = find.descendant(
        of: find.byKey(const ValueKey<String>('step2_first_name')),
        matching: find.byType(EditableText),
      );
      final surnameEditables = find.descendant(
        of: find.byKey(const ValueKey<String>('step2_last_name')),
        matching: find.byType(EditableText),
      );

      expect(
        tester.widget<EditableText>(nameEditables).controller.text,
        equals('Оля'),
      );
      expect(
        tester.widget<EditableText>(surnameEditables).controller.text,
        equals('Тимченко'),
      );
    });
  });

  // ── Test 5 — Valid submit navigates to registerStep3 ─────────────────────
  group('Valid submit', () {
    testWidgets(
      'CLIENT: navigates to /register/step-3 when phone is non-empty',
      (tester) async {
        final container = _containerWithRole(UserRole.client);
        addTearDown(container.dispose);
        final router = _makeRouter();

        await tester.pumpWidget(
          _buildApp(router: router, container: container),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey<String>('step2_first_name')),
          'Аня',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('step2_last_name')),
          'Коваль',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('step2_phone')),
          '+380671234567',
        );

        await tester.tap(find.byKey(const ValueKey<String>('step2_submit')));
        await tester.pumpAndSettle();

        expect(find.text('step-3'), findsOneWidget);
      },
    );

    testWidgets(
      'OWNER: navigates to /register/step-3 when phone and salon name filled',
      (tester) async {
        final container = _containerWithRole(UserRole.salonOwner);
        addTearDown(container.dispose);
        final router = _makeRouter();

        await tester.pumpWidget(
          _buildApp(router: router, container: container),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey<String>('step2_first_name')),
          'Марія',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('step2_last_name')),
          'Лазаренко',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('step2_phone')),
          '+380501112233',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('step2_salon_name')),
          'Salon Lumière',
        );

        await tester.tap(find.byKey(const ValueKey<String>('step2_submit')));
        await tester.pumpAndSettle();

        expect(find.text('step-3'), findsOneWidget);
      },
    );
  });

  // ── Test 6 — updateStep2 called with correct args ────────────────────────
  group('updateStep2 args', () {
    testWidgets(
      'CLIENT: draft has correct firstName, lastName, phone; salonName is ""',
      (tester) async {
        final container = _containerWithRole(UserRole.client);
        addTearDown(container.dispose);
        final router = _makeRouter();

        await tester.pumpWidget(
          _buildApp(router: router, container: container),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey<String>('step2_first_name')),
          'Аня',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('step2_last_name')),
          'Коваль',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('step2_phone')),
          '+380671234567',
        );

        await tester.tap(find.byKey(const ValueKey<String>('step2_submit')));
        await tester.pumpAndSettle();

        final draft = container.read(registerDraftProvider);
        expect(draft, isNotNull);
        expect(draft!.firstName, equals('Аня'));
        expect(draft.lastName, equals('Коваль'));
        // UaPhoneInputFormatter reformats the entered value to the masked form.
        expect(draft.phone, equals('+380 67 123 45 67'));
        // Non-owner: salonName must be '' (exercises the optional default branch).
        expect(draft.salonName, equals(''));
      },
    );

    testWidgets('OWNER: draft has correct salonName from field', (
      tester,
    ) async {
      final container = _containerWithRole(UserRole.salonOwner);
      addTearDown(container.dispose);
      final router = _makeRouter();

      await tester.pumpWidget(_buildApp(router: router, container: container));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey<String>('step2_first_name')),
        'Марія',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('step2_last_name')),
        'Лазаренко',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('step2_phone')),
        '+380501112233',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('step2_salon_name')),
        'Salon Lumière',
      );

      await tester.tap(find.byKey(const ValueKey<String>('step2_submit')));
      await tester.pumpAndSettle();

      final draft = container.read(registerDraftProvider);
      expect(draft, isNotNull);
      expect(draft!.salonName, equals('Salon Lumière'));
    });

    testWidgets('INDEPENDENT_MASTER: salonName is "" on submit', (
      tester,
    ) async {
      final container = _containerWithRole(UserRole.independentMaster);
      addTearDown(container.dispose);
      final router = _makeRouter();

      await tester.pumpWidget(_buildApp(router: router, container: container));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey<String>('step2_first_name')),
        'Оля',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('step2_last_name')),
        'Тимченко',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('step2_phone')),
        '+380672345678',
      );

      await tester.tap(find.byKey(const ValueKey<String>('step2_submit')));
      await tester.pumpAndSettle();

      final draft = container.read(registerDraftProvider);
      expect(draft, isNotNull);
      expect(draft!.salonName, equals(''));
      expect(find.text('step-3'), findsOneWidget);
    });
  });

  // ── Test 7 — No BackdropFilter in tree ───────────────────────────────────
  group('VelvetTouch design constraints', () {
    testWidgets('no BackdropFilter widget exists in the tree', (tester) async {
      final container = _containerWithRole(UserRole.client);
      addTearDown(container.dispose);
      final router = _makeRouter();

      await tester.pumpWidget(_buildApp(router: router, container: container));
      await tester.pumpAndSettle();

      expect(find.byType(BackdropFilter), findsNothing);
    });
  });

  // ── Back-nav dedup — auth_scaffold_back on Step 2 ────────────────────────
  //
  // GROUP A regression: Step 2 now delegates back-navigation entirely to
  // AuthScaffold (key 'auth_scaffold_back'). The old bottom-row duplicate was
  // removed. Tapping auth_scaffold_back must navigate to /register (Step 1)
  // and PRESERVE the draft (the in-progress wizard state must survive
  // stepping back one step).
  group('Back-nav dedup (GROUP A regression)', () {
    testWidgets(
      'auth_scaffold_back is present on Step 2 and navigates to /register '
      '(Step 1), preserving the draft',
      (tester) async {
        final container = _containerWithRole(UserRole.client);
        addTearDown(container.dispose);
        final router = _makeRouter();

        await tester.pumpWidget(
          _buildApp(router: router, container: container),
        );
        await tester.pumpAndSettle();

        // Sanity — draft has role set (from _containerWithRole).
        expect(
          container.read(registerDraftProvider),
          isNotNull,
          reason: 'Draft must be seeded before the back-nav test',
        );

        expect(
          find.byKey(const ValueKey<String>('auth_scaffold_back')),
          findsOneWidget,
          reason:
              'Step 2 wraps its own AuthScaffold — auth_scaffold_back must '
              'be rendered',
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('auth_scaffold_back')),
        );
        await tester.pumpAndSettle();

        // Navigated to /register (Step 1).
        expect(
          router.routerDelegate.currentConfiguration.fullPath,
          equals(RouteNames.register),
          reason:
              'auth_scaffold_back on Step 2 must navigate to /register (Step 1)',
        );
        expect(find.text('step-1'), findsOneWidget);

        // Draft is preserved — role must still be set.
        expect(
          container.read(registerDraftProvider),
          isNotNull,
          reason:
              'Tapping auth_scaffold_back on Step 2 must NOT reset() the draft',
        );
      },
    );
  });

  // ── M-REG-PHONE-FORMAT-1 / M-REG-PHONE-FORMAT-2 regression tests ──────────
  //
  // Security agent MEDIUM-1 fix: validatePhone() rejects structurally invalid
  // numbers (partial phone with fewer than 9 subscriber digits). These tests
  // verify:
  //   FORMAT-1 — partial input (2 subscriber digits) → blocked (errPhoneInvalid
  //              shown, no navigation).
  //   FORMAT-2 — "+380501234567" → proceeds (no error, navigates to step-3).
  //
  // Note: "+" alone is now stripped to empty by UaPhoneInputFormatter, so it
  // triggers the required-field guard (registerPhoneRequired), not errPhoneInvalid.
  // FORMAT-1 now uses a partial number ('067' → '+380 67', 2 subscriber digits)
  // which passes the empty guard but fails validatePhone's 9-digit check.
  //
  // Also covers the _phoneFormatError-cleared-on-edit path: after a format
  // error is set by submit, typing in the phone field must clear the error.
  group('Phone format validation (M-REG-PHONE-FORMAT regression)', () {
    testWidgets(
      'M-REG-PHONE-FORMAT-1: partial "067" (→ "+380 67") blocks submit and '
      'shows errPhoneInvalid',
      (tester) async {
        final container = _containerWithRole(UserRole.client);
        addTearDown(container.dispose);
        final router = _makeRouter();

        await tester.pumpWidget(
          _buildApp(router: router, container: container),
        );
        await tester.pumpAndSettle();

        // Names are required and gate submit before the phone check — fill
        // valid names so this test isolates the phone-format behaviour.
        await tester.enterText(
          find.byKey(const ValueKey<String>('step2_first_name')),
          'Аня',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('step2_last_name')),
          'Коваль',
        );

        // Enter a partial UA number (only 2 subscriber digits after the local
        // prefix) — formatter produces '+380 67'. This passes the empty guard
        // but has only 2 subscriber digits, which validatePhone rejects.
        await tester.enterText(
          find.byKey(const ValueKey<String>('step2_phone')),
          '067',
        );

        // Tap submit.
        await tester.tap(find.byKey(const ValueKey<String>('step2_submit')));
        await tester.pumpAndSettle();

        // Navigation must be blocked.
        expect(find.text('step-3'), findsNothing);

        // Format error (errPhoneInvalid) must be visible, not the empty-field
        // required message.
        final l10n = AppLocalizations.of(
          tester.element(find.byKey(const ValueKey<String>('step2_phone'))),
        );
        expect(find.text(l10n.errPhoneInvalid), findsOneWidget);
        expect(find.text(l10n.registerPhoneRequired), findsNothing);
      },
    );

    testWidgets(
      'M-REG-PHONE-FORMAT-1b: "+" alone is stripped to empty by formatter → '
      'shows registerPhoneRequired (not errPhoneInvalid)',
      (tester) async {
        final container = _containerWithRole(UserRole.client);
        addTearDown(container.dispose);
        final router = _makeRouter();

        await tester.pumpWidget(
          _buildApp(router: router, container: container),
        );
        await tester.pumpAndSettle();

        // Names are required and gate submit before the phone check — fill
        // valid names so this test isolates the phone-required behaviour.
        await tester.enterText(
          find.byKey(const ValueKey<String>('step2_first_name')),
          'Аня',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('step2_last_name')),
          'Коваль',
        );

        // "+" has no digits → formatter returns empty string.
        await tester.enterText(
          find.byKey(const ValueKey<String>('step2_phone')),
          '+',
        );

        await tester.tap(find.byKey(const ValueKey<String>('step2_submit')));
        await tester.pumpAndSettle();

        expect(find.text('step-3'), findsNothing);

        final l10n = AppLocalizations.of(
          tester.element(find.byKey(const ValueKey<String>('step2_phone'))),
        );
        // Empty guard fires — required error shown.
        expect(find.text(l10n.registerPhoneRequired), findsOneWidget);
        expect(find.text(l10n.errPhoneInvalid), findsNothing);
      },
    );

    testWidgets(
      'M-REG-PHONE-FORMAT-2: "+380501234567" passes validation and navigates',
      (tester) async {
        final container = _containerWithRole(UserRole.client);
        addTearDown(container.dispose);
        final router = _makeRouter();

        await tester.pumpWidget(
          _buildApp(router: router, container: container),
        );
        await tester.pumpAndSettle();

        // Resolve l10n before navigation removes the Step 2 widgets from the
        // tree.
        final l10n = AppLocalizations.of(
          tester.element(find.byKey(const ValueKey<String>('step2_phone'))),
        );

        // Names are required and gate submit before the phone check — fill
        // valid names so a valid phone can navigate to step-3.
        await tester.enterText(
          find.byKey(const ValueKey<String>('step2_first_name')),
          'Аня',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('step2_last_name')),
          'Коваль',
        );

        await tester.enterText(
          find.byKey(const ValueKey<String>('step2_phone')),
          '+380501234567',
        );

        await tester.tap(find.byKey(const ValueKey<String>('step2_submit')));
        await tester.pumpAndSettle();

        // No phone error was rendered before navigation.
        expect(find.text(l10n.errPhoneInvalid), findsNothing);
        expect(find.text(l10n.registerPhoneRequired), findsNothing);

        // Navigation to step-3 occurred.
        expect(find.text('step-3'), findsOneWidget);
      },
    );

    testWidgets(
      'format error cleared when user edits phone field after failed submit',
      (tester) async {
        final container = _containerWithRole(UserRole.client);
        addTearDown(container.dispose);
        final router = _makeRouter();

        await tester.pumpWidget(
          _buildApp(router: router, container: container),
        );
        await tester.pumpAndSettle();

        final phoneFinder = find.byKey(const ValueKey<String>('step2_phone'));

        // Names are required and gate submit before the phone check — fill
        // valid names so the format error path is reached.
        await tester.enterText(
          find.byKey(const ValueKey<String>('step2_first_name')),
          'Аня',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('step2_last_name')),
          'Коваль',
        );

        // 1. Trigger a format error: submit with '067' (partial — 2 subscriber
        //    digits after the local-prefix strip → '+380 67' → not 9 digits).
        await tester.enterText(phoneFinder, '067');
        await tester.tap(find.byKey(const ValueKey<String>('step2_submit')));
        await tester.pumpAndSettle();

        final l10n = AppLocalizations.of(tester.element(phoneFinder));
        expect(find.text(l10n.errPhoneInvalid), findsOneWidget);

        // 2. User edits the field — _phoneFormatError must be cleared
        //    immediately on onChanged, before the next submit.
        await tester.enterText(phoneFinder, '0671234567');
        await tester.pumpAndSettle();

        // Format error is gone; the required error is also absent (field is
        // non-empty and a full number).
        expect(find.text(l10n.errPhoneInvalid), findsNothing);
        expect(find.text(l10n.registerPhoneRequired), findsNothing);
      },
    );
  });

  // ── Contact-info icon tile (Phase 2.x icon standardisation) ───────────────
  group('Contact-info icon tile', () {
    testWidgets('person_outline_rounded icon tile renders at top of Step 2 '
        '(VelvetTouch icon tile consistency — no VelvetHeader logo)', (
      tester,
    ) async {
      final container = _containerWithRole(UserRole.client);
      addTearDown(container.dispose);
      final router = _makeRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(_buildApp(router: router, container: container));
      await tester.pumpAndSettle();

      final icons = tester.widgetList<Icon>(find.byType(Icon)).toList();
      expect(
        icons.any((i) => i.icon == Icons.person_outline_rounded),
        isTrue,
        reason:
            'RegisterStep2Screen must render Icons.person_outline_rounded '
            '(72×72 neumorphic icon tile) at the top of the screen.',
      );
    });
  });
}
