// M517 (AUTH-D12, AUTH-45) — the PRODUCTION wiring of the server phone gate.
//
// `error_mapper_interceptor_test.dart` pins the mapper's own hook (a 409
// `PHONE_NOT_VERIFIED` fires `onPhoneNotVerified` once). This file pins the
// other half that no other tier reaches: `dioProvider` hands the mapper a
// callback that re-reads `GET /users/me`, so a gated write while the app is
// open turns the session into one the auth redirect holds on
// /auth/add-phone. The E2E tier cannot see it — `FakeBackend.dio` replaces
// `dioProvider` with a bare `ErrorMapperInterceptor()` (no callback).
//
// Real `dioProvider` (production interceptor list, production order) over a
// scripted transport; the session comes from a fake repository.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/dio_provider.dart';
import 'package:beautica_mobile/core/network/refresh_dio_provider.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/auth_tokens.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/routing/auth_redirect.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes/fake_auth_repository.dart';
import '../../helpers/fakes/fake_secure_storage.dart';

/// Answers every request with [status] + [body] and records the paths.
final class _OneReplyAdapter implements HttpClientAdapter {
  _OneReplyAdapter(this.status, this.body);

  final int status;
  final Map<String, dynamic> body;
  final List<String> paths = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.path);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _error(String code) => <String, dynamic>{
  'success': false,
  'message': 'gate',
  'data': <String, dynamic>{'code': code},
};

const User _client = User(id: 'c-1', role: UserRole.client);

final class _Gate {
  _Gate._(this.container, this.dio, this.repo);

  static Future<_Gate> boot(int status, String code) async {
    final FakeSecureStorage storage = FakeSecureStorage();
    await storage.writeRefreshToken('stored-refresh');
    final FakeAuthRepository repo = FakeAuthRepository()
      ..refreshResult = const AuthTokens(
        accessToken: 'access',
        refreshToken: 'stored-refresh',
      )
      ..meResult = _client;
    final ProviderContainer container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        secureStorageProvider.overrideWith((_) => storage),
        authRepositoryProvider.overrideWith((_) => repo),
        refreshDioProvider.overrideWith((_) => Dio()),
      ],
    );
    addTearDown(container.dispose);
    final Dio dio = container.read(dioProvider)
      ..httpClientAdapter = _OneReplyAdapter(status, _error(code));
    await container.read(authProvider.future);
    return _Gate._(container, dio, repo);
  }

  final ProviderContainer container;
  final Dio dio;
  final FakeAuthRepository repo;

  User? get user {
    final AuthSession? s = container.read(authProvider).value;
    return s is Authenticated ? s.user : null;
  }

  /// A gated write; returns the typed failure it was rejected with.
  Future<Object?> write() async {
    try {
      await dio.post<dynamic>('/api/v1/appointments');
    } on DioException catch (e) {
      return e.error;
    }
    return null;
  }
}

void main() {
  test('a 409 PHONE_NOT_VERIFIED on a write re-reads /users/me and the '
      'session then redirects every screen to /auth/add-phone', () async {
    final _Gate g = await _Gate.boot(409, 'PHONE_NOT_VERIFIED');
    expect(g.user?.mustAddPhone, isFalse, reason: 'precondition');
    final int meBefore = g.repo.meCallCount;
    g.repo.meResult = _client.copyWith(
      phoneVerified: false,
      phoneRequiredBy: '2026-11-18',
    );

    final Object? failure = await g.write();
    await pumpEventQueue();

    expect(failure, isA<PhoneNotVerifiedFailure>());
    expect(g.repo.meCallCount, meBefore + 1);
    expect(g.user?.mustAddPhone, isTrue);
    expect(
      authRedirectForLocation(
        g.container.read(authProvider),
        RouteNames.clientBookings,
      ),
      RouteNames.addPhone,
    );
  });

  test('a burst of gated 409s re-reads /users/me once', () async {
    final _Gate g = await _Gate.boot(409, 'PHONE_NOT_VERIFIED');
    final int meBefore = g.repo.meCallCount;
    // Hold /users/me open so all three 409s land while the refresh is live.
    final Completer<void> meGate = Completer<void>();
    g.repo.meDelay = meGate.future;

    await Future.wait(<Future<Object?>>[g.write(), g.write(), g.write()]);
    meGate.complete();
    await pumpEventQueue();

    expect(g.repo.meCallCount, meBefore + 1);
  });

  test('any other 409 leaves the session alone (no /users/me)', () async {
    final _Gate g = await _Gate.boot(409, 'SLOT_TAKEN');
    final int meBefore = g.repo.meCallCount;

    final Object? failure = await g.write();
    await pumpEventQueue();

    expect(failure, isNot(isA<PhoneNotVerifiedFailure>()));
    expect(g.repo.meCallCount, meBefore);
  });
}
