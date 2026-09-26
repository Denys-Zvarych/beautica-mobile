// Phase 4.6, rewritten Phase 351, rewritten user decision 2026-09-26 —
// Entry-point test: the master profile's «Відгуки» stat tile
// (`Key('master-profile-reviews-tile')`) renders, and tapping it does
// NOTHING — no tab switch, no navigation, no button semantics. The stat
// cards are display-only; the «Про майстра» / «Послуги» / «Відгуки» tabs
// are the only way to switch tabs.
//
// No second route is registered on the test router — see
// `master_profile_rating_tile_test.dart`'s header for why.

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

class _StubMasterProfileNotifier extends MasterProfile {
  @override
  Future<Master> build() {
    // ignore: unawaited_futures — post the resolved state asynchronously while
    // keeping the Future<Master> return type.
    Future<void>.microtask(() => state = const AsyncData<Master>(_stubMaster));
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
}) {
  return ProviderScope(
    retry: beauticaProviderRetry,
    overrides: [
      authProvider.overrideWith(_StubAuthNotifier.new),
      masterProfileProvider.overrideWith(() => _StubMasterProfileNotifier()),
      masterRepositoryProvider.overrideWithValue(masterRepo),
      serviceRepositoryProvider.overrideWithValue(serviceRepo),
      approvedCategoriesProvider.overrideWith(
        (ref) async => const <ServiceCategoryOption>[],
      ),
      masterReviewSummaryProvider(_stubMaster.id).overrideWith(
        (ref) async => MasterReviewSummary(
          avgRating: _stubMaster.avgRating,
          reviewCount: _stubMaster.reviewCount,
          distribution: const <int>[0, 0, 0, 0, 0],
        ),
      ),
      masterReviewsProvider(
        _stubMaster.id,
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
    'the reviews stat tile is present and tapping it leaves the selected '
    'tab and route unchanged (display-only, user decision 2026-09-26)',
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
        ),
      );
      await tester.pumpAndSettle();

      final Finder tile = find.byKey(const Key('master-profile-reviews-tile'));
      expect(tile, findsOneWidget, reason: 'the reviews stat tile must render');
      expect(find.byType(MasterReviewsBody), findsNothing);

      // No InkWell/GestureDetector on the tile — warnIfMissed would flag a
      // real interactive target the tap failed to land on.
      await tester.tap(tile, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(
        find.byType(MasterReviewsBody),
        findsNothing,
        reason:
            'the reviews tile is display-only — a tap must never switch '
            'the screen to the «Відгуки» tab',
      );
      expect(find.byType(MasterProfileScreen), findsOneWidget);
      expect(
        // router-location-ok: go-only navigation in this test, never a push.
        router.routerDelegate.currentConfiguration.uri.toString(),
        RouteNames.masterProfile,
      );
    },
  );

  testWidgets('the reviews stat tile exposes no button semantics', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final SemanticsHandle handle = tester.ensureSemantics();

    final GoRouter router = _buildRouter();
    await tester.pumpWidget(
      _buildApp(
        masterRepo: masterRepo,
        serviceRepo: serviceRepo,
        router: router,
      ),
    );
    await tester.pumpAndSettle();

    final Finder tile = find.byKey(const Key('master-profile-reviews-tile'));
    expect(tester.getSemantics(tile), isNot(isSemantics(isButton: true)));

    handle.dispose();
  });
}
