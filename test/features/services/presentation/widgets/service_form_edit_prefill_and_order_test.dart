// Items 2 + 4 regression — service-form edit prefill, optional name, field
// order (2026-06-08).
//
// Item 2 (edit prefill): given a service with serviceTypeId + serviceTypeNameUk,
//   the form pre-selects the service type. The closed service-type field shows
//   the loaded name IMMEDIATELY via the fallback label (before the option list
//   resolves), and continues to show it after the options load and the id match
//   resolves. Guards the original "service type empty on edit" bug.
//
// Item 4 (optional name + field order):
//   • A blank name field submits MasterServiceCreate.name == '' — NOT
//     substituted with the service-type name (the _effectiveName stopgap was
//     removed; the backend defaults a blank name).
//   • A typed name submits the trimmed value.
//   • Field order is category → service type → Name (keyed fields ordered
//     top-to-bottom by vertical position).
//
// Isolation: fresh ProviderScope per pump; serviceRepositoryProvider mocked so
// approvedCategoriesProvider resolves without real HTTP; serviceTypesProvider
// overridden per test (empty list to prove the fallback path; a matching option
// to prove the id-match path). Fields located by Key (M2).

import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
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

// ---------------------------------------------------------------------------
// Mocks + fakes
// ---------------------------------------------------------------------------

class _MockServiceRepository extends Mock implements ServiceRepository {}

class _FakeMasterServiceCreate extends Fake implements MasterServiceCreate {}

// A FIXED edit-mode service tagged with a MANICURE category + a service type.
const _editService = MasterService(
  id: 'svc-edit-1',
  serviceDefId: 'def-edit-1',
  name: 'Мій власний манікюр',
  category: 'MANICURE',
  serviceTypeId: 'type-loaded',
  serviceTypeNameUk: 'Класичний манікюр',
  durationMinutes: 60,
  priceType: ServicePriceType.fixed,
  priceMin: 500,
  priceDisplay: '500 ₴',
);

// ---------------------------------------------------------------------------
// Finders (by Key — M2)
// ---------------------------------------------------------------------------

final _nameField = find.descendant(
  of: find.byKey(const Key('field-service-name')),
  matching: find.byType(TextField),
);
final _durationField = find.descendant(
  of: find.byKey(const Key('field-service-duration')),
  matching: find.byType(TextField),
);

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(ServiceForm)));

void main() {
  setUpAll(() => registerFallbackValue(_FakeMasterServiceCreate()));

  late _MockServiceRepository repo;

  // approvedCategoriesProvider is overridden directly below (it fetches via
  // categoryRequestApi, not the repo).
  const categories = <ServiceCategoryOption>[
    ServiceCategoryOption(name: 'MANICURE', displayName: 'Манікюр'),
    ServiceCategoryOption(name: 'HAIRCUT', displayName: 'Стрижка'),
  ];

  setUp(() {
    repo = _MockServiceRepository();
  });

  /// Pumps a [ServiceForm] inside a fresh ProviderScope. [serviceTypes] feeds
  /// the second-level picker; [initial] seeds edit mode. The 1:1 tall viewport
  /// keeps the submit button hittable.
  Future<void> pumpForm(
    WidgetTester tester, {
    required Future<void> Function(MasterServiceCreate) onSubmit,
    MasterService? initial,
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
          approvedCategoriesProvider.overrideWith((ref) async => categories),
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
              child: ServiceForm(initial: initial, onSubmit: onSubmit),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> tapSubmit(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('btn-submit-service')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('btn-submit-service')));
    await tester.pump();
  }

  Future<void> neverSubmit(MasterServiceCreate _) async {}

  /// The closed service-type field's currently-shown label text.
  Finder serviceTypeFieldText(String text) => find.descendant(
    of: find.byKey(const Key('select-service-type-field')),
    matching: find.text(text),
  );

  // =========================================================================
  // Item 2 — edit prefill of the service type.
  // =========================================================================
  group('Item 2 — edit prefill of the service type', () {
    testWidgets(
      'E-FALLBACK. closed field shows the loaded type name immediately, '
      'BEFORE options resolve',
      (tester) async {
        // Empty option list → the dropdown cannot resolve an id match, so the
        // closed field must fall back to the loaded serviceTypeNameUk. This is
        // exactly the "edit form, options still loading" condition that used to
        // render an empty service-type field.
        await pumpForm(
          tester,
          onSubmit: neverSubmit,
          initial: _editService,
          serviceTypes: const <ServiceTypeOption>[],
        );
        await tester.pumpAndSettle();

        expect(
          serviceTypeFieldText('Класичний манікюр'),
          findsOneWidget,
          reason:
              'edit prefill: the loaded serviceTypeNameUk must label the '
              'closed field even before the option list resolves',
        );
      },
    );

    testWidgets(
      'E-IDMATCH. after options load, the field resolves the label from the '
      'matched option id',
      (tester) async {
        // The option list contains the loaded id. The dropdown resolves the
        // label from the matched option (proving the id round-trips, not just
        // the fallback). Use a label distinct from the fallback so we know the
        // matched-option branch is the one rendering.
        await pumpForm(
          tester,
          onSubmit: neverSubmit,
          initial: _editService,
          serviceTypes: const <ServiceTypeOption>[
            ServiceTypeOption(
              id: 'type-loaded',
              slug: 'CLASSIC_MANICURE',
              nameUk: 'Класичний манікюр (каталог)',
              categoryName: 'MANICURE',
            ),
          ],
        );
        await tester.pumpAndSettle();

        expect(
          serviceTypeFieldText('Класичний манікюр (каталог)'),
          findsOneWidget,
          reason:
              'the matched option label wins once the type list resolves the '
              'loaded serviceTypeId',
        );
      },
    );

    testWidgets(
      'E-SUBMIT. editing only the duration keeps the loaded serviceTypeId on '
      'the submitted payload',
      (tester) async {
        MasterServiceCreate? captured;
        await pumpForm(
          tester,
          onSubmit: (input) async => captured = input,
          initial: _editService,
          serviceTypes: const <ServiceTypeOption>[
            ServiceTypeOption(
              id: 'type-loaded',
              slug: 'CLASSIC_MANICURE',
              nameUk: 'Класичний манікюр',
              categoryName: 'MANICURE',
            ),
          ],
        );
        await tester.pumpAndSettle();

        // Change duration only; leave the pre-selected type untouched.
        await tester.enterText(_durationField, '75');
        await tapSubmit(tester);
        await tester.pumpAndSettle();

        expect(captured, isNotNull);
        expect(
          captured!.serviceTypeId,
          'type-loaded',
          reason:
              'the pre-selected service type must survive an unrelated edit '
              '(guards "type empty / dropped on edit")',
        );
      },
    );
  });

  // =========================================================================
  // Item 4 — optional name + field order.
  // =========================================================================
  group('Item 4 — optional name + field order', () {
    testWidgets(
      'N-BLANK. clearing the name on edit submits name == "" (NOT the type '
      'name)',
      (tester) async {
        MasterServiceCreate? captured;
        await pumpForm(
          tester,
          onSubmit: (input) async => captured = input,
          initial: _editService,
          serviceTypes: const <ServiceTypeOption>[
            ServiceTypeOption(
              id: 'type-loaded',
              slug: 'CLASSIC_MANICURE',
              nameUk: 'Класичний манікюр',
              categoryName: 'MANICURE',
            ),
          ],
        );
        await tester.pumpAndSettle();

        // Master clears the custom name entirely.
        await tester.enterText(_nameField, '');
        await tapSubmit(tester);
        await tester.pumpAndSettle();

        expect(captured, isNotNull);
        expect(
          captured!.name,
          '',
          reason:
              'a cleared name flows through as empty — the client must NOT '
              'substitute the service-type name (_effectiveName removed)',
        );
        expect(find.text(_l10n(tester).errNameRequired), findsNothing);
      },
    );

    testWidgets('N-TYPED. a typed name submits its trimmed value', (
      tester,
    ) async {
      MasterServiceCreate? captured;
      await pumpForm(
        tester,
        onSubmit: (input) async => captured = input,
        serviceTypes: const <ServiceTypeOption>[],
      );

      await tester.enterText(_durationField, '60');
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('pricing-fixed-amount')),
          matching: find.byType(TextField),
        ),
        '500',
      );
      await selectCategoryOption(tester, 'MANICURE');
      // Service type is mandatory on create — select one via the form State
      // (its name auto-fill is overwritten by the explicit name below).
      (tester.state(find.byType(ServiceForm)) as dynamic).onServiceTypeSelected(
        const ServiceTypeOption(
          id: 'stype-manicure',
          slug: 'MANICURE_A',
          nameUk: 'Класичний манікюр',
          categoryName: 'MANICURE',
        ),
      );
      await tester.pump();
      // Leading/trailing whitespace must be trimmed off the submitted name.
      await tester.enterText(_nameField, '  Спеціальний манікюр  ');
      await tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.name, 'Спеціальний манікюр');
    });

    testWidgets(
      'N-ORDER. fields are ordered category → service type → Name (top to '
      'bottom)',
      (tester) async {
        // Edit mode with a category already selected so the second-level
        // service-type dropdown is mounted between category and name.
        await pumpForm(
          tester,
          onSubmit: neverSubmit,
          initial: _editService,
          serviceTypes: const <ServiceTypeOption>[
            ServiceTypeOption(
              id: 'type-loaded',
              slug: 'CLASSIC_MANICURE',
              nameUk: 'Класичний манікюр',
              categoryName: 'MANICURE',
            ),
          ],
        );
        await tester.pumpAndSettle();

        final double categoryTop = tester
            .getTopLeft(find.byKey(const Key('select-category-field')))
            .dy;
        final double serviceTypeTop = tester
            .getTopLeft(find.byKey(const Key('select-service-type-field')))
            .dy;
        final double nameTop = tester
            .getTopLeft(find.byKey(const Key('field-service-name')))
            .dy;

        expect(
          categoryTop < serviceTypeTop,
          isTrue,
          reason: 'category must render ABOVE the service type',
        );
        expect(
          serviceTypeTop < nameTop,
          isTrue,
          reason: 'service type must render ABOVE the (now last) name field',
        );
      },
    );
  });
}
