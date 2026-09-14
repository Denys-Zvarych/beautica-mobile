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
//   Item 3 (M4). Changing the service type in the picker and saving sends the
//      NEW serviceTypeId in MasterServiceUpdate (no silent PATCH drop).

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/domain/service_type_option.dart';
import 'package:beautica_mobile/features/services/domain/master_service_input.dart';
import 'package:beautica_mobile/features/services/presentation/service_edit_screen.dart';
import 'package:beautica_mobile/features/services/presentation/service_types_provider.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_notifier.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_photo_slot.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'widgets/select_dropdown_test_helpers.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import '../../../helpers/velvet_snack_matchers.dart';

// ---------------------------------------------------------------------------
// Fakes + Mocks
// ---------------------------------------------------------------------------

class _FakeMasterServiceCreate extends Fake implements MasterServiceCreate {}

class _FakeMasterServiceUpdate extends Fake implements MasterServiceUpdate {}

class _MockServiceRepository extends Mock implements ServiceRepository {}

/// Records every route pop so a test can assert that [ServiceEditScreen]
/// popped itself. The screen's [_popServiceEditScreen] falls back to
/// `Navigator.maybePop` when there is no GoRouter ancestor (the plain
/// [MaterialApp] used here) — this observer captures that pop.
class _PopObserver extends NavigatorObserver {
  int popCount = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popCount++;
    super.didPop(route, previousRoute);
  }
}

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
  priceType: ServicePriceType.fixed,
  priceMin: 750.0,
  priceDisplay: '750 ₴',
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
/// The default approved-category list used by the edit form's category
/// dropdown. approvedCategoriesProvider now fetches DIRECTLY (not through the
/// repository), so it must be overridden in-scope. This mirrors the list the
/// pre-migration `fetchApprovedCategories` stub returned in setUp.
const _defaultCategories = <ServiceCategoryOption>[
  ServiceCategoryOption(name: 'MANICURE', displayName: 'Манікюр'),
  ServiceCategoryOption(name: 'HAIRCUT', displayName: 'Стрижка'),
  ServiceCategoryOption(name: 'EYELASH', displayName: 'Вії'),
];

List<Object> _overrides(
  _MockServiceRepository repo, {
  bool includeMasterProfile = false,
  List<ServiceCategoryOption> categories = _defaultCategories,
}) {
  return <Object>[
    serviceRepositoryProvider.overrideWithValue(repo),
    // The category dropdown watches approvedCategoriesProvider, which now
    // fetches DIRECTLY (not through the repository); override it in-scope so the
    // category row resolves to the data state.
    approvedCategoriesProvider.overrideWith((ref) async => categories),
    // The seeded service has a category, so _ServiceTypeChips mounts on pump
    // and would drive a real fetchServiceTypes for the seeded category (and any
    // category the test taps). Override with a calm empty list for every
    // category so no un-mocked fetch fires inside the form subtree.
    serviceTypesProvider.overrideWith(
      (ref, String categoryName) async => const <ServiceTypeOption>[],
    ),
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
  List<ServiceCategoryOption> categories = _defaultCategories,
  // Phase 320 (D1) — additive, defaults to `true` so every existing caller
  // (below) renders exactly as before.
  bool writable = true,
}) async {
  // The seeded service has a category, so the form mounts the second-level
  // _ServiceTypeChips section and grows taller. Use a roomy viewport so the
  // submit CTA and the category chips stay laid out and hit-testable after the
  // ensureVisible scroll (a shifted layout otherwise drops the tap).
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  Widget screen = ServiceEditScreen(id: id, writable: writable);

  if (watcherStates != null) {
    screen = _ListWatcher(states: watcherStates, child: screen);
  }
  if (masterProfileStates != null) {
    screen = _MasterProfileWatcher(states: masterProfileStates, child: screen);
  }

  await tester.pumpWidget(
    ProviderScope(
      retry: beauticaProviderRetry,
      overrides: _overrides(
        repo,
        includeMasterProfile: masterProfileStates != null,
        categories: categories,
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
  // Settle the second-level serviceTypesProvider future so the _ServiceTypeChips
  // section reaches its final (empty) layout BEFORE any ensureVisible/tap. Left
  // pending, it would resolve mid-interaction and shift the submit CTA, dropping
  // the tap (hit-test miss).
  await tester.pumpAndSettle();
}

/// Pumps [ServiceEditScreen] WITHOUT settling, leaving [serviceByIdProvider]
/// unresolved so the screen renders its loading branch.
///
/// [listMyServices] is held on a never-completing future by the caller so the
/// provider stays in [AsyncLoading]; a single [pump] flushes the initial build
/// (the spinner) but does not drain microtasks, so the loading scaffold is the
/// rendered state when control returns.
Future<void> _pumpEditLoading(
  WidgetTester tester,
  _MockServiceRepository repo, {
  String id = 'svc-edit-1',
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      retry: beauticaProviderRetry,
      overrides: _overrides(repo).cast(),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('uk'),
        home: ServiceEditScreen(id: id),
      ),
    ),
  );
  // A single pump flushes the first frame (loading scaffold) without draining
  // the pending list/getMyService futures, so the spinner is the rendered state.
  await tester.pump();
}

/// Pumps [ServiceEditScreen] as a SECOND route pushed onto a Navigator, so the
/// screen's `Navigator.maybePop` fallback (used when there is no GoRouter
/// ancestor) has a route beneath it to pop back to. The returned [_PopObserver]
/// records every pop, letting a test assert that the edit screen popped itself
/// on cancel / after a confirmed delete.
///
/// A starter button on the first route pushes the edit screen; we tap it,
/// settle, and hand control back with the screen mounted.
///
/// [watcherStates] — when supplied, the pushed [ServiceEditScreen] is wrapped
/// in a [_ListWatcher] so `servicesListProvider` has an active subscriber and
/// an `invalidate()` on it actually manifests as an observable re-emission
/// (an invalidate with NO subscriber marks the provider dirty but triggers no
/// refetch until something reads it — a test asserting `verifyNever(() =>
/// repo.listMyServices())` with no watcher attached would pass regardless of
/// whether the invalidate call was ever made, which is vacuous). Defaults to
/// `null` so the five existing callers (L1-L5) are unaffected.
Future<_PopObserver> _pumpEditInNavigator(
  WidgetTester tester,
  _MockServiceRepository repo, {
  String id = 'svc-edit-1',
  List<AsyncValue<Object?>>? watcherStates,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final observer = _PopObserver();

  await tester.pumpWidget(
    ProviderScope(
      retry: beauticaProviderRetry,
      overrides: _overrides(repo).cast(),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('uk'),
        navigatorObservers: <NavigatorObserver>[observer],
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const Key('open-edit'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) {
                      Widget screen = ServiceEditScreen(id: id);
                      if (watcherStates != null) {
                        screen = _ListWatcher(
                          states: watcherStates,
                          child: screen,
                        );
                      }
                      return screen;
                    },
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();

  // Push the edit screen onto the stack.
  await tester.tap(find.byKey(const Key('open-edit')));
  await tester.pumpAndSettle();
  expect(find.byType(ServiceEditScreen), findsOneWidget);

  return observer;
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
    // The category chip selector watches approvedCategoriesProvider, which now
    // fetches DIRECTLY (not through the repository). It is overridden in-scope
    // via _overrides(categories: ...) with _defaultCategories, so no repository
    // stub is needed here.
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

  // ── 3. Price pre-fills as "750" (FIXED mode) not "750.0" ────────────────────
  //
  // Phase 5.6: the single price field was replaced by PricingField. For a FIXED
  // service the toggle opens in FIXED mode and the fixed-amount field is pre-filled
  // from priceMin. The test checks via the pricing-fixed-amount inset key.

  testWidgets('3. price displays as integer string not double', (tester) async {
    await _pumpEdit(tester, repo);

    // The fixed-amount field is keyed as 'pricing-fixed-amount' inside PricingField.
    final priceField = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('pricing-fixed-amount')),
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

      // Gap 8: a success VelvetSnack must be shown after a valid save.
      final l10n = _l10n(tester);
      expectVelvetSnack(
        l10n.serviceUpdatedSuccess,
        variant: VelvetSnackVariant.success,
      );
      await pumpPastVelvetSnack(tester);
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
        retry: beauticaProviderRetry,
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

  // ── Gap 9. Save fan-out is TRIMMED to the service catalogues ─────────────
  //
  // Rewritten (phase 316, mobile-perf LOW). The save path used to also
  // `ref.invalidate(masterProfileProvider)`, buying a redundant
  // `GET /masters/me` on every rename / reprice / recategorize — none of which
  // moves a field on [Master] (`master.dart` carries nothing service-derived)
  // — and leaving the two writes on this screen fanning out asymmetrically
  // after `_onDelete` was trimmed. The profile screen's services stat tile and
  // category section watch `servicesListProvider` directly
  // (`master_profile_screen.dart:505,746`), which the catalogue invalidation
  // already covers.
  //
  // The PREVIOUS assertion here was VACUOUS, in exactly the way gap 10's was:
  // it read `masterProfileStates.length > 1`, and the stub notifier's `async
  // build()` emits `AsyncLoading` → `AsyncData` at MOUNT, so the expectation
  // was already satisfied before the save happened. Verified empirically —
  // with `ref.invalidate(masterProfileProvider)` deleted from the save path,
  // the old test still passed. This version counts from a post-mount baseline
  // and pins BOTH halves: the catalogues are invalidated, the profile is not.

  testWidgets(
    'gap 9. a valid save invalidates the service catalogues and does NOT '
    'invalidate masterProfileProvider',
    (tester) async {
      final listStates = <AsyncValue<Object?>>[];
      final masterProfileStates = <AsyncValue<Object?>>[];
      await _pumpEdit(
        tester,
        repo,
        watcherStates: listStates,
        masterProfileStates: masterProfileStates,
      );

      // Baseline: whatever each watcher saw while the screen mounted
      // (AsyncLoading → AsyncData). Counting from HERE rather than asserting an
      // absolute length is what stops the mount transitions from satisfying the
      // assertion on their own — the defect this rewrite removes.
      final int profileStatesBeforeSave = masterProfileStates.length;
      final int listStatesBeforeSave = listStates.length;

      // Drain the mount-time list fetches so the verification after the save
      // counts ONLY what the save caused. mocktail excludes already-verified
      // invocations from later `verify` calls, which is what makes the
      // post-save `called(1)` an exact figure rather than a running total.
      verify(() => repo.listMyServices()).called(greaterThanOrEqualTo(1));

      await tester.ensureVisible(find.byKey(const Key('btn-submit-service')));
      await tester.pump();

      // All fields pre-filled; tap save.
      await tester.tap(find.byKey(const Key('btn-submit-service')));
      await tester.pump();
      await tester.pumpAndSettle();

      // The PATCH fired — without this the assertions below would pass on a
      // save that never happened.
      verify(
        () => repo.update(
          _stubService.serviceDefId,
          any(),
          assignmentId: _stubService.id,
        ),
      ).called(1);

      // servicesListProvider must have been invalidated — proven by the REFETCH
      // it causes, exactly once. `any((s) => s is AsyncLoading)` would not work
      // here: a seamless invalidate emits `AsyncData(previous, isLoading: true)`
      // rather than `AsyncLoading` (project_riverpod_seamless_invalidate_gotcha)
      // and that flag is already back to false by the frame the watcher
      // rebuilds on.
      verify(() => repo.listMyServices()).called(1);
      expect(
        listStates.length,
        greaterThan(listStatesBeforeSave),
        reason:
            'servicesListProvider should re-emit to its watchers after a '
            'successful save invalidates it',
      );

      // masterProfileProvider must NOT be invalidated: an edit cannot change
      // anything [Master] carries. Asserting the watcher saw no NEW state is
      // the non-vacuous form — `ref.invalidate` retains `.value`
      // (project_riverpod_seamless_invalidate_gotcha), so asserting
      // "still has data" would pass even after an invalidation.
      expect(
        masterProfileStates.length,
        profileStatesBeforeSave,
        reason:
            'masterProfileProvider must NOT be invalidated by a service save '
            '— Master carries no service-derived field, and the profile '
            'surfaces read services through servicesListProvider',
      );
    },
  );

  // ── Gap 10. Delete fan-out is TRIMMED to the service catalogues ───────────
  //
  // Rewritten (phase 316, mobile-perf MEDIUM): the delete path used to also
  // `ref.invalidate(masterProfileProvider)`, buying a redundant `GET
  // /masters/me` — and, with a salon target in scope, refetching the
  // OPERATOR's profile rather than the unassigned master's. [Master] carries
  // no service-derived field and the profile screen's services section watches
  // `servicesListProvider` directly, so the catalogue invalidation below is
  // the complete fan-out. This test now pins BOTH halves: the catalogues are
  // invalidated, the profile is not.
  //
  // The SAVE path carries the identical trim (gap 9), so the two writes on this
  // screen no longer fan out asymmetrically.

  testWidgets(
    'gap 10. confirmed delete invalidates the service catalogues and does '
    'NOT invalidate masterProfileProvider',
    (tester) async {
      final listStates = <AsyncValue<Object?>>[];
      final masterProfileStates = <AsyncValue<Object?>>[];
      await _pumpEdit(
        tester,
        repo,
        watcherStates: listStates,
        masterProfileStates: masterProfileStates,
      );

      // Baseline: whatever the profile watcher saw while the screen mounted
      // (AsyncLoading → AsyncData). Counting from HERE rather than asserting an
      // absolute length keeps the test honest about the mount transitions
      // without letting a post-delete invalidation hide inside them.
      final int profileStatesBeforeDelete = masterProfileStates.length;
      final int listStatesBeforeDelete = listStates.length;

      // Drain the mount-time list fetches so the verification after the delete
      // counts ONLY what the delete caused. mocktail excludes already-verified
      // invocations from later `verify` calls, which is what makes the
      // post-delete `called(1)` an exact figure rather than a running total.
      verify(() => repo.listMyServices()).called(greaterThanOrEqualTo(1));

      // Open the delete dialog.
      await tester.tap(find.byKey(const Key('btn-delete-service')));
      await tester.pumpAndSettle();

      // Confirm deletion.
      await tester.tap(find.byKey(const Key('btn-confirm-delete-service')));
      await tester.pumpAndSettle();

      // servicesListProvider must have been invalidated — proven by the REFETCH
      // it causes, exactly once.
      //
      // Two traps this replaces. The previous shape was
      // `listStates.any((s) => s is AsyncLoading)` over the WHOLE list, which
      // the mount-time AsyncLoading satisfied for free: it passed whether or
      // not the delete invalidated anything. And narrowing it to the states
      // observed after the delete does not rescue it, because a seamless
      // invalidate emits `AsyncData(previous, isLoading: true)` rather than
      // `AsyncLoading` (project_riverpod_seamless_invalidate_gotcha) AND that
      // flag is already back to false by the frame the watcher rebuilds on —
      // the widget never observes it at all.
      //
      // `called(1)` is also what pins the TRIMMED fan-out: before this phase,
      // `ref.invalidate(masterProfileProvider)` on this path rebuilt
      // `serviceRepositoryProvider` (watched by `services_list_notifier.dart`)
      // and cascaded a SECOND `listMyServices()`.
      verify(() => repo.listMyServices()).called(1);
      expect(
        listStates.length,
        greaterThan(listStatesBeforeDelete),
        reason:
            'servicesListProvider should re-emit to its watchers after a '
            'confirmed delete invalidates it',
      );

      // masterProfileProvider must NOT be invalidated: the delete cannot change
      // anything the profile carries. Asserting the watcher saw no NEW state is
      // the non-vacuous form — `ref.invalidate` retains `.value`
      // (project_riverpod_seamless_invalidate_gotcha), so asserting
      // "still has data" would pass even after an invalidation.
      expect(
        masterProfileStates.length,
        profileStatesBeforeDelete,
        reason:
            'masterProfileProvider must NOT be invalidated by a service '
            'delete — Master carries no service-derived field, and in salon '
            'mode GET /masters/me reads the operator, not the target master',
      );
    },
  );

  // ── Gap 10b. Double tap issues exactly ONE delete ─────────────────────────

  testWidgets(
    'gap 10b. a second delete tap while the first DELETE is in flight is '
    'dropped — deactivate fires once and no error snack is shown',
    (tester) async {
      // The DELETE is held open on a Completer so the second tap provably
      // overlaps the FIRST call's pending future. A test that taps twice after
      // the first call already resolved proves nothing.
      final deleteGate = Completer<void>();
      var deactivateCalls = 0;
      when(() => repo.deactivate(_stubService.serviceDefId)).thenAnswer((_) {
        deactivateCalls++;
        return deleteGate.future;
      });

      await _pumpEdit(tester, repo);

      // Tap 1 → dialog → confirm. The dialog dismissal settles; the DELETE
      // stays pending (a pending Future is not an animation, so pumpAndSettle
      // returns without draining it).
      await tester.tap(find.byKey(const Key('btn-delete-service')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn-confirm-delete-service')));
      await tester.pumpAndSettle();

      // NON-VACUITY PIN: the first DELETE has been issued and has NOT resolved.
      // If either of these fails the overlap the test claims to exercise did
      // not happen and every assertion below is worthless.
      expect(
        deactivateCalls,
        1,
        reason: 'the first DELETE must already be in flight',
      );
      expect(
        deleteGate.isCompleted,
        isFalse,
        reason: 'the first DELETE must still be pending at the second tap',
      );
      // The screen is still mounted and the delete icon is hit-testable again —
      // the dialog barrier is gone, which is exactly why a user can double tap.
      expect(find.byKey(const Key('btn-delete-service')), findsOneWidget);

      // Tap 2, mid-flight. The in-flight guard drops it before showDialog, so
      // no second confirmation dialog opens and no second DELETE is issued.
      await tester.tap(find.byKey(const Key('btn-delete-service')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('delete-service-dialog')),
        findsNothing,
        reason:
            'the re-entrancy guard must drop the second tap before the '
            'confirmation dialog is shown',
      );

      // Release the first DELETE.
      deleteGate.complete();
      await tester.pumpAndSettle();

      expect(
        deactivateCalls,
        1,
        reason: 'a double tap must issue exactly one DELETE',
      );
      verify(() => repo.deactivate(_stubService.serviceDefId)).called(1);

      // And no error snackbar: the pre-guard behaviour was a second DELETE
      // answering 404 → NotFoundFailure → an error snack for a delete that
      // SUCCEEDED (phase 316 D2).
      expect(
        find.byType(VelvetSnack),
        findsNothing,
        reason: 'a successful delete must not surface an error snack',
      );
    },
  );

  // ── D. Category pre-populated from initial service ───────────────────────

  testWidgets(
    'D. category pre-populated from initial service (HAIRCUT label shown in '
    'the closed dropdown field)',
    (tester) async {
      // Stub service has category 'HAIRCUT'.
      const haircutService = MasterService(
        id: 'svc-haircut',
        serviceDefId: 'def-haircut',
        name: 'Стрижка',
        durationMinutes: 45,
        priceMin: 400.0,
        priceDisplay: '400 ₴',
        category: 'HAIRCUT',
      );

      when(
        () => repo.listMyServices(),
      ).thenAnswer((_) async => const <MasterService>[haircutService]);
      when(
        () => repo.getMyService(haircutService.id),
      ).thenAnswer((_) async => haircutService);

      await _pumpEdit(tester, repo, id: haircutService.id);

      // The closed category dropdown field shows the pre-populated selection's
      // Ukrainian label ('Стрижка' for HAIRCUT), proving it loaded as selected.
      // (Service name is also 'Стрижка', so scope to the category field.)
      expect(
        find.descendant(
          of: find.byKey(const Key('select-category-field')),
          matching: find.text('Стрижка'),
        ),
        findsOneWidget,
        reason: 'category field must show the pre-populated HAIRCUT label',
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
      priceMin: 600.0,
      priceDisplay: '600 ₴',
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

    // Select a different category via the dropdown (HAIRCUT ≠ EYELASH).
    await selectCategoryOption(tester, 'HAIRCUT');

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
        priceMin: 500.0,
        priceDisplay: '500 ₴',
        category: 'MANICURE',
      );

      when(
        () => repo.listMyServices(),
      ).thenAnswer((_) async => const <MasterService>[manicureService]);
      when(
        () => repo.getMyService(manicureService.id),
      ).thenAnswer((_) async => manicureService);
      when(
        () => repo.update(
          manicureService.serviceDefId,
          any(),
          assignmentId: manicureService.id,
        ),
      ).thenAnswer((_) async => manicureService);

      // Approved categories must include both MANICURE (baseline) and BROWS
      // (the new selection) so both chips render.
      await _pumpEdit(
        tester,
        repo,
        id: manicureService.id,
        categories: const <ServiceCategoryOption>[
          ServiceCategoryOption(name: 'MANICURE', displayName: 'Манікюр'),
          ServiceCategoryOption(name: 'BROWS', displayName: 'Брови'),
        ],
      );

      // Switch category MANICURE → BROWS via the dropdown.
      await selectCategoryOption(tester, 'BROWS');

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

  // ── Item 3 (M4). Changing the service type in the picker and saving sends
  //    the NEW serviceTypeId in MasterServiceUpdate ──────────────────────────
  //
  // Regression guard for the silent-drop bug: the picker was editable in the UI
  // but the chosen serviceTypeId never reached repository.update (dropped on the
  // PATCH). This drives the full flow — open the service-type menu, pick a
  // different type, save — and asserts the captured patch carries the new id.
  // Uses a bespoke ProviderScope because the shared `_overrides` stubs
  // serviceTypesProvider to an empty list (no selectable option to tap).

  testWidgets(
    'Item 3. changing the service type in the picker and saving sends the new '
    'serviceTypeId in MasterServiceUpdate (M4 — no silent drop)',
    (tester) async {
      const editService = MasterService(
        id: 'svc-st-1',
        serviceDefId: 'def-st-1',
        name: 'Манікюр',
        durationMinutes: 60,
        priceType: ServicePriceType.fixed,
        priceMin: 500.0,
        priceDisplay: '500 ₴',
        category: 'MANICURE',
        // Loaded with one type; the test switches to another.
        serviceTypeId: 'type-old',
        serviceTypeNameUk: 'Класичний манікюр',
      );

      const newType = ServiceTypeOption(
        id: 'type-new',
        slug: 'HARDWARE_MANICURE',
        nameUk: 'Апаратний манікюр',
        categoryName: 'MANICURE',
      );

      when(
        () => repo.listMyServices(),
      ).thenAnswer((_) async => const <MasterService>[editService]);
      when(
        () => repo.getMyService(editService.id),
      ).thenAnswer((_) async => editService);
      when(
        () => repo.update(
          editService.serviceDefId,
          any(),
          assignmentId: editService.id,
        ),
      ).thenAnswer((_) async => editService);

      // Roomy viewport so the service-type field + submit CTA stay hittable.
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          retry: beauticaProviderRetry,
          overrides: [
            serviceRepositoryProvider.overrideWithValue(repo),
            // approvedCategoriesProvider fetches directly now — override it here
            // with the single MANICURE category this test selects.
            approvedCategoriesProvider.overrideWith(
              (ref) async => const <ServiceCategoryOption>[
                ServiceCategoryOption(name: 'MANICURE', displayName: 'Манікюр'),
              ],
            ),
            // The selected MANICURE category surfaces the new type in the
            // second-level picker so it can be tapped.
            serviceTypesProvider.overrideWith(
              (ref, String categoryName) async => const <ServiceTypeOption>[
                newType,
              ],
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('uk'),
            home: ServiceEditScreen(id: 'svc-st-1'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      // Switch the service type type-old → type-new via the picker.
      await selectServiceTypeOption(tester, 'type-new');

      // Save.
      await tester.ensureVisible(find.byKey(const Key('btn-submit-service')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('btn-submit-service')));
      await tester.pump();
      await tester.pumpAndSettle();

      final captured =
          verify(
                () => repo.update(
                  editService.serviceDefId,
                  captureAny(),
                  assignmentId: editService.id,
                ),
              ).captured.single
              as MasterServiceUpdate;

      expect(
        captured.serviceTypeId,
        'type-new',
        reason:
            'the newly-picked serviceTypeId must reach repository.update — '
            'M4 guard against the silent PATCH drop',
      );
    },
  );

  // ── B3. RANGE pre-fill (HIGH gap) ─────────────────────────────────────────
  //
  // Pumps the edit screen with a RANGE service and verifies:
  //   - The toggle rests on RANGE (range fields visible, fixed field absent).
  //   - pricing-range-min pre-fills from priceMin.
  //   - pricing-range-max pre-fills from priceMax.

  testWidgets(
    'B3. RANGE service pre-fills toggle in RANGE mode with correct min/max',
    (tester) async {
      const rangeService = MasterService(
        id: 'svc-range-1',
        serviceDefId: 'def-range-1',
        name: 'Процедура',
        durationMinutes: 60,
        priceType: ServicePriceType.range,
        priceMin: 500.0,
        priceMax: 800.0,
        priceDisplay: 'від 500 до 800 ₴',
      );

      when(
        () => repo.listMyServices(),
      ).thenAnswer((_) async => const <MasterService>[rangeService]);
      when(
        () => repo.getMyService(rangeService.id),
      ).thenAnswer((_) async => rangeService);

      await _pumpEdit(tester, repo, id: rangeService.id);

      // Toggle rests on RANGE: range fields visible, fixed field absent.
      expect(find.byKey(const Key('pricing-range-min')), findsOneWidget);
      expect(find.byKey(const Key('pricing-range-max')), findsOneWidget);
      expect(find.byKey(const Key('pricing-fixed-amount')), findsNothing);

      // Min field text must equal '500' (integer, not '500.0').
      final minField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('pricing-range-min')),
          matching: find.byType(TextField),
        ),
      );
      expect(minField.controller!.text, equals('500'));

      // Max field text must equal '800'.
      final maxField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('pricing-range-max')),
          matching: find.byType(TextField),
        ),
      );
      expect(maxField.controller!.text, equals('800'));
    },
  );

  // ── L1. Loading state — spinner shown while serviceByIdProvider resolves ──
  //
  // Gap (mobile-qa M3): the loading branch of asyncService.when was never
  // pumped. Hold the underlying list fetch on a never-completing future so the
  // provider stays in AsyncLoading, then assert the keyed spinner renders.

  testWidgets(
    'L1. shows loading spinner while serviceByIdProvider is unresolved',
    (tester) async {
      // Both data sources hang so serviceByIdProvider never leaves AsyncLoading.
      final never = Completer<List<MasterService>>();
      when(() => repo.listMyServices()).thenAnswer((_) => never.future);
      final neverOne = Completer<MasterService>();
      when(
        () => repo.getMyService(_stubService.id),
      ).thenAnswer((_) => neverOne.future);

      await _pumpEditLoading(tester, repo);

      // The keyed loading spinner from the screen's loading branch must render,
      // and the loaded form chrome (cancel/delete buttons) must NOT be present.
      expect(find.byKey(const Key('edit_service_loading')), findsOneWidget);
      expect(find.byKey(const Key('btn-cancel-service-edit')), findsNothing);
      expect(find.byKey(const Key('btn-delete-service')), findsNothing);

      // Complete the futures so no pending-timer leak is reported on teardown.
      never.complete(const <MasterService>[_stubService]);
      neverOne.complete(_stubService);
      await tester.pumpAndSettle();
    },
  );

  // ── L2. Cancel-tap pops the screen without saving ────────────────────────
  //
  // Gap (mobile-qa): tapping the top-bar cancel icon must pop the route via
  // the Navigator.maybePop fallback and must NOT call repository.update.

  testWidgets('L2. tapping cancel pops the screen without calling update', (
    tester,
  ) async {
    final observer = await _pumpEditInNavigator(tester, repo);

    // Tap the cancel (close) icon in the top bar.
    await tester.tap(find.byKey(const Key('btn-cancel-service-edit')));
    await tester.pumpAndSettle();

    // The edit screen popped back to the launcher route.
    expect(observer.popCount, 1);
    expect(find.byType(ServiceEditScreen), findsNothing);

    // No save happened — cancel must never persist anything.
    verifyNever(
      () => repo.update(any(), any(), assignmentId: any(named: 'assignmentId')),
    );
  });

  // ── L3. Delete-flow: cancel dismisses the dialog, no deactivate call ──────
  //
  // Gap (mobile-qa): tapping the real DeleteServiceDialog's cancel button
  // returns false, so _onDelete short-circuits — the dialog closes, the screen
  // stays, and repository.deactivate is never invoked.

  testWidgets(
    'L3. delete dialog cancel dismisses dialog and does not call deactivate',
    (tester) async {
      final observer = await _pumpEditInNavigator(tester, repo);

      // Open the real delete dialog.
      await tester.tap(find.byKey(const Key('btn-delete-service')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('delete-service-dialog')), findsOneWidget);

      final popsBeforeCancel = observer.popCount;

      // Cancel it.
      await tester.tap(find.byKey(const Key('btn-cancel-delete-service')));
      await tester.pumpAndSettle();

      // Dialog gone, screen still mounted, nothing deleted. The only pop that
      // occurred is the dialog route dismissing itself — the edit screen route
      // must still be mounted (it did not pop).
      expect(find.byKey(const Key('delete-service-dialog')), findsNothing);
      expect(find.byType(ServiceEditScreen), findsOneWidget);
      // Exactly one further pop (the dialog) and no more — the screen stays.
      expect(observer.popCount, popsBeforeCancel + 1);
      verifyNever(() => repo.deactivate(any()));
    },
  );

  // ── L4. Delete-flow: failure surfaces a snackbar and stays on screen ──────
  //
  // Gap (mobile-qa M3): when deactivate throws, _onDelete catches it and shows
  // a failure snackbar via failure.userMessage(context). The screen must NOT
  // pop. Asserts the mapped ServerFailure copy (errServer) is the snackbar text.

  testWidgets(
    'L4. delete failure shows error snackbar and screen is not popped',
    (tester) async {
      when(
        () => repo.deactivate(_stubService.serviceDefId),
      ).thenThrow(const ServerFailure());

      await _pumpEditInNavigator(tester, repo);
      final l10n = _l10n(tester);

      // Open the dialog and confirm.
      await tester.tap(find.byKey(const Key('btn-delete-service')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn-confirm-delete-service')));
      await tester.pumpAndSettle();

      // deactivate was attempted once.
      verify(() => repo.deactivate(_stubService.serviceDefId)).called(1);

      // A failure VelvetSnack with the mapped ServerFailure copy is shown.
      expectVelvetSnack(l10n.errServer, variant: VelvetSnackVariant.error);
      await pumpPastVelvetSnack(tester);

      // The screen stays mounted — a failed delete must not pop the route.
      // (The observer counts the dialog's own dismiss pop; the durable signal
      // that the SCREEN did not pop is its continued presence in the tree.)
      expect(find.byType(ServiceEditScreen), findsOneWidget);
    },
  );

  // ── L5. Delete-flow: success calls deactivate, pops, and shows NO snackbar ─
  //
  // Gap (mobile-qa): the success path calls deactivate(serviceDefId), pops the
  // screen, and invalidates the providers. Unlike the SAVE path it deliberately
  // shows NO success snackbar — this test pins that actual behaviour so a future
  // change that adds/removes the pop is caught.

  testWidgets(
    'L5. confirmed delete calls deactivate, pops the screen, shows no snackbar',
    (tester) async {
      await _pumpEditInNavigator(tester, repo);

      // Open the dialog and confirm.
      await tester.tap(find.byKey(const Key('btn-delete-service')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn-confirm-delete-service')));
      await tester.pumpAndSettle();

      // deactivate called once on the serviceDefId (not the assignment id).
      verify(() => repo.deactivate(_stubService.serviceDefId)).called(1);
      verifyNever(() => repo.deactivate(_stubService.id));

      // The screen popped itself off the stack on success — it is gone from
      // the tree and the launcher route is back. (The observer also records the
      // dialog's own pop, so screen-absence is the durable success signal.)
      expect(find.byType(ServiceEditScreen), findsNothing);
      expect(find.byKey(const Key('open-edit')), findsOneWidget);

      // The delete success path shows NO snack (distinct from the save path).
      expect(find.byType(VelvetSnack), findsNothing);
    },
  );

  // ── L6. Delete-flow: 409 ServiceUnassignBlockedFailure re-shows the ───────
  // ──     dialog blocked, does not pop, and does not invalidate the list ────
  //
  // Phase 319 D3: a salon-target unassign refused because the master still
  // has a future CONFIRMED booking must NOT be treated like an ordinary
  // failure (L4) — it re-shows [DeleteServiceDialog] with `blocked: true`
  // instead of a snackbar, and it must do NO optimistic removal (no pop) and
  // NO catalogue invalidation (nothing was written). The "generic failure →
  // today's error handling, unchanged" case this complements is ALREADY
  // covered by L4 (`ServerFailure` — the null-target / independent-master
  // path must not acquire a blocked dialog it can never legitimately show).

  testWidgets(
    'L6. a 409 ServiceUnassignBlockedFailure re-shows the dialog blocked, '
    'does not pop, and does not invalidate servicesListProvider',
    (tester) async {
      when(
        () => repo.deactivate(_stubService.serviceDefId),
      ).thenThrow(const ServiceUnassignBlockedFailure());

      // A watcher gives servicesListProvider an active subscriber, so a
      // (wrong) invalidate on the 409 arm would manifest as an observable
      // re-emission — without it, `verifyNever(() => repo.listMyServices())`
      // below would pass regardless of whether invalidate was ever called
      // (nothing would be listening to trigger the refetch either way).
      final listStates = <AsyncValue<Object?>>[];
      final observer = await _pumpEditInNavigator(
        tester,
        repo,
        watcherStates: listStates,
      );
      final l10n = _l10n(tester);

      // Drain the mount-time list fetch so the verification below counts
      // ONLY what the failed delete caused
      // (project_riverpod_seamless_invalidate_gotcha: assert the refetch
      // COUNT, never `.value != null`).
      verify(() => repo.listMyServices()).called(greaterThanOrEqualTo(1));
      final popsBeforeDelete = observer.popCount;
      final listStatesBeforeDelete = listStates.length;

      // Open the dialog and confirm.
      await tester.tap(find.byKey(const Key('btn-delete-service')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn-confirm-delete-service')));
      await tester.pumpAndSettle();

      verify(() => repo.deactivate(_stubService.serviceDefId)).called(1);

      // The blocked dialog re-appears with its title and NO destructive
      // button — the absence assertion, not just the title.
      expect(find.byKey(const Key('delete-service-dialog')), findsOneWidget);
      expect(find.text(l10n.deleteServiceBlockedTitle), findsOneWidget);
      expect(find.text(l10n.deleteServiceBlockedBodyNoCount), findsOneWidget);
      expect(
        find.byKey(const Key('btn-confirm-delete-service')),
        findsNothing,
        reason: 'the blocked variant offers nothing to confirm',
      );

      // No optimistic removal: the repository was never asked to re-list,
      // AND the watched provider produced no new state — the non-vacuous
      // form, since `ref.invalidate` retains `.value`
      // (project_riverpod_seamless_invalidate_gotcha), so a null-gate
      // assertion alone would not catch a wrongly-added invalidate.
      verifyNever(() => repo.listMyServices());
      expect(
        listStates.length,
        listStatesBeforeDelete,
        reason:
            'servicesListProvider must NOT re-emit after a 409 refusal — '
            'nothing was written, so there is nothing to refresh',
      );

      // No navigation-to-bookings shortcut anywhere in the refusal path
      // (backend phase 308 stays deferred): the dialog's only action is the
      // shared cancel key (D1) — no third action, no tappable route beyond
      // it. Verified statically too:
      // `grep -a -rn "bookings" lib/features/services/presentation/` shows
      // nothing new added by this phase.
      final dialogFinder = find.byKey(const Key('delete-service-dialog'));
      expect(
        find.descendant(of: dialogFinder, matching: find.byType(TextButton)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialogFinder, matching: find.byType(FilledButton)),
        findsNothing,
      );

      // The screen itself stays mounted — a refusal must not pop the route.
      // Only the dialog's own dismiss-and-reopen pops registered above (the
      // confirm tap that triggered the 409 pops the confirmation dialog
      // route, then showDialog pushes the blocked one back) — the edit
      // screen route itself is never popped.
      expect(find.byType(ServiceEditScreen), findsOneWidget);
      expect(
        observer.popCount,
        greaterThan(popsBeforeDelete),
        reason: 'the confirmation dialog route itself still pops on confirm',
      );
    },
  );

  // ── Phase 320 — writable: false ────────────────────────────────────────────
  //
  // D1: additive, defaults to `true`. IMPORTANT: `_pumpEdit`'s own `writable`
  // PARAMETER defaults to `true` and is threaded into the widget on every
  // call — `ServiceEditScreen(id: id, writable: writable)` — so every OTHER
  // test in this file (including test 7, which asserts `btn-delete-service`
  // is present) always passes `writable` EXPLICITLY, never omits it. Those
  // tests do NOT prove the widget's own default; mutation check 1 confirmed
  // this the hard way (flipping `ServiceEditScreen`'s class default to
  // `false` left every `_pumpEdit`-driven test green). The first test below
  // constructs the widget directly, omitting `writable`, to close that gap.

  testWidgets(
    'the widget default renders writable — constructed directly, omitting '
    '`writable`, bypassing `_pumpEdit`\'s always-explicit pass-through',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          retry: beauticaProviderRetry,
          overrides: _overrides(repo).cast(),
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('uk'),
            // `writable` OMITTED — this is the actual default-parameter
            // proof mutation check 1 needs.
            home: ServiceEditScreen(id: 'svc-edit-1'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn-delete-service')), findsOneWidget);
      expect(find.byKey(const Key('btn-submit-service')), findsOneWidget);
    },
  );

  group('Phase 320 — writable: false removes write affordances only', () {
    testWidgets('delete icon and save action are both absent — not disabled', (
      tester,
    ) async {
      await _pumpEdit(tester, repo, writable: false);

      expect(find.byKey(const Key('btn-delete-service')), findsNothing);
      expect(find.byKey(const Key('btn-submit-service')), findsNothing);
      // The cancel icon is unaffected — leaving is not a write.
      expect(find.byKey(const Key('btn-cancel-service-edit')), findsOneWidget);
    });

    testWidgets('the service name, duration and price still render', (
      tester,
    ) async {
      await _pumpEdit(tester, repo, writable: false);

      // Name — Phase 320 (D3) renders the VALUE, not a TextField, so this
      // is a plain-text lookup scoped under the field's key.
      expect(
        find.descendant(
          of: find.byKey(const Key('field-service-name')),
          matching: find.text(_stubService.name),
        ),
        findsOneWidget,
      );

      // Duration + price stay inside PricingField (disabled, not hidden —
      // D3 applies only to the four ACTION affordances, not to data
      // fields); their controllers still carry the loaded values, matching
      // the same read convention tests 1-3 already use for this screen.
      final durationField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('field-service-duration')),
          matching: find.byType(TextField),
        ),
      );
      expect(
        durationField.controller!.text,
        equals(_stubService.durationMinutes.toString()),
      );
      final priceField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('pricing-fixed-amount')),
          matching: find.byType(TextField),
        ),
      );
      expect(priceField.controller!.text, equals('750'));
    });

    testWidgets('entering text into the name field is impossible — there is no '
        'EditableText to target, not a disabled one', (tester) async {
      await _pumpEdit(tester, repo, writable: false);

      // Structural proof first: no TextField at all under the field's key.
      expect(
        find.descendant(
          of: find.byKey(const Key('field-service-name')),
          matching: find.byType(TextField),
        ),
        findsNothing,
      );

      // Attempt the interaction anyway — the doc requires trying it, not
      // reading a `readOnly`/`enabled` field off a widget. There being no
      // TextField under the key means the attempt itself fails to find a
      // target; catch that and assert the value never moved.
      Object? caught;
      try {
        await tester.enterText(
          find.descendant(
            of: find.byKey(const Key('field-service-name')),
            matching: find.byType(TextField),
          ),
          'hacked name',
        );
      } catch (e) {
        caught = e;
      }
      expect(
        caught,
        isNotNull,
        reason:
            'there is nothing an input method could attach to under '
            'field-service-name in read-only mode',
      );

      // The original value is exactly what still renders — unmoved.
      expect(
        find.descendant(
          of: find.byKey(const Key('field-service-name')),
          matching: find.text(_stubService.name),
        ),
        findsOneWidget,
      );
      expect(find.text('hacked name'), findsNothing);
    });
  });

  tearDownAll(() {});
}
