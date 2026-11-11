// 409 DUPLICATE_SERVICE → localized inline error on [ServiceForm].
//
// THE BUG THIS GUARDS
// -------------------
// A backend 409 with the typed `{ data: { code: "DUPLICATE_SERVICE", … } }`
// envelope used to fall through to the generic `errServer` "server error, try
// again" snackbar — which re-hit the same 409 forever — because neither the
// repository nor the form decoded the typed code. The repository now throws a
// [ServiceDuplicateFailure]; the form special-cases it and surfaces the
// localized duplicate copy INLINE, never the generic snackbar. Phase 468: a
// type may be held more than once (copies differ in duration OR name), so the
// message (`serviceErrDuplicateCopy`) sits on the name + duration fields.
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
    'D1. ServiceDuplicateFailure → the duplicate-copy copy inline on BOTH the '
    'name and duration fields (phase 468), not the service-type row, and NOT '
    'the generic errServer snackbar',
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
      expect(
        find.text(l10n.serviceErrDuplicateCopy),
        findsNWidgets(2),
        reason: 'the 409 flags the two fields that resolve it: name + duration',
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('pricing-field')),
          matching: find.text(l10n.serviceErrDuplicateCopy),
        ),
        findsOneWidget,
        reason: 'one of the two messages sits on the duration well',
      );
      expect(
        find.byKey(const Key('error-service-type')),
        findsNothing,
        reason: 'the service type no longer decides the duplicate',
      );
      expect(find.byType(VelvetSnack), findsNothing);
      expect(find.text(l10n.errServer), findsNothing);
    },
  );

  testWidgets(
    'D2. editing the duration clears the paired duplicate message on BOTH '
    'fields (the rule is "differs in duration OR name")',
    (tester) async {
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

      final l10n = _l10n(tester);
      expect(
        find.text(l10n.serviceErrDuplicateCopy),
        findsNWidgets(2),
        reason: 'D2 precondition',
      );

      await tester.enterText(
        find
            .descendant(
              of: find.byKey(const Key('pricing-field')),
              matching: find.byType(TextField),
            )
            .first,
        '75',
      );
      await tester.pumpAndSettle();

      expect(
        find.text(l10n.serviceErrDuplicateCopy),
        findsNothing,
        reason: 'changing either field resolves the duplicate',
      );
    },
  );

  testWidgets('D3. editing the NAME also clears both messages', (tester) async {
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

    final l10n = _l10n(tester);
    expect(find.text(l10n.serviceErrDuplicateCopy), findsNWidgets(2));

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-service-name')),
        matching: find.byType(TextField),
      ),
      'Класичний манікюр (довгий)',
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.serviceErrDuplicateCopy), findsNothing);
  });
}
