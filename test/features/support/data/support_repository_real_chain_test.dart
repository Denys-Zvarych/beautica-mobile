// Phase 070 QA — support-ticket multipart submit over the REAL production Dio
// chain (mirrors `test/core/media/upload/media_upload_real_chain_test.dart`).
//
// `RefreshInterceptor` refreshes on a 401 but cannot replay a finalised
// `FormData`; `HttpSupportRepository` therefore rebuilds the form and re-sends
// ONCE with the fresh token (shared `retryOnceOnUnauthorized`).

import 'dart:typed_data';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/dio_provider.dart';
import 'package:beautica_mobile/core/network/refresh_dio_provider.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/auth_tokens.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/support/data/support_repository.dart';
import 'package:beautica_mobile/features/support/domain/support_attachment.dart';
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

/// Token-aware transport: 401 to the stale Bearer, 202 to the fresh one. Drains
/// the body so an empty/finalised replay is observable.
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
      '',
      ok ? 202 : 401,
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
  final attachment = SupportAttachment(
    name: 'a.png',
    bytes: List<int>.filled(64, 1),
    contentType: 'image/png',
    kind: SupportAttachmentKind.image,
  );

  Future<
    ({
      ProviderContainer container,
      _TokenAwareAdapter adapter,
      _MockDio refreshDio,
    })
  >
  boot({String refreshedAccess = _kFresh}) async {
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
            'accessToken': refreshedAccess,
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
      'the refreshed token, submit resolves', () async {
    final h = await boot();

    await h.container
        .read(supportRepositoryProvider)
        .submitContact(
          message: 'A real ten-plus char message',
          attachments: [attachment],
        );

    expect(h.adapter.bearers, <String?>['Bearer $_kStale', 'Bearer $_kFresh']);
    expect(
      h.adapter.bodyLengths.every((n) => n > 0),
      isTrue,
      reason: 'both attempts must carry the multipart body',
    );
    expect(
      h.adapter.contentTypes.every(
        (c) => c != null && c.startsWith('multipart/form-data; boundary='),
      ),
      isTrue,
    );
    verify(
      () => h.refreshDio.post<Map<String, dynamic>>(
        _kRefreshPath,
        data: any(named: 'data'),
      ),
    ).called(1);
  });

  test('401 on the REAL chain: a persistent 401 is terminal and bounded '
      '(UnauthorizedFailure, no loop)', () async {
    final h = await boot(refreshedAccess: 'still-stale');

    Object? error;
    try {
      await h.container
          .read(supportRepositoryProvider)
          .submitContact(message: 'A real ten-plus char message');
    } on Failure catch (e) {
      error = e;
    }

    expect(error, isA<UnauthorizedFailure>());
    expect(
      h.adapter.bearers.length,
      lessThanOrEqualTo(2),
      reason: 'exactly one re-attempt, never a loop',
    );
  });
}
