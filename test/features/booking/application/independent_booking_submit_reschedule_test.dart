// mobile-qa (track 24.x booking auto-confirm) — Unit tests for
// [IndependentBookingSubmit.submit] on the RESCHEDULE path.
//
// The create path is covered by booking_confirm_test.dart +
// independent_multi_service_booking_flow_test.dart. This suite pins the
// reschedule-specific contract the notifier OWNS:
//
//   1. A non-null `rescheduleBookingId` submit calls
//      `BookingRepository.rescheduleBooking(id, startAt)` — NEVER
//      `createBooking` — and, on success, surfaces the single appointment as
//      SUCCEEDED (`hasSucceeded` / `allSucceeded`).
//   2. A per-appointment failure (409 / 403 / 400, whatever mapped Failure the
//      repository throws) surfaces on that appointment EXACTLY like the create
//      path — `failureFor(serviceId)` set, `hasFailures` true — with NO create
//      fallback.
//
// MOVED OUT OF THIS NOTIFIER (track 24.x follow-up): the post-reschedule
// REFETCH of the moved booking's detail + the upcoming My Bookings list is no
// longer fired here. Cross-provider `ref.invalidate(...)` from inside a Notifier
// can close a watch cycle (`CircularDependencyError`, debug-only) — the
// `forbid_provider_self_invalidation` CI gate's footgun — so that refetch was
// relocated to the WIDGET layer (`BookingConfirmScreen._submit`), mirroring how
// the cancel flow refreshes the same providers in
// `booking_detail_screen._confirmCancel`. Its coverage now lives in the
// "successful RESCHEDULE invalidates bookingDetail + upcoming My Bookings"
// widget test in `booking_confirm_test.dart`. This suite therefore asserts only
// what the notifier itself still owns (which endpoint is hit + how each
// appointment's outcome is surfaced), never an invalidation side effect.
//
// Strategy: a fresh `ProviderContainer` per test (M1 — disposed via
// addTearDown) overriding `bookingRepositoryProvider` with a hand-written
// recording fake.

import 'package:dio/dio.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/features/booking/application/booking_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_appointment.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/create_booking_request.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Recording fake — records reschedule + create calls. `rescheduleErr` makes the
// NEXT rescheduleBooking throw the given Failure. The read endpoints are never
// exercised by the notifier (the refetch now lives in the widget layer), so
// they throw UnimplementedError.
// ---------------------------------------------------------------------------

class _RecordingRepo implements BookingRepository {
  _RecordingRepo({this.rescheduleErr});

  Failure? rescheduleErr;

  final List<(String, DateTime)> rescheduleCalls = <(String, DateTime)>[];
  final List<CreateBookingRequest> createCalls = <CreateBookingRequest>[];

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
  Future<List<DateTime>> getMyBookedDays({
    required DateTime from,
    required DateTime to,
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

void main() {
  group('IndependentBookingSubmit.submit — reschedule path', () {
    test('a non-null rescheduleBookingId calls rescheduleBooking (never '
        'createBooking) with the picked start, and surfaces the appointment '
        'as succeeded', () async {
      final _RecordingRepo repo = _RecordingRepo();
      final ProviderContainer c = _container(repo);

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

      // The appointment succeeded — the notifier's own observable contract.
      expect(result.hasFailures, isFalse);
      expect(result.hasSucceeded, isTrue);
      expect(
        result.statusFor(_serviceId),
        IndependentAppointmentSubmitStatus.succeeded,
      );
      expect(result.allSucceeded(appts), isTrue);
    });

    // 409 / 403 / 400 — whatever mapped Failure the repository throws must
    // surface on the appointment EXACTLY like the create path, with no create
    // fallback.
    for (final (String label, Failure failure) in <(String, Failure)>[
      ('409 → ConflictFailure', const ConflictFailure()),
      ('403 → ServerFailure(403)', const ServerFailure(statusCode: 403)),
      (
        '400 → ValidationFailure',
        const ValidationFailure(fieldErrors: <String, String>{}),
      ),
    ]) {
      test('a reschedule $label surfaces on the appointment (hasFailures) with '
          'no create fallback', () async {
        final _RecordingRepo repo = _RecordingRepo(rescheduleErr: failure);
        final ProviderContainer c = _container(repo);

        final List<BookingAppointment> appts = <BookingAppointment>[_appt()];
        final IndependentBookingSubmitState result = await c
            .read(independentBookingSubmitProvider.notifier)
            .submit(_masterId, appts, rescheduleBookingId: _bookingId);

        // The reschedule was attempted once; no create fallback.
        expect(repo.rescheduleCalls, hasLength(1));
        expect(repo.createCalls, isEmpty);

        // The failure landed on the appointment, mapped 1:1.
        expect(result.hasFailures, isTrue);
        expect(result.hasSucceeded, isFalse);
        expect(result.allSucceeded(appts), isFalse);
        expect(
          result.statusFor(_serviceId),
          IndependentAppointmentSubmitStatus.failed,
        );
        expect(result.failureFor(_serviceId), same(failure));
      });
    }
  });
}
