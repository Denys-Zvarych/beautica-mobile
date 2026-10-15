// «Мої послуги» — single-flight guard on `_openAndRefresh`.
//
// The bug: taps that queued up while the screen was not drawing frames (the
// flutter_riverpod 3.1.0 dropped-frame freeze) each ran `context.push`, so the
// first frame after recovery showed SEVERAL setup pages stacked on top of each
// other. A fast triple-tap reproduces the same stack headlessly: no frame is
// pumped between the taps, so the FAB / CTA stays hit-testable and every tap
// reaches `_openAndRefresh`.
//
// The real [ServiceSetupScreen] is mounted (not a dummy leaf) so the close path
// is the production one: `btn-setup-close` -> `_leave` -> `context.pop()`.
//
// Anti-vacuity: remove the `_opening` early-return in `_openAndRefresh` and
// both rows fail with 3 setup screens instead of 1 (verified when written).

import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/presentation/service_setup_screen.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_notifier.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/pump_app.dart';

class _MockServiceRepository extends Mock implements ServiceRepository {}

class _SeededServicesList extends ServicesList {
  _SeededServicesList(this.seed);

  final List<MasterService> seed;

  @override
  Future<List<MasterService>> build() => SynchronousFuture(seed);
}

const _service = MasterService(
  id: 'svc-1',
  serviceDefId: 'def-1',
  name: 'Манікюр класичний',
  durationMinutes: 60,
  priceMin: 500,
  priceDisplay: '500 ₴',
  category: 'MANICURE',
);

const _manicure = ServiceCategoryOption(
  name: 'MANICURE',
  displayName: 'Манікюр',
);

void main() {
  late _MockServiceRepository repo;

  setUp(() {
    repo = _MockServiceRepository();
  });

  GoRouter router() => GoRouter(
    initialLocation: RouteNames.services,
    routes: <RouteBase>[
      GoRoute(
        path: RouteNames.services,
        builder: (_, _) => const ServicesListScreen(),
      ),
      GoRoute(
        path: RouteNames.serviceSetup,
        builder: (_, _) => const ServiceSetupScreen(),
      ),
    ],
  );

  Future<void> pump(WidgetTester tester, List<MasterService> existing) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpRoutedApp(
      router(),
      overrides: <Object>[
        serviceRepositoryProvider.overrideWithValue(repo),
        servicesListProvider.overrideWith(() => _SeededServicesList(existing)),
        approvedCategoriesProvider.overrideWith(
          (ref) async => const <ServiceCategoryOption>[_manicure],
        ),
      ],
    );
    await tester.pumpAndSettle();
  }

  /// Every [ServiceSetupScreen] in the navigator, covered pages included.
  Finder setupScreens() => find.byType(ServiceSetupScreen, skipOffstage: false);

  /// Three taps with NO frame in between — the queued-tap burst.
  Future<void> tripleTap(WidgetTester tester, Finder target) async {
    for (var i = 0; i < 3; i++) {
      await tester.tap(target);
    }
    await tester.pumpAndSettle();
  }

  Future<void> closeAndExpectList(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('btn-setup-close')));
    await tester.pumpAndSettle();
    expect(setupScreens(), findsNothing);
    expect(find.byType(ServicesListScreen), findsOneWidget);
  }

  testWidgets('FAB tapped 3x fast opens exactly ONE setup screen', (
    tester,
  ) async {
    await pump(tester, const <MasterService>[_service]);

    // The FAB root is an AnimatedScale; target the GestureDetector that owns
    // the hit box (project_animatedscale_root_breaks_tap_by_key).
    final Finder fab = find.descendant(
      of: find.byKey(const Key('btn-create-service')),
      matching: find.byType(GestureDetector),
    );
    await tripleTap(tester, fab.first);

    expect(setupScreens(), findsOneWidget);
    await closeAndExpectList(tester);
    expect(find.byKey(const Key('btn-create-service')), findsOneWidget);
  });

  testWidgets('empty-state CTA tapped 3x fast opens exactly ONE setup screen', (
    tester,
  ) async {
    await pump(tester, const <MasterService>[]);

    await tripleTap(tester, find.byKey(const Key('btn-create-service-empty')));

    expect(setupScreens(), findsOneWidget);
    await closeAndExpectList(tester);
    expect(find.byKey(const Key('btn-create-service-empty')), findsOneWidget);
  });

  testWidgets('the guard re-arms: a second open after close still works', (
    tester,
  ) async {
    await pump(tester, const <MasterService>[]);
    final Finder cta = find.byKey(const Key('btn-create-service-empty'));

    await tester.tap(cta);
    await tester.pumpAndSettle();
    await closeAndExpectList(tester);

    await tester.tap(cta);
    await tester.pumpAndSettle();
    expect(setupScreens(), findsOneWidget);
  });
}
