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

({Dio dio, _Adapter adapter}) _dio(Future<PackageInfo> Function() load) {
  final _Adapter adapter = _Adapter();
  final Dio dio = Dio(BaseOptions(baseUrl: 'https://api.beautica.app'))
    ..httpClientAdapter = adapter
    ..interceptors.add(AppVersionInterceptor(load));
  return (dio: dio, adapter: adapter);
}

void main() {
  test('every request carries X-App-Version = <version>+<build>', () async {
    final r = _dio(() async => _info());
    await r.dio.get<Object?>('/api/v1/a');
    await r.dio.get<Object?>('/api/v1/b');

    expect(r.adapter.seen, hasLength(2));
    for (final RequestOptions o in r.adapter.seen) {
      expect(o.headers[kAppVersionHeader], '1.5.0+7');
    }
  });

  test('PackageInfo is read ONCE for the whole process', () async {
    int reads = 0;
    final r = _dio(() async {
      reads++;
      return _info();
    });
    await Future.wait(<Future<Object?>>[
      r.dio.get<Object?>('/a'),
      r.dio.get<Object?>('/b'),
    ]);
    await r.dio.get<Object?>('/c');

    expect(reads, 1);
  });

  test('a failed platform read sends the request WITHOUT the header — never '
      'fails it', () async {
    final r = _dio(() async => throw StateError('no plugin'));
    final Response<Object?> response = await r.dio.get<Object?>('/a');

    expect(response.statusCode, 200);
    expect(
      r.adapter.seen.single.headers.containsKey(kAppVersionHeader),
      isFalse,
    );
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
    'requests racing the FIRST platform read all carry the header',
    () async {
      final r = _dio(() async {
        await Future<void>.delayed(Duration.zero);
        return _info();
      });
      await Future.wait(<Future<Object?>>[
        r.dio.get<Object?>('/a'),
        r.dio.get<Object?>('/b'),
        r.dio.get<Object?>('/c'),
      ]);

      expect(r.adapter.seen, hasLength(3));
      expect(
        r.adapter.seen.map((RequestOptions o) => o.headers[kAppVersionHeader]),
        everyElement('1.5.0+7'),
      );
    },
  );

  test('a failed platform read is memoised: read once, every later request '
      'goes out without the header', () async {
    int reads = 0;
    final r = _dio(() async {
      reads++;
      throw StateError('no plugin');
    });
    await r.dio.get<Object?>('/a');
    await r.dio.get<Object?>('/b');

    expect(reads, 1);
    expect(
      r.adapter.seen.where(
        (RequestOptions o) => o.headers.containsKey(kAppVersionHeader),
      ),
      isEmpty,
    );
  });

  test(
    'the per-request headers the caller set are preserved alongside it',
    () async {
      final r = _dio(() async => _info());
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
