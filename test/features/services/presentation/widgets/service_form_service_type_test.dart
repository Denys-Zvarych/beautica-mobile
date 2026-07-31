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
//   W-SUBMIT-NULL. CONTRACT CHANGE — service type is now MANDATORY on create:
//                  submitting WITHOUT selecting a type BLOCKS submit (onSubmit
//                  never fires) and surfaces the inline serviceTypeRequired error.
//   W-CLEAR.       clearServiceType() drops the id → submit is likewise BLOCKED
//                  with the inline required error (no create payload leaves).
//
// Isolation: fresh ProviderScope per pump; serviceRepositoryProvider overridden
// with a mock so approvedCategoriesProvider resolves without real HTTP. Fields
// found by Key (M2). The State is reached via find.byType(ServiceForm) — the
// methods exercised are public; the State class is private so it is accessed
// through `dynamic` (the only way to invoke a public method on a private State).

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

/// Resolves the localisations bound to the pumped [ServiceForm] so error
/// assertions compare against the l10n value (not a raw literal).
AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(ServiceForm)));

void main() {
  late _MockServiceRepository repo;

  // approvedCategoriesProvider is overridden directly below (it fetches via
  // categoryRequestApi, not the repo).
  const categories = <ServiceCategoryOption>[
    ServiceCategoryOption(name: 'MANICURE', displayName: 'Манікюр'),
  ];

  setUp(() {
    repo = _MockServiceRepository();
  });

  Future<void> pumpForm(
    WidgetTester tester, {
    required Future<void> Function(MasterServiceCreate) onSubmit,
    // Service types surfaced by the second-level picker for the selected
    // category. Defaults to empty (the picker renders its calm empty state);
    // tests that need to tap / submit a type chip pass a non-empty list.
    List<ServiceTypeOption> serviceTypes = const <ServiceTypeOption>[],
    // Non-null → EDIT mode (prefilled form). Null → CREATE mode.
    MasterService? initial,
  }) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        retry: beauticaProviderRetry,
        overrides: [
          serviceRepositoryProvider.overrideWithValue(repo),
          approvedCategoriesProvider.overrideWith((ref) async => categories),
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
            body: SingleChildScrollView(
              child: ServiceForm(initial: initial, onSubmit: onSubmit),
            ),
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
    'W-SUBMIT-NULL. submitting WITHOUT a type is BLOCKED and shows the '
    'required error (service type mandatory on create)',
    (tester) async {
      MasterServiceCreate? captured;
      await pumpForm(tester, onSubmit: (input) async => captured = input);

      await fillExceptName(tester);
      await tester.enterText(_nameField, 'Манікюр');
      await tapSubmit(tester);
      await tester.pumpAndSettle();

      // Client-side required validation blocks the submit entirely.
      expect(
        captured,
        isNull,
        reason: 'no type selected → onSubmit must NOT fire (submit blocked)',
      );
      // The inline required error is surfaced on the service-type field.
      final l10n = _l10n(tester);
      expect(find.byKey(const Key('error-service-type')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('error-service-type')),
          // find via l10n value (i18n-safe), not a raw literal.
          matching: find.text(l10n.serviceTypeRequired),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'W-CLEAR. clearing the selected type re-BLOCKS submit with the required '
    'error',
    (tester) async {
      MasterServiceCreate? captured;
      final option = _type('type-xyz', 'Манікюр');
      await pumpForm(
        tester,
        onSubmit: (input) async => captured = input,
        serviceTypes: <ServiceTypeOption>[option],
      );

      await fillExceptName(tester);
      _formState(tester).onServiceTypeSelected(option);
      await tester.pump();
      // Master removes the selection again → back to "no type".
      _formState(tester).clearServiceType();
      await tester.pump();

      await tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(
        captured,
        isNull,
        reason: 'type cleared → onSubmit must NOT fire (submit blocked)',
      );
      final l10n = _l10n(tester);
      expect(find.byKey(const Key('error-service-type')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('error-service-type')),
          matching: find.text(l10n.serviceTypeRequired),
        ),
        findsOneWidget,
      );
    },
  );

  // ── NEW (mandatory-picker positive guarantees) ────────────────────────────
  // The feature's positive contract: selecting a type after a blocked attempt
  // CLEARS the required error and lets the create through.

  testWidgets(
    'W-SELECT-CLEARS-ERROR. selecting a type after a blocked submit clears '
    'the required error and allows submit',
    (tester) async {
      MasterServiceCreate? captured;
      final option = _type('type-xyz', 'Манікюр');
      await pumpForm(
        tester,
        onSubmit: (input) async => captured = input,
        serviceTypes: <ServiceTypeOption>[option],
      );

      await fillExceptName(tester);
      // First attempt with no type → blocked + error shown.
      await tapSubmit(tester);
      await tester.pumpAndSettle();
      expect(captured, isNull);
      expect(find.byKey(const Key('error-service-type')), findsOneWidget);

      // Now select a type → the required error must disappear.
      _formState(tester).onServiceTypeSelected(option);
      await tester.pump();
      expect(find.byKey(const Key('error-service-type')), findsNothing);

      // And the second submit now goes through with the selected id.
      await tapSubmit(tester);
      await tester.pumpAndSettle();
      expect(captured, isNotNull);
      expect(captured!.serviceTypeId, 'type-xyz');
    },
  );

  // ── Backend-400 safety net (contract-drift guard) ─────────────────────────
  // A create that passes client validation but is rejected server-side with a
  // serviceTypeId field error must map back onto the SAME picker field (so a
  // backend contract drift is surfaced inline, never swallowed).
  testWidgets(
    'W-SERVER-400. a serviceTypeId 400 from the API maps to the picker field '
    'error',
    (tester) async {
      const serverMsg = 'Тип послуги обовʼязковий';
      final option = _type('type-xyz', 'Манікюр');
      await pumpForm(
        tester,
        // Simulate the API rejecting the create with a serviceTypeId field
        // error (e.g. contract drift / a race that cleared the type server-side).
        onSubmit: (_) async => throw const ValidationFailure(
          fieldErrors: <String, String>{'serviceTypeId': serverMsg},
        ),
        serviceTypes: <ServiceTypeOption>[option],
      );

      await fillExceptName(tester);
      _formState(tester).onServiceTypeSelected(option);
      await tester.pump();
      await tapSubmit(tester);
      await tester.pumpAndSettle();

      // The server message lands INLINE on the service-type field, not a
      // generic snackbar.
      expect(find.byKey(const Key('error-service-type')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('error-service-type')),
          matching: find.text(serverMsg),
        ),
        findsOneWidget,
      );
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  // ── Create-vs-edit asymmetry ──────────────────────────────────────────────
  // The mandatory-type rule is CREATE-only. In EDIT mode the picker stays
  // optional (PATCH "no change" semantics), so a submit with NO type selected
  // must still fire onSubmit and must NOT raise the required error. This pins
  // the asymmetry so edit is never accidentally made required.
  testWidgets(
    'EDIT-OPTIONAL. edit mode submits without a type — no required error '
    '(create-vs-edit asymmetry)',
    (tester) async {
      MasterServiceCreate? captured;
      // Loaded service with NO service type — proves edit does not enforce it.
      const editService = MasterService(
        id: 'svc-edit-1',
        serviceDefId: 'def-edit-1',
        name: 'Мій манікюр',
        category: 'MANICURE',
        durationMinutes: 60,
        priceType: ServicePriceType.fixed,
        priceMin: 500,
        priceDisplay: '500 ₴',
      );

      await pumpForm(
        tester,
        onSubmit: (input) async => captured = input,
        initial: editService,
      );

      // Submit as-is — no type selected, no field changed.
      await tapSubmit(tester);
      await tester.pumpAndSettle();

      // onSubmit fires (edit is not blocked) and the type is left null (PATCH
      // "no change"); crucially the required ERROR row is NEVER shown in edit
      // mode. (The serviceTypeRequired string also doubles as the picker's
      // empty-state placeholder, so the unambiguous proof is the absent
      // `error-service-type` row — not a raw text match.)
      expect(
        captured,
        isNotNull,
        reason: 'edit mode must submit without a service type (type optional)',
      );
      expect(captured!.serviceTypeId, isNull);
      expect(find.byKey(const Key('error-service-type')), findsNothing);
    },
  );
}
