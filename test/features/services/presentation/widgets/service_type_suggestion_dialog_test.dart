// Phase 16.6 — widget tests for ServiceTypeSuggestionDialog.
//
// The dialog has a SINGLE input — name (required, Key 'field-service-type-suggest-
// name'). The description field was REMOVED (Change 1); `_handleSubmit` now always
// forwards `description: null`. It forwards the read-only `categoryName` SLUG
// context (supplied by the caller, never user-entered) to
// [ServiceRepository.suggestServiceType].
//
// On success it pops `true` (the caller shows the success SnackBar). A 400
// ValidationFailure carrying a `name` field error maps to the inline name-field
// error and the dialog STAYS OPEN; a 429 throttle surfaces a SnackBar within the
// dialog and STAYS OPEN.
//
// Finders use Key lookups (M2). The repository is mocked (Isolation); no real
// network. The slug-arg assertion is the M4 guard: the dialog must forward the
// passed-in SLUG, never a UUID.
//
// Covered scenarios:
//   1. empty name → inline serviceTypeSuggestNameError; suggestServiceType NOT
//      called.
//   2. valid submit → calls suggestServiceType with the passed categoryName SLUG
//      + entered name + description: null (the field is gone); success pops true.
//   3. (Change 1 guard) the removed description field is ABSENT from the tree so
//      it cannot silently return.
//   4. 400 ValidationFailure{name} → inline name error, dialog stays open.
//   5. 429 CategoryRequestThrottledFailure → throttle SnackBar, dialog stays
//      open.
//   6a. (Change 2 — genuine regression) with a 300 px keyboard the Dialog
//       outer AnimatedPadding.padding.bottom == viewInsets + xl (332), NOT
//       2*viewInsets + xl (632 — the double-count bug).
//   6b. (Change 2 — baseline) with no keyboard, padding.bottom == xl (32) only.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_type_suggestion_dialog.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class _MockServiceRepository extends Mock implements ServiceRepository {}

// The SLUG context the picker passes in (a System-B category slug). It must be
// forwarded verbatim — never replaced with a UUID (M4).
const _categorySlug = 'EYELASH';

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

// A GoRouter is needed because the dialog pops via dismissOverlay(context, true)
// on success. Failure paths do not pop, but the router must exist so the tree
// resolves identically to production.
GoRouter _router() => GoRouter(
  initialLocation: '/',
  routes: <RouteBase>[
    GoRoute(
      path: '/',
      builder: (context, state) => Scaffold(
        body: Builder(
          builder: (ctx) => ElevatedButton(
            key: const Key('trigger'),
            onPressed: () => showServiceTypeSuggestionDialog(
              ctx,
              categoryName: _categorySlug,
            ),
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

Finder get _nameField => find.descendant(
  of: find.byKey(const Key('field-service-type-suggest-name')),
  matching: find.byType(TextField),
);

Future<void> _enterName(WidgetTester tester, String value) async {
  await tester.enterText(_nameField, value);
  await tester.pump();
}

Future<void> _submit(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('btn-submit-suggest-service-type')));
  await tester.pumpAndSettle();
}

AppLocalizations _l10n(WidgetTester tester) => AppLocalizations.of(
  tester.element(find.byType(ServiceTypeSuggestionDialog)),
);

/// Asserts [message] renders inline inside the dialog (the name field's error
/// row) and NOT inside a SnackBar.
void _expectInlineNameError(WidgetTester tester, String message) {
  expect(
    find.descendant(
      of: find.byType(ServiceTypeSuggestionDialog),
      matching: find.text(message),
    ),
    findsOneWidget,
    reason: 'Inline name error must render inside the dialog.',
  );
  expect(
    find.descendant(of: find.byType(SnackBar), matching: find.text(message)),
    findsNothing,
    reason: 'A mapped field error must not also appear in a SnackBar.',
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _MockServiceRepository repo;

  setUp(() => repo = _MockServiceRepository());

  testWidgets('1. empty name → inline serviceTypeSuggestNameError; '
      'suggestServiceType is NOT called', (tester) async {
    await _openDialog(tester, repo);

    final l10n = _l10n(tester);

    // Submit with an empty name field.
    await _submit(tester);

    _expectInlineNameError(tester, l10n.serviceTypeSuggestNameError);
    // The repository must never be touched on a client-invalid submit.
    verifyNever(
      () => repo.suggestServiceType(
        categoryName: any(named: 'categoryName'),
        name: any(named: 'name'),
        description: any(named: 'description'),
      ),
    );
    // Dialog stays open.
    expect(
      find.byKey(const Key('btn-submit-suggest-service-type')),
      findsOneWidget,
    );
  });

  testWidgets(
    '2. valid submit → calls suggestServiceType with the passed categoryName '
    'SLUG + name + description: null (field removed); success pops true',
    (tester) async {
      when(
        () => repo.suggestServiceType(
          categoryName: any(named: 'categoryName'),
          name: any(named: 'name'),
          description: any(named: 'description'),
        ),
      ).thenAnswer((_) async {});

      await _openDialog(tester, repo);
      await _enterName(tester, 'Ламінування вій');
      await _submit(tester);

      // M4: the SLUG is forwarded verbatim (never a UUID), with the typed name.
      // Change 1: the description field is gone — the dialog always passes null.
      final captured = verify(
        () => repo.suggestServiceType(
          categoryName: captureAny(named: 'categoryName'),
          name: captureAny(named: 'name'),
          description: captureAny(named: 'description'),
        ),
      ).captured;
      expect(captured[0], _categorySlug);
      expect(
        captured[0],
        isNot(matches(RegExp(r'^[0-9a-fA-F-]{36}$'))),
        reason: 'categoryName must be a slug, never a UUID',
      );
      expect(captured[1], 'Ламінування вій');
      expect(
        captured[2],
        isNull,
        reason: 'the removed description field must forward null',
      );

      // Success → the dialog popped (no longer in the tree).
      expect(find.byType(ServiceTypeSuggestionDialog), findsNothing);
    },
  );

  testWidgets(
    '3. (Change 1 guard) the removed description field is ABSENT — it cannot '
    'silently return',
    (tester) async {
      await _openDialog(tester, repo);

      // The description input was removed from the dialog. Guarding its key here
      // makes a silent reintroduction fail loudly.
      expect(
        find.byKey(const Key('field-service-type-suggest-description')),
        findsNothing,
        reason:
            'the description field was removed (Change 1) and must stay gone',
      );
      // Only the name field remains.
      expect(
        find.byKey(const Key('field-service-type-suggest-name')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    '4. 400 ValidationFailure{name} → inline name error, dialog stays open',
    (tester) async {
      const serverMsg = 'Така послуга вже існує';
      when(
        () => repo.suggestServiceType(
          categoryName: any(named: 'categoryName'),
          name: any(named: 'name'),
          description: any(named: 'description'),
        ),
      ).thenThrow(
        const ValidationFailure(
          fieldErrors: <String, String>{'name': serverMsg},
        ),
      );

      await _openDialog(tester, repo);
      await _enterName(tester, 'Дублікат');
      await _submit(tester);

      _expectInlineNameError(tester, serverMsg);
      // No SnackBar — the field error was mapped inline.
      expect(find.byType(SnackBar), findsNothing);
      // Dialog stays open.
      expect(find.byType(ServiceTypeSuggestionDialog), findsOneWidget);
    },
  );

  testWidgets('5. 429 CategoryRequestThrottledFailure → throttle SnackBar, '
      'dialog stays open', (tester) async {
    when(
      () => repo.suggestServiceType(
        categoryName: any(named: 'categoryName'),
        name: any(named: 'name'),
        description: any(named: 'description'),
      ),
    ).thenThrow(const CategoryRequestThrottledFailure());

    await _openDialog(tester, repo);
    final l10n = _l10n(tester);

    await _enterName(tester, 'Забагато запитів');
    await _submit(tester);

    // A non-field failure surfaces the throttle copy in a SnackBar.
    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.text(l10n.categoryRequestErrThrottled),
      ),
      findsOneWidget,
    );
    // No inline name error for a non-field failure.
    expect(
      find.descendant(
        of: find.byKey(const Key('field-service-type-suggest-name')),
        matching: find.text(l10n.categoryRequestErrThrottled),
      ),
      findsNothing,
    );
    // Dialog stays open so the user can retry.
    expect(find.byType(ServiceTypeSuggestionDialog), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // Keyboard-inset layout guard (Change 2 regression)
  //
  // The bug: ServiceTypeSuggestionDialog.build() read MediaQuery.viewInsets
  // .bottom and added it to both Dialog.insetPadding.bottom AND a
  // ConstrainedBox.maxHeight term.  Flutter's Dialog ALREADY applies
  // MediaQuery.viewInsetsOf to its outer AnimatedPadding, so the keyboard
  // height was double-counted — the dialog shifted to the top of the screen.
  //
  // The fix: insetPadding and BoxConstraints are now const — no manual
  // viewInsets arithmetic.  Dialog applies the inset exactly once.
  //
  // Why the previous rect-vs-visible-fold assertion did NOT catch this:
  //   Dialog.build() wraps its child in MediaQuery.removeViewInsets, so
  //   ServiceTypeSuggestionDialog.build() always reads viewInsets = 0 in
  //   the widget test environment.  The CTA rect was identical in both old
  //   and new code, so the assertion passed trivially against the bug.
  //
  // Genuine regression test: assert the Dialog's outer AnimatedPadding
  // .padding.bottom equals viewInsets + VelvetSpacing.xl (single application),
  // not 2*viewInsets + xl (double-count).
  // ---------------------------------------------------------------------------

  testWidgets(
    '6a. (Change 2 — genuine regression) with a 300 px keyboard inset the '
    'Dialog outer padding.bottom == viewInsets + xl (single application)',
    (tester) async {
      const double kSimulatedKeyboard = 300.0;
      const double kXl = 32.0; // VelvetSpacing.xl

      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      tester.view.viewInsets = const FakeViewPadding(bottom: kSimulatedKeyboard);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);

      await _openDialog(tester, repo);

      // The Dialog widget wraps its content in an AnimatedPadding whose
      // padding = MediaQuery.viewInsetsOf(context) + insetPadding.
      // With the fix:   padding.bottom = 300 + 32 = 332  (one application)
      // With the bug:   padding.bottom = 300 + 300 + 32 = 632  (double-count)
      final animPaddings = tester
          .widgetList<AnimatedPadding>(find.byType(AnimatedPadding))
          .toList();
      expect(
        animPaddings,
        isNotEmpty,
        reason: 'Dialog must produce at least one AnimatedPadding',
      );
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

  testWidgets(
    '6b. (Change 2 — baseline) with no keyboard the Dialog outer '
    'padding.bottom == xl only (no phantom inset term)',
    (tester) async {
      const double kXl = 32.0; // VelvetSpacing.xl

      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
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
    },
  );
}
