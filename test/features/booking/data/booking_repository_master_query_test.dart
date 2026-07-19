// Phase 7.1 — the `queryParameters` MAP the repository hands to Dio for the
// widened `GET /bookings/me` + the new `GET /bookings/me/booked-days`.
//
// SCOPE — READ THIS BEFORE TRUSTING A GREEN RUN
// ---------------------------------------------------------------------------
// These tests capture the map passed to a **mocktail [Dio]**. A mock never runs
// Dio's own serialisation, so NOTHING here observes the emitted URL: this file
// cannot tell you whether a `List<String>` renders as `?status=A&status=B` or
// as `?status[]=A&status[]=B`. It pins one layer earlier — that the repository
// builds the right VALUES with the right TYPES:
//
//   * `status` / `serviceId` arrive as a `List<String>` (not a comma-joined
//     string), in canonical order, with `BookingStatus.unknown` stripped and
//     the param omitted entirely when the filter is empty.
//   * Date bounds are formatted `yyyy-MM-dd` — never `toIso8601String()` (a
//     timestamp, rejected) and never `.toUtc()` (shifts the day east of UTC:
//     accepted, and wrong).
//   * Every emitted `sort` value targets a property inside the backend's
//     Phase 26.6 whitelist; anything else now 400s.
//
// None of those surface as a Dart error, which is why the map is asserted
// directly.
//
// The URL-level guarantee lives in a SEPARATE file:
// `booking_repository_listformat_test.dart` drives a REAL [Dio] and asserts
// `RequestOptions.uri`, pinning the `ListFormat` that decides whether the
// `List<String>` this file checks becomes `?status=A&status=B` (correct) or
// `?status[]=A&status[]=B` (which Spring binds to a param named `status[]`,
// silently dropping the filter and returning unfiltered 200s). If you are
// changing list serialisation or `dio_provider.dart`'s `BaseOptions`, that is
// the file that will catch you — not this one.

import 'package:beautica_api/beautica_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/bookings_day_query.dart';

class _MockDio extends Mock implements Dio {}

class _MockBookingApi extends Mock implements BookingControllerApi {}

class _MockReviewApi extends Mock implements ReviewControllerApi {}

const String _myBookingsPath = '/api/v1/bookings/me';
const String _bookedDaysPath = '/api/v1/bookings/me/booked-days';

/// An empty-but-well-formed `ApiResponse<PageResponse<BookingDetailResponse>>`
/// envelope — these tests care about the REQUEST, so the response only has to
/// deserialize.
Map<String, dynamic> _emptyPageEnvelope() => <String, dynamic>{
  'data': <String, dynamic>{
    'data': <dynamic>[],
    'page': 0,
    'size': 20,
    'totalElements': 0,
    'totalPages': 0,
  },
};

void main() {
  late _MockDio dio;
  late HttpBookingRepository repository;

  setUp(() {
    dio = _MockDio();
    repository = HttpBookingRepository(
      dio,
      _MockBookingApi(),
      _MockReviewApi(),
    );
  });

  /// Runs [call] against a stubbed 200 and returns the query map Dio was
  /// handed.
  Future<Map<String, dynamic>> capturedQuery(
    String path,
    Future<void> Function() call, {
    Object? responseData,
  }) async {
    when(
      () => dio.get<Map<String, dynamic>>(
        path,
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer(
      (_) async => Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: (responseData ?? _emptyPageEnvelope()) as Map<String, dynamic>,
      ),
    );

    await call();

    return verify(
          () => dio.get<Map<String, dynamic>>(
            path,
            queryParameters: captureAny(named: 'queryParameters'),
          ),
        ).captured.single
        as Map<String, dynamic>;
  }

  group('getMyBookings — repeated status params (backend 26.1)', () {
    test(
      'multiple statuses are passed as a LIST value — the precondition Dio\'s '
      'default ListFormat.multi needs to emit ?status=A&status=B '
      '(the emitted URL itself is pinned in '
      'booking_repository_listformat_test.dart)',
      () async {
        final q = await capturedQuery(
          _myBookingsPath,
          () => repository.getMyBookings(
            statuses: <BookingStatus>{
              BookingStatus.declined,
              BookingStatus.confirmed,
            },
            page: 0,
          ),
        );

        // A List (not a comma-joined String, not a Map) is what lets Dio emit
        // repeated bare `status=` params. That it ACTUALLY does so is not
        // observable here — a mock Dio never serialises.
        expect(q['status'], isA<List<String>>());
        expect(q['status'], <String>['CONFIRMED', 'DECLINED']);
      },
    );

    test('status order is CANONICAL — the same filter built in the opposite '
        'order produces the identical query map', () async {
      final a = await capturedQuery(
        _myBookingsPath,
        () => repository.getMyBookings(
          statuses: <BookingStatus>{
            BookingStatus.notCompleted,
            BookingStatus.cancelled,
          },
          page: 0,
        ),
      );
      final b = await capturedQuery(
        _myBookingsPath,
        () => repository.getMyBookings(
          statuses: <BookingStatus>{
            BookingStatus.cancelled,
            BookingStatus.notCompleted,
          },
          page: 0,
        ),
      );

      expect(a['status'], equals(b['status']));
    });

    test('an empty status set omits the param entirely (no filter)', () async {
      final q = await capturedQuery(
        _myBookingsPath,
        () => repository.getMyBookings(
          statuses: const <BookingStatus>{},
          page: 0,
        ),
      );

      expect(q.containsKey('status'), isFalse);
    });

    test(
      'all five FILTERABLE statuses fit the backend\'s @Size(max = 5) cap',
      () async {
        final q = await capturedQuery(
          _myBookingsPath,
          () => repository.getMyBookings(
            // `filterable`, not `values` — `values` also carries the decode-only
            // `BookingStatus.unknown`, which would be a 6th param AND a literal
            // `status=UNKNOWN` the backend 400s on.
            statuses: BookingStatus.filterable,
            page: 0,
          ),
        );

        expect((q['status'] as List<String>).length, 5);
        expect(q['status'], isNot(contains('UNKNOWN')));
      },
    );

    test('BookingStatus.unknown is STRIPPED from the status filter rather '
        'than serialised as a 400-inducing status=UNKNOWN', () async {
      final q = await capturedQuery(
        _myBookingsPath,
        () => repository.getMyBookings(
          statuses: <BookingStatus>[
            BookingStatus.confirmed,
            BookingStatus.unknown,
          ],
          page: 0,
        ),
      );

      expect(q['status'], <String>['CONFIRMED']);
    });

    test('an all-unknown status filter omits the param entirely rather than '
        'passing an empty one', () async {
      final q = await capturedQuery(
        _myBookingsPath,
        () => repository.getMyBookings(
          statuses: <BookingStatus>[BookingStatus.unknown],
          page: 0,
        ),
      );

      expect(q.containsKey('status'), isFalse);
    });

    // Perf P5 — the notifier now passes the query's canonical Lists straight
    // through instead of round-tripping them via `.toSet()`, and the
    // repository's own canonicalisation sorts by enum INDEX (it used to sort
    // by wire STRING, so the query's canonical order was reshuffled on the
    // way into the request). This pins that the two agree — i.e. the
    // repository's sort is now idempotent on a query built through `.of()`.
    // `BookingsDayQuery` (Phase 7.9) carries the identical canonicalisation
    // forward from the retired `MasterBookingsQuery`.
    test('the query\'s canonical list order reaches the query map unchanged '
        '(both sorts order by enum index)', () async {
      final BookingsDayQuery query = BookingsDayQuery.of(
        day: DateTime(2026, 7, 20),
        statuses: <BookingStatus>{
          // Deliberately NOT in declaration order.
          BookingStatus.notCompleted,
          BookingStatus.confirmed,
          BookingStatus.declined,
        },
      );

      final q = await capturedQuery(
        _myBookingsPath,
        () => repository.getMyBookings(statuses: query.statuses, page: 0),
      );

      // `.of()` sorted by index → confirmed(0), declined(2), notCompleted(4).
      expect(query.statuses, <BookingStatus>[
        BookingStatus.confirmed,
        BookingStatus.declined,
        BookingStatus.notCompleted,
      ]);
      // …and that exact order is what reached the query map.
      expect(q['status'], <String>['CONFIRMED', 'DECLINED', 'NOT_COMPLETED']);
    });
  });

  group('getMyBookings — serviceId params (backend 26.4)', () {
    test('multiple serviceIds serialise as a sorted LIST value', () async {
      final q = await capturedQuery(
        _myBookingsPath,
        () => repository.getMyBookings(
          statuses: const <BookingStatus>{},
          serviceIds: <String>{'svc-zebra', 'svc-alpha'},
          page: 0,
        ),
      );

      expect(q['serviceId'], isA<List<String>>());
      expect(q['serviceId'], <String>['svc-alpha', 'svc-zebra']);
    });

    test('a null or empty serviceId set omits the param', () async {
      final nullQ = await capturedQuery(
        _myBookingsPath,
        () => repository.getMyBookings(
          statuses: const <BookingStatus>{},
          page: 0,
        ),
      );
      final emptyQ = await capturedQuery(
        _myBookingsPath,
        () => repository.getMyBookings(
          statuses: const <BookingStatus>{},
          serviceIds: const <String>{},
          page: 0,
        ),
      );

      expect(nullQ.containsKey('serviceId'), isFalse);
      expect(emptyQ.containsKey('serviceId'), isFalse);
    });
  });

  group('getMyBookings — date range (backend 26.2)', () {
    test('bounds serialise as yyyy-MM-dd, never a timestamp', () async {
      final q = await capturedQuery(
        _myBookingsPath,
        () => repository.getMyBookings(
          statuses: const <BookingStatus>{},
          from: DateTime(2026, 7, 1),
          to: DateTime(2026, 7, 31),
          page: 0,
        ),
      );

      expect(q['from'], '2026-07-01');
      expect(q['to'], '2026-07-31');
    });

    test('single-digit months and days are zero-padded', () async {
      final q = await capturedQuery(
        _myBookingsPath,
        () => repository.getMyBookings(
          statuses: const <BookingStatus>{},
          from: DateTime(2026, 1, 5),
          to: DateTime(2026, 9, 9),
          page: 0,
        ),
      );

      expect(q['from'], '2026-01-05');
      expect(q['to'], '2026-09-09');
    });

    test('a bound one minute before local midnight keeps its OWN day — the '
        'UTC day-shift regression guard', () async {
      // The bug this pins: `.toUtc().toIso8601String()` on a UTC+3 device turns
      // 2026-07-18T23:59 local into 2026-07-18T20:59Z — same day here, but
      // 2026-07-19T00:30 local becomes 2026-07-18T21:30Z, i.e. the PREVIOUS
      // day, and the user's «today» filter silently loses today's bookings.
      final q = await capturedQuery(
        _myBookingsPath,
        () => repository.getMyBookings(
          statuses: const <BookingStatus>{},
          from: DateTime(2026, 7, 18, 23, 59),
          to: DateTime(2026, 7, 19, 0, 30),
          page: 0,
        ),
      );

      expect(q['from'], '2026-07-18');
      expect(q['to'], '2026-07-19');
    });

    test('each bound is independently optional', () async {
      final fromOnly = await capturedQuery(
        _myBookingsPath,
        () => repository.getMyBookings(
          statuses: const <BookingStatus>{},
          from: DateTime(2026, 7, 1),
          page: 0,
        ),
      );
      final toOnly = await capturedQuery(
        _myBookingsPath,
        () => repository.getMyBookings(
          statuses: const <BookingStatus>{},
          to: DateTime(2026, 7, 31),
          page: 0,
        ),
      );

      expect(fromOnly['from'], '2026-07-01');
      expect(fromOnly.containsKey('to'), isFalse);
      expect(toOnly['to'], '2026-07-31');
      expect(toOnly.containsKey('from'), isFalse);
    });
  });

  group('getMyBookings — sort (backend 26.3 / whitelist 26.6)', () {
    for (final (BookingSort sort, String wire) in <(BookingSort, String)>[
      (BookingSort.newest, 'startsAt,desc'),
      (BookingSort.oldest, 'startsAt,asc'),
      // Phase 7.8 retired the `priceAtBooking,*` members with the sort UI.
      // This list is exhaustive over `BookingSort` on purpose — a new member
      // added without a wire mapping should show up as a gap here.
    ]) {
      test('$sort maps to the sort value $wire', () async {
        final q = await capturedQuery(
          _myBookingsPath,
          () => repository.getMyBookings(
            statuses: const <BookingStatus>{},
            sort: sort,
            page: 0,
          ),
        );

        expect(q['sort'], wire);
      });
    }

    test('a null sort omits the param, deferring to the backend '
        '@PageableDefault', () async {
      final q = await capturedQuery(
        _myBookingsPath,
        () => repository.getMyBookings(
          statuses: const <BookingStatus>{},
          page: 0,
        ),
      );

      expect(q.containsKey('sort'), isFalse);
    });

    test('every BookingSort targets a whitelisted property — anything else '
        'now 400s (backend 26.6 removed createdAt)', () {
      for (final BookingSort s in BookingSort.values) {
        final String property = s.wireValue.split(',').first;
        expect(
          property,
          anyOf('startsAt', 'priceAtBooking'),
          reason: '$s targets "$property", which is off the 26.6 whitelist',
        );
      }
    });
  });

  group('getMyBookings — combined filter shape', () {
    test('every filter travels in ONE request', () async {
      final q = await capturedQuery(
        _myBookingsPath,
        () => repository.getMyBookings(
          statuses: <BookingStatus>{
            BookingStatus.confirmed,
            BookingStatus.completed,
          },
          serviceIds: <String>{'svc-b', 'svc-a'},
          from: DateTime(2026, 7, 1),
          to: DateTime(2026, 7, 31),
          sort: BookingSort.oldest,
          page: 2,
        ),
      );

      expect(q, <String, dynamic>{
        'page': 2,
        'size': kBookingsPageSize,
        'sort': 'startsAt,asc',
        // Perf P5 — statuses are canonicalised by enum INDEX (confirmed(0)
        // before completed(1)), matching `MasterBookingsQuery.of`. This used
        // to read ['COMPLETED', 'CONFIRMED'] because the repository sorted by
        // wire STRING instead, which reshuffled the query's canonical order on
        // the way into the request. Both orders are equally valid to the
        // backend; the point is that exactly one of them is produced, always.
        // serviceIds stay lexicographic — they are opaque ids with no other
        // natural order.
        'status': <String>['CONFIRMED', 'COMPLETED'],
        'serviceId': <String>['svc-a', 'svc-b'],
        'from': '2026-07-01',
        'to': '2026-07-31',
      });
    });
  });

  group('getMyBookedDays (backend 26.5)', () {
    Map<String, dynamic> daysEnvelope(List<String> days) => <String, dynamic>{
      'data': days,
    };

    test('passes both bounds as yyyy-MM-dd', () async {
      final q = await capturedQuery(
        _bookedDaysPath,
        () => repository.getMyBookedDays(
          from: DateTime(2026, 1, 20),
          to: DateTime(2026, 12, 5),
        ),
        responseData: daysEnvelope(const <String>[]),
      );

      expect(q, <String, dynamic>{'from': '2026-01-20', 'to': '2026-12-05'});
    });

    test('parses bare day strings into LOCAL date-only DateTimes', () async {
      when(
        () => dio.get<Map<String, dynamic>>(
          _bookedDaysPath,
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: _bookedDaysPath),
          statusCode: 200,
          data: daysEnvelope(const <String>['2026-07-18', '2026-07-20']),
        ),
      );

      final days = await repository.getMyBookedDays(
        from: DateTime(2026, 7, 1),
        to: DateTime(2026, 7, 31),
      );

      expect(days, <DateTime>[DateTime(2026, 7, 18), DateTime(2026, 7, 20)]);
      // Local, not UTC — a UTC value would compare unequal to DateTime(...)
      // and would render as the wrong rail cell east of the meridian.
      expect(days.every((DateTime d) => !d.isUtc), isTrue);
      expect(days.every((DateTime d) => d.hour == 0 && d.minute == 0), isTrue);
    });

    test('skips a malformed day rather than failing the whole rail', () async {
      when(
        () => dio.get<Map<String, dynamic>>(
          _bookedDaysPath,
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: _bookedDaysPath),
          statusCode: 200,
          data: daysEnvelope(const <String>['2026-07-18', 'not-a-date']),
        ),
      );

      final days = await repository.getMyBookedDays(
        from: DateTime(2026, 7, 1),
        to: DateTime(2026, 7, 31),
      );

      expect(days, <DateTime>[DateTime(2026, 7, 18)]);
    });

    test('an empty range is an empty list, not an error', () async {
      when(
        () => dio.get<Map<String, dynamic>>(
          _bookedDaysPath,
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: _bookedDaysPath),
          statusCode: 200,
          data: daysEnvelope(const <String>[]),
        ),
      );

      expect(
        await repository.getMyBookedDays(
          from: DateTime(2026, 7, 1),
          to: DateTime(2026, 7, 31),
        ),
        isEmpty,
      );
    });

    test('a transport error surfaces as a typed Failure, never a raw '
        'DioException', () async {
      when(
        () => dio.get<Map<String, dynamic>>(
          _bookedDaysPath,
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: _bookedDaysPath),
          type: DioExceptionType.connectionTimeout,
        ),
      );

      expect(
        () => repository.getMyBookedDays(
          from: DateTime(2026, 7, 1),
          to: DateTime(2026, 7, 31),
        ),
        throwsA(isA<NetworkFailure>()),
      );
    });
  });
}
