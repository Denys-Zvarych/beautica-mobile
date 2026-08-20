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
import 'package:beautica_mobile/features/booking/domain/create_master_booking_request.dart';
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
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
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

// ---------------------------------------------------------------------------
// Booking-fixture instants — UTC-anchored, shared, named ONCE
// ---------------------------------------------------------------------------
//
// Every fixture below used to spell its own instant as a bare
// `DateTime(2026, 7, 20, 14)`. That resolves its underlying instant through
// the HOST process's own `TZ`, and this file's code under test converts that
// instant through Europe/Kyiv: `booking_confirm_screen.dart:248` keys its
// `bookingsDayProvider` invalidation off
// `dateOnly(toBeauticaTime(widget.args.startAt))`. So the KYIV calendar day
// those fixtures landed on differed per machine — and on 2026-08-04 one of
// them was a live defect, not a hypothetical: under `TZ=Pacific/Honolulu`
// (UTC-10) local 14:00 July 20 is 03:00 July 21 in Kyiv, the invalidation
// targeted a day nobody subscribed to, and the "REGRESSION GUARD — ...
// invalidates bookingsDayProvider" test went red while staying green on the
// dev VM (`TZ=Europe/Kyiv`) and on CI (`TZ=UTC`). Measured across all three
// zones before and after.
//
// `2026-07-20T11:00:00Z` == 14:00 Kyiv (UTC+3, summer DST) — the exact
// wall-clock these fixtures always meant, now a property of the INSTANT
// rather than of whichever zone the test process happens to run under.
//
// Declared as NAMED tokens reused everywhere rather than repeated inline: it
// keeps the `// future-date-ok:` justification to one verified place instead
// of a dozen copies, and it is the style
// `scripts/forbid_host_local_instant_anchor.sh`'s Rule 2 header explicitly
// recommends ("pass a date-token IDENTIFIER rather than an inline literal").
// future-date-ok: fixed booking fixture; the instant it names IS the fixture's identity, never now-relative
final DateTime _kStartAt = DateTime.utc(2026, 7, 20, 11);

/// [_kStartAt] + 90 minutes — 15:30 Kyiv, matching every fixture's
/// `totalDurationMinutes: 90`.
// future-date-ok: fixed twin of _kStartAt, see above
final DateTime _kEndAt = DateTime.utc(2026, 7, 20, 12, 30);

BookingConfirmArgs _confirmArgs({
  List<MasterService> services = const <MasterService>[_kService],
}) => BookingConfirmArgs(
  masterId: _kMaster.id,
  master: _kMaster,
  services: services,
  startAt: _kStartAt,
  idempotencyKey: _kIdemKey,
);

Appointment _appointmentFixture() => Appointment(
  id: 'appt-1',
  status: BookingStatus.confirmed,
  masterId: _kMaster.id,
  masterFirstName: _kMaster.firstName,
  masterLastName: _kMaster.lastName,
  masterType: 'INDEPENDENT_MASTER',
  startAt: _kStartAt,
  endAt: _kEndAt,
  totalDurationMinutes: 90,
  totalPrice: 500,
  items: <AppointmentItem>[
    AppointmentItem(
      bookingId: 'booking-1',
      masterServiceId: _kService.id,
      serviceName: _kService.name,
      startAt: _kStartAt,
      endAt: _kEndAt,
      durationMinutes: 90,
      price: 500,
    ),
  ],
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
  startAt: _kStartAt,
  endAt: _kEndAt,
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
  startAt: _kStartAt,
  idempotencyKey: _kIdemKey,
  rescheduleBookingId: 'booking-1',
);

/// Same shape again, but for a track 30.x per-item VISIT reschedule — both
/// `rescheduleBookingId` (the ONE service being moved) AND
/// `rescheduleAppointmentId` (the visit it belongs to — the routing
/// discriminator, checked FIRST in `_submit`) are set. [services] STILL
/// carries exactly the one item being moved, mirroring [_rescheduleArgs]'s
/// single-service shape — this endpoint never touches the visit's siblings.
///
/// [_kStartAt]'s UTC anchoring is load-bearing HERE in particular, not merely
/// stylistic: `_submit`'s per-item branch scopes its `bookingsDayProvider`
/// invalidation to the KYIV calendar day of this instant
/// (`booking_confirm_screen.dart:248`), and the "REGRESSION GUARD — ...
/// invalidates bookingsDayProvider" test below subscribes to July 20 by name.
/// See [_kStartAt]'s own comment for the measured Honolulu failure this fixed.
BookingConfirmArgs _appointmentItemRescheduleArgs() => BookingConfirmArgs(
  masterId: _kMaster.id,
  master: _kMaster,
  services: const <MasterService>[_kService],
  startAt: _kStartAt,
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
    this.rescheduleItemErrorToThrow,
  });

  Appointment? appointmentToReturn;
  Object? errorToThrow;

  /// Track 30.x — thrown by [rescheduleAppointmentItem] when set, mirroring
  /// [errorToThrow]'s role for [createAppointment].
  Object? rescheduleItemErrorToThrow;
  final List<CreateAppointmentRequest> requests = <CreateAppointmentRequest>[];

  /// Records every per-item reschedule call so the "single call, correct
  /// appointment id / booking id / time" criteria can be asserted directly —
  /// mirrors `_RecordingRescheduleRepository.rescheduleCalls` for the
  /// single-booking path.
  final List<(String, String, DateTime)> rescheduleItemCalls =
      <(String, String, DateTime)>[];

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
  Future<Appointment> rescheduleAppointmentItem(
    String appointmentId,
    String bookingId,
    DateTime newStartAt,
  ) async {
    rescheduleItemCalls.add((appointmentId, bookingId, newStartAt));
    final Object? err = rescheduleItemErrorToThrow;
    if (err != null) throw err;
    return appointmentToReturn ?? _appointmentFixture();
  }

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
  Future<Appointment> createMasterBooking(
    String masterId,
    CreateMasterBookingRequest request,
  ) => throw UnimplementedError();

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

/// Minimal stub auth session — needed by the `bookingsDayProvider` regression
/// guard below, whose watch (mirroring the real provider footer's day-calendar
/// invalidation) reads `authProvider` for its session-boundary PII cache-key.
/// Mirrors `booking_detail_appointment_child_footer_test.dart`'s `_StubAuth`.
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

        // ── Phase 240 tappability policy (LOCKED) — the TAPPABLE half ──────
        //
        // «Підтвердження» is a TERMINAL screen: leaving it costs the client
        // nothing and a back-swipe restores it exactly, so the strip routes
        // into the master's reviews here. This is the one TAPPABLE screen of
        // the three whose branch had no assertion of its own — the other two
        // («Деталі запису», «Залишити відгук») are pinned in their own
        // suites. Without this, a refactor that made the whole booking flow
        // uniformly inert would break the policy silently in the other
        // direction from the SlotDate/SlotTime assertions.
        expect(
          tester.widget<MasterStrip>(masterStrip).onTap,
          isNotNull,
          reason:
              'the confirm step is terminal — the strip must offer the route '
              'into the master\'s reviews.',
        );

        final l10n = AppLocalizations.of(tester.element(masterStrip));
        final String roleLabel = masterRoleLabel(_kMaster.type, l10n);
        expect(
          find.descendant(of: masterStrip, matching: find.text(roleLabel)),
          findsOneWidget,
        );
        // `!` is deliberate: the fixture defines a non-null rating, and this
        // assertion must stay strict — falling back to the `—` placeholder
        // here would let a regression that drops the rating pass silently.
        final String ratingLabel = _kMaster.avgRating!.toStringAsFixed(1);
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
        expect(sent.startAt, _kStartAt);
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

    // Track 30.x — a successful per-item VISIT reschedule calls
    // AppointmentRepository.rescheduleAppointmentItem (never
    // BookingRepository.rescheduleBooking), and — because it now shares the
    // exact same single-item shape as the plain single-booking reschedule —
    // invalidates the SAME set from the widget layer: bookingDetail(id) +
    // upcoming My Bookings + nextAppointmentProvider. There is no more a
    // separate provider-only bookingsDayProvider branch to special-case (the
    // earlier whole-visit flow's endpoint is untouched on the backend; only
    // this mobile entry point was retired).
    testWidgets('a successful per-item VISIT reschedule calls '
        'rescheduleAppointmentItem, invalidates bookingDetail(id) + upcoming '
        'My Bookings + nextAppointmentProvider, and navigates to success', (
      tester,
    ) async {
      int nextApptFetches = 0;
      final appointments = _FakeAppointmentRepository();
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
      unawaited(
        router.push(
          RouteNames.bookingConfirm,
          extra: _appointmentItemRescheduleArgs(),
        ),
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
      expect(bookings.getBookingByIdCalls, 1);
      expect(bookings.getMyBookingsCalls, 1);
      expect(nextApptFetches, 1);

      await tester.tap(find.byKey(const Key('booking-confirm-submit-cta')));
      await tester.pumpAndSettle();

      expect(appointments.rescheduleItemCalls, hasLength(1));
      expect(appointments.rescheduleItemCalls.single.$1, 'appt-1');
      expect(appointments.rescheduleItemCalls.single.$2, 'booking-1');
      // Mirrors `_appointmentItemRescheduleArgs()`'s own anchor — see its doc
      // for why this is `DateTime.utc(...)` and not a bare local literal.
      expect(appointments.rescheduleItemCalls.single.$3, _kStartAt);
      expect(find.byType(BookingSuccessScreen), findsOneWidget);

      await container.read(bookingDetailProvider('booking-1').future);
      await container.read(myBookingsProvider(BookingTab.upcoming).future);
      await container.read(nextAppointmentProvider.future);
      expect(bookings.getBookingByIdCalls, 2);
      expect(bookings.getMyBookingsCalls, 2);
      expect(
        nextApptFetches,
        2,
        reason:
            'a successful per-item reschedule must invalidate '
            'nextAppointmentProvider — the Home Hub card must never show a '
            'stale booking after this write',
      );
    });

    // mobile-qa REGRESSION GUARD (mobile-perf CRITICAL, track 30.x cutover) —
    // the retired whole-visit branch used to ALSO invalidate
    // `bookingsDayProvider` (the PROVIDER's own «Мої записи» day timeline)
    // alongside the detail/list refresh above — see
    // `booking_calendar_invalidation.dart` and `booking_detail_screen.dart`'s
    // `_confirmDecline`/`_confirmComplete` for the SAME pattern on the other
    // two provider-write transitions. When the per-item branch was unified
    // with the plain single-booking one (which never touched
    // `bookingsDayProvider`), this invalidation was silently dropped:
    // `_onReschedule` forwards `appointmentId` for BOTH client and provider
    // viewers, so a PROVIDER moving ONE service of their own multi-service
    // visit now leaves their day-calendar screen showing the booking at its
    // OLD slot until the ≤3-day keepAlive LRU happens to evict. This test
    // pins the CORRECT behaviour and is EXPECTED TO FAIL until `_submit`'s
    // per-item branch also invalidates `bookingsDayProvider`, mirroring
    // `_confirmDecline`/`_confirmComplete`.
    testWidgets(
      'REGRESSION GUARD — a successful per-item VISIT reschedule ALSO '
      'invalidates bookingsDayProvider so the PROVIDER\'s own day-calendar '
      'screen re-fetches and stops showing the moved item at its OLD slot',
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
              (ref) => (_kMaster, const <MasterService>[_kService]),
            ),
            authProvider.overrideWith(_StubAuth.new),
          ],
        );
        unawaited(
          router.push(
            RouteNames.bookingConfirm,
            extra: _appointmentItemRescheduleArgs(),
          ),
        );
        await tester.pumpAndSettle();

        final ProviderContainer container = ProviderScope.containerOf(
          tester.element(find.byType(BookingConfirmScreen)),
          listen: false,
        );
        // Pre-warm auth BEFORE subscribing to bookingsDayProvider — that
        // family watches `authProvider.select(...)`, and `_StubAuth.build()`
        // resolves asynchronously (loading → authenticated), which is itself
        // a VALUE CHANGE the `.select` would otherwise see mid-flight,
        // rebuilding `BookingsDayNotifier` a second time and inflating
        // `getMyBookingsCalls` before the reschedule submit ever runs.
        await container.read(authProvider.future);
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
        await container.read(bookingsDayProvider(dayQuery).future);
        expect(bookings.getMyBookingsCalls, 1);

        await tester.tap(find.byKey(const Key('booking-confirm-submit-cta')));
        await tester.pumpAndSettle();

        expect(appointments.rescheduleItemCalls, hasLength(1));
        expect(find.byType(BookingSuccessScreen), findsOneWidget);

        await container.read(bookingsDayProvider(dayQuery).future);
        expect(
          bookings.getMyBookingsCalls,
          2,
          reason:
              'a successful per-item VISIT reschedule must invalidate '
              'bookingsDayProvider so the PROVIDER\'s own day-calendar '
              'screen re-fetches — the retired whole-visit branch did this; '
              'the unified per-item branch must too (mobile-perf CRITICAL)',
        );
      },
    );

    // REGRESSION GUARD (mobile-perf HIGH, 2026-08-13) — the sibling guard
    // above subscribes to `BookingsDayQuery.of(day:)`, the EMPTY-status family
    // member. That is NOT the member the master's own «Мої записи» watches:
    // since CANCELLED/DECLINED became hidden by default (locked 2026-08-13),
    // `BookingsDiscoveryView` watches `BookingsDayQuery.dayList(day:)`
    // (`{CONFIRMED, COMPLETED, NOT_COMPLETED}` on the wire). Different family
    // key — so the invalidation loop could stay green here while invalidating
    // nothing the screen actually reads, and `bookings_day_notifier.dart`'s
    // ≤3-day keepAlive LRU pins that stale member ACROSS screen disposal, so
    // the moved item keeps rendering at its OLD slot until a manual
    // pull-to-refresh. This test pins the member the SCREEN uses; keep both.
    testWidgets(
      'REGRESSION GUARD — a successful per-item VISIT reschedule invalidates '
      'the DEFAULT day-list member (BookingsDayQuery.dayList) the master\'s '
      'own «Мої записи» actually watches, not just the empty-status one',
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
              (ref) => (_kMaster, const <MasterService>[_kService]),
            ),
            authProvider.overrideWith(_StubAuth.new),
          ],
        );
        unawaited(
          router.push(
            RouteNames.bookingConfirm,
            extra: _appointmentItemRescheduleArgs(),
          ),
        );
        await tester.pumpAndSettle();

        final ProviderContainer container = ProviderScope.containerOf(
          tester.element(find.byType(BookingConfirmScreen)),
          listen: false,
        );
        // Pre-warm auth BEFORE subscribing — see the sibling guard above.
        await container.read(authProvider.future);
        // Built exactly as `BookingsDiscoveryView._rebuildQuery` builds it: the
        // shared factory with the master's RAW (empty) selection, NOT a
        // hand-written `{confirmed, completed, notCompleted}` literal — a
        // literal here would re-create the drift this guard exists to catch.
        final BookingsDayQuery dayListQuery = BookingsDayQuery.dayList(
          day: DateTime(2026, 7, 20),
        );
        expect(
          dayListQuery,
          isNot(BookingsDayQuery.of(day: DateTime(2026, 7, 20))),
          reason:
              'the default day-list member must be a DIFFERENT family key '
              'from the plain empty-status one — if these ever collapse to '
              'one key this guard silently stops testing anything',
        );
        final ProviderSubscription<AsyncValue<BookingsDayState>> subDay =
            container.listen(
              bookingsDayProvider(dayListQuery),
              (_, _) {},
              fireImmediately: true,
            );
        addTearDown(subDay.close);
        await container.read(bookingsDayProvider(dayListQuery).future);
        expect(bookings.getMyBookingsCalls, 1);

        await tester.tap(find.byKey(const Key('booking-confirm-submit-cta')));
        await tester.pumpAndSettle();

        expect(appointments.rescheduleItemCalls, hasLength(1));
        expect(find.byType(BookingSuccessScreen), findsOneWidget);

        await container.read(bookingsDayProvider(dayListQuery).future);
        expect(
          bookings.getMyBookingsCalls,
          2,
          reason:
              'a successful per-item VISIT reschedule must invalidate the '
              'day-list member the master\'s own screen watches — '
              'invalidating only BookingsDayQuery.of(day:) leaves the '
              'kept-alive default member serving the item at its OLD slot',
        );
      },
    );

    // mobile-qa REGRESSION GUARD (UTC/Kyiv date-boundary anchor) — the
    // invalidation loop above used to key `bookingsDayProvider` off
    // `dateOnly(widget.args.startAt)` DIRECTLY. `startAt` is a canonical UTC
    // instant on the wire (the generated built_value client normalises every
    // `DateTime` to UTC), so reading `.year`/`.month`/`.day` straight off it
    // yields the UTC calendar day, not the Kyiv one `BookingsDayQuery` is
    // keyed on. For a visit whose Kyiv wall-clock time falls shortly after
    // Kyiv midnight, the UTC day is the PREVIOUS day — so the invalidation
    // silently targets a family member nobody subscribes to, and the
    // day-calendar screen keeps showing the item at its OLD slot until the
    // ≤3-day keepAlive LRU evicts.
    //
    // Deliberately built on a `DateTime.utc(...)` instant (never a bare
    // `DateTime(...)` literal, which resolves through the HOST process's own
    // zone) so the UTC-vs-Kyiv day split is a REAL, host-timezone-independent
    // property of the instant itself — this must fail identically whichever
    // zone the test happens to run under, not just on the dev VM's zone.
    testWidgets(
      'REGRESSION GUARD — a per-item VISIT reschedule whose new startAt '
      'crosses the UTC/Kyiv date boundary invalidates the KYIV calendar day, '
      'not the UTC one',
      (tester) async {
        // 2026-07-20T22:00:00Z == 2026-07-21 01:00 in Kyiv (UTC+3, summer
        // DST) — the Kyiv calendar day is the 21st, one day AHEAD of the raw
        // UTC calendar day (the 20th). Fixed rather than now-relative because
        // the exact boundary crossing IS the assertion; this screen never
        // reads the value through isPast, so it can never become a
        // stale-fixture time bomb.
        // future-date-ok: fixed instant pins the exact UTC/Kyiv day-boundary split under test
        final DateTime boundaryStartAt = DateTime.utc(2026, 7, 20, 22);
        final BookingConfirmArgs args = BookingConfirmArgs(
          masterId: _kMaster.id,
          master: _kMaster,
          services: const <MasterService>[_kService],
          startAt: boundaryStartAt,
          idempotencyKey: _kIdemKey,
          rescheduleBookingId: 'booking-1',
          rescheduleAppointmentId: 'appt-1',
        );
        final appointments = _FakeAppointmentRepository();
        final bookings = _RecordingRescheduleRepository();
        final router = _router();
        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[
            appointmentRepositoryProvider.overrideWith((_) => appointments),
            bookingRepositoryProvider.overrideWith((_) => bookings),
            publicMasterProfileProvider(_kMaster.id).overrideWith(
              (ref) => (_kMaster, const <MasterService>[_kService]),
            ),
            authProvider.overrideWith(_StubAuth.new),
          ],
        );
        unawaited(router.push(RouteNames.bookingConfirm, extra: args));
        await tester.pumpAndSettle();

        final ProviderContainer container = ProviderScope.containerOf(
          tester.element(find.byType(BookingConfirmScreen)),
          listen: false,
        );
        // Pre-warm auth BEFORE subscribing to bookingsDayProvider — see the
        // sibling REGRESSION GUARD test above for why.
        await container.read(authProvider.future);

        // Subscribes to the CORRECT (Kyiv) day, July 21st — NOT July 20th,
        // the UTC day the bug used to compute.
        final BookingsDayQuery kyivDayQuery = BookingsDayQuery.of(
          day: DateTime(2026, 7, 21),
        );
        final ProviderSubscription<AsyncValue<BookingsDayState>> subDay =
            container.listen(
              bookingsDayProvider(kyivDayQuery),
              (_, _) {},
              fireImmediately: true,
            );
        addTearDown(subDay.close);
        await container.read(bookingsDayProvider(kyivDayQuery).future);
        expect(bookings.getMyBookingsCalls, 1);

        await tester.tap(find.byKey(const Key('booking-confirm-submit-cta')));
        await tester.pumpAndSettle();

        expect(appointments.rescheduleItemCalls, hasLength(1));
        expect(find.byType(BookingSuccessScreen), findsOneWidget);

        await container.read(bookingsDayProvider(kyivDayQuery).future);
        expect(
          bookings.getMyBookingsCalls,
          2,
          reason:
              'a per-item VISIT reschedule whose new startAt lands just '
              'after Kyiv midnight must invalidate the KYIV calendar day '
              '(the 21st), not the UTC one (the 20th) — otherwise the '
              'day-calendar screen keeps showing the item at its OLD slot',
        );
      },
    );

    // Track 30.x — a failed per-item VISIT reschedule (the requested slot
    // overlaps a sibling, or the master is otherwise busy) shows ONE inline
    // error banner and stays on the confirm screen, mirroring the single-visit
    // CREATE 409 test above — never a raw crash, never a silent navigation.
    // The backend cannot distinguish this from the "changed concurrently"
    // guard on the wire (both are a bare `data: null` 409 — see
    // `HttpAppointmentRepository._mapAppointmentItemRescheduleException`), so
    // both surface as this SAME generic errConflict copy.
    testWidgets(
      'a 409 on a per-item VISIT reschedule shows ONE inline error banner '
      'and does not navigate away',
      (tester) async {
        final fake = _FakeAppointmentRepository(
          rescheduleItemErrorToThrow: const ConflictFailure(),
        );
        final router = await pump(
          tester,
          fake,
          args: _appointmentItemRescheduleArgs(),
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
        expect(fake.rescheduleItemCalls, hasLength(1));
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
      startAt: _kStartAt,
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
      // 07:00Z / 08:00Z == 10:00 / 11:00 Kyiv (UTC+3, summer DST). UTC-anchored
      // for the same reason as `_kStartAt` above — `SlotTimeScreen` renders
      // these through the Kyiv zone, so a bare local literal would render a
      // different wall-clock on every host.
      final BookingSlot slot = BookingSlot(
        // future-date-ok: fixed slot fixture; twin of _kStartAt's rationale
        startAt: DateTime.utc(2026, 7, 20, 7),
        // future-date-ok: fixed slot fixture; twin of _kStartAt's rationale
        endAt: DateTime.utc(2026, 7, 20, 8),
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

      // mobile-qa (F2 timezone fix) — `SlotDateScreen`'s calendar gates
      // "today" via `kyivToday`, fed from the app's injected clock seam (see
      // `lib/core/time/clock_provider.dart`), not the raw device clock; a
      // bare `DateTime.now()` here disagrees with it for roughly a third of
      // every 24h window (UTC ~21:00-24:00, once Kyiv has already rolled to
      // the next calendar day), taps an already-PAST disabled cell, and
      // fails deterministically. Mirrors the same fix in
      // `slot_picker_test.dart` / `salon_time_screen_test.dart`.
      final DateTime today = kyivToday(DateTime.now);
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
