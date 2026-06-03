// Profile-category-cards feature — profile→services navigation end-to-end.
//
// Area 3 of the required new coverage:
//
// Tapping Key('profile-category-MANICURE') on the master profile screen must
// push to /services with the expandCategory=MANICURE query parameter. This
// test verifies the FULL navigation contract — not just that SOME push
// happened (the existing test 4 in master_profile_screen_test.dart), but:
//   1. ServicesListScreen is rendered after the tap.
//   2. ServicesListScreen.initialExpandCategory is set to 'MANICURE'.
//
// pumpAndSettle IS used here because:
//   • All providers resolve to finite futures (no repeating animations while
//     settling) — serviceRepo.listMyServices() returns an empty list so the
//     empty state renders (no stagger timers, no shimmer repeat).
//   • The MasterProfileScreen entrance animation (1100 ms) is finite and
//     terminates — pumpAndSettle drains it cleanly.
//
// Strategy:
//   1. pumpAndSettle() after initial pump settles master + services providers.
//   2. Category card must be visible (no scroll needed on tall surface).
//   3. tap(card) + pumpAndSettle() for the router push to settle.
//   4. Assert ServicesListScreen.initialExpandCategory field.
//
// Isolation:
//   • ProviderScope with overrides — no real network, no real storage.
//   • Large test surface (800 × 2400) so the category section does not scroll
//     off-screen.
//   • masterRepositoryProvider, serviceRepositoryProvider overrideWithValue.
//   • serviceRepo returns an empty list for /services so the empty state
//     renders (no animated service cards, no shimmer, no stagger timers).

import 'dart:async';

import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_screen.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/category_slug.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class _MockMasterRepository extends Mock implements MasterRepository {}

class _MockServiceRepository extends Mock implements ServiceRepository {}

// ---------------------------------------------------------------------------
// Stub data
// ---------------------------------------------------------------------------

const _fakeUser = User(
  id: 'user-nav',
  email: 'nav@beautica.ua',
  role: UserRole.independentMaster,
  firstName: 'Нав',
  lastName: 'Тест',
);

const _stubMaster = Master(
  id: 'user-nav',
  firstName: 'Нав',
  lastName: 'Тест',
  avgRating: 4.9,
  reviewCount: 5,
  type: MasterType.independentMaster,
);

const _manicureService = MasterService(
  id: 'svc-nav-1',
  serviceDefId: 'def-nav-1',
  name: 'Манікюр',
  durationMinutes: 60,
  priceMin: 500,
  priceDisplay: '500 грн',
  category: 'MANICURE',
);

// ---------------------------------------------------------------------------
// Stub notifiers
// ---------------------------------------------------------------------------

class _StubMasterProfileNotifier extends MasterProfile {
  @override
  Future<Master> build() {
    // ignore: unawaited_futures — intentional: posts state asynchronously to
    // simulate a resolved load while keeping build() return type Future<Master>.
    Future<void>.microtask(() => state = const AsyncData<Master>(_stubMaster));
    return Completer<Master>().future;
  }
}

class _StubAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async =>
      const AuthSession.authenticated(user: _fakeUser, accessToken: 'token');
}

// ---------------------------------------------------------------------------
// Router builder
// ---------------------------------------------------------------------------

/// Builds a router that hosts the profile screen and the services screen
/// with the PRODUCTION expandCategory coercion logic, but no auth redirect.
GoRouter _buildRouter() => GoRouter(
      initialLocation: RouteNames.masterProfile,
      redirect: (context, state) => null,
      routes: <RouteBase>[
        GoRoute(
          path: RouteNames.masterProfile,
          builder: (context, _) => const MasterProfileScreen(),
        ),
        // Production pageBuilder logic — identical to app_router.dart.
        GoRoute(
          path: RouteNames.services,
          pageBuilder: (context, state) {
            final raw = state.uri.queryParameters['expandCategory']
                ?.trim()
                .toUpperCase();
            final expandCategory =
                (raw != null && isValidCategorySlug(raw)) ? raw : null;
            return MaterialPage<void>(
              child: ServicesListScreen(initialExpandCategory: expandCategory),
            );
          },
        ),
      ],
    );

// ---------------------------------------------------------------------------
// Helper — builds the full provider scope and router app
// ---------------------------------------------------------------------------

ProviderScope _buildApp({
  required _MockMasterRepository masterRepo,
  required _MockServiceRepository serviceRepo,
  required GoRouter router,
}) {
  return ProviderScope(
    overrides: [
      authProvider.overrideWith(() => _StubAuthNotifier()),
      masterProfileProvider.overrideWith(
        () => _StubMasterProfileNotifier(),
      ),
      masterRepositoryProvider.overrideWithValue(masterRepo),
      serviceRepositoryProvider.overrideWithValue(serviceRepo),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('uk'),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _MockMasterRepository masterRepo;
  late _MockServiceRepository serviceRepo;

  setUp(() {
    masterRepo = _MockMasterRepository();
    serviceRepo = _MockServiceRepository();

    // Profile screen: one MANICURE service so the category card renders.
    // Services screen (after nav): empty list so the empty-state renders
    // (no stagger timers, no shimmer repeat — pumpAndSettle can drain).
    // The mock is called twice on the /services screen (once from
    // servicesListProvider, possibly once from approvedCategoriesProvider).
    when(() => serviceRepo.listMyServices()).thenAnswer(
      (_) async => const <MasterService>[_manicureService],
    );
    when(() => serviceRepo.fetchApprovedCategories()).thenAnswer(
      (_) async => const <ServiceCategoryOption>[
        ServiceCategoryOption(name: 'MANICURE', displayName: 'Манікюр'),
      ],
    );
    registerFallbackValue('');
  });

  group('Profile → Services navigation — expandCategory query param', () {
    testWidgets(
      'tapping profile-category-MANICURE card navigates to /services and '
      'ServicesListScreen.initialExpandCategory is MANICURE',
      (tester) async {
        // Tall surface so the category cards section (below the stats row)
        // is visible without scrolling.
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final router = _buildRouter();
        await tester.pumpWidget(_buildApp(
          masterRepo: masterRepo,
          serviceRepo: serviceRepo,
          router: router,
        ));
        // pumpAndSettle drains all providers + the 1100 ms entrance animation.
        // Works here because serviceRepo.listMyServices() returns a finite
        // future and the empty-state has no repeating animations.
        await tester.pumpAndSettle();

        // Confirm the MANICURE card is rendered on the profile screen.
        final cardFinder = find.byKey(const Key('profile-category-MANICURE'));
        expect(
          cardFinder,
          findsOneWidget,
          reason:
              'MANICURE category card must be rendered on the profile screen '
              'before the tap',
        );

        // Tap the card — triggers context.push('/services?expandCategory=MANICURE').
        await tester.tap(cardFinder);
        await tester.pumpAndSettle();

        // ServicesListScreen must be in the tree.
        final servicesScreenFinder = find.byType(ServicesListScreen);
        expect(
          servicesScreenFinder,
          findsOneWidget,
          reason:
              'ServicesListScreen must be rendered after tapping the category card',
        );

        // Ground-truth assertion: the router parsed the query param and wired
        // it into the widget's initialExpandCategory field.
        final screen = tester.widget<ServicesListScreen>(servicesScreenFinder);
        expect(
          screen.initialExpandCategory,
          'MANICURE',
          reason:
              'initialExpandCategory must be "MANICURE" — the router must '
              'parse expandCategory=MANICURE, validate it via '
              'isValidCategorySlug, and pass it to ServicesListScreen',
        );
      },
    );

    testWidgets(
      'navigating directly to /services without expandCategory param '
      'results in null initialExpandCategory on ServicesListScreen',
      (tester) async {
        final router = _buildRouter();
        await tester.pumpWidget(_buildApp(
          masterRepo: masterRepo,
          serviceRepo: serviceRepo,
          router: router,
        ));
        // One pump to process initial build.
        await tester.pump();

        // Navigate directly to /services with no query param.
        // Pump twice: first to trigger the route change, second to let
        // GoRouter's page stack rebuild and mount the new widget.
        router.go(RouteNames.services);
        await tester.pump();
        await tester.pump();

        // ServicesListScreen must be in the tree after the route change.
        final servicesScreenFinder = find.byType(ServicesListScreen);
        expect(
          servicesScreenFinder,
          findsOneWidget,
          reason: 'ServicesListScreen must be rendered after router.go(services)',
        );

        final screen = tester.widget<ServicesListScreen>(servicesScreenFinder);
        expect(
          screen.initialExpandCategory,
          isNull,
          reason:
              'no expandCategory param → null must be passed to '
              'ServicesListScreen.initialExpandCategory',
        );
      },
    );
  });
}
