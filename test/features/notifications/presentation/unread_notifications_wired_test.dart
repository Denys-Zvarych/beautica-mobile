// Phase 360 — provider-level "integration" tests for UnreadNotifications.
//
// The notifier is not wired into UI until phase 361 (integration_test/ flows
// land in phase 365), so this is the widest honest seam available:
//
//  1. the REAL `authProvider` (real AuthNotifier over FakeAuthRepository +
//     FakeSecureStorage) driven through login -> logout -> login as ANOTHER
//     user, with the real notifier and a fake notification repository;
//  2. a REAL Dio + production ErrorMapperInterceptor + scripted
//     HttpClientAdapter + HttpNotificationRepository chain, proving a wire
//     429 with `Retry-After` suspends polling for exactly that long.
//
// fakeAsync + explicit `elapse` throughout — never `pumpAndSettle`.

import 'dart:convert';
import 'dart:typed_data';

import 'package:beautica_api/beautica_api.dart' as api;
import 'package:beautica_mobile/core/media/beautica_image.dart';
import 'package:beautica_mobile/core/network/error_mapper_interceptor.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/auth_tokens.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/notifications/data/notification_repository.dart';
import 'package:beautica_mobile/features/notifications/domain/app_notification.dart';
import 'package:beautica_mobile/features/notifications/presentation/unread_notifications_notifier.dart';
import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';

const Duration _interval = Duration(seconds: 10);

class _NoopCacheManager implements BaseCacheManager {
  @override
  Future<void> emptyCache() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _CountRepo implements NotificationRepository {
  int calls = 0;
  int next = 0;

  @override
  Future<int> unreadCount() async {
    calls++;
    return next;
  }

  @override
  Future<NotificationPage> fetchPage({required int page, required int size}) =>
      throw UnimplementedError();

  @override
  Future<void> markRead(String id) => throw UnimplementedError();

  @override
  Future<int> markAllRead({DateTime? upTo}) => throw UnimplementedError();
}

User _user(String id) =>
    User(id: id, email: '$id@e.com', role: UserRole.salonOwner);

AuthTokens _tokens(String id) =>
    AuthTokens(accessToken: 'access-$id', refreshToken: 'refresh-$id');

void _walk(List<AppLifecycleState> states) {
  for (final AppLifecycleState s in states) {
    TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(s);
  }
}

void _background() => _walk(const [
  AppLifecycleState.inactive,
  AppLifecycleState.hidden,
  AppLifecycleState.paused,
]);

void _foreground() => _walk(const [
  AppLifecycleState.hidden,
  AppLifecycleState.inactive,
  AppLifecycleState.resumed,
]);

/// Scripted transport for the Dio chain: replies come from [replies] in
/// order, the last one repeating.
final class _Adapter implements HttpClientAdapter {
  _Adapter(this.replies);

  final List<({int status, Object? body, Map<String, String> headers})> replies;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final r = replies[calls < replies.length ? calls : replies.length - 1];
    calls++;
    return ResponseBody.fromString(
      jsonEncode(r.body),
      r.status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
        for (final e in r.headers.entries) e.key: <String>[e.value],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

typedef _Reply = ({int status, Object? body, Map<String, String> headers});

_Reply _throttled(String retryAfter) => (
  status: 429,
  body: const <String, Object?>{'success': false, 'message': 'Too many'},
  headers: <String, String>{'retry-after': retryAfter},
);

_Reply _count(int n) => (
  status: 200,
  body: <String, Object?>{
    'success': true,
    'data': <String, Object?>{'count': n},
  },
  headers: const <String, String>{},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    debugMediaCacheManager = _NoopCacheManager();
    final AppLifecycleState? current =
        TestWidgetsFlutterBinding.instance.lifecycleState;
    if (current == AppLifecycleState.paused) {
      _foreground();
    } else if (current == AppLifecycleState.inactive) {
      _walk(const [AppLifecycleState.resumed]);
    }
  });

  tearDown(() => debugMediaCacheManager = null);

  test('should_followRealAuthTransitions_loginLogoutLoginAsOtherUser', () {
    fakeAsync((FakeAsync async) {
      final DateTime start = DateTime.utc(2026, 1, 1);
      final FakeAuthRepository authRepo = FakeAuthRepository();
      final _CountRepo repo = _CountRepo();
      final ProviderContainer container = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
          authRepositoryProvider.overrideWith((_) => authRepo),
          notificationRepositoryProvider.overrideWithValue(repo),
          pollIntervalProvider.overrideWithValue(_interval),
          clockProvider.overrideWithValue(() => start.add(async.elapsed)),
        ],
      );
      void settle([Duration d = Duration.zero]) {
        async.elapse(d);
        async.flushMicrotasks();
      }

      int? value() => container.read(unreadNotificationsProvider).value;
      AuthNotifier auth() => container.read(authProvider.notifier);

      try {
        // Cold start, no stored session: nothing is requested, ever.
        container.read(authProvider);
        settle();
        container.listen(unreadNotificationsProvider, (_, _) {});
        settle(_interval * 5);
        expect(container.read(authProvider).value, isA<Unauthenticated>());
        expect(repo.calls, 0);
        expect(value(), 0);

        // Login as u1: immediate fetch, then one request per interval.
        authRepo
          ..loginResult = (_user('u1'), _tokens('u1'))
          ..meResult = _user('u1');
        repo.next = 5;
        auth().login('u1@e.com', 'pw');
        settle();
        expect(container.read(authProvider).value, isA<Authenticated>());
        expect(repo.calls, 1);
        expect(value(), 5);
        settle(_interval);
        expect(repo.calls, 2);

        // Logout through the real notifier: reset to 0, zero requests after.
        auth().logout();
        settle();
        expect(container.read(authProvider).value, isA<Unauthenticated>());
        expect(value(), 0);
        final int afterLogout = repo.calls;
        settle(_interval * 5);
        _background();
        settle();
        _foreground();
        settle();
        expect(
          repo.calls,
          afterLogout,
          reason: 'zero requests once logged out',
        );
        expect(value(), 0);

        // Login as ANOTHER user: fresh fetch, u1's late mutations are dropped.
        authRepo
          ..loginResult = (_user('u2'), _tokens('u2'))
          ..meResult = _user('u2');
        repo.next = 2;
        auth().login('u2@e.com', 'pw');
        settle();
        expect(repo.calls, afterLogout + 1);
        expect(value(), 2);

        container
            .read(unreadNotificationsProvider.notifier)
            .setCount(99, forUserId: 'u1');
        expect(value(), 2, reason: 'a late u1 response must not reach u2');
        container
            .read(unreadNotificationsProvider.notifier)
            .setCount(7, forUserId: 'u2');
        expect(value(), 7);

        // Same-user silent token refresh neither refetches nor resets.
        final int beforeRefresh = repo.calls;
        auth().setAccessToken('rotated');
        settle();
        expect(repo.calls, beforeRefresh);
        expect(value(), 7);
      } finally {
        container.dispose();
      }
    });
  });

  group('wire 429 through the real Dio + ErrorMapperInterceptor chain', () {
    // Retry-After header -> observed suspension: 90 s verbatim; 5 s floored to
    // 30 s by the notifier; an absurd value clamped to 3600 s by the mapper.
    const cases = <(String, Duration)>[
      ('90', Duration(seconds: 90)),
      ('5', Duration(seconds: 30)),
      ('999999', Duration(seconds: 3600)),
    ];

    for (final (String header, Duration expected) in cases) {
      test(
        'should_suspendPollingFor${expected.inSeconds}s_whenRetryAfter$header',
        () {
          fakeAsync((FakeAsync async) {
            final DateTime start = DateTime.utc(2026, 1, 1);
            final _Adapter adapter = _Adapter([_throttled(header), _count(4)]);
            final Dio dio = Dio(BaseOptions(baseUrl: 'http://test.invalid'))
              ..interceptors.add(ErrorMapperInterceptor())
              ..httpClientAdapter = adapter;
            final ProviderContainer container = ProviderContainer(
              overrides: [
                secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
                authRepositoryProvider.overrideWith(
                  (_) => FakeAuthRepository()
                    ..refreshResult = _tokens('u1')
                    ..meResult = _user('u1'),
                ),
                notificationRepositoryProvider.overrideWithValue(
                  HttpNotificationRepository(
                    api.NotificationsApi(dio, api.standardSerializers),
                  ),
                ),
                pollIntervalProvider.overrideWithValue(_interval),
                clockProvider.overrideWithValue(() => start.add(async.elapsed)),
              ],
            );
            void settle(Duration d) {
              async.elapse(d);
              async.flushMicrotasks();
            }

            try {
              final FakeSecureStorage storage =
                  container.read(secureStorageProvider) as FakeSecureStorage;
              storage.writeRefreshToken(_tokens('u1').refreshToken);
              container.read(authProvider);
              async.flushMicrotasks();
              container.listen(unreadNotificationsProvider, (_, _) {});
              settle(Duration.zero);

              // First request is the throttled one.
              expect(adapter.calls, 1);
              expect(container.read(unreadNotificationsProvider).value, 0);

              // Ticks (every 10 s) and a background/foreground cycle inside the
              // window must NOT reach the wire.
              settle(expected - const Duration(seconds: 1));
              _background();
              settle(Duration.zero);
              _foreground();
              settle(Duration.zero);
              expect(
                adapter.calls,
                1,
                reason: 'suspended for the whole window',
              );

              // Window ends: exactly one request, count lands, polling resumes.
              settle(const Duration(seconds: 1));
              expect(adapter.calls, 2);
              expect(container.read(unreadNotificationsProvider).value, 4);
              settle(_interval);
              expect(adapter.calls, 3);
            } finally {
              container.dispose();
            }
          });
        },
      );
    }
  });
}
