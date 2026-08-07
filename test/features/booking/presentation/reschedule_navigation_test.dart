// mobile-qa (track 24.x booking auto-confirm) — guard coverage for
// [startBookingReschedule].
//
// booking_detail_interactions_test.dart proves the HAPPY path (a CONFIRMED
// booking → the slot picker seeded with `rescheduleBookingId`). This suite pins
// the three short-circuits the helper owns — each must surface the calm
// «Цей запис не можна перенести» / «errUnknown» VelvetSnack and NEVER navigate:
//
//   1. a non-CONFIRMED booking (defensive — the CTA is confirmed-gated, but the
//      helper must not rely on that);
//   2. a CONFIRMED booking whose booked service is no longer in the master's
//      public catalogue (nothing to fetch slots against);
//   3. a booking-detail load error (the catch-all branch → errUnknown).
//
// Track 30.x — [startBookingReschedule] now ALSO doubles as the per-item
// VISIT reschedule entry point (an optional `appointmentId` parameter,
// forwarded onto `BookingSlotPickerArgs.rescheduleAppointmentId`), superseding
// the retired whole-VISIT `startAppointmentReschedule` sibling that used to
// live in this file's second `main()` group. `booking_detail_appointment_
// child_footer_test.dart` covers the appointment-child routing end to end
// (via `BookingDetailScreen`); this file stays scoped to the three guards
// above, which apply identically regardless of `appointmentId`.
//
// Finders are key-first; every string is asserted through l10n (CI no-raw-Cyrillic
// gate). The helper is driven inside a real `GoRouter` whose `RouteNames.bookingSlots`
// stub flips a flag — so "did not navigate" is a positive assertion, not the
// absence of an exception.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/booking/application/booking_detail_notifier.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/reschedule_navigation.dart';
import 'package:beautica_mobile/features/master/application/public_master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/pump_app.dart';
import '../../../helpers/velvet_snack_matchers.dart';

const String _bookingId = 'booking-1';
const String _masterId = 'master-aaa';
const String _serviceId = 'pub-assign-1';

const Master _master = Master(
  id: _masterId,
  firstName: 'Софія',
  lastName: 'Бондар',
  avgRating: 4.9,
  reviewCount: 24,
  type: MasterType.independentMaster,
);

const MasterService _bookedService = MasterService(
  id: _serviceId,
  serviceDefId: 'pub-svc-1',
  name: 'Манікюр з покриттям',
  durationMinutes: 90,
  priceMin: 650,
  priceDisplay: '650 ₴',
  category: 'NAILS',
);

Booking _booking({required BookingStatus status}) {
  final DateTime start = DateTime.utc(2026, 7, 20, 15);
  return Booking(
    id: _bookingId,
    masterId: _masterId,
    masterFirstName: 'Софія',
    masterLastName: 'Бондар',
    masterType: 'INDEPENDENT_MASTER',
    serviceId: _serviceId,
    serviceName: 'Манікюр з покриттям',
    durationMinutes: 90,
    price: 650,
    startAt: start,
    endAt: start.add(const Duration(minutes: 90)),
    status: status,
    canReview: false,
  );
}

/// Drives [startBookingReschedule] once from a `/start` button and reports
/// whether the [RouteNames.bookingSlots] stub was reached. [detail] overrides
/// the booking-detail load (return a booking, or throw for the error case);
/// [services] is the master's public catalogue the helper resolves against.
class _NavProbe {
  bool navigated = false;
}

Future<_NavProbe> _drive(
  WidgetTester tester, {
  required Future<Booking> Function() detail,
  required List<MasterService> services,
}) async {
  final _NavProbe probe = _NavProbe();
  final GoRouter router = GoRouter(
    initialLocation: '/start',
    routes: <RouteBase>[
      GoRoute(
        path: '/start',
        builder: (BuildContext context, _) => Scaffold(
          body: Consumer(
            builder: (BuildContext context, WidgetRef ref, _) => TextButton(
              key: const Key('go'),
              onPressed: () => startBookingReschedule(
                context: context,
                ref: ref,
                bookingId: _bookingId,
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: RouteNames.bookingSlots,
        builder: (_, _) {
          probe.navigated = true;
          return const Scaffold(key: Key('slots_stub'));
        },
      ),
    ],
  );

  await tester.pumpRoutedApp(
    router,
    overrides: <Object>[
      bookingDetailProvider(_bookingId).overrideWith((ref) => detail()),
      publicMasterProfileProvider(
        _masterId,
      ).overrideWith((ref) async => (_master, services)),
    ],
  );
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const Key('go')));
  await tester.pumpAndSettle();
  return probe;
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byKey(const Key('go'))));

void main() {
  testWidgets(
    'a non-CONFIRMED booking short-circuits with «не можна перенести» and does '
    'not navigate',
    (tester) async {
      final _NavProbe probe = await _drive(
        tester,
        detail: () async => _booking(status: BookingStatus.declined),
        services: const <MasterService>[_bookedService],
      );

      expectVelvetSnack(
        _l10n(tester).bookingRescheduleUnavailable,
        variant: VelvetSnackVariant.warning,
      );
      expect(probe.navigated, isFalse);
      expect(find.byKey(const Key('slots_stub')), findsNothing);
      // Drains the dwell Timer — otherwise flutter_test flags it as a leak.
      await pumpPastVelvetSnack(tester);
    },
  );

  testWidgets(
    'a CONFIRMED booking whose booked service is gone from the catalogue '
    'short-circuits with «не можна перенести» and does not navigate',
    (tester) async {
      final _NavProbe probe = await _drive(
        tester,
        detail: () async => _booking(status: BookingStatus.confirmed),
        // The booked service (`pub-assign-1`) is absent — only an unrelated one.
        services: const <MasterService>[
          MasterService(
            id: 'some-other-service',
            serviceDefId: 'def-x',
            name: 'Педикюр',
            durationMinutes: 60,
            priceMin: 500,
            priceDisplay: '500 ₴',
            category: 'NAILS',
          ),
        ],
      );

      expectVelvetSnack(
        _l10n(tester).bookingRescheduleUnavailable,
        variant: VelvetSnackVariant.warning,
      );
      expect(probe.navigated, isFalse);
      expect(find.byKey(const Key('slots_stub')), findsNothing);
      await pumpPastVelvetSnack(tester);
    },
  );

  testWidgets(
    'a booking-detail load error surfaces errUnknown and does not navigate',
    (tester) async {
      final _NavProbe probe = await _drive(
        tester,
        detail: () async => throw const ServerFailure(statusCode: 500),
        services: const <MasterService>[_bookedService],
      );

      expectVelvetSnack(
        _l10n(tester).errUnknown,
        variant: VelvetSnackVariant.error,
      );
      expect(probe.navigated, isFalse);
      expect(find.byKey(const Key('slots_stub')), findsNothing);
      await pumpPastVelvetSnack(tester);
    },
  );
}
