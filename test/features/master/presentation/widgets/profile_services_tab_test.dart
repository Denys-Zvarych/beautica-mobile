// Phase 24.5 — widget tests for the shared ProfileServicesTab (promoted from
// the private `_ProfileCategoriesSection` of master_profile_screen.dart).
// Pins the default destinations (independent master) AND the additive
// overrides (owner profile, phase 389). Navigation is driven by real taps
// through a real GoRouter (nav-detection trap).

import 'package:beautica_mobile/features/master/presentation/widgets/profile_services_tab.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../../helpers/pump_app.dart';

const List<MasterService> _services = <MasterService>[
  MasterService(
    id: 'svc-1',
    serviceDefId: 'def-1',
    name: 'svc',
    durationMinutes: 60,
    priceMin: 500,
    priceDisplay: '500',
    category: 'NAILS',
  ),
];

List<Object> _overrides() => <Object>[
  approvedCategoriesProvider.overrideWith(
    (ref) async => const <ServiceCategoryOption>[],
  ),
];

/// Mounts [tab] on `/host`; records every location pushed to
/// `/services...` and `/service-setup`.
Future<List<String>> _pump(WidgetTester tester, Widget tab) async {
  final List<String> pushed = <String>[];
  final GoRouter router = GoRouter(
    initialLocation: '/host',
    routes: <RouteBase>[
      GoRoute(
        path: '/host',
        builder: (_, _) => Scaffold(body: SingleChildScrollView(child: tab)),
      ),
      GoRoute(
        path: RouteNames.services,
        builder: (_, state) {
          pushed.add(state.uri.toString());
          return const Scaffold(body: Text('services-page'));
        },
      ),
      GoRoute(
        path: RouteNames.serviceSetup,
        builder: (_, state) {
          pushed.add(state.uri.toString());
          return const Scaffold(body: Text('setup-page'));
        },
      ),
    ],
  );
  await tester.pumpRoutedApp(router, overrides: _overrides());
  await tester.pump();
  await tester.pump();
  return pushed;
}

void main() {
  testWidgets('loading → two skeleton blocks', (tester) async {
    await _pump(
      tester,
      const ProfileServicesTab(services: AsyncLoading<List<MasterService>>()),
    );
    expect(find.byType(SkeletonBlock), findsNWidgets(2));
  });

  testWidgets('error → errUnknown', (tester) async {
    await _pump(
      tester,
      const ProfileServicesTab(
        services: AsyncError<List<MasterService>>('x', StackTrace.empty),
      ),
    );
    final BuildContext ctx = tester.element(find.byType(ProfileServicesTab));
    expect(find.text(AppLocalizations.of(ctx).errUnknown), findsOneWidget);
  });

  group('empty', () {
    testWidgets('default CTA pushes serviceSetup', (tester) async {
      final List<String> pushed = await _pump(
        tester,
        const ProfileServicesTab(
          services: AsyncData<List<MasterService>>(<MasterService>[]),
        ),
      );
      expect(find.byIcon(Icons.arrow_forward_ios_rounded), findsNothing);
      await tester.tap(find.byKey(const Key('btn-master-add-services')));
      await tester.pumpAndSettle();
      expect(pushed, <String>[RouteNames.serviceSetup]);
    });

    testWidgets('onAddServices overrides the default', (tester) async {
      int calls = 0;
      final List<String> pushed = await _pump(
        tester,
        ProfileServicesTab(
          services: const AsyncData<List<MasterService>>(<MasterService>[]),
          onAddServices: () => calls++,
        ),
      );
      await tester.tap(find.byKey(const Key('btn-master-add-services')));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(pushed, isEmpty);
    });
  });

  group('data', () {
    testWidgets('header link default pushes services; card key uses prefix', (
      tester,
    ) async {
      final List<String> pushed = await _pump(
        tester,
        const ProfileServicesTab(
          services: AsyncData<List<MasterService>>(_services),
        ),
      );
      expect(find.byKey(const Key('profile-category-NAILS')), findsOneWidget);
      await tester.tap(find.byKey(const Key('profile-services-all-link')));
      await tester.pumpAndSettle();
      expect(pushed, <String>[RouteNames.services]);
    });

    testWidgets('onAllServices overrides the header link', (tester) async {
      int calls = 0;
      final List<String> pushed = await _pump(
        tester,
        ProfileServicesTab(
          services: const AsyncData<List<MasterService>>(_services),
          onAllServices: () => calls++,
        ),
      );
      await tester.tap(find.byKey(const Key('profile-services-all-link')));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(pushed, isEmpty);
    });

    testWidgets('card tap default pushes expandCategory', (tester) async {
      final List<String> pushed = await _pump(
        tester,
        const ProfileServicesTab(
          services: AsyncData<List<MasterService>>(_services),
        ),
      );
      await tester.tap(find.byKey(const Key('profile-category-NAILS')));
      await tester.pumpAndSettle();
      expect(pushed, <String>['${RouteNames.services}?expandCategory=NAILS']);
    });

    testWidgets('onCategoryTap + keyPrefix override', (tester) async {
      String? tapped;
      final List<String> pushed = await _pump(
        tester,
        ProfileServicesTab(
          services: const AsyncData<List<MasterService>>(_services),
          keyPrefix: 'owner-category',
          onCategoryTap: (_, String? slug) => tapped = slug,
        ),
      );
      expect(find.byKey(const Key('profile-category-NAILS')), findsNothing);
      await tester.tap(find.byKey(const Key('owner-category-NAILS')));
      await tester.pumpAndSettle();
      expect(tapped, 'NAILS');
      expect(pushed, isEmpty);
    });
  });
}
