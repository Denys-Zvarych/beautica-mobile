// MO-5 — E2E: the CLIENT «МОЇ ЗАПИСИ» multi-service VISIT journey.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b — integration-test gate)
// --------------------------------------------------------------
// The widget/unit tier proves the pieces in isolation: my_bookings_entry_test
// (grouping + summary derivations), my_bookings_visit_grouping_test (one grouped
// card + routing), visit_detail_screen_test (recap + cancel/review routing).
// NONE proves the REAL journey wired together against the fake backend:
//
//   1. CLIENT logs in and opens the Записи branch.
//   2. `GET /bookings/me` returns TWO per-service rows sharing an appointmentId
//      + one legacy standalone row → the list collapses the visit into ONE
//      `VisitCard` while the legacy row keeps its own `BookingCard`.
//   3. Tapping the visit card opens the VISIT detail (`getAppointment`), which
//      renders the multi-service recap (both ordered services, one window, one
//      total).
//   4. Cancelling the visit calls `AppointmentRepository.cancelAppointment`
//      (the visit path) and NEVER the per-booking `cancelBooking` — the backend
//      409s a single-booking cancel on an appointment child, so the client must
//      route a visit to the appointment endpoint.
//
// `/bookings/me` is served by `FakeBackend` (real Dio adapter, so the grouping
// runs over genuinely-fetched rows). The visit DETAIL's `getAppointment` /
// `cancelAppointment` go through a hand-written [_FakeAppointmentRepository]
// override — mirroring `independent_multi_service_booking_flow_test.dart`, which
// likewise overrides `appointmentRepositoryProvider` rather than adding a real
// `/appointments` route to the fake adapter.
//
// KEY POLICY (AppHarness): all TAPS are key-/type-based; Ukrainian text appears
// in CONTENT ASSERTIONS only.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/data/appointment_repository.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/domain/appointment.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/booking_tab.dart';
import 'package:beautica_mobile/features/booking/domain/create_appointment_request.dart';
import 'package:beautica_mobile/features/booking/presentation/appointment_review_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/my_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/visit_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_card.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

/// The visit read/cancel path, hand-faked (no real `/appointments` adapter route
/// — see the file header). [getAppointment] serves a 2-item visit; the status
/// flips to CANCELLED once [cancelAppointment] runs so a re-fetch reflects it.
class _FakeAppointmentRepository implements AppointmentRepository {
  _FakeAppointmentRepository({
    BookingStatus status = BookingStatus.confirmed,
    bool canReview = false,
    this.completed = false,
  }) : _status = status,
       _canReview = canReview;

  /// When true, the visit's window is in the PAST (a COMPLETED visit) rather
  /// than one day out — so `getAppointment` yields a review-eligible detail.
  final bool completed;

  int getCalls = 0;
  int cancelCalls = 0;
  int reviewCalls = 0;
  String? lastCancelNote;
  int? lastReviewRating;
  String? lastReviewComment;
  BookingStatus _status;
  bool _canReview;

  @override
  Future<Appointment> getAppointment(String id) async {
    getCalls++;
    final DateTime start = completed
        ? DateTime.now().subtract(const Duration(days: 1, hours: 10))
        : DateTime.now().add(const Duration(days: 1, hours: 10));
    return Appointment(
      id: id,
      status: _status,
      masterId: 'master-aaa',
      masterFirstName: 'Софія',
      masterLastName: 'Бондар',
      masterProfessionalTitle: 'Майстриня манікюру',
      masterType: 'INDEPENDENT_MASTER',
      startAt: start,
      endAt: start.add(const Duration(minutes: 150)),
      totalDurationMinutes: 150,
      totalPrice: 900,
      items: <AppointmentItem>[
        AppointmentItem(
          bookingId: 'v-1',
          masterServiceId: 'ms-1',
          serviceName: 'Манікюр з покриттям',
          startAt: start,
          endAt: start.add(const Duration(minutes: 90)),
          durationMinutes: 90,
          price: 500,
        ),
        AppointmentItem(
          bookingId: 'v-2',
          masterServiceId: 'ms-2',
          serviceName: 'Педикюр апаратний',
          startAt: start.add(const Duration(minutes: 90)),
          endAt: start.add(const Duration(minutes: 150)),
          durationMinutes: 60,
          price: 400,
        ),
      ],
      canReview: _canReview,
      cityLabel: 'Київ',
      districtLabel: 'Печерський',
      street: 'вул. Хрещатик',
      buildingNo: '12',
    );
  }

  @override
  Future<void> cancelAppointment(String id, {String? note}) async {
    cancelCalls++;
    lastCancelNote = note;
    _status = BookingStatus.cancelled;
  }

  @override
  Future<void> createAppointmentReview(
    String id, {
    required int rating,
    String? comment,
  }) async {
    reviewCalls++;
    lastReviewRating = rating;
    lastReviewComment = comment;
    // The visit is now reviewed — a re-fetch reflects it (canReview flips false).
    _canReview = false;
  }

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

  testWidgets(
    'CLIENT sees a multi-service visit as ONE grouped card, opens its detail, '
    'and cancels via cancelAppointment (never cancelBooking)',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      final fakeAppt = _FakeAppointmentRepository();

      final DateTime visitStart = DateTime.now().add(
        const Duration(days: 1, hours: 10),
      );
      final DateTime legacyStart = DateTime.now().add(
        const Duration(days: 2, hours: 10),
      );

      // Two rows sharing appt-1 (the visit) + one legacy standalone row.
      fb.seedManyBookingsDataset(<Map<String, dynamic>>[
        _row(
          id: 'v-1',
          appointmentId: 'appt-1',
          serviceName: 'Манікюр з покриттям',
          startsAt: visitStart,
          minutes: 90,
        ),
        _row(
          id: 'v-2',
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
          appointmentRepositoryProvider.overrideWithValue(fakeAppt),
        ],
      );

      await AppHarness.loginAs(tester, fb, UserRole.client);

      // ── Open the Записи branch (bottom-nav tile 3). ───────────────────────
      await tester.tap(find.byKey(const Key('client-nav-tile-3')));
      await AppHarness.settle(tester);
      expect(find.byType(MyBookingsScreen), findsOneWidget);

      // ── The visit collapses into ONE VisitCard; the legacy row keeps its
      //    own BookingCard. ──────────────────────────────────────────────────
      expect(find.byType(VisitCard), findsOneWidget);
      expect(find.byType(BookingCard), findsOneWidget);
      // The grouped card lists both of the visit's ordered services.
      expect(
        find.byKey(const ValueKey<String>('visit-service-appt-1-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('visit-service-appt-1-1')),
        findsOneWidget,
      );

      // ── Open the VISIT detail (getAppointment) — the multi-service recap. ──
      await tester.tap(find.byType(VisitCard));
      await AppHarness.settle(tester);
      expect(find.byType(VisitDetailScreen), findsOneWidget);
      expect(fakeAppt.getCalls, greaterThanOrEqualTo(1));
      // i18n-finder-ok: service name is injected fixture data, locale-invariant
      expect(find.text('Манікюр з покриттям'), findsWidgets);
      // i18n-finder-ok: service name is injected fixture data, locale-invariant
      expect(find.text('Педикюр апаратний'), findsWidgets);

      // ── Cancel the visit — routes to cancelAppointment, never cancelBooking.
      await tester.tap(find.byKey(const Key('visit-detail-cancel')));
      await AppHarness.settle(tester);
      expect(find.byKey(const Key('cancel-visit-dialog')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('cancel-booking-note-field')),
        'Захворіла, вибачте.',
      );
      await AppHarness.settle(tester);
      await tester.tap(find.byKey(const Key('cancel-booking-confirm')));
      await AppHarness.settle(tester);

      expect(fakeAppt.cancelCalls, 1);
      expect(fakeAppt.lastCancelNote, 'Захворіла, вибачте.');
      // The per-booking cancel path must NOT have been touched for a visit.
      expect(
        fb.cancelBookingCalls,
        0,
        reason:
            'a visit cancel must route to cancelAppointment, never the '
            'per-booking cancelBooking (the backend 409s that on a child)',
      );
    },
  );

  // MO-6 — the review leg: a COMPLETED, review-eligible visit reviewed ONCE via
  // `createAppointmentReview`, never the per-booking review of a child.
  testWidgets('CLIENT opens a COMPLETED visit, leaves ONE review via '
      'createAppointmentReview, and the CTA disappears once canReview flips', (
    tester,
  ) async {
    final fb = FakeBackend()..currentRole = UserRole.client;
    final fakeAppt = _FakeAppointmentRepository(
      status: BookingStatus.completed,
      canReview: true,
      completed: true,
    );

    // A past, COMPLETED two-service visit → lands in the Минулі tab.
    final DateTime visitStart = DateTime.now().subtract(
      const Duration(days: 1, hours: 10),
    );
    fb.seedManyBookingsDataset(<Map<String, dynamic>>[
      _row(
        id: 'v-1',
        appointmentId: 'appt-1',
        serviceName: 'Манікюр з покриттям',
        startsAt: visitStart,
        minutes: 90,
        status: 'COMPLETED',
      ),
      _row(
        id: 'v-2',
        appointmentId: 'appt-1',
        serviceName: 'Педикюр апаратний',
        startsAt: visitStart.add(const Duration(minutes: 90)),
        minutes: 60,
        status: 'COMPLETED',
      ),
    ]);

    await AppHarness.boot(
      tester,
      fb,
      extraOverrides: <Object>[
        appointmentRepositoryProvider.overrideWithValue(fakeAppt),
      ],
    );

    await AppHarness.loginAs(tester, fb, UserRole.client);

    // ── Open the Записи branch and switch to the Минулі tab. ────────────────
    await tester.tap(find.byKey(const Key('client-nav-tile-3')));
    await AppHarness.settle(tester);
    expect(find.byType(MyBookingsScreen), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<BookingTab>(BookingTab.past)));
    await AppHarness.settle(tester);

    // ── The completed visit collapses into ONE grouped VisitCard. ───────────
    expect(find.byType(VisitCard), findsOneWidget);

    // ── Open the VISIT detail — COMPLETED + canReview → the review CTA. ──────
    await tester.tap(find.byType(VisitCard));
    await AppHarness.settle(tester);
    expect(find.byType(VisitDetailScreen), findsOneWidget);
    final Finder reviewCta = find.byKey(const Key('visit-detail-leave-review'));
    expect(reviewCta, findsOneWidget);

    // ── Route to the VISIT review form (never a per-booking review). ────────
    await tester.tap(reviewCta);
    await AppHarness.settle(tester);
    expect(find.byType(AppointmentReviewScreen), findsOneWidget);

    // ── Rate + submit → createAppointmentReview (the visit path). ───────────
    await tester.tap(find.byKey(const ValueKey<String>('review-star-5')));
    await AppHarness.settle(tester);
    await tester.enterText(
      find.byKey(const Key('visit-review-comment')),
      'Дуже задоволена візитом!',
    );
    await AppHarness.settle(tester);
    await tester.tap(find.byKey(const Key('visit-review-submit')));
    await AppHarness.settle(tester);

    expect(fakeAppt.reviewCalls, 1);
    expect(fakeAppt.lastReviewRating, 5);
    expect(fakeAppt.lastReviewComment, 'Дуже задоволена візитом!');

    // ── Popped back to the visit detail; canReview flipped → the CTA is gone,
    //    replaced by the rebook-only action set. ─────────────────────────────
    expect(find.byType(AppointmentReviewScreen), findsNothing);
    expect(find.byType(VisitDetailScreen), findsOneWidget);
    final AppLocalizations l10n = AppLocalizations.of(
      tester.element(find.byType(VisitDetailScreen)),
    );
    expect(find.text(l10n.reviewSubmitSuccess), findsOneWidget);
    expect(
      find.byKey(const Key('visit-detail-leave-review')),
      findsNothing,
      reason: 'canReview flipped false after the review — CTA must vanish',
    );
    expect(find.byKey(const Key('visit-detail-rebook')), findsOneWidget);
  });
}
