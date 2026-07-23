// MO-4 — Widget tests for the reworked SalonBookingSuccessScreen (single visit).

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/booking/domain/salon_booking_confirm_args.dart';
import 'package:beautica_mobile/features/booking/domain/salon_master_schedule.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_booking_success_screen.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/salon/application/public_salon_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_master_summary.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/pump_app.dart';

const String _kSalonId = 'salon-1';
const _stubSalon = Salon(
  id: _kSalonId,
  name: 'Салон «Вельвет»',
  street: 'вул. Хрещатик',
  buildingNo: '1',
);

const _svc1 = SalonCatalogService(
  id: 'svc-1',
  name: 'Манікюр з покриттям',
  durationLabel: '1 год 30 хв',
  priceDisplay: '500 ₴',
  durationMinutes: 90,
  priceType: ServicePriceType.fixed,
  priceMin: 500,
);

const _visit = SalonMasterSchedule(
  masterId: 'm2',
  firstName: 'Софія',
  lastName: 'Мельник',
  type: MasterType.salonMaster,
  avgRating: 5.0,
  reviewCount: 3,
  services: <SalonCatalogService>[_svc1],
  orderedMasterServiceIds: <String>['assign-m2-svc1'],
);

SalonBookingSuccessArgs _args() => SalonBookingSuccessArgs(
  salonId: _kSalonId,
  visit: _visit,
  startAt: DateTime(2026, 7, 20, 14),
);

GoRouter _router() => GoRouter(
  initialLocation: RouteNames.salonBookingSuccess,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.salonBookingSuccess,
      builder: (context, state) => SalonBookingSuccessScreen(args: _args()),
    ),
    GoRoute(
      path: RouteNames.clientHome,
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('client-home-reached'))),
    ),
  ],
);

List<Object> _overrides() => <Object>[
  screenProtectionProvider.overrideWithValue(ScreenProtectionManager()),
  publicSalonProfileProvider(
    _kSalonId,
  ).overrideWith((ref) => (_stubSalon, const <SalonMasterSummary>[])),
];

void main() {
  testWidgets('renders the confirmed visit recap + address + home CTA', (
    tester,
  ) async {
    await tester.pumpRoutedApp(_router(), overrides: _overrides());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('salon-success-visit-card')), findsOneWidget);
    expect(find.byKey(const Key('salon-success-address-card')), findsOneWidget);
    expect(find.byKey(const Key('salon-success-home-cta')), findsOneWidget);
    // i18n-finder-ok: service name is backend fixture data, not localized UI copy
    expect(find.text('Манікюр з покриттям'), findsOneWidget);
  });

  testWidgets('«На головну» routes to the client home', (tester) async {
    await tester.pumpRoutedApp(_router(), overrides: _overrides());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('salon-success-home-cta')));
    await tester.pumpAndSettle();
    expect(find.text('client-home-reached'), findsOneWidget);
  });
}
