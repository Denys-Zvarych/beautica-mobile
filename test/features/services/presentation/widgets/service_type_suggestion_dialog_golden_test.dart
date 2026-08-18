// Phase 16.6 — golden tests for ServiceTypeSuggestionDialog.
//
// Pixel-level regression guards for the suggest-a-service-type dialog surface
// (VelvetTouch neumorphic). golden_toolkit was removed from the repo
// (2026-05-26, discontinued on pub.dev), so these use the framework's built-in
// `matchesGoldenFile` at a fixed phone viewport — identical to the schedule
// golden suite. Three states capture the visual contract (the description field
// was REMOVED — Change 1 — so the surface is title → subtitle → name well →
// footer CTA, no description well):
//   • DEFAULT     — pristine dialog: title, subtitle, name well, footer CTA.
//   • NAME-ERROR  — submit-with-empty-name → the inline name error row renders.
//   • SUBMITTING  — an in-flight submit → the CTA shows its loading affordance
//                   and the name field is disabled.
//
// Regenerate intentionally after a design change with:
//   flutter test --update-goldens test/features/services/presentation/widgets/service_type_suggestion_dialog_golden_test.dart
// then commit the updated PNGs.

import 'dart:async';

import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_type_suggestion_dialog.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

class _MockServiceRepository extends Mock implements ServiceRepository {}

const _categorySlug = 'EYELASH';

/// Pumps just the dialog widget (no route push) at a fixed phone viewport so the
/// golden is deterministic. The repository is mocked per [repo].
Future<void> _pumpDialog(
  WidgetTester tester,
  _MockServiceRepository repo,
) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      retry: beauticaProviderRetry,
      overrides: [serviceRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(
        debugShowCheckedModeBanner: false,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('uk'),
        home: Scaffold(
          body: Center(
            child: ServiceTypeSuggestionDialog(categoryName: _categorySlug),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder get _nameField => find.descendant(
  of: find.byKey(const Key('field-service-type-suggest-name')),
  matching: find.byType(TextField),
);

void main() {
  late _MockServiceRepository repo;

  setUp(() => repo = _MockServiceRepository());

  testWidgets('GOLDEN. default (pristine) dialog', (tester) async {
    await _pumpDialog(tester, repo);

    await expectLater(
      find.byType(ServiceTypeSuggestionDialog),
      matchesGoldenFile('goldens/service_type_suggest_default.png'),
    );
  });

  testWidgets('GOLDEN. name-error state (submit with empty name)', (
    tester,
  ) async {
    await _pumpDialog(tester, repo);

    // Submit with an empty name → the inline name error row renders.
    await tester.tap(find.byKey(const Key('btn-submit-suggest-service-type')));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(ServiceTypeSuggestionDialog),
      matchesGoldenFile('goldens/service_type_suggest_name_error.png'),
    );
  });

  testWidgets('GOLDEN. submitting state (CTA loading, fields disabled)', (
    tester,
  ) async {
    // A submit that never completes holds the dialog in the in-flight state so
    // the CTA loading affordance and disabled wells are captured.
    final gate = Completer<void>();
    when(
      () => repo.suggestServiceType(
        categoryName: any(named: 'categoryName'),
        name: any(named: 'name'),
        description: any(named: 'description'),
      ),
    ).thenAnswer((_) => gate.future);

    await _pumpDialog(tester, repo);

    await tester.enterText(_nameField, 'Ламінування вій');
    await tester.pump();
    await tester.tap(find.byKey(const Key('btn-submit-suggest-service-type')));
    await tester
        .pump(); // enter the submitting state (do not settle — it hangs)
    await tester.pump(const Duration(milliseconds: 16));

    await expectLater(
      find.byType(ServiceTypeSuggestionDialog),
      matchesGoldenFile('goldens/service_type_suggest_submitting.png'),
    );

    gate.complete(); // release the pending future so teardown is clean.
    await tester.pumpAndSettle();
  });
}
