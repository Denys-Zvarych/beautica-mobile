// Phase 438 D2 — appConfigApiProvider: a clone of the main dioProvider Dio
// with the short fail-open timeout, sharing the (cert-pinned) adapter and the
// interceptor chain, so X-App-Version rides on the config call. Observed at
// the wire: the request the main Dio's adapter actually receives.

import 'dart:convert';
import 'dart:typed_data';

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/network/api_client_provider.dart';
import 'package:beautica_mobile/core/network/app_version_interceptor.dart';
import 'package:beautica_mobile/core/network/dio_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

final class _CapturingAdapter implements HttpClientAdapter {
  final List<RequestOptions> seen = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seen.add(options);
    return ResponseBody.fromString(
      jsonEncode(<String, Object?>{
        'success': true,
        'data': <String, Object?>{
          'android': <String, Object?>{
            'minVersionCode': 1,
            'latestVersionCode': 1,
            'storeUrl': 'https://play.google.com/store/apps/details?id=x',
          },
        },
      }),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

final PackageInfo _info = PackageInfo(
  appName: 'Beautica',
  packageName: 'com.beautica.app',
  version: '1.5.0',
  buildNumber: '7',
);

({ProviderContainer c, Dio main, _CapturingAdapter adapter}) _setUp() {
  final _CapturingAdapter adapter = _CapturingAdapter();
  final Dio main =
      Dio(
          BaseOptions(
            baseUrl: 'https://api.beautica.app',
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 30),
          ),
        )
        ..httpClientAdapter = adapter
        ..interceptors.add(AppVersionInterceptor(() => _info));
  final ProviderContainer c = ProviderContainer(
    overrides: [dioProvider.overrideWithValue(main)],
  );
  addTearDown(c.dispose);
  return (c: c, main: main, adapter: adapter);
}

void main() {
  test('the config call fails open within kAppConfigTimeout (10 s), not the '
      'main Dio timeouts — and leaves the main Dio untouched', () async {
    final r = _setUp();

    await r.c.read(appConfigApiProvider).getConfig();

    expect(kAppConfigTimeout, const Duration(seconds: 10));
    final RequestOptions sent = r.adapter.seen.single;
    expect(sent.connectTimeout, kAppConfigTimeout);
    expect(sent.receiveTimeout, kAppConfigTimeout);
    expect(r.main.options.connectTimeout, const Duration(seconds: 15));
    expect(r.main.options.receiveTimeout, const Duration(seconds: 30));
  });

  test('goes through the MAIN adapter (cert pinning) and interceptor chain: '
      'GET <baseUrl>/api/v1/app/config carrying X-App-Version', () async {
    final r = _setUp();

    final Response<ApiResponseAppConfigResponse> response = await r.c
        .read(appConfigApiProvider)
        .getConfig();

    final RequestOptions sent = r.adapter.seen.single;
    expect(sent.method, 'GET');
    expect(sent.uri.toString(), 'https://api.beautica.app/api/v1/app/config');
    expect(sent.headers[kAppVersionHeader], '1.5.0+7');
    expect(response.data?.data?.android.minVersionCode, 1);
  });
}
