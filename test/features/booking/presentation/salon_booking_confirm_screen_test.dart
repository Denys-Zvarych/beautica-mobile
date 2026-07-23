// MO-4 — Widget tests for the reworked SalonBookingConfirmScreen.
//
// The salon flow now submits ONE visit via the SHARED AppointmentSubmit
// (`createAppointment`). Covers:
//   1. Renders the visit recap (master + ordered services) + salon address.
//   2. «Записатись» → ONE createAppointment with the chosen master, the ordered
//      per-master assignment ids, the chosen start, and the visit idem key;
//      then navigates to /booking/salon/success.
//   3. A failed submit → a single inline error banner; a retry REUSES the same
//      idempotency key (de-dupe).

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/booking/application/my_bookings_notifier.dart';
import 'package:beautica_mobile/features/booking/data/appointment_repository.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/appointment.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/booking_tab.dart';
import 'package:beautica_mobile/features/booking/domain/create_appointment_request.dart';
import 'package:beautica_mobile/features/booking/domain/create_booking_request.dart';
import 'package:beautica_mobile/features/booking/domain/salon_booking_confirm_args.dart';
import 'package:beautica_mobile/features/booking/domain/salon_master_schedule.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_booking_confirm_screen.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/salon/application/public_salon_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_master_summary.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/pump_app.dart';

const String _kSalonId = 'salon-1';
const _stubSalon = Salon(
  id: _kSalonId,
  name: 'Салон «Вельвет»',
  street: 'вул. Хрещатик',
  buildingNo: '1',
);
const String _kIdemKey = 'idem-visit-123';

const _svc1 = SalonCatalogService(
  id: 'svc-1',
  name: 'Манікюр з покриттям',
  durationLabel: '1 год 30 хв',
  priceDisplay: '500 ₴',
  durationMinutes: 90,
  priceType: ServicePriceType.fixed,
  priceMin: 500,
);
const _svc2 = SalonCatalogService(
  id: 'svc-2',
  name: 'Педикюр',
  durationLabel: '2 год',
  priceDisplay: '800 ₴',
  durationMinutes: 120,
  priceType: ServicePriceType.fixed,
  priceMin: 800,
);

const _visit = SalonMasterSchedule(
  masterId: 'm2',
  firstName: 'Софія',
  lastName: 'Мельник',
  type: MasterType.salonMaster,
  avgRating: 5.0,
  reviewCount: 3,
  services: <SalonCatalogService>[_svc1, _svc2],
  orderedMasterServiceIds: <String>['assign-m2-svc1', 'assign-m2-svc2'],
);

SalonBookingConfirmArgs _args() => SalonBookingConfirmArgs(
  salonId: _kSalonId,
  visit: _visit,
  startAt: DateTime(2026, 7, 20, 14),
  idempotencyKey: _kIdemKey,
);

Appointment _appointmentFixture() => Appointment(
  id: 'appt-1',
  status: BookingStatus.confirmed,
  masterId: 'm2',
  masterFirstName: 'Софія',
  masterLastName: 'Мельник',
  masterType: 'SALON_MASTER',
  startAt: DateTime(2026, 7, 20, 14),
  endAt: DateTime(2026, 7, 20, 17, 30),
  totalDurationMinutes: 210,
  totalPrice: 1300,
  items: const <AppointmentItem>[],
  canReview: false,
);

class _FakeAppointmentRepository implements AppointmentRepository {
  _FakeAppointmentRepository({this.appointmentToReturn, this.errorToThrow});

  Appointment? appointmentToReturn;
  Object? errorToThrow;
  final List<CreateAppointmentRequest> requests = <CreateAppointmentRequest>[];

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
  Future<void> cancelAppointment(String id, {String? note}) =>
      throw UnimplementedError();
  @override
  Future<void> createAppointmentReview(
    String id, {
    required int rating,
    String? comment,
  }) => throw UnimplementedError();
}

/// COUNTS `getMyBookings` reads so the salon confirm screen's widget-layer
/// `ref.invalidate(myBookingsProvider(BookingTab.upcoming))` (fired on a
/// successful CREATE) is observable as a re-fetch: a still-listened autoDispose
/// notifier only calls `getMyBookings` again when it is invalidated. Mirrors the
/// independent flow's `_RecordingRescheduleRepository` in booking_confirm_test.
class _RecordingBookingRepository implements BookingRepository {
  int getMyBookingsCalls = 0;
  final List<Iterable<BookingStatus>> statusesSeen =
      <Iterable<BookingStatus>>[];

  Booking _bookingFixture() => Booking(
    id: 'booking-salon-1',
    masterId: 'm2',
    masterFirstName: 'Софія',
    masterLastName: 'Мельник',
    masterType: 'SALON_MASTER',
    serviceId: 'svc-1',
    serviceName: 'Манікюр з покриттям',
    durationMinutes: 90,
    price: 500,
    startAt: DateTime(2026, 7, 20, 14),
    endAt: DateTime(2026, 7, 20, 15, 30),
    status: BookingStatus.confirmed,
    canReview: false,
  );

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
  }) async {
    getMyBookingsCalls++;
    statusesSeen.add(statuses);
    return PageResponse<Booking>(
      items: <Booking>[_bookingFixture()],
      page: page,
      totalPages: 1,
      totalElements: 1,
    );
  }

  @override
  Future<Booking> createBooking(CreateBookingRequest req) =>
      throw UnimplementedError();

  @override
  Future<Booking> rescheduleBooking(String id, DateTime newStartAt) =>
      throw UnimplementedError();

  @override
  Future<Booking> getBookingById(String id) => throw UnimplementedError();

  @override
  Future<List<DateTime>> getMyBookedDays({
    required DateTime from,
    required DateTime to,
    CancelToken? cancelToken,
  }) => throw UnimplementedError();

  @override
  Future<void> cancelBooking(String id, {String? reason}) =>
      throw UnimplementedError();

  @override
  Future<void> createReview({
    required String bookingId,
    required int rating,
    String? comment,
  }) => throw UnimplementedError();
}

GoRouter _router() => GoRouter(
  initialLocation: RouteNames.salonBookingConfirm,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.salonBookingConfirm,
      builder: (context, state) => SalonBookingConfirmScreen(args: _args()),
    ),
    GoRoute(
      path: RouteNames.salonBookingSuccess,
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('salon-success-reached'))),
    ),
  ],
);

List<Object> _overrides(_FakeAppointmentRepository fake) => <Object>[
  screenProtectionProvider.overrideWithValue(ScreenProtectionManager()),
  appointmentRepositoryProvider.overrideWith((_) => fake),
  publicSalonProfileProvider(
    _kSalonId,
  ).overrideWith((ref) => (_stubSalon, const <SalonMasterSummary>[])),
];

void main() {
  testWidgets('renders the visit recap and the salon address', (tester) async {
    final fake = _FakeAppointmentRepository(
      appointmentToReturn: _appointmentFixture(),
    );
    await tester.pumpRoutedApp(_router(), overrides: _overrides(fake));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('salon-confirm-visit-card')), findsOneWidget);
    expect(find.byKey(const Key('salon-confirm-address-card')), findsOneWidget);
    // i18n-finder-ok: service name is backend fixture data, not localized UI copy
    expect(find.text('Манікюр з покриттям'), findsOneWidget);
    // i18n-finder-ok: service name is backend fixture data, not localized UI copy
    expect(find.text('Педикюр'), findsOneWidget);
  });

  testWidgets(
    '«Записатись» submits ONE createAppointment with ordered ids + key, then '
    'navigates to success',
    (tester) async {
      final fake = _FakeAppointmentRepository(
        appointmentToReturn: _appointmentFixture(),
      );
      await tester.pumpRoutedApp(_router(), overrides: _overrides(fake));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('salon-confirm-submit-cta')));
      await tester.pumpAndSettle();

      expect(fake.requests, hasLength(1));
      final CreateAppointmentRequest req = fake.requests.single;
      expect(req.masterId, 'm2');
      expect(req.masterServiceIds, <String>[
        'assign-m2-svc1',
        'assign-m2-svc2',
      ]);
      expect(req.startAt, DateTime(2026, 7, 20, 14));
      expect(req.idempotencyKey, _kIdemKey);
      expect(find.text('salon-success-reached'), findsOneWidget);
    },
  );

  testWidgets('a failed submit shows the inline error banner and stays put', (
    tester,
  ) async {
    final fake = _FakeAppointmentRepository(
      errorToThrow: const ServerFailure(statusCode: 500),
    );
    await tester.pumpRoutedApp(_router(), overrides: _overrides(fake));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('salon-confirm-submit-cta')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('salon-confirm-submit-error')), findsOneWidget);
    expect(find.text('salon-success-reached'), findsNothing);
    expect(fake.requests, hasLength(1));
  });

  testWidgets('a retry after a failure REUSES the same idempotency key', (
    tester,
  ) async {
    final fake = _FakeAppointmentRepository(
      errorToThrow: const ServerFailure(statusCode: 500),
    );
    await tester.pumpRoutedApp(_router(), overrides: _overrides(fake));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('salon-confirm-submit-cta')));
    await tester.pumpAndSettle();
    expect(fake.requests, hasLength(1));

    // Second attempt succeeds.
    fake
      ..errorToThrow = null
      ..appointmentToReturn = _appointmentFixture();
    await tester.tap(find.byKey(const Key('salon-confirm-submit-cta')));
    await tester.pumpAndSettle();

    expect(fake.requests, hasLength(2));
    expect(fake.requests[0].idempotencyKey, _kIdemKey);
    expect(fake.requests[1].idempotencyKey, _kIdemKey);
    expect(find.text('salon-success-reached'), findsOneWidget);
  });

  // mobile-qa — stale-My-Bookings regression (salon flow). A successful salon
  // CREATE (a newly-booked, auto-CONFIRMED visit) must invalidate the upcoming
  // My Bookings list from the WIDGET layer: the client shell keeps that branch
  // mounted (`StatefulShellRoute.indexedStack`), so its autoDispose notifier
  // only re-fetches when invalidated — otherwise the new booking is invisible on
  // the already-mounted Записи tab until a manual pull-to-refresh. This mirrors
  // the independent flow's assertion in booking_confirm_test.dart. Without the
  // `ref.invalidate(myBookingsProvider(BookingTab.upcoming))` in
  // SalonBookingConfirmScreen._submit, `getMyBookingsCalls` stays at 1 and this
  // fails.
  testWidgets(
    'a successful CREATE invalidates upcoming My Bookings from the widget layer '
    '(it re-fetches) and navigates to success',
    (tester) async {
      final fake = _FakeAppointmentRepository(
        appointmentToReturn: _appointmentFixture(),
      );
      final bookings = _RecordingBookingRepository();
      await tester.pumpRoutedApp(
        _router(),
        overrides: <Object>[
          ..._overrides(fake),
          bookingRepositoryProvider.overrideWith((_) => bookings),
        ],
      );
      await tester.pumpAndSettle();

      // Mount + warm the upcoming tab BEFORE the create — this is the branch the
      // shell keeps alive while the booking flow is pushed on top of it.
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(SalonBookingConfirmScreen)),
        listen: false,
      );
      final ProviderSubscription<AsyncValue<MyBookingsState>> subList =
          container.listen(
            myBookingsProvider(BookingTab.upcoming),
            (_, _) {},
            fireImmediately: true,
          );
      addTearDown(subList.close);
      await container.read(myBookingsProvider(BookingTab.upcoming).future);
      expect(bookings.getMyBookingsCalls, 1);
      // Precision: the create lands in the UPCOMING tab (auto-CONFIRMED), so it
      // is the upcoming family key the screen must invalidate — assert the tab
      // we warmed queried exactly the CONFIRMED status set.
      expect(
        bookings.statusesSeen.single,
        BookingTab.upcoming.statuses,
        reason: 'the warmed tab is the upcoming (CONFIRMED) family key',
      );

      await tester.tap(find.byKey(const Key('salon-confirm-submit-cta')));
      await tester.pumpAndSettle();

      expect(fake.requests, hasLength(1));
      expect(find.text('salon-success-reached'), findsOneWidget);

      // The widget-layer invalidate forced a background re-fetch of the still
      // -listened (mounted) upcoming tab — its `getMyBookings` ran a 2nd time.
      await container.read(myBookingsProvider(BookingTab.upcoming).future);
      expect(
        bookings.getMyBookingsCalls,
        2,
        reason:
            'a successful salon CREATE must invalidate '
            'myBookingsProvider(BookingTab.upcoming) so the mounted list '
            're-fetches without a manual pull-to-refresh',
      );
    },
  );

  // MO-4 req 6 — the salon confirm reuses the independent flow's failure
  // mapping: the single inline banner (`salon-confirm-submit-error`) is
  // failure-type-agnostic (`failure.userMessage(context)`). These pin that each
  // typed create failure the repository decodes surfaces THAT failure's OWN
  // localized copy in exactly ONE banner, the screen stays on confirm (never
  // navigates to success), and there are NO per-master status rows (the pre-MO-4
  // N-booking fan-out UI is gone). One representative sub-test per decoded arm.
  group('failure states → one inline banner, no per-master rows', () {
    Future<AppLocalizations> pumpWithError(
      WidgetTester tester,
      Object error,
    ) async {
      final fake = _FakeAppointmentRepository(errorToThrow: error);
      await tester.pumpRoutedApp(_router(), overrides: _overrides(fake));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('salon-confirm-submit-cta')));
      await tester.pumpAndSettle();

      // Never navigated away, exactly ONE banner, one create call attempted.
      expect(find.text('salon-success-reached'), findsNothing);
      expect(
        find.byKey(const Key('salon-confirm-submit-error')),
        findsOneWidget,
      );
      expect(fake.requests, hasLength(1));
      return AppLocalizations.of(
        tester.element(find.byType(SalonBookingConfirmScreen)),
      );
    }

    testWidgets('a plain 409 conflict surfaces its own localized banner', (
      tester,
    ) async {
      final l10n = await pumpWithError(tester, const ConflictFailure());
      expect(find.text(l10n.errConflict), findsOneWidget);
    });

    testWidgets(
      'a 409 CLIENT_BOOKING_CONFLICT surfaces its own localized banner naming '
      'the clashing window',
      (tester) async {
        final l10n = await pumpWithError(
          tester,
          ClientBookingConflictFailure(
            conflictingBookingId: 'bk-1',
            serviceName: 'Манікюр класичний',
            masterName: 'Олена Коваль',
            startsAt: DateTime(2026, 7, 20, 12),
            endsAt: DateTime(2026, 7, 20, 13, 30),
          ),
        );
        expect(
          find.text(
            l10n.bookingErrClientConflict(
              'Манікюр класичний',
              'Олена Коваль',
              // The same shared window formatter userMessage composes with.
              formatBookingWindow(
                DateTime(2026, 7, 20, 12),
                DateTime(2026, 7, 20, 13, 30),
              ),
            ),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'a 409 BOOKING_ALREADY_ELAPSED surfaces its own localized banner',
      (tester) async {
        final l10n = await pumpWithError(
          tester,
          const BookingAlreadyElapsedFailure(),
        );
        expect(find.text(l10n.bookingErrorAlreadyElapsed), findsOneWidget);
      },
    );

    testWidgets('a 409 DUPLICATE_SERVICE surfaces its own localized banner', (
      tester,
    ) async {
      final l10n = await pumpWithError(tester, const DuplicateServiceFailure());
      expect(find.text(l10n.bookingErrDuplicateService), findsOneWidget);
    });

    testWidgets('a 429 rate-limit surfaces its own localized banner', (
      tester,
    ) async {
      final l10n = await pumpWithError(
        tester,
        const BookingRateLimitedFailure(),
      );
      expect(find.text(l10n.bookingErrRateLimited), findsOneWidget);
    });
  });
}
