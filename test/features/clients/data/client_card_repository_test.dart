// M510 — HttpClientRepository card reads (`getCard` / `getVisits`) over the REAL generated models + standardSerializers + the
// production ErrorMapperInterceptor, with only the transport stubbed.
//
// Proves at the wire boundary:
//   • the requests: salon vs `me` base, `users` vs `guests`, `/visits` with
//     FLAT `page` / `size`, `masterId` only for a salon scope that carries one;
//   • the card mapper: no kind branch (the same mapper serves both handles),
//     zero distribution when absent, 5→1 buckets, blank name / phone → null,
//     `stats` / `firstVisitAt` not mapped; `servedByMasters` in server order,
//     incomplete / repeated entries dropped (CLI-73);
//   • the visit mapper: unknown status → BookingStatus.unknown, a visit with
//     no usable item dropped, the master name is not on the domain type;
//   • the uniform 404 → NotFoundFailure, an unreadable envelope →
//     ResponseUnusableFailure.

import 'dart:convert';
import 'dart:typed_data';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/error_mapper_interceptor.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/clients/data/client_repository.dart';
import 'package:beautica_mobile/features/clients/domain/client_card.dart';
import 'package:beautica_mobile/features/clients/domain/client_summary.dart';
import 'package:beautica_mobile/features/clients/domain/client_visit.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

final class _StubAdapter implements HttpClientAdapter {
  _StubAdapter({required this.status, this.body});

  final int status;
  final Object? body;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
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
}) {
  final _StubAdapter adapter = _StubAdapter(status: status, body: body);
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
    ..httpClientAdapter = adapter
    ..interceptors.add(ErrorMapperInterceptor());
  return (repo: HttpClientRepository(dio), adapter: adapter);
}

const String _userId = 'a1111111-0000-4000-8000-000000000001';
const String _bookingId = 'b2222222-0000-4000-8000-000000000002';
const String _salonId = 'c3333333-0000-4000-8000-000000000003';
const String _masterRow = 'd4444444-0000-4000-8000-000000000004';

const ClientRef _registered = ClientRef.registered(_userId);
const ClientRef _guest = ClientRef.guest(_bookingId);

Map<String, Object?> _envelope(Object? data) => <String, Object?>{
  'success': true,
  'message': 'ok',
  'data': data,
};

Map<String, Object?> _page(List<Object?> rows, {int page = 0, int pages = 1}) =>
    _envelope(<String, Object?>{
      'success': true,
      'data': rows,
      'page': page,
      'size': 20,
      'totalElements': rows.length,
      'totalPages': pages,
    });

Map<String, Object?> _cardJson({
  String kind = 'REGISTERED',
  String? displayName = 'Оксана Мельник',
  String? phone = '+380671234567',
  Object? distribution = const <Object?>[],
  int ratingCount = 12,
  num? ratingAvg = 4.9,
  Object? servedByMasters,
}) => <String, Object?>{
  'servedByMasters': ?servedByMasters,
  'kind': kind,
  'userId': kind == 'REGISTERED' ? _userId : null,
  'guestBookingId': kind == 'GUEST' ? _bookingId : null,
  'displayName': displayName,
  'avatarUrl': null,
  'phone': phone,
  'blocked': true,
  'ratingAvg': ratingAvg,
  'ratingCount': ratingCount,
  'ratingDistribution': distribution,
  'firstVisitAt': '2026-01-01T10:00:00Z',
  'lastVisitAt': '2026-11-07T12:00:00Z',
  'nextVisitAt': '2026-11-20T12:00:00Z',
  'stats': <String, Object?>{
    'totalVisits': 9,
    'completedVisits': 8,
    'upcomingVisits': 1,
  },
};

Map<String, Object?> _item({
  String bookingId = 'bk-1',
  String? status = 'CONFIRMED',
  String at = '2026-11-20T12:00:00Z',
}) => <String, Object?>{
  'bookingId': bookingId,
  'serviceName': 'Манікюр',
  'status': status,
  'startsAt': at,
  'masterId': 'm-1',
  'masterDisplayName': 'Секретна Майстриня',
  'priceAtBooking': 650,
  'priceMaxAtBooking': 800,
};

/// Runs [json] through the visit page mapper and returns the single visit.
ClientVisit? clientVisitFromDtoForTest(Map<String, Object?> json) {
  final PageResponse<ClientVisit> p = clientVisitsFromBody(
    _page(<Object?>[json]),
    requestedPage: 0,
  );
  return p.items.isEmpty ? null : p.items.single;
}

void main() {
  group('requests', () {
    test('salon scope, registered → /salons/{id}/clients/users/{id}', () async {
      final b = _build(body: _envelope(_cardJson()));
      await b.repo.getCard(
        const ClientListScope.salon(salonId: _salonId),
        _registered,
      );
      expect(
        b.adapter.requests.single.path,
        '/api/v1/salons/$_salonId/clients/users/$_userId',
      );
      expect(b.adapter.requests.single.queryParameters, isEmpty);
    });

    test('salon scope with masterId sends it; guest → /guests/{id}', () async {
      final b = _build(body: _envelope(_cardJson(kind: 'GUEST')));
      await b.repo.getCard(
        const ClientListScope.salon(salonId: _salonId, masterId: _masterRow),
        _guest,
      );
      expect(
        b.adapter.requests.single.path,
        '/api/v1/salons/$_salonId/clients/guests/$_bookingId',
      );
      expect(b.adapter.requests.single.queryParameters, <String, dynamic>{
        'masterId': _masterRow,
      });
    });

    test('me scope never sends masterId; visits use FLAT paging', () async {
      final b = _build(body: _page(<Object?>[]));
      await b.repo.getVisits(
        const ClientListScope.me(),
        _registered,
        page: 2,
        size: 20,
      );
      expect(
        b.adapter.requests.single.path,
        '/api/v1/masters/me/clients/users/$_userId/visits',
      );
      expect(b.adapter.requests.single.queryParameters, <String, dynamic>{
        'page': 2,
        'size': 20,
      });
    });
  });

  group('card mapper', () {
    test('maps both handles with the same code (no kind branch)', () async {
      final reg = _build(body: _envelope(_cardJson()));
      final gst = _build(body: _envelope(_cardJson(kind: 'GUEST')));
      final ClientCard a = await reg.repo.getCard(
        const ClientListScope.me(),
        _registered,
      );
      final ClientCard g = await gst.repo.getCard(
        const ClientListScope.me(),
        _guest,
      );
      expect(a.ref, _registered, reason: 'the REQUESTED handle, not the body');
      expect(g.ref, _guest);
      expect(a.copyWith(ref: _guest), g);
      expect(a.phone, '+380671234567');
      expect(a.blocked, isTrue);
      expect(a.displayRating, 4.9);
      expect(a.nextVisitAt, DateTime.utc(2026, 11, 20, 12));
    });

    test('absent / empty distribution → five zeros', () async {
      final b = _build(body: _envelope(_cardJson(ratingCount: 0)));
      final ClientCard c = await b.repo.getCard(
        const ClientListScope.me(),
        _guest,
      );
      expect(c.ratingDistribution, <int>[0, 0, 0, 0, 0]);
      expect(c.displayRating, isNull, reason: 'count 0 → unrated');
    });

    test('buckets map 5→1 into index 0..4; junk buckets are ignored', () async {
      final b = _build(
        body: _envelope(
          _cardJson(
            distribution: <Object?>[
              <String, Object?>{'rating': 5, 'count': 9},
              <String, Object?>{'rating': 4, 'count': 2},
              <String, Object?>{'rating': 1, 'count': 1},
              <String, Object?>{'rating': 9, 'count': 50},
              <String, Object?>{'rating': 3, 'count': -4},
            ],
          ),
        ),
      );
      final ClientCard c = await b.repo.getCard(
        const ClientListScope.me(),
        _registered,
      );
      expect(c.ratingDistribution, <int>[9, 2, 0, 0, 1]);
    });

    test('blank name / phone → null', () async {
      final b = _build(
        body: _envelope(_cardJson(displayName: '  ', phone: '')),
      );
      final ClientCard c = await b.repo.getCard(
        const ClientListScope.me(),
        _guest,
      );
      expect(c.displayName, isNull);
      expect(c.phone, isNull);
      expect(c.initials, isNull);
    });

    test('servedByMasters: server order kept; incomplete / repeated dropped '
        '(CLI-73)', () async {
      final b = _build(
        body: _envelope(
          _cardJson(
            servedByMasters: <Object?>[
              <String, Object?>{
                'masterId': 'm-2',
                'name': ' Ірина ',
                'avatarUrl': 'https://cdn.test/i.jpg',
              },
              <String, Object?>{'masterId': 'm-1', 'name': 'Олена'},
              <String, Object?>{'masterId': '', 'name': 'NoId'},
              <String, Object?>{'masterId': 'm-3', 'name': '  '},
              <String, Object?>{'masterId': 'm-2', 'name': 'Дубль'},
            ],
          ),
        ),
      );
      final ClientCard c = await b.repo.getCard(
        const ClientListScope.salon(salonId: _salonId),
        _registered,
      );
      expect(c.servedByMasters, const <ClientServedMaster>[
        ClientServedMaster(
          masterId: 'm-2',
          name: 'Ірина',
          avatarUrl: 'https://cdn.test/i.jpg',
        ),
        ClientServedMaster(masterId: 'm-1', name: 'Олена'),
      ]);
      expect(c.toString(), isNot(contains('Ірина')));
    });

    test('servedByMasters absent → empty', () async {
      final b = _build(body: _envelope(_cardJson()));
      final ClientCard c = await b.repo.getCard(
        const ClientListScope.me(),
        _registered,
      );
      expect(c.servedByMasters, isEmpty);
    });

    test('initials: first letters of the first two words', () {
      expect(
        const ClientCard(
          ref: _registered,
          displayName: 'оксана мельник іванівна',
        ).initials,
        'ОМ',
      );
    });
  });

  group('visit mapper', () {
    test('maps items; unknown status → unknown; no master name', () {
      final ClientVisit? v = clientVisitFromDtoForTest(<String, Object?>{
        'visitKey': 'v1',
        'startsAt': '2026-11-20T12:00:00Z',
        'items': <Object?>[
          _item(),
          _item(bookingId: 'bk-2', status: 'SOMETHING_NEW'),
        ],
      });
      expect(v, isNotNull);
      expect(v!.items.map((i) => i.status), <BookingStatus>[
        BookingStatus.confirmed,
        BookingStatus.unknown,
      ]);
      expect(v.items.first.price, 650);
      expect(v.items.first.priceMax, 800);
      expect(v.firstBookingId, 'bk-1');
      expect(v.toString(), isNot(contains('Секретна')));
      expect(v.sharedStatus, isNull);
    });

    test('a visit without a usable item is dropped', () {
      expect(
        clientVisitFromDtoForTest(<String, Object?>{
          'visitKey': 'v1',
          'startsAt': '2026-11-20T12:00:00Z',
          'items': <Object?>[
            <String, Object?>{'serviceName': 'x'},
          ],
        }),
        isNull,
      );
    });

    test('page: rows mapped, paging carried', () async {
      final b = _build(
        body: _page(<Object?>[
          <String, Object?>{
            'visitKey': 'v1',
            'startsAt': '2026-11-20T12:00:00Z',
            'items': <Object?>[_item()],
          },
        ], pages: 3),
      );
      final PageResponse<ClientVisit> p = await b.repo.getVisits(
        const ClientListScope.me(),
        _registered,
      );
      expect(p.items, hasLength(1));
      expect(p.hasMore, isTrue);
    });
  });

  group('errors', () {
    test('404 → NotFoundFailure (the uniform CLIENT_NOT_FOUND)', () async {
      final b = _build(
        status: 404,
        body: <String, Object?>{
          'success': false,
          'message': 'CLIENT_NOT_FOUND',
        },
      );
      await expectLater(
        b.repo.getCard(const ClientListScope.me(), _guest),
        throwsA(isA<NotFoundFailure>()),
      );
    });

    test('an unreadable envelope → ResponseUnusableFailure', () async {
      final b = _build(body: <String, Object?>{'success': false});
      await expectLater(
        b.repo.getCard(const ClientListScope.me(), _registered),
        throwsA(isA<ResponseUnusableFailure>()),
      );
    });
  });
}
