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
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
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

class _FakeMasterServiceUpdate extends Fake implements MasterServiceUpdate {}

class _MockServiceRepository extends Mock implements ServiceRepository {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// A representative service loaded by the edit screen.
const _stubService = MasterService(
  id: 'svc-edit-1',
  name: 'Стрижка жіноча',
  durationMinutes: 60,
  price: 750.0,
);

/// Resolves [AppLocalizations] from the currently-mounted widget tree.
AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(ServiceEditScreen)));

/// Overrides [serviceRepositoryProvider] so no HTTP calls are made.
List<Object> _overrides(_MockServiceRepository repo) {
  return <Object>[serviceRepositoryProvider.overrideWithValue(repo)];
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

/// Pumps [ServiceEditScreen] (for the given [id]) with the mocked repository.
///
/// [watcherStates] — when supplied a [_ListWatcher] wraps the screen so that
/// [servicesListProvider] has an active subscriber and its state transitions
/// are captured.
Future<void> _pumpEdit(
  WidgetTester tester,
  _MockServiceRepository repo, {
  String id = 'svc-edit-1',
  List<AsyncValue<Object?>>? watcherStates,
}) async {
  final Widget screen = watcherStates != null
      ? _ListWatcher(
          states: watcherStates,
          child: ServiceEditScreen(id: id),
        )
      : ServiceEditScreen(id: id);

  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(repo).cast(),
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
    // Default: update succeeds.
    when(
      () => repo.update(_stubService.id, any()),
    ).thenAnswer((_) async => _stubService);
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

      verify(() => repo.update(_stubService.id, any())).called(1);

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

  tearDownAll(() {});
}
