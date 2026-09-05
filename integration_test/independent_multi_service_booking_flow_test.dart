// mobile-qa — MO-3 E2E coverage for the INDEPENDENT-master MULTI-SERVICE
// SINGLE-VISIT booking flow.
//
// WHY THIS FILE EXISTS
// --------------------
// MO-3 reworked the independent-master flow: the client multi-selects services,
// picks ONE date + ONE start time for the whole visit, and the visit is
// submitted as ONE `POST /appointments` (ordered `masterServiceIds` + one
// `startsAt` + one idempotency key) — replacing the pre-MO-3 "N `POST /bookings`,
// one per service" fan-out. The widget tier proves the pieces in isolation
// (`booking_confirm_test.dart`); this file proves the REAL journey end to end:
//   • Test 1 — a logged-in CLIENT lands on the REAL `BookingConfirmScreen` (its
//     `publicMasterProfileProvider(master-aaa)` resolved through the REAL
//     fake-backed public master repository), submits the visit, and reaches the
//     success screen — with ONE `createAppointment` carrying BOTH ordered
//     service ids + ONE calendar export spanning the whole visit.
//   • Test 2 — the single submit 409s with CLIENT_BOOKING_CONFLICT → the confirm
//     screen STAYS and the conflict surfaces EXACTLY ONCE, as the shared POPUP
//     (`showClientBookingConflictDialog`, never the bottom banner — commit
//     `4d49d1c3`), and confirming it resubmits the SAME idempotency key with
//     `allowClientOverlap: true` and reaches success.
//   • Test 3 — enters the real date→time picker (`SlotDateScreen` →
//     `SlotTimeScreen`) with a two-service selection and proves the pinned
//     "Послуги та ціни" shelf lists both services and the single chosen-window
//     line appears once a slot is picked.
//
// `appointmentRepositoryProvider` is overridden with a hand-written fake (never a
// real `POST /appointments` route on `FakeBackend`'s `DioAdapter`) — mirrors
// `salon_booking_flow_test.dart`'s precedent (avoids the generated client's
// real-Dio timer leak while exercising the REAL `AppointmentSubmit` notifier +
// confirm/success screens + router end to end).
//
// PATROL — REASONED EXEMPTION: the calendar export ends at the `Event` payload
// handed to `add_2_calendar` (an implicit ACTION_INSERT intent needing no
// runtime permission). The payload — the only part we own — is pinned exactly by
// the channel interception below. No other native surface is involved.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/data/appointment_repository.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/domain/appointment.dart';
import 'package:beautica_mobile/features/booking/domain/booking_confirm_args.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot_picker_args.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/create_appointment_request.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_confirm_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_success_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/my_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/slot_picker_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_card.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/calendar_button.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/slot_chip.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import '../test/helpers/pump_app.dart';
import 'support/app_harness.dart';

/// The `add_2_calendar` plugin's platform boundary — intercepted so the visit
/// export never launches a real OS calendar activity on the emulator.
const MethodChannel _kCalendarChannel = MethodChannel('add_2_calendar');

/// Records every `createAppointment` call and, on the FIRST call only, throws
/// [failOnceWith] if set (then clears it, so a retry succeeds) — mirrors the
/// "fail once, then succeed on retry" shape, keyed by the single visit call.
class _FakeAppointmentRepository implements AppointmentRepository {
  _FakeAppointmentRepository({this.failOnceWith, this.onCreated});

  Failure? failOnceWith;

  /// Invoked synchronously on a SUCCESSFUL create, BEFORE the request resolves —
  /// lets a flow mutate `FakeBackend` state (e.g. append the just-booked visit
  /// to `/bookings/me`) so the confirm screen's post-create
  /// `ref.invalidate(myBookingsProvider(upcoming))` re-fetches the NEW row.
  final void Function(CreateAppointmentRequest req)? onCreated;

  final List<CreateAppointmentRequest> requests = <CreateAppointmentRequest>[];

  @override
  Future<Appointment> createAppointment(CreateAppointmentRequest req) async {
    requests.add(req);
    final Failure? typed = failOnceWith;
    if (typed != null) {
      failOnceWith = null;
      throw typed;
    }
    onCreated?.call(req);
    final DateTime end = req.startAt.add(const Duration(minutes: 150));
    return Appointment(
      id: 'appt-1',
      status: BookingStatus.confirmed,
      masterId: req.masterId,
      masterFirstName: 'Софія',
      masterLastName: 'Бондар',
      masterType: 'INDEPENDENT_MASTER',
      startAt: req.startAt,
      endAt: end,
      totalDurationMinutes: 150,
      totalPrice: 900,
      items: <AppointmentItem>[
        for (final String id in req.masterServiceIds)
          AppointmentItem(
            bookingId: 'booking-$id',
            masterServiceId: id,
            serviceName: 'Послуга',
            startAt: req.startAt,
            endAt: end,
            durationMinutes: 75,
            price: 450,
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
    DateTime newStartAt, {
    bool allowClientOverlap = false,
  }) => throw UnimplementedError();

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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  // The seeded `master-aaa` fixture's two PUBLIC service ids.
  const String masterId = 'master-aaa';
  const String serviceA = 'pub-assign-1';
  const String serviceB = 'pub-assign-2';

  // ONE start time for the whole visit — anchored to the harness's INJECTED
  // clock, not the host's.
  //
  // This is a DISPLAY fixture (it feeds `BookingConfirmArgs.startAt`, which
  // the confirm screen renders and which the POST assertion at
  // `expect(sent.startAt, visitStart)` round-trips) — it never selects a
  // calendar cell, so it is not the shape that broke this file on 2026-08-04.
  // It is still converted rather than annotated, for three reasons:
  //   1. The `// instant-ok:` escape hatch asserts "this read is a genuine
  //      absolute-instant use that clock injection would not change". That
  //      would be FALSE here: the confirm screen formats this instant as a
  //      calendar date through the app's own (injected) clock, so a
  //      host-anchored "+1 day" renders as a date ~7 weeks out rather than
  //      tomorrow. Writing a false reason into the source is precisely the
  //      unverified-assertion failure mode `forbid_host_local_instant_anchor
  //      .sh`'s own header post-mortem is about.
  //   2. "Relative, therefore stable" is stability, not correctness — it
  //      pins nothing, and the rendered date still differs on every run.
  //   3. Leaving ONE host-clock read in the very file whose other host-clock
  //      read was the bug is how this pattern propagates: the three prior
  //      recurrences of this defect class all came from copying a nearby
  //      example.
  // `kFixedNow` is re-exported by `AppHarness`; `+1 day` keeps the original
  // "tomorrow" intent, now relative to the clock the app is actually on.
  final DateTime visitStart = kFixedNow.add(const Duration(days: 1, hours: 10));

  // Display fixtures — the confirm screen renders the visit from
  // `BookingConfirmArgs.services` directly (the ordered selection), so the
  // durations here drive the calendar export window (90 + 60 = 150 min).
  const MasterService svcA = MasterService(
    id: serviceA,
    serviceDefId: 'def-$serviceA',
    name: 'Манікюр з покриттям',
    durationMinutes: 90,
    priceMin: 500,
    priceDisplay: '500 ₴',
    category: 'NAILS',
  );
  const MasterService svcB = MasterService(
    id: serviceB,
    serviceDefId: 'def-$serviceB',
    name: 'Педикюр апаратний',
    durationMinutes: 60,
    priceMin: 400,
    priceDisplay: '400 ₴',
    category: 'NAILS',
  );
  const Master masterDisplay = Master(
    id: masterId,
    firstName: 'Софія',
    lastName: 'Бондар',
    city: 'Київ',
    street: 'вул. Хрещатик',
    buildingNo: '22',
    avgRating: 4.8,
    reviewCount: 47,
    type: MasterType.independentMaster,
  );

  BookingConfirmArgs visitArgs({required String idempotencyKey}) =>
      BookingConfirmArgs(
        masterId: masterId,
        master: masterDisplay,
        services: const <MasterService>[svcA, svcB],
        startAt: visitStart,
        idempotencyKey: idempotencyKey,
      );

  // =========================================================================
  // Test 1 — ACCEPTANCE: two services → ONE POST /appointments (ordered
  // masterServiceIds, one startsAt, one idempotency key) → success recaps the
  // whole visit + exports it as ONE calendar event.
  // =========================================================================
  testWidgets(
    'CLIENT confirms a two-service visit and submits → exactly ONE POST '
    '/appointments (ordered masterServiceIds, one startsAt + idempotencyKey) → '
    'the success screen recaps the visit and exports it as one calendar event',
    (tester) async {
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
          RouteNames.bookingConfirm,
          extra: visitArgs(idempotencyKey: 'itest-visit-key'),
        ),
      );
      await AppHarness.settle(tester);

      AppHarness.expectShellLocation(router, RouteNames.bookingConfirm);
      expect(find.byType(BookingConfirmScreen), findsOneWidget);
      expect(
        fb.getPublicMasterCalls,
        greaterThanOrEqualTo(1),
        reason:
            'the confirm screen must resolve master-aaa through the real '
            'public GET /masters/{id} fetch',
      );
      // The visit recap lists both selected services.
      // i18n-finder-ok: service names are catalogue fixture data.
      expect(find.text('Манікюр з покриттям'), findsOneWidget);
      // i18n-finder-ok: service name is backend fixture data, not localized UI copy
      expect(find.text('Педикюр апаратний'), findsOneWidget);

      // Submit → ONE createAppointment → success.
      await tester.tap(find.byKey(const Key('booking-confirm-submit-cta')));
      await AppHarness.settle(tester);

      AppHarness.expectShellLocation(router, RouteNames.bookingSuccess);
      expect(find.byType(BookingSuccessScreen), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Exactly ONE request carrying BOTH ordered service ids + the single key.
      expect(repo.requests, hasLength(1));
      final CreateAppointmentRequest sent = repo.requests.single;
      expect(sent.masterId, masterId);
      expect(sent.masterServiceIds, <String>[serviceA, serviceB]);
      expect(sent.startAt, visitStart);
      expect(sent.idempotencyKey, 'itest-visit-key');

      // ── ONE visit-level calendar export ────────────────────────────────
      final List<MethodCall> calendarCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_kCalendarChannel, (MethodCall call) async {
            calendarCalls.add(call);
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_kCalendarChannel, null),
      );

      expect(find.byType(CalendarButton), findsOneWidget);
      final Finder button = find.byKey(
        const Key('booking-success-add-calendar'),
      );
      expect(button, findsOneWidget);
      await tester.ensureVisible(button);
      await AppHarness.settle(tester);
      await tester.tap(button);
      await AppHarness.settle(tester);

      expect(calendarCalls, hasLength(1));
      expect(calendarCalls.single.method, 'add2Cal');
      final Map<Object?, Object?> args =
          calendarCalls.single.arguments as Map<Object?, Object?>;
      // ONE event spanning the whole visit: start = visitStart, end = start +
      // summed duration (90 + 60 = 150 min).
      expect(args['startDate'], visitStart.millisecondsSinceEpoch);
      const int msPerMinute = 60 * 1000;
      expect(
        (args['endDate']! as int) - (args['startDate']! as int),
        150 * msPerMinute,
        reason:
            'the visit event must span the summed duration of both services',
      );
      // The title names both services in the visit.
      final String title = args['title']! as String;
      expect(title.contains('Манікюр з покриттям'), isTrue);
      expect(title.contains('Педикюр апаратний'), isTrue);
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  // =========================================================================
  // Test 2 — the single submit 409s with CLIENT_BOOKING_CONFLICT → the confirm
  // screen STAYS and the conflict surfaces EXACTLY ONCE, through EXACTLY ONE
  // surface: the shared `showClientBookingConflictDialog` POPUP, never the
  // bottom `booking-confirm-submit-error` banner. Confirming the popup
  // resubmits the SAME request — same idempotency key — with
  // `allowClientOverlap: true` and reaches success.
  //
  // This body originally pinned the OPPOSITE mapping (banner shown, dialog
  // absent), which was correct when it was written on 2026-07-15. Commit
  // `4d49d1c3` (2026-08-27, "fix(booking): show the overlap conflict as a
  // popup, not a red banner") deliberately reversed it — the salon flow had
  // answered the same failure with the same dialog since `92644d2e`, and the
  // client paths were brought onto it. That commit updated the widget tier but
  // not this one, so the two drifted. The widget tier's counterpart is
  // `test/features/booking/presentation/booking_confirm_test.dart`'s
  // "client-create: a ClientBookingConflictFailure opens the conflict dialog
  // and renders NO bottom error banner" — this flow proves the same contract
  // survives the REAL router/shell/session wiring.
  // =========================================================================
  testWidgets(
    'CLIENT submits a visit, the create 409s with CLIENT_BOOKING_CONFLICT → the '
    'confirm screen stays and the conflict surfaces exactly ONCE as the popup '
    '(never the bottom banner) → confirming it resubmits the same idempotency '
    'key with allowClientOverlap and reaches success',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      final ClientBookingConflictFailure conflict =
          ClientBookingConflictFailure(
            conflictingBookingId: 'other-booking-1',
            serviceName: 'Педикюр апаратний',
            masterName: 'Ірина Шевченко',
            // The CLASHING booking's own window, not this visit's. It is only
            // ever fed to a pure absolute formatter inside the conflict popup's
            // `client-booking-conflict-existing` row (asserted below), never
            // compared against the wall clock — and `startsAt`/`endsAt` must
            // stay a matched pair, so anchoring one of them to now would invert
            // the window.
            // future-date-ok: pinned conflict window, no wall-clock read.
            startsAt: DateTime.utc(2026, 7, 16, 14),
            // future-date-ok: pinned conflict window, no wall-clock read.
            endsAt: DateTime.utc(2026, 7, 16, 15, 30),
          );
      final repo = _FakeAppointmentRepository(failOnceWith: conflict);
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
          RouteNames.bookingConfirm,
          extra: visitArgs(idempotencyKey: 'itest-pf-key'),
        ),
      );
      await AppHarness.settle(tester);

      AppHarness.expectShellLocation(router, RouteNames.bookingConfirm);
      expect(find.byType(BookingConfirmScreen), findsOneWidget);

      // ── First submit → 409 ──────────────────────────────────────────────
      await tester.tap(find.byKey(const Key('booking-confirm-submit-cta')));
      await AppHarness.settle(tester);

      // STAYS on the confirm screen — no navigation, no crash.
      AppHarness.expectShellLocation(router, RouteNames.bookingConfirm);
      expect(find.byType(BookingConfirmScreen), findsOneWidget);
      expect(find.byType(BookingSuccessScreen), findsNothing);

      // ── EXACTLY ONE surface, and it is the popup ────────────────────────
      // `findsOneWidget` carries the "exactly one" half on its own: a second
      // dialog stacked on top (a double-submit, a retry re-entering `_submit`
      // while the first is still up) fails here rather than passing.
      final Finder conflictDialog = find.byKey(
        const Key('client-booking-conflict-dialog'),
      );
      expect(
        conflictDialog,
        findsOneWidget,
        reason:
            'a CLIENT_BOOKING_CONFLICT must open the shared popup — the '
            'contract commit 4d49d1c3 moved the client-create path onto',
      );
      // …and the OTHER surface stays silent. Asserting only the dialog would
      // let the retired banner creep back BESIDE it as a duplicate second
      // surface for the same failure — the exact drift this pair guards.
      expect(
        find.byKey(const Key('booking-confirm-submit-error')),
        findsNothing,
        reason:
            'the popup replaces the bottom error banner for this failure — '
            'never both, never the banner alone',
      );
      // The one surface that DID render names the CLASHING booking, so the
      // conflict is legible from it. Scoped to the row's own subtree: the
      // service name is also the visit's own second service, so an unscoped
      // `find.text` would match the recap and pass vacuously.
      final Finder existingRow = find.byKey(
        const Key('client-booking-conflict-existing'),
      );
      expect(existingRow, findsOneWidget);
      expect(
        find.descendant(
          of: existingRow,
          matching: find.textContaining('Ірина Шевченко'),
        ),
        findsOneWidget,
        reason: "the popup must name the clashing booking's master",
      );

      expect(repo.requests, hasLength(1));
      expect(
        repo.requests.single.allowClientOverlap,
        isFalse,
        reason: 'the FIRST attempt never waives the client overlap check',
      );

      // ── Confirm the popup → resubmit with the override → success ────────
      await tester.tap(
        find.byKey(const Key('client-booking-conflict-proceed')),
      );
      await AppHarness.settle(tester);

      AppHarness.expectShellLocation(router, RouteNames.bookingSuccess);
      expect(find.byType(BookingSuccessScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      // The single surface is GONE once resolved — it neither lingers over the
      // success screen nor hands the failure off to the banner on its way out.
      expect(conflictDialog, findsNothing);
      expect(
        find.byKey(const Key('booking-confirm-submit-error')),
        findsNothing,
      );

      // Two submits, both reusing the SAME stable idempotency key so the
      // ambiguously-failed first attempt de-duplicates server-side. Only the
      // SECOND carries the client's explicit overlap waiver.
      expect(repo.requests, hasLength(2));
      expect(repo.requests[0].idempotencyKey, 'itest-pf-key');
      expect(
        repo.requests[1].idempotencyKey,
        equals(repo.requests[0].idempotencyKey),
        reason: 'the resubmit must REUSE the same key, never mint a fresh one',
      );
      expect(
        repo.requests[1].allowClientOverlap,
        isTrue,
        reason:
            'confirming the popup is what waives the overlap check — without '
            'the flag the resubmit would simply 409 again',
      );
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  // =========================================================================
  // Test 3 — the real date→time picker (`SlotDateScreen` → `SlotTimeScreen`)
  // with a two-service selection: the pinned "Послуги та ціни" shelf lists both
  // services, and the single chosen-window line appears once a slot is picked.
  // =========================================================================
  testWidgets(
    'CLIENT drives date→time for a two-service visit: the shelf lists both '
    'services, and the single chosen-window line appears after a slot is picked',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;

      // AN AWKWARD WORKING WINDOW — 13:00-15:00 Kyiv, i.e. 10:00Z / 10:30Z /
      // 11:00Z on the June (EEST, +3) day `kFixedNow` sits on.
      //
      // This is the exact shape of the HIGH bug that shipped: the group
      // headings (Ранок / День / Вечір) were bucketed on `startAt.hour` — the
      // RAW UTC hour — while the chip beside them rendered `formatSlotTime`,
      // the Kyiv wall-clock. Every one of these three slots therefore rendered
      // a correct `13:00` / `13:30` / `14:00` label filed under «Ранок».
      //
      // The default fixture (07:00Z / 11:00Z → 10:00 and 14:00 Kyiv) cannot
      // see it: its raw UTC hours (7, 11) land in the same buckets the Kyiv
      // hours do, near enough that the flow still looks sane. A window whose
      // UTC hour and Kyiv hour fall on OPPOSITE sides of the 12:00 cut point is
      // what makes the incoherence observable end-to-end.
      //
      // The widget tier pins the same contract exhaustively (both boundaries,
      // both seasons, both pickers) in
      // `test/features/booking/presentation/slot_bucket_heading_tz_test.dart`;
      // this flow proves it survives the REAL provider→repository→Dio wiring
      // and the real `Iso8601DateTimeSerializer` `.toUtc()` normalisation,
      // which no widget test exercises.
      fb.availableSlotUtcStarts = const <(int, int)>[
        (10, 0),
        (10, 30),
        (11, 0),
      ];

      final GoRouter router = await AppHarness.boot(tester, fb);

      await AppHarness.loginAs(tester, fb, UserRole.client);
      await AppHarness.settle(tester);

      // Enter AT the date step with the two-service selection (mirrors the push
      // `ServiceSelectorSheet` makes into `/booking/slots`).
      unawaited(
        router.push(
          RouteNames.bookingSlots,
          extra: const BookingSlotPickerArgs(
            masterId: masterId,
            master: masterDisplay,
            services: <MasterService>[svcA, svcB],
          ),
        ),
      );
      await AppHarness.settle(tester);

      AppHarness.expectShellLocation(router, RouteNames.bookingSlots);
      expect(find.byType(SlotDateScreen), findsOneWidget);

      // The calendar's availability query must carry BOTH chosen services, in
      // order — the generated client sends `serviceId` as a REPEATED param
      // (Dio `ListParam`/`ListFormat.multi`), so a regression that collapses it
      // to a single scalar would silently price the visit as one service. The
      // scalar `lastMasterAaaWorkingDaysServiceId` telemetry cannot see this;
      // it keeps only the first id.
      expect(
        fb.lastMasterAaaWorkingDaysServiceIds,
        <String>[serviceA, serviceB],
        reason:
            'a two-service visit must thread both masterServiceIds into '
            'GET /working-days, in the order the client picked them',
      );

      final Finder shelfList = find.byKey(
        const Key('booking-summary-expanded-list'),
      );

      // Expand the shelf → both services listed.
      await tester.tap(find.byKey(const Key('booking-summary-expand-toggle')));
      await AppHarness.settle(tester);
      expect(shelfList, findsOneWidget);
      expect(
        find.descendant(
          of: shelfList,
          matching: find.byKey(const ValueKey<String>(serviceA)),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: shelfList,
          matching: find.byKey(const ValueKey<String>(serviceB)),
        ),
        findsOneWidget,
      );
      // No chosen window yet (still on the date step).
      expect(find.byIcon(Icons.event_available_rounded), findsNothing);
      // Collapse before driving the calendar.
      await tester.tap(find.byKey(const Key('booking-summary-expand-toggle')));
      await AppHarness.settle(tester);

      // Pick today (a working day over the real working-days endpoint) → «Далі»
      // to reach the time step.
      //
      // Kyiv "today" AS THE APP UNDER TEST COMPUTES IT, derived from the
      // harness's INJECTED clock (`kFixedNow`, 2026-06-14 12:00 UTC), never
      // the host device clock. `SlotDateScreen._today` reads `clockProvider`,
      // which `AppHarness.boot` overrides to `kFixedNow`, so the visible month
      // + "today" cell are always June 2026 no matter what day the suite runs
      // on. The bare `DateTime.now()` this used to read instead passed only by
      // ACCIDENT, whenever the real run date's day-of-month happened to land
      // on/after the 14th — any run on the 1st–13th tapped an ALREADY-PAST
      // June cell, which `MonthCalendar` renders with `onTap: null` and no
      // `GestureDetector` at all, so the tap is a silent no-op and the flow
      // dies at the time step. Mirrors `client_reschedule_flow_test.dart` and
      // `master_bookings_flow_test.dart`'s `_kyivToday`. DO NOT regress this
      // back to a host-clock read.
      final DateTime today = kyivToday(() => kFixedNow);
      // Via `tapCalendarDay` (NOT a blind `tester.tap`): at the harness's
      // 800×600 surface the last grid rows sit below the scroll fold, so a
      // blind tap silently lands on the summary bar. See the extension's doc
      // comment in test/helpers/pump_app.dart.
      await tester.tapCalendarDay(today.day);
      await AppHarness.settle(tester);
      await tester.tap(find.byKey(const Key('booking-summary-cta')));
      await AppHarness.settle(tester);

      AppHarness.expectShellLocation(router, RouteNames.bookingSlotsTime);
      expect(find.byType(SlotTimeScreen), findsOneWidget);

      // ── THE HEADING/LABEL COHERENCE PIN (Step 2.7 Rule 3b) ──────────────
      //
      // Round-trip check across the REAL wire: the fixture put 10:00Z /
      // 10:30Z / 11:00Z on the adapter, the generated client normalised them
      // to UTC, and the picker must render them at the KYIV wall-clock AND
      // file them under the heading that matches that same wall-clock.
      final AppLocalizations timeL10n = AppLocalizations.of(
        tester.element(find.byType(SlotTimeScreen)),
      );

      final List<String> chipLabels = tester
          .widgetList<SlotChip>(find.byType(SlotChip))
          .map((SlotChip c) => c.time)
          .toList(growable: false);
      expect(
        chipLabels,
        <String>['13:00', '13:30', '14:00'],
        reason:
            'the seeded 10:00Z/10:30Z/11:00Z window must render at the Kyiv '
            'wall-clock. If this reads 10:00/10:30/11:00 the display zone '
            'regressed to raw UTC; if it shifted by an hour, kFixedNow moved '
            'out of EEST and this fixture needs re-deriving.',
      );

      final List<String> groupLabels = tester
          .widgetList<SlotGroup>(find.byType(SlotGroup))
          .map((SlotGroup g) => g.label)
          .toList(growable: false);
      expect(
        groupLabels,
        <String>[timeL10n.bookingAfternoonLabel],
        reason:
            'a 13:00-15:00 KYIV window is entirely afternoon. Bucketing on the '
            'raw UTC hour (10, 10, 11) files the whole day under «Ранок» — the '
            'shipped bug — and renders the MORNING heading above chips '
            'labelled 13:00.',
      );

      // Pick the first available slot → the single chosen-window line appears.
      final Finder availableChip = find
          .byWidgetPredicate((Widget w) => w is SlotChip && w.available)
          .first;
      await tester.ensureVisible(availableChip);
      await AppHarness.settle(tester);
      await tester.tap(availableChip);
      await AppHarness.settle(tester);

      expect(
        find.byIcon(Icons.event_available_rounded),
        findsOneWidget,
        reason:
            'the single visit chosen-window line renders once a slot is picked',
      );
      expect(tester.takeException(), isNull);

      // The l10n handle is resolvable (locale wired) — a light sanity touch so
      // the import stays load-bearing and the screen is truly mounted.
      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(SlotTimeScreen)),
      );
      expect(l10n.bookingConfirmCta, isNotEmpty);
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  // =========================================================================
  // Test 4 — STALE-MY-BOOKINGS regression (Step 2.7 Rule 3b). THE gap the
  // debugger named: the client shell is a `StatefulShellRoute.indexedStack`, so
  // once the CLIENT opens the Записи tab its `MyBookingsScreen` branch stays
  // MOUNTED (offstage) while the booking flow is pushed on top of it — its
  // autoDispose `myBookingsProvider(upcoming)` therefore never re-fetches on a
  // plain tab re-select. A newly-created booking is auto-CONFIRMED → belongs in
  // upcoming, but the mounted-and-cached list did NOT show it until a manual
  // pull-to-refresh. The fix: `BookingConfirmScreen._submit` invalidates
  // `myBookingsProvider(BookingTab.upcoming)` from the widget layer on the
  // CREATE success path (mirroring the reschedule path).
  //
  // The widget tier proves the invalidate fires (booking_confirm_test.dart's
  // "a successful CREATE invalidates upcoming My Bookings" + the salon twin).
  // NO widget test proves the REAL indexedStack scenario end-to-end: open the
  // tab ONCE (branch mounts + caches an EMPTY upcoming list) → book a visit
  // through the real confirm→success flow → return to the ALREADY-MOUNTED tab →
  // the new card is visible WITHOUT any pull-to-refresh gesture. This is that
  // flow. `/bookings/me` starts EMPTY and the fake create appends the booked row
  // to the FakeBackend dataset, so the ONLY way the card appears on return is
  // the confirm screen's invalidate re-fetching the mounted branch. Removing the
  // invalidate makes the final assertion fail (verified by mutation).
  testWidgets('CLIENT opens the (empty) Записи tab, books a visit, returns to the '
      'already-mounted tab and sees the new booking WITHOUT a pull-to-refresh '
      '(indexedStack keeps the branch mounted)', (tester) async {
    final fb = FakeBackend()..currentRole = UserRole.client;
    // The upcoming list starts EMPTY — the mounted branch caches "no bookings".
    fb.seedManyBookingsDataset(const <Map<String, dynamic>>[]);

    const String newBookingId = 'booking-created-1';
    // On a successful create the fake backend gains ONE upcoming (CONFIRMED,
    // future) booking — exactly what a real auto-confirmed POST /appointments
    // would make visible on the next GET /bookings/me.
    final repo = _FakeAppointmentRepository(
      onCreated: (CreateAppointmentRequest req) {
        fb.seedManyBookingsDataset(<Map<String, dynamic>>[
          fb.datasetBookingRow(
            id: newBookingId,
            status: 'CONFIRMED',
            startsAt: req.startAt,
            duration: const Duration(minutes: 150),
          ),
        ]);
      },
    );

    final GoRouter router = await AppHarness.boot(
      tester,
      fb,
      extraOverrides: <Object>[
        appointmentRepositoryProvider.overrideWithValue(repo),
      ],
    );

    await AppHarness.loginAs(tester, fb, UserRole.client);
    await AppHarness.settle(tester);

    // ── 1. Open the Записи branch ONCE — the indexedStack mounts it and its
    //       myBookingsProvider(upcoming) caches the EMPTY list. ─────────────
    await tester.tap(find.byKey(const Key('client-nav-tile-3')));
    await AppHarness.settle(tester);
    AppHarness.expectLocation(router, RouteNames.clientBookings);
    expect(find.byType(MyBookingsScreen), findsOneWidget);
    expect(
      find.byType(BookingCard),
      findsNothing,
      reason: 'the upcoming tab starts empty — nothing booked yet',
    );
    expect(
      find.byKey(const ValueKey<String>('service-$newBookingId')),
      findsNothing,
    );

    // ── 2. Book a visit: push the REAL confirm screen ON TOP of the shell
    //       (the Записи branch stays mounted offstage), then submit. ────────
    unawaited(
      router.push(
        RouteNames.bookingConfirm,
        extra: visitArgs(idempotencyKey: 'itest-stale-list-key'),
      ),
    );
    await AppHarness.settle(tester);
    AppHarness.expectShellLocation(router, RouteNames.bookingConfirm);
    expect(find.byType(BookingConfirmScreen), findsOneWidget);

    await tester.tap(find.byKey(const Key('booking-confirm-submit-cta')));
    await AppHarness.settle(tester);

    AppHarness.expectShellLocation(router, RouteNames.bookingSuccess);
    expect(find.byType(BookingSuccessScreen), findsOneWidget);
    expect(repo.requests, hasLength(1));

    // ── 3. Leave the success screen for /home, then re-select the Записи tab.
    //       NO pull-to-refresh is performed anywhere in this flow. ──────────
    await tester.tap(find.byKey(const Key('booking-success-home-cta')));
    await AppHarness.settle(tester);
    AppHarness.expectLocation(router, RouteNames.clientHome);

    await tester.tap(find.byKey(const Key('client-nav-tile-3')));
    await AppHarness.settle(tester);
    AppHarness.expectLocation(router, RouteNames.clientBookings);
    expect(find.byType(MyBookingsScreen), findsOneWidget);

    // ── 4. THE ASSERTION: the just-booked visit is visible on the mounted
    //       upcoming tab with NO manual refresh — only the confirm screen's
    //       widget-layer invalidate could have re-fetched the branch. ───────
    expect(
      find.byType(BookingCard),
      findsOneWidget,
      reason:
          'the auto-CONFIRMED booking must appear on the already-mounted '
          'Записи tab after the create — the confirm screen invalidated '
          'myBookingsProvider(upcoming), so the indexedStack-cached branch '
          're-fetched WITHOUT a pull-to-refresh',
    );
    expect(
      find.byKey(const ValueKey<String>('service-$newBookingId')),
      findsOneWidget,
    );
    final AppLocalizations listL10n = AppLocalizations.of(
      tester.element(find.byType(MyBookingsScreen)),
    );
    expect(
      find.text(listL10n.bookingStatusConfirmed),
      findsOneWidget,
      reason: 'the new card carries the «Підтверджено» badge',
    );
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 120)));
}
