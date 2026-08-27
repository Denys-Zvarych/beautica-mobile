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
//   2.5. Each card's category icon resolves from the REAL `categoryKey`
//      that traveled over that same round trip — the shared
//      `categoryIconOrNullFor` resolver (`core/icons/category_icons.dart`),
//      never the deleted private Ukrainian-literal switch. Also proves the
//      genuinely-uncategorised row renders NO icon (mobile-qa gap-closure,
//      2026-08-27 — Step 2.7 Rule 3b: this real-user-flow surface needed
//      its own extended coverage, not only the widget-tier fixture in
//      `booking_card_svg_icon_test.dart`).
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
// `createAppointmentReview`) is GONE, not merely unreachable: the backend
// deleted `POST /appointments/{id}/review` and `Appointment.canReview` under
// the locked "1 booking = 1 feedback" decision, so `VisitDetailScreen` /
// `AppointmentReviewScreen` / `appointment_leave_review_notifier.dart` /
// `appointment_detail_notifier.dart` were deleted outright along with their
// own widget-tier tests. Every review now flows through the per-booking
// `LeaveReviewScreen` (`POST /reviews` with a `bookingId`) instead.
//
// KEY POLICY (AppHarness): all TAPS are key-/type-based; Ukrainian text appears
// in CONTENT ASSERTIONS only.

import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
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
  Future<Appointment> rescheduleAppointmentItem(
    String appointmentId,
    String bookingId,
    DateTime newStartAt, {
    bool allowClientOverlap = false,
  }) => throw UnimplementedError();

  @override
  Future<void> completeAppointment(String id) => throw UnimplementedError();
  @override
  Future<void> completeAppointmentService(
    String appointmentId,
    String bookingId,
  ) => throw UnimplementedError();

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
  // Real wire shape (mobile-qa gap-closure, 2026-08-27): `categoryKey` is
  // the backend's stable UPPER_SNAKE slug (`BookingDetailResponse.
  // categoryKey`, threaded via `booking_mapper.dart:150`), `categoryName`
  // is its documented Ukrainian-keyword fallback — see
  // `core/icons/category_icons.dart`'s file header. Both default to null
  // (the genuinely-uncategorised row `legacy-1` below exercises that).
  String? categoryKey,
  String? categoryName,
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
  'categoryKey': categoryKey,
  'categoryName': categoryName,
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

    // These rows must read as UPCOMING, and `BookingDisplayX.isPast`
    // compares `endAt` against the DEVICE clock on purpose (`instant-ok`
    // annotated in `lib/features/booking/domain/booking_display_x.dart`),
    // never the injected one — the same rationale documented on
    // `FakeBackend._kFixtureDay`. Anchoring these to `kFixedNow` would make
    // them render as PAST once the real wall clock passes 2026-06-14.
    // instant-ok: fixture must track the same DEVICE clock BookingDisplayX reads
    final DateTime visitStart = DateTime.now().add(
      const Duration(days: 1, hours: 10),
    );
    // instant-ok: same DEVICE-clock rationale as `visitStart` directly above
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
        categoryKey: 'NAIL_SERVICE',
      ),
      _row(
        id: 'booking-2',
        appointmentId: 'appt-1',
        serviceName: 'Педикюр апаратний',
        startsAt: visitStart.add(const Duration(minutes: 90)),
        minutes: 60,
        categoryKey: 'PODOLOGY',
      ),
      // Genuinely uncategorised — neither field on the wire. Proves the
      // real Dio round trip renders NO icon rather than the cosmetology
      // fallback (`categoryIconOrNullFor`'s null-gate), not just the
      // widget-tier fixture in `booking_card_svg_icon_test.dart`.
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

    // ── Each card's category icon resolves from the REAL fetched
    //    `categoryKey`, over the genuine `GET /bookings/me` round trip —
    //    not a widget-tier fixture (mobile-qa gap-closure, 2026-08-27; the
    //    bug this whole rollout fixed was silently invisible at exactly
    //    this boundary: the wire carries a slug, the card's OLD private
    //    mapper matched Ukrainian text, and every card fell through to one
    //    default glyph). Scoped to each card's own key — `find.byType`
    //    alone also catches the home-hub bell/nav `AppIcon`s still mounted
    //    offstage in the shell.
    final AppIcon nailIcon = tester.widget<AppIcon>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('booking-1')),
        matching: find.byType(AppIcon),
      ),
    );
    expect(nailIcon.asset, BeauticaAssetIcons.categoryNailService);
    final AppIcon podologyIcon = tester.widget<AppIcon>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('booking-2')),
        matching: find.byType(AppIcon),
      ),
    );
    expect(podologyIcon.asset, BeauticaAssetIcons.categoryPodology);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('legacy-1')),
        matching: find.byType(AppIcon),
      ),
      findsNothing,
      reason:
          'the uncategorised legacy row must render NO icon, never the '
          'cosmetology fallback a regression to the never-null '
          'categoryIconFor at this call site would produce',
    );

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
