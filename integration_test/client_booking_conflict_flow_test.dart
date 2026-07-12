// mobile-qa gap-fix — Step 2.7 Rule 3b E2E coverage for the CLIENT
// booking-conflict feature (backend commit f95d8fd).
//
// WHY THIS FILE EXISTS
// --------------------
// The widget tier (`test/features/booking/presentation/booking_confirm_test.dart`,
// `test/features/booking/presentation/widgets/client_booking_conflict_dialog_test.dart`)
// proves the dialog and the confirm screen's catch-branch in isolation, with
// every provider hand-stubbed. Neither proves the REAL user journey end to
// end: a CLIENT logging in against the fake backend, landing on the real
// `BookingConfirmScreen` (its `publicMasterProfileProvider` resolved through
// the REAL fake-backed master repository, not a stubbed fixture tuple),
// submitting, hitting a 409 `CLIENT_BOOKING_CONFLICT`, the dialog naming the
// clashing booking, dismissing it, and confirming the in-progress
// selection/comment survived untouched — then that the client can still
// complete the booking from that exact same screen state.
//
// `bookingRepositoryProvider` is overridden with a hand-written fake (never
// a `POST /bookings` route on `FakeBackend`'s `DioAdapter`) — mirrors the
// established precedent in `salon_booking_flow_test.dart`'s
// `_FakeBookingRepository` (its file header explains why: it avoids the
// generated booking client's real-Dio timer leak while still exercising the
// REAL `BookingConfirmNotifier` + screen + dialog + router end to end).
//
// No native surface is involved (no OS permission dialog, no deep link, no
// FCM/local notification, no WebView, no biometric) — this is pure
// Dart/Riverpod state driving a pure Flutter widget tree, so no companion
// Patrol test is added alongside this one.
//
// The SALON-flow companion of this same feature ("a conflict on ONE master
// surfaces on that master's card only and does not fail the whole batch")
// lives in `salon_booking_flow_test.dart`'s
// "CLIENT_BOOKING_CONFLICT on one master" test, mirroring its existing
// partial-failure/retry test for the generic ConflictFailure case.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_confirm_args.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/create_booking_request.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_confirm_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_success_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

/// Records every `createBooking` call and, for the FIRST call only, throws
/// [firstError] (when set) — every subsequent call succeeds. Mirrors
/// `salon_booking_flow_test.dart`'s `_FakeBookingRepository` "fail once,
/// then succeed on retry" shape, adapted to the single-appointment
/// independent-master flow (`BookingConfirmNotifier` makes exactly one
/// `createBooking` call per submit tap, unlike the salon N-per-master submit).
class _FakeBookingRepository implements BookingRepository {
  _FakeBookingRepository({this.firstError});

  Object? firstError;
  final List<CreateBookingRequest> requests = <CreateBookingRequest>[];

  @override
  Future<Booking> createBooking(CreateBookingRequest req) async {
    requests.add(req);
    final Object? err = firstError;
    if (err != null && requests.length == 1) {
      firstError = null;
      throw err;
    }
    return Booking(
      id: 'booking-1',
      masterId: req.masterId,
      masterFirstName: 'Софія',
      masterLastName: 'Бондар',
      masterType: 'INDEPENDENT_MASTER',
      serviceId: req.serviceId,
      serviceName: 'Манікюр',
      durationMinutes: 60,
      price: 500,
      startAt: req.startAt,
      endAt: req.startAt.add(const Duration(minutes: 60)),
      status: BookingStatus.pending,
      canReview: false,
    );
  }

  @override
  Future<PageResponse<Booking>> getMyBookings({
    required BookingStatus? status,
    required int page,
    int size = kBookingsPageSize,
  }) => throw UnimplementedError();

  @override
  Future<Booking> getBookingById(String id) => throw UnimplementedError();

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

  // The seeded `master-aaa` fixture's own public service id
  // (`FakeBackend`'s "PUBLIC active-services list for `master-aaa`" block —
  // the SAME service `public_master_profile_flow_test.dart` selects).
  const String masterId = 'master-aaa';
  const String serviceId = 'pub-assign-1';

  testWidgets('CLIENT picks a slot and submits → backend 409s with '
      'CLIENT_BOOKING_CONFLICT → the dialog names the clashing booking → '
      'dismissing it leaves the selection intact → the client picks another '
      'time (retries) and the booking succeeds', (tester) async {
    final fb = FakeBackend()..currentRole = UserRole.client;
    final DateTime clashStart = DateTime.utc(2026, 7, 15, 14);
    final DateTime clashEnd = DateTime.utc(2026, 7, 15, 15, 30);
    final ClientBookingConflictFailure conflict = ClientBookingConflictFailure(
      conflictingBookingId: 'other-booking-1',
      serviceName: 'Педикюр апаратний',
      masterName: 'Ірина Шевченко',
      startsAt: clashStart,
      endsAt: clashEnd,
    );
    final repo = _FakeBookingRepository(firstError: conflict);

    final GoRouter router = await AppHarness.boot(
      tester,
      fb,
      extraOverrides: <Object>[
        bookingRepositoryProvider.overrideWithValue(repo),
      ],
    );

    await AppHarness.loginAs(tester, fb, UserRole.client);
    await AppHarness.settle(tester);

    // "The user picks a slot" — a real BookingConfirmArgs pushed through
    // the real clientOnlyGuard, landing on the REAL BookingConfirmScreen
    // with its `publicMasterProfileProvider(masterId)` resolved through
    // the fake backend's genuine `GET /masters/{id}` +
    // `GET /masters/{id}/services` routes (never a stubbed fixture tuple).
    unawaited(
      router.push(
        RouteNames.bookingConfirm,
        extra: BookingConfirmArgs(
          masterId: masterId,
          serviceId: serviceId,
          startAt: DateTime.now().add(const Duration(days: 1)),
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

    // Fill in a comment — this is the "selection" that must survive the
    // conflict round trip intact.
    await tester.enterText(
      find.byKey(const Key('booking-confirm-comment-field')),
      'Прошу зателефонувати заздалегідь',
    );
    await tester.pump();

    // "Submits" — the real CTA, real notifier, real fake-backed repository.
    await tester.tap(find.byKey(const Key('booking-confirm-submit-cta')));
    await AppHarness.settle(tester);

    // "backend 409s with CLIENT_BOOKING_CONFLICT → the dialog appears
    // naming the clashing booking"
    expect(
      find.byKey(const Key('client-booking-conflict-dialog')),
      findsOneWidget,
    );
    // i18n-finder-ok: service/master names are fixture data on the
    // Failure object, not translated UI copy.
    expect(find.text('Педикюр апаратний'), findsOneWidget);
    expect(find.text('Ірина Шевченко'), findsOneWidget);
    expect(
      find.text(formatBookingWindow(clashStart, clashEnd)),
      findsOneWidget,
    );
    expectLocation(router, RouteNames.bookingConfirm);

    // "user dismisses" via "Залишитись тут".
    await tester.tap(find.byKey(const Key('client-booking-conflict-stay')));
    await AppHarness.settle(tester);

    expect(
      find.byKey(const Key('client-booking-conflict-dialog')),
      findsNothing,
    );
    // "their selection is still intact" — still on the confirm screen,
    // comment untouched.
    expectLocation(router, RouteNames.bookingConfirm);
    expect(find.byType(BookingConfirmScreen), findsOneWidget);
    // i18n-finder-ok: arbitrary test-entered text (round-trip check).
    expect(find.text('Прошу зателефонувати заздалегідь'), findsOneWidget);

    // "and they can pick another time" — retrying from the exact same
    // screen state now succeeds (the fake's fail-once is consumed).
    await tester.tap(find.byKey(const Key('booking-confirm-submit-cta')));
    await AppHarness.settle(tester);

    expectLocation(router, RouteNames.bookingSuccess);
    expect(find.byType(BookingSuccessScreen), findsOneWidget);
    expect(repo.requests, hasLength(2));
    expect(
      repo.requests[1].idempotencyKey,
      isNot(equals(repo.requests[0].idempotencyKey)),
      reason: 'the retried submit must mint a FRESH idempotency key',
    );
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 120)));

  testWidgets(
    'tapping «Обрати інший час» in the conflict dialog pops the CLIENT back '
    'to slot selection instead of leaving them stuck on the confirm screen',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      final ClientBookingConflictFailure conflict =
          ClientBookingConflictFailure(
            conflictingBookingId: 'other-booking-1',
            serviceName: 'Педикюр апаратний',
            masterName: 'Ірина Шевченко',
            startsAt: DateTime.utc(2026, 7, 15, 14),
            endsAt: DateTime.utc(2026, 7, 15, 15, 30),
          );
      final repo = _FakeBookingRepository(firstError: conflict);

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
          extra: BookingConfirmArgs(
            masterId: masterId,
            serviceId: serviceId,
            startAt: DateTime.now().add(const Duration(days: 1)),
          ),
        ),
      );
      await AppHarness.settle(tester);
      expectLocation(router, RouteNames.bookingConfirm);

      await tester.tap(find.byKey(const Key('booking-confirm-submit-cta')));
      await AppHarness.settle(tester);
      expect(
        find.byKey(const Key('client-booking-conflict-dialog')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('client-booking-conflict-pick-another-time')),
      );
      await AppHarness.settle(tester);

      expect(
        find.byKey(const Key('client-booking-conflict-dialog')),
        findsNothing,
      );
      expect(
        find.byType(BookingConfirmScreen),
        findsNothing,
        reason:
            '«Обрати інший час» must pop the confirm screen back to slot '
            'selection, not leave the client stuck on it',
      );
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );
}
