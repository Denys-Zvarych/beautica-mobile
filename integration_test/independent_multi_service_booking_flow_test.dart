// mobile-qa — Step 2.7 Rule 3b E2E coverage for the INDEPENDENT-master
// MULTI-SERVICE booking flow (the multi-service booking rework).
//
// WHY THIS FILE EXISTS
// --------------------
// The independent-master flow now carries all N selected services through to
// the confirm screen, submitting ONE `POST /bookings` per service (same
// master, distinct service + start + stable idempotency key each), with
// EXPLICIT per-appointment partial-failure handling. The widget tier proves
// the pieces in isolation:
//   • `test/.../booking_time_screen_test.dart` — the PageView schedules two
//     services into two appointments with distinct stable keys + the
//     self-overlap guard;
//   • `test/.../booking_confirm_test.dart` — the confirm screen's submit,
//     per-appointment error row, partial-failure SnackBar, and same-key retry
//     (single appointment, hand-stubbed providers).
// Neither proves the REAL multi-appointment journey end to end: a CLIENT
// logged in against the fake backend, landing on the REAL
// `BookingConfirmScreen` (its `publicMasterProfileProvider(master-aaa)`
// resolved through the REAL fake-backed public master repository — both
// selected services resolved out of the genuine
// `GET /masters/master-aaa/services` response, not a stubbed fixture tuple),
// submitting TWO appointments, and reaching the success screen with two
// confirmed cards — plus the partial-failure variant where one service's 409
// keeps the client on the confirm screen and a retry re-sends ONLY the failed
// service with its SAME stable key.
//
// SUPERSEDES `client_booking_conflict_flow_test.dart` (removed): that file
// still asserted the OLD single-appointment `ClientBookingConflictDialog`
// (keys `client-booking-conflict-dialog/-stay/-pick-another-time`), which the
// reworked confirm screen NO LONGER shows — a 409 now surfaces as a
// per-appointment error row + a partial-failure SnackBar (never a modal). Its
// CLIENT_BOOKING_CONFLICT scenario is re-authored here against the new
// contract (Test 2).
//
// `bookingRepositoryProvider` is overridden with a hand-written fake (never a
// `POST /bookings` route on `FakeBackend`'s `DioAdapter`) — mirrors the
// established precedent in `salon_booking_flow_test.dart`'s
// `_FakeBookingRepository` (its file header explains why: it avoids the
// generated booking client's real-Dio timer leak while still exercising the
// REAL `IndependentBookingSubmit` notifier + confirm/success screens + router
// end to end).
//
// Test 3 (added with the "selected services" shelf) enters AT the time step
// (`/booking/slots/time`, real `BookingTimeScreen` + real
// `slotRepositoryProvider` over the fake backend's working-days/slots routes)
// and proves the pinned shelf lists both selected services and that a
// service's per-service chosen-window line appears in the shelf only after its
// slot is picked — the one end-to-end place the time-step shelf is exercised
// (Tests 1–2 deliberately push past this screen).
//
// Test 1 additionally covers the PER-APPOINTMENT «Додати в календар» export
// (the calendar rework: one page-level pill → N card-scoped buttons). The
// widget suite `test/.../booking_success_calendar_test.dart` pumps
// `BookingSuccessScreen` with HAND-BUILT `BookingSuccessArgs`, so the one
// thing it cannot prove is the wiring that produces those args: which
// `MasterService` the confirm screen resolved for appointment i, and which
// `startAt` it carried over. Here card i's exported Event window is checked
// against the REAL `GET /masters/master-aaa/services` catalogue — `pub-assign-1`
// is 90 min, `pub-assign-2` is 60 min — so an off-by-one in the
// resolved→success mapping (the exact defect the rework fixed) shows up as the
// wrong duration, not merely the wrong label.
//
// PATROL — REASONED EXEMPTION, not a deferral. The export is a platform-channel
// call, but the app-side contract ENDS at the `Event` payload handed to
// `add_2_calendar`: on Android it is an implicit ACTION_INSERT intent, which
// needs no runtime permission (nothing for `$.native.*` to grant or dismiss)
// and hands off to whatever calendar app the device happens to have. A CI
// emulator image may have none at all — the honest outcome there is
// ActivityNotFoundException, which is already pinned at the helper tier
// (`add_to_calendar_test.dart`) and at the screen tier (the failure/guard-release
// cases). A Patrol test could therefore only assert "some third-party activity
// appeared", which is neither deterministic nor a statement about this app. The
// payload — the only part we own and the only part that can regress — is pinned
// exactly by the channel interception below. No other native surface is
// involved in this flow (no permission dialog, deep link, FCM/local
// notification, WebView, or biometric).

import 'dart:async';

import 'package:dio/dio.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_appointment.dart';
import 'package:beautica_mobile/features/booking/domain/booking_confirm_args.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot_picker_args.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/create_booking_request.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_confirm_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_success_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_time_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/calendar_button.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

/// The `add_2_calendar` plugin's platform boundary — intercepted so the
/// per-appointment export never launches a real OS calendar activity on the
/// emulator (same seam `client_my_bookings_cancel_flow_test.dart` and
/// `booking_price_band_flow_test.dart` already use).
const MethodChannel _kCalendarChannel = MethodChannel('add_2_calendar');

/// Records every `createBooking` call and, for each serviceId in
/// [failOnceWith], throws its mapped [Failure] on THAT service's FIRST call
/// only (then clears it, so a retry of the same service succeeds). Mirrors
/// `salon_booking_flow_test.dart`'s `_FakeBookingRepository` "fail once, then
/// succeed on retry" shape, keyed by SERVICE instead of MASTER (the
/// independent flow's `IndependentBookingSubmit` makes one `createBooking`
/// call per SERVICE per submit pass).
class _FakeBookingRepository implements BookingRepository {
  _FakeBookingRepository({
    Map<String, Failure> failOnceWith = const <String, Failure>{},
  }) : _failOnceWith = <String, Failure>{...failOnceWith};

  final Map<String, Failure> _failOnceWith;
  final List<CreateBookingRequest> requests = <CreateBookingRequest>[];

  int callsFor(String serviceId) => requests
      .where((CreateBookingRequest r) => r.serviceId == serviceId)
      .length;

  List<CreateBookingRequest> requestsFor(String serviceId) => requests
      .where((CreateBookingRequest r) => r.serviceId == serviceId)
      .toList(growable: false);

  @override
  Future<Booking> createBooking(CreateBookingRequest req) async {
    requests.add(req);
    final Failure? typed = _failOnceWith.remove(req.serviceId);
    if (typed != null) throw typed;
    return Booking(
      id: 'booking-${req.serviceId}',
      masterId: req.masterId,
      masterFirstName: 'Софія',
      masterLastName: 'Бондар',
      masterType: 'INDEPENDENT_MASTER',
      serviceId: req.serviceId,
      serviceName: 'Послуга',
      durationMinutes: 60,
      price: 500,
      startAt: req.startAt,
      endAt: req.startAt.add(const Duration(minutes: 60)),
      status: BookingStatus.confirmed,
      canReview: false,
    );
  }

  @override
  Future<PageResponse<Booking>> getMyBookings({
    required Iterable<BookingStatus> statuses,
    BookingSort? sort,
    required int page,
    int size = kBookingsPageSize,
    Iterable<String>? serviceIds,
    DateTime? from,
    DateTime? to,
    CancelToken? cancelToken,
  }) => throw UnimplementedError();

  @override
  Future<List<DateTime>> getMyBookedDays({
    required DateTime from,
    required DateTime to,
    CancelToken? cancelToken,
  }) => throw UnimplementedError();

  @override
  Future<Booking> getBookingById(String id) => throw UnimplementedError();

  @override
  Future<void> createReview({
    required String bookingId,
    required int rating,
    String? comment,
  }) => throw UnimplementedError();

  @override
  Future<void> cancelBooking(String id, {String? reason}) =>
      throw UnimplementedError();

  @override
  Future<Booking> rescheduleBooking(String id, DateTime newStartAt) =>
      throw UnimplementedError();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  void expectLocation(GoRouter router, String expected) {
    final String current =
        router.routerDelegate.currentConfiguration.matches.last.matchedLocation;
    expect(
      current,
      startsWith(expected),
      reason: 'Expected router location to start with $expected, got $current',
    );
  }

  // The seeded `master-aaa` fixture's own two PUBLIC service ids
  // (`FakeBackend._publicMasterServices` — the SAME `GET
  // /masters/master-aaa/services` response `public_master_profile_flow_test.dart`
  // reads). The confirm screen resolves each appointment's service DISPLAY
  // object out of that real response, so these ids MUST match it.
  const String masterId = 'master-aaa';
  const String serviceA = 'pub-assign-1';
  const String serviceB = 'pub-assign-2';

  // Two distinct, non-overlapping starts — one per service (what
  // `BookingTimeScreen` would have snapshotted from two separate slide picks).
  final DateTime startA = DateTime.now().add(
    const Duration(days: 1, hours: 10),
  );
  final DateTime startB = DateTime.now().add(
    const Duration(days: 1, hours: 14),
  );

  // Display fixtures for the TIME-STEP variant (Test 3). The shelf itemises
  // these `MasterService`s; the slot fetch itself is path-only on
  // `master-aaa/slots` (query ignored), so the ids only need to match
  // `master-aaa`'s two public catalogue ids for realism.
  const MasterService svcADisplay = MasterService(
    id: serviceA,
    serviceDefId: 'def-$serviceA',
    name: 'Манікюр з покриттям',
    durationMinutes: 60,
    priceMin: 500,
    priceDisplay: '500 ₴',
    category: 'NAILS',
  );
  const MasterService svcBDisplay = MasterService(
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

  BookingConfirmArgs twoServiceArgs({
    required String keyA,
    required String keyB,
  }) => BookingConfirmArgs(
    masterId: masterId,
    appointments: <BookingAppointment>[
      BookingAppointment(
        serviceId: serviceA,
        startAt: startA,
        idempotencyKey: keyA,
      ),
      BookingAppointment(
        serviceId: serviceB,
        startAt: startB,
        idempotencyKey: keyB,
      ),
    ],
  );

  // =========================================================================
  // Test 1 — ACCEPTANCE: two services, two non-overlapping slots, submit →
  // exactly two `POST /bookings` (same master, distinct service + start +
  // stable key) → success screen shows two confirmed bookings.
  // =========================================================================
  testWidgets(
    'CLIENT confirms two services and submits → exactly two POST /bookings '
    '(same masterId, distinct serviceId + startsAt + idempotencyKey) → the '
    'success screen recaps two confirmed appointments',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      final repo = _FakeBookingRepository();
      final GoRouter router = await AppHarness.boot(
        tester,
        fb,
        extraOverrides: <Object>[
          bookingRepositoryProvider.overrideWithValue(repo),
        ],
      );

      await AppHarness.loginAs(tester, fb, UserRole.client);
      await AppHarness.settle(tester);

      // Land on the REAL confirm screen with two fully-resolved appointments
      // (mirrors `BookingTimeScreen._confirm`'s push), through the real
      // clientOnlyGuard. `publicMasterProfileProvider(master-aaa)` resolves
      // BOTH services out of the genuine `GET /masters/master-aaa/services`
      // response, not a stubbed fixture tuple.
      unawaited(
        router.push(
          RouteNames.bookingConfirm,
          extra: twoServiceArgs(
            keyA: 'itest-multi-key-A',
            keyB: 'itest-multi-key-B',
          ),
        ),
      );
      await AppHarness.settle(tester);

      expectLocation(router, RouteNames.bookingConfirm);
      expect(find.byType(BookingConfirmScreen), findsOneWidget);
      expect(
        fb.getPublicMasterCalls,
        greaterThanOrEqualTo(1),
        reason:
            'the confirm screen must resolve master-aaa through the real '
            'public GET /masters/{id} fetch, not a stubbed fixture',
      );
      // Both appointment cards render (one per selected service).
      expect(
        find.byKey(const ValueKey<String>('booking-confirm-appt-$serviceA')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('booking-confirm-appt-$serviceB')),
        findsOneWidget,
      );

      // Submit → both `POST /bookings` succeed → success screen.
      await tester.tap(find.byKey(const Key('booking-confirm-submit-cta')));
      await AppHarness.settle(tester);

      expectLocation(router, RouteNames.bookingSuccess);
      expect(find.byType(BookingSuccessScreen), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Exactly TWO requests — one per service.
      expect(repo.requests, hasLength(2));
      expect(repo.callsFor(serviceA), 1);
      expect(repo.callsFor(serviceB), 1);

      final CreateBookingRequest reqA = repo.requestsFor(serviceA).single;
      final CreateBookingRequest reqB = repo.requestsFor(serviceB).single;

      // SAME master.
      expect(reqA.masterId, masterId);
      expect(reqB.masterId, masterId);

      // DISTINCT serviceId + startsAt.
      expect(reqA.serviceId, isNot(reqB.serviceId));
      expect(reqA.startAt, startA);
      expect(reqB.startAt, startB);
      expect(reqA.startAt, isNot(reqB.startAt));

      // DISTINCT stable idempotency keys (one per appointment — never shared).
      expect(reqA.idempotencyKey, 'itest-multi-key-A');
      expect(reqB.idempotencyKey, 'itest-multi-key-B');
      expect(reqA.idempotencyKey, isNot(reqB.idempotencyKey));

      // The success recap lists one card per confirmed appointment (key
      // `booking-success-appt-<serviceId>-<index>`).
      expect(
        find.byKey(const ValueKey<String>('booking-success-appt-$serviceA-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('booking-success-appt-$serviceB-1')),
        findsOneWidget,
      );

      // ── 4. PER-APPOINTMENT CALENDAR EXPORT (Step 2.7 Rule 3b) ────────────
      // The OS INSERT sheet takes ONE event per invocation, so the retired
      // page-level pill could only ever seed the first of N. Every card now
      // carries its own button — and the fact under test HERE (unreachable
      // from the widget suite, which hand-builds `BookingSuccessArgs`) is that
      // the confirm screen carried the RIGHT resolved service and start into
      // card i. `pub-assign-1` is 90 min and `pub-assign-2` is 60 min in the
      // real `GET /masters/master-aaa/services` response, so a mapping that
      // slipped by one card would export the wrong WINDOW, not just the wrong
      // label.
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

      expect(
        find.byType(CalendarButton),
        findsNWidgets(2),
        reason: 'one export per confirmed appointment, never one for the page',
      );

      Future<Map<Object?, Object?>> exportCard(String serviceId, int i) async {
        calendarCalls.clear();
        final Finder button = find.byKey(
          ValueKey<String>('booking-success-add-calendar-$serviceId-$i'),
        );
        expect(button, findsOneWidget);
        await tester.ensureVisible(button);
        await AppHarness.settle(tester);
        await tester.tap(button);
        await AppHarness.settle(tester);
        expect(calendarCalls, hasLength(1));
        expect(calendarCalls.single.method, 'add2Cal');
        return calendarCalls.single.arguments as Map<Object?, Object?>;
      }

      final Map<Object?, Object?> exportA = await exportCard(serviceA, 0);
      final Map<Object?, Object?> exportB = await exportCard(serviceB, 1);

      // Each card exports ITS OWN start — the very instants submitted above.
      expect(exportA['startDate'], startA.millisecondsSinceEpoch);
      expect(exportB['startDate'], startB.millisecondsSinceEpoch);

      // …and ITS OWN duration, resolved out of the real catalogue response
      // (90 min vs 60 min). Asserted as a delta so the check reads as
      // "this card's service", not "this hard-coded instant".
      const int msPerMinute = 60 * 1000;
      expect(
        (exportA['endDate']! as int) - (exportA['startDate']! as int),
        90 * msPerMinute,
        reason: 'pub-assign-1 is 90 min in GET /masters/master-aaa/services',
      );
      expect(
        (exportB['endDate']! as int) - (exportB['startDate']! as int),
        60 * msPerMinute,
        reason:
            'pub-assign-2 is 60 min — a first-card fallback would export 90',
      );

      // Distinct services, one shared master address (the recap's address card
      // is page-level; only the appointment differs card to card).
      expect(exportA['title'], isNot(exportB['title']));
      expect(exportA['location'], isNotNull);
      expect(exportB['location'], exportA['location']);

      // The structured description follows the same appointment as the window.
      final AppLocalizations successL10n = AppLocalizations.of(
        tester.element(find.byType(BookingSuccessScreen)),
      );
      String serviceLine(Map<Object?, Object?> args) =>
          (args['desc']! as String)
              .split('\n')
              .firstWhere(
                (String line) =>
                    line.startsWith(successL10n.bookingCalendarNoteService),
                orElse: () => '',
              );
      expect(serviceLine(exportA), isNotEmpty);
      expect(
        serviceLine(exportB),
        isNot(serviceLine(exportA)),
        reason: 'card B must describe card B\'s service',
      );
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  // =========================================================================
  // Test 2 — PARTIAL FAILURE (re-authors the removed
  // client_booking_conflict_flow_test.dart against the NEW contract): the 2nd
  // service's first `POST /bookings` 409s with CLIENT_BOOKING_CONFLICT → the
  // confirm screen STAYS, that appointment shows a per-appointment error row +
  // a partial-failure SnackBar (never the retired conflict DIALOG), and a
  // retry re-sends ONLY the failed service with its SAME stable key (the
  // already-succeeded service is never re-POSTed).
  // =========================================================================
  testWidgets(
    'CLIENT submits two services, the second 409s with CLIENT_BOOKING_CONFLICT '
    '→ the confirm screen stays with a per-appointment error row + '
    'partial-failure SnackBar → retry re-sends ONLY the failed service (same '
    'stable key) and reaches success',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      // These are the ALREADY-EXISTING clashing booking's instants inside a 409
      // payload, not a fixture that must read as "upcoming". They reach only
      // `ClientBookingConflictFailure.userMessage` → `formatBookingWindow`,
      // which is a pure absolute formatter with no `now()` in it, and no
      // assertion in this flow reads the rendered date. A fixed instant is
      // therefore strictly more deterministic here.
      final ClientBookingConflictFailure conflict =
          ClientBookingConflictFailure(
            conflictingBookingId: 'other-booking-1',
            serviceName: 'Педикюр апаратний',
            masterName: 'Ірина Шевченко',
            // future-date-ok: clashing booking's own window, see note above.
            startsAt: DateTime.utc(2026, 7, 16, 14),
            // future-date-ok: clashing booking's own window, see note above.
            endsAt: DateTime.utc(2026, 7, 16, 15, 30),
          );
      // Only service B's FIRST call fails; service A always succeeds.
      final repo = _FakeBookingRepository(
        failOnceWith: <String, Failure>{serviceB: conflict},
      );
      final GoRouter router = await AppHarness.boot(
        tester,
        fb,
        extraOverrides: <Object>[
          bookingRepositoryProvider.overrideWithValue(repo),
        ],
      );

      await AppHarness.loginAs(tester, fb, UserRole.client);
      await AppHarness.settle(tester);

      unawaited(
        router.push(
          RouteNames.bookingConfirm,
          extra: twoServiceArgs(keyA: 'itest-pf-key-A', keyB: 'itest-pf-key-B'),
        ),
      );
      await AppHarness.settle(tester);

      expectLocation(router, RouteNames.bookingConfirm);
      expect(find.byType(BookingConfirmScreen), findsOneWidget);

      // ── First submit → service A succeeds, service B 409s ────────────────
      await tester.tap(find.byKey(const Key('booking-confirm-submit-cta')));
      await AppHarness.settle(tester);

      // STAYS on the confirm screen — no navigation, no crash, no dialog.
      expectLocation(router, RouteNames.bookingConfirm);
      expect(find.byType(BookingConfirmScreen), findsOneWidget);
      expect(find.byType(BookingSuccessScreen), findsNothing);
      // The retired conflict dialog must NEVER appear (this is the exact
      // regression the removed stale test would have kept asserting).
      expect(
        find.byKey(const Key('client-booking-conflict-dialog')),
        findsNothing,
      );

      // The FAILED service (B) shows its own per-appointment error row; the
      // succeeded service (A) does not.
      expect(
        find.byKey(const Key('booking-confirm-appt-error-$serviceB')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('booking-confirm-appt-error-$serviceA')),
        findsNothing,
      );

      final l10n = AppLocalizations.of(
        tester.element(find.byType(BookingConfirmScreen)),
      );
      // The partial-failure nudge SnackBar (asserted via l10n key, not a raw
      // literal — locale-invariant).
      expect(find.text(l10n.salonBookingPartialFailureMessage), findsOneWidget);
      // The CTA flipped «Записатись» → «Повторити».
      expect(find.text(l10n.salonBookingRetryCta), findsOneWidget);

      // Each service was attempted exactly once so far.
      expect(repo.callsFor(serviceA), 1);
      expect(repo.callsFor(serviceB), 1);

      // ── Retry → service B now succeeds (fail-once consumed) → success ─────
      await tester.tap(find.byKey(const Key('booking-confirm-submit-cta')));
      await AppHarness.settle(tester);

      expectLocation(router, RouteNames.bookingSuccess);
      expect(find.byType(BookingSuccessScreen), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Service A booked ONCE (never re-sent); service B booked twice (fail +
      // retry), BOTH reusing its SAME stable idempotency key so the
      // ambiguously-failed first attempt de-duplicates server-side.
      expect(
        repo.callsFor(serviceA),
        1,
        reason:
            'the already-succeeded service must never be re-POSTed on retry',
      );
      expect(repo.callsFor(serviceB), 2);
      final List<CreateBookingRequest> bReqs = repo.requestsFor(serviceB);
      expect(bReqs[0].idempotencyKey, 'itest-pf-key-B');
      expect(
        bReqs[1].idempotencyKey,
        equals(bReqs[0].idempotencyKey),
        reason:
            'the retried submit must REUSE the failed appointment\'s stable '
            'key, never mint a fresh one',
      );
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  // =========================================================================
  // Test 3 — TIME-STEP SHELF (mobile-qa Rule 3b, "selected services" shelf
  // addition): the independent `BookingTimeScreen` now pins the SAME
  // expandable "Послуги та ціни" shelf the salon flow carries, PLUS a
  // per-service chosen-window line. Tests 1–2 deliberately enter PAST this
  // screen (at `/booking/confirm`), so the shelf on the time step was
  // otherwise unexercised end to end. This variant enters AT the time step
  // (real `BookingTimeScreen`, real `slotRepositoryProvider` over the fake
  // backend's `GET /masters/master-aaa/working-days` + `/slots` routes) and
  // proves: (a) the shelf is present and lists both selected services before
  // any pick with NO chosen-window line; (b) after picking service A's slot,
  // that service's chosen-window line (the camel `event_available_rounded`
  // beat) appears in the shelf while the still-unscheduled sibling shows none.
  // =========================================================================
  testWidgets(
    'CLIENT on the time step sees the pinned selected-services shelf; a '
    'service\'s chosen-window line appears in the shelf only after its slot '
    'is picked',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      final GoRouter router = await AppHarness.boot(tester, fb);

      await AppHarness.loginAs(tester, fb, UserRole.client);
      await AppHarness.settle(tester);

      // Enter AT the time step with the two-service selection (mirrors the
      // push `ServiceSelectorSheet` makes into `/booking/slots/time`).
      unawaited(
        router.push(
          RouteNames.bookingSlotsTime,
          extra: const BookingSlotPickerArgs(
            masterId: masterId,
            master: masterDisplay,
            services: <MasterService>[svcADisplay, svcBDisplay],
          ),
        ),
      );
      await AppHarness.settle(tester);

      expectLocation(router, RouteNames.bookingSlotsTime);
      expect(find.byType(BookingTimeScreen), findsOneWidget);

      // Scopes a finder to ONE service's slide (both are kept-alive-mounted by
      // the pager's current±1 bound, so the shared calendar/slot keys would
      // otherwise be ambiguous). Mirrors `booking_time_screen_test.dart`.
      Finder inSlide(String serviceId, Finder matching) => find.descendant(
        of: find.byKey(
          Key('service-schedule-page-$serviceId'),
          skipOffstage: false,
        ),
        matching: matching,
        skipOffstage: false,
      );

      final Finder shelfList = find.byKey(
        const Key('booking-summary-expanded-list'),
      );

      // ── Before any pick: expand the shelf → both services listed, NO
      // chosen-window line yet ─────────────────────────────────────────────
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
      expect(
        find.descendant(
          of: shelfList,
          matching: find.byIcon(Icons.event_available_rounded),
        ),
        findsNothing,
        reason:
            'no service is scheduled yet, so no chosen-window line may render',
      );

      // Collapse before driving the calendar/slot taps (the shelf toggle and
      // the slide keys are independent, but there is no reason to leave the
      // itemized list mounted over the taps).
      await tester.tap(find.byKey(const Key('booking-summary-expand-toggle')));
      await AppHarness.settle(tester);

      // ── Pick service A's date + its 10:00 slot over the REAL working-days /
      // slots endpoints. The slot chip key mirrors the salon flow's own
      // local-iso convention (`booking_time_screen_test.dart`). ────────────
      final DateTime today = DateTime.now();
      final String morningIso = DateTime(
        today.year,
        today.month,
        today.day,
        10,
      ).toIso8601String();

      await tester.tap(
        inSlide(serviceA, find.byKey(Key('booking-calendar-day-${today.day}'))),
      );
      await AppHarness.settle(tester);

      final Finder morningSlotA = inSlide(
        serviceA,
        find.byKey(Key('independent-slot-chip-$morningIso')),
      );
      expect(morningSlotA, findsOneWidget);
      await tester.tap(morningSlotA);
      // Drains service A's post-slot auto-advance onto service B's slide.
      await AppHarness.settle(tester);

      // ── After the pick: expand the shelf → service A now carries its
      // chosen-window line; the still-unscheduled service B does not ────────
      await tester.tap(find.byKey(const Key('booking-summary-expand-toggle')));
      await AppHarness.settle(tester);
      expect(shelfList, findsOneWidget);
      expect(
        find.descendant(
          of: shelfList,
          matching: find.byIcon(Icons.event_available_rounded),
        ),
        findsOneWidget,
        reason:
            'exactly one service (A) is scheduled → exactly one chosen-window '
            'line updates into the shelf',
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>(serviceA)),
          matching: find.byIcon(Icons.event_available_rounded),
        ),
        findsOneWidget,
        reason: 'the chosen-window line sits inside service A\'s own row',
      );
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );
}
