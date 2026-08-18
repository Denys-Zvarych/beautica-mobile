// 409 DUPLICATE_SERVICE → localized inline error on [ServiceForm].
//
// THE BUG THIS GUARDS
// -------------------
// A backend 409 with the typed `{ data: { code: "DUPLICATE_SERVICE", … } }`
// envelope used to fall through to the generic `errServer` "server error, try
// again" snackbar — which re-hit the same 409 forever — because neither the
// repository nor the form decoded the typed code. The repository now throws a
// [ServiceDuplicateFailure]; the form special-cases it and surfaces the
// localized `l10n.serviceErrDuplicate` INLINE on the keyed `error-service-type`
// row (the field that determines the duplicate), never the generic snackbar.
//
// This widget test drives ServiceForm's real _handleSubmit:
//   D1. onSubmit throws ServiceDuplicateFailure → localized duplicate copy shown
//       inline on the service-type row; NO snackbar; the generic errServer copy
//       is never rendered.
//
// Isolation: fresh ProviderScope per pump; serviceRepositoryProvider +
// serviceTypesProvider overridden so no real HTTP fires. All finders by Key or
// by a localized string pulled from AppLocalizations — never a hardcoded
// Cyrillic literal (i18n-finder gate compliant).

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/master_service_input.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/domain/service_type_option.dart';
import 'package:beautica_mobile/features/services/presentation/service_types_provider.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_form.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'select_dropdown_test_helpers.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

class _MockServiceRepository extends Mock implements ServiceRepository {}

// Edit-mode FIXED service: NAILS category + a service type belonging to NAILS.
// (Prefilled + valid, so a bare tapSubmit reaches onSubmit without local
// validation blocking it.)
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
  // A SECOND NAILS type so D2 can re-select a DIFFERENT type on the same
  // (unchanged) category and prove the inline duplicate error clears on edit.
  ServiceTypeOption(
    id: 'type-nails-gel',
    slug: 'GEL_MANICURE',
    nameUk: 'Гель-лак',
    categoryName: 'NAILS',
  ),
];

/// Resolves [l10n] from the live pumped tree so the asserted text is the real
/// localized value (never a hardcoded literal).
AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(ServiceForm)));

void main() {
  late _MockServiceRepository repo;

  const categories = <ServiceCategoryOption>[
    ServiceCategoryOption(name: 'NAILS', displayName: 'Нігті'),
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
            return categoryName == 'NAILS'
                ? _nailsTypes
                : const <ServiceTypeOption>[];
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
    'D1. ServiceDuplicateFailure → localized duplicate copy inline on the '
    'service-type row (NOT the generic errServer snackbar)',
    (tester) async {
      await pumpForm(
        tester,
        // The repository decodes 409 DUPLICATE_SERVICE to this typed failure.
        onSubmit: (_) async => throw const ServiceDuplicateFailure(
          serviceName: 'Класичний манікюр',
          existingServiceDefId: 'def-existing',
        ),
        initial: _editService,
      );

      await tapSubmit(tester);
      await tester.pumpAndSettle();

      final l10n = _l10n(tester);
      final errorRow = find.byKey(const Key('error-service-type'));
      expect(
        errorRow,
        findsOneWidget,
        reason: 'the duplicate 409 must surface on the inline error row',
      );
      expect(
        find.descendant(
          of: errorRow,
          matching: find.text(l10n.serviceErrDuplicate),
        ),
        findsOneWidget,
        reason: 'the LOCALIZED duplicate copy must render inline',
      );
      // The whole point of the fix: never the generic errServer snack.
      expect(
        find.byType(VelvetSnack),
        findsNothing,
        reason: 'a duplicate 409 must NOT fall through to a snack',
      );
      expect(
        find.text(l10n.errServer),
        findsNothing,
        reason: 'the generic "server error, try again" copy must never show',
      );
    },
  );

  testWidgets(
    'D2. editing the flagged service-type field clears the inline duplicate '
    'error (mirrors the mismatch-400 edit-clears-error contract)',
    (tester) async {
      // First submit throws the duplicate; a second (re-selection) would NOT be
      // reached because the guard is on the service-type field. Keep onSubmit
      // throwing so the ONLY way the inline error disappears is the field edit
      // clearing the stored server error, not a subsequent successful submit.
      await pumpForm(
        tester,
        onSubmit: (_) async => throw const ServiceDuplicateFailure(
          serviceName: 'Класичний манікюр',
          existingServiceDefId: 'def-existing',
        ),
        initial: _editService,
      );

      await tapSubmit(tester);
      await tester.pumpAndSettle();

      // Precondition: the inline duplicate error is showing on the row.
      final l10n = _l10n(tester);
      final errorRow = find.byKey(const Key('error-service-type'));
      expect(
        find.descendant(
          of: errorRow,
          matching: find.text(l10n.serviceErrDuplicate),
        ),
        findsOneWidget,
        reason: 'D2 precondition: the duplicate error must be shown first',
      );

      // Edit the flagged field: re-open the service-type picker and choose a
      // DIFFERENT NAILS type. onServiceTypeSelected → _clearServerError(
      // 'serviceTypeId') must drop the stale server error.
      await selectServiceTypeOption(tester, 'type-nails-gel');

      expect(
        find.descendant(
          of: errorRow,
          matching: find.text(l10n.serviceErrDuplicate),
        ),
        findsNothing,
        reason:
            'editing (re-selecting) the service type must clear the stale '
            'duplicate inline error',
      );
    },
  );
}
