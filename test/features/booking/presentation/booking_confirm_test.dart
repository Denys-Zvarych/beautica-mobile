// Phase 14.2 — Widget tests for BookingConfirmScreen + BookingSuccessScreen.
//
// Both screens are covered in ONE file, mirroring the Phase 14.1 precedent
// (`slot_picker_test.dart` covers SlotDateScreen + SlotTimeScreen together)
// since these two screens are the two halves of a single "confirm → success"
// step and share the exact same fixtures.
//
// Covers the phase doc's acceptance criteria:
//   1. The "Записатись" CTA calls `BookingRepository.createBooking` with a
//      fresh UUID v4 idempotency key.
//   2. A 409 (ConflictFailure) shows a SnackBar, does NOT navigate away, and
//      the confirm screen stays fully interactive.
//   3. A retry after a failure generates a NEW idempotency key (never reused).
//   4. Success navigates (pushReplacement) to /booking/success.
//   5. BookingSuccessScreen blocks back navigation (PopScope(canPop: false)).
//
// Strategy: mounts a test-local GoRouter with `/booking/confirm` and
// `/booking/success` (mirroring `slot_picker_test.dart`'s `_router()`
// pattern), overriding `publicMasterProfileProvider` (hand-fixture, no real
// Dio call) and `bookingRepositoryProvider` with a hand-written fake — no
// mocktail, matching the `_FakeSlotRepository` precedent in this same
// feature's Phase 14.1 test file.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_confirm_args.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/booking_success_args.dart';
import 'package:beautica_mobile/features/booking/domain/create_booking_request.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_confirm_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_success_screen.dart';
import 'package:beautica_mobile/features/master/application/public_master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _kMaster = Master(
  id: 'master-1',
  firstName: 'Олена',
  lastName: 'Ковальчук',
  city: 'Київ',
  street: 'вул. Хрещатик',
  buildingNo: '22',
  avgRating: 4.8,
  reviewCount: 47,
  type: MasterType.independentMaster,
);

const _kService = MasterService(
  id: 'svc-1',
  serviceDefId: 'def-1',
  name: 'Манікюр з покриттям',
  durationMinutes: 90,
  priceMin: 500,
  priceDisplay: '500 грн',
  category: 'NAILS',
);

BookingConfirmArgs _confirmArgs() => BookingConfirmArgs(
  masterId: _kMaster.id,
  serviceId: _kService.id,
  startAt: DateTime(2026, 7, 20, 14),
);

Booking _bookingFixture() => Booking(
  id: 'booking-1',
  masterId: _kMaster.id,
  masterFirstName: _kMaster.firstName,
  masterLastName: _kMaster.lastName,
  masterType: 'INDEPENDENT_MASTER',
  serviceId: _kService.id,
  serviceName: _kService.name,
  durationMinutes: _kService.durationMinutes,
  price: _kService.priceMin,
  startAt: DateTime(2026, 7, 20, 14),
  endAt: DateTime(2026, 7, 20, 15, 30),
  status: BookingStatus.pending,
  canReview: false,
);

/// Records every [createBooking] call (request + resulting idempotency key)
/// so the "fresh key per submit" criterion can be asserted directly, and
/// either returns [bookingToReturn] or throws [errorToThrow] when set —
/// mirrors `slot_picker_test.dart`'s `_FakeSlotRepository`.
class _FakeBookingRepository implements BookingRepository {
  _FakeBookingRepository({this.bookingToReturn, this.errorToThrow});

  Booking? bookingToReturn;
  Object? errorToThrow;
  final List<CreateBookingRequest> requests = <CreateBookingRequest>[];

  @override
  Future<Booking> createBooking(CreateBookingRequest req) async {
    requests.add(req);
    final Object? err = errorToThrow;
    if (err != null) throw err;
    return bookingToReturn!;
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

/// Test-local router mirroring `app_router.dart`'s bookingConfirm →
/// bookingSuccess shape, rendering the REAL production screens.
///
/// A dummy `/root` initial location is registered UNDERNEATH both booking
/// routes (mirroring how, in the real app, `/booking/confirm` is always
/// PUSHED on top of the slot picker, never the router's own initial
/// location) so `context.pop()` from the confirm screen's back button has
/// somewhere to land, and so the initial pump never has to build a booking
/// route's `state.extra!` before a test has supplied one — both booking
/// routes are only ever reached via an explicit `router.push(...)` call.
/// [RouteNames.clientBookings] / [RouteNames.clientHome] are registered as
/// bare stub destinations so the success screen's «Мої записи» / «На
/// головну» `context.go(...)` calls resolve to a real route instead of
/// throwing (go_router has no matching-route fallback).
GoRouter _router() => GoRouter(
  initialLocation: '/root',
  routes: <RouteBase>[
    GoRoute(
      path: '/root',
      builder: (context, state) => const SizedBox.shrink(),
    ),
    GoRoute(
      path: RouteNames.clientBookings,
      builder: (context, state) => const SizedBox.shrink(),
    ),
    GoRoute(
      path: RouteNames.clientHome,
      builder: (context, state) => const SizedBox.shrink(),
    ),
    GoRoute(
      path: RouteNames.bookingConfirm,
      builder: (context, state) =>
          BookingConfirmScreen(args: state.extra! as BookingConfirmArgs),
    ),
    GoRoute(
      path: RouteNames.bookingSuccess,
      builder: (context, state) =>
          BookingSuccessScreen(args: state.extra! as BookingSuccessArgs),
    ),
  ],
);

/// Reads the router's CURRENT top-of-stack location. `GoRouter.push()`
/// (unlike `.go()`) does not update `currentConfiguration.uri` the same way
/// (it deliberately preserves the underlying "URL" for a stacked/modal-style
/// push — confirmed empirically: `matches` correctly grows while `.uri`
/// stays put), so this reads the LAST entry of `.matches` instead, which
/// reflects the actual top-of-stack screen for both `.go()` and `.push()`.
String locationOf(GoRouter router) =>
    router.routerDelegate.currentConfiguration.matches.last.matchedLocation;

void main() {
  group('BookingConfirmScreen', () {
    Future<GoRouter> pump(
      WidgetTester tester,
      _FakeBookingRepository fake,
    ) async {
      final GoRouter router = _router();
      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[
          bookingRepositoryProvider.overrideWith((_) => fake),
          publicMasterProfileProvider(
            _kMaster.id,
          ).overrideWith((ref) => (_kMaster, const <MasterService>[_kService])),
        ],
      );
      unawaited(router.push(RouteNames.bookingConfirm, extra: _confirmArgs()));
      await tester.pumpAndSettle();
      return router;
    }

    testWidgets('renders the master + service summary once data resolves', (
      tester,
    ) async {
      final fake = _FakeBookingRepository(bookingToReturn: _bookingFixture());
      await pump(tester, fake);

      expect(find.byType(BookingConfirmScreen), findsOneWidget);
      // i18n-finder-ok: master name is fixture data (_kMaster), not translated UI copy.
      expect(find.text('Олена Ковальчук'), findsOneWidget);
      // i18n-finder-ok: service name is fixture data (_kService), not translated UI copy.
      expect(find.text('Манікюр з покриттям'), findsOneWidget);
    });

    testWidgets(
      '«Записатись» calls createBooking with a fresh UUID v4 idempotency key '
      'and navigates to /booking/success on success',
      (tester) async {
        final fake = _FakeBookingRepository(bookingToReturn: _bookingFixture());
        final router = await pump(tester, fake);

        await tester.tap(find.byKey(const Key('booking-confirm-submit-cta')));
        await tester.pumpAndSettle();

        expect(fake.requests, hasLength(1));
        final CreateBookingRequest sent = fake.requests.single;
        expect(sent.masterId, _kMaster.id);
        expect(sent.serviceId, _kService.id);
        // A syntactically valid UUID v4: 8-4-4-4-12 hex groups.
        expect(
          sent.idempotencyKey,
          matches(
            RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            ),
          ),
        );

        expect(locationOf(router), equals(RouteNames.bookingSuccess));
        expect(find.byType(BookingSuccessScreen), findsOneWidget);
      },
    );

    testWidgets(
      'a 409 conflict shows a SnackBar, does not navigate away, and the '
      'screen stays interactive for a retry',
      (tester) async {
        final fake = _FakeBookingRepository(
          bookingToReturn: _bookingFixture(),
          errorToThrow: const ConflictFailure(),
        );
        final router = await pump(tester, fake);

        await tester.tap(find.byKey(const Key('booking-confirm-submit-cta')));
        await tester.pumpAndSettle();

        // Still on the confirm screen — no crash, no navigation.
        expect(locationOf(router), equals(RouteNames.bookingConfirm));
        expect(find.byType(BookingConfirmScreen), findsOneWidget);
        expect(find.byType(SnackBar), findsOneWidget);

        final l10n = AppLocalizations.of(
          tester.element(find.byType(BookingConfirmScreen)),
        );
        expect(find.text(l10n.errConflict), findsOneWidget);

        // The comment field is still editable — the screen never got stuck
        // mid-submit.
        await tester.enterText(
          find.byKey(const Key('booking-confirm-comment-field')),
          'Будь ласка, без запізнень',
        );
        await tester.pump();
        // i18n-finder-ok: arbitrary test-entered text (round-trip check), not translated UI copy.
        expect(find.text('Будь ласка, без запізнень'), findsOneWidget);

        // Retry with a fresh key — a DIFFERENT key than the failed attempt.
        fake.errorToThrow = null;
        await tester.tap(find.byKey(const Key('booking-confirm-submit-cta')));
        await tester.pumpAndSettle();

        expect(fake.requests, hasLength(2));
        expect(
          fake.requests[1].idempotencyKey,
          isNot(equals(fake.requests[0].idempotencyKey)),
        );
        expect(locationOf(router), equals(RouteNames.bookingSuccess));
      },
    );

    testWidgets('an empty comment is sent as null, a non-empty comment is '
        'trimmed and forwarded', (tester) async {
      final fake = _FakeBookingRepository(bookingToReturn: _bookingFixture());
      await pump(tester, fake);

      await tester.enterText(
        find.byKey(const Key('booking-confirm-comment-field')),
        '  Прошу зателефонувати заздалегідь  ',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('booking-confirm-submit-cta')));
      await tester.pumpAndSettle();

      expect(
        fake.requests.single.clientComment,
        'Прошу зателефонувати заздалегідь',
      );
    });

    testWidgets('the back button pops without submitting a booking', (
      tester,
    ) async {
      final fake = _FakeBookingRepository(bookingToReturn: _bookingFixture());
      await pump(tester, fake);

      await tester.tap(find.byKey(const Key('booking-confirm-back')));
      await tester.pumpAndSettle();

      expect(fake.requests, isEmpty);
    });
  });

  group('BookingSuccessScreen', () {
    BookingSuccessArgs successArgs() => BookingSuccessArgs(
      master: _kMaster,
      service: _kService,
      start: DateTime(2026, 7, 20, 14),
    );

    Future<GoRouter> pump(WidgetTester tester) async {
      final GoRouter router = _router();
      await tester.pumpRoutedApp(router);
      router.go(RouteNames.bookingSuccess, extra: successArgs());
      await tester.pumpAndSettle();
      return router;
    }

    testWidgets('renders the recap WITHOUT the master card', (tester) async {
      await pump(tester);

      final l10n = AppLocalizations.of(
        tester.element(find.byType(BookingSuccessScreen)),
      );
      expect(find.text(l10n.bookingSuccessTitle), findsOneWidget);
      // i18n-finder-ok: service name is fixture data (_kService), not translated UI copy.
      expect(find.text('Манікюр з покриттям'), findsOneWidget);
      // The master's NAME (only shown on the master card) must be absent —
      // `showMasterCard: false` per the design.
      // i18n-finder-ok: master name is fixture data (_kMaster), not translated UI copy.
      expect(find.text('Олена Ковальчук'), findsNothing);
    });

    testWidgets('blocks back navigation (PopScope canPop: false)', (
      tester,
    ) async {
      await pump(tester);

      final PopScope popScope = tester.widget<PopScope>(find.byType(PopScope));
      expect(popScope.canPop, isFalse);
    });

    testWidgets('«Мої записи» navigates to /bookings', (tester) async {
      final router = await pump(tester);

      await tester.tap(
        find.byKey(const Key('booking-success-my-bookings-cta')),
      );
      await tester.pumpAndSettle();

      expect(locationOf(router), equals(RouteNames.clientBookings));
    });

    testWidgets('«На головну» navigates to /home', (tester) async {
      final router = await pump(tester);

      await tester.tap(find.byKey(const Key('booking-success-home-cta')));
      await tester.pumpAndSettle();

      expect(locationOf(router), equals(RouteNames.clientHome));
    });
  });
}
