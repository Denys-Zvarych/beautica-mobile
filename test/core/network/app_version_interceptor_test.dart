// Phase 438 D6 — `X-App-Version: <version>+<buildNumber>` on every request.

import 'dart:typed_data';

import 'package:beautica_mobile/core/app_version/app_version_info.dart';
import 'package:beautica_mobile/core/network/app_version_interceptor.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

final class _Adapter implements HttpClientAdapter {
  final List<RequestOptions> seen = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seen.add(options);
    return ResponseBody.fromString(
      '{}',
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

PackageInfo _info({String version = '1.5.0', String build = '7'}) =>
    PackageInfo(
      appName: 'Beautica',
      packageName: 'com.beautica.app',
      version: version,
      buildNumber: build,
    );

({Dio dio, _Adapter adapter}) _dio(PackageInfo? Function() peek) {
  final _Adapter adapter = _Adapter();
  final Dio dio = Dio(BaseOptions(baseUrl: 'https://api.beautica.app'))
    ..httpClientAdapter = adapter
    ..interceptors.add(AppVersionInterceptor(peek));
  return (dio: dio, adapter: adapter);
}

final class _Handler extends RequestInterceptorHandler {
  RequestOptions? passed;

  @override
  void next(RequestOptions requestOptions) => passed = requestOptions;
}

void main() {
  test('once resolved, every request carries X-App-Version = '
      '<version>+<build>', () async {
    final r = _dio(() => _info());
    await r.dio.get<Object?>('/api/v1/a');
    await r.dio.get<Object?>('/api/v1/b');

    expect(r.adapter.seen, hasLength(2));
    for (final RequestOptions o in r.adapter.seen) {
      expect(o.headers[kAppVersionHeader], '1.5.0+7');
    }
  });

  test('while PackageInfo is unresolved (or the read failed) the request '
      'goes out WITHOUT the header — never fails it', () async {
    final r = _dio(() => null);
    final Response<Object?> response = await r.dio.get<Object?>('/a');

    expect(response.statusCode, 200);
    expect(
      r.adapter.seen.single.headers.containsKey(kAppVersionHeader),
      isFalse,
    );
  });

  test('the header appears as soon as the value resolves — requests before '
      'it go without, requests after it carry it', () async {
    PackageInfo? resolved;
    final r = _dio(() => resolved);
    await r.dio.get<Object?>('/before');
    resolved = _info();
    await r.dio.get<Object?>('/after');

    expect(
      r.adapter.seen.first.headers.containsKey(kAppVersionHeader),
      isFalse,
    );
    expect(r.adapter.seen.last.headers[kAppVersionHeader], '1.5.0+7');
  });

  test('never blocks: handler.next is called synchronously inside '
      'onRequest, resolved or not', () {
    for (final PackageInfo? value in <PackageInfo?>[null, _info()]) {
      final _Handler handler = _Handler();
      final RequestOptions options = RequestOptions(path: '/a');
      AppVersionInterceptor(() => value).onRequest(options, handler);

      // No await between the call and this check: the request was passed on
      // inside onRequest itself.
      expect(handler.passed, same(options));
    }
  });

  test('header name is exactly X-App-Version (backend RequestIdFilter '
      'contract)', () {
    expect(kAppVersionHeader, 'X-App-Version');
  });

  test(
    'value format is <version>+<buildNumber>, verbatim from PackageInfo',
    () {
      expect(appVersionHeaderValue(_info()), '1.5.0+7');
      expect(
        appVersionHeaderValue(_info(version: '2.10.3', build: '142')),
        '2.10.3+142',
      );
    },
  );

  test(
    'the per-request headers the caller set are preserved alongside it',
    () async {
      final r = _dio(() => _info());
      await r.dio.get<Object?>(
        '/a',
        options: Options(headers: <String, Object?>{'X-Request-Id': 'rid-1'}),
      );

      final Map<String, Object?> sent = r.adapter.seen.single.headers;
      expect(sent['X-Request-Id'], 'rid-1');
      expect(sent[kAppVersionHeader], '1.5.0+7');
    },
  );
}
