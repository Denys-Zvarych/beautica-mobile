// Phase 16.5 regression (fix #3) — the FIELDLESS backend-400 → localized inline
// error mapping on [ServiceForm].
//
// THE BUG THIS GUARDS
// -------------------
// The backend hardened category-only edits to return a 400 BusinessException
// envelope `{success:false, message:"service type does not belong to the
// selected category"}` with NO `errors` field map when a category change orphans
// the still-selected service type. The ErrorMapperInterceptor (or the
// repository's _mapDioException on the fake backend) maps that to a
// `ValidationFailure(fieldErrors: {}, ...)` — an EMPTY field map.
//
// Before the fix, an empty field map fell straight through to a raw English
// snackbar (the server `message`). After the fix, when the field map is empty
// AND a service type is still selected AND the category is dirty, the form
// surfaces the localized `l10n.serviceTypeCategoryMismatch` INLINE on the
// keyed `error-service-type` row — never the raw English snackbar.
//
// These widget tests drive ServiceForm's real _handleSubmit:
//   M1. fieldless 400 + type selected + category dirty → localized inline error,
//       NO snackbar.                                   (the fix; FAILS pre-fix)
//   M2. fieldless 400 + type selected + category NOT dirty → falls through to the
//       generic snackbar (the structural gate is not a string match, so an
//       unrelated business 400 must still snackbar).
//   M3. a non-empty field map keyed `serviceTypeId` still maps inline (the
//       Phase 16.3 path is unaffected by the fix).
//
// Isolation: fresh ProviderScope per pump; serviceRepositoryProvider +
// serviceTypesProvider overridden so no real HTTP fires. All finders by Key
// (M2). The asserted error text is resolved off the pumped tree via l10n, never
// a hardcoded literal (M2 / M11).

import 'package:beautica_mobile/core/errors/failures.dart';
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

class _MockServiceRepository extends Mock implements ServiceRepository {}

// Edit-mode FIXED service: NAILS category + a service type belonging to NAILS.
const _editService = MasterService(
  id: 'svc-edit-1',
  serviceDefId: 'def-edit-1',
  name: 'Класичний манікюр',
  category: 'NAILS',
  serviceTypeId: 'type-nails',
  serviceTypeNameUk: 'Класичний манікюр',
  durationMinutes: 60,
  priceType: ServicePriceType.fixed,
  priceMin: 500,
  priceDisplay: '500 ₴',
);

const _nailsTypes = <ServiceTypeOption>[
  ServiceTypeOption(
    id: 'type-nails',
    slug: 'CLASSIC_MANICURE',
    nameUk: 'Класичний манікюр',
    categoryName: 'NAILS',
  ),
];
const _browsTypes = <ServiceTypeOption>[
  ServiceTypeOption(
    id: 'type-brows',
    slug: 'BROW_CORRECTION',
    nameUk: 'Корекція брів',
    categoryName: 'BROWS',
  ),
];

/// Resolves [l10n] from the live pumped tree so the asserted error text is the
/// real localized value (never a hardcoded literal — M2 / M11).
AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(ServiceForm)));

void main() {
  late _MockServiceRepository repo;

  // approvedCategoriesProvider is overridden directly below (it fetches via
  // categoryRequestApi, not the repo).
  const categories = <ServiceCategoryOption>[
    ServiceCategoryOption(name: 'NAILS', displayName: 'Нігті'),
    ServiceCategoryOption(name: 'BROWS', displayName: 'Брови'),
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
          serviceTypesProvider.overrideWith((ref, String categoryName) async {
            switch (categoryName) {
              case 'NAILS':
                return _nailsTypes;
              case 'BROWS':
                return _browsTypes;
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

  testWidgets(
    'M1. fieldless 400 + type selected + category dirty → localized inline error '
    '(NOT a raw snackbar)',
    (tester) async {
      await pumpForm(
        tester,
        // The fieldless backend-400 envelope, as mapped by the interceptor /
        // repository: EMPTY fieldErrors + the raw English server message.
        onSubmit: (_) async => throw const ValidationFailure(
          fieldErrors: <String, String>{},
          serverMessage:
              'service type does not belong to the selected category',
        ),
        initial: _editService,
      );

      // Switch category NAILS → BROWS. _onCategoryChanged clears the now-orphan
      // type (Phase 16.5 fix #2). Re-pick a BROWS type so a type IS selected at
      // submit (the gate requires typeSelected) and the category is dirty.
      await selectCategoryOption(tester, 'BROWS');
      await selectServiceTypeOption(tester, 'type-brows');

      await tapSubmit(tester);
      await tester.pumpAndSettle();

      final l10n = _l10n(tester);
      final errorRow = find.byKey(const Key('error-service-type'));
      expect(
        errorRow,
        findsOneWidget,
        reason: 'the fieldless 400 must surface on the inline error row',
      );
      expect(
        find.descendant(
          of: errorRow,
          matching: find.text(l10n.serviceTypeCategoryMismatch),
        ),
        findsOneWidget,
        reason:
            'a fieldless mismatch-400 must render the LOCALIZED inline message',
      );
      // The fix replaced the raw English snackbar with the inline error.
      expect(
        find.byType(SnackBar),
        findsNothing,
        reason: 'fieldless mismatch must NOT fall through to a raw snackbar',
      );
      expect(
        find.text('service type does not belong to the selected category'),
        findsNothing,
        reason: 'the raw English server message must never reach the UI',
      );
    },
  );

  testWidgets(
    'M2. fieldless 400 + category NOT dirty → generic snackbar (gate is '
    'structural, not a string match)',
    (tester) async {
      await pumpForm(
        tester,
        onSubmit: (_) async => throw const ValidationFailure(
          fieldErrors: <String, String>{},
          serverMessage: 'some unrelated business rule failed',
        ),
        initial: _editService,
      );

      // Submit WITHOUT changing the category (category not dirty). The mismatch
      // gate requires categoryDirty, so this unrelated 400 must fall through to
      // the generic snackbar — proving the fix did not blanket-swallow every
      // fieldless 400 into the service-type row.
      await tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('error-service-type')),
        findsNothing,
        reason:
            'an unrelated fieldless 400 (category not dirty) must NOT be mapped '
            'to the service-type inline error',
      );
      expect(
        find.byType(SnackBar),
        findsOneWidget,
        reason: 'an unattributable fieldless 400 still surfaces as a snackbar',
      );
    },
  );

  testWidgets(
    'M3. non-empty serviceTypeId field error still maps inline (Phase 16.3 path '
    'unaffected by the fix)',
    (tester) async {
      const serverMsg = 'Цей тип не належить до обраної категорії';
      await pumpForm(
        tester,
        onSubmit: (_) async => throw const ValidationFailure(
          fieldErrors: <String, String>{'serviceTypeId': serverMsg},
        ),
        initial: _editService,
      );

      // No category change needed — a populated field map maps directly.
      await tapSubmit(tester);
      await tester.pumpAndSettle();

      final errorRow = find.byKey(const Key('error-service-type'));
      expect(errorRow, findsOneWidget);
      expect(
        find.descendant(of: errorRow, matching: find.text(serverMsg)),
        findsOneWidget,
      );
      expect(find.byType(SnackBar), findsNothing);
    },
  );
}
