// Widget tests for CategoryRequestDialog — inline server-error mapping.
//
// The dialog's only input is the display-name field (Key
// 'field-category-request-name'). A backend ValidationFailure carrying a
// `name` / `displayName` field error must map onto that field's inline
// errorText (_serverNameError) rather than collapsing to a transient SnackBar.
// All other failures (and a ValidationFailure with no name/displayName key)
// still surface a SnackBar.
//
// Finders use Key lookups (M2). The repository is mocked; no real network.
//
// Covered scenarios:
//   1. ValidationFailure{name}        → inline error under the name field,
//                                       NO snackbar, dialog stays open.
//   2. ValidationFailure{displayName} → inline error (alias key) under the field.
//   3. Editing the name after a server error clears the inline error.
//   4. Non-validation failure (CategoryAlreadyExists) → SnackBar, no inline.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/category_request_dialog.dart';
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

Future<void> _submit(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('btn-submit-suggest-category')));
  await tester.pumpAndSettle();
}

/// Asserts [message] is rendered inline inside the dialog (the _DialogField
/// error row sits next to the keyed NeumorphicInset, inside CategoryRequestDialog)
/// and is NOT a SnackBar.
void _expectInlineNameError(WidgetTester tester, String message) {
  expect(
    find.descendant(
      of: find.byType(CategoryRequestDialog),
      matching: find.text(message),
    ),
    findsOneWidget,
    reason: 'Server error must render inline inside the dialog name field row.',
  );
  // The same message must NOT be inside a SnackBar — it is mapped inline.
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

  testWidgets(
    '1. ValidationFailure keyed by "name" maps to the inline name error '
    '(no snackbar, dialog stays open)',
    (tester) async {
      const serverMsg = 'Назва вже зайнята';
      when(
        () => repo.requestCategory(
          name: any(named: 'name'),
          displayName: any(named: 'displayName'),
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
      // No SnackBar — the error was mapped inline.
      expect(find.byType(SnackBar), findsNothing);
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
      expect(find.byType(SnackBar), findsNothing);
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
    '4. a non-validation failure (CategoryAlreadyExists) shows a SnackBar, '
    'not an inline name error',
    (tester) async {
      when(
        () => repo.requestCategory(
          name: any(named: 'name'),
          displayName: any(named: 'displayName'),
        ),
      ).thenThrow(const CategoryAlreadyExistsFailure());

      await _openDialog(tester, repo);

      final l10n = AppLocalizations.of(
        tester.element(find.byType(CategoryRequestDialog)),
      );

      await _enterValidName(tester);
      await _submit(tester);

      // Generic failure → SnackBar with the failure's userMessage.
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text(l10n.categoryRequestErrExists), findsOneWidget);
      // No inline error under the name field for a non-field failure.
      expect(
        find.descendant(
          of: find.byKey(const Key('field-category-request-name')),
          matching: find.text(l10n.categoryRequestErrExists),
        ),
        findsNothing,
      );
    },
  );
}
