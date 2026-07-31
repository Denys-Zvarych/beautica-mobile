// Phase 16.6 — golden tests for CategoryRequestDialog.
//
// Pixel-level regression guard for the suggest-a-category dialog surface
// (VelvetTouch neumorphic). golden_toolkit was removed from the repo
// (2026-05-26, discontinued on pub.dev), so this uses the framework's built-in
// `matchesGoldenFile` at a fixed phone viewport — identical to the
// service-type-suggestion golden suite.
//
// The dialog now carries the OPTIONAL initial-service field (Change 3): the
// surface is title → subtitle → name well → initial-service well → footer CTA.
// This golden captures the field FILLED so a regression that drops or restyles
// the optional well is caught:
//   • FILLED — name + initial-service both populated, footer CTA.
//
// Regenerate intentionally after a design change with:
//   flutter test --update-goldens test/features/services/presentation/widgets/category_request_dialog_golden_test.dart
// then commit the updated PNGs.

import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/category_request_dialog.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

class _MockServiceRepository extends Mock implements ServiceRepository {}

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
        home: Scaffold(body: Center(child: CategoryRequestDialog())),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _field(String key) =>
    find.descendant(of: find.byKey(Key(key)), matching: find.byType(TextField));

void main() {
  late _MockServiceRepository repo;

  setUp(() => repo = _MockServiceRepository());

  testWidgets('GOLDEN. initial-service field filled (Change 3)', (
    tester,
  ) async {
    await _pumpDialog(tester, repo);

    await tester.enterText(
      _field('field-category-request-name'),
      'Нарощування вій',
    );
    await tester.enterText(
      _field('field-category-request-initial-service-name'),
      'Ламінування вій',
    );
    await tester.pump();

    await expectLater(
      find.byType(CategoryRequestDialog),
      matchesGoldenFile('goldens/category_request_initial_service_filled.png'),
    );
  });
}
