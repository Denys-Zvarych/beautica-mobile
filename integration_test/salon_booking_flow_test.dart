// MO-4 — E2E: CLIENT salon booking is now ONE visit against ONE chosen master,
// submitted as a SINGLE `POST /appointments` via the SHARED AppointmentSubmit
// (the same path the independent-master flow uses — NOT a forked salon submit).
//
// This replaces the pre-MO-4 multi-master journey (assign a master per service
// → per-master time picker → N `POST /bookings`), which is retired. It drives
// the REAL `SalonBookingConfirmScreen` + router + `AppointmentSubmit` through
// the app harness, faking only the `AppointmentRepository` so the single-call /
// stable-key / error-banner contract can be asserted end to end.
//
// Wired into `integration_test/all_tests.dart` (via the aggregated bundle).

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/data/appointment_repository.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/domain/appointment.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/create_appointment_request.dart';
import 'package:beautica_mobile/features/booking/domain/salon_booking_confirm_args.dart';
import 'package:beautica_mobile/features/booking/domain/salon_master_schedule.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_booking_confirm_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_booking_success_screen.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import 'support/app_harness.dart';

// ---------------------------------------------------------------------------
// Recording fake AppointmentRepository — the salon confirm screen's ONE
// `POST /appointments` submit runs against this instead of the network.
// ---------------------------------------------------------------------------
class _FakeAppointmentRepository implements AppointmentRepository {
  _FakeAppointmentRepository({this.failFirst = false});

  bool failFirst;
  final List<CreateAppointmentRequest> requests = <CreateAppointmentRequest>[];

  @override
  Future<Appointment> createAppointment(CreateAppointmentRequest req) async {
    requests.add(req);
    if (failFirst) {
      failFirst = false;
      throw const ServerFailure(statusCode: 500);
    }
    return Appointment(
      id: 'appt-1',
      status: BookingStatus.confirmed,
      masterId: req.masterId,
      masterFirstName: 'Софія',
      masterLastName: 'Мельник',
      masterType: 'SALON_MASTER',
      startAt: req.startAt,
      endAt: req.startAt.add(const Duration(hours: 3, minutes: 30)),
      totalDurationMinutes: 210,
      totalPrice: 1300,
      items: const <AppointmentItem>[],
      canReview: false,
    );
  }

  @override
  Future<Appointment> getAppointment(String id) => throw UnimplementedError();
  @override
  Future<Appointment> rescheduleAppointmentItem(
    String appointmentId,
    String bookingId,
    DateTime newStartAt,
  ) => throw UnimplementedError();
  @override
  Future<void> cancelAppointment(String id, {String? note}) =>
      throw UnimplementedError();
  @override
  Future<void> completeAppointment(String id) => throw UnimplementedError();
  @override
  Future<void> declineAppointment(String id, {String? comment}) =>
      throw UnimplementedError();
  @override
  Future<void> declineAppointmentService(
    String appointmentId,
    String bookingId, {
    String? comment,
  }) => throw UnimplementedError();
  @override
  Future<void> createAppointmentReview(
    String id, {
    required int rating,
    String? comment,
  }) => throw UnimplementedError();
}

SalonBookingConfirmArgs _visitArgs() => SalonBookingConfirmArgs(
  salonId: 'salon-xyz',
  visit: const SalonMasterSchedule(
    masterId: 'm-two',
    firstName: 'Софія',
    lastName: 'Мельник',
    type: MasterType.salonMaster,
    services: <SalonCatalogService>[
      SalonCatalogService(
        id: 'svc-1',
        name: 'Манікюр',
        durationLabel: '1 год 30 хв',
        priceDisplay: '500 ₴',
        durationMinutes: 90,
        priceType: ServicePriceType.fixed,
        priceMin: 500,
      ),
      SalonCatalogService(
        id: 'svc-2',
        name: 'Педикюр',
        durationLabel: '2 год',
        priceDisplay: '800 ₴',
        durationMinutes: 120,
        priceType: ServicePriceType.fixed,
        priceMin: 800,
      ),
    ],
    orderedMasterServiceIds: <String>['assign-m2-svc1', 'assign-m2-svc2'],
  ),
  startAt: DateTime.now().add(const Duration(days: 1)),
  idempotencyKey: 'idem-visit-1',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'CLIENT salon confirm: ONE createAppointment (chosen master + ordered ids '
    '+ stable key) → success',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()..currentRole = UserRole.client;
        final repo = _FakeAppointmentRepository();
        final GoRouter router = await AppHarness.boot(
          tester,
          fb,
          extraOverrides: <Object>[
            appointmentRepositoryProvider.overrideWithValue(repo),
          ],
        );

        await AppHarness.loginAs(tester, fb, UserRole.client);
        await AppHarness.settle(tester);

        unawaited(
          router.push(RouteNames.salonBookingConfirm, extra: _visitArgs()),
        );
        await AppHarness.settle(tester);

        expect(find.byType(SalonBookingConfirmScreen), findsOneWidget);

        await tester.tap(find.byKey(const Key('salon-confirm-submit-cta')));
        await AppHarness.settle(tester);

        expect(find.byType(SalonBookingSuccessScreen), findsOneWidget);
        expect(repo.requests, hasLength(1));
        final CreateAppointmentRequest req = repo.requests.single;
        expect(req.masterId, 'm-two');
        expect(req.masterServiceIds, <String>[
          'assign-m2-svc1',
          'assign-m2-svc2',
        ]);
        expect(req.idempotencyKey, 'idem-visit-1');
        expect(tester.takeException(), isNull);
      });
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  testWidgets(
    'CLIENT salon confirm: a failed submit shows the inline error and a retry '
    'REUSES the same idempotency key',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()..currentRole = UserRole.client;
        final repo = _FakeAppointmentRepository(failFirst: true);
        final GoRouter router = await AppHarness.boot(
          tester,
          fb,
          extraOverrides: <Object>[
            appointmentRepositoryProvider.overrideWithValue(repo),
          ],
        );

        await AppHarness.loginAs(tester, fb, UserRole.client);
        await AppHarness.settle(tester);

        unawaited(
          router.push(RouteNames.salonBookingConfirm, extra: _visitArgs()),
        );
        await AppHarness.settle(tester);

        // First submit fails → stay on confirm with the error banner.
        await tester.tap(find.byKey(const Key('salon-confirm-submit-cta')));
        await AppHarness.settle(tester);
        expect(find.byType(SalonBookingConfirmScreen), findsOneWidget);
        expect(
          find.byKey(const Key('salon-confirm-submit-error')),
          findsOneWidget,
        );
        expect(repo.requests, hasLength(1));

        // Retry succeeds → success; both requests reuse the same key.
        await tester.tap(find.byKey(const Key('salon-confirm-submit-cta')));
        await AppHarness.settle(tester);
        expect(find.byType(SalonBookingSuccessScreen), findsOneWidget);
        expect(repo.requests, hasLength(2));
        expect(repo.requests.map((r) => r.idempotencyKey).toSet(), <String>{
          'idem-visit-1',
        });
        expect(tester.takeException(), isNull);
      });
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );
}
