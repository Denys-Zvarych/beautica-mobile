// Phase 070 QA — the upload seam over the REAL production Dio chain.
//
// `media_upload_repository_test.dart` / `media_upload_wire_test.dart` build a
// bare Dio with only `ErrorMapperInterceptor`, so they can never see what
// `AuthInterceptor` and `RefreshInterceptor` do to a multipart request. These
// tests read `dioProvider` (production interceptor list, production order) and
// swap only the transport + refresh Dio, mirroring
// `test/core/network/interceptor_chain_test.dart`.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:beautica_mobile/core/media/upload/media_upload_repository.dart';
import 'package:beautica_mobile/core/media/upload/upload_failure.dart';
import 'package:beautica_mobile/core/network/dio_provider.dart';
import 'package:beautica_mobile/core/network/refresh_dio_provider.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/auth_tokens.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';

const String _kRefreshPath = '/api/v1/auth/refresh';
const String _kStale = 'stale-access';
const String _kFresh = 'fresh-access';

class _MockDio extends Mock implements Dio {}

/// Token-aware transport: answers 401 to the stale Bearer, 200 to the fresh
/// one — i.e. a server that actually validates what it is handed. Drains the
/// body so an empty/finalised replay is observable.
final class _TokenAwareAdapter implements HttpClientAdapter {
  final List<String?> bearers = <String?>[];
  final List<int> bodyLengths = <int>[];
  final List<String?> contentTypes = <String?>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    var n = 0;
    if (requestStream != null) {
      await for (final c in requestStream) {
        n += c.length;
      }
    }
    final auth = options.headers.entries
        .where((e) => e.key.toLowerCase() == 'authorization')
        .map((e) => e.value?.toString())
        .firstOrNull;
    bearers.add(auth);
    bodyLengths.add(n);
    contentTypes.add(options.headers[Headers.contentTypeHeader]?.toString());
    final ok = auth == 'Bearer $_kFresh';
    return ResponseBody.fromString(
      jsonEncode(
        ok
            ? <String, Object>{
                'success': true,
                'data': <String, Object>{
                  'avatarUrl': 'https://media.test/avatars/u1/2.jpg',
                },
              }
            : <String, Object>{'success': false},
      ),
      ok ? 200 : 401,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Duration? _noRetry(int retryCount, Object error) => null;

void main() {
  late Directory tmp;
  late File photo;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('upload_chain_test');
    photo = File('${tmp.path}/p.jpg')..writeAsBytesSync(<int>[1, 2, 3, 4]);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<
    ({
      ProviderContainer container,
      _TokenAwareAdapter adapter,
      _MockDio refreshDio,
    })
  >
  boot() async {
    final storage = FakeSecureStorage();
    await storage.writeRefreshToken('stored-refresh');
    final repo = FakeAuthRepository()
      ..refreshResult = const AuthTokens(
        accessToken: _kStale,
        refreshToken: 'stored-refresh',
      );
    final refreshDio = _MockDio();
    when(
      () => refreshDio.post<Map<String, dynamic>>(
        _kRefreshPath,
        data: any(named: 'data'),
      ),
    ).thenAnswer(
      (_) async => Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(path: _kRefreshPath),
        statusCode: 200,
        data: <String, dynamic>{
          'data': <String, dynamic>{
            'accessToken': _kFresh,
            'refreshToken': 'new-refresh',
          },
        },
      ),
    );
    final container = ProviderContainer(
      retry: _noRetry,
      overrides: [
        secureStorageProvider.overrideWith((_) => storage),
        authRepositoryProvider.overrideWith((_) => repo),
        refreshDioProvider.overrideWith((_) => refreshDio),
      ],
    );
    addTearDown(container.dispose);
    final adapter = _TokenAwareAdapter();
    container.read(dioProvider).httpClientAdapter = adapter;
    expect(
      await container.read(authProvider.future),
      isA<Authenticated>(),
      reason: 'precondition: live session',
    );
    return (container: container, adapter: adapter, refreshDio: refreshDio);
  }

  test('401 on the REAL chain: refresh once, retry with FRESH FormData and '
      'the refreshed token, resolve to the URL', () async {
    final h = await boot();

    final url = await h.container
        .read(mediaUploadRepositoryProvider)
        .uploadAvatar(photo)
        .result;

    expect(url, 'https://media.test/avatars/u1/2.jpg');
    expect(h.adapter.bearers, <String?>['Bearer $_kStale', 'Bearer $_kFresh']);
    expect(
      h.adapter.bodyLengths.every((n) => n > 0),
      isTrue,
      reason: 'both attempts must carry the file bytes',
    );
    verify(
      () => h.refreshDio.post<Map<String, dynamic>>(
        _kRefreshPath,
        data: any(named: 'data'),
      ),
    ).called(1);
  });

  test(
    '401 on the REAL chain: a second 401 is terminal (no refresh loop)',
    () async {
      final h = await boot();
      // The token-aware server only accepts _kFresh; make refresh hand back
      // another stale token so EVERY attempt is 401.
      when(
        () => h.refreshDio.post<Map<String, dynamic>>(
          _kRefreshPath,
          data: any(named: 'data'),
        ),
      ).thenAnswer(
        (_) async => Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: _kRefreshPath),
          statusCode: 200,
          data: <String, dynamic>{
            'data': <String, dynamic>{
              'accessToken': 'still-stale',
              'refreshToken': 'new-refresh',
            },
          },
        ),
      );

      Object? error;
      try {
        await h.container
            .read(mediaUploadRepositoryProvider)
            .uploadAvatar(photo)
            .result;
      } on UploadFailure catch (e) {
        error = e;
      }

      expect(error, isA<UploadFailure>());
      expect(
        h.adapter.bearers.length,
        lessThanOrEqualTo(4),
        reason: 'bounded: repo retry x interceptor replay, never a loop',
      );
    },
  );

  test('authenticated upload sends the Bearer and multipart content type '
      'through the real chain', () async {
    final h = await boot();
    // First attempt carries the live-session token.
    try {
      await h.container
          .read(mediaUploadRepositoryProvider)
          .uploadAvatar(photo)
          .result;
    } on UploadFailure {
      // The stale-token server answers 401 — irrelevant to this assertion.
    }
    expect(h.adapter.bearers.first, 'Bearer $_kStale');
    expect(h.adapter.bodyLengths.first, greaterThan(0));
    expect(
      h.adapter.contentTypes.first,
      startsWith('multipart/form-data; boundary='),
    );
  });
}
