// M509 — HttpClientRepository over the REAL generated models +
// standardSerializers + the production ErrorMapperInterceptor, with only the
// transport stubbed.
//
// Proves at the wire boundary:
//   • the request: salon scope → `/api/v1/salons/{id}/clients` with FLAT
//     `page` / `size` (never a `pageable=` blob), `masterId` only when the
//     scope carries one, `q` only when given; `me` scope → `/masters/me/clients`;
//   • the row mapper: registered, guest, a registered row whose visits came
//     from walk-ins (B527 — maps like any registered row), unknown `kind`
//     dropped, a row without its kind's id dropped, blank name → null, a
//     guest never carries a photo but DOES carry the backend's rating (M548);
//   • `completedVisits` is mapped but is not a display value;
//   • `clientQueryFor`: the 2–50-char `q` rule;
//   • an unreadable envelope → ResponseUnusableFailure, HTTP errors → typed
//     Failures.

import 'dart:convert';
import 'dart:typed_data';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/error_mapper_interceptor.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/features/clients/data/client_repository.dart';
import 'package:beautica_mobile/features/clients/domain/client_summary.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

final class _StubAdapter implements HttpClientAdapter {
  _StubAdapter({required this.status, this.body, this.throwType});

  final int status;
  final Object? body;
  final DioExceptionType? throwType;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final DioExceptionType? t = throwType;
    if (t != null) throw DioException(requestOptions: options, type: t);
    return ResponseBody.fromString(
      body == null ? '' : jsonEncode(body),
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

({HttpClientRepository repo, _StubAdapter adapter}) _build({
  int status = 200,
  Object? body,
  DioExceptionType? throwType,
}) {
  final _StubAdapter adapter = _StubAdapter(
    status: status,
    body: body,
    throwType: throwType,
  );
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
    ..httpClientAdapter = adapter
    ..interceptors.add(ErrorMapperInterceptor());
  return (repo: HttpClientRepository(dio), adapter: adapter);
}

const String _userId = 'a1111111-0000-4000-8000-000000000001';
const String _bookingId = 'b2222222-0000-4000-8000-000000000002';

Map<String, Object?> _registered({
  String? displayName = 'Оксана Мельник',
  num? ratingAvg = 4.9,
  int ratingCount = 12,
  bool blocked = false,
  String? avatarUrl = 'https://cdn.test/o.jpg',
}) => <String, Object?>{
  'kind': 'REGISTERED',
  'userId': _userId,
  'displayName': displayName,
  'avatarUrl': avatarUrl,
  'lastVisitAt': '2026-11-07T12:00:00Z',
  'nextVisitAt': '2026-11-20T12:00:00Z',
  'completedVisits': 9,
  'ratingAvg': ratingAvg,
  'ratingCount': ratingCount,
  'blocked': blocked,
};

Map<String, Object?> _guest({String? displayName = 'Ірина Коваль'}) =>
    <String, Object?>{
      'kind': 'GUEST',
      'guestBookingId': _bookingId,
      'displayName': displayName,
      // A guest never carries a photo; the mapper must not trust one.
      'avatarUrl': 'https://cdn.test/leak.jpg',
      // M548 / REV-D10: a guest's rating IS the backend's value.
      'ratingAvg': 3.0,
      'ratingCount': 2,
      'completedVisits': 1,
      'blocked': false,
    };

Map<String, Object?> _page(
  List<Map<String, Object?>> rows, {
  int page = 0,
  int totalPages = 1,
  int totalElements = 0,
}) => <String, Object?>{
  'success': true,
  'data': <String, Object?>{
    'success': true,
    'data': rows,
    'page': page,
    'size': 20,
    'totalElements': totalElements == 0 ? rows.length : totalElements,
    'totalPages': totalPages,
  },
};

void main() {
  group('request', () {
    test('salon scope: flat page/size, no masterId, no q by default', () async {
      final r = _build(body: _page(<Map<String, Object?>>[]));
      await r.repo.list(const ClientListScope.salon(salonId: 'salon-1'));

      final RequestOptions sent = r.adapter.requests.single;
      expect(sent.method, 'GET');
      expect(sent.path, '/api/v1/salons/salon-1/clients');
      expect(sent.queryParameters, <String, dynamic>{'page': 0, 'size': 20});
      expect(
        sent.queryParameters.containsKey('pageable'),
        isFalse,
        reason: 'the generated Pageable blob must never reach the wire',
      );
    });

    test('salon scope + masterId + q + page 2 (owner master mode)', () async {
      final r = _build(body: _page(<Map<String, Object?>>[]));
      await r.repo.list(
        const ClientListScope.salon(salonId: 'salon-1', masterId: 'm-9'),
        q: 'ол',
        page: 2,
      );
      expect(r.adapter.requests.single.queryParameters, <String, dynamic>{
        'page': 2,
        'size': 20,
        'masterId': 'm-9',
        'q': 'ол',
      });
    });

    test(
      'me scope hits /masters/me/clients and never sends masterId',
      () async {
        final r = _build(body: _page(<Map<String, Object?>>[]));
        await r.repo.list(const ClientListScope.me());
        final RequestOptions sent = r.adapter.requests.single;
        expect(sent.path, '/api/v1/masters/me/clients');
        expect(sent.queryParameters.containsKey('masterId'), isFalse);
      },
    );

    test('a dot-segment salonId is rejected before any request', () async {
      final r = _build(body: _page(<Map<String, Object?>>[]));
      await expectLater(
        r.repo.list(const ClientListScope.salon(salonId: '..')),
        throwsA(isA<Failure>()),
      );
      expect(r.adapter.requests, isEmpty);
    });
  });

  group('row mapper', () {
    test('registered row maps every display field', () async {
      final r = _build(
        body: _page(<Map<String, Object?>>[_registered()], totalPages: 3),
      );
      final PageResponse<ClientSummary> page = await r.repo.list(
        const ClientListScope.me(),
      );
      expect(page.items, hasLength(1));
      final ClientSummary s = page.items.single;
      expect(s.ref, const ClientRef.registered(_userId));
      expect(s.isGuest, isFalse);
      expect(s.displayName, 'Оксана Мельник');
      expect(s.initials, 'ОМ');
      expect(s.avatarUrl, 'https://cdn.test/o.jpg');
      expect(s.lastVisitAt, DateTime.utc(2026, 11, 7, 12));
      expect(s.nextVisitAt, DateTime.utc(2026, 11, 20, 12));
      expect(s.displayRating, 4.9);
      expect(s.ratingCount, 12);
      expect(s.blocked, isFalse);
      // Mapped from the contract, never a display value (D5).
      expect(s.completedVisits, 9);
      expect(page.hasMore, isTrue);
      expect(page.page, 0);
    });

    test('a registered row whose visits came from walk-ins (B527) maps like '
        'any registered row — nothing marks the source', () async {
      // The wire row of a REGISTERED client whose bookings were attached from
      // LINK / STAFF carries no extra field; it is just a registered row.
      final r = _build(
        body: _page(<Map<String, Object?>>[
          _registered(
            displayName: 'Наталія Гончаренко',
            ratingAvg: null,
            ratingCount: 0,
          ),
        ]),
      );
      final ClientSummary s = (await r.repo.list(
        const ClientListScope.me(),
      )).items.single;
      expect(s.ref, isA<RegisteredClientRef>());
      expect(s.isGuest, isFalse);
      expect(s.displayRating, isNull, reason: 'unrated → «—»');
    });

    test('guest row: guest ref, no photo, backend rating mapped', () async {
      final r = _build(body: _page(<Map<String, Object?>>[_guest()]));
      final ClientSummary s = (await r.repo.list(
        const ClientListScope.me(),
      )).items.single;
      expect(s.ref, const ClientRef.guest(_bookingId));
      expect(s.isGuest, isTrue);
      expect(s.id, _bookingId);
      expect(s.avatarUrl, isNull);
      expect(s.ratingAvg, 3.0);
      expect(s.ratingCount, 2);
      expect(s.displayRating, 3.0);
    });

    test('guest row: unrated guest stays unrated', () async {
      final r = _build(
        body: _page(<Map<String, Object?>>[
          <String, Object?>{..._guest(), 'ratingAvg': null, 'ratingCount': 0},
        ]),
      );
      final ClientSummary s = (await r.repo.list(
        const ClientListScope.me(),
      )).items.single;
      expect(s.ratingAvg, isNull);
      expect(s.ratingCount, 0);
      expect(s.displayRating, isNull);
    });

    test(
      'null / blank name → null (the row renders «Гість»), no initials',
      () async {
        final r = _build(
          body: _page(<Map<String, Object?>>[
            _guest(displayName: null),
            _guest(displayName: '   '),
          ]),
        );
        final List<ClientSummary> items = (await r.repo.list(
          const ClientListScope.me(),
        )).items;
        expect(items.map((ClientSummary s) => s.displayName), <String?>[
          null,
          null,
        ]);
        expect(items.first.initials, isNull);
      },
    );

    test(
      'unknown kind and rows missing their id are dropped, the rest stay',
      () async {
        final r = _build(
          body: _page(<Map<String, Object?>>[
            <String, Object?>{'kind': 'ALIEN', 'userId': _userId},
            <String, Object?>{'kind': 'REGISTERED'}, // no userId
            <String, Object?>{'kind': 'GUEST', 'guestBookingId': ''},
            _registered(),
          ]),
        );
        final PageResponse<ClientSummary> page = await r.repo.list(
          const ClientListScope.me(),
        );
        expect(page.items, hasLength(1));
        expect(page.items.single.ref, const ClientRef.registered(_userId));
      },
    );

    test(
      'a blocked row keeps its flag; nonsense counts clamp to zero',
      () async {
        final row = _registered(blocked: true, ratingCount: -3);
        row['completedVisits'] = -1;
        final r = _build(body: _page(<Map<String, Object?>>[row]));
        final ClientSummary s = (await r.repo.list(
          const ClientListScope.me(),
        )).items.single;
        expect(s.blocked, isTrue);
        expect(s.ratingCount, 0);
        expect(s.completedVisits, 0);
      },
    );

    test('toString never prints the name', () async {
      final r = _build(body: _page(<Map<String, Object?>>[_registered()]));
      final ClientSummary s = (await r.repo.list(
        const ClientListScope.me(),
      )).items.single;
      expect(s.toString(), isNot(contains('Оксана')));
    });
  });

  group('clientQueryFor (B507 q: 2–50 chars, never blank)', () {
    test('blank, whitespace and 1 char send no q', () {
      expect(clientQueryFor(''), isNull);
      expect(clientQueryFor('   '), isNull);
      expect(clientQueryFor('а'), isNull);
      expect(clientQueryFor(' а '), isNull);
    });

    test('2 chars is the floor, trimmed', () {
      expect(clientQueryFor('ол'), 'ол');
      expect(clientQueryFor('  ол  '), 'ол');
    });

    test('over 50 chars is capped at 50', () {
      final String long = 'я' * 80;
      expect(clientQueryFor(long), 'я' * 50);
    });
  });

  group('failures', () {
    test('an envelope without data → ResponseUnusableFailure', () async {
      final r = _build(body: <String, Object?>{'success': true});
      await expectLater(
        r.repo.list(const ClientListScope.me()),
        throwsA(isA<ResponseUnusableFailure>()),
      );
    });

    test('a 5xx → ServerFailure', () async {
      final r = _build(status: 500, body: <String, Object?>{'success': false});
      await expectLater(
        r.repo.list(const ClientListScope.me()),
        throwsA(isA<Failure>()),
      );
    });

    test('a transport error → NetworkFailure', () async {
      final r = _build(throwType: DioExceptionType.connectionError);
      await expectLater(
        r.repo.list(const ClientListScope.me()),
        throwsA(isA<NetworkFailure>()),
      );
    });
  });

  group('cancellation', () {
    test('the CancelToken reaches the Dio request', () async {
      final r = _build(body: _page(<Map<String, Object?>>[_registered()]));
      final CancelToken token = CancelToken();
      await r.repo.list(const ClientListScope.me(), cancelToken: token);
      expect(r.adapter.requests.single.cancelToken, same(token));
    });

    test(
      'a cancelled request rethrows the Dio cancel, never a Failure',
      () async {
        final r = _build(throwType: DioExceptionType.cancel);
        await expectLater(
          r.repo.list(const ClientListScope.me()),
          throwsA(
            isA<DioException>().having(
              (DioException e) => CancelToken.isCancel(e),
              'isCancel',
              isTrue,
            ),
          ),
        );
      },
    );
  });

  // M544 / B564 — the removal writes go through the GENERATED client with the
  // generated `ClientListRemovalRequest`: path, method and EXACTLY one key.
  group('removeFromList / restoreToList (B564)', () {
    const String salonId = 'c3333333-0000-4000-8000-000000000003';

    Map<String, dynamic> bodyOf(RequestOptions r) =>
        (r.data is String ? jsonDecode(r.data as String) : r.data)
            as Map<String, dynamic>;

    test('salon scope, registered → POST …/salons/{id}/clients/removals '
        '{clientId}, no masterId', () async {
      final b = _build(status: 204);
      await b.repo.removeFromList(
        const ClientListScope.salon(salonId: salonId, masterId: 'm-1'),
        const ClientRef.registered(_userId),
      );
      final RequestOptions r = b.adapter.requests.single;
      expect(r.method, 'POST');
      expect(r.path, '/api/v1/salons/$salonId/clients/removals');
      expect(r.queryParameters, isEmpty);
      expect(bodyOf(r), <String, dynamic>{'clientId': _userId});
    });

    test('salon scope, guest restore → …/removals/restore '
        '{guestBookingId}', () async {
      final b = _build(status: 204);
      await b.repo.restoreToList(
        const ClientListScope.salon(salonId: salonId),
        const ClientRef.guest(_bookingId),
      );
      final RequestOptions r = b.adapter.requests.single;
      expect(r.path, '/api/v1/salons/$salonId/clients/removals/restore');
      expect(bodyOf(r), <String, dynamic>{'guestBookingId': _bookingId});
    });

    test('me scope → /masters/me/clients/removals[/restore]', () async {
      final b = _build(status: 204);
      await b.repo.removeFromList(
        const ClientListScope.me(),
        const ClientRef.registered(_userId),
      );
      await b.repo.restoreToList(
        const ClientListScope.me(),
        const ClientRef.guest(_bookingId),
      );
      expect(b.adapter.requests.map((RequestOptions r) => r.path), <String>[
        '/api/v1/masters/me/clients/removals',
        '/api/v1/masters/me/clients/removals/restore',
      ]);
    });

    test('HTTP errors → typed Failures', () async {
      await expectLater(
        _build(
          status: 404,
          body: <String, Object?>{'success': false},
        ).repo.removeFromList(
          const ClientListScope.me(),
          const ClientRef.registered(_userId),
        ),
        throwsA(isA<NotFoundFailure>()),
      );
      await expectLater(
        _build(throwType: DioExceptionType.connectionError).repo.restoreToList(
          const ClientListScope.me(),
          const ClientRef.registered(_userId),
        ),
        throwsA(isA<NetworkFailure>()),
      );
    });
  });
}
