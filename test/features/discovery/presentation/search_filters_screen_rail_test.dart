// Phase 13.x (Variant A «Рейка + послуги») — widget regression tests for the
// redesigned category RAIL + «Всі категорії» SHEET + service-chip DRAWER.
//
// The sibling search_filters_screen_test.dart proves the five sections and the
// rail's loading/loaded/empty/error states. THIS file drills the second-level
// (Variant A) interactions the redesign introduced:
//   • tapping a rail tile reveals the service-chip drawer for that category;
//   • re-tapping the active tile collapses the drawer (single-select toggle);
//   • the «Всі категорії» more-tile opens the full-list bottom sheet, and
//     picking a category there selects it (updates the controller + label) and
//     closes the sheet;
//   • tapping a service chip toggles its selected state (the selection set);
//   • switching the parent category CLEARS the prior service selection so it
//     never leaks across categories.
//
// All finders are key/type-based (locale-invariant); category/service NAMES are
// backend/placeholder data, asserted only as rendered content.
//
// SERVICES SOURCE: the chips come from the now-ASYNC categoryServiceOptionsProvider
// (a keepAlive FutureProvider.family backed by CategoryServiceRepository →
// `GET /api/v1/service-types?categoryName={slug}` — see
// lib/features/discovery/data/category_service_providers.dart). The sync
// placeholder map is gone, so each test OVERRIDES the family per slug with a
// resolved fake list (`categoryServiceOptionsProvider(<slug>).overrideWith(...)`).
// The fakes are keyed `manicure` / `haircut` so the existing chip-key
// assertions (`search_service_chip_manicure` / `_haircut`) stay valid — the
// chip key is `search_service_chip_${option.key}` (see ServiceChipDrawer).

import 'dart:async';

import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/discovery/data/category_service_providers.dart';
import 'package:beautica_mobile/features/discovery/data/category_service_repository.dart';
import 'package:beautica_mobile/features/discovery/domain/category_service_option.dart';
import 'package:beautica_mobile/features/discovery/presentation/search_filters_screen.dart';
import 'package:beautica_mobile/features/discovery/presentation/state/search_filters_controller.dart';
import 'package:beautica_mobile/features/discovery/presentation/widgets/service_chip_drawer.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';
import '../../../helpers/overflow_guard.dart';

const _testUser = User(
  id: 'u-client-1',
  email: 'client@beautica.ua',
  role: UserRole.client,
  firstName: 'Дмитро',
  lastName: 'Клієнт',
);

const _authenticated = AsyncData<AuthSession>(
  AuthSession.authenticated(user: _testUser, accessToken: 'tok'),
);

// Two distinct categories with two distinct service families. Two families let
// the category-switch-clears-services test prove the selection does not leak.
const _categories = <ServiceCategoryOption>[
  ServiceCategoryOption(name: 'NAILS', displayName: 'Манікюр'),
  ServiceCategoryOption(name: 'HAIR', displayName: 'Волосся'),
];

// Per-slug service-option fakes the async categoryServiceOptionsProvider is
// overridden to return. Keyed `manicure` / `haircut` so the rendered chips key
// to `search_service_chip_manicure` / `_haircut` (ServiceChipDrawer builds the
// key from `option.key`), keeping the existing assertions valid.
const _nailsServices = <CategoryServiceOption>[
  CategoryServiceOption(key: 'manicure', displayName: 'Манікюр'),
  CategoryServiceOption(key: 'pedicure', displayName: 'Педикюр'),
];
const _hairServices = <CategoryServiceOption>[
  CategoryServiceOption(key: 'haircut', displayName: 'Стрижка'),
];

class _FixedAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async {
    state = _authenticated;
    return const AuthSession.authenticated(user: _testUser, accessToken: 'tok');
  }
}

class _MockServiceRepository extends Mock implements ServiceRepository {}

class _MockCategoryServiceRepository extends Mock
    implements CategoryServiceRepository {}

/// Default per-slug async overrides for the service-chip drawer: NAILS / HAIR
/// each resolve to their fake family. Pass [serviceOverrides] to [_pumpScreen]
/// to replace these (e.g. drive a single slug into loading / error / empty).
///
/// Typed as `List<Object>` (not the internal `Override` type, which
/// flutter_riverpod does not re-export from its barrel) — `ProviderScope`
/// accepts the cast list, mirroring `test/helpers/pump_app.dart`.
List<Object> _defaultServiceOverrides() => <Object>[
  categoryServiceOptionsProvider(
    'NAILS',
  ).overrideWith((ref) async => _nailsServices),
  categoryServiceOptionsProvider(
    'HAIR',
  ).overrideWith((ref) async => _hairServices),
];

Future<void> _pumpScreen(
  WidgetTester tester, {
  List<Object>? serviceOverrides,
}) async {
  installOverflowGuard();
  // Tall surface so the rail + revealed drawer + sheet all lay out on-screen for
  // hit-testing.
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  // Built as List<Object> then cast at the ProviderScope boundary (the internal
  // Override type is not re-exported) — see _defaultServiceOverrides.
  final List<Object> overrides = <Object>[
    authProvider.overrideWith(_FixedAuthNotifier.new),
    authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
    secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
    serviceRepositoryProvider.overrideWithValue(_MockServiceRepository()),
    approvedCategoriesProvider.overrideWith((ref) async => _categories),
    // The category→services drawer is now async; resolve each slug to its fake
    // family so the data state (chips) renders deterministically with no real
    // network. Per-state tests pass [serviceOverrides] instead.
    ...(serviceOverrides ?? _defaultServiceOverrides()),
  ];

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides.cast(),
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('uk'),
        home: ClientSearchScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(ClientSearchScreen)));

void main() {
  group('ClientSearchScreen — rail → drawer reveal', () {
    testWidgets('drawer is hidden until a category is selected', (
      tester,
    ) async {
      await _pumpScreen(tester);

      expect(find.byType(ServiceChipDrawer), findsNothing);
    });

    testWidgets('tapping a category reveals its service-chip drawer', (
      tester,
    ) async {
      await _pumpScreen(tester);

      await tester.tap(find.byKey(const Key('search_service_type_NAILS')));
      await tester.pumpAndSettle();

      expect(find.byType(ServiceChipDrawer), findsOneWidget);
      // The overridden async family for NAILS resolves to chips, each keyed.
      expect(
        find.byKey(const Key('search_service_chip_manicure')),
        findsOneWidget,
      );
    });

    testWidgets('re-tapping the active category collapses the drawer', (
      tester,
    ) async {
      await _pumpScreen(tester);

      await tester.tap(find.byKey(const Key('search_service_type_NAILS')));
      await tester.pumpAndSettle();
      expect(find.byType(ServiceChipDrawer), findsOneWidget);

      await tester.tap(find.byKey(const Key('search_service_type_NAILS')));
      await tester.pumpAndSettle();

      expect(
        _container(tester).read(searchFiltersControllerProvider).categoryKey,
        isNull,
      );
      expect(find.byType(ServiceChipDrawer), findsNothing);
    });
  });

  group('ClientSearchScreen — service-chip selection', () {
    testWidgets('tapping a chip toggles its selected state', (tester) async {
      await _pumpScreen(tester);
      await tester.tap(find.byKey(const Key('search_service_type_NAILS')));
      await tester.pumpAndSettle();

      // Select.
      await tester.tap(find.byKey(const Key('search_service_chip_manicure')));
      await tester.pumpAndSettle();
      expect(
        _container(tester).read(searchServiceSelectionControllerProvider),
        contains('manicure'),
      );

      // Toggle off.
      await tester.tap(find.byKey(const Key('search_service_chip_manicure')));
      await tester.pumpAndSettle();
      expect(
        _container(tester).read(searchServiceSelectionControllerProvider),
        isNot(contains('manicure')),
      );
    });

    testWidgets(
      'switching the parent category clears prior service selections',
      (tester) async {
        await _pumpScreen(tester);

        // Pick NAILS, select a NAILS service.
        await tester.tap(find.byKey(const Key('search_service_type_NAILS')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('search_service_chip_manicure')));
        await tester.pumpAndSettle();
        expect(
          _container(tester).read(searchServiceSelectionControllerProvider),
          contains('manicure'),
        );

        // Switch to HAIR — the prior NAILS service selection must NOT leak.
        await tester.tap(find.byKey(const Key('search_service_type_HAIR')));
        await tester.pumpAndSettle();

        expect(
          _container(tester).read(searchServiceSelectionControllerProvider),
          isEmpty,
          reason: 'a category switch must clear the second-level service set',
        );
        // The HAIR drawer is now shown with its own family chips.
        expect(
          find.byKey(const Key('search_service_chip_haircut')),
          findsOneWidget,
        );
      },
    );
  });

  group('ClientSearchScreen — «Всі категорії» sheet', () {
    testWidgets(
      'the more-tile opens the sheet; picking a category selects it + closes',
      (tester) async {
        await _pumpScreen(tester);
        final AppLocalizations l10n = await AppLocalizations.delegate.load(
          const Locale('uk'),
        );

        // Open the sheet via the more-tile.
        await tester.tap(find.byKey(const Key('search_all_categories_tile')));
        await tester.pumpAndSettle();

        // The sheet lists every category as a keyed tile.
        expect(find.text(l10n.searchAllCategoriesSheetTitle), findsOneWidget);
        expect(
          find.byKey(const Key('search_all_categories_HAIR')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('search_all_categories_NAILS')),
          findsOneWidget,
        );

        // Pick HAIR in the sheet.
        await tester.tap(find.byKey(const Key('search_all_categories_HAIR')));
        await tester.pumpAndSettle();

        // Selection updated + label mirrored.
        expect(
          _container(tester).read(searchFiltersControllerProvider).categoryKey,
          'HAIR',
        );
        expect(
          _container(
            tester,
          ).read(searchFilterLabelsControllerProvider).categoryName,
          'Волосся',
        );
        // The sheet closed (no sheet tiles left in the tree).
        expect(
          find.byKey(const Key('search_all_categories_HAIR')),
          findsNothing,
        );
        // …and the drawer for the picked category is revealed.
        expect(find.byType(ServiceChipDrawer), findsOneWidget);
      },
    );
  });

  // ── Variant A second-level drawer: async loading / error / empty states ─────
  //
  // The drawer's service list is now an async family (categoryServiceOptions
  // Provider). Each state is driven via a per-slug provider/repository override
  // so it renders deterministically with no real network.
  group('ClientSearchScreen — service drawer async states', () {
    testWidgets('LOADING → drawer skeleton, no chips', (tester) async {
      // A never-completing override keeps the family in AsyncLoading so the
      // skeleton (with its spinner) stays up.
      await _pumpScreen(
        tester,
        serviceOverrides: <Object>[
          categoryServiceOptionsProvider('NAILS').overrideWith(
            (ref) => Completer<List<CategoryServiceOption>>().future,
          ),
        ],
      );
      // pumpAndSettle for the rail (approvedCategories resolves) but the NAILS
      // family stays pending.
      await tester.tap(find.byKey(const Key('search_service_type_NAILS')));
      // Single bounded pumps (NOT settle — the family never completes).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The drawer's loading affordance is the skeleton's spinner; no chips and
      // no error retry yet.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        find.byKey(const Key('search_service_chip_manicure')),
        findsNothing,
      );
    });

    testWidgets('ERROR → error copy + retry; retry re-fetches and renders chips', (
      tester,
    ) async {
      // The override body reads a mutable flag on every (re-)run: it throws a
      // StateError first (a Dart Error → Riverpod's defaultRetry does NOT
      // auto-retry, so the family settles cleanly to AsyncError and the drawer
      // paints _GridError), then — after retry flips the flag — resolves to the
      // fake family. This proves the retry's ref.invalidate genuinely re-runs
      // the provider body (a second fetch), not a dead button.
      var fetches = 0;
      var shouldSucceed = false;

      await _pumpScreen(
        tester,
        serviceOverrides: <Object>[
          categoryServiceOptionsProvider('NAILS').overrideWith((ref) {
            fetches++;
            if (shouldSucceed) {
              return Future<List<CategoryServiceOption>>.value(_nailsServices);
            }
            return Future<List<CategoryServiceOption>>.error(
              StateError('services boom'),
            );
          }),
        ],
      );
      final AppLocalizations l10n = await AppLocalizations.delegate.load(
        const Locale('uk'),
      );

      await tester.tap(find.byKey(const Key('search_service_type_NAILS')));
      // Bounded single pumps until the rejected Future settles the family to
      // AsyncError → _GridError paints. NOT pumpAndSettle: the keepAlive search
      // controllers rebuild and could otherwise re-enter a seamless loading
      // state (Riverpod 3.x seamless-invalidate), masking the error branch.
      for (var i = 0; i < 6; i++) {
        if (find.text(l10n.searchServicesLoadError).evaluate().isNotEmpty)
          break;
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Error branch: localized services error copy + retry affordance, no chips.
      expect(find.text(l10n.searchServicesLoadError), findsOneWidget);
      expect(find.byKey(const Key('search_categories_retry')), findsOneWidget);
      expect(
        find.byKey(const Key('search_service_chip_manicure')),
        findsNothing,
      );
      expect(fetches, 1, reason: 'the first reveal fetched once');

      // Tap retry → ref.invalidate(categoryServiceOptionsProvider('NAILS')) →
      // the provider body re-runs; with the flag flipped it now resolves, so the
      // chips render — proving the retry re-fetches.
      shouldSucceed = true;
      await tester.tap(find.byKey(const Key('search_categories_retry')));
      for (var i = 0; i < 6; i++) {
        if (find
            .byKey(const Key('search_service_chip_manicure'))
            .evaluate()
            .isNotEmpty) {
          break;
        }
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(
        fetches,
        2,
        reason: 'retry must re-run the provider (a 2nd fetch)',
      );
      expect(find.text(l10n.searchServicesLoadError), findsNothing);
      expect(
        find.byKey(const Key('search_service_chip_manicure')),
        findsOneWidget,
      );
    });

    testWidgets('EMPTY → drawer collapses (no chips, no skeleton)', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        serviceOverrides: <Object>[
          categoryServiceOptionsProvider(
            'NAILS',
          ).overrideWith((ref) async => const <CategoryServiceOption>[]),
        ],
      );

      await tester.tap(find.byKey(const Key('search_service_type_NAILS')));
      await tester.pumpAndSettle();

      // An empty service list collapses the drawer entirely: no chip drawer, no
      // skeleton, no error.
      expect(find.byType(ServiceChipDrawer), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Не вдалося завантажити послуги'), findsNothing);
    });
  });

  // ── categoryServiceOptionsProvider behaviour (keyed by slug + keepAlive) ────
  group('categoryServiceOptionsProvider', () {
    test('returns the repo-mapped list for the queried slug', () async {
      final repo = _MockCategoryServiceRepository();
      when(
        () => repo.fetchServices('NAILS'),
      ).thenAnswer((_) async => _nailsServices);

      final container = ProviderContainer(
        overrides: [categoryServiceRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      final result = await container.read(
        categoryServiceOptionsProvider('NAILS').future,
      );

      expect(result, _nailsServices);
      verify(() => repo.fetchServices('NAILS')).called(1);
    });

    test(
      'different slugs are independent (each queries its own slug)',
      () async {
        final repo = _MockCategoryServiceRepository();
        when(
          () => repo.fetchServices('NAILS'),
        ).thenAnswer((_) async => _nailsServices);
        when(
          () => repo.fetchServices('HAIR'),
        ).thenAnswer((_) async => _hairServices);

        final container = ProviderContainer(
          overrides: [
            categoryServiceRepositoryProvider.overrideWithValue(repo),
          ],
        );
        addTearDown(container.dispose);

        final nails = await container.read(
          categoryServiceOptionsProvider('NAILS').future,
        );
        final hair = await container.read(
          categoryServiceOptionsProvider('HAIR').future,
        );

        expect(nails, _nailsServices);
        expect(hair, _hairServices);
        verify(() => repo.fetchServices('NAILS')).called(1);
        verify(() => repo.fetchServices('HAIR')).called(1);
      },
    );

    test('keepAlive caches: a second read of the same slug does not re-invoke '
        'the repo', () async {
      final repo = _MockCategoryServiceRepository();
      when(
        () => repo.fetchServices('NAILS'),
      ).thenAnswer((_) async => _nailsServices);

      final container = ProviderContainer(
        overrides: [categoryServiceRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      await container.read(categoryServiceOptionsProvider('NAILS').future);
      // Second read of the SAME slug — the keepAlive family must serve the cached
      // value, not re-run the provider body.
      await container.read(categoryServiceOptionsProvider('NAILS').future);

      verify(() => repo.fetchServices('NAILS')).called(1);
    });
  });
}
