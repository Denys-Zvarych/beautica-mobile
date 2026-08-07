// Widget tests for CategoryRequestDialog — inline server-error mapping and the
// optional initial-service field (Change 3) + keyboard-inset layout (Change 2).
//
// The dialog has the required display-name field (Key
// 'field-category-request-name') and an OPTIONAL initial-service field (Key
// 'field-category-request-initial-service-name'). A backend ValidationFailure
// carrying a `name` / `displayName` field error must map onto the name field's
// inline errorText (_serverNameError) rather than collapsing to a transient
// VelvetSnack. All other failures (and a ValidationFailure with no name/displayName
// key) still surface a VelvetSnack.
//
// Finders use Key lookups (M2). The repository is mocked; no real network.
//
// Covered scenarios:
//   1. ValidationFailure{name}        → inline error under the name field,
//                                       NO VelvetSnack, dialog stays open.
//   2. ValidationFailure{displayName} → inline error (alias key) under the field.
//   3. Editing the name after a server error clears the inline error.
//   4. Non-validation failure (CategoryAlreadyExists) → VelvetSnack, no inline.
//   5. (Change 3) initial-service field EMPTY → requestCategory called with
//      initialServiceName == null; the field is optional (no inline required
//      error when blank).
//   6. (Change 3) initial-service field filled → the TRIMMED value is forwarded.
//   7a. (Change 2 — genuine regression) with a 300 px keyboard the Dialog
//       outer AnimatedPadding.padding.bottom == viewInsets + xl (332), NOT
//       2*viewInsets + xl (632 — the double-count bug).
//   7b. (Change 2 — baseline) with no keyboard, padding.bottom == xl (32) only.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/category_request_dialog.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import '../../../../helpers/velvet_snack_matchers.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class _MockServiceRepository extends Mock implements ServiceRepository {}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

// A GoRouter is needed because the dialog calls context.pop(true) on success.
// The failure paths under test do not pop, but the router must exist so the
// widget tree resolves identically to production.
GoRouter _router() => GoRouter(
  initialLocation: '/',
  routes: <RouteBase>[
    GoRoute(
      path: '/',
      builder: (context, state) => Scaffold(
        body: Builder(
          builder: (ctx) => ElevatedButton(
            key: const Key('trigger'),
            onPressed: () => showCategoryRequestDialog(ctx),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ],
);

Future<void> _openDialog(
  WidgetTester tester,
  _MockServiceRepository repo,
) async {
  await tester.pumpWidget(
    ProviderScope(
      retry: beauticaProviderRetry,
      overrides: [serviceRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp.router(
        routerConfig: _router(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('uk'),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('trigger')));
  await tester.pumpAndSettle();
}

/// Enters a valid display name (transliterates to a valid slug) so the client
/// validation passes and the submit reaches the repository.
Future<void> _enterValidName(WidgetTester tester) async {
  await tester.enterText(
    find.descendant(
      of: find.byKey(const Key('field-category-request-name')),
      matching: find.byType(TextField),
    ),
    'Нарощування вій',
  );
  await tester.pump();
}

/// Enters [value] into the OPTIONAL initial-service field (Change 3).
Future<void> _enterInitialService(WidgetTester tester, String value) async {
  await tester.enterText(
    find.descendant(
      of: find.byKey(const Key('field-category-request-initial-service-name')),
      matching: find.byType(TextField),
    ),
    value,
  );
  await tester.pump();
}

Future<void> _submit(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('btn-submit-suggest-category')));
  await tester.pumpAndSettle();
}

/// Asserts [message] is rendered inline inside the dialog (the _DialogField
/// error row sits next to the keyed NeumorphicInset, inside CategoryRequestDialog)
/// and is NOT a VelvetSnack.
///
/// VelvetSnack lives on the app's ROOT `Overlay` — a SIBLING of the dialog
/// route, never a descendant of it (see `test/helpers/velvet_snack_matchers.dart`)
/// — so the "not a snack" half of this check must be an UNSCOPED
/// `find.byType(VelvetSnack)`, not a `find.descendant(of: ...)` scoped to the
/// dialog (that would vacuously pass no matter what).
void _expectInlineNameError(WidgetTester tester, String message) {
  expect(
    find.descendant(
      of: find.byType(CategoryRequestDialog),
      matching: find.text(message),
    ),
    findsOneWidget,
    reason: 'Server error must render inline inside the dialog name field row.',
  );
  // The same message must NOT be inside a VelvetSnack — it is mapped inline.
  expect(
    find.byType(VelvetSnack),
    findsNothing,
    reason: 'A mapped field error must not also appear in a VelvetSnack.',
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _MockServiceRepository repo;

  setUp(() => repo = _MockServiceRepository());

  testWidgets(
    '1. ValidationFailure keyed by "name" maps to the inline name error '
    '(no snackbar, dialog stays open)',
    (tester) async {
      const serverMsg = 'Назва вже зайнята';
      when(
        () => repo.requestCategory(
          name: any(named: 'name'),
          displayName: any(named: 'displayName'),
          initialServiceName: any(named: 'initialServiceName'),
        ),
      ).thenThrow(
        const ValidationFailure(
          fieldErrors: <String, String>{'name': serverMsg},
        ),
      );

      await _openDialog(tester, repo);
      await _enterValidName(tester);
      await _submit(tester);

      _expectInlineNameError(tester, serverMsg);
      // No VelvetSnack — the error was mapped inline.
      expect(find.byType(VelvetSnack), findsNothing);
      // Dialog stays open (submit button still present).
      expect(
        find.byKey(const Key('btn-submit-suggest-category')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    '2. ValidationFailure keyed by "displayName" (alias) also maps inline',
    (tester) async {
      const serverMsg = 'Некоректна назва';
      when(
        () => repo.requestCategory(
          name: any(named: 'name'),
          displayName: any(named: 'displayName'),
          initialServiceName: any(named: 'initialServiceName'),
        ),
      ).thenThrow(
        const ValidationFailure(
          fieldErrors: <String, String>{'displayName': serverMsg},
        ),
      );

      await _openDialog(tester, repo);
      await _enterValidName(tester);
      await _submit(tester);

      _expectInlineNameError(tester, serverMsg);
      expect(find.byType(VelvetSnack), findsNothing);
    },
  );

  testWidgets(
    '3. editing the name after a server error clears the inline error',
    (tester) async {
      const serverMsg = 'Назва вже зайнята';
      when(
        () => repo.requestCategory(
          name: any(named: 'name'),
          displayName: any(named: 'displayName'),
          initialServiceName: any(named: 'initialServiceName'),
        ),
      ).thenThrow(
        const ValidationFailure(
          fieldErrors: <String, String>{'name': serverMsg},
        ),
      );

      await _openDialog(tester, repo);
      await _enterValidName(tester);
      await _submit(tester);
      _expectInlineNameError(tester, serverMsg);

      // Edit the field — the stale server error must clear immediately.
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('field-category-request-name')),
          matching: find.byType(TextField),
        ),
        'Манікюр гель',
      );
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(CategoryRequestDialog),
          matching: find.text(serverMsg),
        ),
        findsNothing,
        reason: 'Editing the name must clear the stale inline server error.',
      );
    },
  );

  testWidgets(
    '4. a non-validation failure (CategoryAlreadyExists) shows a VelvetSnack, '
    'not an inline name error',
    (tester) async {
      when(
        () => repo.requestCategory(
          name: any(named: 'name'),
          displayName: any(named: 'displayName'),
          initialServiceName: any(named: 'initialServiceName'),
        ),
      ).thenThrow(const CategoryAlreadyExistsFailure());

      await _openDialog(tester, repo);

      final l10n = AppLocalizations.of(
        tester.element(find.byType(CategoryRequestDialog)),
      );

      await _enterValidName(tester);
      await _submit(tester);

      // Generic failure → VelvetSnack with the failure's userMessage.
      expectVelvetSnack(
        l10n.categoryRequestErrExists,
        variant: VelvetSnackVariant.error,
      );
      // No inline error under the name field for a non-field failure.
      expect(
        find.descendant(
          of: find.byKey(const Key('field-category-request-name')),
          matching: find.text(l10n.categoryRequestErrExists),
        ),
        findsNothing,
      );
      await pumpPastVelvetSnack(tester);
    },
  );

  testWidgets(
    '5. (Change 3) initial-service field left empty → requestCategory called '
    'with initialServiceName == null; field is optional (no inline error)',
    (tester) async {
      when(
        () => repo.requestCategory(
          name: any(named: 'name'),
          displayName: any(named: 'displayName'),
          initialServiceName: any(named: 'initialServiceName'),
        ),
      ).thenAnswer((_) async {});

      await _openDialog(tester, repo);
      await _enterValidName(tester);
      // Initial-service field deliberately left empty.
      await _submit(tester);

      final captured = verify(
        () => repo.requestCategory(
          name: any(named: 'name'),
          displayName: any(named: 'displayName'),
          initialServiceName: captureAny(named: 'initialServiceName'),
        ),
      ).captured;
      expect(
        captured.single,
        isNull,
        reason: 'an empty optional initial-service must be forwarded as null',
      );

      // Optional field: submitting blank must NOT pop a required-style error and
      // must succeed (dialog popped).
      expect(find.byType(CategoryRequestDialog), findsNothing);
    },
  );

  testWidgets(
    '6. (Change 3) initial-service filled → the TRIMMED value is forwarded',
    (tester) async {
      when(
        () => repo.requestCategory(
          name: any(named: 'name'),
          displayName: any(named: 'displayName'),
          initialServiceName: any(named: 'initialServiceName'),
        ),
      ).thenAnswer((_) async {});

      await _openDialog(tester, repo);
      await _enterValidName(tester);
      // Surrounding whitespace must be trimmed before forwarding.
      await _enterInitialService(tester, '  Ламінування вій  ');
      await _submit(tester);

      final captured = verify(
        () => repo.requestCategory(
          name: any(named: 'name'),
          displayName: any(named: 'displayName'),
          initialServiceName: captureAny(named: 'initialServiceName'),
        ),
      ).captured;
      expect(captured.single, 'Ламінування вій');

      expect(find.byType(CategoryRequestDialog), findsNothing);
    },
  );

  // ---------------------------------------------------------------------------
  // Keyboard-inset layout guard (Change 2 regression)
  //
  // The bug: CategoryRequestDialog.build() read MediaQuery.viewInsets.bottom and
  // added it to both Dialog.insetPadding.bottom AND a ConstrainedBox.maxHeight
  // term.  Flutter's Dialog widget ALREADY applies MediaQuery.viewInsetsOf to its
  // outer AnimatedPadding (effectivePadding = viewInsetsOf + insetPadding).
  // Double-counting caused the outer AnimatedPadding.padding.bottom to grow by
  // 2 × viewInsets instead of 1 ×, pushing the dialog to the top of the screen.
  //
  // The fix: insetPadding and BoxConstraints are now const — no manual viewInsets
  // arithmetic.  Dialog applies the inset exactly once.
  //
  // Why the previous rect-vs-visible-fold assertion did NOT catch this:
  //   Dialog.build() wraps its child in MediaQuery.removeViewInsets, so the
  //   CategoryRequestDialog.build() context always reads viewInsets = 0 in the
  //   widget test environment, making old and new code produce the same CTA rect.
  //
  // Genuine regression test: assert the Dialog's outer AnimatedPadding.padding
  // .bottom equals viewInsets + VelvetSpacing.xl (= 300 + 32 = 332 with a 300-px
  // keyboard), NOT 2*viewInsets + xl (= 632, the double-count).
  // ---------------------------------------------------------------------------

  testWidgets(
    '7a. (Change 2 — genuine regression) with a 300 px keyboard inset the '
    'Dialog outer padding.bottom == viewInsets + xl (single application)',
    (tester) async {
      // No repository stub needed — the test does not submit.
      const double kSimulatedKeyboard = 300.0;
      const double kXl = 32.0; // VelvetSpacing.xl

      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      tester.view.viewInsets = const FakeViewPadding(
        bottom: kSimulatedKeyboard,
      );
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);

      await _openDialog(tester, repo);

      // The Dialog widget wraps its content in an AnimatedPadding whose
      // padding = MediaQuery.viewInsetsOf(context) + insetPadding.
      // With the fix:   padding.bottom = 300 + 32 = 332  (one application)
      // With the bug:   padding.bottom = 300 + 300 + 32 = 632  (double-count)
      //
      // We read the AnimatedPadding that the Dialog route injects.  It is the
      // first AnimatedPadding found inside the dialog route overlay (there are
      // no AnimatedPaddings in the trigger Scaffold).
      final animPaddings = tester
          .widgetList<AnimatedPadding>(find.byType(AnimatedPadding))
          .toList();
      expect(
        animPaddings,
        isNotEmpty,
        reason: 'Dialog must produce at least one AnimatedPadding',
      );
      // The Dialog's AnimatedPadding is the one whose bottom padding reflects the
      // keyboard.  Find it as the widget with the largest bottom padding value
      // among all AnimatedPaddings (the double-count would produce 632 > 332).
      final double maxBottom = animPaddings
          .map((ap) => (ap.padding as EdgeInsets).bottom)
          .reduce((a, b) => a > b ? a : b);

      const double expectedBottom = kSimulatedKeyboard + kXl; // 332.0
      const double doubleCountedBottom =
          kSimulatedKeyboard + kSimulatedKeyboard + kXl; // 632.0

      expect(
        maxBottom,
        closeTo(expectedBottom, 1.0),
        reason:
            'Dialog outer padding.bottom must be viewInsets + xl ($expectedBottom), '
            'not 2*viewInsets + xl ($doubleCountedBottom — the double-count bug). '
            'Got $maxBottom.',
      );
    },
  );

  testWidgets('7b. (Change 2 — baseline) with no keyboard the Dialog outer '
      'padding.bottom == xl only (no phantom inset term)', (tester) async {
    const double kXl = 32.0; // VelvetSpacing.xl

    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    // No viewInsets set — keyboard is absent.
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openDialog(tester, repo);

    final animPaddings = tester
        .widgetList<AnimatedPadding>(find.byType(AnimatedPadding))
        .toList();
    expect(animPaddings, isNotEmpty);
    final double maxBottom = animPaddings
        .map((ap) => (ap.padding as EdgeInsets).bottom)
        .reduce((a, b) => a > b ? a : b);

    expect(
      maxBottom,
      closeTo(kXl, 1.0),
      reason:
          'With no keyboard the Dialog outer padding.bottom must equal xl '
          '($kXl) only — no extra inset term must be added.',
    );
  });
}
