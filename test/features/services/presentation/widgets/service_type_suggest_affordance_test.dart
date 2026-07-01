// Phase 16.6 — widget tests for the suggest-a-service-type AFFORDANCE on the
// service form's second-level picker (_ServiceTypeDropdown.menuFooter).
//
// The footer chip (Key 'chip-service-type-suggest') is the escape hatch from the
// service-type menu into ServiceTypeSuggestionDialog. This file drives the real
// rendered picker (through ServiceForm, exactly like service_type_chips_test.dart)
// rather than the dialog in isolation, because the affordance + success-SnackBar
// wiring is the user-facing surface:
//   - tapping the footer chip closes the menu and opens the dialog;
//   - a successful suggestion raises the serviceTypeSuggestSuccess SnackBar on
//     the form's messenger (NOT the dialog's transient context);
//   - a suggestion does NOT appear in the picker option list (it is queued for
//     review, never optimistically inserted).
//
// Isolation: fresh ProviderScope per pump; serviceRepositoryProvider mocked so
// approvedCategoriesProvider + suggestServiceType resolve without HTTP;
// serviceTypesProvider overridden per-test. Widgets found by Key (M2).

import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/domain/service_type_option.dart';
import 'package:beautica_mobile/features/services/presentation/service_types_provider.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_form.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_type_suggestion_dialog.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'select_dropdown_test_helpers.dart';

class _MockServiceRepository extends Mock implements ServiceRepository {}

ServiceTypeOption _type(String id, String nameUk) => ServiceTypeOption(
  id: id,
  slug: id.toUpperCase(),
  nameUk: nameUk,
  categoryName: 'EYELASH',
);

const _categories = <ServiceCategoryOption>[
  ServiceCategoryOption(name: 'EYELASH', displayName: 'Вії'),
];

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(ServiceForm)));

void main() {
  late _MockServiceRepository repo;

  setUp(() {
    repo = _MockServiceRepository();
  });

  Future<void> pumpForm(
    WidgetTester tester, {
    List<ServiceTypeOption> serviceTypes = const <ServiceTypeOption>[],
  }) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serviceRepositoryProvider.overrideWithValue(repo),
          approvedCategoriesProvider.overrideWith((ref) async => _categories),
          serviceTypesProvider.overrideWith(
            (ref, String categoryName) async => serviceTypes,
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('uk'),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ServiceForm(onSubmit: (_) async {}),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'AFFORDANCE. tapping chip-service-type-suggest in the menu footer opens '
    'ServiceTypeSuggestionDialog',
    (tester) async {
      await pumpForm(tester);

      await selectCategoryOption(tester, 'EYELASH');
      await tester.pumpAndSettle();

      await openServiceTypeMenu(tester);
      expect(
        find.byKey(const Key('chip-service-type-suggest')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('chip-service-type-suggest')));
      await tester.pumpAndSettle();

      expect(find.byType(ServiceTypeSuggestionDialog), findsOneWidget);
    },
  );

  testWidgets(
    'SUCCESS. submitting a suggestion via the footer chip raises the '
    'serviceTypeSuggestSuccess SnackBar; the name does NOT enter the picker list',
    (tester) async {
      when(
        () => repo.suggestServiceType(
          categoryName: any(named: 'categoryName'),
          name: any(named: 'name'),
          description: any(named: 'description'),
        ),
      ).thenAnswer((_) async {});

      await pumpForm(
        tester,
        // One pre-existing approved option so we can prove the SUGGESTED name is
        // not appended to the list after a successful suggestion.
        serviceTypes: <ServiceTypeOption>[_type('t1', 'Класичні вії')],
      );

      await selectCategoryOption(tester, 'EYELASH');
      await tester.pumpAndSettle();

      // Open the menu and enter the suggest dialog via the footer chip.
      await openServiceTypeMenu(tester);
      await tester.tap(find.byKey(const Key('chip-service-type-suggest')));
      await tester.pumpAndSettle();

      // Fill + submit the dialog.
      const suggested = 'Ламінування вій';
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('field-service-type-suggest-name')),
          matching: find.byType(TextField),
        ),
        suggested,
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('btn-submit-suggest-service-type')),
      );
      await tester.pumpAndSettle();

      final l10n = _l10n(tester);

      // The repository was called and the dialog popped.
      verify(
        () => repo.suggestServiceType(
          categoryName: 'EYELASH',
          name: suggested,
          description: any(named: 'description'),
        ),
      ).called(1);
      expect(find.byType(ServiceTypeSuggestionDialog), findsNothing);

      // Success SnackBar on the form's messenger.
      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(l10n.serviceTypeSuggestSuccess),
        ),
        findsOneWidget,
      );

      // Re-open the menu → the suggested name is NOT an option (queued for
      // review, never optimistically inserted). The original option remains.
      await openServiceTypeMenu(tester);
      expect(find.byKey(const Key('chip-service-type-t1')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('select-service-type-field-wrapper')),
          matching: find.text(suggested),
        ),
        findsNothing,
        reason: 'a queued suggestion must not appear in the picker option list',
      );
    },
  );
}
