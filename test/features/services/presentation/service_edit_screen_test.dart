// Phase 5.4 — Widget tests for ServiceEditScreen.
//
// Strategy:
//   - Pump [ServiceEditScreen] inside a [ProviderScope] with overridden
//     [serviceRepositoryProvider] and [servicesListProvider].
//   - Cover all required cases from the phase spec.
//
// Coverage:
//   1. Form pre-populated from cached list (cache hit via servicesListProvider).
//   2. Form pre-populated via getMyService(id) on cache miss.
//   3. Price displays as "750" not "750.0".
//   4. Save calls update(id, patch) and invalidates servicesListProvider.
//   5. Error state shows with retry button when serviceByIdProvider errors.
//   6. Dirty-state marker visible after changing name, hidden when reverted.
//   7. ServicePhotoSlot shows empty state by default.
//   8. ServicePhotoSlot shows filled state when imageUrl is provided (widget test).

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/domain/master_service_input.dart';
import 'package:beautica_mobile/features/services/presentation/service_edit_screen.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_notifier.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_photo_slot.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Fakes + Mocks
// ---------------------------------------------------------------------------

class _FakeMasterServiceCreate extends Fake implements MasterServiceCreate {}

class _FakeMasterServiceUpdate extends Fake implements MasterServiceUpdate {}

class _MockServiceRepository extends Mock implements ServiceRepository {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// A representative service loaded by the edit screen.
const _stubService = MasterService(
  id: 'svc-edit-1',
  // serviceDefId is the id the update/deactivate endpoints key on — distinct
  // from the assignment id above.
  serviceDefId: 'def-edit-1',
  name: 'Стрижка жіноча',
  durationMinutes: 60,
  price: 750.0,
  // Category is required by the backend; the edit form pre-selects it so a
  // pristine save passes validation.
  category: 'HAIRCUT',
);

/// Resolves [AppLocalizations] from the currently-mounted widget tree.
AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(ServiceEditScreen)));

/// Overrides [serviceRepositoryProvider] so no HTTP calls are made.
///
/// [includeMasterProfile] — when true also overrides [masterProfileProvider]
/// with a stub notifier so tests that track its invalidation have an active
/// subscriber. Defaults to false so existing tests are unaffected.
List<Object> _overrides(
  _MockServiceRepository repo, {
  bool includeMasterProfile = false,
}) {
  return <Object>[
    serviceRepositoryProvider.overrideWithValue(repo),
    if (includeMasterProfile)
      masterProfileProvider.overrideWith(() => _StubMasterProfileNotifier()),
  ];
}

/// A minimal [ConsumerWidget] that watches [servicesListProvider] and appends
/// every received [AsyncValue] to [states]. Used to assert invalidation.
class _ListWatcher extends ConsumerWidget {
  const _ListWatcher({required this.child, required this.states});

  final Widget child;
  final List<AsyncValue<Object?>> states;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    states.add(ref.watch(servicesListProvider));
    return child;
  }
}

/// A minimal [ConsumerWidget] that watches [masterProfileProvider] and appends
/// every received [AsyncValue] to [states]. Used to assert masterProfileProvider
/// invalidation after save and delete operations.
class _MasterProfileWatcher extends ConsumerWidget {
  const _MasterProfileWatcher({required this.child, required this.states});

  final Widget child;
  final List<AsyncValue<Object?>> states;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    states.add(ref.watch(masterProfileProvider));
    return child;
  }
}

/// Stub [MasterProfile] notifier — resolves immediately with dummy data so
/// that [ref.invalidate] produces a visible AsyncData → AsyncLoading transition.
/// A never-completing future would keep the state at AsyncLoading, making
/// Riverpod's equality check suppress watcher notifications on re-invalidation.
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

/// Pumps [ServiceEditScreen] (for the given [id]) with the mocked repository.
///
/// [watcherStates] — when supplied a [_ListWatcher] wraps the screen so that
/// [servicesListProvider] has an active subscriber and its state transitions
/// are captured.
///
/// [masterProfileStates] — when supplied a [_MasterProfileWatcher] wraps the
/// screen (outside the list watcher) so that [masterProfileProvider] state
/// transitions are captured. Requires [includeMasterProfile] = true to also
/// install the stub notifier override.
Future<void> _pumpEdit(
  WidgetTester tester,
  _MockServiceRepository repo, {
  String id = 'svc-edit-1',
  List<AsyncValue<Object?>>? watcherStates,
  List<AsyncValue<Object?>>? masterProfileStates,
}) async {
  Widget screen = ServiceEditScreen(id: id);

  if (watcherStates != null) {
    screen = _ListWatcher(states: watcherStates, child: screen);
  }
  if (masterProfileStates != null) {
    screen = _MasterProfileWatcher(states: masterProfileStates, child: screen);
  }

  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(
        repo,
        includeMasterProfile: masterProfileStates != null,
      ).cast(),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('uk'),
        home: screen,
      ),
    ),
  );
  // One pump: provider resolves.
  await tester.pump();
  // Second pump: form renders.
  await tester.pump();
}

// ---------------------------------------------------------------------------
// Test group
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeMasterServiceCreate());
    registerFallbackValue(_FakeMasterServiceUpdate());
  });

  late _MockServiceRepository repo;

  setUp(() {
    repo = _MockServiceRepository();
    // Default: list succeeds, returning the stub service.
    when(
      () => repo.listMyServices(),
    ).thenAnswer((_) async => const <MasterService>[_stubService]);
    // Default: getMyService resolves for the stub id.
    when(
      () => repo.getMyService(_stubService.id),
    ).thenAnswer((_) async => _stubService);
    // Default: update succeeds. The screen calls update with the serviceDefId
    // and threads the assignment id through `assignmentId`.
    when(
      () => repo.update(
        _stubService.serviceDefId,
        any(),
        assignmentId: _stubService.id,
      ),
    ).thenAnswer((_) async => _stubService);
    // Default: deactivate succeeds (used in tests 7 & 8). Keyed on serviceDefId.
    when(
      () => repo.deactivate(_stubService.serviceDefId),
    ).thenAnswer((_) async {});
    // The category chip selector watches approvedCategoriesProvider, which
    // calls fetchApprovedCategories on the repository. Stub it so the form's
    // category row resolves to the data state.
    when(() => repo.fetchApprovedCategories()).thenAnswer(
      (_) async => const <ServiceCategoryOption>[
        ServiceCategoryOption(name: 'MANICURE', displayName: 'Манікюр'),
        ServiceCategoryOption(name: 'HAIRCUT', displayName: 'Стрижка'),
        ServiceCategoryOption(name: 'EYELASH', displayName: 'Вії'),
      ],
    );
  });

  // ── 1. Form pre-populated from cache ──────────────────────────────────────

  testWidgets('1. form pre-populated from cached list (cache hit)', (
    tester,
  ) async {
    await _pumpEdit(tester, repo);

    // servicesListProvider has data so serviceByIdProvider hits the cache.
    // The name field should be pre-filled with the stub service name.
    final nameField = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('field-service-name')),
        matching: find.byType(TextField),
      ),
    );
    expect(nameField.controller!.text, equals(_stubService.name));
  });

  // ── 2. Form pre-populated via getMyService on cache miss ──────────────────

  testWidgets('2. form pre-populated via getMyService on cache miss', (
    tester,
  ) async {
    // Return an empty list so serviceByIdProvider gets a cache miss.
    when(
      () => repo.listMyServices(),
    ).thenAnswer((_) async => const <MasterService>[]);

    await _pumpEdit(tester, repo);

    // Fallback path triggered: getMyService must have been called at least once.
    // (The provider may invoke it more than once during widget tree construction.)
    verify(
      () => repo.getMyService(_stubService.id),
    ).called(greaterThanOrEqualTo(1));

    final nameField = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('field-service-name')),
        matching: find.byType(TextField),
      ),
    );
    expect(nameField.controller!.text, equals(_stubService.name));
  });

  // ── 3. Price shows as "750" not "750.0" ───────────────────────────────────

  testWidgets('3. price displays as integer string not double', (tester) async {
    await _pumpEdit(tester, repo);

    final priceField = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('field-service-price')),
        matching: find.byType(TextField),
      ),
    );
    // Must be "750" not "750.0".
    expect(priceField.controller!.text, equals('750'));
    expect(priceField.controller!.text, isNot(contains('.')));
  });

  // ── 4. Save calls update(id, patch) and invalidates servicesListProvider ──

  testWidgets(
    '4. valid save calls update and invalidates servicesListProvider',
    (tester) async {
      final states = <AsyncValue<Object?>>[];
      await _pumpEdit(tester, repo, watcherStates: states);

      // The CTA may be off-screen due to the photo slot height. Ensure it is
      // visible before tapping by scrolling to it.
      await tester.ensureVisible(find.byKey(const Key('btn-submit-service')));
      await tester.pump();

      // All fields are already pre-filled from the stub service; tap save.
      await tester.tap(find.byKey(const Key('btn-submit-service')));
      await tester.pump();
      // Let the async update + invalidation + re-fetch complete.
      await tester.pumpAndSettle();

      // Must call update with the serviceDefId path id (not the assignment id)
      // and thread the assignment id through `assignmentId`.
      verify(
        () => repo.update(
          _stubService.serviceDefId,
          any(),
          assignmentId: _stubService.id,
        ),
      ).called(1);

      // The watcher should have received AsyncLoading after invalidation
      // (the provider re-fetches the list).
      final hasLoading = states.any((s) => s is AsyncLoading);
      expect(
        hasLoading,
        isTrue,
        reason:
            'servicesListProvider should have entered AsyncLoading after '
            'ref.invalidate()',
      );

      // Gap 8: a success SnackBar must be shown after a valid save.
      expect(find.byType(SnackBar), findsOneWidget);
    },
  );

  // ── 5. Error state shown with retry ───────────────────────────────────────

  testWidgets('5. error state with retry when serviceByIdProvider throws', (
    tester,
  ) async {
    // Return an empty list so serviceByIdProvider gets a cache miss,
    // then fail getMyService so the provider errors.
    when(
      () => repo.listMyServices(),
    ).thenAnswer((_) async => const <MasterService>[]);
    when(
      () => repo.getMyService(_stubService.id),
    ).thenThrow(const NotFoundFailure());

    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(repo).cast(),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('uk'),
          home: ServiceEditScreen(id: _stubService.id),
        ),
      ),
    );
    // Let the async provider chain settle fully.
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('service_edit_error_state')), findsOneWidget);
    expect(find.byKey(const Key('error_state_retry_button')), findsOneWidget);
  });

  // ── 6. Dirty-state marker ─────────────────────────────────────────────────

  testWidgets(
    '6. dirty marker appears after name change, disappears on revert',
    (tester) async {
      await _pumpEdit(tester, repo);
      final l10n = _l10n(tester);

      // Marker should be hidden initially (form pristine).
      expect(find.text(l10n.serviceUnsavedChanges), findsNothing);

      // Change the name field.
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('field-service-name')),
          matching: find.byType(TextField),
        ),
        'Нова назва',
      );
      await tester.pump();

      // Marker should now be visible.
      expect(find.text(l10n.serviceUnsavedChanges), findsOneWidget);

      // Revert the name to the baseline.
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('field-service-name')),
          matching: find.byType(TextField),
        ),
        _stubService.name,
      );
      await tester.pump();

      // Marker should be hidden again.
      expect(find.text(l10n.serviceUnsavedChanges), findsNothing);
    },
  );

  // ── 7. ServicePhotoSlot — empty state ────────────────────────────────────

  testWidgets('7. ServicePhotoSlot shows empty state when imageUrl is null', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('uk'),
        home: Scaffold(body: ServicePhotoSlot(key: Key('photo-slot'))),
      ),
    );
    await tester.pump();

    // Empty state: camera icon is present.
    expect(find.byIcon(Icons.add_a_photo_rounded), findsOneWidget);

    // FIX 2: the "Обкладинка сервісу у списку" cover subtitle was removed.
    expect(
      find.text('Обкладинка сервісу у списку'),
      findsNothing,
      reason: 'the cover-subtitle line must no longer render (FIX 2)',
    );
  });

  // ── 8. ServicePhotoSlot — filled state ───────────────────────────────────

  testWidgets(
    '8. ServicePhotoSlot shows filled state when imageUrl is provided',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('uk'),
          home: Scaffold(
            body: ServicePhotoSlot(
              key: Key('photo-slot-filled'),
              imageUrl: 'https://example.com/photo.jpg',
            ),
          ),
        ),
      );
      await tester.pump();

      // Filled state: change-photo camera icon is present.
      expect(find.byIcon(Icons.photo_camera_rounded), findsOneWidget);
      // The "add photo" camera icon must NOT be shown.
      expect(find.byIcon(Icons.add_a_photo_rounded), findsNothing);
    },
  );

  // ── 7. Tapping btn-delete-service opens the dialog ───────────────────────

  testWidgets('7. tapping btn-delete-service opens DeleteServiceDialog', (
    tester,
  ) async {
    await _pumpEdit(tester, repo);

    // The delete button should be visible in the loaded data state.
    expect(find.byKey(const Key('btn-delete-service')), findsOneWidget);

    // Tap the delete button.
    await tester.tap(find.byKey(const Key('btn-delete-service')));
    await tester.pumpAndSettle();

    // The dialog should now be open.
    expect(
      find.byKey(const Key('delete-service-dialog')),
      findsOneWidget,
      reason:
          'DeleteServiceDialog must be shown after tapping btn-delete-service',
    );

    // Dismiss with cancel to avoid dangling timer / dialog in subsequent tests.
    await tester.tap(find.byKey(const Key('btn-cancel-delete-service')));
    await tester.pumpAndSettle();
  });

  // ── 8. Confirming delete calls deactivate(id) and pops ───────────────────

  testWidgets(
    '8. confirming delete calls repository.deactivate(serviceDefId) and pops',
    (tester) async {
      await _pumpEdit(tester, repo);

      // Open the dialog.
      await tester.tap(find.byKey(const Key('btn-delete-service')));
      await tester.pumpAndSettle();

      // Confirm deletion.
      await tester.tap(find.byKey(const Key('btn-confirm-delete-service')));
      await tester.pumpAndSettle();

      // deactivate must have been called exactly once with the serviceDefId
      // (NOT the assignment id).
      verify(() => repo.deactivate(_stubService.serviceDefId)).called(1);
      verifyNever(() => repo.deactivate(_stubService.id));
    },
  );

  // ── Gap 9. masterProfileProvider invalidated after save ──────────────────

  testWidgets('gap 9. masterProfileProvider is invalidated after valid save', (
    tester,
  ) async {
    final masterProfileStates = <AsyncValue<Object?>>[];
    await _pumpEdit(tester, repo, masterProfileStates: masterProfileStates);

    await tester.ensureVisible(find.byKey(const Key('btn-submit-service')));
    await tester.pump();

    // All fields pre-filled; tap save.
    await tester.tap(find.byKey(const Key('btn-submit-service')));
    await tester.pump();
    await tester.pumpAndSettle();

    // masterProfileProvider must have emitted additional states (AsyncLoading
    // or a rebuild) after ref.invalidate(masterProfileProvider) is called on
    // the successful save path.
    expect(
      masterProfileStates.length,
      greaterThan(1),
      reason:
          'masterProfileProvider must be invalidated after a successful '
          'service save',
    );
  });

  // ── Gap 10. masterProfileProvider invalidated after confirmed delete ──────

  testWidgets(
    'gap 10. masterProfileProvider is invalidated after confirmed delete',
    (tester) async {
      final listStates = <AsyncValue<Object?>>[];
      final masterProfileStates = <AsyncValue<Object?>>[];
      await _pumpEdit(
        tester,
        repo,
        watcherStates: listStates,
        masterProfileStates: masterProfileStates,
      );

      // Open the delete dialog.
      await tester.tap(find.byKey(const Key('btn-delete-service')));
      await tester.pumpAndSettle();

      // Confirm deletion.
      await tester.tap(find.byKey(const Key('btn-confirm-delete-service')));
      await tester.pumpAndSettle();

      // servicesListProvider must have been invalidated (emitted AsyncLoading).
      final listHasLoading = listStates.any((s) => s is AsyncLoading);
      expect(
        listHasLoading,
        isTrue,
        reason:
            'servicesListProvider should be invalidated after confirmed delete',
      );

      // masterProfileProvider must also have been invalidated.
      expect(
        masterProfileStates.length,
        greaterThan(1),
        reason:
            'masterProfileProvider must be invalidated after confirmed delete',
      );
    },
  );

  // ── D. Category pre-populated from initial service ───────────────────────

  testWidgets(
    'D. category chip pre-populated from initial service (HAIRCUT shown selected)',
    (tester) async {
      // Stub service has category 'HAIRCUT'.
      const haircutService = MasterService(
        id: 'svc-haircut',
        serviceDefId: 'def-haircut',
        name: 'Стрижка',
        durationMinutes: 45,
        price: 400.0,
        category: 'HAIRCUT',
      );

      when(
        () => repo.listMyServices(),
      ).thenAnswer((_) async => const <MasterService>[haircutService]);
      when(
        () => repo.getMyService(haircutService.id),
      ).thenAnswer((_) async => haircutService);

      await _pumpEdit(tester, repo, id: haircutService.id);

      // The HAIRCUT chip must be in the widget tree.
      expect(
        find.byKey(const Key('chip-category-HAIRCUT')),
        findsOneWidget,
        reason: 'HAIRCUT chip must be rendered when category is pre-populated',
      );

      // The check icon inside the chip confirms it is in the selected state.
      expect(
        find.descendant(
          of: find.byKey(const Key('chip-category-HAIRCUT')),
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsOneWidget,
        reason:
            'HAIRCUT chip must show check icon when pre-populated as selected',
      );
    },
  );

  // ── E. Changing category triggers dirty marker ────────────────────────────

  testWidgets('E. changing category chip alone triggers dirty marker', (
    tester,
  ) async {
    // Stub service has category 'EYELASH'.
    const eyelashService = MasterService(
      id: 'svc-eyelash',
      serviceDefId: 'def-eyelash',
      name: 'Вії',
      durationMinutes: 90,
      price: 600.0,
      category: 'EYELASH',
    );

    when(
      () => repo.listMyServices(),
    ).thenAnswer((_) async => const <MasterService>[eyelashService]);
    when(
      () => repo.getMyService(eyelashService.id),
    ).thenAnswer((_) async => eyelashService);

    await _pumpEdit(tester, repo, id: eyelashService.id);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(ServiceEditScreen)),
    );

    // Dirty marker must NOT be visible when the form is pristine.
    expect(
      find.text(l10n.serviceUnsavedChanges),
      findsNothing,
      reason: 'dirty marker must be hidden for a pristine form',
    );

    // Tap a different category chip (HAIRCUT ≠ EYELASH).
    await tester.ensureVisible(find.byKey(const Key('chip-category-HAIRCUT')));
    await tester.tap(find.byKey(const Key('chip-category-HAIRCUT')));
    await tester.pump();

    // Dirty marker must now be visible.
    expect(
      find.text(l10n.serviceUnsavedChanges),
      findsOneWidget,
      reason:
          'dirty marker must appear after changing the category from the '
          'baseline value',
    );
  });

  // ── FIX 3. Changing category is persisted in the saved MasterServiceUpdate ─
  //
  // Regression: onSave previously built MasterServiceUpdate WITHOUT category,
  // so a category change silently never persisted. Assert the captured patch
  // carries the newly-selected slug.

  testWidgets(
    'FIX 3. changing category and saving sends category in MasterServiceUpdate',
    (tester) async {
      const manicureService = MasterService(
        id: 'svc-mani',
        serviceDefId: 'def-mani',
        name: 'Манікюр класичний',
        durationMinutes: 60,
        price: 500.0,
        category: 'MANICURE',
      );

      when(
        () => repo.listMyServices(),
      ).thenAnswer((_) async => const <MasterService>[manicureService]);
      when(
        () => repo.getMyService(manicureService.id),
      ).thenAnswer((_) async => manicureService);
      // Approved categories must include both MANICURE (baseline) and BROWS
      // (the new selection) so both chips render.
      when(() => repo.fetchApprovedCategories()).thenAnswer(
        (_) async => const <ServiceCategoryOption>[
          ServiceCategoryOption(name: 'MANICURE', displayName: 'Манікюр'),
          ServiceCategoryOption(name: 'BROWS', displayName: 'Брови'),
        ],
      );
      when(
        () => repo.update(
          manicureService.serviceDefId,
          any(),
          assignmentId: manicureService.id,
        ),
      ).thenAnswer((_) async => manicureService);

      await _pumpEdit(tester, repo, id: manicureService.id);

      // Switch category MANICURE → BROWS.
      await tester.ensureVisible(find.byKey(const Key('chip-category-BROWS')));
      await tester.tap(find.byKey(const Key('chip-category-BROWS')));
      await tester.pump();

      // Save.
      await tester.ensureVisible(find.byKey(const Key('btn-submit-service')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('btn-submit-service')));
      await tester.pump();
      await tester.pumpAndSettle();

      // Capture the patch passed to repository.update and assert its category.
      final captured =
          verify(
                () => repo.update(
                  manicureService.serviceDefId,
                  captureAny(),
                  assignmentId: manicureService.id,
                ),
              ).captured.single
              as MasterServiceUpdate;

      expect(
        captured.category,
        'BROWS',
        reason:
            'the newly-selected category must be threaded into '
            'MasterServiceUpdate (FIX 3)',
      );
    },
  );

  tearDownAll(() {});
}
