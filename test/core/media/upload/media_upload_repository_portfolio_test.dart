// Phase 403 (9.8, D4/D5) — the portfolio methods of HttpMediaUploadRepository
// over a scripted Dio adapter (with the real ErrorMapperInterceptor, as in
// production): paths per owner, multipart part `file` with the SNIFFED content
// type, progress, and the portfolio-scoped 409 / 503 mapping.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/media/portfolio/portfolio_owner.dart';
import 'package:beautica_mobile/core/media/portfolio/portfolio_photo.dart';
import 'package:beautica_mobile/core/media/upload/media_upload_repository.dart';
import 'package:beautica_mobile/core/media/upload/upload_failure.dart';
import 'package:beautica_mobile/core/network/error_mapper_interceptor.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Handler = Future<ResponseBody> Function(RequestOptions, Future<void>?);

/// Records every request and answers with the next scripted handler; drives
/// `onSendProgress` like a real adapter would.
final class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this._handlers);

  final List<_Handler> _handlers;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (requestStream != null) {
      final int total = options.headers[Headers.contentLengthHeader] is int
          ? options.headers[Headers.contentLengthHeader] as int
          : -1;
      var sent = 0;
      await for (final Uint8List chunk in requestStream) {
        sent += chunk.length;
        options.onSendProgress?.call(sent, total > 0 ? total : sent);
      }
    }
    final int i = requests.length - 1;
    return _handlers[i < _handlers.length ? i : _handlers.length - 1](
      options,
      cancelFuture,
    );
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(
  int status,
  Object body, {
  Map<String, List<String>> headers = const <String, List<String>>{},
}) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: <String, List<String>>{
    Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    ...headers,
  },
);

_Handler _reply(
  int status, [
  Object body = const <String, Object>{'success': false},
  Map<String, List<String>> headers = const <String, List<String>>{},
]) =>
    (_, _) async => _json(status, body, headers: headers);

const Map<String, Object> _created = <String, Object>{
  'success': true,
  'data': <String, Object>{
    'id': 'media-1',
    'url': 'https://media.test/portfolio/media-1.png',
    'entityType': 'SALON',
  },
};

const Map<String, Object> _limitBody = <String, Object>{
  'success': false,
  'data': <String, Object>{'code': 'PORTFOLIO_LIMIT_REACHED'},
  'message': 'Portfolio photo limit reached',
};

const List<int> _png = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
const List<int> _jpeg = <int>[0xFF, 0xD8, 0xFF, 0xE0];
const List<int> _webp = <int>[
  0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50, //
];

const PortfolioOwner _master = PortfolioOwner.masterSelf('master-1');
const PortfolioOwner _salon = PortfolioOwner.salon('salon-1');

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('portfolio_repo'));
  tearDown(() => tmp.deleteSync(recursive: true));

  File photo(List<int> magic, {int pad = 64}) =>
      File('${tmp.path}/photo.bin')
        ..writeAsBytesSync(<int>[...magic, ...List<int>.filled(pad, 7)]);

  HttpMediaUploadRepository build(_ScriptedAdapter adapter) {
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
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

  MultipartFile partOf(RequestOptions o) {
    final FormData form = o.data as FormData;
    expect(form.files, hasLength(1));
    expect(form.files.single.key, 'file', reason: '@RequestPart("file")');
    return form.files.single.value;
  }

  group('uploadPortfolioPhoto', () {
    test('master → POST /api/v1/media/portfolio; 201 resolves to the '
        'photo', () async {
      final adapter = _ScriptedAdapter(<_Handler>[_reply(201, _created)]);
      final PortfolioPhoto p = await build(
        adapter,
      ).uploadPortfolioPhoto(_master, photo(_png)).result;
      expect(
        p,
        const PortfolioPhoto(
          id: 'media-1',
          url: 'https://media.test/portfolio/media-1.png',
        ),
      );
      expect(adapter.requests.single.method, 'POST');
      expect(adapter.requests.single.path, '/api/v1/media/portfolio');
    });

    test('salon → POST /api/v1/salons/{salonId}/portfolio', () async {
      final adapter = _ScriptedAdapter(<_Handler>[_reply(201, _created)]);
      await build(adapter).uploadPortfolioPhoto(_salon, photo(_png)).result;
      expect(adapter.requests.single.method, 'POST');
      expect(adapter.requests.single.path, '/api/v1/salons/salon-1/portfolio');
    });

    test('declares the REAL content type + extension (never a fixed '
        'avatar.jpg / image/jpeg)', () async {
      for (final (List<int> magic, String type, String name)
          in <(List<int>, String, String)>[
            (_png, 'image/png', 'portfolio.png'),
            (_jpeg, 'image/jpeg', 'portfolio.jpg'),
            (_webp, 'image/webp', 'portfolio.webp'),
          ]) {
        final adapter = _ScriptedAdapter(<_Handler>[_reply(201, _created)]);
        await build(adapter).uploadPortfolioPhoto(_salon, photo(magic)).result;
        final MultipartFile part = partOf(adapter.requests.single);
        expect(part.contentType?.mimeType, type, reason: name);
        expect(part.filename, name);
      }
    });

    test(
      'an unrecognised format is rejected client-side, no request',
      () async {
        final adapter = _ScriptedAdapter(<_Handler>[_reply(201, _created)]);
        final UploadFailure f = await failureOf(
          build(
            adapter,
          ).uploadPortfolioPhoto(_salon, photo(<int>[1, 2, 3])).result,
        );
        expect(f, isA<UploadUnsupportedFormatFailure>());
        expect(adapter.requests, isEmpty);
      },
    );

    test('progress ends at 1.0 on success and the stream closes', () async {
      final adapter = _ScriptedAdapter(<_Handler>[_reply(201, _created)]);
      final task = build(
        adapter,
      ).uploadPortfolioPhoto(_master, photo(_png, pad: 4096));
      final List<double> seen = <double>[];
      final Completer<void> closed = Completer<void>();
      task.progress.listen(seen.add, onDone: closed.complete);
      await task.result;
      await closed.future;
      expect(seen, isNotEmpty);
      expect(seen.last, 1.0);
      for (var i = 1; i < seen.length; i++) {
        expect(seen[i], greaterThanOrEqualTo(seen[i - 1]));
      }
    });

    test('201 with an unusable body → unknown(201)', () async {
      final f = await failureOf(
        build(
          _ScriptedAdapter(<_Handler>[
            _reply(201, const <String, Object>{'data': <String, Object>{}}),
          ]),
        ).uploadPortfolioPhoto(_master, photo(_png)).result,
      );
      expect(f, isA<UploadUnknownFailure>());
      expect((f as UploadUnknownFailure).status, 201);
    });

    test('409 + data.code PORTFOLIO_LIMIT_REACHED → limit reached (both '
        'owners)', () async {
      for (final PortfolioOwner owner in <PortfolioOwner>[_master, _salon]) {
        final f = await failureOf(
          build(
            _ScriptedAdapter(<_Handler>[_reply(409, _limitBody)]),
          ).uploadPortfolioPhoto(owner, photo(_png)).result,
        );
        expect(f, isA<PortfolioLimitReachedFailure>(), reason: '$owner');
      }
    });

    test('409 with any other / no code is NOT "limit reached" '
        '(→ conflict)', () async {
      for (final Object body in <Object>[
        const <String, Object>{'success': false},
        const <String, Object>{
          'success': false,
          'data': <String, Object>{'code': 'SOMETHING_ELSE'},
        },
      ]) {
        final f = await failureOf(
          build(
            _ScriptedAdapter(<_Handler>[_reply(409, body)]),
          ).uploadPortfolioPhoto(_salon, photo(_png)).result,
        );
        expect(f, isA<UploadConflictFailure>(), reason: '$body');
      }
    });

    test('503 + Retry-After → busy (retryable), carrying the seconds; never '
        'limit reached', () async {
      final f = await failureOf(
        build(
          _ScriptedAdapter(<_Handler>[
            _reply(
              503,
              const <String, Object>{'success': false},
              const <String, List<String>>{
                'retry-after': <String>['2'],
              },
            ),
          ]),
        ).uploadPortfolioPhoto(_salon, photo(_png)).result,
      );
      expect(f, isA<UploadBusyFailure>());
      expect((f as UploadBusyFailure).retryAfterSeconds, 2);
    });

    test('503 + an unusable Retry-After → busy with null seconds (never '
        '0)', () async {
      final f = await failureOf(
        build(
          _ScriptedAdapter(<_Handler>[
            _reply(
              503,
              const <String, Object>{'success': false},
              const <String, List<String>>{
                'retry-after': <String>['soon'],
              },
            ),
          ]),
        ).uploadPortfolioPhoto(_salon, photo(_png)).result,
      );
      expect(f, isA<UploadBusyFailure>());
      expect((f as UploadBusyFailure).retryAfterSeconds, isNull);
    });

    test('503 WITHOUT Retry-After → storage unavailable', () async {
      final f = await failureOf(
        build(
          _ScriptedAdapter(<_Handler>[_reply(503)]),
        ).uploadPortfolioPhoto(_master, photo(_png)).result,
      );
      expect(f, isA<UploadStorageUnavailableFailure>());
    });

    test('403 → generic forbidden (not the salon-owner-only copy); 404 → '
        'notFound; 413 → tooLarge', () async {
      final f403 = await failureOf(
        build(
          _ScriptedAdapter(<_Handler>[_reply(403)]),
        ).uploadPortfolioPhoto(_salon, photo(_png)).result,
      );
      expect(f403, isA<UploadForbiddenFailure>());
      expect((f403 as UploadForbiddenFailure).salonOwnerOnly, isFalse);
      expect(
        await failureOf(
          build(
            _ScriptedAdapter(<_Handler>[_reply(404)]),
          ).uploadPortfolioPhoto(_salon, photo(_png)).result,
        ),
        isA<UploadNotFoundFailure>(),
      );
      expect(
        await failureOf(
          build(
            _ScriptedAdapter(<_Handler>[_reply(413)]),
          ).uploadPortfolioPhoto(_master, photo(_png)).result,
        ),
        isA<UploadTooLargeFailure>(),
      );
    });

    test('a dot-segment salon id never opens a request', () async {
      final adapter = _ScriptedAdapter(<_Handler>[_reply(201, _created)]);
      final f = await failureOf(
        build(adapter)
            .uploadPortfolioPhoto(const PortfolioOwner.salon('..'), photo(_png))
            .result,
      );
      expect(f, isA<UploadUnknownFailure>());
      expect(adapter.requests, isEmpty);
    });
  });

  group('deletePortfolioPhoto', () {
    test('never follows a redirect (audit S3, like the uploads)', () async {
      final adapter = _ScriptedAdapter(<_Handler>[
        (_, _) async => ResponseBody.fromString('', 204),
      ]);
      await build(adapter).deletePortfolioPhoto(_salon, 'media-9');
      expect(adapter.requests.single.followRedirects, isFalse);
    });

    test('master → DELETE /api/v1/media/portfolio/{mediaId}', () async {
      final adapter = _ScriptedAdapter(<_Handler>[
        (_, _) async => ResponseBody.fromString('', 204),
      ]);
      await build(adapter).deletePortfolioPhoto(_master, 'media-9');
      expect(adapter.requests.single.method, 'DELETE');
      expect(adapter.requests.single.path, '/api/v1/media/portfolio/media-9');
    });

    test(
      'salon → DELETE /api/v1/salons/{salonId}/portfolio/{mediaId}',
      () async {
        final adapter = _ScriptedAdapter(<_Handler>[
          (_, _) async => ResponseBody.fromString('', 204),
        ]);
        await build(adapter).deletePortfolioPhoto(_salon, 'media-9');
        expect(adapter.requests.single.method, 'DELETE');
        expect(
          adapter.requests.single.path,
          '/api/v1/salons/salon-1/portfolio/media-9',
        );
      },
    );

    test('404 (another master\'s row / wrong salon) → notFound; 403 → '
        'forbidden', () async {
      expect(
        await failureOf(
          build(
            _ScriptedAdapter(<_Handler>[_reply(404)]),
          ).deletePortfolioPhoto(_master, 'media-9'),
        ),
        isA<UploadNotFoundFailure>(),
      );
      expect(
        await failureOf(
          build(
            _ScriptedAdapter(<_Handler>[_reply(403)]),
          ).deletePortfolioPhoto(_salon, 'media-9'),
        ),
        isA<UploadForbiddenFailure>(),
      );
    });

    test('a dot-segment media id never opens a request', () async {
      final adapter = _ScriptedAdapter(<_Handler>[_reply(204)]);
      expect(
        await failureOf(build(adapter).deletePortfolioPhoto(_salon, '..')),
        isA<UploadUnknownFailure>(),
      );
      expect(adapter.requests, isEmpty);
    });
  });

  group('getMasterPortfolio', () {
    test('GET /api/v1/masters/{masterId}/portfolio → mapped content (broken '
        'rows dropped)', () async {
      final adapter = _ScriptedAdapter(<_Handler>[
        _reply(200, <String, Object>{
          'success': true,
          'data': <String, Object>{
            'content': <Object>[
              <String, Object>{'id': 'a', 'url': 'https://m.test/a.jpg'},
              <String, Object>{'id': 'broken'},
              <String, Object>{'id': 'b', 'url': 'https://m.test/b.jpg'},
            ],
          },
        }),
      ]);
      final List<PortfolioPhoto> out = await build(
        adapter,
      ).getMasterPortfolio('master-1');
      expect(adapter.requests.single.method, 'GET');
      expect(
        adapter.requests.single.path,
        '/api/v1/masters/master-1/portfolio',
      );
      expect(out, const <PortfolioPhoto>[
        PortfolioPhoto(id: 'a', url: 'https://m.test/a.jpg'),
        PortfolioPhoto(id: 'b', url: 'https://m.test/b.jpg'),
      ]);
    });

    test('404 → a typed NotFoundFailure', () async {
      final repo = build(_ScriptedAdapter(<_Handler>[_reply(404)]));
      await expectLater(
        repo.getMasterPortfolio('master-1'),
        throwsA(isA<NotFoundFailure>()),
      );
    });

    test('a dot-segment master id never opens a request', () async {
      final adapter = _ScriptedAdapter(<_Handler>[_reply(200)]);
      await expectLater(
        build(adapter).getMasterPortfolio('..'),
        throwsA(isA<Failure>()),
      );
      expect(adapter.requests, isEmpty);
    });
  });

  group('mapUploadFailure is portfolio-SCOPED (D5)', () {
    DioException err(int status, Object body, [Map<String, List<String>>? h]) {
      final RequestOptions o = RequestOptions(path: '/x');
      return DioException(
        requestOptions: o,
        type: DioExceptionType.badResponse,
        response: Response<Object>(
          requestOptions: o,
          statusCode: status,
          data: body,
          headers: Headers.fromMap(h ?? <String, List<String>>{}),
        ),
      );
    }

    test('the limit code on a NON-portfolio path stays conflict', () {
      expect(
        mapUploadFailure(err(409, _limitBody)),
        isA<UploadConflictFailure>(),
      );
      expect(
        mapUploadFailure(err(409, _limitBody), portfolio: true),
        isA<PortfolioLimitReachedFailure>(),
      );
    });

    test('503 + Retry-After on a NON-portfolio path stays storage', () {
      final Map<String, List<String>> h = <String, List<String>>{
        'retry-after': <String>['2'],
      };
      expect(
        mapUploadFailure(err(503, const <String, Object>{}, h)),
        isA<UploadStorageUnavailableFailure>(),
      );
      expect(
        mapUploadFailure(
          err(503, const <String, Object>{}, h),
          portfolio: true,
        ),
        isA<UploadBusyFailure>(),
      );
    });
  });
}
