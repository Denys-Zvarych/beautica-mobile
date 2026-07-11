// Phase 14.18 — Unit tests for SalonBookingSubmit (the salon confirmation
// screen's N-booking submit notifier).
//
// Covers the phase's non-negotiable submit contract:
//   1. All-succeed → every appointment marked succeeded + `allSucceeded` true,
//      exactly ONE `createBooking` per master.
//   2. One-of-N fails (409 → ConflictFailure) → the pass STAYS partial:
//      `allSucceeded` false, the failed master flagged with its mapped
//      Failure, the succeeded ones marked succeeded.
//   3. Retry re-submits ONLY the still-failed appointment — an already-
//      succeeded master is NEVER re-POSTed (asserted via per-master call
//      counts), and the retried call reuses the appointment's STABLE
//      idempotency key.
//   4. Failure mapping: a repo `NetworkFailure` is kept as-is; a raw
//      (non-Failure) exception is wrapped as `UnknownFailure`.
//
// Strategy: a fresh `ProviderContainer` per test overriding
// `bookingRepositoryProvider` with a hand-written recording fake (mirrors the
// `_FakeBookingRepository` precedent in `booking_confirm_test.dart`) — no
// mocktail, no real Dio. Every container is disposed via `addTearDown` (M1).

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/features/booking/application/salon_booking_submit_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/create_booking_request.dart';
import 'package:beautica_mobile/features/booking/domain/salon_booking_confirm_args.dart';
import 'package:beautica_mobile/features/booking/domain/salon_master_schedule.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Recording fake — records every createBooking request + optionally throws a
// configured Failure/exception for a given master.
// ---------------------------------------------------------------------------

class _RecordingBookingRepository implements BookingRepository {
  _RecordingBookingRepository({Map<String, Object> failFor = const {}})
    : _failFor = <String, Object>{...failFor};

  final Map<String, Object> _failFor;
  final List<CreateBookingRequest> requests = <CreateBookingRequest>[];

  /// Stops failing [masterId] so a retry pass succeeds for it.
  void stopFailing(String masterId) => _failFor.remove(masterId);

  int callsFor(String masterId) =>
      requests.where((CreateBookingRequest r) => r.masterId == masterId).length;

  List<CreateBookingRequest> requestsFor(String masterId) => requests
      .where((CreateBookingRequest r) => r.masterId == masterId)
      .toList(growable: false);

  @override
  Future<Booking> createBooking(CreateBookingRequest req) async {
    requests.add(req);
    final Object? err = _failFor[req.masterId];
    if (err != null) throw err;
    return _bookingFor(req);
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

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

final DateTime _kStart = DateTime(2026, 7, 20, 14);

Booking _bookingFor(CreateBookingRequest req) => Booking(
  id: 'booking-${req.masterId}',
  masterId: req.masterId,
  masterFirstName: 'Олена',
  masterLastName: 'Ковальчук',
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

SalonMasterSchedule _schedule(String masterId) => SalonMasterSchedule(
  masterId: masterId,
  firstName: 'Олена',
  lastName: 'Ковальчук',
  type: MasterType.independentMaster,
  services: <SalonCatalogService>[
    SalonCatalogService(
      id: 'svc-$masterId',
      name: 'Манікюр',
      durationLabel: '1 год',
      priceDisplay: '500 грн',
      durationMinutes: 60,
      priceType: ServicePriceType.fixed,
      priceMin: 500,
    ),
  ],
  // Master-scoped assignment id — the id the booking-write must carry, never
  // the salon-wide catalog id.
  primaryServiceAssignmentId: 'assign-$masterId',
);

/// One appointment for [masterId] with a STABLE idempotency key defaulting to
/// `key-<masterId>` (overridable) so retry-reuse can be asserted precisely.
SalonBookingAppointment _appt(String masterId, {String? key}) =>
    SalonBookingAppointment(
      schedule: _schedule(masterId),
      startAt: _kStart,
      idempotencyKey: key ?? 'key-$masterId',
    );

ProviderContainer _container(BookingRepository repo) {
  final ProviderContainer c = ProviderContainer(
    overrides: [bookingRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('SalonBookingSubmit.submit', () {
    test(
      'all-succeed: every appointment marked succeeded, allSucceeded true, one '
      'createBooking per master carrying the master-scoped assignment id + '
      'stable key + startAt',
      () async {
        final _RecordingBookingRepository repo = _RecordingBookingRepository();
        final ProviderContainer c = _container(repo);
        final List<SalonBookingAppointment> appts = <SalonBookingAppointment>[
          _appt('m1'),
          _appt('m2'),
        ];

        final SalonBookingSubmitState result = await c
            .read(salonBookingSubmitProvider.notifier)
            .submit(appts);

        expect(result.allSucceeded(appts), isTrue);
        expect(result.statusFor('m1'), SalonAppointmentSubmitStatus.succeeded);
        expect(result.statusFor('m2'), SalonAppointmentSubmitStatus.succeeded);
        expect(result.hasFailures, isFalse);
        expect(result.inFlight, isFalse);
        // The public provider state reflects the same terminal snapshot.
        expect(c.read(salonBookingSubmitProvider).allSucceeded(appts), isTrue);

        // Exactly one call per master, never a fan-out or a re-send.
        expect(repo.callsFor('m1'), 1);
        expect(repo.callsFor('m2'), 1);

        // Correctness: the write carries the master-scoped ASSIGNMENT id
        // (not the catalog id), the chosen start, and the stable key.
        final CreateBookingRequest m1 = repo.requestsFor('m1').single;
        expect(m1.serviceId, 'assign-m1');
        expect(m1.startAt, _kStart);
        expect(m1.idempotencyKey, 'key-m1');
      },
    );

    test(
      'one-of-N fails (409 → ConflictFailure): pass stays partial — the failed '
      'master is flagged with its mapped Failure, the succeeded one is marked '
      'succeeded, allSucceeded is false',
      () async {
        final _RecordingBookingRepository repo = _RecordingBookingRepository(
          failFor: <String, Object>{'m2': const ConflictFailure()},
        );
        final ProviderContainer c = _container(repo);
        final List<SalonBookingAppointment> appts = <SalonBookingAppointment>[
          _appt('m1'),
          _appt('m2'),
        ];

        final SalonBookingSubmitState result = await c
            .read(salonBookingSubmitProvider.notifier)
            .submit(appts);

        expect(result.allSucceeded(appts), isFalse);
        expect(result.hasFailures, isTrue);
        expect(result.statusFor('m1'), SalonAppointmentSubmitStatus.succeeded);
        expect(result.statusFor('m2'), SalonAppointmentSubmitStatus.failed);
        expect(result.failureFor('m2'), isA<ConflictFailure>());
        expect(
          result.failureFor('m1'),
          isNull,
          reason: 'a succeeded appointment carries no failure',
        );
      },
    );

    test('retry re-submits ONLY the still-failed appointment — the already-'
        'succeeded master is never re-POSTed, and the retried call reuses its '
        'STABLE idempotency key', () async {
      final _RecordingBookingRepository repo = _RecordingBookingRepository(
        failFor: <String, Object>{'m2': const ConflictFailure()},
      );
      final ProviderContainer c = _container(repo);
      final SalonBookingSubmit notifier = c.read(
        salonBookingSubmitProvider.notifier,
      );
      final List<SalonBookingAppointment> appts = <SalonBookingAppointment>[
        _appt('m1', key: 'key-m1'),
        _appt('m2', key: 'key-m2'),
      ];

      // First pass: m1 succeeds, m2 fails.
      final SalonBookingSubmitState first = await notifier.submit(appts);
      expect(first.allSucceeded(appts), isFalse);
      expect(repo.callsFor('m1'), 1);
      expect(repo.callsFor('m2'), 1);

      // Retry: m2 now succeeds.
      repo.stopFailing('m2');
      final SalonBookingSubmitState retry = await notifier.submit(appts);

      expect(retry.allSucceeded(appts), isTrue);
      expect(
        repo.callsFor('m1'),
        1,
        reason: 'the already-succeeded m1 must NOT be re-POSTed on retry',
      );
      expect(
        repo.callsFor('m2'),
        2,
        reason: 'only the previously-failed m2 is re-submitted',
      );

      // Stable idempotency key: both of m2's calls carry the SAME key, so an
      // ambiguously-failed booking de-duplicates server-side.
      expect(
        repo
            .requestsFor('m2')
            .map((CreateBookingRequest r) => r.idempotencyKey)
            .toSet(),
        <String>{'key-m2'},
      );
    });

    test(
      'a repo NetworkFailure is surfaced as-is on the failed appointment',
      () async {
        final _RecordingBookingRepository repo = _RecordingBookingRepository(
          failFor: <String, Object>{'m1': const NetworkFailure()},
        );
        final ProviderContainer c = _container(repo);

        final SalonBookingSubmitState result = await c
            .read(salonBookingSubmitProvider.notifier)
            .submit(<SalonBookingAppointment>[_appt('m1')]);

        expect(result.statusFor('m1'), SalonAppointmentSubmitStatus.failed);
        expect(result.failureFor('m1'), isA<NetworkFailure>());
      },
    );

    test(
      'a raw (non-Failure) exception is wrapped as UnknownFailure',
      () async {
        final _RecordingBookingRepository repo = _RecordingBookingRepository(
          failFor: <String, Object>{'m1': Exception('boom')},
        );
        final ProviderContainer c = _container(repo);

        final SalonBookingSubmitState result = await c
            .read(salonBookingSubmitProvider.notifier)
            .submit(<SalonBookingAppointment>[_appt('m1')]);

        expect(result.statusFor('m1'), SalonAppointmentSubmitStatus.failed);
        expect(result.failureFor('m1'), isA<UnknownFailure>());
      },
    );
  });

  // ---------------------------------------------------------------------------
  // hasSucceeded — the getter that drives the confirm screen's back-navigation
  // guard (PopScope.canPop == !hasSucceeded). Once ANY appointment's `POST
  // /bookings` has landed, leaving+re-entering the step-3 picker would re-mint
  // fresh idempotency keys for the already-created bookings, so back must be
  // blocked. It must therefore be false while everything is pending/failed and
  // flip true the instant one appointment succeeds.
  // ---------------------------------------------------------------------------
  group('SalonBookingSubmitState.hasSucceeded', () {
    test('is false for a fresh state (every appointment still pending)', () {
      const SalonBookingSubmitState state = SalonBookingSubmitState();
      expect(state.hasSucceeded, isFalse);
    });

    test('is false when every attempted appointment failed', () {
      const SalonBookingSubmitState state = SalonBookingSubmitState(
        statusByMaster: <String, SalonAppointmentSubmitStatus>{
          'm1': SalonAppointmentSubmitStatus.failed,
          'm2': SalonAppointmentSubmitStatus.failed,
        },
      );
      expect(state.hasSucceeded, isFalse);
    });

    test('is false while a pass is in flight and nothing has landed yet', () {
      const SalonBookingSubmitState state = SalonBookingSubmitState(
        statusByMaster: <String, SalonAppointmentSubmitStatus>{
          'm1': SalonAppointmentSubmitStatus.submitting,
          'm2': SalonAppointmentSubmitStatus.submitting,
        },
        inFlight: true,
      );
      expect(state.hasSucceeded, isFalse);
    });

    test('flips to true the moment any single appointment succeeds', () {
      const SalonBookingSubmitState state = SalonBookingSubmitState(
        statusByMaster: <String, SalonAppointmentSubmitStatus>{
          'm1': SalonAppointmentSubmitStatus.succeeded,
          'm2': SalonAppointmentSubmitStatus.failed,
        },
      );
      expect(state.hasSucceeded, isTrue);
    });

    test('after a partial-success submit pass the live notifier state reports '
        'hasSucceeded true (this is what the back guard reads)', () async {
      final _RecordingBookingRepository repo = _RecordingBookingRepository(
        failFor: <String, Object>{'m2': const ConflictFailure()},
      );
      final ProviderContainer c = _container(repo);

      final SalonBookingSubmitState result = await c
          .read(salonBookingSubmitProvider.notifier)
          .submit(<SalonBookingAppointment>[_appt('m1'), _appt('m2')]);

      expect(result.hasSucceeded, isTrue);
      expect(c.read(salonBookingSubmitProvider).hasSucceeded, isTrue);
    });

    test(
      'after an all-failed submit pass hasSucceeded stays false (back is still '
      'free to pop)',
      () async {
        final _RecordingBookingRepository repo = _RecordingBookingRepository(
          failFor: <String, Object>{
            'm1': const NetworkFailure(),
            'm2': const NetworkFailure(),
          },
        );
        final ProviderContainer c = _container(repo);

        final SalonBookingSubmitState result = await c
            .read(salonBookingSubmitProvider.notifier)
            .submit(<SalonBookingAppointment>[_appt('m1'), _appt('m2')]);

        expect(result.hasSucceeded, isFalse);
        expect(c.read(salonBookingSubmitProvider).hasSucceeded, isFalse);
      },
    );
  });
}
