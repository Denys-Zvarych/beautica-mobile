// MO-7 — E2E: the CLIENT «МОЇ ЗАПИСИ» multi-service VISIT journey, PER SERVICE.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b — integration-test gate)
// --------------------------------------------------------------
// Product decision (locked 2026-07-26): «Мої записи» no longer collapses a
// multi-service visit's rows into one grouped card. This file used to prove
// the OPPOSITE — that a visit's rows collapsed into one `VisitCard` and
// cancelled as a whole via `AppointmentRepository.cancelAppointment` (the
// backend 409'd a per-booking cancel on a visit child at the time). Both of
// those are now false: `VisitCard`/`groupBookingsByAppointment` are DELETED
// (see `my_bookings_screen.dart`'s file header), and the backend's
// `assertNotAppointmentChild` guard on `PATCH /bookings/{id}/cancel` is gone
// (backend `1d1d524`) — the endpoint now cancels ONLY the targeted leg and
// recomputes the appointment header server-side.
//
// The widget/unit tier proves the pieces in isolation:
// `my_bookings_visit_grouping_test.dart` (per-service rendering + routing +
// the cancel-routes-to-cancelBooking regression). This file proves the REAL
// journey wired together against the fake backend:
//
//   1. CLIENT logs in and opens the Записи branch.
//   2. `GET /bookings/me` returns TWO per-service rows sharing an
//      appointmentId + one legacy standalone row → the list renders THREE
//      ordinary `BookingCard`s — no grouping, no visit chrome.
//   3. Tapping ONE visit leg opens ITS OWN single-booking detail
//      (`GET /bookings/{id}`), never `VisitDetailScreen`.
//   4. Cancelling that leg calls the PER-BOOKING
//      `PATCH /bookings/{id}/cancel` — never any appointment-level
//      endpoint — proving the write acts on that ONE service only.
//
// `/bookings/me` is served by `FakeBackend` (real Dio adapter, so the render
// runs over genuinely-fetched rows). The tapped leg reuses the FIXED
// `booking-1` single-seeded fixture (`fb.bookingAppointmentId` marks it as a
// visit child) so the cancel goes through the REAL wired
// `PATCH /bookings/booking-1/cancel` route — the same "seed the concrete
// fixture id" pattern `booking_detail_appointment_child_footer_test.dart`
// established for the provider-side per-service decline regression.
// `AppointmentRepository` is overridden with a call-counting fake (no real
// `/appointments` route exists on the fake adapter — mirrors every other
// appointment-vs-booking flow in this suite) purely to prove it is NEVER
// touched by this journey.
//
// The whole-visit REVIEW journey this file used to also cover (tap a
// `VisitCard` → `VisitDetailScreen` → `AppointmentReviewScreen` →
// `createAppointmentReview`) has no UI entry point left after this change —
// `VisitCard` was its only tap target in the list. That journey is NOT
// deleted: `VisitDetailScreen`/`AppointmentReviewScreen` and their own
// widget-tier tests (`visit_detail_screen_test.dart`,
// `appointment_review_screen_test.dart`, both pump the screens directly, no
// dependency on the list) still cover it in isolation. Whether that journey
// needs a new entry point is a product decision outside this ticket's scope.
//
// KEY POLICY (AppHarness): all TAPS are key-/type-based; Ukrainian text appears
// in CONTENT ASSERTIONS only.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/data/appointment_repository.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/domain/appointment.dart';
import 'package:beautica_mobile/features/booking/domain/create_appointment_request.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/my_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

/// A call-counting stand-in for [AppointmentRepository] — every method throws
/// except [cancelAppointment], which merely counts calls. This journey must
/// NEVER reach ANY appointment-level endpoint (no real `/appointments` route
/// exists on the fake Dio adapter — see the file header), so any accidental
/// call surfaces loudly rather than silently 404ing.
class _SpyAppointmentRepository implements AppointmentRepository {
  int cancelCalls = 0;
  String? lastCancelNote;

  @override
  Future<void> cancelAppointment(String id, {String? note}) async {
    cancelCalls++;
    lastCancelNote = note;
  }

  @override
  Future<Appointment> getAppointment(String id) => throw UnimplementedError();

  @override
  Future<Appointment> rescheduleAppointment(String id, DateTime newStartAt) =>
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

  @override
  Future<Appointment> createAppointment(CreateAppointmentRequest req) =>
      throw UnimplementedError();
}

Map<String, dynamic> _row({
  required String id,
  String? appointmentId,
  required String serviceName,
  required DateTime startsAt,
  int minutes = 60,
  String status = 'CONFIRMED',
}) => <String, dynamic>{
  'id': id,
  'masterId': 'master-aaa',
  'masterFirstName': 'Софія',
  'masterLastName': 'Бондар',
  'masterAvatarUrl': null,
  'masterType': 'INDEPENDENT_MASTER',
  'salonName': null,
  'masterServiceId': 'ms-$id',
  'serviceName': serviceName,
  'categoryName': 'Манікюр',
  'cityLabel': 'Київ',
  'districtLabel': 'Печерський',
  'street': 'вул. Хрещатик',
  'buildingNo': '12',
  'durationMinutesAtBooking': minutes,
  'priceAtBooking': 450,
  'priceMaxAtBooking': null,
  'startsAt': startsAt.toIso8601String(),
  'endsAt': startsAt.add(Duration(minutes: minutes)).toIso8601String(),
  'status': status,
  'canReview': false,
  'clientComment': null,
  'providerComment': null,
  'clientCancellationNote': null,
  'masterProfessionalTitle': 'Майстриня манікюру',
  'locationNote': null,
  'appointmentId': appointmentId,
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets('CLIENT sees a multi-service visit as TWO plain BookingCards (no '
      'grouping), opens ONE leg, and cancels it via the per-booking '
      'cancelBooking — never any appointment-level endpoint', (tester) async {
    final fb = FakeBackend()..currentRole = UserRole.client;
    final spyAppt = _SpyAppointmentRepository();

    final DateTime visitStart = DateTime.now().add(
      const Duration(days: 1, hours: 10),
    );
    final DateTime legacyStart = DateTime.now().add(
      const Duration(days: 2, hours: 10),
    );

    // `booking-1` is the tapped/cancelled leg — reuses the FIXED
    // single-seeded fixture (`fb.bookingAppointmentId`) so its
    // `GET`/`PATCH …/cancel` go through the REAL wired routes (see the
    // file header). `booking-2` is its sibling in the list only (its own
    // GET/cancel routes are not exercised by this flow) + one legacy
    // standalone row.
    fb.bookingAppointmentId = 'appt-1';
    fb.seedManyBookingsDataset(<Map<String, dynamic>>[
      _row(
        id: 'booking-1',
        appointmentId: 'appt-1',
        serviceName: 'Манікюр з покриттям',
        startsAt: visitStart,
        minutes: 90,
      ),
      _row(
        id: 'booking-2',
        appointmentId: 'appt-1',
        serviceName: 'Педикюр апаратний',
        startsAt: visitStart.add(const Duration(minutes: 90)),
        minutes: 60,
      ),
      _row(id: 'legacy-1', serviceName: 'Стрижка', startsAt: legacyStart),
    ]);

    await AppHarness.boot(
      tester,
      fb,
      extraOverrides: <Object>[
        appointmentRepositoryProvider.overrideWithValue(spyAppt),
      ],
    );

    await AppHarness.loginAs(tester, fb, UserRole.client);

    // ── Open the Записи branch (bottom-nav tile 3). ───────────────────────
    await tester.tap(find.byKey(const Key('client-nav-tile-3')));
    await AppHarness.settle(tester);
    expect(find.byType(MyBookingsScreen), findsOneWidget);

    // ── The visit's two legs render as ORDINARY, SEPARATE BookingCards —
    //    no grouping, no visit chrome — alongside the legacy row. ─────────
    expect(find.byType(BookingCard), findsNWidgets(3));
    expect(find.byKey(const ValueKey<String>('booking-1')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('booking-2')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('legacy-1')), findsOneWidget);

    // ── Open ONE leg's OWN detail (GET /bookings/booking-1). ───────────────
    await tester.tap(find.byKey(const ValueKey<String>('booking-1')));
    await AppHarness.settle(tester);
    expect(find.byType(BookingDetailScreen), findsOneWidget);

    // ── Cancel THIS leg — routes to the per-booking cancelBooking, never
    //    an appointment-level endpoint. ─────────────────────────────────────
    await tester.tap(find.byKey(const Key('booking-detail-cancel')));
    await AppHarness.settle(tester);
    expect(find.byKey(const Key('cancel-booking-dialog')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('cancel-booking-note-field')),
      'Захворіла, вибачте.',
    );
    await AppHarness.settle(tester);
    await tester.tap(find.byKey(const Key('cancel-booking-confirm')));
    await AppHarness.settle(tester);

    expect(fb.cancelBookingCalls, 1);
    expect(fb.lastCancelComment, 'Захворіла, вибачте.');
    // Never touched ANY appointment-level endpoint — the write acted on
    // this ONE service only.
    expect(
      spyAppt.cancelCalls,
      0,
      reason:
          'a per-card cancel must route to the per-booking cancelBooking, '
          'never AppointmentRepository.cancelAppointment',
    );
  });
}
