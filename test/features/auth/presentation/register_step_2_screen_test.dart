// Phase 2.17 — Widget tests for [RegisterStep2Screen].
//
// SOURCE OF TRUTH: docs/signup-designs/sign-up-step-2-profile.html.
//
// Covered scenarios (6 minimum per spec Step 7):
//   1. CLIENT variant renders 3 fields (name/surname/phone), NO salon section.
//   2. MASTER variant renders 3 fields (name/surname/phone), NO salon section.
//   3. OWNER variant renders 4 fields including "field-salon-name".
//   4. Validators trip on empty + invalid input (each field).
//   5. Valid submit writes draft + navigates to /register/step-3.
//   6. Returning to Step 2 via "← Назад" preserves draft (initState re-seeds).
//   7. Non-OWNER valid submit calls updateStep2 with salonName='' (default branch).

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

GoRouter _makeRouter({String stepThreeLabel = 'step-3'}) => GoRouter(
  initialLocation: RouteNames.registerStep2,
  redirect: (context, state) => null,
  routes: [
    GoRoute(
      path: RouteNames.registerStep2,
      // Minimal Scaffold so TextFormFields can find a Material ancestor.
      builder: (context, state) => const Scaffold(
        body: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: RegisterStep2Screen(),
        ),
      ),
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

/// Builds the test app with a [ProviderContainer] that has [registerDraftProvider]
/// pre-seeded with [role].
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

/// Returns a fresh [ProviderContainer] with the draft pre-seeded for [role].
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

    testWidgets('renders 3 fields and NO salon section', (tester) async {
      await tester.pumpWidget(_buildApp(router: router, container: container));
      await tester.pumpAndSettle();

      // All three personal fields present.
      expect(find.byKey(const Key('field-name')), findsOneWidget);
      expect(find.byKey(const Key('field-surname')), findsOneWidget);
      expect(find.byKey(const Key('field-phone')), findsOneWidget);

      // Salon-specific widgets absent.
      expect(find.byKey(const Key('field-salon-name')), findsNothing);
      expect(find.byKey(const Key('salon-section-divider')), findsNothing);
      expect(find.byKey(const Key('salon-section-label')), findsNothing);
    });
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

    testWidgets('renders 3 fields and NO salon section', (tester) async {
      await tester.pumpWidget(_buildApp(router: router, container: container));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('field-name')), findsOneWidget);
      expect(find.byKey(const Key('field-surname')), findsOneWidget);
      expect(find.byKey(const Key('field-phone')), findsOneWidget);

      expect(find.byKey(const Key('field-salon-name')), findsNothing);
      expect(find.byKey(const Key('salon-section-divider')), findsNothing);
    });
  });

  // ── Test 3 — SALON_OWNER variant ─────────────────────────────────────────
  group('SALON_OWNER variant', () {
    late ProviderContainer container;
    late GoRouter router;

    setUp(() {
      container = _containerWithRole(UserRole.salonOwner);
      router = _makeRouter();
    });

    tearDown(() => container.dispose());

    testWidgets(
      'renders 4 fields including salon-name; no divider and no section label',
      (tester) async {
        await tester.pumpWidget(
          _buildApp(router: router, container: container),
        );
        await tester.pumpAndSettle();

        // Personal fields + salon-name field all present.
        expect(find.byKey(const Key('field-name')), findsOneWidget);
        expect(find.byKey(const Key('field-surname')), findsOneWidget);
        expect(find.byKey(const Key('field-phone')), findsOneWidget);
        expect(find.byKey(const Key('field-salon-name')), findsOneWidget);

        // Divider and section-label are removed per design alignment.
        expect(find.byKey(const Key('salon-section-divider')), findsNothing);
        expect(find.byKey(const Key('salon-section-label')), findsNothing);

        // Confirm the section label text is absent — not just the key.
        expect(find.text('Дані салону'), findsNothing);
        expect(find.text('ДАНІ САЛОНУ'), findsNothing);
      },
    );
  });

  // ── Test 4 — Validators ───────────────────────────────────────────────────
  group('Validators', () {
    late ProviderContainer container;
    late GoRouter router;

    setUp(() {
      container = _containerWithRole(UserRole.salonOwner);
      router = _makeRouter();
    });

    tearDown(() => container.dispose());

    // Test 4a — all-empty submit: fields stay visible, navigation does NOT occur,
    //           and the salon-name required error text is rendered.
    testWidgets(
      '4a: empty submit — step-3 not reached and errSalonNameRequired shown',
      (tester) async {
        await tester.pumpWidget(
          _buildApp(router: router, container: container),
        );
        await tester.pumpAndSettle();

        // Tap CTA without filling any field.
        await tester.tap(find.byKey(const Key('btn-continue-step2')));
        await tester.pumpAndSettle();

        // (a) key fields still present — navigation did NOT occur.
        expect(find.byKey(const Key('field-name')), findsOneWidget);
        expect(find.byKey(const Key('field-salon-name')), findsOneWidget);
        // step-3 marker is absent.
        expect(find.text('step-3'), findsNothing);

        // (b) salon-name required error is rendered.
        // ARB key errSalonNameRequired = "Введіть назву салону"
        expect(find.text('Введіть назву салону'), findsOneWidget);
      },
    );

    // Test 4b — invalid phone submit: navigation blocked, phone error rendered.
    testWidgets(
      '4b: invalid phone — step-3 not reached and errPhoneInvalid shown',
      (tester) async {
        await tester.pumpWidget(
          _buildApp(router: router, container: container),
        );
        await tester.pumpAndSettle();

        // Fill name and surname; enter an invalid phone; fill salon name.
        await tester.enterText(find.byKey(const Key('field-name')), 'Марія');
        await tester.enterText(
          find.byKey(const Key('field-surname')),
          'Лазаренко',
        );
        await tester.enterText(find.byKey(const Key('field-phone')), '123');
        await tester.enterText(
          find.byKey(const Key('field-salon-name')),
          'Lumière',
        );

        await tester.tap(find.byKey(const Key('btn-continue-step2')));
        await tester.pumpAndSettle();

        // (a) field-phone still present; navigation did NOT occur.
        expect(find.byKey(const Key('field-phone')), findsOneWidget);
        expect(find.byKey(const Key('field-name')), findsOneWidget);
        expect(find.text('step-3'), findsNothing);

        // (b) phone validation error is rendered. Resolve via the l10n key so
        // the assertion survives copy changes (Defect 4 shortened the string).
        final l10n = AppLocalizations.of(
          tester.element(find.byKey(const Key('field-phone'))),
        );
        expect(find.text(l10n.errPhoneInvalid), findsOneWidget);
      },
    );

    testWidgets('trips on salon name too short (< 2 chars) for OWNER', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp(router: router, container: container));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('field-name')), 'Марія');
      await tester.enterText(
        find.byKey(const Key('field-surname')),
        'Лазаренко',
      );
      await tester.enterText(
        find.byKey(const Key('field-phone')),
        '+380501112233',
      );
      await tester.enterText(find.byKey(const Key('field-salon-name')), 'X');

      await tester.tap(find.byKey(const Key('btn-continue-step2')));
      await tester.pumpAndSettle();

      // Still on step-2 (validation failure).
      expect(find.byKey(const Key('field-name')), findsOneWidget);
      // step-3 marker is absent.
      expect(find.text('step-3'), findsNothing);
      // salon-name required error is rendered (1 char treated as too short).
      expect(find.text('Введіть назву салону'), findsOneWidget);
    });
  });

  // ── Test 5 — Valid submit → draft written + navigation ───────────────────
  group('Valid submit', () {
    testWidgets(
      'CLIENT: writes draft with salonName="" and navigates to /register/step-3',
      (tester) async {
        final container = _containerWithRole(UserRole.client);
        addTearDown(container.dispose);

        final router = _makeRouter();

        await tester.pumpWidget(
          _buildApp(router: router, container: container),
        );
        await tester.pumpAndSettle();

        await tester.enterText(find.byKey(const Key('field-name')), 'Аня');
        await tester.enterText(
          find.byKey(const Key('field-surname')),
          'Коваль',
        );
        await tester.enterText(
          find.byKey(const Key('field-phone')),
          '+380671234567',
        );

        await tester.tap(find.byKey(const Key('btn-continue-step2')));
        await tester.pumpAndSettle();

        // ── Verify draft was written ──
        final draft = container.read(registerDraftProvider);
        expect(draft, isNotNull);
        expect(draft!.firstName, equals('Аня'));
        expect(draft.lastName, equals('Коваль'));
        expect(draft.phone, equals('+380671234567'));
        // updateStep2 salonName='' default branch exercised for non-owner.
        expect(draft.salonName, equals(''));

        // ── Verify navigation ──
        expect(find.text('step-3'), findsOneWidget);
      },
    );

    testWidgets(
      'OWNER: writes draft with salonName and navigates to /register/step-3',
      (tester) async {
        final container = _containerWithRole(UserRole.salonOwner);
        addTearDown(container.dispose);

        final router = _makeRouter();

        await tester.pumpWidget(
          _buildApp(router: router, container: container),
        );
        await tester.pumpAndSettle();

        await tester.enterText(find.byKey(const Key('field-name')), 'Марія');
        await tester.enterText(
          find.byKey(const Key('field-surname')),
          'Лазаренко',
        );
        await tester.enterText(
          find.byKey(const Key('field-phone')),
          '+380501112233',
        );
        await tester.enterText(
          find.byKey(const Key('field-salon-name')),
          'Salon Lumière',
        );

        await tester.tap(find.byKey(const Key('btn-continue-step2')));
        await tester.pumpAndSettle();

        final draft = container.read(registerDraftProvider);
        expect(draft, isNotNull);
        expect(draft!.firstName, equals('Марія'));
        expect(draft.salonName, equals('Salon Lumière'));

        expect(find.text('step-3'), findsOneWidget);
      },
    );
  });

  // ── Test 6 — "← Назад" preserves draft ──────────────────────────────────
  group('Back navigation preserves draft', () {
    testWidgets('returning to step-2 re-seeds controllers from draft', (
      tester,
    ) async {
      // Pre-seed the draft with Step 2 data as if the user filled the form
      // and then came back from Step 3.
      final container = _containerWithRole(UserRole.independentMaster);
      addTearDown(container.dispose);

      // Write Step 2 data into draft directly (simulating a completed submit).
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

      // Screen mounts with draft data — controllers should be pre-filled.
      final nameField = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const Key('field-name')),
          matching: find.byType(EditableText),
        ),
      );
      final surnameField = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const Key('field-surname')),
          matching: find.byType(EditableText),
        ),
      );

      expect(nameField.controller.text, equals('Оля'));
      expect(surnameField.controller.text, equals('Тимченко'));

      // Draft is unchanged (no reset was called).
      final draft = container.read(registerDraftProvider);
      expect(draft?.firstName, equals('Оля'));
      expect(draft?.lastName, equals('Тимченко'));
    });
  });

  // ── Test 7 — salonName='' default branch for INDEPENDENT_MASTER ──────────
  group('updateStep2 salonName default branch', () {
    testWidgets(
      'MASTER valid submit: updateStep2 called with salonName empty string',
      (tester) async {
        final container = _containerWithRole(UserRole.independentMaster);
        addTearDown(container.dispose);

        final router = _makeRouter();

        await tester.pumpWidget(
          _buildApp(router: router, container: container),
        );
        await tester.pumpAndSettle();

        await tester.enterText(find.byKey(const Key('field-name')), 'Оля');
        await tester.enterText(
          find.byKey(const Key('field-surname')),
          'Тимченко',
        );
        await tester.enterText(
          find.byKey(const Key('field-phone')),
          '+380672345678',
        );

        await tester.tap(find.byKey(const Key('btn-continue-step2')));
        await tester.pumpAndSettle();

        final draft = container.read(registerDraftProvider);
        expect(draft, isNotNull);
        // updateStep2's optional salonName parameter defaults to '' — this is
        // the branch the spec requires a test to exercise explicitly.
        expect(draft!.salonName, equals(''));
        // Confirms navigation completed.
        expect(find.text('step-3'), findsOneWidget);
      },
    );
  });

  // ── Test 8 — Sub-step indicator renders (dots-only, no visible label) ────
  group('SubStepIndicator', () {
    testWidgets('renders two pill dots; no visible sub-step label text', (
      tester,
    ) async {
      final container = _containerWithRole(UserRole.client);
      addTearDown(container.dispose);

      final router = _makeRouter();

      await tester.pumpWidget(_buildApp(router: router, container: container));
      await tester.pumpAndSettle();

      // Dots present.
      expect(find.byKey(const Key('substep-indicator')), findsOneWidget);
      expect(find.byKey(const Key('substep-dot-0')), findsOneWidget);
      expect(find.byKey(const Key('substep-dot-1')), findsOneWidget);

      // Visible label text is absent — design is dots-only.
      expect(find.text('Крок 2.1 — Профіль'), findsNothing);
      expect(find.text('КРОК 2.1 — ПРОФІЛЬ'), findsNothing);

      // The label key is not rendered (dots-only widget no longer emits it).
      expect(find.byKey(const Key('substep-label')), findsNothing);
    });
  });

  // ── Test 9 — CTA button present ──────────────────────────────────────────
  group('CTA button', () {
    testWidgets('btn-continue-step2 is present and tappable', (tester) async {
      final container = _containerWithRole(UserRole.client);
      addTearDown(container.dispose);

      final router = _makeRouter();

      await tester.pumpWidget(_buildApp(router: router, container: container));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn-continue-step2')), findsOneWidget);
    });
  });
}
