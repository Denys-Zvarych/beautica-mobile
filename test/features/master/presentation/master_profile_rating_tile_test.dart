// Phase 4.6 follow-up, rewritten Phase 351 — Entry-point test: the master
// profile's «Рейтинг» stat tile (`Key('master-profile-rating-tile')`) is
// present and tapping it SWITCHES the screen to the «Відгуки» tab IN PLACE
// (D15/D11) — the standalone «Мої відгуки» route it used to push is deleted.
// Mirrors `master_profile_reviews_tile_test.dart`.
//
// No second route is registered on the test router: if a future regression
// reintroduced a `context.push`, it would throw (no matching route) rather
// than silently pass, since this test asserts on the ABSENCE of navigation.

import 'dart:async';

import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/master/application/master_review_summary_notifier.dart';
import 'package:beautica_mobile/features/master/application/master_reviews_notifier.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/domain/master_review.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_screen.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/master_reviews_body.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

class _MockMasterRepository extends Mock implements MasterRepository {}

class _MockServiceRepository extends Mock implements ServiceRepository {}

const _fakeUser = User(
  id: 'user-master-1',
  email: 'master@beautica.ua',
  role: UserRole.independentMaster,
  firstName: 'Олена',
  lastName: 'Ковальчук',
);

const _stubMaster = Master(
  id: 'user-master-1',
  firstName: 'Олена',
  lastName: 'Ковальчук',
  avgRating: 4.8,
  reviewCount: 5,
  type: MasterType.independentMaster,
);

/// Zero-review fixture — the reviews tile switches tabs unconditionally
/// regardless of `reviewCount` (only the DISPLAYED value is conditional:
/// '—' vs the number). This test pins that the rating tile matches that
/// behaviour rather than gating the tap on `reviewCount > 0`.
const _stubMasterZeroReviews = Master(
  id: 'user-master-1',
  firstName: 'Олена',
  lastName: 'Ковальчук',
  avgRating: 0,
  reviewCount: 0,
  type: MasterType.independentMaster,
);

class _StubMasterProfileNotifier extends MasterProfile {
  _StubMasterProfileNotifier(this._target);

  final Master _target;

  @override
  Future<Master> build() {
    // ignore: unawaited_futures — post the resolved state asynchronously while
    // keeping the Future<Master> return type.
    Future<void>.microtask(() => state = AsyncData<Master>(_target));
    return Completer<Master>().future;
  }
}

class _StubAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async =>
      const AuthSession.authenticated(user: _fakeUser, accessToken: 'token');
}

GoRouter _buildRouter() => GoRouter(
  initialLocation: RouteNames.masterProfile,
  redirect: (BuildContext context, GoRouterState state) => null,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.masterProfile,
      builder: (BuildContext context, GoRouterState state) =>
          const MasterProfileScreen(),
    ),
  ],
);

ProviderScope _buildApp({
  required _MockMasterRepository masterRepo,
  required _MockServiceRepository serviceRepo,
  required GoRouter router,
  required Master master,
}) {
  return ProviderScope(
    retry: beauticaProviderRetry,
    overrides: [
      authProvider.overrideWith(_StubAuthNotifier.new),
      masterProfileProvider.overrideWith(
        () => _StubMasterProfileNotifier(master),
      ),
      masterRepositoryProvider.overrideWithValue(masterRepo),
      serviceRepositoryProvider.overrideWithValue(serviceRepo),
      approvedCategoriesProvider.overrideWith(
        (ref) async => const <ServiceCategoryOption>[],
      ),
      masterReviewSummaryProvider(master.id).overrideWith(
        (ref) async => MasterReviewSummary(
          avgRating: master.avgRating,
          reviewCount: master.reviewCount,
          distribution: const <int>[0, 0, 0, 0, 0],
        ),
      ),
      masterReviewsProvider(
        master.id,
        MasterReviewSort.newest,
      ).overrideWith((ref) async => const <MasterReviewItem>[]),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('uk'),
    ),
  );
}

void main() {
  late _MockMasterRepository masterRepo;
  late _MockServiceRepository serviceRepo;

  setUp(() {
    masterRepo = _MockMasterRepository();
    serviceRepo = _MockServiceRepository();
    when(
      () => serviceRepo.listMyServices(),
    ).thenAnswer((_) async => const <MasterService>[]);
  });

  testWidgets(
    'the rating stat tile is present and tapping it switches to the «Відгуки» '
    'tab in place (no navigation)',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final GoRouter router = _buildRouter();
      await tester.pumpWidget(
        _buildApp(
          masterRepo: masterRepo,
          serviceRepo: serviceRepo,
          router: router,
          master: _stubMaster,
        ),
      );
      await tester.pumpAndSettle();

      final Finder tile = find.byKey(const Key('master-profile-rating-tile'));
      expect(tile, findsOneWidget, reason: 'the rating stat tile must render');
      expect(find.byType(MasterReviewsBody), findsNothing);

      // The real tap drives the tile's own onTap → selectProfileTab — never a
      // router.go/push stand-in.
      await tester.tap(tile);
      await tester.pumpAndSettle();

      expect(
        find.byType(MasterReviewsBody),
        findsOneWidget,
        reason:
            'tapping the rating tile must switch the screen to the «Відгуки» '
            'tab in place',
      );
      // No navigation happened — still the same screen, same location. No
      // push ever happens in this test (the tap only switches a local tab)
      // — the router's ONLY match is the initial `.go()`-installed route, so
      // the ImperativeRouteMatch exclusion this guard protects against never
      // applies here.
      expect(find.byType(MasterProfileScreen), findsOneWidget);
      expect(
        // router-location-ok: go-only navigation in this test, never a push.
        router.routerDelegate.currentConfiguration.uri.toString(),
        RouteNames.masterProfile,
      );
    },
  );

  testWidgets(
    'the rating stat tile still switches tabs when reviewCount is 0 (the '
    'tile shows a dash but tapping is not gated on having reviews)',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final GoRouter router = _buildRouter();
      await tester.pumpWidget(
        _buildApp(
          masterRepo: masterRepo,
          serviceRepo: serviceRepo,
          router: router,
          master: _stubMasterZeroReviews,
        ),
      );
      await tester.pumpAndSettle();

      // Displayed value is the dash placeholder for zero reviews …
      expect(
        tester
            .widget<Text>(find.byKey(const Key('master-profile-rating-value')))
            .data,
        '—',
      );

      // … but the tile is still tappable and still switches tabs.
      final Finder tile = find.byKey(const Key('master-profile-rating-tile'));
      expect(tile, findsOneWidget);
      expect(find.byType(MasterReviewsBody), findsNothing);

      await tester.tap(tile);
      await tester.pumpAndSettle();

      expect(
        find.byType(MasterReviewsBody),
        findsOneWidget,
        reason:
            'the rating tile must switch tabs unconditionally regardless of '
            'reviewCount, matching the reviews tile\'s behaviour',
      );
    },
  );
}
