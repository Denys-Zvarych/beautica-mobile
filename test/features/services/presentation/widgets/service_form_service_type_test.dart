// Phase 16.3 — widget behaviour tests for the service-type wiring on
// [ServiceForm]. The picker UI lands in Phase 16.4; this phase only wires the
// behaviour, so these tests drive it by reaching the form's public State
// methods ([onServiceTypeSelected] / [clearServiceType]) directly — the same
// surface the future picker will call into.
//
// Coverage (the behaviour-level complement to the pure shouldPrefillName unit
// in service_form_prefill_test.dart):
//   W-PREFILL.     selecting a type pre-fills an empty name with nameUk.
//   W-REFILL.      selecting a 2nd type re-fills the name when it still equals
//                  the first auto-fill (not user-edited).
//   W-NO-CLOBBER.  a user-edited name is NOT overwritten by the next selection.
//   W-SUBMIT-ID.   selecting a type then submitting sends serviceTypeId on the
//                  built MasterServiceCreate.
//   W-SUBMIT-NULL. submitting WITHOUT selecting a type sends serviceTypeId=null
//                  (no regression — the existing create path is unchanged).
//   W-CLEAR.       clearServiceType() nulls the id → submit sends null again.
//
// Isolation: fresh ProviderScope per pump; serviceRepositoryProvider overridden
// with a mock so approvedCategoriesProvider resolves without real HTTP. Fields
// found by Key (M2). The State is reached via find.byType(ServiceForm) — the
// methods exercised are public; the State class is private so it is accessed
// through `dynamic` (the only way to invoke a public method on a private State).

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

// ---------------------------------------------------------------------------
// Mocks + helpers
// ---------------------------------------------------------------------------

class _MockServiceRepository extends Mock implements ServiceRepository {}

ServiceTypeOption _type(String id, String nameUk) => ServiceTypeOption(
  id: id,
  slug: id.toUpperCase(),
  nameUk: nameUk,
  categoryName: 'MANICURE',
);

final _nameField = find.descendant(
  of: find.byKey(const Key('field-service-name')),
  matching: find.byType(TextField),
);
final _durationField = find.descendant(
  of: find.byKey(const Key('field-service-duration')),
  matching: find.byType(TextField),
);
final _fixedPriceField = find.descendant(
  of: find.byKey(const Key('pricing-fixed-amount')),
  matching: find.byType(TextField),
);

/// Reaches the form's State and invokes its public service-type methods.
/// The State class is private (`_ServiceFormState`); `dynamic` dispatch is the
/// only way to call its public methods from outside the library.
dynamic _formState(WidgetTester tester) =>
    tester.state(find.byType(ServiceForm));

String _nameText(WidgetTester tester) =>
    tester.widget<TextField>(_nameField).controller!.text;

void main() {
  late _MockServiceRepository repo;

  setUp(() {
    repo = _MockServiceRepository();
    when(() => repo.fetchApprovedCategories()).thenAnswer(
      (_) async => const <ServiceCategoryOption>[
        ServiceCategoryOption(name: 'MANICURE', displayName: 'Манікюр'),
      ],
    );
  });

  Future<void> pumpForm(
    WidgetTester tester, {
    required Future<void> Function(MasterServiceCreate) onSubmit,
    // Service types surfaced by the second-level picker for the selected
    // category. Defaults to empty (the picker renders its calm empty state);
    // tests that need to tap / submit a type chip pass a non-empty list.
    List<ServiceTypeOption> serviceTypes = const <ServiceTypeOption>[],
  }) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serviceRepositoryProvider.overrideWithValue(repo),
          // _ServiceTypeChips mounts as soon as a category is selected and
          // watches serviceTypesProvider(category) → fetchServiceTypes. Stub it
          // so no un-mocked repository fetch fires inside the form subtree.
          serviceTypesProvider.overrideWith(
            (ref, String categoryName) async => serviceTypes,
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('uk'),
          home: Scaffold(
            body: SingleChildScrollView(child: ServiceForm(onSubmit: onSubmit)),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Fills the non-name fields (duration + fixed price + category) so a submit
  /// passes client validation and onSubmit fires. The name is left to the
  /// caller / the service-type pre-fill.
  Future<void> fillExceptName(WidgetTester tester) async {
    await tester.enterText(_durationField, '30');
    await tester.enterText(_fixedPriceField, '500');
    await selectCategoryOption(tester, 'MANICURE');
  }

  Future<void> tapSubmit(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('btn-submit-service')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('btn-submit-service')));
    await tester.pump();
  }

  Future<void> neverSubmit(MasterServiceCreate _) async {}

  testWidgets('W-PREFILL. selecting a type pre-fills an empty name', (
    tester,
  ) async {
    await pumpForm(tester, onSubmit: neverSubmit);

    _formState(tester).onServiceTypeSelected(_type('t1', 'Класичний манікюр'));
    await tester.pump();

    expect(_nameText(tester), 'Класичний манікюр');
  });

  testWidgets('W-REFILL. a second selection re-fills an un-edited name', (
    tester,
  ) async {
    await pumpForm(tester, onSubmit: neverSubmit);

    _formState(tester).onServiceTypeSelected(_type('t1', 'Класичний манікюр'));
    await tester.pump();
    // Name still equals the first auto-fill → the second selection replaces it.
    _formState(tester).onServiceTypeSelected(_type('t2', 'Апаратний манікюр'));
    await tester.pump();

    expect(_nameText(tester), 'Апаратний манікюр');
  });

  testWidgets('W-NO-CLOBBER. a user-edited name is not overwritten', (
    tester,
  ) async {
    await pumpForm(tester, onSubmit: neverSubmit);

    // Auto-fill, then the user hand-edits the name.
    _formState(tester).onServiceTypeSelected(_type('t1', 'Класичний манікюр'));
    await tester.pump();
    await tester.enterText(_nameField, 'Мій власний манікюр');
    await tester.pump();

    // A subsequent type selection must NOT clobber the edited name.
    _formState(tester).onServiceTypeSelected(_type('t2', 'Апаратний манікюр'));
    await tester.pump();

    expect(_nameText(tester), 'Мій власний манікюр');
  });

  testWidgets('W-SUBMIT-ID. selecting a type sends serviceTypeId on submit', (
    tester,
  ) async {
    MasterServiceCreate? captured;
    final option = _type('type-xyz', 'Манікюр');
    await pumpForm(
      tester,
      onSubmit: (input) async => captured = input,
      // The picker for the selected category must surface this option so the
      // type chip renders and the selection survives.
      serviceTypes: <ServiceTypeOption>[option],
    );

    // Select the category FIRST. Selecting a category now legitimately clears
    // any previously-selected service type (16.4 clear-on-category-change), so
    // the type must be chosen AFTER the category — not before.
    await fillExceptName(tester);
    _formState(tester).onServiceTypeSelected(option);
    await tester.pump();
    await tapSubmit(tester);
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.serviceTypeId, 'type-xyz');
    expect(captured!.name, 'Манікюр');
  });

  testWidgets(
    'W-SUBMIT-NULL. submitting without a selection sends serviceTypeId=null',
    (tester) async {
      MasterServiceCreate? captured;
      await pumpForm(tester, onSubmit: (input) async => captured = input);

      await fillExceptName(tester);
      await tester.enterText(_nameField, 'Манікюр');
      await tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(
        captured!.serviceTypeId,
        isNull,
        reason: 'no type selected → serviceTypeId must be null (no regression)',
      );
    },
  );

  testWidgets('W-CLEAR. clearServiceType nulls the id → submit sends null', (
    tester,
  ) async {
    MasterServiceCreate? captured;
    await pumpForm(tester, onSubmit: (input) async => captured = input);

    _formState(tester).onServiceTypeSelected(_type('type-xyz', 'Манікюр'));
    await tester.pump();
    _formState(tester).clearServiceType();
    await tester.pump();

    await fillExceptName(tester);
    // Name was auto-filled by the selection and clearing leaves it as-is.
    await tapSubmit(tester);
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.serviceTypeId, isNull);
  });
}
