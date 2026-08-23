// mobile-qa (Step 2.7 Rule 3b) — E2E coverage for the salon confirm/success
// `AppointmentPager` rework (owner decision, 2026-08-23 — see
// `lib/features/booking/presentation/widgets/appointment_pager.dart`'s file
// header). The pager port turned a flat vertical stack of per-master cards
// into a horizontal, one-master-at-a-time `PageView`; this file proves the
// four behaviours that change touched which the widget tier alone cannot —
// a real app, a real router, a real (fake-backed) HTTP boundary:
//
//   1. Paging by ARROW (and, as a bonus, by a real hand-driven SWIPE via
//      `support/pager_drag.dart`) actually changes the visible master, and
//      the arrows go inert exactly at the two true ends of the visit — never
//      short of them, never past them (3 masters, so the MIDDLE page proves
//      BOTH arrows are simultaneously enabled, not just "not both disabled").
//   2. With exactly ONE master, the pager control is not built at all —
//      `AppointmentPager._paged` is false, so there is nothing to page
//      through and no dead chrome should render.
//   3. Each MASTER (not each booking/service) gets exactly ONE «Додати в
//      календар» button, covering their whole (possibly multi-service)
//      visit — a master with 2 services still gets exactly ONE button, on
//      THAT master's own page only (FIX 3, superseding the earlier "one per
//      booking" decision — see `salon_booking_success_screen.dart`'s file
//      header).
//   4. Per-master comment isolation survives paging AND reaches the wire
//      correctly on submit — the highest-risk regression in this port, since
//      the two controllers now live at the SCREEN level, outside the pager,
//      specifically so an offstage page unbuilding never loses what was
//      typed (see `salon_booking_confirm_screen.dart`'s PER-MASTER COMMENT
//      note). A widget test already pins the on-screen isolation
//      (`test/features/booking/presentation/salon_booking_confirm_screen_test
//      .dart`); this file additionally proves the SUBMITTED
//      `CreateAppointmentRequest.clientComment` for each master carries its
//      OWN text over the real `AppointmentSubmit` write path, never the
//      other master's.
//
// All four tests reach the confirm/success screens via a real `router.push`
// (through the REAL CLIENT route guard) with a directly-built
// `SalonBookingConfirmArgs`/`SalonBookingSuccessArgs`, mirroring
// `salon_booking_flow_test.dart`'s Test 2/3 precedent — the full
// search→salon→services→masters→time chain is already proven by that file's
// first test and is orthogonal to what THIS file targets (the pager
// widget itself, downstream of that chain). `appointmentRepositoryProvider`
// is overridden with a hand-written fake (never a real `POST /appointments`
// route on `FakeBackend`'s `DioAdapter`) for the ONE test that submits
// (Test 4) — mirrors `salon_booking_flow_test.dart`'s own
// `_FakeAppointmentRepository` precedent (kept private to that file, so this
// one is a local twin rather than a cross-file import of a private symbol).
//
// PATROL — REASONED EXEMPTION: no native surface is touched anywhere in this
// file. Test 3 asserts the «Додати в календар» buttons EXIST and are
// correctly COUNTED per master — it never taps one (that would launch a real
// OS calendar intent, already covered by `independent_multi_service_booking_flow
// _test.dart`'s channel interception, which is orthogonal to the per-master
// COUNT this file exists to prove).

import 'dart:async';

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

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';
import 'support/pager_drag.dart';

/// Records every `createAppointment` call — used ONLY by Test 4 (the one
/// test in this file that actually submits). Overridden at
/// `appointmentRepositoryProvider`, matching the REAL write path
/// `AppointmentSubmit.submitVisit` uses (see `salon_booking_flow_test.dart`'s
/// own repair note on why `bookingRepositoryProvider` would be the WRONG
/// provider to override here).
class _FakeAppointmentRepository implements AppointmentRepository {
  final List<CreateAppointmentRequest> requests = <CreateAppointmentRequest>[];

  List<CreateAppointmentRequest> requestsFor(String masterId) => requests
      .where((CreateAppointmentRequest r) => r.masterId == masterId)
      .toList(growable: false);

  @override
  Future<Appointment> createAppointment(CreateAppointmentRequest req) async {
    requests.add(req);
    final DateTime end = req.startAt.add(const Duration(minutes: 60));
    return Appointment(
      id: 'appt-${req.masterId}',
      status: BookingStatus.confirmed,
      masterId: req.masterId,
      masterFirstName: 'Майстер',
      masterLastName: 'Салону',
      masterType: 'SALON_MASTER',
      startAt: req.startAt,
      endAt: end,
      totalDurationMinutes: 60,
      totalPrice: 500,
      items: <AppointmentItem>[
        for (final String id in req.masterServiceIds)
          AppointmentItem(
            bookingId: 'booking-$id',
            masterServiceId: id,
            serviceName: 'Послуга',
            startAt: req.startAt,
            endAt: end,
            durationMinutes: 60,
            price: 500,
          ),
      ],
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
}

/// One 1-service appointment for [masterId]/[firstName] — mirrors
/// `salon_booking_flow_test.dart`'s identical fixture-builder pattern.
SalonBookingAppointment _oneServiceAppt(
  String masterId,
  String firstName,
) => SalonBookingAppointment(
  schedule: SalonMasterSchedule(
    masterId: masterId,
    firstName: firstName,
    lastName: 'Майстер',
    type: MasterType.salonMaster,
    services: <SalonCatalogService>[
      SalonCatalogService(
        id: 'svc-$masterId',
        name: 'Манікюр',
        durationLabel: '1 год',
        priceDisplay: '500 ₴',
        durationMinutes: 60,
        priceType: ServicePriceType.fixed,
        priceMin: 500,
      ),
    ],
    orderedMasterServiceIds: <String>['assign-$masterId'],
  ),
  // instant-ok: arbitrary future filler for a directly-pushed confirm/success fixture, never compared against a calendar day.
  startAt: DateTime.now().add(const Duration(days: 1)),
  idempotencyKey: 'idem-$masterId',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  // ── 1. Paging by arrow (+ swipe) — visible master changes; arrows inert
  // ONLY at the two true ends. ──────────────────────────────────────────────
  testWidgets(
    'CLIENT salon confirm pager: arrow taps AND a real swipe page through '
    'three masters, changing the visible card each time; the arrows are '
    'inert ONLY at the true first/last page, and BOTH are enabled on the '
    'middle page',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()..currentRole = UserRole.client;
        final GoRouter router = await AppHarness.boot(tester, fb);

        await AppHarness.loginAs(tester, fb, UserRole.client);
        await AppHarness.settle(tester);

        unawaited(
          router.push(
            RouteNames.salonBookingConfirm,
            extra: SalonBookingConfirmArgs(
              salonId: 'salon-xyz',
              appointments: <SalonBookingAppointment>[
                _oneServiceAppt('m-a', 'Ганна'),
                _oneServiceAppt('m-b', 'Богдан'),
                _oneServiceAppt('m-c', 'Христина'),
              ],
            ),
          ),
        );
        await AppHarness.settle(tester);
        AppHarness.expectShellLocation(router, RouteNames.salonBookingConfirm);

        final Finder cardA = find.byKey(
          const ValueKey<String>('salon-confirm-appt-m-a'),
        );
        final Finder cardB = find.byKey(
          const ValueKey<String>('salon-confirm-appt-m-b'),
        );
        final Finder cardC = find.byKey(
          const ValueKey<String>('salon-confirm-appt-m-c'),
        );
        final Finder prev = find.byKey(const Key('appointment-pager-prev'));
        final Finder next = find.byKey(const Key('appointment-pager-next'));

        // Page 0 (m-a): only m-a mounted; prev inert, next enabled.
        expect(cardA, findsOneWidget);
        expect(cardB, findsNothing);
        expect(cardC, findsNothing);
        // i18n-finder-ok: numeric pager counter, not translated UI copy.
        expect(find.text('1 / 3'), findsOneWidget);
        expect(tester.widget<GestureDetector>(prev).onTapUp, isNull);
        expect(tester.widget<GestureDetector>(next).onTapUp, isNotNull);

        // Arrow tap → page 1 (m-b): BOTH arrows enabled — the middle page.
        await tester.tap(next);
        await AppHarness.settle(tester);
        expect(cardB, findsOneWidget);
        expect(cardA, findsNothing);
        expect(cardC, findsNothing);
        expect(find.text('2 / 3'), findsOneWidget);
        expect(
          tester.widget<GestureDetector>(prev).onTapUp,
          isNotNull,
          reason: 'the MIDDLE page must have BOTH arrows enabled',
        );
        expect(tester.widget<GestureDetector>(next).onTapUp, isNotNull);

        // Arrow tap → page 2 (m-c): the true last page — next inert.
        await tester.tap(next);
        await AppHarness.settle(tester);
        expect(cardC, findsOneWidget);
        expect(cardA, findsNothing);
        expect(cardB, findsNothing);
        expect(find.text('3 / 3'), findsOneWidget);
        expect(
          tester.widget<GestureDetector>(next).onTapUp,
          isNull,
          reason: 'page 2 is the LAST master — the next arrow must be inert',
        );
        expect(tester.widget<GestureDetector>(prev).onTapUp, isNotNull);

        // Tapping the inert next arrow is a genuine no-op — no crash, no
        // page change, still page 2.
        await tester.tap(next);
        await AppHarness.settle(tester);
        expect(cardC, findsOneWidget);
        expect(find.text('3 / 3'), findsOneWidget);

        // Arrow tap back → page 1 (m-b) again, proving the round trip.
        await tester.tap(prev);
        await AppHarness.settle(tester);
        expect(cardB, findsOneWidget);
        expect(find.text('2 / 3'), findsOneWidget);

        // ── Bonus: a REAL hand-driven swipe (never `tester.fling` — see
        // `pager_drag.dart`'s own doc for why) turns the page too, not just
        // the arrow controls. Forward from m-b → m-c. ─────────────────────
        await dragPagerByOnePage(
          tester,
          const Key('appointment-pager'),
          forward: true,
        );
        expect(cardC, findsOneWidget);
        expect(cardB, findsNothing);
        expect(find.text('3 / 3'), findsOneWidget);

        // Swipe backward from m-c → m-b.
        await dragPagerByOnePage(
          tester,
          const Key('appointment-pager'),
          forward: false,
        );
        expect(cardB, findsOneWidget);
        expect(cardC, findsNothing);
        expect(find.text('2 / 3'), findsOneWidget);

        expect(tester.takeException(), isNull);
      });
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  // ── 2. Exactly one master — the pager control is not rendered at all. ────
  testWidgets(
    'CLIENT salon confirm/success pager: with exactly ONE master, the '
    '‹ N / M › control and its arrows are not built at all on either screen',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()..currentRole = UserRole.client;
        final GoRouter router = await AppHarness.boot(tester, fb);

        await AppHarness.loginAs(tester, fb, UserRole.client);
        await AppHarness.settle(tester);

        final SalonBookingAppointment solo = _oneServiceAppt('m-solo', 'Ірина');

        unawaited(
          router.push(
            RouteNames.salonBookingConfirm,
            extra: SalonBookingConfirmArgs(
              salonId: 'salon-xyz',
              appointments: <SalonBookingAppointment>[solo],
            ),
          ),
        );
        await AppHarness.settle(tester);
        AppHarness.expectShellLocation(router, RouteNames.salonBookingConfirm);
        expect(find.byType(SalonBookingConfirmScreen), findsOneWidget);

        // The single master's card is directly visible — no paging needed.
        expect(
          find.byKey(const ValueKey<String>('salon-confirm-appt-m-solo')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('appointment-pager-prev')), findsNothing);
        expect(find.byKey(const Key('appointment-pager-next')), findsNothing);
        // i18n-finder-ok: numeric pager counter, not translated UI copy —
        // with one master there is no "1 / 1" control at all, not merely a
        // hidden one.
        expect(find.text('1 / 1'), findsNothing);

        // Same contract on the success screen, reached directly (this file
        // targets the pager, not the submit write path — see Test 4 for
        // that).
        unawaited(
          router.push(
            RouteNames.salonBookingSuccess,
            extra: SalonBookingSuccessArgs(
              salonId: 'salon-xyz',
              appointments: <SalonBookingAppointment>[solo],
            ),
          ),
        );
        await AppHarness.settle(tester);
        expect(find.byType(SalonBookingSuccessScreen), findsOneWidget);
        expect(
          find.byKey(const ValueKey<String>('salon-success-appt-m-solo')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('appointment-pager-prev')), findsNothing);
        expect(find.byKey(const Key('appointment-pager-next')), findsNothing);
        expect(find.text('1 / 1'), findsNothing);

        expect(tester.takeException(), isNull);
      });
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  // ── 3. One «Додати в календар» button per MASTER, covering their whole
  // visit, on the right master's page (FIX 3). ─────────────────────────────
  testWidgets(
    'CLIENT salon success pager: every master gets exactly ONE calendar '
    'button covering their whole visit — a 2-service master and a '
    '1-service master both get exactly one, on their OWN page — never '
    'bleeding onto each other',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()..currentRole = UserRole.client;
        final GoRouter router = await AppHarness.boot(tester, fb);

        await AppHarness.loginAs(tester, fb, UserRole.client);
        await AppHarness.settle(tester);

        // m-multi: TWO services, back-to-back in ONE appointment → still ONE
        // calendar button (FIX 3 — one button per master, covering the whole
        // visit, never one per service).
        final SalonBookingAppointment multi = SalonBookingAppointment(
          schedule: const SalonMasterSchedule(
            masterId: 'm-multi',
            firstName: 'Дарина',
            lastName: 'Майстер',
            type: MasterType.salonMaster,
            services: <SalonCatalogService>[
              SalonCatalogService(
                id: 'svc-multi-1',
                name: 'Манікюр',
                durationLabel: '1 год',
                priceDisplay: '500 ₴',
                durationMinutes: 60,
                priceType: ServicePriceType.fixed,
                priceMin: 500,
              ),
              SalonCatalogService(
                id: 'svc-multi-2',
                name: 'Педикюр',
                durationLabel: '45 хв',
                priceDisplay: '400 ₴',
                durationMinutes: 45,
                priceType: ServicePriceType.fixed,
                priceMin: 400,
              ),
            ],
            orderedMasterServiceIds: <String>[
              'assign-m-multi-1',
              'assign-m-multi-2',
            ],
          ),
          // instant-ok: arbitrary future filler, never compared against a calendar day.
          startAt: DateTime.now().add(const Duration(days: 1)),
          idempotencyKey: 'idem-m-multi',
        );
        // m-single: ONE service → still exactly one calendar button (the
        // per-master rule doesn't special-case a single-service master).
        final SalonBookingAppointment single = _oneServiceAppt(
          'm-single',
          'Євген',
        );

        unawaited(
          router.push(
            RouteNames.salonBookingSuccess,
            extra: SalonBookingSuccessArgs(
              salonId: 'salon-xyz',
              appointments: <SalonBookingAppointment>[multi, single],
            ),
          ),
        );
        await AppHarness.settle(tester);
        expect(find.byType(SalonBookingSuccessScreen), findsOneWidget);

        // Page 0 (m-multi): exactly ONE calendar button, despite 2 services.
        expect(
          find.byKey(const ValueKey<String>('salon-success-add-calendar-0')),
          findsOneWidget,
        );
        // m-single's button is not built yet — offstage page.
        expect(
          find.byKey(const ValueKey<String>('salon-success-add-calendar-1')),
          findsNothing,
        );

        // Page to m-single — its ONE button, m-multi's gone.
        await tester.tap(find.byKey(const Key('appointment-pager-next')));
        await AppHarness.settle(tester);

        expect(
          find.byKey(const ValueKey<String>('salon-success-add-calendar-0')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey<String>('salon-success-add-calendar-1')),
          findsOneWidget,
        );

        expect(tester.takeException(), isNull);
      });
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  // ── 4. Per-master comment isolation survives paging AND reaches the wire
  // correctly — the highest-risk regression in this port. ──────────────────
  testWidgets(
    'CLIENT salon confirm pager: typing distinct comments for two masters, '
    'paging back and forth between them repeatedly, survives with neither '
    'bleeding into the other — and the SUBMITTED request carries each '
    "master's OWN text",
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
          router.push(
            RouteNames.salonBookingConfirm,
            extra: SalonBookingConfirmArgs(
              salonId: 'salon-xyz',
              appointments: <SalonBookingAppointment>[
                _oneServiceAppt('m-one', 'Олена'),
                _oneServiceAppt('m-two', 'Софія'),
              ],
            ),
          ),
        );
        await AppHarness.settle(tester);
        AppHarness.expectShellLocation(router, RouteNames.salonBookingConfirm);

        final Finder commentOne = find.byKey(
          const Key('salon-confirm-comment-field-m-one'),
        );
        final Finder commentTwo = find.byKey(
          const Key('salon-confirm-comment-field-m-two'),
        );
        final Finder next = find.byKey(const Key('appointment-pager-next'));
        final Finder prev = find.byKey(const Key('appointment-pager-prev'));

        // Page 0 (m-one): type its comment.
        await tester.enterText(commentOne, 'Коментар для Олени');
        await tester.pump();
        // i18n-finder-ok: the test's OWN typed input, not app-rendered copy.
        expect(find.text('Коментар для Олени'), findsOneWidget);

        // Page to m-two — its field starts EMPTY, never inheriting m-one's
        // text.
        await tester.tap(next);
        await AppHarness.settle(tester);
        expect(commentTwo, findsOneWidget);
        // i18n-finder-ok: the test's OWN typed input, not app-rendered copy.
        expect(find.text('Коментар для Олени'), findsNothing);

        await tester.enterText(commentTwo, 'Коментар для Софії');
        await tester.pump();
        // i18n-finder-ok: the test's OWN typed input, not app-rendered copy.
        expect(find.text('Коментар для Софії'), findsOneWidget);

        // Page back to m-one — ITS text survived paging away and back.
        await tester.tap(prev);
        await AppHarness.settle(tester);
        expect(
          // i18n-finder-ok: the test's OWN typed input, not app-rendered copy.
          find.text('Коментар для Олени'),
          findsOneWidget,
          reason:
              "m-one's text must survive an offstage page unbuild — the "
              'controller lives at the SCREEN level, outside the pager',
        );
        expect(
          // i18n-finder-ok: the test's OWN typed input, not app-rendered copy.
          find.text('Коментар для Софії'),
          findsNothing,
          reason: "m-two's text must never bleed onto m-one's page",
        );

        // Page forward again — m-two's text ALSO survived.
        await tester.tap(next);
        await AppHarness.settle(tester);
        // i18n-finder-ok: the test's OWN typed input, not app-rendered copy.
        expect(find.text('Коментар для Софії'), findsOneWidget);
        // i18n-finder-ok: the test's OWN typed input, not app-rendered copy.
        expect(find.text('Коментар для Олени'), findsNothing);

        // One more full round trip for good measure — repeated paging, not
        // just a single there-and-back.
        await tester.tap(prev);
        await AppHarness.settle(tester);
        // i18n-finder-ok: the test's OWN typed input, not app-rendered copy.
        expect(find.text('Коментар для Олени'), findsOneWidget);
        await tester.tap(next);
        await AppHarness.settle(tester);
        // i18n-finder-ok: the test's OWN typed input, not app-rendered copy.
        expect(find.text('Коментар для Софії'), findsOneWidget);

        // ── Submit: the WRITE path must carry each master's OWN comment —
        // proves isolation beyond the UI layer, over the real
        // `AppointmentSubmit.submitVisit` call. ───────────────────────────
        await tester.tap(find.byKey(const Key('salon-confirm-submit-cta')));
        await AppHarness.settle(tester);

        AppHarness.expectShellLocation(router, RouteNames.salonBookingSuccess);
        expect(
          repo.requestsFor('m-one').single.clientComment,
          'Коментар для Олени',
        );
        expect(
          repo.requestsFor('m-two').single.clientComment,
          'Коментар для Софії',
        );
        expect(tester.takeException(), isNull);
      });
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );
}
