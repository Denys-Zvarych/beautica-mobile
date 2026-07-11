// Phase 14.18 — Widget tests for SalonBookingSuccessScreen (salon booking
// flow step 4b: the confirmed N-appointment recap).
//
// Covers:
//   1. Lists exactly ONE SalonAppointmentCard per confirmed appointment
//      (`ValueKey('salon-success-appt-<masterId>')`) + the «Записано!»
//      headline.
//   2. Blocks back navigation (PopScope(canPop: false)).
//   3. The «На головну» CTA navigates to the CLIENT home (asserted via a
//      router sentinel, not Navigator).
//
// Strategy: real screen under a test-local GoRouter that stubs the CLIENT
// home destination — no providers needed (the success screen is a pure
// StatelessWidget-fed recap). Mirrors booking_confirm_test's success group.

import 'package:beautica_mobile/features/booking/domain/salon_booking_confirm_args.dart';
import 'package:beautica_mobile/features/booking/domain/salon_master_schedule.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_booking_success_screen.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/pump_app.dart';

Future<void> _pumpTall(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

final DateTime _kStart = DateTime(2026, 7, 20, 14);
const String _kSalonId = 'salon-1';

SalonBookingAppointment _appt(String masterId, String firstName) =>
    SalonBookingAppointment(
      schedule: SalonMasterSchedule(
        masterId: masterId,
        firstName: firstName,
        lastName: 'Ковальчук',
        type: MasterType.independentMaster,
        services: <SalonCatalogService>[
          SalonCatalogService(
            id: 'svc-$masterId',
            name: 'Манікюр',
            durationLabel: '1 год',
            priceDisplay: '500 грн',
            durationMinutes: 60,
            priceType: ServicePriceType.fixed,
            priceMin: 500,
          ),
        ],
        primaryServiceAssignmentId: 'assign-$masterId',
      ),
      startAt: _kStart,
      idempotencyKey: 'key-$masterId',
    );

SalonBookingSuccessArgs _args() => SalonBookingSuccessArgs(
  salonId: _kSalonId,
  appointments: <SalonBookingAppointment>[
    _appt('m1', 'Олена'),
    _appt('m2', 'Софія'),
  ],
);

String _locationOf(GoRouter router) =>
    router.routerDelegate.currentConfiguration.matches.last.matchedLocation;

GoRouter _router() => GoRouter(
  initialLocation: '/root',
  routes: <RouteBase>[
    GoRoute(
      path: '/root',
      builder: (context, state) => const SizedBox.shrink(),
    ),
    GoRoute(
      path: RouteNames.clientHome,
      builder: (context, state) => const SizedBox.shrink(),
    ),
    GoRoute(
      path: RouteNames.salonBookingSuccess,
      builder: (context, state) => SalonBookingSuccessScreen(
        args: state.extra! as SalonBookingSuccessArgs,
      ),
    ),
  ],
);

Future<GoRouter> _pump(WidgetTester tester) async {
  final GoRouter router = _router();
  await tester.pumpRoutedApp(router);
  router.go(RouteNames.salonBookingSuccess, extra: _args());
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets(
    'lists one card per confirmed appointment + the success headline',
    (tester) async {
      await _pumpTall(tester);
      await _pump(tester);

      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(SalonBookingSuccessScreen)),
      );

      expect(find.text(l10n.salonBookingSuccessTitle), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('salon-success-appt-m1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('salon-success-appt-m2')),
        findsOneWidget,
      );
    },
  );

  testWidgets('blocks back navigation (PopScope canPop false)', (tester) async {
    await _pumpTall(tester);
    await _pump(tester);

    final PopScope popScope = tester.widget<PopScope>(
      find.byType(PopScope).first,
    );
    expect(popScope.canPop, isFalse);
  });

  testWidgets('«На головну» navigates to the CLIENT home', (tester) async {
    await _pumpTall(tester);
    final GoRouter router = await _pump(tester);

    await tester.tap(find.byKey(const Key('salon-success-home-cta')));
    await tester.pumpAndSettle();

    expect(_locationOf(router), RouteNames.clientHome);
  });
}
