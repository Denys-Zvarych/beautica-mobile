// mobile-qa (track 24.x booking auto-confirm) — Unit tests for
// [IndependentBookingSubmit.submit] on the RESCHEDULE path.
//
// The create path is covered by booking_confirm_test.dart +
// independent_multi_service_booking_flow_test.dart. This suite pins the
// reschedule-specific contract the notifier owns:
//
//   1. A non-null `rescheduleBookingId` submit calls
//      `BookingRepository.rescheduleBooking(id, startAt)` — NEVER
//      `createBooking` — and, on success, fires BOTH invalidations
//      (`bookingDetailProvider(id)` + `myBookingsProvider(upcoming)`) so the
//      moved booking's detail and the upcoming list re-fetch.
//   2. A per-appointment failure (409 / 403 / 400, whatever mapped Failure the
//      repository throws) surfaces on that appointment EXACTLY like the create
//      path — `failureFor(serviceId)` set, `hasFailures` true — and fires
//      NEITHER invalidation (a failed reschedule must not refresh anything).
//
// Strategy: a fresh `ProviderContainer` per test (M1 — disposed via
// addTearDown) overriding `bookingRepositoryProvider` with a hand-written
// recording fake. The two invalidation targets are kept alive with a listener
// and their post-submit RE-FETCH is the observable proof that each invalidation
// took effect (a plain read of an unchanged, still-listened autoDispose provider
// returns its cache — only an invalidation forces a fresh repo call).

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/features/booking/application/booking_detail_notifier.dart';
import 'package:beautica_mobile/features/booking/application/booking_notifier.dart';
import 'package:beautica_mobile/features/booking/application/my_bookings_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_appointment.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/booking_tab.dart';
import 'package:beautica_mobile/features/booking/domain/create_booking_request.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Recording fake — records reschedule + create calls, and counts the
// detail/list reads (so an invalidation re-fetch is observable). `rescheduleErr`
// makes the NEXT rescheduleBooking throw the given Failure.
// ---------------------------------------------------------------------------

class _RecordingRepo implements BookingRepository {
  _RecordingRepo({this.rescheduleErr});

  Failure? rescheduleErr;

  final List<(String, DateTime)> rescheduleCalls = <(String, DateTime)>[];
  final List<CreateBookingRequest> createCalls = <CreateBookingRequest>[];
  int getBookingByIdCalls = 0;
  int getMyBookingsCalls = 0;

  @override
  Future<Booking> rescheduleBooking(String id, DateTime newStartAt) async {
    rescheduleCalls.add((id, newStartAt));
    final Failure? err = rescheduleErr;
    if (err != null) throw err;
    return _booking(id, newStartAt);
  }

  @override
  Future<Booking> createBooking(CreateBookingRequest req) async {
    createCalls.add(req);
    return _booking('booking-${req.serviceId}', req.startAt);
  }

  @override
  Future<Booking> getBookingById(String id) async {
    getBookingByIdCalls++;
    return _booking(id, DateTime.utc(2026, 7, 20, 15));
  }

  @override
  Future<PageResponse<Booking>> getMyBookings({
    required BookingStatus? status,
    required int page,
    int size = kBookingsPageSize,
  }) async {
    getMyBookingsCalls++;
    return PageResponse<Booking>(
      items: <Booking>[_booking('booking-1', DateTime.utc(2026, 7, 20, 15))],
      page: page,
      totalPages: 1,
      totalElements: 1,
    );
  }

  @override
  Future<void> cancelBooking(String id, {String? reason}) =>
      throw UnimplementedError();
}

Booking _booking(String id, DateTime start) => Booking(
  id: id,
  masterId: _masterId,
  masterFirstName: 'Софія',
  masterLastName: 'Бондар',
  masterType: 'INDEPENDENT_MASTER',
  serviceId: _serviceId,
  serviceName: 'Манікюр з покриттям',
  durationMinutes: 90,
  price: 650,
  startAt: start,
  endAt: start.add(const Duration(minutes: 90)),
  status: BookingStatus.confirmed,
  canReview: false,
);

const String _masterId = 'master-aaa';
const String _serviceId = 'pub-assign-1';
const String _bookingId = 'booking-1';
final DateTime _newStart = DateTime.utc(2026, 8, 1, 11);

BookingAppointment _appt({String key = 'itest-reschedule-key'}) =>
    BookingAppointment(
      serviceId: _serviceId,
      startAt: _newStart,
      idempotencyKey: key,
    );

ProviderContainer _container(BookingRepository repo) {
  final ProviderContainer c = ProviderContainer(
    overrides: [bookingRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(c.dispose);
  return c;
}

/// Keeps the two invalidation targets alive + resolved, and returns their
/// initial repo-call counts (each == 1 after the first resolve).
Future<void> _warmInvalidationTargets(
  ProviderContainer c,
  _RecordingRepo repo,
) async {
  final ProviderSubscription<AsyncValue<Booking>> subDetail = c.listen(
    bookingDetailProvider(_bookingId),
    (_, _) {},
    fireImmediately: true,
  );
  addTearDown(subDetail.close);
  final ProviderSubscription<AsyncValue<MyBookingsState>> subList = c.listen(
    myBookingsProvider(BookingTab.upcoming),
    (_, _) {},
    fireImmediately: true,
  );
  addTearDown(subList.close);

  await c.read(bookingDetailProvider(_bookingId).future);
  await c.read(myBookingsProvider(BookingTab.upcoming).future);
  expect(repo.getBookingByIdCalls, 1);
  expect(
    repo.getMyBookingsCalls,
    1,
    reason: 'the upcoming tab fans out one fetch (CONFIRMED only)',
  );
}

void main() {
  group('IndependentBookingSubmit.submit — reschedule path', () {
    test('a non-null rescheduleBookingId calls rescheduleBooking (never '
        'createBooking) with the picked start, and on success fires BOTH '
        'invalidations (detail + upcoming list re-fetch)', () async {
      final _RecordingRepo repo = _RecordingRepo();
      final ProviderContainer c = _container(repo);
      await _warmInvalidationTargets(c, repo);

      final List<BookingAppointment> appts = <BookingAppointment>[_appt()];
      final IndependentBookingSubmitState result = await c
          .read(independentBookingSubmitProvider.notifier)
          .submit(_masterId, appts, rescheduleBookingId: _bookingId);

      // The reschedule endpoint was called ONCE with (id, new start); the
      // create endpoint was NEVER touched.
      expect(repo.rescheduleCalls, hasLength(1));
      expect(repo.rescheduleCalls.single.$1, _bookingId);
      expect(repo.rescheduleCalls.single.$2, _newStart);
      expect(
        repo.createCalls,
        isEmpty,
        reason: 'a reschedule must never POST a new booking',
      );

      // The appointment succeeded.
      expect(result.hasFailures, isFalse);
      expect(
        result.statusFor(_serviceId),
        IndependentAppointmentSubmitStatus.succeeded,
      );
      expect(result.allSucceeded(appts), isTrue);

      // Let the listened providers' scheduled rebuilds run, then re-read.
      await Future<void>.delayed(Duration.zero);
      await c.read(bookingDetailProvider(_bookingId).future);
      await c.read(myBookingsProvider(BookingTab.upcoming).future);

      // BOTH invalidations took effect — each target re-fetched exactly once
      // more (a still-listened autoDispose provider only re-fetches when it
      // is invalidated).
      expect(
        repo.getBookingByIdCalls,
        2,
        reason: 'bookingDetailProvider(id) must have been invalidated',
      );
      expect(
        repo.getMyBookingsCalls,
        2,
        reason: 'myBookingsProvider(upcoming) must have been invalidated',
      );
    });

    // 409 / 403 / 400 — whatever mapped Failure the repository throws must
    // surface on the appointment EXACTLY like the create path, and must fire
    // NEITHER invalidation.
    for (final (String label, Failure failure) in <(String, Failure)>[
      ('409 → ConflictFailure', const ConflictFailure()),
      ('403 → ServerFailure(403)', const ServerFailure(statusCode: 403)),
      (
        '400 → ValidationFailure',
        const ValidationFailure(fieldErrors: <String, String>{}),
      ),
    ]) {
      test('a reschedule $label surfaces on the appointment (hasFailures) and '
          'fires no invalidation', () async {
        final _RecordingRepo repo = _RecordingRepo(rescheduleErr: failure);
        final ProviderContainer c = _container(repo);
        await _warmInvalidationTargets(c, repo);

        final List<BookingAppointment> appts = <BookingAppointment>[_appt()];
        final IndependentBookingSubmitState result = await c
            .read(independentBookingSubmitProvider.notifier)
            .submit(_masterId, appts, rescheduleBookingId: _bookingId);

        // The reschedule was attempted once; no create fallback.
        expect(repo.rescheduleCalls, hasLength(1));
        expect(repo.createCalls, isEmpty);

        // The failure landed on the appointment, mapped 1:1.
        expect(result.hasFailures, isTrue);
        expect(result.allSucceeded(appts), isFalse);
        expect(
          result.statusFor(_serviceId),
          IndependentAppointmentSubmitStatus.failed,
        );
        expect(result.failureFor(_serviceId), same(failure));

        // Neither target re-fetched — a failed reschedule refreshes nothing.
        await Future<void>.delayed(Duration.zero);
        expect(
          repo.getBookingByIdCalls,
          1,
          reason: 'a failed reschedule must not invalidate the detail',
        );
        expect(
          repo.getMyBookingsCalls,
          1,
          reason: 'a failed reschedule must not invalidate the upcoming list',
        );
      });
    }
  });
}
