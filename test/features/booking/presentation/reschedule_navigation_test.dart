// mobile-qa (track 24.x booking auto-confirm) — guard coverage for
// [startBookingReschedule].
//
// booking_detail_interactions_test.dart proves the HAPPY path (a CONFIRMED
// booking → the slot picker seeded with `rescheduleBookingId`). This suite pins
// the three short-circuits the helper owns — each must surface the calm
// «Цей запис не можна перенести» / «errUnknown» SnackBar and NEVER navigate:
//
//   1. a non-CONFIRMED booking (defensive — the CTA is confirmed-gated, but the
//      helper must not rely on that);
//   2. a CONFIRMED booking whose booked service is no longer in the master's
//      public catalogue (nothing to fetch slots against);
//   3. a booking-detail load error (the catch-all branch → errUnknown).
//
// Track 27.x/MO-6 — the second `main.dart` group below mirrors ALL THREE guards
// for [startAppointmentReschedule] (the whole-VISIT sibling), plus the HAPPY
// path (a CONFIRMED visit → the slot picker seeded with the visit's FULL
// ordered service selection and `rescheduleAppointmentId`).
//
// Finders are key-first; every string is asserted through l10n (CI no-raw-Cyrillic
// gate). The helper is driven inside a real `GoRouter` whose `RouteNames.bookingSlots`
// stub flips a flag — so "did not navigate" is a positive assertion, not the
// absence of an exception.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/booking/application/appointment_detail_notifier.dart';
import 'package:beautica_mobile/features/booking/application/booking_detail_notifier.dart';
import 'package:beautica_mobile/features/booking/domain/appointment.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot_picker_args.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/reschedule_navigation.dart';
import 'package:beautica_mobile/features/master/application/public_master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/pump_app.dart';

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

  /// The `extra` the `RouteNames.bookingSlots` stub was pushed with — only
  /// populated by [startAppointmentReschedule]'s driver ([driveAppointment]
  /// below); `startBookingReschedule`'s own [_drive] never sets it.
  BookingSlotPickerArgs? pushedArgs;
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

      expect(
        find.text(_l10n(tester).bookingRescheduleUnavailable),
        findsOneWidget,
      );
      expect(probe.navigated, isFalse);
      expect(find.byKey(const Key('slots_stub')), findsNothing);
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

      expect(
        find.text(_l10n(tester).bookingRescheduleUnavailable),
        findsOneWidget,
      );
      expect(probe.navigated, isFalse);
      expect(find.byKey(const Key('slots_stub')), findsNothing);
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

      expect(find.text(_l10n(tester).errUnknown), findsOneWidget);
      expect(probe.navigated, isFalse);
      expect(find.byKey(const Key('slots_stub')), findsNothing);
    },
  );

  // ---------------------------------------------------------------------------
  // Track 27.x/MO-6 — [startAppointmentReschedule], the whole-VISIT sibling.
  // ---------------------------------------------------------------------------

  group('startAppointmentReschedule', () {
    const String appointmentId = 'appt-1';
    const String triggeringBookingId = 'booking-of-item-1';

    Appointment appointmentFixture({required BookingStatus status}) {
      final DateTime start = DateTime.utc(2026, 7, 20, 15);
      return Appointment(
        id: appointmentId,
        status: status,
        masterId: _masterId,
        masterFirstName: 'Софія',
        masterLastName: 'Бондар',
        masterType: 'INDEPENDENT_MASTER',
        startAt: start,
        endAt: start.add(const Duration(minutes: 150)),
        totalDurationMinutes: 150,
        totalPrice: 1150,
        items: <AppointmentItem>[
          AppointmentItem(
            bookingId: triggeringBookingId,
            masterServiceId: _serviceId,
            serviceName: 'Манікюр з покриттям',
            startAt: start,
            endAt: start.add(const Duration(minutes: 90)),
            durationMinutes: 90,
            price: 650,
          ),
          AppointmentItem(
            bookingId: 'booking-of-item-2',
            masterServiceId: 'pub-assign-2',
            serviceName: 'Педикюр',
            startAt: start.add(const Duration(minutes: 90)),
            endAt: start.add(const Duration(minutes: 150)),
            durationMinutes: 60,
            price: 500,
          ),
        ],
        canReview: false,
      );
    }

    const MasterService secondBookedService = MasterService(
      id: 'pub-assign-2',
      serviceDefId: 'pub-svc-2',
      name: 'Педикюр',
      durationMinutes: 60,
      priceMin: 500,
      priceDisplay: '500 ₴',
      category: 'NAILS',
    );

    /// Drives [startAppointmentReschedule] once from a `/start` button and
    /// reports whether the [RouteNames.bookingSlots] stub was reached, and (on
    /// success) what [BookingSlotPickerArgs] it was pushed with.
    Future<_NavProbe> driveAppointment(
      WidgetTester tester, {
      required Future<Appointment> Function() detail,
      required List<MasterService> services,
    }) async {
      final _NavProbe probe = _NavProbe();
      BookingSlotPickerArgs? pushedArgs;
      final GoRouter router = GoRouter(
        initialLocation: '/start',
        routes: <RouteBase>[
          GoRoute(
            path: '/start',
            builder: (BuildContext context, _) => Scaffold(
              body: Consumer(
                builder: (BuildContext context, WidgetRef ref, _) => TextButton(
                  key: const Key('go'),
                  onPressed: () => startAppointmentReschedule(
                    context: context,
                    ref: ref,
                    appointmentId: appointmentId,
                    bookingId: triggeringBookingId,
                  ),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: RouteNames.bookingSlots,
            builder: (_, GoRouterState state) {
              probe.navigated = true;
              pushedArgs = state.extra as BookingSlotPickerArgs?;
              return const Scaffold(key: Key('slots_stub'));
            },
          ),
        ],
      );

      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[
          appointmentDetailProvider(
            appointmentId,
          ).overrideWith((ref) => detail()),
          publicMasterProfileProvider(
            _masterId,
          ).overrideWith((ref) async => (_master, services)),
        ],
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('go')));
      await tester.pumpAndSettle();
      probe.pushedArgs = pushedArgs;
      return probe;
    }

    testWidgets(
      'a CONFIRMED visit seeds the slot picker with the FULL ordered service '
      'selection and rescheduleAppointmentId — never navigating via '
      'startBookingReschedule\'s single-service shape',
      (tester) async {
        final _NavProbe probe = await driveAppointment(
          tester,
          detail: () async =>
              appointmentFixture(status: BookingStatus.confirmed),
          services: const <MasterService>[_bookedService, secondBookedService],
        );

        expect(probe.navigated, isTrue);
        final BookingSlotPickerArgs? args = probe.pushedArgs;
        expect(args, isNotNull);
        expect(args!.rescheduleAppointmentId, appointmentId);
        expect(args.rescheduleBookingId, triggeringBookingId);
        expect(args.services, hasLength(2));
        expect(args.services[0].id, _serviceId);
        expect(args.services[1].id, 'pub-assign-2');
      },
    );

    testWidgets(
      'a non-CONFIRMED visit short-circuits with «не можна перенести» and '
      'does not navigate',
      (tester) async {
        final _NavProbe probe = await driveAppointment(
          tester,
          detail: () async =>
              appointmentFixture(status: BookingStatus.declined),
          services: const <MasterService>[_bookedService, secondBookedService],
        );

        expect(
          find.text(_l10n(tester).appointmentRescheduleUnavailable),
          findsOneWidget,
        );
        expect(probe.navigated, isFalse);
        expect(find.byKey(const Key('slots_stub')), findsNothing);
      },
    );

    testWidgets('a CONFIRMED visit whose FIRST item is gone from the catalogue '
        'short-circuits with «не можна перенести» and does not navigate', (
      tester,
    ) async {
      final _NavProbe probe = await driveAppointment(
        tester,
        detail: () async => appointmentFixture(status: BookingStatus.confirmed),
        // Only the SECOND item's service remains — the first is absent.
        services: const <MasterService>[secondBookedService],
      );

      expect(
        find.text(_l10n(tester).appointmentRescheduleUnavailable),
        findsOneWidget,
      );
      expect(probe.navigated, isFalse);
      expect(find.byKey(const Key('slots_stub')), findsNothing);
    });

    testWidgets(
      'an appointment-detail load error surfaces errUnknown and does not '
      'navigate',
      (tester) async {
        final _NavProbe probe = await driveAppointment(
          tester,
          detail: () async => throw const ServerFailure(statusCode: 500),
          services: const <MasterService>[_bookedService, secondBookedService],
        );

        expect(find.text(_l10n(tester).errUnknown), findsOneWidget);
        expect(probe.navigated, isFalse);
        expect(find.byKey(const Key('slots_stub')), findsNothing);
      },
    );
  });
}
