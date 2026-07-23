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
//     screen STAYS with ONE inline error banner (never the retired conflict
//     DIALOG), and a retry REUSES the same idempotency key and reaches success.
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
import 'package:beautica_mobile/features/booking/presentation/slot_picker_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/calendar_button.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/slot_chip.dart';
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

/// The `add_2_calendar` plugin's platform boundary — intercepted so the visit
/// export never launches a real OS calendar activity on the emulator.
const MethodChannel _kCalendarChannel = MethodChannel('add_2_calendar');

/// Records every `createAppointment` call and, on the FIRST call only, throws
/// [failOnceWith] if set (then clears it, so a retry succeeds) — mirrors the
/// "fail once, then succeed on retry" shape, keyed by the single visit call.
class _FakeAppointmentRepository implements AppointmentRepository {
  _FakeAppointmentRepository({this.failOnceWith});

  Failure? failOnceWith;
  final List<CreateAppointmentRequest> requests = <CreateAppointmentRequest>[];

  @override
  Future<Appointment> createAppointment(CreateAppointmentRequest req) async {
    requests.add(req);
    final Failure? typed = failOnceWith;
    if (typed != null) {
      failOnceWith = null;
      throw typed;
    }
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
      canReview: false,
    );
  }

  @override
  Future<Appointment> getAppointment(String id) => throw UnimplementedError();

  @override
  Future<void> cancelAppointment(String id, {String? note}) =>
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

  // The seeded `master-aaa` fixture's two PUBLIC service ids.
  const String masterId = 'master-aaa';
  const String serviceA = 'pub-assign-1';
  const String serviceB = 'pub-assign-2';

  // ONE start time for the whole visit.
  final DateTime visitStart = DateTime.now().add(
    const Duration(days: 1, hours: 10),
  );

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
  // Test 2 — the single submit 409s with CLIENT_BOOKING_CONFLICT → ONE inline
  // error banner (never the retired conflict DIALOG), confirm screen STAYS,
  // retry REUSES the same idempotency key and reaches success.
  // =========================================================================
  testWidgets(
    'CLIENT submits a visit, the create 409s with CLIENT_BOOKING_CONFLICT → the '
    'confirm screen stays with ONE inline error banner → retry reuses the same '
    'idempotency key and reaches success',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      final ClientBookingConflictFailure conflict =
          ClientBookingConflictFailure(
            conflictingBookingId: 'other-booking-1',
            serviceName: 'Педикюр апаратний',
            masterName: 'Ірина Шевченко',
            // future-date-ok: clashing booking's own window (pure absolute
            // formatter, never asserted for freshness).
            startsAt: DateTime.utc(2026, 7, 16, 14),
            // future-date-ok: clashing booking's own window.
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

      // STAYS on the confirm screen — no navigation, no crash, no dialog.
      AppHarness.expectShellLocation(router, RouteNames.bookingConfirm);
      expect(find.byType(BookingConfirmScreen), findsOneWidget);
      expect(find.byType(BookingSuccessScreen), findsNothing);
      // The retired conflict dialog must NEVER appear.
      expect(
        find.byKey(const Key('client-booking-conflict-dialog')),
        findsNothing,
      );
      // ONE inline error banner, naming the conflict.
      expect(
        find.byKey(const Key('booking-confirm-submit-error')),
        findsOneWidget,
      );

      expect(repo.requests, hasLength(1));

      // ── Retry → now succeeds (fail-once consumed) → success ─────────────
      await tester.tap(find.byKey(const Key('booking-confirm-submit-cta')));
      await AppHarness.settle(tester);

      AppHarness.expectShellLocation(router, RouteNames.bookingSuccess);
      expect(find.byType(BookingSuccessScreen), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Two submits, both reusing the SAME stable idempotency key so the
      // ambiguously-failed first attempt de-duplicates server-side.
      expect(repo.requests, hasLength(2));
      expect(repo.requests[0].idempotencyKey, 'itest-pf-key');
      expect(
        repo.requests[1].idempotencyKey,
        equals(repo.requests[0].idempotencyKey),
        reason: 'the retry must REUSE the same key, never mint a fresh one',
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
      final DateTime today = DateTime.now();
      await tester.tap(find.byKey(Key('booking-calendar-day-${today.day}')));
      await AppHarness.settle(tester);
      await tester.tap(find.byKey(const Key('booking-summary-cta')));
      await AppHarness.settle(tester);

      AppHarness.expectShellLocation(router, RouteNames.bookingSlotsTime);
      expect(find.byType(SlotTimeScreen), findsOneWidget);

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
}
