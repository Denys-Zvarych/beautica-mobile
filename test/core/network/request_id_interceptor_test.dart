// Phase 410 (R.3 D5) — X-Request-Id + scrubbed http breadcrumbs.
import 'dart:convert';
import 'dart:typed_data';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/auth_interceptor.dart';
import 'package:beautica_mobile/core/network/dio_provider.dart';
import 'package:beautica_mobile/core/network/error_mapper_interceptor.dart';
import 'package:beautica_mobile/core/network/request_id_interceptor.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../helpers/fakes/fake_secure_storage.dart';

final RegExp _hex32 = RegExp(r'^[0-9a-f]{32}$');

/// Answers every request with [status]; echoes nothing unless [echo].
final class _Adapter implements HttpClientAdapter {
  _Adapter(this.status, {this.echo = false, this.body});

  final int status;
  final bool echo;
  final Map<String, dynamic>? body;
  final List<RequestOptions> seen = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seen.add(options);
    final Object? sent = options.headers[kRequestIdHeader];
    return ResponseBody.fromString(
      jsonEncode(body ?? <String, dynamic>{'data': 'secret canary@x.ua'}),
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
        if (echo && sent is String) kRequestIdHeader: <String>[sent],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _NoopTransport implements Transport {
  @override
  Future<SentryId?> send(SentryEnvelope envelope) async =>
      const SentryId.empty();
}

Dio _dio(_Adapter adapter) =>
    Dio(BaseOptions(baseUrl: 'https://api.beautica.app'))
      ..httpClientAdapter = adapter
      ..interceptors.addAll(<Interceptor>[
        RequestIdInterceptor(),
        ErrorMapperInterceptor(),
      ]);

void main() {
  late List<Breadcrumb> crumbs;

  setUp(() async {
    crumbs = <Breadcrumb>[];
    await Sentry.init((SentryOptions o) {
      o
        ..dsn = 'https://public@o1.ingest.de.sentry.io/2'
        ..transport = _NoopTransport()
        ..beforeBreadcrumb = (Breadcrumb? b, Hint _) {
          if (b != null && b.category == 'http') crumbs.add(b);
          return b;
        };
    });
  });
  tearDown(Sentry.close);

  test('outbound X-Request-Id is 32 hex, fresh per request', () async {
    final _Adapter adapter = _Adapter(200);
    final Dio dio = _dio(adapter);
    await dio.get<dynamic>('/api/v1/a');
    await dio.get<dynamic>('/api/v1/a');
    final List<Object?> ids = adapter.seen
        .map((RequestOptions o) => o.headers[kRequestIdHeader])
        .toList();
    expect(
      ids[0],
      isA<String>().having((String s) => s, 'id', matches(_hex32)),
    );
    expect(ids[1], matches(_hex32));
    expect(ids[0], isNot(ids[1]));
  });

  test(
    'breadcrumb: method / normalised path / status / request_id only',
    () async {
      final _Adapter adapter = _Adapter(200);
      await _dio(adapter).get<dynamic>(
        '/api/v1/masters/3f2b8c1e-1111-4222-8333-944445555666/slots',
        queryParameters: <String, dynamic>{'phone': '+380501112233'},
      );
      expect(crumbs, hasLength(1));
      final Map<String, dynamic> data = crumbs.single.data!;
      expect(data['method'], 'GET');
      expect(data['path'], '/api/v1/masters/{id}/slots');
      expect(data['status'], 200);
      expect(data['request_id'], adapter.seen.single.headers[kRequestIdHeader]);
      expect(data['duration_ms'], isA<int>());
      expect(data.keys.toSet(), <String>{
        'method',
        'path',
        'status',
        'request_id',
        'duration_ms',
      });
      final String raw = '${crumbs.single.toJson()}';
      expect(raw, isNot(contains('phone')));
      expect(raw, isNot(contains('380501112233')));
      expect(raw, isNot(contains('canary@x.ua')), reason: 'no body');
      expect(raw, isNot(contains('Authorization')), reason: 'no headers');
    },
  );

  test(
    'error path: breadcrumb + mapped Failure carries the request id',
    () async {
      final _Adapter adapter = _Adapter(404, echo: true);
      final Dio dio = _dio(adapter);
      Object? thrown;
      try {
        await dio.get<dynamic>(
          '/api/v1/invite/accept/Zx9vQ2kLm8Np4Rt6Yw1Bc3Df5Gh7Jk0',
        );
      } on DioException catch (e) {
        thrown = e.error;
      }
      final Object? sent = adapter.seen.single.headers[kRequestIdHeader];
      expect(thrown, isA<NotFoundFailure>());
      expect((thrown! as Failure).requestId, sent);
      expect(crumbs.single.data!['status'], 404);
      expect(crumbs.single.data!['path'], '/api/v1/invite/accept/{id}');
      expect(crumbs.single.data!['error_type'], 'badResponse');
    },
  );

  test('requestId prefers the server echo, then the body field', () async {
    final _Adapter adapter = _Adapter(
      500,
      body: <String, dynamic>{'success': false, 'requestId': 'srv-body-id-123'},
    );
    Object? thrown;
    try {
      await _dio(adapter).get<dynamic>('/api/v1/x');
    } on DioException catch (e) {
      thrown = e.error;
    }
    expect((thrown! as Failure).requestId, 'srv-body-id-123');
  });

  test('a non-HTTP failure has no request id', () {
    expect(const UnknownFailure().requestId, isNull);
  });

  test('normalisePath keeps literal segments', () {
    expect(normalisePath('/api/v1/bookings'), '/api/v1/bookings');
    expect(normalisePath('/api/v1/users/a@b.ua'), '/api/v1/users/{id}');
    expect(
      normalisePath('/api/v1/search/%D0%BB%D0%B0%D0%BA'),
      '/api/v1/search/{id}',
    );
    expect(normalisePath('/api/v1/bookings/12345'), '/api/v1/bookings/{id}');
  });

  test('dioProvider registers RequestIdInterceptor FIRST', () {
    final ProviderContainer c = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
      ],
    );
    addTearDown(c.dispose);
    final List<Interceptor> list = c.read(dioProvider).interceptors.toList();
    final int ridAt = list.indexWhere(
      (Interceptor i) => i is RequestIdInterceptor,
    );
    final int authAt = list.indexWhere((Interceptor i) => i is AuthInterceptor);
    expect(ridAt, isNonNegative);
    expect(ridAt, lessThan(authAt));
  });
}
