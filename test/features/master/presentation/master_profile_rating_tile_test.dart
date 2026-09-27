// Phase 4.6 follow-up, rewritten Phase 351, rewritten user decision
// 2026-09-26 — Entry-point test: the master profile's «Рейтинг» stat tile
// (`Key('master-profile-rating-tile')`) renders, and tapping it does
// NOTHING — no tab switch, no navigation, no button semantics. The stat
// cards are display-only; the «Про майстра» / «Послуги» / «Відгуки» tabs
// are the only way to switch tabs.
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

/// Zero-review fixture — pins that the rating tile stays inert regardless of
/// `reviewCount` (only the DISPLAYED value is conditional: '—' vs the
/// number).
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
    'the rating stat tile is present and tapping it leaves the selected tab '
    'and route unchanged (display-only, user decision 2026-09-26)',
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

      // No InkWell/GestureDetector on the tile — warnIfMissed would flag a
      // real interactive target the tap failed to land on.
      await tester.tap(tile, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(
        find.byType(MasterReviewsBody),
        findsNothing,
        reason:
            'the rating tile is display-only — a tap must never switch the '
            'screen to the «Відгуки» tab',
      );
      expect(find.byType(MasterProfileScreen), findsOneWidget);
      expect(
        // router-location-ok: go-only navigation in this test, never a push.
        router.routerDelegate.currentConfiguration.uri.toString(),
        RouteNames.masterProfile,
      );
    },
  );

  testWidgets('the rating stat tile exposes no button semantics', (
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
        master: _stubMaster,
      ),
    );
    await tester.pumpAndSettle();

    final Finder tile = find.byKey(const Key('master-profile-rating-tile'));
    expect(tester.getSemantics(tile), isNot(isSemantics(isButton: true)));

    handle.dispose();
  });

  testWidgets(
    'the rating stat tile stays inert when reviewCount is 0 (shows a dash, '
    'no tap behaviour either way)',
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

      // … and the tile is still non-interactive.
      final Finder tile = find.byKey(const Key('master-profile-rating-tile'));
      expect(tile, findsOneWidget);
      expect(find.byType(MasterReviewsBody), findsNothing);

      await tester.tap(tile, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byType(MasterReviewsBody), findsNothing);
    },
  );
}
