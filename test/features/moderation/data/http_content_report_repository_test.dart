// Phase 424 — HttpContentReportRepository over the REAL generated
// ReportControllerApi + standardSerializers + the production
// ErrorMapperInterceptor, with only the transport stubbed.
//
// Proves at the wire boundary:
//   • the exact JSON body (backend 395 enum wire names, trimmed comment, a
//     blank comment omitted);
//   • the 201/200 envelope → ContentReport mapping, and a 2xx envelope with no
//     report → ResponseUnusableFailure;
//   • 429 → ServerFailure(statusCode: 429) even though the shared interceptor
//     attaches an UnknownFailure for it (no generic 429 arm), 404 →
//     NotFoundFailure, 400 → ValidationFailure, 5xx → ServerFailure, transport
//     errors → NetworkFailure;
//   • the provider wiring returns the HTTP implementation.

import 'dart:convert';
import 'dart:typed_data';

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/error_mapper_interceptor.dart';
import 'package:beautica_mobile/features/moderation/application/report_notifier.dart';
import 'package:beautica_mobile/features/moderation/data/content_report_repository.dart';
import 'package:beautica_mobile/features/moderation/domain/content_report.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const String _path = '/api/v1/reports';

/// Replies with a fixed status + JSON body and records every request body.
final class _StubAdapter implements HttpClientAdapter {
  _StubAdapter({required this.status, this.body, this.throwType});

  final int status;
  final Object? body;
  final DioExceptionType? throwType;
  final List<Map<String, Object?>> sentBodies = <Map<String, Object?>>[];
  final List<String> paths = <String>[];

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
    paths.add(options.path);
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

({HttpContentReportRepository repo, _StubAdapter adapter}) _build({
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
    repo: HttpContentReportRepository(
      ReportControllerApi(dio, standardSerializers),
    ),
    adapter: adapter,
  );
}

Map<String, Object?> _okEnvelope({String status = 'OPEN'}) => <String, Object?>{
  'success': true,
  'data': <String, Object?>{
    'id': 'report-42',
    'status': status,
    'createdAt': '2026-10-28T10:15:00Z',
  },
};

Map<String, Object?> _errorEnvelope(String message) => <String, Object?>{
  'success': false,
  'message': message,
};

ContentReportRequest _req({
  ReportTargetType type = ReportTargetType.review,
  ReportReason reason = ReportReason.spam,
  String? comment,
}) => ContentReportRequest(
  targetType: type,
  targetId: '7b0c3c52-0000-4000-8000-000000000001',
  reason: reason,
  comment: comment,
);

void main() {
  group('request body', () {
    test('POSTs /api/v1/reports with backend wire names and a trimmed '
        'comment', () async {
      final b = _build(status: 201, body: _okEnvelope());
      await b.repo.create(
        _req(
          type: ReportTargetType.clientReview,
          reason: ReportReason.other,
          comment: '  образливий текст  ',
        ),
      );
      expect(b.adapter.paths.single, _path);
      expect(b.adapter.sentBodies.single, <String, Object?>{
        'targetType': 'CLIENT_REVIEW',
        'targetId': '7b0c3c52-0000-4000-8000-000000000001',
        'reason': 'OTHER',
        'comment': 'образливий текст',
      });
    });

    test('a blank comment is omitted from the wire', () async {
      final b = _build(status: 201, body: _okEnvelope());
      await b.repo.create(_req(comment: '   '));
      expect(b.adapter.sentBodies.single.containsKey('comment'), isFalse);
    });

    test(
      'every ReportTargetType / ReportReason sends the backend enum literal',
      () async {
        // Fixed literals mirror beautica-backend
        // com.beautica.moderation.entity.ReportTargetType / ReportReason.
        const Map<ReportTargetType, String> expectedTypes =
            <ReportTargetType, String>{
              ReportTargetType.review: 'REVIEW',
              ReportTargetType.clientReview: 'CLIENT_REVIEW',
              ReportTargetType.portfolioPhoto: 'PORTFOLIO_PHOTO',
              ReportTargetType.masterProfile: 'MASTER_PROFILE',
              ReportTargetType.salonProfile: 'SALON_PROFILE',
              ReportTargetType.clientProfile: 'CLIENT_PROFILE',
            };
        const Map<ReportReason, String> expectedReasons =
            <ReportReason, String>{
              ReportReason.spam: 'SPAM',
              ReportReason.offensive: 'OFFENSIVE',
              ReportReason.harassment: 'HARASSMENT',
              ReportReason.falseInfo: 'FALSE_INFO',
              ReportReason.sexualContent: 'SEXUAL_CONTENT',
              ReportReason.other: 'OTHER',
            };
        expect(expectedTypes.keys.toSet(), ReportTargetType.values.toSet());
        expect(expectedReasons.keys.toSet(), ReportReason.values.toSet());
        // wireName is documented as the backend constant (also the sheet key).
        for (final MapEntry<ReportTargetType, String> t
            in expectedTypes.entries) {
          expect(t.key.wireName, t.value, reason: '${t.key}.wireName');
        }
        for (final MapEntry<ReportReason, String> r
            in expectedReasons.entries) {
          expect(r.key.wireName, r.value, reason: '${r.key}.wireName');
        }

        for (final MapEntry<ReportTargetType, String> t
            in expectedTypes.entries) {
          final b = _build(status: 201, body: _okEnvelope());
          await b.repo.create(_req(type: t.key, comment: 'abcdef'));
          expect(
            b.adapter.sentBodies.single['targetType'],
            t.value,
            reason: '${t.key}',
          );
        }
        for (final MapEntry<ReportReason, String> r
            in expectedReasons.entries) {
          final b = _build(status: 201, body: _okEnvelope());
          await b.repo.create(_req(reason: r.key, comment: 'abcdef'));
          expect(
            b.adapter.sentBodies.single['reason'],
            r.value,
            reason: '${r.key}',
          );
        }
      },
    );
  });

  group('success', () {
    test('201 maps the envelope to a ContentReport', () async {
      final b = _build(status: 201, body: _okEnvelope());
      final ContentReport r = await b.repo.create(_req());
      expect(r.id, 'report-42');
      expect(r.status, 'OPEN');
      expect(r.createdAt, DateTime.utc(2026, 10, 28, 10, 15));
    });

    test('200 idempotent repeat resolves the same way', () async {
      final b = _build(status: 200, body: _okEnvelope());
      expect((await b.repo.create(_req())).id, 'report-42');
    });

    test(
      '2xx with no report in the envelope → ResponseUnusableFailure',
      () async {
        final b = _build(status: 201, body: <String, Object?>{'success': true});
        await expectLater(
          b.repo.create(_req()),
          throwsA(isA<ResponseUnusableFailure>()),
        );
      },
    );

    test(
      '2xx with an unknown status constant → ResponseUnusableFailure',
      () async {
        final b = _build(status: 201, body: _okEnvelope(status: 'WHATEVER'));
        await expectLater(
          b.repo.create(_req()),
          throwsA(isA<ResponseUnusableFailure>()),
        );
      },
    );
  });

  // Phase 428 add-on — GET /api/v1/reports/mine (backend 415).
  group('mine', () {
    test(
      'GETs /api/v1/reports/mine and maps every known target type',
      () async {
        final b = _build(
          status: 200,
          body: <String, Object?>{
            'success': true,
            'data': <Object?>[
              <String, Object?>{'targetType': 'REVIEW', 'targetId': 'r1'},
              <String, Object?>{
                'targetType': 'PORTFOLIO_PHOTO',
                'targetId': 'p1',
              },
              <String, Object?>{
                'targetType': 'MASTER_PROFILE',
                'targetId': 'm1',
              },
              <String, Object?>{
                'targetType': 'SALON_PROFILE',
                'targetId': 's1',
              },
              <String, Object?>{
                'targetType': 'CLIENT_PROFILE',
                'targetId': 'c1',
              },
              <String, Object?>{
                'targetType': 'CLIENT_REVIEW',
                'targetId': 'cr1',
              },
              // Dropped: unknown type, missing id.
              <String, Object?>{'targetType': 'MARTIAN', 'targetId': 'x'},
              <String, Object?>{'targetType': 'REVIEW'},
            ],
          },
        );
        final Set<ReportedTarget> got = await b.repo.mine();
        expect(b.adapter.paths.single, '/api/v1/reports/mine');
        expect(got, <ReportedTarget>{
          (type: ReportTargetType.review, id: 'r1'),
          (type: ReportTargetType.portfolioPhoto, id: 'p1'),
          (type: ReportTargetType.masterProfile, id: 'm1'),
          (type: ReportTargetType.salonProfile, id: 's1'),
          (type: ReportTargetType.clientProfile, id: 'c1'),
          (type: ReportTargetType.clientReview, id: 'cr1'),
        });
      },
    );

    test('503 → ServerFailure', () async {
      final b = _build(status: 503, body: <String, Object?>{'success': false});
      await expectLater(b.repo.mine(), throwsA(isA<ServerFailure>()));
    });
  });

  group('error mapping', () {
    test('429 → ServerFailure(statusCode: 429) → rateLimited banner', () async {
      final b = _build(status: 429, body: _errorEnvelope('Too many reports'));
      Object? thrown;
      try {
        await b.repo.create(_req());
      } catch (e) {
        thrown = e;
      }
      expect(thrown, isA<ServerFailure>());
      expect((thrown! as ServerFailure).statusCode, 429);
      expect(reportErrorKindOf(thrown as Failure), ReportErrorKind.rateLimited);
    });

    test('404 → NotFoundFailure → generic banner', () async {
      final b = _build(status: 404, body: _errorEnvelope('Not found'));
      Object? thrown;
      try {
        await b.repo.create(_req());
      } catch (e) {
        thrown = e;
      }
      expect(thrown, isA<NotFoundFailure>());
      expect(reportErrorKindOf(thrown! as Failure), ReportErrorKind.generic);
    });

    test('400 (self-report / bad body) → ValidationFailure', () async {
      final b = _build(status: 400, body: _errorEnvelope('Cannot report'));
      await expectLater(
        b.repo.create(_req()),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('503 → ServerFailure(503)', () async {
      final b = _build(status: 503, body: _errorEnvelope('down'));
      await expectLater(
        b.repo.create(_req()),
        throwsA(
          isA<ServerFailure>().having((f) => f.statusCode, 'statusCode', 503),
        ),
      );
    });

    test('connection error → NetworkFailure', () async {
      final b = _build(status: 0, throwType: DioExceptionType.connectionError);
      await expectLater(b.repo.create(_req()), throwsA(isA<NetworkFailure>()));
    });
  });

  group('mapContentReportDioException (no interceptor attached)', () {
    DioException bad(int code) => DioException(
      requestOptions: RequestOptions(path: _path),
      type: DioExceptionType.badResponse,
      response: Response<dynamic>(
        requestOptions: RequestOptions(path: _path),
        statusCode: code,
      ),
    );

    test('status arms win over an attached UnknownFailure', () {
      final DioException e = DioException(
        requestOptions: RequestOptions(path: _path),
        type: DioExceptionType.badResponse,
        error: const UnknownFailure(),
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: _path),
          statusCode: 429,
        ),
      );
      expect(
        mapContentReportDioException(e),
        isA<ServerFailure>().having((f) => f.statusCode, 'statusCode', 429),
      );
    });

    test('bare 400 / 422 → ValidationFailure, 401 → UnauthorizedFailure', () {
      expect(mapContentReportDioException(bad(400)), isA<ValidationFailure>());
      expect(mapContentReportDioException(bad(422)), isA<ValidationFailure>());
      expect(
        mapContentReportDioException(bad(401)),
        isA<UnauthorizedFailure>(),
      );
    });

    test('timeouts → NetworkFailure; cancel → UnknownFailure', () {
      for (final DioExceptionType t in <DioExceptionType>[
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      ]) {
        expect(
          mapContentReportDioException(
            DioException(
              requestOptions: RequestOptions(path: _path),
              type: t,
            ),
          ),
          isA<NetworkFailure>(),
          reason: '$t',
        );
      }
      expect(
        mapContentReportDioException(
          DioException(
            requestOptions: RequestOptions(path: _path),
            type: DioExceptionType.cancel,
          ),
        ),
        isA<UnknownFailure>(),
      );
    });
  });

  group('provider wiring', () {
    test('contentReportRepositoryProvider is the HTTP implementation', () {
      final Dio dio = Dio();
      final ProviderContainer c = ProviderContainer(
        overrides: [
          reportApiProvider.overrideWithValue(
            ReportControllerApi(dio, standardSerializers),
          ),
        ],
      );
      addTearDown(c.dispose);
      expect(
        c.read(contentReportRepositoryProvider),
        isA<HttpContentReportRepository>(),
      );
    });
  });
}
