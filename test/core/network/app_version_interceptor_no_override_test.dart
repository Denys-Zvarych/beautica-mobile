// Phase 438 D6 regression — a widget test that does NOT override
// [appPackageInfoProvider] must still be able to send requests through the
// REAL [dioProvider] and settle.
//
// The first cut of `AppVersionInterceptor` awaited the PackageInfo platform
// read on the first request(s); with no override that read never resolved in
// a widget test, so every main-Dio request blocked (pumpAndSettle timeouts,
// pending timers in goldens). The interceptor now only peeks at a resolved
// value: an unresolved read means "no header", never "wait".

import 'dart:typed_data';

import 'package:beautica_mobile/core/network/app_version_interceptor.dart';
import 'package:beautica_mobile/core/network/dio_provider.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes/fake_secure_storage.dart';

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

/// Fires one GET through the real [dioProvider] on tap and shows the status.
class _Probe extends ConsumerStatefulWidget {
  const _Probe(this.adapter);

  final _Adapter adapter;

  @override
  ConsumerState<_Probe> createState() => _ProbeState();
}

class _ProbeState extends ConsumerState<_Probe> {
  String _status = 'idle';

  Future<void> _send() async {
    final Dio dio = ref.read(dioProvider)..httpClientAdapter = widget.adapter;
    final Response<Object?> r = await dio.get<Object?>('/api/v1/probe');
    if (!mounted) return;
    setState(() => _status = 'done ${r.statusCode}');
  }

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      TextButton(
        key: const Key('probe.send'),
        onPressed: _send,
        child: const Text('send'),
      ),
      Text(_status, key: const Key('probe.status')),
    ],
  );
}

void main() {
  testWidgets('a request through the real dioProvider with NO '
      'appPackageInfoProvider override goes out (without X-App-Version) and '
      'pumpAndSettle completes', (WidgetTester tester) async {
    final _Adapter adapter = _Adapter();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
        ],
        child: MaterialApp(home: Scaffold(body: _Probe(adapter))),
      ),
    );

    await tester.tap(find.byKey(const Key('probe.send')));
    await tester.pumpAndSettle();

    expect(adapter.seen, hasLength(1));
    expect(adapter.seen.single.headers.containsKey(kAppVersionHeader), isFalse);
    expect(find.text('done 200'), findsOneWidget);
  });
}
