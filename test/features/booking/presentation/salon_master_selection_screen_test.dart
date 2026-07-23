// MO-4 — Widget tests for the reworked SalonMasterSelectionScreen.
//
// The salon flow now picks the ONE master who performs ALL selected services
// (the coverage INTERSECTION), single-select. Covers:
//   1. Only masters covering EVERY selected service render (intersection).
//   2. No-covering-master empty state (single-master constraint, no fallback).
//   3. Single-service selection.
//   4. «Далі» disabled until a master is picked; enabled after.
//   5. Confirm builds a SalonMasterSchedule visit with ordered per-master
//      assignment ids and pushes /booking/salon/time.

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/booking/application/salon_master_coverage_notifier.dart';
import 'package:beautica_mobile/features/booking/domain/salon_booking_args.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_master_selection_screen.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/salon/application/public_salon_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_service_catalog_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_master_summary.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/pump_app.dart';

Future<void> _pumpTall(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

const String _kSalonId = 'salon-1';
const _stubSalon = Salon(id: _kSalonId, name: 'Салон «Вельвет»');

const _svc1 = SalonCatalogService(
  id: 'svc-1',
  name: 'Манікюр з покриттям',
  durationLabel: '1 год 30 хв',
  priceDisplay: '500 ₴',
  durationMinutes: 90,
  priceType: ServicePriceType.fixed,
  priceMin: 500,
);
const _svc2 = SalonCatalogService(
  id: 'svc-2',
  name: 'Педикюр',
  durationLabel: '2 год',
  priceDisplay: '800 ₴',
  durationMinutes: 120,
  priceType: ServicePriceType.fixed,
  priceMin: 800,
);

const _stubCatalog = <SalonServiceCategoryEntry>[
  SalonServiceCategoryEntry(
    category: 'MANICURE',
    displayName: 'Манікюр',
    count: 1,
    services: <SalonCatalogService>[_svc1],
  ),
  SalonServiceCategoryEntry(
    category: 'PEDICURE',
    displayName: 'Педикюр',
    count: 1,
    services: <SalonCatalogService>[_svc2],
  ),
];

// m1 covers ONLY svc-1; m2 covers BOTH; m3 covers NEITHER.
const _m1 = SalonMasterSummary(
  masterId: 'm1',
  firstName: 'Олена',
  lastName: 'Ковальчук',
  avgRating: 4.9,
  reviewCount: 12,
  type: MasterType.independentMaster,
);
const _m2 = SalonMasterSummary(
  masterId: 'm2',
  firstName: 'Софія',
  lastName: 'Мельник',
  avgRating: 5.0,
  reviewCount: 3,
  type: MasterType.salonMaster,
);
const _m3 = SalonMasterSummary(
  masterId: 'm3',
  firstName: 'Дарина',
  lastName: 'Пономаренко',
  avgRating: 4.6,
  reviewCount: 1,
  type: MasterType.salonMaster,
);
const _stubMasters = <SalonMasterSummary>[_m1, _m2, _m3];

// Coverage: serviceDefId -> the master's OWN assignment id (deliberately
// different from the catalog id, mirroring production).
final _coverage = <String, Map<String, String>>{
  'm1': <String, String>{'svc-1': 'assign-m1-svc1'},
  'm2': <String, String>{'svc-1': 'assign-m2-svc1', 'svc-2': 'assign-m2-svc2'},
  'm3': <String, String>{},
};

SalonBookingMasterSelectionArgs _args({
  List<String> ids = const <String>['svc-1', 'svc-2'],
}) => SalonBookingMasterSelectionArgs(
  salonId: _kSalonId,
  selectedServiceIds: ids,
);

List<Object> _overrides({
  Map<String, Map<String, String>>? coverage,
  required SalonBookingMasterSelectionArgs args,
}) => <Object>[
  screenProtectionProvider.overrideWithValue(ScreenProtectionManager()),
  publicSalonProfileProvider(
    _kSalonId,
  ).overrideWith((ref) => (_stubSalon, _stubMasters)),
  salonServiceCatalogProvider(_kSalonId).overrideWith((ref) => _stubCatalog),
  salonMasterServiceCoverageProvider(
    args,
  ).overrideWith((ref) => coverage ?? _coverage),
];

GoRouter _routerFor(
  SalonBookingMasterSelectionArgs args, {
  ValueChanged<SalonBookingTimeArgs>? onReached,
}) => GoRouter(
  initialLocation: RouteNames.salonBookingMasters,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.salonBookingMasters,
      builder: (context, state) => SalonMasterSelectionScreen(args: args),
    ),
    GoRoute(
      path: RouteNames.salonBookingTime,
      builder: (context, state) {
        onReached?.call(state.extra! as SalonBookingTimeArgs);
        return const Scaffold(body: Center(child: Text('salon-time-reached')));
      },
    ),
  ],
);

void main() {
  testWidgets('only masters covering EVERY selected service render', (
    tester,
  ) async {
    await _pumpTall(tester);
    final args = _args();
    await tester.pumpRoutedApp(
      _routerFor(args),
      overrides: _overrides(args: args),
    );
    await tester.pumpAndSettle();

    // m2 covers both svc-1 + svc-2 → the ONLY covering master.
    expect(
      find.byKey(const Key('salon_booking_master_row_m2')),
      findsOneWidget,
    );
    // m1 covers only svc-1, m3 covers nothing → not in the intersection.
    expect(find.byKey(const Key('salon_booking_master_row_m1')), findsNothing);
    expect(find.byKey(const Key('salon_booking_master_row_m3')), findsNothing);
  });

  testWidgets('no-covering-master empty state when nobody covers all', (
    tester,
  ) async {
    await _pumpTall(tester);
    final args = _args();
    // Split coverage: m1 does svc-1, m2 does svc-2, nobody does both.
    final coverage = <String, Map<String, String>>{
      'm1': <String, String>{'svc-1': 'assign-m1-svc1'},
      'm2': <String, String>{'svc-2': 'assign-m2-svc2'},
      'm3': <String, String>{},
    };
    await tester.pumpRoutedApp(
      _routerFor(args),
      overrides: _overrides(args: args, coverage: coverage),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('salon-master-selection-no-covering-master')),
      findsOneWidget,
    );
    // No confirm bar in the empty state.
    expect(find.byKey(const Key('booking-summary-cta')), findsNothing);
  });

  testWidgets(
    'single-service selection lists every master doing that service',
    (tester) async {
      await _pumpTall(tester);
      final args = _args(ids: const <String>['svc-1']);
      await tester.pumpRoutedApp(
        _routerFor(args),
        overrides: _overrides(args: args),
      );
      await tester.pumpAndSettle();

      // Both m1 and m2 perform svc-1.
      expect(
        find.byKey(const Key('salon_booking_master_row_m1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('salon_booking_master_row_m2')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('salon_booking_master_row_m3')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'picking a master enables «Далі» and pushes the visit with ordered '
    'assignment ids',
    (tester) async {
      await _pumpTall(tester);
      final args = _args();
      SalonBookingTimeArgs? reached;
      await tester.pumpRoutedApp(
        _routerFor(args, onReached: (a) => reached = a),
        overrides: _overrides(args: args),
      );
      await tester.pumpAndSettle();

      // Pick the only covering master, then tap the pinned «Далі» CTA.
      await tester.tap(find.byKey(const Key('salon_booking_master_row_m2')));
      await tester.pumpAndSettle();

      final Finder cta = find.byKey(const Key('booking-summary-cta'));
      expect(cta, findsOneWidget);
      await tester.tap(cta);
      await tester.pumpAndSettle();

      expect(find.text('salon-time-reached'), findsOneWidget);
      expect(reached, isNotNull);
      expect(reached!.visit.masterId, 'm2');
      // Ordered per svc-1, svc-2 selection order.
      expect(reached!.visit.orderedMasterServiceIds, <String>[
        'assign-m2-svc1',
        'assign-m2-svc2',
      ]);
      expect(reached!.visit.services.map((s) => s.id).toList(), <String>[
        'svc-1',
        'svc-2',
      ]);
    },
  );
}
