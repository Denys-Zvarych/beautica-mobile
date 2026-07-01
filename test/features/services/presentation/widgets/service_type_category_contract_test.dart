// Phase 16.6 — CONTRACT guard: the `categoryName` the form passes down to
// `serviceTypesProvider(categoryName)` MUST be the exact
// `ServiceCategoryOption.name` slug returned by `approvedCategoriesProvider`.
//
// Why this is its own test (the debugger called it out): there are two category
// systems in the codebase (platform_categories vs the orphan System-A
// service_categories). If the form ever sent the human displayName, a
// localised value, or a System-A id instead of the platform wire slug, the
// second-level service-type lookup would silently resolve nothing — the picker
// would look "empty" with no error, masking a contract drift. This test locks
// the slug contract end-to-end through the rendered category dropdown:
//
//   CONTRACT-SLUG. selecting the category whose ServiceCategoryOption.name is
//                  'MANICURE' (displayName 'Манікюр') drives
//                  serviceTypesProvider with EXACTLY 'MANICURE' — never the
//                  displayName and never a transformed value.
//
// Mechanism: the serviceTypesProvider override is a closure that RECORDS the
// `categoryName` family arg it is invoked with; the category options come from
// the mocked approvedCategoriesProvider, so the asserted value is provably the
// same `.name` the provider returned (not a literal hard-coded twice).
//
// Isolation: fresh ProviderScope per pump; serviceRepositoryProvider mocked;
// widgets found by Key (M2).

import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service_input.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/domain/service_type_option.dart';
import 'package:beautica_mobile/features/services/presentation/service_types_provider.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_form.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'select_dropdown_test_helpers.dart';

class _MockServiceRepository extends Mock implements ServiceRepository {}

// The single category the test selects. The displayName ('Манікюр') is what the
// user reads and searches; the name ('MANICURE') is the platform wire slug that
// MUST flow to the service-type lookup. Keeping them deliberately different is
// what makes the assertion meaningful.
const _category = ServiceCategoryOption(
  name: 'MANICURE',
  displayName: 'Манікюр',
);

void main() {
  late _MockServiceRepository repo;

  setUp(() {
    repo = _MockServiceRepository();
  });

  testWidgets(
    'CONTRACT-SLUG. selecting a category drives serviceTypesProvider with the '
    'EXACT ServiceCategoryOption.name slug (not the displayName)',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Records every categoryName the provider family is invoked with.
      final List<String> requestedCategoryNames = <String>[];

      Future<void> neverSubmit(MasterServiceCreate _) async {}

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            serviceRepositoryProvider.overrideWithValue(repo),
            approvedCategoriesProvider.overrideWith(
              (ref) async => const <ServiceCategoryOption>[_category],
            ),
            serviceTypesProvider.overrideWith((ref, String categoryName) async {
              requestedCategoryNames.add(categoryName);
              return const <ServiceTypeOption>[];
            }),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('uk'),
            home: Scaffold(
              body: SingleChildScrollView(
                child: ServiceForm(onSubmit: neverSubmit),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Drive the rendered category dropdown: open menu → tap the MANICURE row.
      await selectCategoryOption(tester, _category.name);
      await tester.pumpAndSettle();

      // The lookup fired with EXACTLY the platform wire slug returned by the
      // approved-categories provider — never the displayName, never a transform.
      expect(requestedCategoryNames, isNotEmpty);
      expect(requestedCategoryNames, contains(_category.name));
      expect(
        requestedCategoryNames,
        isNot(contains(_category.displayName)),
        reason:
            'the service-type lookup must key off the wire slug "MANICURE", '
            'not the localised displayName "Манікюр" (System-A drift guard)',
      );
    },
  );
}
