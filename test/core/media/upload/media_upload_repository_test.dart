import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/media/upload/media_upload_repository.dart';
import 'package:beautica_mobile/core/media/upload/upload_failure.dart';
import 'package:beautica_mobile/core/network/error_mapper_interceptor.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Scripted [HttpClientAdapter]: records every request and answers with the
/// next scripted handler. http_mock_adapter does not drive `onSendProgress`,
/// so this fake does.
final class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this._handlers);

  final List<Future<ResponseBody> Function(RequestOptions, Future<void>?)>
  _handlers;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    final i = requests.length - 1;
    return _handlers[i < _handlers.length ? i : _handlers.length - 1](
      options,
      cancelFuture,
    );
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Object body) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: <String, List<String>>{
    Headers.contentTypeHeader: <String>[Headers.jsonContentType],
  },
);

Future<ResponseBody> Function(RequestOptions, Future<void>?) _reply(
  int status, [
  Object body = const <String, Object>{'success': false},
]) =>
    (_, _) async => _json(status, body);

const Map<String, Object> _okBody = <String, Object>{
  'success': true,
  'data': <String, Object>{'avatarUrl': 'https://media.test/avatars/u1/1.jpg'},
};

void main() {
  late Directory tmp;
  late File photo;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('upload_test');
    photo = File('${tmp.path}/p.jpg')..writeAsBytesSync(<int>[1, 2, 3]);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  HttpMediaUploadRepository build(_ScriptedAdapter adapter) {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..httpClientAdapter = adapter
      ..interceptors.add(ErrorMapperInterceptor());
    return HttpMediaUploadRepository(dio: dio);
  }

  Future<UploadFailure> failureOf(Future<Object?> f) async {
    try {
      await f;
    } on UploadFailure catch (e) {
      return e;
    }
    fail('expected an UploadFailure');
  }

  // Wire bytes (part name, content type, filename, headers) are covered by
  // media_upload_wire_test.dart; here we only assert the result and path.
  test('resolves to the avatar URL on a single POST', () async {
    final adapter = _ScriptedAdapter([_reply(200, _okBody)]);
    final url = await build(adapter).uploadAvatar(photo).result;
    expect(url, 'https://media.test/avatars/u1/1.jpg');
    expect(adapter.requests.single.method, 'POST');
    expect(adapter.requests.single.path, '/api/v1/media/avatar');
  });

  test('413 -> tooLarge', () async {
    final f = build(_ScriptedAdapter([_reply(413)])).uploadAvatar(photo).result;
    expect(await failureOf(f), isA<UploadTooLargeFailure>());
  });

  test('400 -> unsupportedFormat', () async {
    final f = build(_ScriptedAdapter([_reply(400)])).uploadAvatar(photo).result;
    expect(await failureOf(f), isA<UploadUnsupportedFormatFailure>());
  });

  test('503 -> storageUnavailable', () async {
    final f = build(_ScriptedAdapter([_reply(503)])).uploadAvatar(photo).result;
    expect(await failureOf(f), isA<UploadStorageUnavailableFailure>());
  });

  test('404 -> notFound', () async {
    final f = build(_ScriptedAdapter([_reply(404)])).uploadAvatar(photo).result;
    expect(await failureOf(f), isA<UploadNotFoundFailure>());
  });

  test('403 -> forbidden', () async {
    final f = build(_ScriptedAdapter([_reply(403)])).uploadAvatar(photo).result;
    expect(await failureOf(f), isA<UploadForbiddenFailure>());
  });

  test('500 -> unknown(500)', () async {
    final f = build(_ScriptedAdapter([_reply(500)])).uploadAvatar(photo).result;
    final unknown = await failureOf(f);
    expect(unknown, isA<UploadUnknownFailure>());
    expect((unknown as UploadUnknownFailure).status, 500);
  });

  test('typed UnauthorizedFailure without a response -> unauthorized', () {
    final e = DioException(
      requestOptions: RequestOptions(path: '/x'),
      error: const UnauthorizedFailure(),
    );
    expect(mapUploadFailure(e), isA<UploadUnauthorizedFailure>());
  });

  test('200 with an unusable body -> unknown(200)', () async {
    final f = build(
      _ScriptedAdapter([
        _reply(200, const <String, Object>{'data': {}}),
      ]),
    ).uploadAvatar(photo).result;
    final e = await failureOf(f);
    expect(e, isA<UploadUnknownFailure>());
    expect((e as UploadUnknownFailure).status, 200);
  });

  test('timeouts and connection errors -> network', () async {
    for (final type in <DioExceptionType>[
      DioExceptionType.connectionTimeout,
      DioExceptionType.sendTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.connectionError,
    ]) {
      final adapter = _ScriptedAdapter([
        (o, _) async => throw DioException(requestOptions: o, type: type),
      ]);
      expect(
        await failureOf(build(adapter).uploadAvatar(photo).result),
        isA<UploadNetworkFailure>(),
        reason: '$type',
      );
    }
  });

  test('badCertificate -> certificate, never network/unknown', () async {
    final adapter = _ScriptedAdapter([
      (o, _) async => throw DioException(
        requestOptions: o,
        type: DioExceptionType.badCertificate,
      ),
    ]);
    expect(
      await failureOf(build(adapter).uploadAvatar(photo).result),
      isA<UploadCertificateFailure>(),
    );
  });

  test('cancel -> cancelled', () async {
    final adapter = _ScriptedAdapter([
      (o, cancelFuture) async {
        await cancelFuture;
        throw DioException.requestCancelled(
          requestOptions: o,
          reason: 'cancelled',
        );
      },
    ]);
    final task = build(adapter).uploadAvatar(photo);
    final outcome = failureOf(task.result);
    // Poll (real file IO precedes the request; a fixed 20 ms sleep flaked).
    for (var i = 0; i < 200 && adapter.requests.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(adapter.requests, hasLength(1));
    task.cancel();
    task.cancel(); // idempotent
    expect(await outcome, isA<UploadCancelledFailure>());
  });

  test('cancel before the request starts makes no request', () async {
    final adapter = _ScriptedAdapter([_reply(200, _okBody)]);
    final task = build(adapter).uploadAvatar(photo)..cancel();
    expect(await failureOf(task.result), isA<UploadCancelledFailure>());
    expect(adapter.requests, isEmpty);
  });

  test('over 5 MB -> tooLarge with zero requests', () async {
    final big = File('${tmp.path}/big.jpg')
      ..writeAsBytesSync(Uint8List(kMaxUploadBytes + 1));
    final adapter = _ScriptedAdapter([_reply(200, _okBody)]);
    expect(
      await failureOf(build(adapter).uploadAvatar(big).result),
      isA<UploadTooLargeFailure>(),
    );
    expect(adapter.requests, isEmpty);
  });

  test('exactly 5 MB is sent', () async {
    final edge = File('${tmp.path}/edge.jpg')
      ..writeAsBytesSync(Uint8List(kMaxUploadBytes));
    final adapter = _ScriptedAdapter([_reply(200, _okBody)]);
    await build(adapter).uploadAvatar(edge).result;
    expect(adapter.requests, hasLength(1));
  });

  test('401 is retried once with a fresh FormData, then succeeds', () async {
    final adapter = _ScriptedAdapter([_reply(401), _reply(200, _okBody)]);
    final url = await build(adapter).uploadAvatar(photo).result;
    expect(url, isNotEmpty);
    expect(adapter.requests, hasLength(2));
    expect(
      identical(adapter.requests[0].data, adapter.requests[1].data),
      isFalse,
    );
  });

  test('a second 401 -> unauthorized (no loop)', () async {
    final adapter = _ScriptedAdapter([_reply(401)]);
    expect(
      await failureOf(build(adapter).uploadAvatar(photo).result),
      isA<UploadUnauthorizedFailure>(),
    );
    expect(adapter.requests, hasLength(2));
  });

  test('401 retry is skipped when the session has ended', () async {
    final adapter = _ScriptedAdapter([_reply(401), _reply(200, _okBody)]);
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..httpClientAdapter = adapter
      ..interceptors.add(ErrorMapperInterceptor());
    final repo = HttpMediaUploadRepository(
      dio: dio,
      isSessionLive: () => false,
    );
    expect(
      await failureOf(repo.uploadAvatar(photo).result),
      isA<UploadUnauthorizedFailure>(),
    );
    expect(adapter.requests, hasLength(1));
  });

  // Phase 367 audit (security INFO): the one 401 retry re-sends the photo
  // under whatever token is current. If the signed-in account changed between
  // the 401 and the retry, that would deliver user A's photo as user B's
  // avatar — so the retry requires the SAME user who started the upload.
  group('401 retry is bound to the user who started the upload', () {
    HttpMediaUploadRepository withUser(
      _ScriptedAdapter adapter,
      String? Function() currentUserId,
    ) {
      final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
        ..httpClientAdapter = adapter
        ..interceptors.add(ErrorMapperInterceptor());
      return HttpMediaUploadRepository(dio: dio, currentUserId: currentUserId);
    }

    test('same user -> retried once, succeeds', () async {
      final adapter = _ScriptedAdapter([_reply(401), _reply(200, _okBody)]);
      final url = await withUser(
        adapter,
        () => 'u1',
      ).uploadAvatar(photo).result;
      expect(url, isNotEmpty);
      expect(adapter.requests, hasLength(2));
    });

    test('user switched after the 401 -> NO retry, unauthorized', () async {
      String? user = 'u1';
      final adapter = _ScriptedAdapter([
        (_, _) async {
          user = 'u2'; // account switch lands while the 401 is in flight
          return _json(401, const <String, Object>{'success': false});
        },
        _reply(200, _okBody),
      ]);
      expect(
        await failureOf(
          withUser(adapter, () => user).uploadAvatar(photo).result,
        ),
        isA<UploadUnauthorizedFailure>(),
      );
      expect(adapter.requests, hasLength(1), reason: 'never re-sent as u2');
    });

    test('signed out after the 401 -> NO retry', () async {
      String? user = 'u1';
      final adapter = _ScriptedAdapter([
        (_, _) async {
          user = null;
          return _json(401, const <String, Object>{'success': false});
        },
        _reply(200, _okBody),
      ]);
      expect(
        await failureOf(
          withUser(adapter, () => user).uploadAvatar(photo).result,
        ),
        isA<UploadUnauthorizedFailure>(),
      );
      expect(adapter.requests, hasLength(1));
    });

    test('no user when it started -> NO retry', () async {
      final adapter = _ScriptedAdapter([_reply(401), _reply(200, _okBody)]);
      expect(
        await failureOf(
          withUser(adapter, () => null).uploadAvatar(photo).result,
        ),
        isA<UploadUnauthorizedFailure>(),
      );
      expect(adapter.requests, hasLength(1));
    });
  });

  test('progress restarts from 0 on the 401 retry, not frozen', () async {
    final adapter = _ScriptedAdapter([
      (o, _) async {
        o.onSendProgress?.call(50, 100);
        return _json(401, const <String, Object>{'success': false});
      },
      (o, _) async {
        o.onSendProgress?.call(30, 100);
        o.onSendProgress?.call(100, 100);
        return _json(200, _okBody);
      },
    ]);
    final task = build(adapter).uploadAvatar(photo);
    final seen = <double>[];
    final done = task.progress.listen(seen.add).asFuture<void>();
    await task.result;
    await done.timeout(const Duration(seconds: 2));
    expect(seen, <double>[0.5, 0.0, 0.3, 1.0]);
  });

  test('progress is monotonic, >=1% steps, ends at 1.0, then closes', () async {
    final adapter = _ScriptedAdapter([
      (o, _) async {
        for (final sent in <int>[0, 10, 10, 10, 50, 50, 99, 100]) {
          o.onSendProgress?.call(sent, 100);
        }
        return _json(200, _okBody);
      },
    ]);
    final task = build(adapter).uploadAvatar(photo);
    final seen = <double>[];
    final done = task.progress.listen(seen.add).asFuture<void>();
    await task.result;
    await done.timeout(const Duration(seconds: 2)); // stream closed
    expect(seen, <double>[0.1, 0.5, 0.99, 1.0]);
    expect(seen.last, 1.0);
    for (var i = 1; i < seen.length; i++) {
      expect(seen[i], greaterThan(seen[i - 1]));
    }
  });

  test('progress stream closes on failure too', () async {
    final task = build(_ScriptedAdapter([_reply(503)])).uploadAvatar(photo);
    final done = task.progress.toList();
    await failureOf(task.result);
    expect(await done.timeout(const Duration(seconds: 2)), isEmpty);
  });

  group('deleteAvatar', () {
    test('DELETE /api/v1/media/avatar succeeds on 204', () async {
      final adapter = _ScriptedAdapter([
        (o, _) async => ResponseBody.fromString('', 204),
      ]);
      await build(adapter).deleteAvatar();
      expect(adapter.requests.single.method, 'DELETE');
      expect(adapter.requests.single.path, '/api/v1/media/avatar');
    });

    test('503 -> storageUnavailable', () async {
      final f = build(_ScriptedAdapter([_reply(503)])).deleteAvatar();
      expect(await failureOf(f), isA<UploadStorageUnavailableFailure>());
    });
  });
}
