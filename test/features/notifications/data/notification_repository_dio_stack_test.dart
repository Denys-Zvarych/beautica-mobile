// Phase 359 — Dio-STACK test for the notification repository: a real [Dio]
// with the production [ErrorMapperInterceptor] over a scripted
// [HttpClientAdapter], driving the REAL generated [NotificationsApi] and
// [HttpNotificationRepository]. Proves what the mocked-API tests cannot: a
// wire 429 on any /notifications route surfaces as the typed failure, and the
// request shapes (paths, query, UTC `upTo`) are what the backend expects.
//
// This is the "integration" level for phase 359 (no UI yet); the
// integration_test/ flows arrive with phase 365.

import 'dart:convert';
import 'dart:typed_data';

import 'package:beautica_api/beautica_api.dart' as api;
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/error_mapper_interceptor.dart';
import 'package:beautica_mobile/features/notifications/data/notification_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Reply = ({int status, Object? body, Map<String, String> headers});

final class _Adapter implements HttpClientAdapter {
  _Adapter(this.reply);

  final _Reply reply;
  final List<RequestOptions> seen = <RequestOptions>[];
  final List<String> bodies = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seen.add(options);
    if (requestStream != null) {
      final bytes = <int>[];
      await for (final c in requestStream) {
        bytes.addAll(c);
      }
      bodies.add(utf8.decode(bytes));
    } else {
      bodies.add('');
    }
    return ResponseBody.fromString(
      jsonEncode(reply.body),
      reply.status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
        for (final e in reply.headers.entries) e.key: <String>[e.value],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

({HttpNotificationRepository repo, _Adapter adapter}) _boot(_Reply reply) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test.invalid'))
    ..interceptors.add(ErrorMapperInterceptor());
  final adapter = _Adapter(reply);
  dio.httpClientAdapter = adapter;
  return (
    repo: HttpNotificationRepository(
      api.NotificationsApi(dio, api.standardSerializers),
    ),
    adapter: adapter,
  );
}

_Reply _ok(Object? body) => (status: 200, body: body, headers: const {});

_Reply _throttled({String? retryAfter}) => (
  status: 429,
  body: const <String, Object?>{'success': false, 'message': 'Too many'},
  headers: <String, String>{'retry-after': ?retryAfter},
);

void main() {
  group('429 through the real interceptor chain', () {
    final calls =
        <String, Future<Object?> Function(HttpNotificationRepository)>{
          'fetchPage': (r) => r.fetchPage(page: 0, size: 20),
          'unreadCount': (r) => r.unreadCount(),
          'markRead': (r) => r.markRead('abc-123'),
          'markAllRead': (r) => r.markAllRead(),
        };

    for (final e in calls.entries) {
      test(
        'should_surfaceTypedFailureWithRetryAfter_when_${e.key}429',
        () async {
          final s = _boot(_throttled(retryAfter: '42'));

          await expectLater(
            e.value(s.repo),
            throwsA(
              isA<NotificationsRateLimitedFailure>().having(
                (f) => f.retryAfterSeconds,
                'retryAfterSeconds',
                42,
              ),
            ),
          );
          expect(
            s.adapter.seen,
            hasLength(1),
            reason: 'a 429 is never replayed',
          );
        },
      );
    }

    test('should_haveNullRetryAfter_when_headerAbsent', () async {
      final s = _boot(_throttled());
      await expectLater(
        s.repo.unreadCount(),
        throwsA(
          isA<NotificationsRateLimitedFailure>().having(
            (f) => f.retryAfterSeconds,
            'retryAfterSeconds',
            isNull,
          ),
        ),
      );
    });

    test('should_haveNullRetryAfter_when_headerOverUxCeiling', () async {
      final s = _boot(_throttled(retryAfter: '999999'));
      await expectLater(
        s.repo.unreadCount(),
        throwsA(
          isA<NotificationsRateLimitedFailure>().having(
            (f) => f.retryAfterSeconds,
            'retryAfterSeconds',
            isNull,
          ),
        ),
      );
    });

    test('should_neverBeAutoRetried_whenMappedFromWire429', () async {
      final s = _boot(_throttled(retryAfter: '5'));
      Object? caught;
      try {
        await s.repo.unreadCount();
      } on Failure catch (f) {
        caught = f;
      }
      expect(caught, isA<NotificationsRateLimitedFailure>());
      expect(isThrottleFailure(caught! as Failure), isTrue);
      expect(beauticaProviderRetry(0, caught), isNull);
    });
  });

  group('other statuses through the chain', () {
    test('should_throwNotFoundFailure_when_markRead404', () async {
      final s = _boot((
        status: 404,
        body: const <String, Object?>{'success': false},
        headers: const {},
      ));
      await expectLater(
        s.repo.markRead('gone'),
        throwsA(isA<NotFoundFailure>()),
      );
    });

    test('should_throwServerFailure_when_503', () async {
      final s = _boot((
        status: 503,
        body: const <String, Object?>{'success': false},
        headers: const {},
      ));
      await expectLater(
        s.repo.fetchPage(page: 0, size: 20),
        throwsA(
          isA<ServerFailure>().having((f) => f.statusCode, 'status', 503),
        ),
      );
    });
  });

  group('request shapes on the wire', () {
    test('should_requestFeedWithPageAndSizeQuery', () async {
      final s = _boot(
        _ok(<String, Object?>{
          'success': true,
          'data': <Object?>[
            <String, Object?>{
              'id': 'n1',
              'type': 'BOOKING_CREATED',
              'createdAt': '2026-09-30T10:00:00Z',
              'read': false,
              'target': <String, Object?>{'kind': 'NONE'},
            },
          ],
          'page': 2,
          'size': 5,
          'totalElements': 11,
          'totalPages': 3,
        }),
      );

      final page = await s.repo.fetchPage(page: 2, size: 5);

      final req = s.adapter.seen.single;
      expect(req.method, 'GET');
      expect(req.path, '/api/v1/notifications');
      expect(req.queryParameters, containsPair('page', 2));
      expect(req.queryParameters, containsPair('size', 5));
      expect(page.items.single.id, 'n1');
      expect(page.hasNext, isFalse);
    });

    test('should_patchMarkReadAtIdPath', () async {
      final s = _boot(_ok(<String, Object?>{'success': true}));
      await s.repo.markRead('abc-123');
      final req = s.adapter.seen.single;
      expect(req.method, 'PATCH');
      expect(req.path, '/api/v1/notifications/abc-123/read');
    });

    test(
      'should_serializeUpToInUtc_when_markAllReadWithLocalInstant',
      () async {
        final s = _boot(
          _ok(<String, Object?>{
            'success': true,
            'data': <String, Object?>{'updated': 4},
          }),
        );
        // A +03:00 instant: 13:00 local == 10:00Z. The wire body must be UTC.
        final local = DateTime.parse('2026-09-30T13:00:00+03:00');

        final updated = await s.repo.markAllRead(upTo: local);

        expect(updated, 4);
        final req = s.adapter.seen.single;
        expect(req.method, 'PATCH');
        expect(req.path, '/api/v1/notifications/read-all');
        final body =
            jsonDecode(s.adapter.bodies.single) as Map<String, Object?>;
        expect(DateTime.parse(body['upTo']! as String), local.toUtc());
        expect(body['upTo'], endsWith('Z'));
      },
    );

    test('should_sendNoUpTo_when_markAllReadDefault', () async {
      final s = _boot(
        _ok(<String, Object?>{
          'success': true,
          'data': <String, Object?>{'updated': 0},
        }),
      );
      expect(await s.repo.markAllRead(), 0);
      final raw = s.adapter.bodies.single;
      final decoded = raw.isEmpty ? <String, Object?>{} : jsonDecode(raw);
      expect((decoded as Map).containsKey('upTo'), isFalse);
    });
  });
}
