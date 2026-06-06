// Phase 5.3 — Widget tests for ServiceCreateScreen + ServiceForm.
//
// Strategy:
//   - Pump [ServiceCreateScreen] inside [pumpApp] (which wraps it in a minimal
//     ProviderScope + MaterialApp with UK l10n).
//   - Override [serviceRepositoryProvider] with a [_MockServiceRepository]
//     so no real HTTP calls are made.
//   - Tap the submit CTA and inspect field-level error text.
//
// Coverage:
//   1. Empty name shows errRequired / errNameRequired.
//   2. Empty duration (digitsOnly formatter blocks non-digits; leaving it empty
//      after submit shows errRequired).
//   3. Zero duration shows errDurationPositive.
//   4. Duration > 1440 shows errDurationMax.
//   5. Negative price blocked by FilteringTextInputFormatter (digits-only;
//      cannot type '-', so entering '-500' leaves the field as '500').
//   6. Valid submit calls repository.create() with the correct payload.
//   7. Submit button disabled during loading (CTA shows CircularProgressIndicator).
//   8. Empty price shows errRequired (MEDIUM-1).
//   9. servicesListProvider is invalidated after successful create (MEDIUM-2).
//  10. Server error shows SnackBar and screen stays visible (HIGH-2 regression).

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/master_service_input.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/domain/service_type_option.dart';
import 'package:beautica_mobile/features/services/presentation/service_create_screen.dart';
import 'package:beautica_mobile/features/services/presentation/service_types_provider.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_notifier.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'widgets/select_dropdown_test_helpers.dart';

// pump_app.dart intentionally not imported — this test pumps widgets directly.;

// ---------------------------------------------------------------------------
// Fakes + Mocks
// ---------------------------------------------------------------------------

class _FakeMasterServiceCreate extends Fake implements MasterServiceCreate {}

class _MockServiceRepository extends Mock implements ServiceRepository {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Stub [MasterService] returned by the mock on success.
const _stubService = MasterService(
  id: 'svc-new',
  serviceDefId: 'def-new',
  name: 'Тест',
  durationMinutes: 30,
  priceMin: 100,
  priceDisplay: '100 грн',
);

/// Resolves the [AppLocalizations] from the pumped widget tree.
AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(ServiceCreateScreen)));

/// A minimal [ConsumerWidget] that watches [servicesListProvider] and records
/// every [AsyncValue] state it receives.
///
/// Placed above [ServiceCreateScreen] in the widget tree so the provider is
/// kept alive (has an active subscriber). When the create screen calls
/// [ref.invalidate(servicesListProvider)] the provider rebuilds, posting a new
/// [AsyncLoading] value that this listener captures.
class _ListWatcher extends ConsumerWidget {
  const _ListWatcher({required this.child, required this.states});

  final Widget child;

  /// Mutable list populated by the watcher on every state change.
  final List<AsyncValue<Object?>> states;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(servicesListProvider);
    states.add(value);
    return child;
  }
}

/// A minimal [ConsumerWidget] that watches [masterProfileProvider] and appends
/// every received [AsyncValue] to [states]. Used to assert invalidation of
/// [masterProfileProvider] after a successful create.
class _MasterProfileWatcher extends ConsumerWidget {
  const _MasterProfileWatcher({required this.child, required this.states});

  final Widget child;

  /// Mutable list populated by the watcher on every state change.
  final List<AsyncValue<Object?>> states;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    states.add(ref.watch(masterProfileProvider));
    return child;
  }
}

/// Stub [MasterProfile] notifier — resolves immediately with dummy data so
/// [ref.invalidate] produces an observable AsyncData → AsyncLoading transition.
class _StubMasterProfileNotifier extends MasterProfile {
  static const _stub = Master(
    id: 'stub',
    firstName: 'T',
    lastName: 'T',
    avgRating: 0,
    reviewCount: 0,
    type: MasterType.independentMaster,
  );

  @override
  Future<Master> build() async => _stub;
}

// ---------------------------------------------------------------------------
// Provider overrides
// ---------------------------------------------------------------------------

/// Overrides [serviceRepositoryProvider] with [mock] in a [ProviderScope].
List<Object> _overrides(_MockServiceRepository mock) {
  return <Object>[
    serviceRepositoryProvider.overrideWithValue(mock),
    // Selecting a category mounts the second-level service-type dropdown →
    // serviceTypesProvider. Stub it to a calm empty list so no un-mocked fetch
    // fires in-tree (the dropdown then resolves to its empty state).
    serviceTypesProvider.overrideWith(
      (ref, String categoryName) async => const <ServiceTypeOption>[],
    ),
  ];
}

// ---------------------------------------------------------------------------
// Test group
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeMasterServiceCreate());
  });

  late _MockServiceRepository mockRepo;

  setUp(() {
    mockRepo = _MockServiceRepository();
    // Default stub: create succeeds.
    when(() => mockRepo.create(any())).thenAnswer((_) async => _stubService);
    // Default stub for listMyServices — used when _ListWatcher subscribes to
    // servicesListProvider in test 9.
    when(
      () => mockRepo.listMyServices(),
    ).thenAnswer((_) async => const <MasterService>[]);
    // The category chip selector in ServiceForm watches approvedCategoriesProvider
    // (which calls fetchApprovedCategories on the repository). Stub it so the
    // form's category row resolves to the data state in these tests.
    when(() => mockRepo.fetchApprovedCategories()).thenAnswer(
      (_) async => const <ServiceCategoryOption>[
        ServiceCategoryOption(name: 'MANICURE', displayName: 'Манікюр'),
        ServiceCategoryOption(name: 'HAIRCUT', displayName: 'Стрижка'),
      ],
    );
  });

  // Convenience: pump the screen.
  //
  // When [watcherStates] is provided, a [_ListWatcher] wraps the screen so
  // that [servicesListProvider] has an active subscriber and its state
  // transitions are recorded into [watcherStates].
  Future<void> pumpCreate(
    WidgetTester tester, {
    List<AsyncValue<Object?>>? watcherStates,
  }) async {
    // Phase 5.6: the PricingField expands the form height significantly. Set a
    // taller test viewport (1200 px) so that `ensureVisible` / `tap` on the
    // submit button is not at the edge of the visible area. The 1:1 pixel
    // ratio keeps coordinates directly comparable to logical pixels.
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final Widget screen = watcherStates != null
        ? _ListWatcher(
            states: watcherStates,
            child: const ServiceCreateScreen(),
          )
        : const ServiceCreateScreen();

    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(mockRepo).cast(),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('uk'),
          home: screen,
        ),
      ),
    );
    await tester.pump(); // settle initial build
  }

  // Convenience: scroll the submit button into view, then tap and settle.
  // ensureVisible is needed because the form may extend beyond the test viewport.
  // Phase 5.6: viewport is set to 1200px tall in pumpCreate so ensureVisible
  // positions the button well within hittable bounds.
  Future<void> tapSubmit(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('btn-submit-service')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('btn-submit-service')));
    await tester.pump();
  }

  // ---------------------------------------------------------------------------
  // 1. Empty name shows a required-field error after submit.
  // ---------------------------------------------------------------------------
  testWidgets('empty name shows required error after submit', (tester) async {
    await pumpCreate(tester);
    final l10n = _l10n(tester);

    // Leave name empty; fill valid duration and price.
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-service-duration')),
        matching: find.byType(TextField),
      ),
      '30',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('pricing-fixed-amount')),
        matching: find.byType(TextField),
      ),
      '100',
    );
    await tapSubmit(tester);

    expect(find.text(l10n.errRequired), findsWidgets);
  });

  // ---------------------------------------------------------------------------
  // 2. Empty duration shows errRequired after submit.
  // ---------------------------------------------------------------------------
  testWidgets('empty duration shows errRequired after submit', (tester) async {
    await pumpCreate(tester);
    final l10n = _l10n(tester);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-service-name')),
        matching: find.byType(TextField),
      ),
      'Манікюр',
    );
    // Leave duration empty.
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('pricing-fixed-amount')),
        matching: find.byType(TextField),
      ),
      '100',
    );
    await tapSubmit(tester);

    expect(find.text(l10n.errRequired), findsWidgets);
  });

  // ---------------------------------------------------------------------------
  // 3. Zero duration shows errDurationPositive.
  // ---------------------------------------------------------------------------
  testWidgets('zero duration shows errDurationPositive', (tester) async {
    await pumpCreate(tester);
    final l10n = _l10n(tester);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-service-name')),
        matching: find.byType(TextField),
      ),
      'Манікюр',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-service-duration')),
        matching: find.byType(TextField),
      ),
      '0',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('pricing-fixed-amount')),
        matching: find.byType(TextField),
      ),
      '100',
    );
    await tapSubmit(tester);

    expect(find.text(l10n.errDurationPositive), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // 4. Duration > 1440 shows errDurationMax.
  // ---------------------------------------------------------------------------
  testWidgets('duration > 1440 shows errDurationMax', (tester) async {
    await pumpCreate(tester);
    final l10n = _l10n(tester);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-service-name')),
        matching: find.byType(TextField),
      ),
      'Манікюр',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-service-duration')),
        matching: find.byType(TextField),
      ),
      '1441',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('pricing-fixed-amount')),
        matching: find.byType(TextField),
      ),
      '100',
    );
    await tapSubmit(tester);

    expect(find.text(l10n.errDurationMax), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // 5. Malformed price blocked by _DecimalPriceFormatter (hardened 2026-06-03).
  //    The formatter now accepts a decimal with ≤ 2 dp but REJECTS a sign or a
  //    third decimal place wholesale (keeps the previous valid value) rather
  //    than stripping mid-string.
  // ---------------------------------------------------------------------------
  testWidgets('price field rejects a leading sign and keeps decimals', (
    tester,
  ) async {
    await pumpCreate(tester);

    final priceFinder = find.descendant(
      of: find.byKey(const Key('pricing-fixed-amount')),
      matching: find.byType(TextField),
    );

    // A leading '-' makes the whole value malformed → rejected → stays empty.
    await tester.enterText(priceFinder, '-500');
    await tester.pump();
    expect(tester.widget<TextField>(priceFinder).controller?.text, '');

    // A valid 2-decimal amount is accepted as typed.
    await tester.enterText(priceFinder, '500.50');
    await tester.pump();
    expect(tester.widget<TextField>(priceFinder).controller?.text, '500.50');

    // A third decimal place is rejected → previous valid value retained.
    await tester.enterText(priceFinder, '500.505');
    await tester.pump();
    expect(tester.widget<TextField>(priceFinder).controller?.text, '500.50');
  });

  // ---------------------------------------------------------------------------
  // 6. Valid submit calls repository.create() with the correct payload.
  // ---------------------------------------------------------------------------
  testWidgets('valid submit calls repository.create with correct data', (
    tester,
  ) async {
    await pumpCreate(tester);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-service-name')),
        matching: find.byType(TextField),
      ),
      'Манікюр',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-service-duration')),
        matching: find.byType(TextField),
      ),
      '60',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('pricing-fixed-amount')),
        matching: find.byType(TextField),
      ),
      '500',
    );
    // Category is required by the backend — select the stubbed MANICURE chip.
    await tester.pumpAndSettle(); // resolve approvedCategoriesProvider
    await selectCategoryOption(tester, 'MANICURE');
    await tester.pump();
    await tapSubmit(tester);
    await tester.pumpAndSettle();

    final captured = verify(() => mockRepo.create(captureAny())).captured;
    expect(captured.length, 1);
    final input = captured.first as MasterServiceCreate;
    expect(input.name, 'Манікюр');
    expect(input.durationMinutes, 60);
    // Phase 5.6: FIXED mode, price goes to input.price.
    expect(input.priceType, ServicePriceType.fixed);
    expect(input.price, 500.0);
    expect(input.category, 'MANICURE');
    // Description must be null — not included in the form (user decision).
    expect(input.description, isNull);
  });

  // ---------------------------------------------------------------------------
  // 7. Submit button disabled during loading.
  // ---------------------------------------------------------------------------
  testWidgets(
    'submit button shows spinner and is inactive while create is in-flight',
    (tester) async {
      // Make create() never complete so we can inspect the loading state.
      final completer = Completer<MasterService>();
      when(() => mockRepo.create(any())).thenAnswer((_) => completer.future);

      await pumpCreate(tester);

      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('field-service-name')),
          matching: find.byType(TextField),
        ),
        'Манікюр',
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('field-service-duration')),
          matching: find.byType(TextField),
        ),
        '30',
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('pricing-fixed-amount')),
          matching: find.byType(TextField),
        ),
        '200',
      );
      // Category is required — select it via the dropdown (which settles the
      // category provider first, so the only CircularProgressIndicator below is
      // the CTA spinner).
      await selectCategoryOption(tester, 'MANICURE');

      await tapSubmit(tester);
      await tester.pump();

      // The NeumorphicButton renders a CircularProgressIndicator when loading.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Tapping again while loading must not trigger a second create() call.
      await tester.tap(
        find.byKey(const Key('btn-submit-service')),
        warnIfMissed: false,
      );
      await tester.pump();

      // Only the original call — no second invocation.
      verify(() => mockRepo.create(any())).called(1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Clean up: complete the future so the test teardown is tidy.
      completer.complete(_stubService);
    },
  );

  // ---------------------------------------------------------------------------
  // 8. Empty price shows errRequired (MEDIUM-1).
  // ---------------------------------------------------------------------------
  testWidgets('empty price shows errRequired after submit', (tester) async {
    await pumpCreate(tester);
    final l10n = _l10n(tester);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-service-name')),
        matching: find.byType(TextField),
      ),
      'Манікюр',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-service-duration')),
        matching: find.byType(TextField),
      ),
      '60',
    );
    // Leave price empty.
    await tapSubmit(tester);

    expect(find.text(l10n.errRequired), findsWidgets);
  });

  // ---------------------------------------------------------------------------
  // 9. servicesListProvider is invalidated after successful create (MEDIUM-2).
  //
  // Strategy: a [_ListWatcher] widget watches [servicesListProvider] so the
  // provider has an active subscriber. Before submit there is at least one
  // data/loading state. After [ref.invalidate(servicesListProvider)] the
  // provider restarts, emitting an [AsyncLoading] state. We assert that the
  // watcher received more than one state (initial + post-invalidate loading).
  // ---------------------------------------------------------------------------
  testWidgets('servicesListProvider is invalidated after successful create', (
    tester,
  ) async {
    final states = <AsyncValue<Object?>>[];

    await pumpCreate(tester, watcherStates: states);
    await tester
        .pumpAndSettle(); // settle the initial servicesListProvider load

    final int stateCountBefore = states.length;

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-service-name')),
        matching: find.byType(TextField),
      ),
      'Манікюр',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-service-duration')),
        matching: find.byType(TextField),
      ),
      '60',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('pricing-fixed-amount')),
        matching: find.byType(TextField),
      ),
      '500',
    );
    // Category is required — select the stubbed MANICURE chip.
    await selectCategoryOption(tester, 'MANICURE');
    await tester.pump();
    await tapSubmit(tester);
    await tester
        .pump(); // one frame — let Riverpod fire the invalidation rebuild
    await tester.pumpAndSettle(); // settle through loading → data

    // The provider must have emitted additional states after invalidation.
    // This confirms ref.invalidate(servicesListProvider) was called on the
    // create path — the only code that invalidates it is the onSubmit closure.
    expect(states.length, greaterThan(stateCountBefore));
  });

  // ---------------------------------------------------------------------------
  // 10. Server error shows SnackBar and screen stays visible (HIGH-2 regression).
  // ---------------------------------------------------------------------------
  testWidgets(
    'server error during create shows SnackBar and screen is not popped',
    (tester) async {
      when(() => mockRepo.create(any())).thenThrow(const ServerFailure());

      await pumpCreate(tester);
      await tester.pumpAndSettle(); // resolve approvedCategoriesProvider

      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('field-service-name')),
          matching: find.byType(TextField),
        ),
        'Манікюр',
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('field-service-duration')),
          matching: find.byType(TextField),
        ),
        '60',
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('pricing-fixed-amount')),
          matching: find.byType(TextField),
        ),
        '500',
      );
      // Category is required — select the stubbed MANICURE option.
      await selectCategoryOption(tester, 'MANICURE');
      await tapSubmit(tester);
      await tester.pumpAndSettle();

      // A SnackBar must appear.
      expect(find.byType(SnackBar), findsOneWidget);

      // The create screen must still be in the tree (not popped).
      expect(find.byType(ServiceCreateScreen), findsOneWidget);
    },
  );

  // ---------------------------------------------------------------------------
  // 11. Success SnackBar shown after valid create (gap 6).
  // ---------------------------------------------------------------------------
  testWidgets('success SnackBar is shown after a valid create', (tester) async {
    // Default stub: create() succeeds (set up in setUp).
    await pumpCreate(tester);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-service-name')),
        matching: find.byType(TextField),
      ),
      'Манікюр',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-service-duration')),
        matching: find.byType(TextField),
      ),
      '60',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('pricing-fixed-amount')),
        matching: find.byType(TextField),
      ),
      '500',
    );
    // Category is required — select the stubbed MANICURE chip.
    await tester.pumpAndSettle();
    await selectCategoryOption(tester, 'MANICURE');
    await tester.pump();
    await tapSubmit(tester);
    await tester.pumpAndSettle();

    // Resolve l10n from the pumped widget tree — no raw Ukrainian strings.
    final l10n = AppLocalizations.of(
      tester.element(find.byType(ServiceCreateScreen)),
    );

    // SnackBar must be visible after a successful create.
    expect(find.byType(SnackBar), findsOneWidget);
    // The SnackBar content must match the localised success message.
    expect(find.text(l10n.serviceCreatedSuccess), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // A. Select category chip — payload carries the selected category.
  // ---------------------------------------------------------------------------
  testWidgets('A. selecting a category chip sends it in the create payload', (
    tester,
  ) async {
    await pumpCreate(tester);
    await tester.pumpAndSettle(); // resolve approvedCategoriesProvider

    // Tap the MANICURE chip.
    await selectCategoryOption(tester, 'MANICURE');
    await tester.pumpAndSettle();

    // Fill the required text fields.
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-service-name')),
        matching: find.byType(TextField),
      ),
      'Манікюр',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-service-duration')),
        matching: find.byType(TextField),
      ),
      '60',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('pricing-fixed-amount')),
        matching: find.byType(TextField),
      ),
      '500',
    );
    await tapSubmit(tester);
    await tester.pumpAndSettle();

    final captured = verify(() => mockRepo.create(captureAny())).captured;
    expect(captured.length, 1);
    final input = captured.first as MasterServiceCreate;
    expect(
      input.category,
      'MANICURE',
      reason: 'category must equal the selected chip wire name',
    );
  });

  // ---------------------------------------------------------------------------
  // B. Submit without selecting a chip — category is REQUIRED, so submit is
  //    blocked and the required error is shown (backend @NotBlank contract).
  // ---------------------------------------------------------------------------
  testWidgets('B. submitting without a category shows the required error', (
    tester,
  ) async {
    await pumpCreate(tester);
    await tester.pumpAndSettle(); // resolve category provider

    final l10n = AppLocalizations.of(
      tester.element(find.byType(ServiceCreateScreen)),
    );

    // Fill valid fields only — do NOT tap any chip.
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-service-name')),
        matching: find.byType(TextField),
      ),
      'Педикюр',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-service-duration')),
        matching: find.byType(TextField),
      ),
      '45',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('pricing-fixed-amount')),
        matching: find.byType(TextField),
      ),
      '300',
    );
    await tapSubmit(tester);
    await tester.pumpAndSettle();

    // create() must NOT be called when no category is selected.
    verifyNever(() => mockRepo.create(any()));
    // The required-category error must be visible.
    expect(find.text(l10n.serviceCategoryRequired), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // C. Re-selecting the same category option keeps its wire slug on submit.
  //    (Dropdowns are select-only; clearing happens via category change, not by
  //    re-tapping. This locks that re-selection does not corrupt the wire value.)
  // ---------------------------------------------------------------------------
  testWidgets('C. re-selecting a category option submits the same wire slug', (
    tester,
  ) async {
    await pumpCreate(tester);

    // Select HAIRCUT via the dropdown, then re-select it a second time.
    await selectCategoryOption(tester, 'HAIRCUT');
    await selectCategoryOption(tester, 'HAIRCUT');

    // The closed field shows the Ukrainian label (not the raw slug).
    expect(
      find.descendant(
        of: find.byKey(const Key('select-category-field')),
        matching: find.text('Стрижка'),
      ),
      findsOneWidget,
    );

    // Fill valid fields and submit; category must be the re-selected slug.
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-service-name')),
        matching: find.byType(TextField),
      ),
      'Стрижка',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-service-duration')),
        matching: find.byType(TextField),
      ),
      '30',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('pricing-fixed-amount')),
        matching: find.byType(TextField),
      ),
      '200',
    );
    await tapSubmit(tester);
    await tester.pumpAndSettle();

    final captured = verify(() => mockRepo.create(captureAny())).captured;
    expect(captured.length, 1);
    final input = captured.first as MasterServiceCreate;
    expect(
      input.category,
      'HAIRCUT',
      reason:
          'after select → deselect → reselect, the submitted category must '
          'be the re-selected wire slug (toggle cycle is reversible)',
    );
  });

  // ---------------------------------------------------------------------------
  // 12. masterProfileProvider is invalidated after successful create (gap 7).
  // ---------------------------------------------------------------------------
  testWidgets('masterProfileProvider is invalidated after successful create', (
    tester,
  ) async {
    final masterStates = <AsyncValue<Object?>>[];

    final listStates = <AsyncValue<Object?>>[];
    final Widget screen = _MasterProfileWatcher(
      states: masterStates,
      child: _ListWatcher(
        states: listStates,
        child: const ServiceCreateScreen(),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._overrides(mockRepo),
          masterProfileProvider.overrideWith(
            () => _StubMasterProfileNotifier(),
          ),
        ].cast(),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('uk'),
          home: screen,
        ),
      ),
    );
    await tester.pump(); // settle initial build
    await tester.pumpAndSettle(); // settle initial provider load

    final int stateCountBefore = masterStates.length;

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-service-name')),
        matching: find.byType(TextField),
      ),
      'Манікюр',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-service-duration')),
        matching: find.byType(TextField),
      ),
      '60',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('pricing-fixed-amount')),
        matching: find.byType(TextField),
      ),
      '500',
    );
    // Category is required — select the stubbed MANICURE chip.
    await selectCategoryOption(tester, 'MANICURE');
    await tester.pump();
    await tapSubmit(tester);
    await tester.pump(); // let Riverpod fire the invalidation rebuild
    await tester.pumpAndSettle(); // settle through loading → data

    // masterProfileProvider must have emitted additional states after
    // ref.invalidate(masterProfileProvider) is called on the success path.
    expect(
      masterStates.length,
      greaterThan(stateCountBefore),
      reason:
          'masterProfileProvider must be invalidated after a successful '
          'service create',
    );
  });

  // ---------------------------------------------------------------------------
  // B2-RANGE-SUBMIT — RANGE mode submit carries correct payload (HIGH gap).
  // ---------------------------------------------------------------------------
  testWidgets(
    'B2-RANGE-SUBMIT: RANGE submit sends priceType=range, priceMin=400, '
    'priceMax=700, price=null',
    (tester) async {
      await pumpCreate(tester);
      await tester.pumpAndSettle(); // resolve approvedCategoriesProvider

      // Switch to RANGE mode.
      await tester.tap(find.byKey(const Key('pricing-toggle-range')));
      await tester.pump();
      await tester.pumpAndSettle(); // AnimatedSwitcher cross-fade

      // Fill min and max price fields.
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('pricing-range-min')),
          matching: find.byType(TextField),
        ),
        '400',
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('pricing-range-max')),
          matching: find.byType(TextField),
        ),
        '700',
      );

      // Fill required non-price fields.
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('field-service-name')),
          matching: find.byType(TextField),
        ),
        'Манікюр',
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('field-service-duration')),
          matching: find.byType(TextField),
        ),
        '60',
      );
      // Select category via the dropdown.
      await selectCategoryOption(tester, 'MANICURE');

      await tapSubmit(tester);
      await tester.pumpAndSettle();

      final captured = verify(() => mockRepo.create(captureAny())).captured;
      expect(captured.length, 1);
      final input = captured.first as MasterServiceCreate;
      expect(input.priceType, ServicePriceType.range);
      expect(input.priceMin, 400.0);
      expect(input.priceMax, 700.0);
      expect(input.price, isNull);
    },
  );

  // ---------------------------------------------------------------------------
  // B2-RANGE-VAL-MIN — Empty min in RANGE mode shows errPriceMinRequired (HIGH).
  // ---------------------------------------------------------------------------
  testWidgets(
    'B2-RANGE-VAL-MIN: empty range min shows errPriceMinRequired after submit',
    (tester) async {
      await pumpCreate(tester);
      await tester.pumpAndSettle();

      // Switch to RANGE mode.
      await tester.tap(find.byKey(const Key('pricing-toggle-range')));
      await tester.pump();
      await tester.pumpAndSettle();

      // Fill name, duration, max; leave min empty.
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('field-service-name')),
          matching: find.byType(TextField),
        ),
        'Педикюр',
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('field-service-duration')),
          matching: find.byType(TextField),
        ),
        '45',
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('pricing-range-max')),
          matching: find.byType(TextField),
        ),
        '700',
      );
      // Leave pricing-range-min empty.

      await tapSubmit(tester);
      await tester.pump();

      final l10n = _l10n(tester);
      expect(find.text(l10n.errPriceMinRequired), findsOneWidget);
      // create() must NOT be called when min is missing.
      verifyNever(() => mockRepo.create(any()));
    },
  );

  // ---------------------------------------------------------------------------
  // B2-RANGE-VAL-MAXGTMIN — min > max shows errPriceMaxGtMin (HIGH).
  // ---------------------------------------------------------------------------
  testWidgets(
    'B2-RANGE-VAL-MAXGTMIN: min=800 max=500 shows errPriceMaxGtMin after submit',
    (tester) async {
      await pumpCreate(tester);
      await tester.pumpAndSettle();

      // Switch to RANGE mode.
      await tester.tap(find.byKey(const Key('pricing-toggle-range')));
      await tester.pump();
      await tester.pumpAndSettle();

      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('field-service-name')),
          matching: find.byType(TextField),
        ),
        'Педикюр',
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('field-service-duration')),
          matching: find.byType(TextField),
        ),
        '45',
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('pricing-range-min')),
          matching: find.byType(TextField),
        ),
        '800',
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('pricing-range-max')),
          matching: find.byType(TextField),
        ),
        '500',
      );

      await tapSubmit(tester);
      await tester.pump();

      final l10n = _l10n(tester);
      expect(find.text(l10n.errPriceMaxGtMin), findsOneWidget);
      verifyNever(() => mockRepo.create(any()));
    },
  );

  // ---------------------------------------------------------------------------
  // 11. ScreenProtector lifecycle (security MS — anti-screenshot).
  //
  // ServiceCreateScreen is a ConsumerStatefulWidget that calls
  // ScreenProtector.preventScreenshotOn() in initState and ...Off() in dispose,
  // both guarded by !kDebugMode. Because kDebugMode == true under the test
  // binding, the platform-channel calls are intentionally skipped — so the
  // assertion is that mount AND unmount complete with no platform-channel
  // exception (the screen_protector MethodChannel is never invoked, mirroring
  // the DoneScreen ScreenProtector test pattern). This guards against a
  // regression where the guard is removed and the un-mocked channel throws.
  // ---------------------------------------------------------------------------
  testWidgets(
    'ScreenProtector guard: screen mounts and unmounts without a platform '
    'channel exception (kDebugMode skips preventScreenshotOn/Off)',
    (tester) async {
      await pumpCreate(tester);

      // Mounted cleanly — initState ran, no channel exception.
      expect(find.byType(ServiceCreateScreen), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Replace the screen so ServiceCreateScreen is disposed (dispose runs the
      // guarded preventScreenshotOff). Pump a bare app to unmount it.
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
      );
      await tester.pump();

      expect(find.byType(ServiceCreateScreen), findsNothing);
      expect(
        tester.takeException(),
        isNull,
        reason:
            'ServiceCreateScreen must dispose cleanly — the ScreenProtector '
            'call is guarded by !kDebugMode and never hits the platform channel',
      );
    },
  );
}
