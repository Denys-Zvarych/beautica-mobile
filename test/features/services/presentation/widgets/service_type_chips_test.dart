// Phase 16.4 — widget tests for the second-level service-type picker UI on
// [ServiceForm] (the `_ServiceTypeChips` row + `_ServiceTypeError` leaf).
//
// Where Phase 16.3's tests drive the wiring by reaching the form's public State
// methods directly, THIS file exercises the actual rendered picker — row
// visibility, the three async states, real chip taps, and the inline error —
// because 16.4 is the UI surface that the user touches. The highest-value
// guards (per the debugger) are end-to-end through the rendered pills:
//   - tapping a type pill drives the 16.3 wiring (id set + name pre-fill) and
//     submit carries `serviceTypeId`;
//   - changing the category clears the previously-selected type so a later
//     submit sends `serviceTypeId = null`.
//
// Coverage:
//   V-HIDDEN.    no category selected → the service-type row is absent.
//   V-SHOWN.     selecting a category → the row (label) appears.
//   S-EMPTY.     provider returns [] → calm `serviceTypeEmpty` hint, no error.
//   S-DATA.      provider returns options → a `nameUk` pill per option renders.
//   S-LOADING.   delayed provider → the inset skeleton pill shows first.
//   E2E-SELECT.  tapping a pill sets serviceTypeId + pre-fills name; submit
//                carries the id and the pre-filled name (highest value).
//   E2E-CLEAR.   select category→type, then change category → submit sends
//                serviceTypeId = null (locks clear-on-category-change).
//   INLINE-ERR.  a serviceTypeId server error renders the `error-service-type`
//                row (closes the 16.3 widget-gap backlog item).
//
// Isolation: fresh ProviderScope per pump; serviceRepositoryProvider mocked so
// approvedCategoriesProvider resolves without HTTP; serviceTypesProvider
// overridden per-test (sync list, empty, or delayed for the loading state).
// Widgets found by Key (M2) — no localised-string finders for assertions.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service_input.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/domain/service_type_option.dart';
import 'package:beautica_mobile/features/services/presentation/service_types_provider.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_form.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

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

// Two categories so the clear-on-category-change test has a second chip to tap.
const _categories = <ServiceCategoryOption>[
  ServiceCategoryOption(name: 'MANICURE', displayName: 'Манікюр'),
  ServiceCategoryOption(name: 'PEDICURE', displayName: 'Педикюр'),
];

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

String _nameText(WidgetTester tester) =>
    tester.widget<TextField>(_nameField).controller!.text;

/// The picker's section label `Text` — used only to assert row VISIBILITY,
/// never to assert data (M2: data assertions go through chip keys).
Finder _serviceTypeLabel(WidgetTester tester) {
  final l10n = AppLocalizations.of(tester.element(find.byType(ServiceForm)));
  return find.text(l10n.serviceTypeLabel.toUpperCase());
}

void main() {
  late _MockServiceRepository repo;

  setUp(() {
    repo = _MockServiceRepository();
    when(() => repo.fetchApprovedCategories())
        .thenAnswer((_) async => _categories);
  });

  /// Pumps the create form. [serviceTypes] is the synchronous list every
  /// category's picker resolves to (the override ignores the category arg so a
  /// single list serves all tests that don't need per-category differences).
  /// [delayedTypes] (when set) wins over [serviceTypes] and resolves after a
  /// delay — used to assert the loading state.
  Future<void> pumpForm(
    WidgetTester tester, {
    required Future<void> Function(MasterServiceCreate) onSubmit,
    List<ServiceTypeOption> serviceTypes = const <ServiceTypeOption>[],
    Duration? typesDelay,
    Object? typesError,
  }) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serviceRepositoryProvider.overrideWithValue(repo),
          serviceTypesProvider.overrideWith((ref, String categoryName) async {
            if (typesError != null) throw typesError;
            if (typesDelay != null) await Future<void>.delayed(typesDelay);
            return serviceTypes;
          }),
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

  /// Selects [wire]'s category chip (resolving the category provider first).
  Future<void> selectCategory(WidgetTester tester, String wire) async {
    await tester.pumpAndSettle(); // resolve approvedCategoriesProvider
    final chip = find.byKey(Key('chip-category-$wire'));
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pump();
  }

  /// Fills duration + fixed price so a submit passes client validation. Name
  /// and category are left to the test (the name may come from the type
  /// pre-fill; the category is selected explicitly to control the picker).
  Future<void> fillDurationAndPrice(WidgetTester tester) async {
    await tester.enterText(_durationField, '30');
    await tester.enterText(_fixedPriceField, '500');
    await tester.pump();
  }

  Future<void> tapSubmit(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('btn-submit-service')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('btn-submit-service')));
    await tester.pump();
  }

  Future<void> neverSubmit(MasterServiceCreate _) async {}

  // -------------------------------------------------------------------------
  // 1 — Row visibility
  // -------------------------------------------------------------------------

  testWidgets('V-HIDDEN. no category selected → service-type row is absent', (
    tester,
  ) async {
    await pumpForm(tester, onSubmit: neverSubmit);
    await tester.pumpAndSettle();

    expect(_serviceTypeLabel(tester), findsNothing);
    expect(find.byKey(const Key('service-type-chips-empty')), findsNothing);
  });

  testWidgets('V-SHOWN. selecting a category → the service-type row appears', (
    tester,
  ) async {
    await pumpForm(tester, onSubmit: neverSubmit);

    await selectCategory(tester, 'MANICURE');
    await tester.pumpAndSettle();

    expect(_serviceTypeLabel(tester), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // 2 — Async states
  // -------------------------------------------------------------------------

  testWidgets('S-EMPTY. empty list → calm hint, no error styling', (
    tester,
  ) async {
    await pumpForm(tester, onSubmit: neverSubmit); // default [] types

    await selectCategory(tester, 'MANICURE');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('service-type-chips-empty')), findsOneWidget);
    // The empty state is NOT an error: the inline error row must be absent.
    expect(find.byKey(const Key('error-service-type')), findsNothing);
    // And it is a hint, not an error retry chip.
    expect(find.byKey(const Key('category-chips-error')), findsNothing);
  });

  testWidgets('S-DATA. non-empty list → a nameUk pill per option renders', (
    tester,
  ) async {
    await pumpForm(
      tester,
      onSubmit: neverSubmit,
      serviceTypes: <ServiceTypeOption>[
        _type('t1', 'Класичний манікюр'),
        _type('t2', 'Апаратний манікюр'),
      ],
    );

    await selectCategory(tester, 'MANICURE');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chip-service-type-t1')), findsOneWidget);
    expect(find.byKey(const Key('chip-service-type-t2')), findsOneWidget);
    // Data binding: the pill label is the nameUk, not the id/slug.
    expect(find.text('Класичний манікюр'), findsOneWidget);
    expect(find.text('Апаратний манікюр'), findsOneWidget);
    // No empty hint when there is data.
    expect(find.byKey(const Key('service-type-chips-empty')), findsNothing);
  });

  testWidgets('S-LOADING. delayed provider → inset skeleton pill shows first', (
    tester,
  ) async {
    await pumpForm(
      tester,
      onSubmit: neverSubmit,
      serviceTypes: <ServiceTypeOption>[_type('t1', 'Класичний манікюр')],
      typesDelay: const Duration(milliseconds: 200),
    );

    await tester.pumpAndSettle(); // resolve categories
    await tester.tap(find.byKey(const Key('chip-category-MANICURE')));
    await tester.pump(); // mount picker → provider is still loading

    // The category row also uses this loading key, but it has long since
    // resolved; the only loading skeleton on screen now is the type picker's.
    expect(find.byKey(const Key('category-chips-loading')), findsOneWidget);

    // Let the delayed future complete so the test ends clean.
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chip-service-type-t1')), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // 3 — Selection drives the 16.3 wiring (HIGHEST VALUE, end-to-end via tap)
  // -------------------------------------------------------------------------

  testWidgets(
    'E2E-SELECT. tapping a type pill sets serviceTypeId, pre-fills name, '
    'and submit carries both',
    (tester) async {
      MasterServiceCreate? captured;
      final option = _type('type-xyz', 'Класичний манікюр');
      await pumpForm(
        tester,
        onSubmit: (input) async => captured = input,
        serviceTypes: <ServiceTypeOption>[option],
      );

      // Category first (mounting the picker), then fill the rest.
      await selectCategory(tester, 'MANICURE');
      await tester.pumpAndSettle();
      await fillDurationAndPrice(tester);

      // Tap the actual rendered pill — this is the 16.4 UI path.
      final pill = find.byKey(const Key('chip-service-type-type-xyz'));
      await tester.ensureVisible(pill);
      await tester.tap(pill);
      await tester.pump();

      // 16.3 wiring: name pre-filled from nameUk.
      expect(_nameText(tester), 'Класичний манікюр');

      await tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.serviceTypeId, 'type-xyz');
      expect(captured!.name, 'Класичний манікюр');
    },
  );

  // -------------------------------------------------------------------------
  // 4 — Clear-on-category-change (second highest value — locks the behaviour
  //     the regression touched)
  // -------------------------------------------------------------------------

  testWidgets(
    'E2E-CLEAR. changing category after selecting a type → submit sends '
    'serviceTypeId = null',
    (tester) async {
      MasterServiceCreate? captured;
      final option = _type('type-xyz', 'Класичний манікюр');
      await pumpForm(
        tester,
        onSubmit: (input) async => captured = input,
        // Both categories surface the same option list here; we only need a
        // tappable type chip under MANICURE.
        serviceTypes: <ServiceTypeOption>[option],
      );

      // Select MANICURE, select the type via its pill.
      await selectCategory(tester, 'MANICURE');
      await tester.pumpAndSettle();
      final pill = find.byKey(const Key('chip-service-type-type-xyz'));
      await tester.ensureVisible(pill);
      await tester.tap(pill);
      await tester.pump();
      expect(_nameText(tester), 'Класичний манікюр'); // type is selected

      // Now change the category → must clear the selected type.
      await selectCategory(tester, 'PEDICURE');
      await tester.pumpAndSettle();

      // Provide a fresh, hand-typed name (the auto-fill carries over, but we
      // assert serviceTypeId specifically — the type, not the name, is cleared).
      await fillDurationAndPrice(tester);
      await tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(
        captured!.serviceTypeId,
        isNull,
        reason: 'changing category must clear the previously-selected type',
      );
    },
  );

  // -------------------------------------------------------------------------
  // 6 — Inline error (closes the 16.3 widget-gap backlog item)
  // -------------------------------------------------------------------------

  testWidgets(
    'INLINE-ERR. a serviceTypeId server error renders the error-service-type '
    'row',
    (tester) async {
      final option = _type('type-xyz', 'Класичний манікюр');
      // onSubmit throws a ValidationFailure keyed on serviceTypeId — the form
      // maps it back to the inline error leaf beneath the picker.
      Future<void> onSubmit(MasterServiceCreate _) async {
        throw const ValidationFailure(
          fieldErrors: <String, String>{
            'serviceTypeId': 'Тип не належить обраній категорії',
          },
        );
      }

      await pumpForm(
        tester,
        onSubmit: onSubmit,
        serviceTypes: <ServiceTypeOption>[option],
      );

      await selectCategory(tester, 'MANICURE');
      await tester.pumpAndSettle();
      await fillDurationAndPrice(tester);

      final pill = find.byKey(const Key('chip-service-type-type-xyz'));
      await tester.ensureVisible(pill);
      await tester.tap(pill);
      await tester.pump();

      await tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('error-service-type')), findsOneWidget);
      expect(find.text('Тип не належить обраній категорії'), findsOneWidget);
    },
  );
}
