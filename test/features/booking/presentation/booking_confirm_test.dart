// MO-3 — Widget tests for BookingConfirmScreen + BookingSuccessScreen
// (single-visit rework).
//
// Both screens are covered in ONE file (the two halves of a single "confirm →
// success" step share the exact same fixtures). Covers the MO-3 acceptance
// criteria:
//   1. The "Записатись" CTA submits ONE `POST /appointments`
//      (`AppointmentRepository.createAppointment`) with the whole ordered
//      service selection + a single stable idempotency key.
//   2. A single 409 failure shows ONE inline error banner, does NOT navigate
//      away, and the confirm screen stays fully interactive.
//   3. A retry after a failure REUSES the same stable idempotency key (never a
//      fresh one — de-dupes an ambiguously-failed create).
//   4. Success navigates (pushReplacement) to /booking/success.
//   5. BookingSuccessScreen blocks back navigation (PopScope(canPop: false)).
//
// Strategy: mounts a test-local GoRouter with `/booking/confirm` and
// `/booking/success`, overriding `publicMasterProfileProvider` (hand-fixture)
// and `appointmentRepositoryProvider` (create path) / `bookingRepositoryProvider`
// (reschedule path) with hand-written fakes — no mocktail.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/booking_detail_notifier.dart';
import 'package:beautica_mobile/features/booking/application/bookings_day_notifier.dart';
import 'package:beautica_mobile/features/booking/application/my_bookings_notifier.dart';
import 'package:beautica_mobile/features/booking/data/appointment_repository.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/data/slot_repository.dart';
import 'package:beautica_mobile/features/booking/domain/appointment.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_confirm_args.dart';
import 'package:beautica_mobile/features/booking/domain/booking_partition.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot_picker_args.dart';
import 'package:beautica_mobile/features/booking/domain/bookings_day_query.dart';
import 'package:beautica_mobile/features/booking/domain/bookings_day_state.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/booking_success_args.dart';
import 'package:beautica_mobile/features/booking/domain/booking_tab.dart';
import 'package:beautica_mobile/features/booking/domain/create_appointment_request.dart';
import 'package:beautica_mobile/features/booking/domain/create_booking_request.dart';
import 'package:beautica_mobile/features/booking/domain/working_day.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_confirm_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_success_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/slot_picker_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_summary_cards.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_strip.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/slot_chip.dart';
import 'package:beautica_mobile/features/home/application/home_hub_notifier.dart';
import 'package:beautica_mobile/features/master/application/public_master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';

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
  priceDisplay: '500 ₴',
  category: 'NAILS',
);

const _kService2 = MasterService(
  id: 'svc-2',
  serviceDefId: 'def-2',
  name: 'Педикюр',
  durationMinutes: 60,
  priceMin: 400,
  priceDisplay: '400 ₴',
  category: 'NAILS',
);

// A STABLE idempotency key generated once when the args were built (in
// production by `SlotTimeScreen._confirm`) — reused verbatim on every retry so
// an ambiguously-failed visit create de-duplicates rather than duplicates.
const String _kIdemKey = '11111111-1111-4111-8111-111111111111';

BookingConfirmArgs _confirmArgs({
  List<MasterService> services = const <MasterService>[_kService],
}) => BookingConfirmArgs(
  masterId: _kMaster.id,
  master: _kMaster,
  services: services,
  startAt: DateTime(2026, 7, 20, 14),
  idempotencyKey: _kIdemKey,
);

Appointment _appointmentFixture() => Appointment(
  id: 'appt-1',
  status: BookingStatus.confirmed,
  masterId: _kMaster.id,
  masterFirstName: _kMaster.firstName,
  masterLastName: _kMaster.lastName,
  masterType: 'INDEPENDENT_MASTER',
  startAt: DateTime(2026, 7, 20, 14),
  endAt: DateTime(2026, 7, 20, 15, 30),
  totalDurationMinutes: 90,
  totalPrice: 500,
  items: <AppointmentItem>[
    AppointmentItem(
      bookingId: 'booking-1',
      masterServiceId: _kService.id,
      serviceName: _kService.name,
      startAt: DateTime(2026, 7, 20, 14),
      endAt: DateTime(2026, 7, 20, 15, 30),
      durationMinutes: 90,
      price: 500,
    ),
  ],
  canReview: false,
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
  status: BookingStatus.confirmed,
  canReview: false,
);

/// Same shape as [_confirmArgs] but on the RESCHEDULE path — carries a non-null
/// `rescheduleBookingId` (matching [_bookingFixture]'s id) so the confirm
/// screen's `_submit` takes the `PATCH /reschedule` branch.
BookingConfirmArgs _rescheduleArgs() => BookingConfirmArgs(
  masterId: _kMaster.id,
  master: _kMaster,
  services: const <MasterService>[_kService],
  startAt: DateTime(2026, 7, 20, 14),
  idempotencyKey: _kIdemKey,
  rescheduleBookingId: 'booking-1',
);

/// Same shape again, but for a track 27.x/MO-6 whole-VISIT reschedule — both
/// `rescheduleBookingId` (the ONE booking whose detail screen triggered the
/// flow, used only for cache invalidation) AND `rescheduleAppointmentId` (the
/// routing discriminator, checked FIRST in `_submit`) are set. [services]
/// carries two items so the recap visibly lists more than one service.
BookingConfirmArgs _appointmentRescheduleArgs() => BookingConfirmArgs(
  masterId: _kMaster.id,
  master: _kMaster,
  services: const <MasterService>[_kService, _kService2],
  startAt: DateTime(2026, 7, 20, 14),
  idempotencyKey: _kIdemKey,
  rescheduleBookingId: 'booking-1',
  rescheduleAppointmentId: 'appt-1',
);

/// Records every [createAppointment] call so the "single call, stable key"
/// criteria can be asserted directly, and either returns [appointmentToReturn]
/// or throws [errorToThrow] when set.
class _FakeAppointmentRepository implements AppointmentRepository {
  _FakeAppointmentRepository({
    this.appointmentToReturn,
    this.errorToThrow,
    this.rescheduleErrorToThrow,
  });

  Appointment? appointmentToReturn;
  Object? errorToThrow;

  /// Track 27.x/MO-6 — thrown by [rescheduleAppointment] when set, mirroring
  /// [errorToThrow]'s role for [createAppointment].
  Object? rescheduleErrorToThrow;
  final List<CreateAppointmentRequest> requests = <CreateAppointmentRequest>[];

  /// Records every whole-visit reschedule call so the "single call, correct
  /// id/time" criteria can be asserted directly — mirrors
  /// `_RecordingRescheduleRepository.rescheduleCalls` for the single-booking
  /// path.
  final List<(String, DateTime)> rescheduleCalls = <(String, DateTime)>[];

  @override
  Future<Appointment> createAppointment(CreateAppointmentRequest req) async {
    requests.add(req);
    final Object? err = errorToThrow;
    if (err != null) throw err;
    return appointmentToReturn!;
  }

  @override
  Future<Appointment> getAppointment(String id) => throw UnimplementedError();

  @override
  Future<Appointment> rescheduleAppointment(
    String id,
    DateTime newStartAt,
  ) async {
    rescheduleCalls.add((id, newStartAt));
    final Object? err = rescheduleErrorToThrow;
    if (err != null) throw err;
    return appointmentToReturn ?? _appointmentFixture();
  }

  @override
  Future<void> cancelAppointment(String id, {String? note}) =>
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
}

/// Records reschedule calls and COUNTS the detail / my-bookings reads so the
/// widget-layer invalidation's re-fetch is observable (a still-listened
/// autoDispose provider only re-fetches when invalidated).
class _RecordingRescheduleRepository implements BookingRepository {
  final List<(String, DateTime)> rescheduleCalls = <(String, DateTime)>[];
  int getBookingByIdCalls = 0;
  int getMyBookingsCalls = 0;

  @override
  Future<Booking> rescheduleBooking(String id, DateTime newStartAt) async {
    rescheduleCalls.add((id, newStartAt));
    return _bookingFixture();
  }

  @override
  Future<Booking> createBooking(CreateBookingRequest req) =>
      throw UnimplementedError();

  @override
  Future<List<DateTime>> getMyBookedDays({
    required DateTime from,
    required DateTime to,
    CancelToken? cancelToken,
  }) => throw UnimplementedError();

  @override
  Future<Booking> getBookingById(String id) async {
    getBookingByIdCalls++;
    return _bookingFixture();
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
    BookingPartition? partition,
    CancelToken? cancelToken,
  }) async {
    getMyBookingsCalls++;
    return PageResponse<Booking>(
      items: <Booking>[_bookingFixture()],
      page: page,
      totalPages: 1,
      totalElements: 1,
    );
  }

  @override
  Future<void> cancelBooking(String id, {String? reason}) =>
      throw UnimplementedError();

  @override
  Future<void> declineBooking(String id, {String? comment}) =>
      throw UnimplementedError();

  @override
  Future<void> completeBooking(String id) => throw UnimplementedError();

  @override
  Future<void> createReview({
    required String bookingId,
    required int rating,
    String? comment,
  }) => throw UnimplementedError();
}

/// Minimal stub auth session — only needed by the whole-visit reschedule
/// test, whose `bookingsDayProvider` watch (mirroring the real provider
/// footer's day-calendar invalidation) reads `authProvider` for its
/// session-boundary PII cache-key. Mirrors
/// `booking_detail_appointment_child_footer_test.dart`'s `_StubAuth`.
class _StubAuth extends AuthNotifier {
  _StubAuth();

  @override
  Future<AuthSession> build() async => const AuthSession.authenticated(
    user: User(
      id: 'master-1',
      email: 'master@e.com',
      role: UserRole.independentMaster,
    ),
    accessToken: 't',
  );
}

/// Minimal fake [SlotRepository] for the Date→Time→Confirm push-chain test.
class _FakeChainSlotRepository implements SlotRepository {
  _FakeChainSlotRepository(this.slotsToReturn);

  final List<BookingSlot> slotsToReturn;

  @override
  Future<List<BookingSlot>> getMasterSlots({
    required String masterId,
    required List<String> serviceIds,
    required DateTime date,
    CancelToken? cancelToken,
  }) async => slotsToReturn;

  @override
  Future<List<WorkingDay>> getWorkingDays({
    required String masterId,
    required DateTime from,
    required DateTime to,
    List<String>? serviceIds,
    CancelToken? cancelToken,
  }) async {
    final List<WorkingDay> days = <WorkingDay>[];
    for (
      DateTime d = from;
      !d.isAfter(to);
      d = d.add(const Duration(days: 1))
    ) {
      days.add(WorkingDay(date: d, working: true));
    }
    return days;
  }
}

/// Router mirroring `app_router.dart`'s REAL nesting for the full booking flow:
/// `bookingSlots` → nested `time` → (pushed) `bookingConfirm`, rendering the
/// REAL production screens (exercises the `master-strip-<id>` Hero chain).
GoRouter _slotToConfirmRouter() => GoRouter(
  initialLocation: '/root',
  routes: <RouteBase>[
    GoRoute(
      path: '/root',
      builder: (context, state) => const SizedBox.shrink(),
    ),
    GoRoute(
      path: RouteNames.bookingSlots,
      builder: (context, state) =>
          SlotDateScreen(args: state.extra! as BookingSlotPickerArgs),
      routes: <RouteBase>[
        GoRoute(
          path: 'time',
          builder: (context, state) =>
              SlotTimeScreen(args: state.extra! as BookingSlotPickerArgs),
        ),
      ],
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

/// Test-local router mirroring `app_router.dart`'s bookingConfirm →
/// bookingSuccess shape, rendering the REAL production screens.
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

/// Reads the router's CURRENT top-of-stack location (`.matches.last`, which
/// reflects the actual top-of-stack for both `.go()` and `.push()`).
String locationOf(GoRouter router) =>
    router.routerDelegate.currentConfiguration.matches.last.matchedLocation;

void main() {
  group('BookingConfirmScreen', () {
    Future<GoRouter> pump(
      WidgetTester tester,
      _FakeAppointmentRepository fake, {
      BookingConfirmArgs? args,
    }) async {
      final GoRouter router = _router();
      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[
          appointmentRepositoryProvider.overrideWith((_) => fake),
          publicMasterProfileProvider(
            _kMaster.id,
          ).overrideWith((ref) => (_kMaster, const <MasterService>[_kService])),
        ],
      );
      unawaited(
        router.push(RouteNames.bookingConfirm, extra: args ?? _confirmArgs()),
      );
      await tester.pumpAndSettle();
      return router;
    }

    testWidgets('renders the master + service summary once data resolves', (
      tester,
    ) async {
      final fake = _FakeAppointmentRepository(
        appointmentToReturn: _appointmentFixture(),
      );
      await pump(tester, fake);

      expect(find.byType(BookingConfirmScreen), findsOneWidget);
      // i18n-finder-ok: master name is fixture data (_kMaster), not translated UI copy.
      expect(find.text('Олена Ковальчук'), findsOneWidget);
      // i18n-finder-ok: service name is fixture data (_kService), not translated UI copy.
      expect(find.text('Манікюр з покриттям'), findsOneWidget);
    });

    // Track 27.x/MO-6 — the whole-visit notice banner is the one explicit
    // "this moves everything" sentence (the recap's multi-row list already
    // implies it, but this makes it unambiguous). Shown ONLY when
    // `rescheduleAppointmentId` is set; absent on a plain create AND on a
    // single-booking reschedule.
    testWidgets(
      'shows the whole-visit notice banner ONLY on an appointment reschedule',
      (tester) async {
        final fake = _FakeAppointmentRepository();
        await pump(tester, fake, args: _appointmentRescheduleArgs());

        expect(
          find.byKey(const Key('booking-confirm-whole-visit-notice')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'REGRESSION GUARD — no whole-visit notice banner on a plain CREATE',
      (tester) async {
        final fake = _FakeAppointmentRepository(
          appointmentToReturn: _appointmentFixture(),
        );
        await pump(tester, fake);

        expect(
          find.byKey(const Key('booking-confirm-whole-visit-notice')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'REGRESSION GUARD — no whole-visit notice banner on a single-booking '
      'reschedule',
      (tester) async {
        final fake = _FakeAppointmentRepository();
        await pump(tester, fake, args: _rescheduleArgs());

        expect(
          find.byKey(const Key('booking-confirm-whole-visit-notice')),
          findsNothing,
        );
      },
    );

    // mobile-qa regression — pins the EXACT locked Ukrainian title so a silent
    // ARB revert is caught (a deliberate exception to the find-by-Key rule).
    testWidgets(
      'renders the exact locked Ukrainian title "Підтвердження" in the top bar',
      (tester) async {
        final fake = _FakeAppointmentRepository(
          appointmentToReturn: _appointmentFixture(),
        );
        await pump(tester, fake);
        // i18n-finder-ok: intentional ARB-lock exception, literal ARB value under test.
        expect(find.text('Підтвердження'), findsOneWidget);
      },
    );

    testWidgets(
      'shows the master\'s role label and ★rating(reviewCount) inside the '
      'master card',
      (tester) async {
        final fake = _FakeAppointmentRepository(
          appointmentToReturn: _appointmentFixture(),
        );
        await pump(tester, fake);

        final Finder masterStrip = find.byType(MasterStrip);
        expect(masterStrip, findsOneWidget);

        final l10n = AppLocalizations.of(tester.element(masterStrip));
        final String roleLabel = masterRoleLabel(_kMaster.type, l10n);
        expect(
          find.descendant(of: masterStrip, matching: find.text(roleLabel)),
          findsOneWidget,
        );
        final String ratingLabel = _kMaster.avgRating.toStringAsFixed(1);
        expect(
          find.descendant(of: masterStrip, matching: find.text(ratingLabel)),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: masterStrip,
            matching: find.text('(${_kMaster.reviewCount})'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      "BookingSummaryCards' showBorder and compactText are NOT set on the "
      'confirm screen',
      (tester) async {
        final fake = _FakeAppointmentRepository(
          appointmentToReturn: _appointmentFixture(),
        );
        await pump(tester, fake);

        final BookingSummaryCards cards = tester.widget<BookingSummaryCards>(
          find.byType(BookingSummaryCards),
        );
        expect(cards.showBorder, isFalse);
        expect(cards.compactText, isFalse);
      },
    );

    testWidgets(
      '«Записатись» calls createAppointment with the ordered service ids + the '
      'stable idempotency key and navigates to /booking/success on success',
      (tester) async {
        final fake = _FakeAppointmentRepository(
          appointmentToReturn: _appointmentFixture(),
        );
        final router = await pump(
          tester,
          fake,
          args: _confirmArgs(
            services: const <MasterService>[_kService, _kService2],
          ),
        );

        await tester.tap(find.byKey(const Key('booking-confirm-submit-cta')));
        await tester.pumpAndSettle();

        expect(fake.requests, hasLength(1));
        final CreateAppointmentRequest sent = fake.requests.single;
        expect(sent.masterId, _kMaster.id);
        // The WHOLE ordered selection is sent as ONE visit, order preserved.
        expect(sent.masterServiceIds, <String>[_kService.id, _kService2.id]);
        expect(sent.startAt, DateTime(2026, 7, 20, 14));
        // The STABLE key carried on the args — never re-minted by this screen.
        expect(sent.idempotencyKey, _kIdemKey);

        expect(locationOf(router), equals(RouteNames.bookingSuccess));
        expect(find.byType(BookingSuccessScreen), findsOneWidget);
      },
    );

    testWidgets(
      'a 409 conflict shows ONE inline error banner, does not navigate away, '
      'and a retry reuses the SAME stable idempotency key and succeeds',
      (tester) async {
        final fake = _FakeAppointmentRepository(
          appointmentToReturn: _appointmentFixture(),
          errorToThrow: const ConflictFailure(),
        );
        final router = await pump(tester, fake);

        await tester.tap(find.byKey(const Key('booking-confirm-submit-cta')));
        await tester.pumpAndSettle();

        // Still on the confirm screen — no crash, no navigation.
        expect(locationOf(router), equals(RouteNames.bookingConfirm));
        expect(find.byType(BookingConfirmScreen), findsOneWidget);

        // ONE inline error banner naming the conflict.
        expect(
          find.byKey(const Key('booking-confirm-submit-error')),
          findsOneWidget,
        );
        final l10n = AppLocalizations.of(
          tester.element(find.byType(BookingConfirmScreen)),
        );
        expect(find.text(l10n.errConflict), findsOneWidget);

        // The comment field is still editable — the screen never got stuck.
        await tester.enterText(
          find.byKey(const Key('booking-confirm-comment-field')),
          'Будь ласка, без запізнень',
        );
        await tester.pump();
        // i18n-finder-ok: arbitrary test-entered text (round-trip check).
        expect(find.text('Будь ласка, без запізнень'), findsOneWidget);

        // Retry — re-attempted with the SAME stable idempotency key (de-dupe).
        fake.errorToThrow = null;
        await tester.tap(find.byKey(const Key('booking-confirm-submit-cta')));
        await tester.pumpAndSettle();

        expect(fake.requests, hasLength(2));
        expect(
          fake.requests[1].idempotencyKey,
          equals(fake.requests[0].idempotencyKey),
        );
        expect(fake.requests[1].idempotencyKey, _kIdemKey);
        expect(locationOf(router), equals(RouteNames.bookingSuccess));
      },
    );

    testWidgets(
      'a DUPLICATE_SERVICE 409 surfaces its own localized error banner',
      (tester) async {
        final fake = _FakeAppointmentRepository(
          appointmentToReturn: _appointmentFixture(),
          errorToThrow: const DuplicateServiceFailure(),
        );
        final router = await pump(tester, fake);

        await tester.tap(find.byKey(const Key('booking-confirm-submit-cta')));
        await tester.pumpAndSettle();

        expect(locationOf(router), equals(RouteNames.bookingConfirm));
        expect(
          find.byKey(const Key('booking-confirm-submit-error')),
          findsOneWidget,
        );
        final l10n = AppLocalizations.of(
          tester.element(find.byType(BookingConfirmScreen)),
        );
        expect(find.text(l10n.bookingErrDuplicateService), findsOneWidget);
      },
    );

    // mobile-qa (MO-3 req 4) — the inline banner is failure-type-agnostic
    // (`failure.userMessage(context)`); these pin that the two remaining
    // create-failure arms decoded by the repository each surface THEIR OWN
    // localized copy in the single banner (never a wrong/generic message), the
    // screen stays put, and no per-appointment rows appear.
    testWidgets(
      'a 409 BOOKING_ALREADY_ELAPSED surfaces its own localized error banner',
      (tester) async {
        final fake = _FakeAppointmentRepository(
          appointmentToReturn: _appointmentFixture(),
          errorToThrow: const BookingAlreadyElapsedFailure(),
        );
        final router = await pump(tester, fake);

        await tester.tap(find.byKey(const Key('booking-confirm-submit-cta')));
        await tester.pumpAndSettle();

        expect(locationOf(router), equals(RouteNames.bookingConfirm));
        expect(
          find.byKey(const Key('booking-confirm-submit-error')),
          findsOneWidget,
        );
        final l10n = AppLocalizations.of(
          tester.element(find.byType(BookingConfirmScreen)),
        );
        expect(find.text(l10n.bookingErrorAlreadyElapsed), findsOneWidget);
      },
    );

    testWidgets('a 429 rate-limit surfaces its own localized error banner', (
      tester,
    ) async {
      final fake = _FakeAppointmentRepository(
        appointmentToReturn: _appointmentFixture(),
        errorToThrow: const BookingRateLimitedFailure(),
      );
      final router = await pump(tester, fake);

      await tester.tap(find.byKey(const Key('booking-confirm-submit-cta')));
      await tester.pumpAndSettle();

      expect(locationOf(router), equals(RouteNames.bookingConfirm));
      expect(
        find.byKey(const Key('booking-confirm-submit-error')),
        findsOneWidget,
      );
      final l10n = AppLocalizations.of(
        tester.element(find.byType(BookingConfirmScreen)),
      );
      expect(find.text(l10n.bookingErrRateLimited), findsOneWidget);
    });

    // mobile-qa (MO-3 req 2) — the SINGLE-service path still books via ONE
    // createAppointment carrying a 1-element ordered list (N=1), UX unchanged.
    testWidgets(
      'a single-service selection books via ONE createAppointment with a '
      '1-element masterServiceIds list',
      (tester) async {
        final fake = _FakeAppointmentRepository(
          appointmentToReturn: _appointmentFixture(),
        );
        final router = await pump(tester, fake); // default args = [_kService]

        await tester.tap(find.byKey(const Key('booking-confirm-submit-cta')));
        await tester.pumpAndSettle();

        expect(fake.requests, hasLength(1));
        expect(fake.requests.single.masterServiceIds, <String>[_kService.id]);
        expect(locationOf(router), equals(RouteNames.bookingSuccess));
      },
    );

    testWidgets('an empty comment is sent as null, a non-empty comment is '
        'trimmed and forwarded', (tester) async {
      final fake = _FakeAppointmentRepository(
        appointmentToReturn: _appointmentFixture(),
      );
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

    testWidgets('the back button pops without submitting a visit', (
      tester,
    ) async {
      final fake = _FakeAppointmentRepository(
        appointmentToReturn: _appointmentFixture(),
      );
      await pump(tester, fake);

      await tester.tap(find.byKey(const Key('booking-confirm-back')));
      await tester.pumpAndSettle();

      expect(fake.requests, isEmpty);
    });

    // A successful RESCHEDULE invalidates bookingDetail(id) + upcoming My
    // Bookings from the widget layer (both re-fetch) and never POSTs a create.
    testWidgets(
      'a successful RESCHEDULE invalidates bookingDetail(id) + upcoming My '
      'Bookings + nextAppointmentProvider from the widget layer (all '
      're-fetch) and navigates to success',
      (tester) async {
        // mobile-qa (Phase 225 fix pass, mobile-perf MEDIUM #4) —
        // nextAppointmentProvider is overridden with its OWN fetch counter
        // (not read off `fake.getMyBookingsCalls`, which the real provider
        // shares with `myBookingsProvider` via `BookingRepository.getMyBookings`
        // and so cannot attribute a refetch to one family over the other).
        // A reschedule may move this booking to/from being the client's
        // soonest upcoming appointment — see `booking_confirm_screen.dart:205`.
        int nextApptFetches = 0;
        final fake = _RecordingRescheduleRepository();
        final router = _router();
        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[
            bookingRepositoryProvider.overrideWith((_) => fake),
            publicMasterProfileProvider(_kMaster.id).overrideWith(
              (ref) => (_kMaster, const <MasterService>[_kService]),
            ),
            nextAppointmentProvider.overrideWith((ref) async {
              nextApptFetches++;
              return null;
            }),
          ],
        );
        unawaited(
          router.push(RouteNames.bookingConfirm, extra: _rescheduleArgs()),
        );
        await tester.pumpAndSettle();

        final ProviderContainer container = ProviderScope.containerOf(
          tester.element(find.byType(BookingConfirmScreen)),
          listen: false,
        );
        final ProviderSubscription<AsyncValue<Booking>> subDetail = container
            .listen(
              bookingDetailProvider('booking-1'),
              (_, _) {},
              fireImmediately: true,
            );
        addTearDown(subDetail.close);
        final ProviderSubscription<AsyncValue<MyBookingsState>> subList =
            container.listen(
              myBookingsProvider(BookingTab.upcoming),
              (_, _) {},
              fireImmediately: true,
            );
        addTearDown(subList.close);
        final ProviderSubscription<AsyncValue<Booking?>> subNextAppt = container
            .listen(nextAppointmentProvider, (_, _) {}, fireImmediately: true);
        addTearDown(subNextAppt.close);
        await container.read(bookingDetailProvider('booking-1').future);
        await container.read(myBookingsProvider(BookingTab.upcoming).future);
        await container.read(nextAppointmentProvider.future);
        expect(fake.getBookingByIdCalls, 1);
        expect(fake.getMyBookingsCalls, 1);
        expect(nextApptFetches, 1);

        await tester.tap(find.byKey(const Key('booking-confirm-submit-cta')));
        await tester.pumpAndSettle();

        expect(fake.rescheduleCalls, hasLength(1));
        expect(fake.rescheduleCalls.single.$1, 'booking-1');
        expect(find.byType(BookingSuccessScreen), findsOneWidget);

        await container.read(bookingDetailProvider('booking-1').future);
        await container.read(myBookingsProvider(BookingTab.upcoming).future);
        await container.read(nextAppointmentProvider.future);
        expect(fake.getBookingByIdCalls, 2);
        expect(fake.getMyBookingsCalls, 2);
        expect(
          nextApptFetches,
          2,
          reason:
              'a successful single-booking reschedule must invalidate '
              'nextAppointmentProvider — the Home Hub card must never show a '
              'stale booking after this write',
        );
      },
    );

    // Track 27.x/MO-6 — a successful WHOLE-VISIT reschedule calls
    // AppointmentRepository.rescheduleAppointment (never BookingRepository
    // .rescheduleBooking), and invalidates bookingDetail(the ONE booking that
    // opened this flow) + bookingsDayProvider (the provider's own day
    // calendar) from the widget layer — NOT myBookingsProvider (that's the
    // CLIENT tab the single-booking branch above refreshes; this flow is
    // PROVIDER-only).
    testWidgets(
      'a successful WHOLE-VISIT reschedule calls rescheduleAppointment, '
      'invalidates bookingDetail(id) + bookingsDayProvider, and navigates to '
      'success',
      (tester) async {
        final appointments = _FakeAppointmentRepository();
        final bookings = _RecordingRescheduleRepository();
        final router = _router();
        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[
            appointmentRepositoryProvider.overrideWith((_) => appointments),
            bookingRepositoryProvider.overrideWith((_) => bookings),
            publicMasterProfileProvider(_kMaster.id).overrideWith(
              (ref) => (_kMaster, const <MasterService>[_kService, _kService2]),
            ),
            authProvider.overrideWith(_StubAuth.new),
          ],
        );
        unawaited(
          router.push(
            RouteNames.bookingConfirm,
            extra: _appointmentRescheduleArgs(),
          ),
        );
        await tester.pumpAndSettle();

        final ProviderContainer container = ProviderScope.containerOf(
          tester.element(find.byType(BookingConfirmScreen)),
          listen: false,
        );
        // Pre-warm auth BEFORE subscribing to bookingsDayProvider — that
        // family watches `authProvider.select(...)`, and _StubAuth's `build()`
        // resolves asynchronously (loading → authenticated), which is itself a
        // VALUE CHANGE the `.select` would otherwise see mid-flight, rebuilding
        // `BookingsDayNotifier` a second time and inflating `getMyBookingsCalls`
        // before the reschedule submit ever runs.
        await container.read(authProvider.future);
        final ProviderSubscription<AsyncValue<Booking>> subDetail = container
            .listen(
              bookingDetailProvider('booking-1'),
              (_, _) {},
              fireImmediately: true,
            );
        addTearDown(subDetail.close);
        final BookingsDayQuery dayQuery = BookingsDayQuery.of(
          day: DateTime(2026, 7, 20),
        );
        final ProviderSubscription<AsyncValue<BookingsDayState>> subDay =
            container.listen(
              bookingsDayProvider(dayQuery),
              (_, _) {},
              fireImmediately: true,
            );
        addTearDown(subDay.close);
        await container.read(bookingDetailProvider('booking-1').future);
        await container.read(bookingsDayProvider(dayQuery).future);
        expect(bookings.getBookingByIdCalls, 1);
        expect(bookings.getMyBookingsCalls, 1);

        await tester.tap(find.byKey(const Key('booking-confirm-submit-cta')));
        await tester.pumpAndSettle();

        expect(appointments.rescheduleCalls, hasLength(1));
        expect(appointments.rescheduleCalls.single.$1, 'appt-1');
        expect(
          appointments.rescheduleCalls.single.$2,
          DateTime(2026, 7, 20, 14),
        );
        expect(find.byType(BookingSuccessScreen), findsOneWidget);

        await container.read(bookingDetailProvider('booking-1').future);
        await container.read(bookingsDayProvider(dayQuery).future);
        expect(bookings.getBookingByIdCalls, 2);
        expect(bookings.getMyBookingsCalls, 2);
      },
    );

    // Track 27.x/MO-6 — a failed WHOLE-VISIT reschedule (the requested slot
    // was taken between fetching availability and submitting) shows ONE
    // inline error banner and stays on the confirm screen, mirroring the
    // single-visit CREATE 409 test above — never a raw crash, never a silent
    // navigation.
    testWidgets(
      'a 409 on a WHOLE-VISIT reschedule shows ONE inline error banner and '
      'does not navigate away',
      (tester) async {
        final fake = _FakeAppointmentRepository(
          rescheduleErrorToThrow: const ConflictFailure(),
        );
        final router = await pump(
          tester,
          fake,
          args: _appointmentRescheduleArgs(),
        );

        await tester.tap(find.byKey(const Key('booking-confirm-submit-cta')));
        await tester.pumpAndSettle();

        expect(locationOf(router), equals(RouteNames.bookingConfirm));
        expect(find.byType(BookingConfirmScreen), findsOneWidget);
        expect(
          find.byKey(const Key('booking-confirm-submit-error')),
          findsOneWidget,
        );
        final l10n = AppLocalizations.of(
          tester.element(find.byType(BookingConfirmScreen)),
        );
        expect(find.text(l10n.errConflict), findsOneWidget);
        expect(fake.rescheduleCalls, hasLength(1));
      },
    );

    // A successful CREATE (a newly-booked, auto-CONFIRMED visit) invalidates
    // the upcoming My Bookings list from the widget layer — the client shell
    // keeps that branch mounted, so its autoDispose notifier only re-fetches
    // when invalidated. Mirrors the reschedule assertion above.
    testWidgets('a successful CREATE invalidates upcoming My Bookings + '
        'nextAppointmentProvider from the widget layer (both re-fetch) and '
        'navigates to success', (tester) async {
      // mobile-qa (Phase 225 fix pass, mobile-perf MEDIUM #4) —
      // nextAppointmentProvider gets its OWN counter, same rationale as the
      // RESCHEDULE test above: it shares `BookingRepository.getMyBookings`
      // with `myBookingsProvider`, so `bookings.getMyBookingsCalls` alone
      // cannot attribute a refetch to one family over the other. A newly
      // created booking may now BE the client's soonest upcoming
      // appointment — see `booking_confirm_screen.dart:235`.
      int nextApptFetches = 0;
      final appointments = _FakeAppointmentRepository(
        appointmentToReturn: _appointmentFixture(),
      );
      final bookings = _RecordingRescheduleRepository();
      final router = _router();
      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[
          appointmentRepositoryProvider.overrideWith((_) => appointments),
          bookingRepositoryProvider.overrideWith((_) => bookings),
          publicMasterProfileProvider(
            _kMaster.id,
          ).overrideWith((ref) => (_kMaster, const <MasterService>[_kService])),
          nextAppointmentProvider.overrideWith((ref) async {
            nextApptFetches++;
            return null;
          }),
        ],
      );
      unawaited(router.push(RouteNames.bookingConfirm, extra: _confirmArgs()));
      await tester.pumpAndSettle();

      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(BookingConfirmScreen)),
        listen: false,
      );
      final ProviderSubscription<AsyncValue<MyBookingsState>> subList =
          container.listen(
            myBookingsProvider(BookingTab.upcoming),
            (_, _) {},
            fireImmediately: true,
          );
      addTearDown(subList.close);
      final ProviderSubscription<AsyncValue<Booking?>> subNextAppt = container
          .listen(nextAppointmentProvider, (_, _) {}, fireImmediately: true);
      addTearDown(subNextAppt.close);
      await container.read(myBookingsProvider(BookingTab.upcoming).future);
      await container.read(nextAppointmentProvider.future);
      expect(bookings.getMyBookingsCalls, 1);
      expect(nextApptFetches, 1);

      await tester.tap(find.byKey(const Key('booking-confirm-submit-cta')));
      await tester.pumpAndSettle();

      expect(appointments.requests, hasLength(1));
      expect(find.byType(BookingSuccessScreen), findsOneWidget);

      // The widget-layer invalidate forced a background re-fetch of the still
      // -listened (mounted) upcoming tab (+ the next-appointment card).
      await container.read(myBookingsProvider(BookingTab.upcoming).future);
      await container.read(nextAppointmentProvider.future);
      expect(bookings.getMyBookingsCalls, 2);
      expect(
        nextApptFetches,
        2,
        reason:
            'a successful CREATE must invalidate nextAppointmentProvider — '
            'the Home Hub card must never show a stale booking after this '
            'write',
      );
    });
  });

  group('BookingSuccessScreen', () {
    BookingSuccessArgs successArgs() => BookingSuccessArgs(
      master: _kMaster,
      services: const <MasterService>[_kService],
      startAt: DateTime(2026, 7, 20, 14),
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
      // i18n-finder-ok: service name is fixture data (_kService).
      expect(find.text('Манікюр з покриттям'), findsOneWidget);
      // No master identity card on the success recap.
      // i18n-finder-ok: master name is fixture data (_kMaster).
      expect(find.text('Олена Ковальчук'), findsNothing);
      expect(find.byType(MasterStrip), findsNothing);
    });

    testWidgets('renders the real Lottie success badge, and the frameBuilder '
        'placeholder path does not crash before the composition loads', (
      tester,
    ) async {
      final GoRouter router = _router();
      await tester.pumpRoutedApp(router);
      router.go(RouteNames.bookingSuccess, extra: successArgs());
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(BookingSuccessScreen), findsOneWidget);

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(Lottie), findsOneWidget);
      expect(tester.getSize(find.byType(Lottie)), const Size(80, 80));
    });

    testWidgets(
      "BookingSummaryCards' showBorder and compactText are wired to true on "
      'the success screen',
      (tester) async {
        await pump(tester);

        final BookingSummaryCards cards = tester.widget<BookingSummaryCards>(
          find.byType(BookingSummaryCards),
        );
        expect(cards.showBorder, isTrue);
        expect(cards.compactText, isTrue);
      },
    );

    testWidgets('subline text renders at fontSize: 11', (tester) async {
      await pump(tester);

      final l10n = AppLocalizations.of(
        tester.element(find.byType(BookingSuccessScreen)),
      );
      final Text subline = tester.widget<Text>(
        find.text(l10n.bookingSuccessSubline),
      );
      expect(subline.style?.fontSize, 11.0);
    });

    testWidgets(
      'lottie controller duration is stretched to 1.4x the raw composition '
      'duration',
      (tester) async {
        await pump(tester);

        final Lottie lottie = tester.widget<Lottie>(find.byType(Lottie));
        final AnimationController? actualController =
            lottie.controller as AnimationController?;
        final Duration? actualDuration = actualController?.duration;
        expect(actualDuration, isNotNull);

        final String? raw = await tester.runAsync(
          () => File('assets/lottie/success.json').readAsString(),
        );
        expect(raw, isNotNull);
        final Map<String, dynamic> json =
            jsonDecode(raw!) as Map<String, dynamic>;
        final double frameRate = (json['fr'] as num).toDouble();
        final double inPoint = (json['ip'] as num).toDouble();
        final double outPoint = (json['op'] as num).toDouble();
        final double rawDurationMs = (outPoint - inPoint) / frameRate * 1000;
        final double expectedStretchedMs = rawDurationMs * 1.4;

        expect(
          actualDuration!.inMicroseconds / 1000,
          closeTo(expectedStretchedMs, 5),
        );
        expect(
          (actualDuration.inMicroseconds / 1000 - rawDurationMs).abs(),
          greaterThan(100),
        );
      },
    );

    testWidgets('blocks back navigation (PopScope canPop: false)', (
      tester,
    ) async {
      await pump(tester);

      final PopScope popScope = tester.widget<PopScope>(find.byType(PopScope));
      expect(popScope.canPop, isFalse);
    });

    testWidgets(
      '«Мої записи» CTA was removed — «На головну» is the sole pinned CTA',
      (tester) async {
        await pump(tester);

        expect(
          find.byKey(const Key('booking-success-my-bookings-cta')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('booking-success-home-cta')),
          findsOneWidget,
        );
      },
    );

    testWidgets('«На головну» navigates to /home', (tester) async {
      final router = await pump(tester);

      await tester.tap(find.byKey(const Key('booking-success-home-cta')));
      await tester.pumpAndSettle();

      expect(locationOf(router), equals(RouteNames.clientHome));
    });
  });

  // MO-3 — the real Date → Time → Confirm push chain (single-visit): pushing
  // all the way from SlotDateScreen through SlotTimeScreen to the REAL
  // BookingConfirmScreen renders the 3rd Hero leg with no tag-collision error,
  // and MasterStrip lands at the same vertical offset on all three screens.
  group('Date → Time → Confirm real push chain', () {
    testWidgets('pushing from SlotDateScreen through SlotTimeScreen to a REAL '
        'BookingConfirmScreen renders the 3rd Hero leg with no tag-collision '
        'error, and MasterStrip stays at the same vertical offset', (
      tester,
    ) async {
      final BookingSlot slot = BookingSlot(
        startAt: DateTime(2026, 7, 20, 10),
        endAt: DateTime(2026, 7, 20, 11),
        available: true,
      );
      final fakeSlots = _FakeChainSlotRepository(<BookingSlot>[slot]);
      const fakeProfile = (_kMaster, <MasterService>[_kService]);
      final router = _slotToConfirmRouter();
      final args = BookingSlotPickerArgs(
        masterId: _kMaster.id,
        master: _kMaster,
        services: const <MasterService>[_kService],
      );

      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[
          slotRepositoryProvider.overrideWith((_) => fakeSlots),
          publicMasterProfileProvider(
            _kMaster.id,
          ).overrideWith((ref) => fakeProfile),
        ],
      );
      unawaited(router.push(RouteNames.bookingSlots, extra: args));
      await tester.pumpAndSettle();

      expect(find.byType(SlotDateScreen), findsOneWidget);
      final double dateOffset = tester
          .getTopLeft(
            find.descendant(
              of: find.byType(SlotDateScreen),
              matching: find.byType(MasterStrip),
            ),
          )
          .dy;

      final DateTime today = DateTime.now();
      await tester.tapCalendarDay(today.day);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('booking-summary-cta')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(SlotTimeScreen), findsOneWidget);
      final double timeOffset = tester
          .getTopLeft(
            find.descendant(
              of: find.byType(SlotTimeScreen),
              matching: find.byType(MasterStrip),
            ),
          )
          .dy;

      final Finder availableChip = find.byWidgetPredicate(
        (Widget w) => w is SlotChip && w.available,
      );
      expect(availableChip, findsOneWidget);
      await tester.tap(availableChip);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('booking-summary-cta')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(BookingConfirmScreen), findsOneWidget);

      final Finder confirmMasterStrip = find.descendant(
        of: find.byType(BookingConfirmScreen),
        matching: find.byType(MasterStrip),
      );
      expect(confirmMasterStrip, findsOneWidget);
      final double confirmOffset = tester.getTopLeft(confirmMasterStrip).dy;

      expect(confirmOffset, closeTo(timeOffset, 0.5));
      expect(confirmOffset, closeTo(dateOffset, 0.5));
    });
  });
}
