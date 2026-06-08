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

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
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
  return find.text(l10nOf(tester).serviceTypeLabel.toUpperCase());
}

AppLocalizations l10nOf(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(ServiceForm)));

void main() {
  late _MockServiceRepository repo;

  setUp(() {
    repo = _MockServiceRepository();
    when(
      () => repo.fetchApprovedCategories(),
    ).thenAnswer((_) async => _categories);
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

  /// Selects [wire]'s category via the dropdown (open menu → tap option).
  Future<void> selectCategory(WidgetTester tester, String wire) async {
    await selectCategoryOption(tester, wire);
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
    // The service-type dropdown field is absent until a category is chosen.
    expect(find.byKey(const Key('select-service-type-field')), findsNothing);
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

  testWidgets('S-EMPTY. empty list → calm hint in the menu, no error styling', (
    tester,
  ) async {
    await pumpForm(tester, onSubmit: neverSubmit); // default [] types

    await selectCategory(tester, 'MANICURE');
    await tester.pumpAndSettle();

    // The empty state is NOT an error: the inline cross-field error row must be
    // absent, and the field shows no error affordance.
    expect(find.byKey(const Key('error-service-type')), findsNothing);
    expect(find.byKey(const Key('select-menu-error')), findsNothing);

    // Open the service-type menu → it shows the calm empty hint, not an error.
    await openServiceTypeMenu(tester);
    expect(find.byKey(const Key('select-menu-empty')), findsOneWidget);
    expect(find.text(l10nOf(tester).serviceTypeEmpty), findsOneWidget);
    expect(find.byKey(const Key('select-menu-error')), findsNothing);
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

    // Open the menu → an option row per service type renders.
    await openServiceTypeMenu(tester);

    expect(find.byKey(const Key('chip-service-type-t1')), findsOneWidget);
    expect(find.byKey(const Key('chip-service-type-t2')), findsOneWidget);
    // Data binding: the option label is the nameUk, not the id/slug.
    expect(find.text('Класичний манікюр'), findsOneWidget);
    expect(find.text('Апаратний манікюр'), findsOneWidget);
    // No empty hint when there is data.
    expect(find.byKey(const Key('select-menu-empty')), findsNothing);
  });

  testWidgets(
    'S-LOADING. delayed provider → the field shows a loading affordance '
    '(no infinite/inescapable spinner)',
    (tester) async {
      await pumpForm(
        tester,
        onSubmit: neverSubmit,
        serviceTypes: <ServiceTypeOption>[_type('t1', 'Класичний манікюр')],
        typesDelay: const Duration(milliseconds: 200),
      );

      // Open the category menu and tap MANICURE, but do NOT pumpAndSettle —
      // settling would also resolve the delayed service-type future and we
      // need to observe the in-flight loading affordance.
      await openCategoryMenu(tester);
      await tester.tap(find.byKey(const Key('chip-category-MANICURE')));
      // One pump closes the sheet and mounts the service-type field; the
      // service-type future is still in flight (200 ms delay not yet elapsed).
      await tester.pump();
      await tester.pump();
      expect(
        find.descendant(
          of: find.byKey(const Key('select-service-type-field')),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );

      // Let the delayed future complete; the field now resolves to data and the
      // option becomes selectable via the menu.
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      await openServiceTypeMenu(tester);
      expect(find.byKey(const Key('chip-service-type-t1')), findsOneWidget);
    },
  );

  testWidgets(
    'S-LOADING-NEVER. a never-completing type lookup → the menu spinner is '
    'ESCAPABLE via header close (NOT a stranded infinite spinner — the bug)',
    (tester) async {
      // The provider future never resolves: this is the worst-case hang the
      // reported bug produced. The guard is that the user is NEVER trapped — the
      // field shows the loading affordance and the menu's close X dismisses it.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            serviceRepositoryProvider.overrideWithValue(repo),
            serviceTypesProvider.overrideWith(
              // Completer that is never completed → a permanently in-flight load.
              (ref, String categoryName) =>
                  Completer<List<ServiceTypeOption>>().future,
            ),
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

      // Select the category (cannot pumpAndSettle — the type future never
      // completes, so settle would time out; pump manually instead).
      await openCategoryMenu(tester);
      await tester.tap(find.byKey(const Key('chip-category-MANICURE')));
      // Fully run the category sheet's exit transition so it is gone before the
      // service-type menu opens (otherwise two sheets — and two close X's —
      // coexist). pumpAndSettle is unavailable (the type future never ends), so
      // advance the dismiss animation frame-by-frame.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // The closed field shows the loading affordance, not a stranded chevron.
      expect(
        find.descendant(
          of: find.byKey(const Key('select-service-type-field')),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );

      // Open the menu → an ESCAPABLE spinner: loading body + an ever-present
      // close X. The search box is suppressed (nothing to filter yet).
      await tester.tap(find.byKey(const Key('select-service-type-field')));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50)); // open the sheet
      }
      expect(find.byKey(const Key('select-menu-loading')), findsOneWidget);
      expect(find.byKey(const Key('select-menu-close')), findsOneWidget);
      expect(find.byKey(const Key('select-menu-search')), findsNothing);

      // PROVE escapable: invoke the close handler → the spinner sheet dismisses
      // (handler invoked directly: the in-sheet spinner animates forever and the
      // bottom-aligned header may fall outside the tappable region).
      tester
          .widget<IconButton>(find.byKey(const Key('select-menu-close')))
          .onPressed!();
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.byKey(const Key('select-menu-loading')), findsNothing);
    },
  );

  testWidgets(
    'S-ERROR. a failed type lookup → the field shows an error affordance and '
    'the menu offers Retry (no infinite spinner)',
    (tester) async {
      await pumpForm(
        tester,
        onSubmit: neverSubmit,
        // The provider throws → the dropdown degrades to a retryable error
        // instead of hanging on a spinner (the reported bug).
        typesError: Exception('boom'),
      );

      await selectCategory(tester, 'MANICURE');
      await tester.pumpAndSettle();

      // The closed field shows an error glyph, not a stranded spinner.
      expect(
        find.descendant(
          of: find.byKey(const Key('select-service-type-field')),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('select-service-type-field')),
          matching: find.byIcon(Icons.error_outline_rounded),
        ),
        findsOneWidget,
      );

      // Opening the menu surfaces an escapable error state with a Retry button.
      await openServiceTypeMenu(tester);
      expect(find.byKey(const Key('select-menu-error')), findsOneWidget);
      expect(find.byKey(const Key('select-menu-retry')), findsOneWidget);
      expect(find.byKey(const Key('select-menu-close')), findsOneWidget);
    },
  );

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

      // Open the dropdown and tap the actual rendered option — the 16.6 UI path.
      await selectServiceTypeOption(tester, 'type-xyz');

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

      // Select MANICURE, select the type via its dropdown option.
      await selectCategory(tester, 'MANICURE');
      await tester.pumpAndSettle();
      await selectServiceTypeOption(tester, 'type-xyz');
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

      await selectServiceTypeOption(tester, 'type-xyz');

      await tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('error-service-type')), findsOneWidget);
      expect(find.text('Тип не належить обраній категорії'), findsOneWidget);
    },
  );
}
