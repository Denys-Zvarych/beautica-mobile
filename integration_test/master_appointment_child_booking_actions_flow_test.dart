// Track 27.x/MO-6 — E2E: the PROVIDER footer's decline/complete/not-complete
// round trip on a booking that is part of a multi-service VISIT
// (`Booking.appointmentId != null`).
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b — integration-test gate)
// --------------------------------------------------------------
// `booking_detail_appointment_child_footer_test.dart` (widget tier) proves the
// Dart call site: an appointment-child booking routes
// complete/decline/not-complete to
// `AppointmentRepository.completeAppointment`/`declineAppointment`/
// `notCompleteAppointment` instead of the per-booking `BookingRepository`
// methods, and hides «Перенести» — but it does all of that against MOCKED
// repositories. This file closes the same gap
// `master_booking_provider_actions_flow_test.dart` closes for the plain
// single-service case: proving the fix holds against a REAL fetch of the
// booking (real login, real `GET /bookings/booking-1` via `FakeBackend`,
// real `BookingDetailScreen` reached via `router.push`) rather than a
// hand-picked `Booking` object a mocked provider was told to return.
//
// `AppointmentRepository` itself stays hand-faked here (never a real
// `/appointments/{id}/complete|decline` route on `FakeBackend`'s
// `DioAdapter`) — this mirrors `independent_multi_service_booking_flow_test
// .dart` / `client_visit_render_flow_test.dart`'s established precedent
// (avoids the generated `AppointmentControllerApi` client's real-Dio timer
// leak against the fake adapter). The routing proof instead rests on two
// independent counters: the hand-fake's own call count (the write WENT to the
// appointment endpoint) and `FakeBackend.declineBookingCalls`/
// `completeBookingCalls` staying at 0 (the write did NOT also hit the
// per-booking endpoint) — the same "prove it went to the OTHER path" shape
// `client_visit_render_flow_test.dart` uses for cancel.
//
// Track 27.x/MO-6 follow-up: `PATCH /appointments/{id}/reschedule` now exists,
// so «Перенести» is SHOWN (not hidden) on a not-yet-started appointment-child
// booking too — see the first assertion in the decline test below. This file
// does not exercise a reschedule TAP (that flow is covered against mocked
// repositories by `booking_detail_appointment_child_footer_test.dart` and
// `reschedule_navigation_test.dart`'s `startAppointmentReschedule` group); the
// fake here still throws `UnimplementedError` for it.
//
// The hand-fake also flips `FakeBackend.bookingStatus` on a successful write
// so the screen's own `ref.invalidate(bookingDetailProvider(...))` triggers a
// REAL re-fetch that reflects the terminal status — proving the invalidate →
// refetch → terminal-footer chain holds for the appointment-child branch too,
// not just that the call landed.
//
// KEY POLICY (AppHarness): all TAPS are key-based; Ukrainian text appears
// nowhere in this file — every assertion is by key or call count.

import 'dart:async';

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/data/appointment_repository.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/domain/appointment.dart';
import 'package:beautica_mobile/features/booking/domain/create_appointment_request.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

/// The whole-visit provider write path, hand-faked (see the file header for
/// why no real `/appointments` adapter route exists). Only
/// [completeAppointment]/[declineAppointment] are exercised here — every
/// other member throws [UnimplementedError], matching this suite's other
/// appointment hand-fakes (`client_visit_render_flow_test.dart`'s
/// `_FakeAppointmentRepository`).
class _FakeAppointmentRepository implements AppointmentRepository {
  _FakeAppointmentRepository(this._fb);

  final FakeBackend _fb;

  int completeCalls = 0;
  int declineCalls = 0;
  int notCompleteCalls = 0;
  String? lastCompleteId;
  String? lastDeclineId;
  String? lastDeclineComment;
  String? lastNotCompleteId;
  String? lastNotCompleteComment;

  @override
  Future<void> completeAppointment(String id) async {
    completeCalls++;
    lastCompleteId = id;
    // Flips the REAL fake-backed booking to COMPLETED so the screen's own
    // post-write `ref.invalidate(bookingDetailProvider(...))` re-fetches a
    // terminal status through the real HTTP boundary, not a value this fake
    // merely remembers.
    _fb.bookingStatus = 'COMPLETED';
  }

  @override
  Future<void> declineAppointment(String id, {String? comment}) async {
    declineCalls++;
    lastDeclineId = id;
    lastDeclineComment = comment;
    _fb.bookingStatus = 'DECLINED';
  }

  @override
  Future<void> notCompleteAppointment(String id, {String? comment}) async {
    notCompleteCalls++;
    lastNotCompleteId = id;
    lastNotCompleteComment = comment;
    _fb.bookingStatus = 'NOT_COMPLETED';
  }

  @override
  Future<Appointment> getAppointment(String id) => throw UnimplementedError();

  @override
  Future<Appointment> rescheduleAppointment(String id, DateTime newStartAt) =>
      throw UnimplementedError();

  @override
  Future<void> cancelAppointment(String id, {String? note}) =>
      throw UnimplementedError();

  @override
  Future<Appointment> createAppointment(CreateAppointmentRequest req) =>
      throw UnimplementedError();

  @override
  Future<void> createAppointmentReview(
    String id, {
    required int rating,
    String? comment,
  }) => throw UnimplementedError();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  /// Boots the app as an INDEPENDENT_MASTER, seeds `booking-1` as an
  /// appointment child (`appointmentId: 'appt-1'`), and pushes its detail
  /// route.
  Future<GoRouter> bootAndOpenDetail(
    WidgetTester tester,
    FakeBackend fb,
    _FakeAppointmentRepository fakeAppt,
  ) async {
    fb.currentRole = UserRole.independentMaster;
    fb.bookingAppointmentId = 'appt-1';
    final GoRouter router = await AppHarness.boot(
      tester,
      fb,
      extraOverrides: <Object>[
        appointmentRepositoryProvider.overrideWithValue(fakeAppt),
      ],
    );
    await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

    unawaited(router.push(RouteNames.masterBookingDetail('booking-1')));
    await AppHarness.settle(tester);
    expect(find.byType(BookingDetailScreen), findsOneWidget);
    return router;
  }

  testWidgets(
    'PROVIDER declines an appointment-child (multi-service visit) booking → '
    'routes to AppointmentRepository.declineAppointment, never '
    'BookingRepository.declineBooking, reschedule stays hidden, and the '
    'status persists as terminal across a real re-fetch',
    (tester) async {
      final fb = FakeBackend();
      final fakeAppt = _FakeAppointmentRepository(fb);
      await bootAndOpenDetail(tester, fb, fakeAppt);

      // ── Footer: «Перенести» + decline both offered — track 27.x/MO-6 added
      //    `PATCH /appointments/{id}/reschedule`, so an appointment-child
      //    booking now offers reschedule too, same as a plain one. ─────────
      expect(
        find.byKey(const Key('booking-detail-decline')),
        findsOneWidget,
        reason: 'CONFIRMED + not started must offer decline',
      );
      expect(
        find.byKey(const Key('booking-detail-provider-reschedule')),
        findsOneWidget,
        reason: 'the provider-facing appointment-reschedule endpoint exists',
      );
      expect(find.byKey(const Key('booking-detail-complete')), findsNothing);

      await tester.tap(find.byKey(const Key('booking-detail-decline')));
      await AppHarness.settle(tester);
      expect(find.byKey(const Key('decline-booking-dialog')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('cancel-booking-note-field')),
        'Client rescheduled elsewhere.',
      );
      await tester.tap(find.byKey(const Key('decline-booking-confirm')));
      await AppHarness.settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('decline-booking-dialog')), findsNothing);

      // ── The write went to the WHOLE-VISIT endpoint, never the per-booking
      //    one — the exact regression this suite pins. ────────────────────
      expect(fakeAppt.declineCalls, 1);
      expect(fakeAppt.lastDeclineId, 'appt-1');
      expect(fakeAppt.lastDeclineComment, 'Client rescheduled elsewhere.');
      expect(
        fb.declineBookingCalls,
        0,
        reason:
            'an appointment-child decline must never reach the per-booking '
            'PATCH /bookings/{id}/decline endpoint',
      );

      // ── The status PERSISTS across a real re-fetch: the footer goes fully
      //    terminal. ────────────────────────────────────────────────────────
      expect(find.byKey(const Key('booking-detail-decline')), findsNothing);
      expect(
        find.byKey(const Key('booking-detail-provider-reschedule')),
        findsNothing,
      );
      expect(find.byKey(const Key('booking-detail-complete')), findsNothing);
    },
  );

  testWidgets(
    'PROVIDER completes an underway appointment-child (multi-service visit) '
    'booking → routes to AppointmentRepository.completeAppointment, never '
    'BookingRepository.completeBooking, and the status persists as terminal '
    'across a real re-fetch',
    (tester) async {
      final fb = FakeBackend();
      final fakeAppt = _FakeAppointmentRepository(fb);

      // Wide, wall-clock-safe "underway" window (mirrors
      // `master_booking_provider_actions_flow_test.dart`) — started well in
      // the past, ends well in the future, so `hasStarted` is
      // deterministically true regardless of how long this test takes.
      final DateTime start = DateTime.now().toUtc().subtract(
        const Duration(hours: 1),
      );
      final DateTime end = start.add(const Duration(hours: 4));
      fb.bookingStartsAt = start.toIso8601String();
      fb.bookingEndsAt = end.toIso8601String();

      await bootAndOpenDetail(tester, fb, fakeAppt);

      expect(
        find.byKey(const Key('booking-detail-complete')),
        findsOneWidget,
        reason: 'an underway CONFIRMED booking must offer complete only',
      );
      expect(find.byKey(const Key('booking-detail-decline')), findsNothing);
      expect(
        find.byKey(const Key('booking-detail-provider-reschedule')),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('booking-detail-complete')));
      await AppHarness.settle(tester);
      expect(find.byKey(const Key('complete-booking-dialog')), findsOneWidget);

      await tester.tap(find.byKey(const Key('complete-booking-confirm')));
      await AppHarness.settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('complete-booking-dialog')), findsNothing);

      // ── The write went to the WHOLE-VISIT endpoint, never the per-booking
      //    one. ─────────────────────────────────────────────────────────────
      expect(fakeAppt.completeCalls, 1);
      expect(fakeAppt.lastCompleteId, 'appt-1');
      expect(
        fb.completeBookingCalls,
        0,
        reason:
            'an appointment-child complete must never reach the per-booking '
            'PATCH /bookings/{id}/complete endpoint',
      );

      // ── The status PERSISTS across a real re-fetch: terminal footer. ──────
      expect(find.byKey(const Key('booking-detail-complete')), findsNothing);
    },
  );

  testWidgets(
    'PROVIDER marks an elapsed appointment-child (multi-service visit) '
    'booking as a no-show → routes to '
    'AppointmentRepository.notCompleteAppointment, never '
    'BookingRepository.notCompleteBooking, and the status persists as '
    'terminal across a real re-fetch',
    (tester) async {
      final fb = FakeBackend();
      final fakeAppt = _FakeAppointmentRepository(fb);

      // Same wide, wall-clock-safe "underway/elapsed" window as the complete
      // test above.
      final DateTime start = DateTime.now().toUtc().subtract(
        const Duration(hours: 1),
      );
      final DateTime end = start.add(const Duration(hours: 4));
      fb.bookingStartsAt = start.toIso8601String();
      fb.bookingEndsAt = end.toIso8601String();

      await bootAndOpenDetail(tester, fb, fakeAppt);

      expect(
        find.byKey(const Key('booking-detail-complete')),
        findsOneWidget,
        reason: 'an underway CONFIRMED booking must offer complete',
      );
      expect(
        find.byKey(const Key('booking-detail-not-complete')),
        findsOneWidget,
        reason: 'an underway CONFIRMED booking must ALSO offer no-show',
      );
      expect(find.byKey(const Key('booking-detail-decline')), findsNothing);
      expect(
        find.byKey(const Key('booking-detail-provider-reschedule')),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('booking-detail-not-complete')));
      await AppHarness.settle(tester);
      expect(
        find.byKey(const Key('not-complete-booking-dialog')),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const Key('cancel-booking-note-field')),
        'Client never arrived, could not reach them.',
      );
      await tester.tap(find.byKey(const Key('not-complete-booking-confirm')));
      await AppHarness.settle(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const Key('not-complete-booking-dialog')),
        findsNothing,
      );

      // ── The write went to the WHOLE-VISIT endpoint, never the per-booking
      //    one — the exact regression this suite pins. ────────────────────
      expect(fakeAppt.notCompleteCalls, 1);
      expect(fakeAppt.lastNotCompleteId, 'appt-1');
      expect(
        fakeAppt.lastNotCompleteComment,
        'Client never arrived, could not reach them.',
      );
      expect(
        fb.notCompleteBookingCalls,
        0,
        reason:
            'an appointment-child no-show must never reach the per-booking '
            'PATCH /bookings/{id}/not-complete endpoint',
      );

      // ── The status PERSISTS across a real re-fetch: terminal footer. ──────
      expect(
        find.byKey(const Key('booking-detail-not-complete')),
        findsNothing,
      );
      expect(find.byKey(const Key('booking-detail-complete')), findsNothing);
    },
  );
}
