// Track 27.x/MO-6 — E2E: the PROVIDER footer's decline/complete round trip on
// a booking that is part of a multi-service VISIT (`Booking.appointmentId !=
// null`).
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b — integration-test gate)
// --------------------------------------------------------------
// `booking_detail_appointment_child_footer_test.dart` (widget tier) proves the
// Dart call site: an appointment-child booking routes complete to
// `AppointmentRepository.completeAppointment` and decline to the PER-SERVICE
// `AppointmentRepository.declineAppointmentService(appointmentId, bookingId)`
// (`PATCH /appointments/{id}/services/{bookingId}/decline`) — declining ONLY
// the tapped service, NEVER the whole-visit `declineAppointment` (the CRITICAL
// bug: it cancelled every service of the visit at once) nor the per-booking
// `BookingRepository` methods — but it does all of that against MOCKED
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

  /// WHOLE-VISIT decline (`PATCH /appointments/{id}/decline`) — the OLD routing
  /// the CRITICAL bug used, which declined EVERY service of the visit at once.
  /// The per-service fix must NEVER call this, so it only records: every
  /// decline test below asserts [declineCalls] stays 0.
  int declineCalls = 0;

  /// PER-SERVICE decline (`PATCH /appointments/{id}/services/{bookingId}/
  /// decline`) — the FIXED routing. Records the exact (appointmentId, bookingId,
  /// comment) the screen passed and flips ONLY that child's status on the fake
  /// backend via [FakeBackend.declineChild], leaving the visit's siblings
  /// untouched.
  int declineServiceCalls = 0;
  String? lastCompleteId;
  String? lastDeclineId;
  String? lastDeclineComment;
  String? lastDeclineServiceAppointmentId;
  String? lastDeclineServiceBookingId;
  String? lastDeclineServiceComment;

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
  Future<void> declineAppointmentService(
    String appointmentId,
    String bookingId, {
    String? comment,
  }) async {
    declineServiceCalls++;
    lastDeclineServiceAppointmentId = appointmentId;
    lastDeclineServiceBookingId = bookingId;
    lastDeclineServiceComment = comment;
    // Flips ONLY the tapped child (`bookingId`) to DECLINED on the real
    // fake-backed detail, so the screen's post-write
    // `ref.invalidate(bookingDetailProvider(bookingId))` re-fetches a terminal
    // status for THIS child while any sibling child stays CONFIRMED.
    _fb.declineChild(bookingId);
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
  Future<Appointment> createAppointment(CreateAppointmentRequest req) =>
      throw UnimplementedError();
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
    'routes to AppointmentRepository.declineAppointmentService(appointmentId, '
    'bookingId) — the PER-SERVICE endpoint — never the whole-visit '
    'declineAppointment nor BookingRepository.declineBooking, and the status '
    'persists as terminal across a real re-fetch',
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

      // ── The write went to the PER-SERVICE endpoint with THIS child's id,
      //    never the whole-visit decline (the CRITICAL bug) nor the per-booking
      //    one — the exact regression this suite pins. ─────────────────────
      expect(fakeAppt.declineServiceCalls, 1);
      expect(fakeAppt.lastDeclineServiceAppointmentId, 'appt-1');
      expect(fakeAppt.lastDeclineServiceBookingId, 'booking-1');
      expect(
        fakeAppt.lastDeclineServiceComment,
        'Client rescheduled elsewhere.',
      );
      expect(
        fakeAppt.declineCalls,
        0,
        reason:
            'an appointment-child decline must never reach the WHOLE-VISIT '
            'PATCH /appointments/{id}/decline endpoint — that cancelled every '
            'service of the visit (the CRITICAL bug this fixes)',
      );
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
      // `BookingDisplayX.hasStarted`/`.isPast` compare against the DEVICE
      // clock on purpose (both `instant-ok` annotated in
      // `lib/features/booking/domain/booking_display_x.dart`) — a
      // presentation-only "has this slot passed" signal, deliberately NOT
      // the injected `clockProvider` instant. A `kFixedNow`-anchored window
      // would classify as long-elapsed, not underway. See the two-clock
      // model documented on `FakeBackend.serverNow`.
      // instant-ok: fixture tracks the DEVICE clock BookingDisplayX reads
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
        find.byKey(const Key('booking-detail-decline')),
        findsOneWidget,
        reason:
            'decline stays offered on an underway booking too — the backend '
            'allows a provider decline at any time',
      );
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
      expect(find.byKey(const Key('booking-detail-decline')), findsNothing);
    },
  );

  testWidgets(
    'PROVIDER declines an underway (elapsed) appointment-child (multi-service '
    'visit) booking → still routes to '
    'AppointmentRepository.declineAppointmentService(appointmentId, bookingId), '
    'never the whole-visit declineAppointment nor '
    'BookingRepository.declineBooking, and the status persists as terminal '
    'across a real re-fetch',
    (tester) async {
      final fb = FakeBackend();
      final fakeAppt = _FakeAppointmentRepository(fb);

      // Same wide, wall-clock-safe "underway/elapsed" window as the complete
      // test above.
      // `BookingDisplayX.hasStarted`/`.isPast` compare against the DEVICE
      // clock on purpose (both `instant-ok` annotated in
      // `lib/features/booking/domain/booking_display_x.dart`) — a
      // presentation-only "has this slot passed" signal, deliberately NOT
      // the injected `clockProvider` instant. A `kFixedNow`-anchored window
      // would classify as long-elapsed, not underway. See the two-clock
      // model documented on `FakeBackend.serverNow`.
      // instant-ok: fixture tracks the DEVICE clock BookingDisplayX reads
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
        find.byKey(const Key('booking-detail-decline')),
        findsOneWidget,
        reason:
            'the backend allows a provider decline at any time, so it stays '
            'offered on an underway/elapsed booking too',
      );
      expect(
        find.byKey(const Key('booking-detail-provider-reschedule')),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('booking-detail-decline')));
      await AppHarness.settle(tester);
      expect(find.byKey(const Key('decline-booking-dialog')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('cancel-booking-note-field')),
        'Client never arrived, could not reach them.',
      );
      await tester.tap(find.byKey(const Key('decline-booking-confirm')));
      await AppHarness.settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('decline-booking-dialog')), findsNothing);

      // ── The write went to the PER-SERVICE endpoint with THIS child's id,
      //    never the whole-visit decline nor the per-booking one — the exact
      //    regression this suite pins. ─────────────────────────────────────
      expect(fakeAppt.declineServiceCalls, 1);
      expect(fakeAppt.lastDeclineServiceAppointmentId, 'appt-1');
      expect(fakeAppt.lastDeclineServiceBookingId, 'booking-1');
      expect(
        fakeAppt.lastDeclineServiceComment,
        'Client never arrived, could not reach them.',
      );
      expect(fakeAppt.declineCalls, 0);
      expect(
        fb.declineBookingCalls,
        0,
        reason:
            'an appointment-child decline must never reach the per-booking '
            'PATCH /bookings/{id}/decline endpoint',
      );

      // ── The status PERSISTS across a real re-fetch: terminal footer. ──────
      expect(find.byKey(const Key('booking-detail-decline')), findsNothing);
      expect(find.byKey(const Key('booking-detail-complete')), findsNothing);
    },
  );

  testWidgets(
    'PER-SERVICE regression — PROVIDER declines ONE service of a multi-service '
    'visit → only that child transitions to DECLINED (per-service endpoint hit '
    'with THIS child id), while a SIBLING child of the same visit stays '
    'CONFIRMED across a real re-fetch',
    (tester) async {
      final fb = FakeBackend();
      final fakeAppt = _FakeAppointmentRepository(fb);
      // Both `booking-1` and `booking-2` are children of the SAME visit
      // (`appt-1`). `booking-2` starts CONFIRMED (FakeBackend default) — the
      // sibling whose survival is the whole point of the per-service fix.
      final GoRouter router = await bootAndOpenDetail(tester, fb, fakeAppt);

      // ── Decline ONLY `booking-1` (the child currently on screen). ─────────
      await tester.tap(find.byKey(const Key('booking-detail-decline')));
      await AppHarness.settle(tester);
      expect(find.byKey(const Key('decline-booking-dialog')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('cancel-booking-note-field')),
        'Only this service is cancelled.',
      );
      await tester.tap(find.byKey(const Key('decline-booking-confirm')));
      await AppHarness.settle(tester);
      expect(tester.takeException(), isNull);

      // ── The PER-SERVICE endpoint was hit for THIS child, never the
      //    whole-visit decline (which would have cancelled the sibling too). ─
      expect(fakeAppt.declineServiceCalls, 1);
      expect(fakeAppt.lastDeclineServiceAppointmentId, 'appt-1');
      expect(fakeAppt.lastDeclineServiceBookingId, 'booking-1');
      expect(
        fakeAppt.declineCalls,
        0,
        reason:
            'the whole-visit PATCH /appointments/{id}/decline must never be '
            'called — it declined every sibling at once (the CRITICAL bug)',
      );
      expect(fb.declineBookingCalls, 0);

      // ── `booking-1` is now terminal across a real re-fetch. ───────────────
      expect(find.byKey(const Key('booking-detail-decline')), findsNothing);
      expect(find.byKey(const Key('booking-detail-complete')), findsNothing);

      // ── The SIBLING (`booking-2`) is UNTOUCHED: opening its detail re-fetches
      //    a still-CONFIRMED booking through the real HTTP boundary, so its
      //    provider footer still offers decline + reschedule. This is the exact
      //    regression — the old whole-visit decline flipped this child too. ──
      unawaited(router.push(RouteNames.masterBookingDetail('booking-2')));
      await AppHarness.settle(tester);

      expect(fb.getSiblingBookingDetailCalls, greaterThanOrEqualTo(1));
      expect(fb.siblingBookingStatus, 'CONFIRMED');
      expect(
        find.byKey(const Key('booking-detail-decline')),
        findsOneWidget,
        reason:
            'the sibling service stayed CONFIRMED, so its provider footer must '
            'still offer decline — proving the decline of booking-1 did NOT '
            'cascade to booking-2',
      );
      expect(
        find.byKey(const Key('booking-detail-provider-reschedule')),
        findsOneWidget,
      );
    },
  );
}
