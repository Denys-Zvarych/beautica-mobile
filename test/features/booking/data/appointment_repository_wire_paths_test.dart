// Phase 476 regression guard. B475 retired the whole-visit
// `PATCH /appointments/{id}/cancel|decline|complete|reschedule` routes; the
// live repository actions must hit ONLY the per-service
// `/appointments/{appointmentId}/services/{bookingId}/…` routes. The sibling
// `appointment_repository_test.dart` mocks the generated API, so it cannot see
// the URL — this file drives the REAL generated `AppointmentControllerApi`
// through `HttpAppointmentRepository` over a recording Dio adapter.
import 'dart:convert';
import 'dart:typed_data';

import 'package:beautica_api/beautica_api.dart' show standardSerializers;
import 'package:beautica_api/src/api/appointment_controller_api.dart';
import 'package:beautica_mobile/features/booking/data/appointment_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Detail-shaped body so the reschedule response deserialises + maps.
Map<String, dynamic> _visitJson() => <String, dynamic>{
  'id': 'appt-1',
  'status': 'CONFIRMED',
  'masterId': 'master-aaa',
  'masterFirstName': 'Софія',
  'masterLastName': 'Бондар',
  'masterType': 'INDEPENDENT_MASTER',
  // future-date-ok: pinned deserialization INPUT — the fixed wire string IS the assertion; the mapper under test never reads the wall clock.
  'startsAt': '2026-08-14T10:00:00Z',
  // future-date-ok: pinned deserialization INPUT — the fixed wire string IS the assertion; the mapper under test never reads the wall clock.
  'endsAt': '2026-08-14T11:30:00Z',
  'totalDurationMinutes': 90,
  'totalPrice': 500,
  'totalPriceMax': null,
  'canReview': false,
  'items': <Map<String, dynamic>>[
    <String, dynamic>{
      'bookingId': 'b-1',
      'masterServiceId': 'assign-b-1',
      'serviceName': 'Манікюр з покриттям',
      'status': 'CONFIRMED',
      // future-date-ok: pinned deserialization INPUT — the fixed wire string IS the assertion; the mapper under test never reads the wall clock.
      'startsAt': '2026-08-14T10:00:00Z',
      // future-date-ok: pinned deserialization INPUT — the fixed wire string IS the assertion; the mapper under test never reads the wall clock.
      'endsAt': '2026-08-14T11:30:00Z',
      'durationMinutesAtBooking': 90,
      'priceAtBooking': 500,
      'priceMaxAtBooking': null,
    },
  ],
};

class _RecordingAdapter implements HttpClientAdapter {
  final List<RequestOptions> seen = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seen.add(options);
    final bool isReschedule = options.path.endsWith('/reschedule');
    return ResponseBody.fromString(
      jsonEncode(<String, Object?>{
        'success': true,
        'data': isReschedule ? _visitJson() : null,
      }),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _RecordingAdapter adapter;
  late HttpAppointmentRepository repository;

  setUp(() {
    adapter = _RecordingAdapter();
    final Dio dio = Dio(BaseOptions(baseUrl: ''))..httpClientAdapter = adapter;
    repository = HttpAppointmentRepository(
      AppointmentControllerApi(dio, standardSerializers),
    );
  });

  test(
    'completeAppointmentService PATCHes the per-service /complete route only',
    () async {
      await repository.completeAppointmentService('appt-1', 'b-1');

      expect(adapter.seen, hasLength(1));
      expect(adapter.seen.single.method, 'PATCH');
      expect(
        adapter.seen.single.path,
        '/api/v1/appointments/appt-1/services/b-1/complete',
      );
    },
  );

  test(
    'declineAppointmentService PATCHes the per-service /decline route with a '
    'trimmed providerComment',
    () async {
      await repository.declineAppointmentService(
        'appt-1',
        'b-1',
        comment: '  sick  ',
      );

      expect(adapter.seen, hasLength(1));
      final RequestOptions req = adapter.seen.single;
      expect(req.method, 'PATCH');
      expect(req.path, '/api/v1/appointments/appt-1/services/b-1/decline');
      expect((req.data as Map<String, dynamic>)['providerComment'], 'sick');
    },
  );

  test(
    'rescheduleAppointmentItem PATCHes the per-service /reschedule route only',
    () async {
      await repository.rescheduleAppointmentItem(
        'appt-1',
        'b-1',
        // future-date-ok: pinned request INPUT — only the route is asserted.
        DateTime.utc(2026, 8, 15, 10),
      );

      expect(adapter.seen, hasLength(1));
      expect(adapter.seen.single.method, 'PATCH');
      expect(
        adapter.seen.single.path,
        '/api/v1/appointments/appt-1/services/b-1/reschedule',
      );
    },
  );

  test('no repository action ever hits a whole-visit mutation route', () async {
    // Drives EVERY mutating method on HttpAppointmentRepository. Per-service
    // cancel has no method on this repository (it lives on BookingRepository),
    // so it is intentionally not driven here.
    await repository.completeAppointmentService('appt-1', 'b-1');
    await repository.declineAppointmentService('appt-1', 'b-1');
    await repository.rescheduleAppointmentItem(
      'appt-1',
      'b-1',
      // future-date-ok: pinned request INPUT — only the route is asserted.
      DateTime.utc(2026, 8, 15, 10),
    );

    final Iterable<String> mutating = adapter.seen
        .where((RequestOptions r) => r.method == 'PATCH')
        .map((RequestOptions r) => r.path);
    expect(mutating, hasLength(3));
    for (final String p in mutating) {
      expect(p, contains('/services/'), reason: 'whole-visit route: $p');
    }
  });
}
