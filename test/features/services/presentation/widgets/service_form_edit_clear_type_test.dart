// Phase 16.5 — edit-flow hardening widget tests for [ServiceForm].
//
// Behaviour-level complement to the pure
// shouldClearServiceTypeOnCategoryChange / shouldResetNameOnTypeCleared units
// in service_form_clear_type_on_category_test.dart. These exercise the real
// widget glue: a category change routed through the category dropdown
// (_onCategoryChanged) must, when the new category is INCOMPATIBLE with the
// loaded service type, clear serviceTypeId so the submit never carries a stale
// cross-category id (backend 16.3) — while a COMPATIBLE / same category keeps
// the selection, and the name reset honours the don't-clobber rule.
//
// Coverage:
//   EC-INCOMPAT.  load a service with a serviceTypeId, change to an INCOMPATIBLE
//                 category → the closed type field clears, the picker repopulates
//                 for the new category, and submit sends serviceTypeId == null.
//   EC-COMPAT.    change to the SAME category → the selection is retained and
//                 submit still carries the loaded serviceTypeId.
//   EC-NAME-USER. a user-edited (non-type-derived) name survives the clear.
//   EC-NAME-AUTO. a type-derived pre-filled name IS reset by the clear.
//   EC-UNTOUCHED. editing without touching the type/category leaves a null type
//                 null (no regression for a typeless service).
//
// Isolation: fresh ProviderScope per pump; serviceRepositoryProvider mocked so
// approvedCategoriesProvider resolves without real HTTP; serviceTypesProvider
// overridden per category so the picker repopulates deterministically. All
// finders by Key (M2). Behaviour asserted directly on the submitted payload /
// closed-field label, never transitively (M3). pumpAndSettle throughout — no
// fixed-duration pumps (M6).

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
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

// ---------------------------------------------------------------------------
// Mocks + fixtures
// ---------------------------------------------------------------------------

class _MockServiceRepository extends Mock implements ServiceRepository {}

// A FIXED edit-mode service in MANICURE with a loaded service type.
const _editService = MasterService(
  id: 'svc-edit-1',
  serviceDefId: 'def-edit-1',
  name: 'Класичний манікюр',
  category: 'MANICURE',
  serviceTypeId: 'type-manicure',
  serviceTypeNameUk: 'Класичний манікюр',
  durationMinutes: 60,
  priceType: ServicePriceType.fixed,
  priceMin: 500,
  priceDisplay: '500 ₴',
);

// Service types keyed by category. The picker is driven by
// serviceTypesProvider(category); the override returns the slice for the
// category being queried so a category change genuinely repopulates the list.
const _manicureTypes = <ServiceTypeOption>[
  ServiceTypeOption(
    id: 'type-manicure',
    slug: 'CLASSIC_MANICURE',
    nameUk: 'Класичний манікюр',
    categoryName: 'MANICURE',
  ),
];
const _haircutTypes = <ServiceTypeOption>[
  ServiceTypeOption(
    id: 'type-haircut',
    slug: 'WOMENS_HAIRCUT',
    nameUk: 'Жіноча стрижка',
    categoryName: 'HAIRCUT',
  ),
];

// ---------------------------------------------------------------------------
// Finders (by Key — M2)
// ---------------------------------------------------------------------------

final _nameField = find.descendant(
  of: find.byKey(const Key('field-service-name')),
  matching: find.byType(TextField),
);

/// The closed service-type field's currently-shown label text.
Finder _serviceTypeFieldText(String text) => find.descendant(
  of: find.byKey(const Key('select-service-type-field')),
  matching: find.text(text),
);

String _nameText(WidgetTester tester) =>
    tester.widget<TextField>(_nameField).controller!.text;

void main() {
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

  Future<void> pumpForm(
    WidgetTester tester, {
    required Future<void> Function(MasterServiceCreate) onSubmit,
    MasterService? initial,
  }) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        retry: beauticaProviderRetry,
        overrides: [
          serviceRepositoryProvider.overrideWithValue(repo),
          approvedCategoriesProvider.overrideWith((ref) async => categories),
          // Return the slice for whichever category the picker queries, so a
          // category change genuinely repopulates the option list.
          serviceTypesProvider.overrideWith((ref, String categoryName) async {
            switch (categoryName) {
              case 'MANICURE':
                return _manicureTypes;
              case 'HAIRCUT':
                return _haircutTypes;
              default:
                return const <ServiceTypeOption>[];
            }
          }),
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
    await tester.pumpAndSettle();
  }

  Future<void> tapSubmit(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('btn-submit-service')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('btn-submit-service')));
    await tester.pump();
  }

  Future<void> neverSubmit(MasterServiceCreate _) async {}

  testWidgets(
    'EC-INCOMPAT. changing to an incompatible category clears serviceTypeId, '
    'repopulates the picker, and submit drops the stale id',
    (tester) async {
      MasterServiceCreate? captured;
      await pumpForm(
        tester,
        onSubmit: (input) async => captured = input,
        initial: _editService,
      );

      // The loaded service type labels the closed field before the change.
      expect(_serviceTypeFieldText('Класичний манікюр'), findsOneWidget);

      // Change category MANICURE → HAIRCUT (incompatible with the loaded type).
      await selectCategoryOption(tester, 'HAIRCUT');

      // The stale type is cleared from the closed field…
      expect(
        _serviceTypeFieldText('Класичний манікюр'),
        findsNothing,
        reason: 'an incompatible category change must clear the loaded type',
      );
      // …and the picker repopulated for HAIRCUT: open it and assert the new
      // category\'s option is present (and the old one is gone).
      await openServiceTypeMenu(tester);
      expect(
        find.byKey(const Key('chip-service-type-type-haircut')),
        findsOneWidget,
        reason: 'the picker must repopulate with the new category\'s types',
      );
      expect(
        find.byKey(const Key('chip-service-type-type-manicure')),
        findsNothing,
      );
      // Close the menu (tap the scrim / back) before submitting.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(
        captured!.serviceTypeId,
        isNull,
        reason:
            'submit after an incompatible category change must NOT carry the '
            'stale cross-category serviceTypeId (backend 16.3)',
      );
      expect(captured!.category, 'HAIRCUT');
    },
  );

  testWidgets('EC-COMPAT. re-selecting the same category retains the loaded '
      'serviceTypeId on submit', (tester) async {
    MasterServiceCreate? captured;
    await pumpForm(
      tester,
      onSubmit: (input) async => captured = input,
      initial: _editService,
    );

    // Re-select the SAME category — a valid selection must be kept.
    await selectCategoryOption(tester, 'MANICURE');

    expect(
      _serviceTypeFieldText('Класичний манікюр'),
      findsOneWidget,
      reason: 're-selecting the same category must keep the selection',
    );

    await tapSubmit(tester);
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(
      captured!.serviceTypeId,
      'type-manicure',
      reason: 'a compatible/same category change must retain serviceTypeId',
    );
  });

  testWidgets(
    'EC-NAME-USER. a user-edited name survives the incompatible-category clear',
    (tester) async {
      await pumpForm(tester, onSubmit: neverSubmit, initial: _editService);

      // The loaded service name was NOT type-derived from this session\'s
      // auto-fill (it is the persisted name). The master also hand-edits it to
      // make the "user-edited" intent unambiguous.
      await tester.enterText(_nameField, 'Мій власний манікюр');
      await tester.pump();

      await selectCategoryOption(tester, 'HAIRCUT');

      expect(
        _nameText(tester),
        'Мій власний манікюр',
        reason: 'a user-edited name must never be clobbered by the type clear',
      );
    },
  );

  testWidgets(
    'EC-NAME-AUTO. a type-derived pre-filled name IS reset by the clear',
    (tester) async {
      // Start from a blank-name, typeless service in MANICURE so the auto-fill
      // genuinely fires when a type is selected. (Selecting a type only
      // overwrites the name when it is empty OR still equals the last auto-fill
      // — a pre-existing persisted name would block the auto-fill and the name
      // would never become type-derived in this session.)
      const blankNameService = MasterService(
        id: 'svc-blank',
        serviceDefId: 'def-blank',
        name: '',
        category: 'MANICURE',
        durationMinutes: 60,
        priceType: ServicePriceType.fixed,
        priceMin: 500,
        priceDisplay: '500 ₴',
      );
      await pumpForm(tester, onSubmit: neverSubmit, initial: blankNameService);

      // Select the type via the picker so the auto-fill path runs and marks the
      // name as type-derived (lastAutoFilledName tracked).
      await selectServiceTypeOption(tester, 'type-manicure');
      expect(
        _nameText(tester),
        'Класичний манікюр',
        reason: 'selecting the type auto-fills its nameUk into the empty name',
      );

      // Now switch to an incompatible category → the type clears AND the
      // type-derived name resets to empty.
      await selectCategoryOption(tester, 'HAIRCUT');

      expect(
        _nameText(tester),
        '',
        reason:
            'a name still equal to the last type-derived auto-fill must be '
            'reset when the incompatible type is cleared',
      );
    },
  );

  testWidgets(
    'EC-UNTOUCHED. editing a typeless service without touching the type leaves '
    'serviceTypeId null',
    (tester) async {
      const typelessService = MasterService(
        id: 'svc-2',
        serviceDefId: 'def-2',
        name: 'Без типу',
        category: 'MANICURE',
        durationMinutes: 45,
        priceType: ServicePriceType.fixed,
        priceMin: 300,
        priceDisplay: '300 ₴',
      );

      MasterServiceCreate? captured;
      await pumpForm(
        tester,
        onSubmit: (input) async => captured = input,
        initial: typelessService,
      );

      // Edit an unrelated field; never touch the category or type.
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('field-service-duration')),
          matching: find.byType(TextField),
        ),
        '50',
      );
      await tester.pump();

      await tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(
        captured!.serviceTypeId,
        isNull,
        reason:
            'a typeless service must submit serviceTypeId == null unchanged',
      );
    },
  );
}
