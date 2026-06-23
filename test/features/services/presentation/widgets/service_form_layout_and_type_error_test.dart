// Backlog QA closure (mobile-qa, service_form row) — two LOW findings:
//
//   1. serviceTypeId inline error (`Key('error-service-type')`) had NO widget-
//      level assertion. The `_ServiceTypeError` subtree only mounts once a
//      category is selected, and its message is sourced PURELY from a backend
//      ValidationFailure mapped onto the `serviceTypeId` wire key (Phase 16.3 —
//      there is no client-side validator because the service type is optional).
//      The test below drives that exact path: select a category (so the picker
//      + its error leaf mount), submit a form whose onSubmit throws a
//      ValidationFailure keyed `serviceTypeId`, and assert the keyed error row
//      renders the backend message inline (and not as a snackbar).
//
//   2. Horizontal RenderFlex overflow at ~320 dp width. The duration + pricing
//      wells share one horizontal Row (FIXED: 2 slots, RANGE: 3 slots), which is
//      the most overflow-prone part of the form at the narrowest supported
//      width. The test pumps ServiceForm at a 320-logical-pixel viewport in BOTH
//      pricing modes and asserts NO RenderFlex overflow — relying on the project
//      overflow guard (test/helpers/overflow_guard.dart, armed here via
//      [installOverflowGuard]) AND an explicit `tester.takeException()` null
//      check. If the form overflows at 320 dp this fails loudly rather than
//      silently passing.
//
// Isolation: fresh ProviderScope per pump; serviceRepositoryProvider +
// serviceTypesProvider overridden so no real HTTP fires. Fields/rows found by
// Key, never by localised label (M2). l10n strings resolved off the pumped tree.

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

import '../../../../helpers/overflow_guard.dart';
import 'select_dropdown_test_helpers.dart';

// ---------------------------------------------------------------------------
// Mocks + fallbacks
// ---------------------------------------------------------------------------

class _MockServiceRepository extends Mock implements ServiceRepository {}

class _FakeMasterServiceCreate extends Fake implements MasterServiceCreate {}

ServiceTypeOption _type(String id, String nameUk) => ServiceTypeOption(
  id: id,
  slug: id.toUpperCase(),
  nameUk: nameUk,
  categoryName: 'MANICURE',
);

// ---------------------------------------------------------------------------
// Finders (by Key — M2).
// ---------------------------------------------------------------------------

final _durationField = find.descendant(
  of: find.byKey(const Key('field-service-duration')),
  matching: find.byType(TextField),
);
final _fixedPriceField = find.descendant(
  of: find.byKey(const Key('pricing-fixed-amount')),
  matching: find.byType(TextField),
);

void main() {
  setUpAll(() => registerFallbackValue(_FakeMasterServiceCreate()));

  late _MockServiceRepository repo;

  // approvedCategoriesProvider is overridden directly below (it fetches via
  // categoryRequestApi, not the repo).
  const categories = <ServiceCategoryOption>[
    ServiceCategoryOption(name: 'MANICURE', displayName: 'Манікюр'),
  ];

  setUp(() {
    repo = _MockServiceRepository();
  });

  /// Pump [ServiceForm] inside a fresh ProviderScope. [size] sets the logical
  /// viewport (devicePixelRatio = 1.0 so logical == physical here).
  Future<void> pumpForm(
    WidgetTester tester, {
    required Future<void> Function(MasterServiceCreate) onSubmit,
    List<ServiceTypeOption> serviceTypes = const <ServiceTypeOption>[],
    Size size = const Size(800, 1400),
  }) async {
    tester.view.physicalSize = size;
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
            body: SingleChildScrollView(child: ServiceForm(onSubmit: onSubmit)),
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

  // =========================================================================
  // 1. serviceTypeId inline error — the keyed `error-service-type` row.
  // =========================================================================
  group('serviceTypeId inline error (Key error-service-type)', () {
    testWidgets(
      'backend serviceTypeId error renders inline on the keyed error row, '
      'not a snackbar',
      (tester) async {
        const serverMsg = 'Цей тип не належить до обраної категорії';
        final option = _type('type-xyz', 'Манікюр');

        await pumpForm(
          tester,
          // onSubmit rejects with a serviceTypeId-keyed ValidationFailure — the
          // only source of this inline error (no client-side validator exists).
          onSubmit: (_) async => throw const ValidationFailure(
            fieldErrors: <String, String>{'serviceTypeId': serverMsg},
          ),
          serviceTypes: <ServiceTypeOption>[option],
        );

        // Category first (mounts the service-type picker + its error leaf),
        // then a valid type + duration + price so client validation passes and
        // onSubmit actually fires.
        await selectCategoryOption(tester, 'MANICURE');
        (tester.state(find.byType(ServiceForm)) as dynamic)
            .onServiceTypeSelected(option);
        await tester.pump();
        await tester.enterText(_durationField, '60');
        await tester.enterText(_fixedPriceField, '500');
        await tapSubmit(tester);
        await tester.pumpAndSettle();

        // The keyed inline error row is present and carries the backend message.
        final errorRow = find.byKey(const Key('error-service-type'));
        expect(errorRow, findsOneWidget);
        expect(
          find.descendant(of: errorRow, matching: find.text(serverMsg)),
          findsOneWidget,
        );
        // Inline path — never the generic snackbar.
        expect(find.byType(SnackBar), findsNothing);
      },
    );

    testWidgets('no serviceTypeId error → the keyed error row is absent', (
      tester,
    ) async {
      await pumpForm(
        tester,
        onSubmit: (_) async {},
        serviceTypes: <ServiceTypeOption>[_type('t1', 'Манікюр')],
      );
      // Mount the picker (category selected) but never trigger a backend
      // serviceTypeId error — the error leaf must render nothing.
      await selectCategoryOption(tester, 'MANICURE');
      await tester.pump();

      expect(find.byKey(const Key('error-service-type')), findsNothing);
    });

    testWidgets('editing the name clears a stale serviceTypeId error '
        '(revalidate tick reflows the leaf)', (tester) async {
      const serverMsg = 'Цей тип не належить до обраної категорії';
      final option = _type('type-xyz', 'Манікюр');

      await pumpForm(
        tester,
        onSubmit: (_) async => throw const ValidationFailure(
          fieldErrors: <String, String>{'serviceTypeId': serverMsg},
        ),
        serviceTypes: <ServiceTypeOption>[option],
      );

      await selectCategoryOption(tester, 'MANICURE');
      (tester.state(find.byType(ServiceForm)) as dynamic).onServiceTypeSelected(
        option,
      );
      await tester.pump();
      await tester.enterText(_durationField, '60');
      await tester.enterText(_fixedPriceField, '500');
      await tapSubmit(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('error-service-type')), findsOneWidget);

      // Re-selecting the service type clears its server error (the handler
      // calls _clearServerError('serviceTypeId')); the leaf reflows to empty.
      (tester.state(find.byType(ServiceForm)) as dynamic).onServiceTypeSelected(
        option,
      );
      await tester.pump();

      expect(find.byKey(const Key('error-service-type')), findsNothing);
    });
  });

  // =========================================================================
  // 2. 320 dp horizontal-overflow regression guard.
  //    The overflow guard (overflow_guard.dart) records any RenderFlex overflow
  //    and fails in tearDown; [installOverflowGuard] arms that tearDown for THIS
  //    test (these tests pump ProviderScope directly, bypassing pump_app.dart's
  //    auto-arm). A belt-and-suspenders takeException() null check is added too.
  // =========================================================================
  group('320 dp no-overflow regression', () {
    testWidgets('FIXED mode renders at 320 dp with no RenderFlex overflow', (
      tester,
    ) async {
      installOverflowGuard();

      await pumpForm(
        tester,
        onSubmit: (_) async {},
        size: const Size(320, 900),
      );
      // Select a category so the service-type picker (an extra full-width row)
      // is also laid out at 320 dp — the worst case for horizontal pressure.
      await selectCategoryOption(tester, 'MANICURE');
      await tester.pumpAndSettle();

      // The duration + price wells share one Row in FIXED mode — assert it laid
      // out cleanly. The overflow guard's tearDown is the primary assertion;
      // takeException() is the explicit secondary check.
      expect(find.byKey(const Key('field-service-duration')), findsOneWidget);
      expect(find.byKey(const Key('pricing-fixed-amount')), findsOneWidget);
      expect(
        tester.takeException(),
        isNull,
        reason: 'ServiceForm must not overflow horizontally at 320 dp (FIXED)',
      );
    });

    testWidgets('RANGE mode renders at 320 dp with no RenderFlex overflow', (
      tester,
    ) async {
      installOverflowGuard();

      await pumpForm(
        tester,
        onSubmit: (_) async {},
        size: const Size(320, 900),
      );
      await selectCategoryOption(tester, 'MANICURE');
      // Switch to RANGE: duration + min + '–' + max share one Row — the densest
      // horizontal layout the form produces, and the likeliest to overflow.
      await tester.tap(find.byKey(const Key('pricing-toggle-range')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('field-service-duration')), findsOneWidget);
      expect(find.byKey(const Key('pricing-range-min')), findsOneWidget);
      expect(find.byKey(const Key('pricing-range-max')), findsOneWidget);
      expect(
        tester.takeException(),
        isNull,
        reason: 'ServiceForm must not overflow horizontally at 320 dp (RANGE)',
      );
    });
  });
}
