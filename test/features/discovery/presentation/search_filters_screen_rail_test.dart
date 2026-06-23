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
// SERVICES SOURCE: the chips come from the PLACEHOLDER
// categoryServiceOptionsProvider (no backend endpoint yet — see
// lib/features/discovery/data/category_service_providers.dart header). NAILS
// resolves (substring `NAIL`) to the placeholder family list, so the drawer
// renders real chips. This is asserted as-is; the provider is NOT overridden.

import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
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

// NAILS resolves to the placeholder family list (Манікюр / Педикюр / …); HAIR
// resolves to its own (Стрижка / …). Two distinct families let the
// category-switch-clears-services test prove the selection does not leak.
const _categories = <ServiceCategoryOption>[
  ServiceCategoryOption(name: 'NAILS', displayName: 'Манікюр'),
  ServiceCategoryOption(name: 'HAIR', displayName: 'Волосся'),
];

class _FixedAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async {
    state = _authenticated;
    return const AuthSession.authenticated(user: _testUser, accessToken: 'tok');
  }
}

class _MockServiceRepository extends Mock implements ServiceRepository {}

Future<void> _pumpScreen(WidgetTester tester) async {
  installOverflowGuard();
  // Tall surface so the rail + revealed drawer + sheet all lay out on-screen for
  // hit-testing.
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(_FixedAuthNotifier.new),
        authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
        secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
        serviceRepositoryProvider.overrideWithValue(_MockServiceRepository()),
        approvedCategoriesProvider.overrideWith((ref) async => _categories),
      ],
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
      // The placeholder family for NAILS renders real chips, each keyed.
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
}
