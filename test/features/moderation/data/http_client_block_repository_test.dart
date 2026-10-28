// Phase 425 — HttpClientBlockRepository over the REAL generated
// BlockControllerApi + standardSerializers + the production
// ErrorMapperInterceptor, with only the transport stubbed.
//
// Proves at the wire boundary:
//   • POST /blocks sends exactly `{bookingId}`; DELETE /blocks/{id}; GET
//     /blocks;
//   • the BlockResponse → ClientBlock mapping (kind, nullable avatar / masked
//     phone — CLIENT rows carry none), a malformed list row dropped, a 2xx
//     without a block → ResponseUnusableFailure;
//   • 429 → ClientBlockRateLimitedFailure (own copy), 403 → ServerFailure(403),
//     404 → NotFoundFailure, 400 (walk-in / erased) → ValidationFailure, 5xx →
//     ServerFailure, transport errors → NetworkFailure.

import 'dart:convert';
import 'dart:typed_data';

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/error_mapper_interceptor.dart';
import 'package:beautica_mobile/features/moderation/data/block_repository.dart';
import 'package:beautica_mobile/features/moderation/domain/client_block.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Replies with a fixed status + JSON body and records every request.
final class _StubAdapter implements HttpClientAdapter {
  _StubAdapter({required this.status, this.body, this.throwType});

  final int status;
  final Object? body;
  final DioExceptionType? throwType;
  final List<Map<String, Object?>> sentBodies = <Map<String, Object?>>[];
  final List<String> requests = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final BytesBuilder bytes = BytesBuilder();
    if (requestStream != null) {
      await for (final Uint8List c in requestStream) {
        bytes.add(c);
      }
    }
    requests.add('${options.method} ${options.path}');
    if (bytes.length > 0) {
      sentBodies.add(
        (jsonDecode(utf8.decode(bytes.takeBytes())) as Map<Object?, Object?>)
            .cast<String, Object?>(),
      );
    }
    final DioExceptionType? t = throwType;
    if (t != null) {
      throw DioException(requestOptions: options, type: t);
    }
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

({HttpClientBlockRepository repo, _StubAdapter adapter}) _build({
  required int status,
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
  return (
    repo: HttpClientBlockRepository(
      BlockControllerApi(dio, standardSerializers),
    ),
    adapter: adapter,
  );
}

const String _bookingId = '7b0c3c52-0000-4000-8000-000000000001';
const String _blockId = '9a1d4e63-0000-4000-8000-000000000002';

Map<String, Object?> _guestRow({String id = _blockId}) => <String, Object?>{
  'id': id,
  'kind': 'GUEST',
  'displayName': 'Ірина С.',
  'maskedPhone': '+380 •• ••• 12 34',
  'createdAt': '2026-10-28T10:15:00Z',
};

Map<String, Object?> _clientRow() => <String, Object?>{
  'id': 'c0ffee00-0000-4000-8000-000000000003',
  'kind': 'CLIENT',
  'displayName': 'Олена Ковальчук',
  'avatarUrl': 'https://cdn.test/a.jpg',
  'createdAt': '2026-10-27T09:00:00Z',
};

Map<String, Object?> _ok(Object? data) => <String, Object?>{
  'success': true,
  'data': data,
};

Map<String, Object?> _err(String message) => <String, Object?>{
  'success': false,
  'message': message,
};

void main() {
  group('block — POST /blocks', () {
    for (final int status in <int>[200, 201]) {
      test('$status sends exactly {bookingId} and maps the block', () async {
        final r = _build(status: status, body: _ok(_guestRow()));

        final ClientBlock block = await r.repo.block(_bookingId);

        expect(r.adapter.requests, <String>['POST /api/v1/blocks']);
        expect(r.adapter.sentBodies.single, <String, Object?>{
          'bookingId': _bookingId,
        });
        expect(block.id, _blockId);
        expect(block.kind, ClientBlockKind.guest);
        expect(block.displayName, 'Ірина С.');
        expect(block.maskedPhone, '+380 •• ••• 12 34');
        expect(block.avatarUrl, isNull);
        expect(block.createdAt, DateTime.utc(2026, 10, 28, 10, 15));
      });
    }

    test('a 2xx without a block → ResponseUnusableFailure', () async {
      final r = _build(status: 200, body: _ok(null));
      await expectLater(
        r.repo.block(_bookingId),
        throwsA(isA<ResponseUnusableFailure>()),
      );
    });

    test('an unknown kind is unusable, never guessed', () async {
      final r = _build(
        status: 200,
        body: _ok(<String, Object?>{..._guestRow(), 'kind': 'ROBOT'}),
      );
      await expectLater(
        r.repo.block(_bookingId),
        throwsA(isA<ResponseUnusableFailure>()),
      );
    });
  });

  group('error mapping', () {
    final Map<int, TypeMatcher<Failure>> cases = <int, TypeMatcher<Failure>>{
      429: isA<ClientBlockRateLimitedFailure>(),
      404: isA<NotFoundFailure>(),
      400: isA<ValidationFailure>(),
    };
    for (final MapEntry<int, TypeMatcher<Failure>> c in cases.entries) {
      test('POST ${c.key} → ${c.value}', () async {
        final r = _build(status: c.key, body: _err('nope'));
        await expectLater(r.repo.block(_bookingId), throwsA(c.value));
      });
    }

    test(
      '429 on DELETE → ClientBlockRateLimitedFailure too (shared budget)',
      () async {
        final r = _build(status: 429, body: _err('slow down'));
        await expectLater(
          r.repo.unblock(_blockId),
          throwsA(isA<ClientBlockRateLimitedFailure>()),
        );
      },
    );

    test('403 (client / salon master) → ServerFailure(403)', () async {
      final r = _build(status: 403, body: _err('forbidden'));
      await expectLater(
        r.repo.block(_bookingId),
        throwsA(
          isA<ServerFailure>().having(
            (ServerFailure f) => f.statusCode,
            'statusCode',
            403,
          ),
        ),
      );
    });

    test('500 → ServerFailure(500)', () async {
      final r = _build(status: 500, body: _err('boom'));
      await expectLater(
        r.repo.list(),
        throwsA(
          isA<ServerFailure>().having(
            (ServerFailure f) => f.statusCode,
            'statusCode',
            500,
          ),
        ),
      );
    });

    test('a connection error → NetworkFailure', () async {
      final r = _build(
        status: 200,
        throwType: DioExceptionType.connectionError,
      );
      await expectLater(
        r.repo.block(_bookingId),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('mapClientBlockDioException: 429 wins over an attached failure', () {
      final RequestOptions o = RequestOptions(path: '/api/v1/blocks');
      final Failure f = mapClientBlockDioException(
        DioException(
          requestOptions: o,
          type: DioExceptionType.badResponse,
          response: Response<Object?>(requestOptions: o, statusCode: 429),
          error: const UnknownFailure(),
        ),
      );
      expect(f, isA<ClientBlockRateLimitedFailure>());
    });
  });

  group('unblock — DELETE /blocks/{id}', () {
    test('204 resolves', () async {
      final r = _build(status: 204);
      await r.repo.unblock(_blockId);
      expect(r.adapter.requests, <String>['DELETE /api/v1/blocks/$_blockId']);
    });
  });

  group('list — GET /blocks', () {
    test(
      'maps every row in server order; a CLIENT row has no masked phone',
      () async {
        final r = _build(
          status: 200,
          body: _ok(<Object?>[_guestRow(), _clientRow()]),
        );

        final List<ClientBlock> blocks = await r.repo.list();

        expect(r.adapter.requests, <String>['GET /api/v1/blocks']);
        expect(blocks, hasLength(2));
        expect(blocks.first.kind, ClientBlockKind.guest);
        expect(blocks.last.kind, ClientBlockKind.client);
        expect(blocks.last.maskedPhone, isNull);
        expect(blocks.last.avatarUrl, 'https://cdn.test/a.jpg');
      },
    );

    test('a malformed row is dropped, not the whole list', () async {
      final r = _build(
        status: 200,
        body: _ok(<Object?>[
          _guestRow(),
          <String, Object?>{'id': 'x', 'kind': 'CLIENT'},
        ]),
      );
      final List<ClientBlock> blocks = await r.repo.list();
      expect(blocks.map((ClientBlock b) => b.id), <String>[_blockId]);
    });

    test('a 2xx without data → ResponseUnusableFailure', () async {
      final r = _build(status: 200, body: _ok(null));
      await expectLater(r.repo.list(), throwsA(isA<ResponseUnusableFailure>()));
    });
  });

  group('kind-scoped fields — a field for the other kind is dropped', () {
    test('a CLIENT row carrying maskedPhone maps it to null', () async {
      final r = _build(
        status: 200,
        body: _ok(<Object?>[
          <String, Object?>{
            ..._clientRow(),
            'maskedPhone': '+380 •• ••• 99 99',
          },
        ]),
      );
      final ClientBlock block = (await r.repo.list()).single;
      expect(block.kind, ClientBlockKind.client);
      expect(block.maskedPhone, isNull);
      expect(block.avatarUrl, 'https://cdn.test/a.jpg');
    });

    test('a GUEST row carrying avatarUrl maps it to null', () async {
      final r = _build(
        status: 200,
        body: _ok(<Object?>[
          <String, Object?>{
            ..._guestRow(),
            'avatarUrl': 'https://cdn.test/g.jpg',
          },
        ]),
      );
      final ClientBlock block = (await r.repo.list()).single;
      expect(block.kind, ClientBlockKind.guest);
      expect(block.avatarUrl, isNull);
      expect(block.maskedPhone, '+380 •• ••• 12 34');
    });
  });
}
