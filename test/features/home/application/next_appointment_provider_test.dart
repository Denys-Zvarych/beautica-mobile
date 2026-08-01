// Phase 225 — nextAppointmentProvider unit tests.
//
// The Home Hub's «Найближчий запис» card used to be a hardcoded stub
// (always null). It now derives from `BookingRepository.getMyBookings` —
// the SAME endpoint/request shape the «Мої записи» Майбутні tab issues
// (`BookingTab.upcoming.statuses` + `BookingSort.oldest`, page 0). These
// tests pin:
//   • the exact request shape (statuses/sort/page) sent to the repository;
//   • the domain → NextAppointment field mapping (date/time labels, location
//     fallback, master initials, the real `endsAt`);
//   • the elapsed-but-not-yet-transitioned edge case: a CONFIRMED booking
//     whose `endAt` is already in the past (server hasn't flipped its status
//     yet) must be skipped in favour of the next genuinely-upcoming row;
//   • an empty page, or a page where EVERY row is elapsed, resolves to null;
//   • a repository failure propagates as this provider's AsyncError, exactly
//     like `clientProfile`'s unauthenticated-session contract.
//
// Strategy: a hand-written [_FakeBookingRepository] (mirrors
// `client_profile_provider_test.dart`'s `_FakeLocationRepository`) rather
// than a mocktail mock — it records the exact call args made and lets each
// test hand back whatever page it wants without matcher gymnastics over an
// `Iterable<BookingStatus>` parameter.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/booking_tab.dart';
import 'package:beautica_mobile/features/booking/domain/create_booking_request.dart';
import 'package:beautica_mobile/features/home/application/home_hub_notifier.dart';
import 'package:beautica_mobile/features/home/domain/home_hub_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/booking_fixture_dates.dart';

// ---------------------------------------------------------------------------
// Fake BookingRepository — records the getMyBookings call, everything else
// throws (unused by this provider).
// ---------------------------------------------------------------------------

class _FakeBookingRepository implements BookingRepository {
  _FakeBookingRepository(this._page);

  /// Swap mid-test via [respondWith] when a test needs a second scripted call
  /// (not used currently, but keeps the fake reusable).
  PageResponse<Booking> _page;
  void respondWith(PageResponse<Booking> page) => _page = page;

  /// The Object? failure to throw instead of returning [_page], or null to
  /// return normally.
  Object? throwing;

  // Captured call args — asserted by the "request shape" test.
  Iterable<BookingStatus>? capturedStatuses;
  BookingSort? capturedSort;
  int? capturedPage;
  int? capturedSize;
  int callCount = 0;

  @override
  Future<PageResponse<Booking>> getMyBookings({
    required Iterable<BookingStatus> statuses,
    required int page,
    int size = kBookingsPageSize,
    BookingSort? sort,
    Iterable<String>? serviceIds,
    DateTime? from,
    DateTime? to,
    CancelToken? cancelToken,
  }) async {
    callCount++;
    capturedStatuses = statuses;
    capturedSort = sort;
    capturedPage = page;
    capturedSize = size;
    final Object? f = throwing;
    if (f != null) throw f;
    return _page;
  }

  @override
  Future<Booking> createBooking(CreateBookingRequest req) =>
      throw UnimplementedError('not used by nextAppointmentProvider');

  @override
  Future<List<DateTime>> getMyBookedDays({
    required DateTime from,
    required DateTime to,
    CancelToken? cancelToken,
  }) => throw UnimplementedError('not used by nextAppointmentProvider');

  @override
  Future<Booking> getBookingById(String id) =>
      throw UnimplementedError('not used by nextAppointmentProvider');

  @override
  Future<void> cancelBooking(String id, {String? reason}) =>
      throw UnimplementedError('not used by nextAppointmentProvider');

  @override
  Future<Booking> rescheduleBooking(String id, DateTime newStartAt) =>
      throw UnimplementedError('not used by nextAppointmentProvider');

  @override
  Future<void> declineBooking(String id, {String? comment}) =>
      throw UnimplementedError('not used by nextAppointmentProvider');

  @override
  Future<void> completeBooking(String id) =>
      throw UnimplementedError('not used by nextAppointmentProvider');

  @override
  Future<void> createReview({
    required String bookingId,
    required int rating,
    String? comment,
  }) => throw UnimplementedError('not used by nextAppointmentProvider');
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/// A CONFIRMED booking starting [aheadOfNow] from now and ending
/// [durationMinutes] later — genuinely upcoming when [aheadOfNow] is positive
/// and [durationMinutes] doesn't carry the end back into the past.
Booking _booking({
  required String id,
  Duration aheadOfNow = const Duration(days: 2),
  int durationMinutes = 60,
  String? salonName,
  String? cityLabel,
  String? street,
  String? buildingNo,
}) {
  final DateTime start = futureBookingStart(aheadOfNow: aheadOfNow);
  return Booking(
    id: id,
    masterId: 'master-$id',
    masterFirstName: 'Марія',
    masterLastName: 'Іванюк',
    masterType: 'INDEPENDENT_MASTER',
    salonName: salonName,
    serviceId: 'svc-$id',
    serviceName: 'Манікюр',
    cityLabel: cityLabel,
    street: street,
    buildingNo: buildingNo,
    durationMinutes: durationMinutes,
    price: 500,
    startAt: start,
    endAt: start.add(Duration(minutes: durationMinutes)),
    status: BookingStatus.confirmed,
    canReview: false,
  );
}

/// An ALREADY-ELAPSED CONFIRMED booking — `endAt` in the past even though the
/// status is still CONFIRMED (the server hasn't transitioned it yet). Exists
/// to drive the client-side [BookingDisplayX.isPast] skip.
Booking _elapsedBooking(String id) {
  final DateTime start = DateTime.utc(2000, 1, 1, 9);
  return Booking(
    id: id,
    masterId: 'master-$id',
    masterFirstName: 'Марія',
    masterLastName: 'Іванюк',
    masterType: 'INDEPENDENT_MASTER',
    serviceId: 'svc-$id',
    serviceName: 'Манікюр',
    durationMinutes: 60,
    price: 500,
    startAt: start,
    endAt: start.add(const Duration(minutes: 60)),
    status: BookingStatus.confirmed,
    canReview: false,
  );
}

ProviderContainer _container(_FakeBookingRepository repo) {
  final container = ProviderContainer(
    overrides: [bookingRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('nextAppointment request shape', () {
    test('issues ONE getMyBookings call with BookingTab.upcoming.statuses, '
        'BookingSort.oldest, page 0', () async {
      final repo = _FakeBookingRepository(
        const PageResponse<Booking>(
          items: <Booking>[],
          page: 0,
          totalPages: 1,
          totalElements: 0,
        ),
      );
      final container = _container(repo);

      final result = await container.read(nextAppointmentProvider.future);

      expect(result, isNull);
      expect(
        repo.callCount,
        1,
        reason: 'must issue exactly one request, never per-status fan-out',
      );
      expect(repo.capturedStatuses, BookingTab.upcoming.statuses);
      expect(repo.capturedSort, BookingSort.oldest);
      expect(repo.capturedPage, 0);
    });
  });

  group('nextAppointment mapping', () {
    test('maps the soonest upcoming booking to a NextAppointment', () async {
      final Booking booking = _booking(
        id: 'bk-1',
        street: 'вул. Хрещатик',
        buildingNo: '22',
        cityLabel: 'Київ',
      );
      final repo = _FakeBookingRepository(
        PageResponse<Booking>(
          items: <Booking>[booking],
          page: 0,
          totalPages: 1,
          totalElements: 1,
        ),
      );
      final container = _container(repo);

      final NextAppointment? result = await container.read(
        nextAppointmentProvider.future,
      );

      expect(result, isNotNull);
      expect(result!.id, booking.id);
      expect(result.masterName, 'Марія Іванюк');
      expect(result.service, 'Манікюр');
      expect(result.startsAt, booking.startAt);
      expect(result.endsAt, booking.endAt);
      expect(result.masterInitials, 'МІ');
      expect(result.location, 'вул. Хрещатик, 22, Київ');
    });

    test(
      'falls back to salonName when the booking has no composed address',
      () async {
        final Booking booking = _booking(
          id: 'bk-2',
          salonName: 'Lviv Nails Studio',
        );
        final repo = _FakeBookingRepository(
          PageResponse<Booking>(
            items: <Booking>[booking],
            page: 0,
            totalPages: 1,
            totalElements: 1,
          ),
        );
        final container = _container(repo);

        final NextAppointment? result = await container.read(
          nextAppointmentProvider.future,
        );

        expect(result!.location, 'Lviv Nails Studio');
      },
    );

    test('location is the empty string when neither an address nor a salon '
        'name is on file', () async {
      final Booking booking = _booking(id: 'bk-3');
      final repo = _FakeBookingRepository(
        PageResponse<Booking>(
          items: <Booking>[booking],
          page: 0,
          totalPages: 1,
          totalElements: 1,
        ),
      );
      final container = _container(repo);

      final NextAppointment? result = await container.read(
        nextAppointmentProvider.future,
      );

      expect(result!.location, '');
    });
  });

  group('nextAppointment elapsed-row skip', () {
    test('a head row whose endAt has already elapsed is skipped in favour of '
        'the next genuinely-upcoming row in the same page', () async {
      final Booking elapsed = _elapsedBooking('bk-elapsed');
      final Booking upcoming = _booking(id: 'bk-upcoming');
      final repo = _FakeBookingRepository(
        PageResponse<Booking>(
          items: <Booking>[elapsed, upcoming],
          page: 0,
          totalPages: 1,
          totalElements: 2,
        ),
      );
      final container = _container(repo);

      final NextAppointment? result = await container.read(
        nextAppointmentProvider.future,
      );

      expect(
        result!.id,
        'bk-upcoming',
        reason:
            'the elapsed row must be skipped client-side even though the '
            'server still reports it CONFIRMED',
      );
    });

    test('a page where every row has already elapsed resolves to null, not the '
        'stale head row', () async {
      final repo = _FakeBookingRepository(
        PageResponse<Booking>(
          items: <Booking>[
            _elapsedBooking('bk-elapsed-1'),
            _elapsedBooking('bk-elapsed-2'),
          ],
          page: 0,
          totalPages: 1,
          totalElements: 2,
        ),
      );
      final container = _container(repo);

      final NextAppointment? result = await container.read(
        nextAppointmentProvider.future,
      );

      expect(result, isNull);
    });

    test(
      'an empty page resolves to null (no upcoming bookings at all)',
      () async {
        final repo = _FakeBookingRepository(
          const PageResponse<Booking>(
            items: <Booking>[],
            page: 0,
            totalPages: 1,
            totalElements: 0,
          ),
        );
        final container = _container(repo);

        final NextAppointment? result = await container.read(
          nextAppointmentProvider.future,
        );

        expect(result, isNull);
      },
    );
  });

  group('nextAppointment error propagation', () {
    test(
      'a repository failure propagates as this provider\'s AsyncError, '
      'exactly like clientProfile\'s unauthenticated-session contract',
      () async {
        final repo = _FakeBookingRepository(
          const PageResponse<Booking>(
            items: <Booking>[],
            page: 0,
            totalPages: 1,
            totalElements: 0,
          ),
        )..throwing = const UnauthorizedFailure();
        final container = ProviderContainer(
          retry: (_, _) => null,
          overrides: [bookingRepositoryProvider.overrideWithValue(repo)],
        );
        addTearDown(container.dispose);

        await expectLater(
          container.read(nextAppointmentProvider.future),
          throwsA(isA<UnauthorizedFailure>()),
        );
      },
    );
  });
}
