// Phase 070 QA — wire-level contract for the shared media-upload seam.
//
// Complements `media_upload_repository_test.dart` (which asserts on the
// RequestOptions) by reading the ACTUAL multipart bytes the transport receives,
// replaying server-shaped bodies (the backend's `ApiResponse` envelope, a
// Tomcat-style non-JSON 413), pinning cancel semantics on the progress stream,
// and capturing what the real `LoggingInterceptor` writes for a /media/ route.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:beautica_mobile/core/media/upload/media_upload_repository.dart';
import 'package:beautica_mobile/core/media/upload/upload_failure.dart';
import 'package:beautica_mobile/core/network/error_mapper_interceptor.dart';
import 'package:beautica_mobile/core/network/logging_interceptor.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the transport saw for one request.
final class _Wire {
  _Wire(this.options, this.body);

  final RequestOptions options;

  /// The complete multipart body as latin1 text (binary-safe for substring
  /// assertions).
  final String body;
}

typedef _Handler =
    Future<ResponseBody> Function(RequestOptions options, Future<void>? cancel);

/// Transport that DRAINS the request stream (so the real multipart bytes are
/// observable) and then answers with the next scripted handler.
final class _WireAdapter implements HttpClientAdapter {
  _WireAdapter(this._handlers, {this.drain = true});

  final List<_Handler> _handlers;

  /// Draining the stream makes Dio itself fire `onSendProgress` with the real
  /// byte counts (observed: a 1.0 event even when the server then answers 503).
  /// Tests that script their OWN progress callbacks turn this off.
  final bool drain;
  final List<_Wire> wire = <_Wire>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final bytes = <int>[];
    if (drain && requestStream != null) {
      await for (final chunk in requestStream) {
        bytes.addAll(chunk);
      }
    }
    wire.add(_Wire(options, latin1.decode(bytes)));
    final i = wire.length - 1;
    return _handlers[i < _handlers.length ? i : _handlers.length - 1](
      options,
      cancelFuture,
    );
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonBody(int status, Object body) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: <String, List<String>>{
    Headers.contentTypeHeader: <String>[Headers.jsonContentType],
  },
);

_Handler _json(int status, Object body) =>
    (_, _) async => _jsonBody(status, body);

const Map<String, Object> _ok = <String, Object>{
  'success': true,
  'data': <String, Object>{'avatarUrl': 'https://media.test/avatars/u1/1.jpg'},
  'message': 'OK',
};

void main() {
  late Directory tmp;
  late File photo;

  // A deliberately identifying on-disk name: it must never leave the device.
  const secretName = 'olena-kovalenko-passport-scan.jpg';
  const fileBytes = <int>[0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46];

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('upload_wire_test');
    photo = File('${tmp.path}/$secretName')..writeAsBytesSync(fileBytes);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  HttpMediaUploadRepository build(
    HttpClientAdapter adapter, {
    List<Interceptor> extra = const <Interceptor>[],
  }) {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..httpClientAdapter = adapter
      ..interceptors.addAll(<Interceptor>[...extra, ErrorMapperInterceptor()]);
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

  group('multipart wire format', () {
    test('Content-Type header carries a multipart boundary and the part '
        'is named "file" / avatar.jpg / image/jpeg', () async {
      final adapter = _WireAdapter(<_Handler>[_json(200, _ok)]);
      await build(adapter).uploadAvatar(photo).result;

      final w = adapter.wire.single;
      final ct = w.options.headers[Headers.contentTypeHeader]?.toString();
      expect(ct, isNotNull, reason: 'Content-Type header must be on the wire');
      expect(ct, matches(RegExp(r'^multipart/form-data; boundary=\S+$')));
      expect(w.body, contains('name="file"'));
      expect(w.body, contains('filename="avatar.jpg"'));
      expect(w.body.toLowerCase(), contains('content-type: image/jpeg'));
    });

    test(
      'the on-disk file name never reaches the wire (neutral constant)',
      () async {
        final adapter = _WireAdapter(<_Handler>[_json(200, _ok)]);
        await build(adapter).uploadAvatar(photo).result;

        final body = adapter.wire.single.body;
        expect(body, isNot(contains(secretName)));
        expect(body, isNot(contains('olena')));
        expect(body, isNot(contains(tmp.path)));
        // …while the bytes themselves DO travel.
        expect(body, contains(latin1.decode(fileBytes)));
      },
    );
  });

  group('server-shaped failures', () {
    // Backend `ApiResponse.error(msg)` envelope: success:false, data:null.
    Map<String, Object?> envelope(String message) => <String, Object?>{
      'success': false,
      'data': null,
      'message': message,
    };

    test(
      '413 with the Spring MaxUploadSizeExceeded envelope -> tooLarge',
      () async {
        final adapter = _WireAdapter(<_Handler>[
          _json(413, envelope('Upload exceeds the maximum allowed size')),
        ]);
        expect(
          await failureOf(build(adapter).uploadAvatar(photo).result),
          isA<UploadTooLargeFailure>(),
        );
        expect(adapter.wire, hasLength(1), reason: '413 is terminal, no retry');
      },
    );

    test(
      '413 with a NON-JSON (proxy / Tomcat HTML) body -> tooLarge',
      () async {
        final adapter = _WireAdapter(<_Handler>[
          (_, _) async => ResponseBody.fromString(
            '<html><body><h1>413 Request Entity Too Large</h1></body></html>',
            413,
            headers: <String, List<String>>{
              Headers.contentTypeHeader: <String>['text/html'],
            },
          ),
        ]);
        expect(
          await failureOf(build(adapter).uploadAvatar(photo).result),
          isA<UploadTooLargeFailure>(),
        );
      },
    );

    test('413 with an EMPTY body -> tooLarge', () async {
      final adapter = _WireAdapter(<_Handler>[
        (_, _) async => ResponseBody.fromString('', 413),
      ]);
      expect(
        await failureOf(build(adapter).uploadAvatar(photo).result),
        isA<UploadTooLargeFailure>(),
      );
    });

    test(
      '503 media-storage-not-configured envelope -> storageUnavailable',
      () async {
        final adapter = _WireAdapter(<_Handler>[
          _json(503, envelope('Media storage is not configured')),
        ]);
        expect(
          await failureOf(build(adapter).uploadAvatar(photo).result),
          isA<UploadStorageUnavailableFailure>(),
        );
        expect(adapter.wire, hasLength(1), reason: '503 is not retried here');
      },
    );

    test('404 "Resource not found" envelope -> notFound', () async {
      final adapter = _WireAdapter(<_Handler>[
        _json(404, envelope('Resource not found')),
      ]);
      expect(
        await failureOf(build(adapter).uploadAvatar(photo).result),
        isA<UploadNotFoundFailure>(),
      );
    });

    test('400 unsupported-format envelope -> unsupportedFormat', () async {
      final adapter = _WireAdapter(<_Handler>[
        _json(
          400,
          envelope(
            'Unsupported image format — JPEG, PNG, and WebP are accepted',
          ),
        ),
      ]);
      expect(
        await failureOf(build(adapter).uploadAvatar(photo).result),
        isA<UploadUnsupportedFormatFailure>(),
      );
    });
  });

  group('cancel semantics', () {
    test('after cancel() the progress stream is closed and no further '
        'events arrive, even if the transport keeps reporting', () async {
      late RequestOptions captured;
      final release = Completer<void>();
      final adapter = _WireAdapter(<_Handler>[
        (o, cancel) async {
          captured = o;
          o.onSendProgress?.call(50, 100); // one legitimate event
          await cancel;
          release.complete();
          throw DioException.requestCancelled(requestOptions: o, reason: 'x');
        },
      ], drain: false);
      final task = build(adapter).uploadAvatar(photo);
      final seen = <double>[];
      var closed = false;
      task.progress.listen(seen.add, onDone: () => closed = true);
      final outcome = failureOf(task.result);

      // Poll: real file IO precedes the request; a fixed sleep flaked.
      for (var i = 0; i < 200 && seen.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(seen, <double>[0.5]);

      task.cancel();
      expect(await outcome, isA<UploadCancelledFailure>());
      await release.future;
      await Future<void>.delayed(Duration.zero);
      expect(closed, isTrue, reason: 'controller must close on cancel');
      // A late progress callback from the transport must be swallowed.
      captured.onSendProgress?.call(100, 100);
      await Future<void>.delayed(Duration.zero);
      expect(seen, <double>[0.5], reason: 'no events after cancel');
      expect(seen, isNot(contains(1.0)));
    });

    test('cancel after completion is a harmless no-op', () async {
      final adapter = _WireAdapter(<_Handler>[_json(200, _ok)]);
      final task = build(adapter).uploadAvatar(photo);
      await task.result;
      expect(task.cancel, returnsNormally);
    });

    test(
      'a cancelled upload never reaches the transport a second time',
      () async {
        final adapter = _WireAdapter(<_Handler>[
          (o, cancel) async {
            await cancel;
            throw DioException.requestCancelled(requestOptions: o, reason: 'x');
          },
        ], drain: false);
        final task = build(adapter).uploadAvatar(photo);
        final outcome = failureOf(task.result);
        for (var i = 0; i < 200 && adapter.wire.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        task.cancel();
        await outcome;
        expect(adapter.wire, hasLength(1));
      },
    );
  });

  group('progress throttling', () {
    test(
      'sub-1% jitter is dropped; values never regress; ends exactly 1.0',
      () async {
        final adapter = _WireAdapter(<_Handler>[
          (o, _) async {
            // 1000 tiny steps — a naive forwarder would emit 1000 events.
            for (var sent = 1; sent <= 1000; sent++) {
              o.onSendProgress?.call(sent, 1000);
            }
            // A regressing callback must not move the stream backwards.
            o.onSendProgress?.call(10, 1000);
            return _jsonBody(200, _ok);
          },
        ], drain: false);
        final task = build(adapter).uploadAvatar(photo);
        final seen = <double>[];
        task.progress.listen(seen.add);
        await task.result;
        await Future<void>.delayed(Duration.zero);

        expect(seen.length, lessThanOrEqualTo(101));
        expect(seen.last, 1.0);
        expect(seen.where((v) => v == 1.0), hasLength(1));
        for (var i = 1; i < seen.length; i++) {
          expect(seen[i], greaterThan(seen[i - 1]));
        }
      },
    );
  });

  group('logging hygiene (real LoggingInterceptor, captured sink)', () {
    test(
      'success path logs neither bytes, token, file name, nor URL',
      () async {
        final lines = <String>[];
        final adapter = _WireAdapter(<_Handler>[_json(200, _ok)]);
        final repo = build(
          adapter,
          extra: <Interceptor>[
            LoggingInterceptor(
              sink: (m, {String name = '', int level = 0, Object? error}) =>
                  lines.add('$m ${error ?? ''}'),
            ),
            // Stand-in for AuthInterceptor: a real Bearer in the headers.
            InterceptorsWrapper(
              onRequest: (o, h) {
                o.headers['Authorization'] = 'Bearer super-secret-jwt';
                h.next(o);
              },
            ),
          ],
        );
        await repo.uploadAvatar(photo).result;

        final log = lines.join('\n');
        expect(
          log,
          isNotEmpty,
          reason: 'sink must be wired or this is vacuous',
        );
        expect(log, contains('/api/v1/media/avatar'));
        expect(log, contains('[REDACTED]'));
        expect(log, isNot(contains('FormData')));
        expect(log, isNot(contains(secretName)));
        expect(log, isNot(contains('olena')));
        expect(log, isNot(contains('super-secret-jwt')));
        expect(log, isNot(contains('avatars/u1')));
      },
    );

    test(
      'failure path logs neither the server body nor the file name',
      () async {
        final lines = <String>[];
        final adapter = _WireAdapter(<_Handler>[
          _json(503, <String, Object?>{
            'success': false,
            'message': 'internal-detail-r2-bucket-xyz',
          }),
        ]);
        final repo = build(
          adapter,
          extra: <Interceptor>[
            LoggingInterceptor(
              sink: (m, {String name = '', int level = 0, Object? error}) =>
                  lines.add('$m ${error ?? ''}'),
            ),
          ],
        );
        await failureOf(repo.uploadAvatar(photo).result);

        final log = lines.join('\n');
        expect(log, contains('<-- ERROR'));
        expect(log, isNot(contains('internal-detail-r2-bucket-xyz')));
        expect(log, isNot(contains(secretName)));
      },
    );
  });
}
