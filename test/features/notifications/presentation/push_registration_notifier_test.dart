// Phase 067 — PushRegistration: permission asked once, token registration,
// refresh, logout deregistration, push-unavailable and failure tolerance.

import 'dart:async';

import 'package:beautica_mobile/core/push/firebase_messaging_provider.dart';
import 'package:beautica_mobile/core/push/push_available_provider.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/notifications/data/device_token_repository.dart';
import 'package:beautica_mobile/features/notifications/domain/push_registration_state.dart';
import 'package:beautica_mobile/features/notifications/presentation/push_registration_notifier.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/fakes/fake_secure_storage.dart';

class _MockMessaging extends Mock implements FirebaseMessaging {}

class _FakeRepo implements DeviceTokenRepository {
  _FakeRepo(this.order);
  final List<String> order;
  final List<String> registered = [];
  final List<String> unregistered = [];
  Object? registerError;
  Object? unregisterError;

  /// When set, `register` blocks until completed (in-flight POST simulation).
  /// A cancelled [CancelToken] aborts the wait (like Dio does).
  Completer<void>? registerGate;

  /// `register` never completes and ignores cancellation (worst-case hang).
  bool registerHangs = false;

  /// How many register calls were aborted through their CancelToken.
  int cancelledRegisters = 0;

  /// When set, `unregister` never completes (dead network).
  bool unregisterHangs = false;

  @override
  Future<void> register(String token, {CancelToken? cancelToken}) async {
    registered.add(token);
    order.add('register');
    if (registerHangs) await Completer<void>().future;
    if (registerGate != null) {
      final cancel = cancelToken;
      if (cancel != null) {
        await Future.any<Object?>([registerGate!.future, cancel.whenCancel]);
        if (cancel.isCancelled) {
          cancelledRegisters++;
          order.add('register-cancelled');
          throw StateError('cancelled');
        }
      } else {
        await registerGate!.future;
      }
    }
    order.add('register-done');
    if (registerError != null) throw registerError!;
  }

  @override
  Future<void> unregister(String token) async {
    unregistered.add(token);
    order.add('unregister');
    if (unregisterHangs) await Completer<void>().future;
    if (unregisterError != null) throw unregisterError!;
  }
}

/// Storage whose revoke-pending write parks on a gate (a hung keystore).
class _GatedWriteStorage extends FakeSecureStorage {
  _GatedWriteStorage(this._gate);
  final Completer<void> _gate;

  @override
  Future<void> writePushRevokePending() async {
    await _gate.future;
    await super.writePushRevokePending();
  }
}

/// Counts revoke-pending reads.
class _CountingReadStorage extends FakeSecureStorage {
  int flagReads = 0;

  @override
  Future<bool> readPushRevokePending() {
    flagReads++;
    return super.readPushRevokePending();
  }
}

class _AuthStub extends AuthNotifier {
  _AuthStub(this._initial);
  final AuthSession _initial;

  @override
  Future<AuthSession> build() async => _initial;

  void set(AuthSession s) => state = AsyncData<AuthSession>(s);
}

AuthSession _user(String id) => AuthSession.authenticated(
  user: User(id: id, email: '$id@e.com', role: UserRole.salonOwner),
  accessToken: 'at',
);

NotificationSettings _settings(AuthorizationStatus status) =>
    NotificationSettings(
      alert: AppleNotificationSetting.notSupported,
      announcement: AppleNotificationSetting.notSupported,
      authorizationStatus: status,
      badge: AppleNotificationSetting.notSupported,
      carPlay: AppleNotificationSetting.notSupported,
      lockScreen: AppleNotificationSetting.notSupported,
      notificationCenter: AppleNotificationSetting.notSupported,
      showPreviews: AppleShowPreviewSetting.notSupported,
      timeSensitive: AppleNotificationSetting.notSupported,
      criticalAlert: AppleNotificationSetting.notSupported,
      sound: AppleNotificationSetting.notSupported,
      providesAppNotificationSettings: AppleNotificationSetting.notSupported,
    );

Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _H {
  _H({
    AuthSession? auth,
    bool available = true,
    this.initGate,
    AuthorizationStatus requestResult = AuthorizationStatus.authorized,
    FakeSecureStorage? storage,
  }) : storage = storage ?? FakeSecureStorage() {
    when(() => messaging.getToken()).thenAnswer((_) async => 'tok-1');
    when(() => messaging.deleteToken()).thenAnswer((_) async {
      order.add('deleteToken');
    });
    when(
      () => messaging.requestPermission(),
    ).thenAnswer((_) async => _settings(requestResult));
    when(
      () => messaging.getNotificationSettings(),
    ).thenAnswer((_) async => _settings(requestResult));
    when(() => messaging.onTokenRefresh).thenAnswer((_) => refresh.stream);
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(() => _AuthStub(auth ?? _user('u1'))),
        firebaseInitializerProvider.overrideWithValue(
          () async => initGate != null ? await initGate!.future : available,
        ),
        firebaseMessagingProvider.overrideWithValue(messaging),
        deviceTokenRepositoryProvider.overrideWithValue(repo),
        secureStorageProvider.overrideWithValue(this.storage),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(refresh.close);
  }

  final _MockMessaging messaging = _MockMessaging();
  late final _FakeRepo repo = _FakeRepo(order);
  final FakeSecureStorage storage;

  /// When set, Firebase init (pushAvailable) blocks until completed.
  final Completer<bool>? initGate;
  final StreamController<String> refresh = StreamController<String>.broadcast();
  final List<String> order = [];
  late final ProviderContainer container;

  _AuthStub get auth => container.read(authProvider.notifier) as _AuthStub;
  PushRegistrationState get state => container.read(pushRegistrationProvider);

  Future<void> start() async {
    await container.read(authProvider.future);
    container.listen(pushRegistrationProvider, (_, _) {});
    await _settle();
  }
}

void main() {
  test('anonymous: no Firebase call, state idle', () async {
    final h = _H(auth: const AuthSession.unauthenticated());
    await h.start();
    verifyNever(() => h.messaging.getToken());
    verifyNever(() => h.messaging.requestPermission());
    expect(h.state, const PushRegistrationState.idle());
  });

  test('authenticated: asks once, registers the token once', () async {
    final h = _H();
    await h.start();
    verify(() => h.messaging.requestPermission()).called(1);
    expect(h.repo.registered, ['tok-1']);
    expect(h.state, const PushRegistrationState.registered());
    expect(await h.storage.readPushPermissionAsked(), isTrue);
  });

  test('token refresh re-registers the new token', () async {
    final h = _H();
    await h.start();
    h.refresh.add('tok-2');
    await _settle();
    expect(h.repo.registered, ['tok-1', 'tok-2']);
    expect(h.state, const PushRegistrationState.registered());
  });

  test('permission asked once across two builds (second container)', () async {
    final storage = FakeSecureStorage();
    final first = _H(storage: storage);
    await first.start();
    final second = _H(storage: storage);
    await second.start();
    verify(() => first.messaging.requestPermission()).called(1);
    verifyNever(() => second.messaging.requestPermission());
    expect(second.repo.registered, ['tok-1']);
  });

  test('denied: permissionDenied, token still registered, no re-ask', () async {
    final storage = FakeSecureStorage();
    final h = _H(requestResult: AuthorizationStatus.denied, storage: storage);
    await h.start();
    expect(h.state, const PushRegistrationState.permissionDenied());
    expect(h.repo.registered, ['tok-1']);
    final again = _H(
      requestResult: AuthorizationStatus.denied,
      storage: storage,
    );
    await again.start();
    verifyNever(() => again.messaging.requestPermission());
    expect(again.state, const PushRegistrationState.permissionDenied());
  });

  test('the asked flag survives a logout wipe (deleteAll)', () async {
    final storage = FakeSecureStorage();
    await storage.writePushPermissionAsked();
    await storage.deleteAll();
    expect(await storage.readPushPermissionAsked(), isTrue);
  });

  test('pushAvailable=false: unavailable, no Firebase calls', () async {
    final h = _H(available: false);
    await h.start();
    expect(h.state, const PushRegistrationState.unavailable());
    verifyNever(() => h.messaging.getToken());
    verifyNever(() => h.messaging.requestPermission());
    expect(h.repo.registered, isEmpty);
  });

  test('repository throws: state still settles, nothing escapes', () async {
    final h = _H();
    h.repo.registerError = StateError('boom tok-1');
    await h.start();
    expect(h.state, const PushRegistrationState.registered());
  });

  test('unregisterForLogout: DELETE then deleteToken, then idle', () async {
    final h = _H();
    await h.start();
    h.order.clear();
    await h.container
        .read(pushRegistrationProvider.notifier)
        .unregisterForLogout();
    expect(h.order, ['unregister', 'deleteToken']);
    expect(h.repo.unregistered, ['tok-1']);
    expect(h.state, const PushRegistrationState.idle());
    // The refresh listener is gone: a late refresh no longer registers.
    h.refresh.add('tok-late');
    await _settle();
    expect(h.repo.registered, ['tok-1']);
  });

  test(
    'unregisterForLogout never throws when unregister / deleteToken fail',
    () async {
      final h = _H();
      await h.start();
      h.repo.unregisterError = StateError('offline');
      when(() => h.messaging.deleteToken()).thenThrow(StateError('x'));
      await h.container
          .read(pushRegistrationProvider.notifier)
          .unregisterForLogout();
      expect(h.state, const PushRegistrationState.idle());
    },
  );

  test(
    'unregisterForLogout without a token (push unavailable) is a no-op',
    () async {
      final h = _H(available: false);
      await h.start();
      await h.container
          .read(pushRegistrationProvider.notifier)
          .unregisterForLogout();
      expect(h.repo.unregistered, isEmpty);
      verifyNever(() => h.messaging.deleteToken());
    },
  );

  test('unregisterForLogout is bounded when deleteToken hangs', () async {
    final h = _H();
    await h.start();
    when(
      () => h.messaging.deleteToken(),
    ).thenAnswer((_) => Completer<void>().future);
    await h.container
        .read(pushRegistrationProvider.notifier)
        .unregisterForLogout()
        .timeout(
          kPushLogoutBudget + const Duration(seconds: 1),
          onTimeout: () => fail('unregisterForLogout hung on deleteToken'),
        );
    expect(h.state, const PushRegistrationState.idle());
  });

  test('unregisterForLogout is bounded when the DELETE hangs', () async {
    final h = _H();
    await h.start();
    h.repo.unregisterHangs = true;
    await h.container
        .read(pushRegistrationProvider.notifier)
        .unregisterForLogout()
        .timeout(
          kPushLogoutBudget + const Duration(seconds: 1),
          onTimeout: () => fail('unregisterForLogout hung on DELETE'),
        );
    verify(() => h.messaging.deleteToken()).called(1);
  });

  test('logout completes within the budget when register, DELETE and '
      'deleteToken ALL hang (not the 15 s sum)', () async {
    final h = _H();
    h.repo.registerHangs = true;
    await h.start();
    h.repo.unregisterHangs = true;
    when(
      () => h.messaging.deleteToken(),
    ).thenAnswer((_) => Completer<void>().future);
    final sw = Stopwatch()..start();
    await h.container
        .read(pushRegistrationProvider.notifier)
        .unregisterForLogout()
        .timeout(
          kPushLogoutBudget + const Duration(seconds: 1),
          onTimeout: () => fail('logout exceeded the push budget'),
        );
    expect(
      sw.elapsed,
      lessThan(kPushLogoutBudget + const Duration(seconds: 1)),
    );
    expect(h.repo.unregistered, ['tok-1']);
    verify(() => h.messaging.deleteToken()).called(1);
  });

  test('logout while the register POST is in flight: the POST is CANCELLED, '
      'not awaited; DELETE is sent immediately', () async {
    final h = _H();
    h.repo.registerGate = Completer<void>();
    await h.start();
    expect(h.repo.registered, ['tok-1']);
    await h.container
        .read(pushRegistrationProvider.notifier)
        .unregisterForLogout();
    await _settle();
    expect(h.repo.cancelledRegisters, 1);
    expect(h.repo.unregistered, ['tok-1']);
    verify(() => h.messaging.deleteToken()).called(1);
    // The stale _start continuation must not DELETE a second time.
    expect(h.repo.unregistered, ['tok-1']);
    expect(h.state, const PushRegistrationState.idle());
  });

  test('refresh-path register in flight at logout is cancelled too', () async {
    final h = _H();
    await h.start();
    h.repo.registerGate = Completer<void>();
    h.refresh.add('tok-2');
    await _settle();
    await h.container
        .read(pushRegistrationProvider.notifier)
        .unregisterForLogout();
    await _settle();
    expect(h.repo.cancelledRegisters, 1);
  });

  test('forced logout: NO DELETE, only the local deleteToken', () async {
    final h = _H();
    await h.start();
    await h.container
        .read(pushRegistrationProvider.notifier)
        .unregisterForLogout(forced: true);
    expect(h.repo.unregistered, isEmpty);
    verify(() => h.messaging.deleteToken()).called(1);
    expect(h.state, const PushRegistrationState.idle());
  });

  test('logout during _start (Firebase init pending) still revokes: '
      'getToken + DELETE + deleteToken', () async {
    final gate = Completer<bool>();
    final h = _H(initGate: gate);
    await h.start();
    expect(h.repo.registered, isEmpty);
    final logout = h.container
        .read(pushRegistrationProvider.notifier)
        .unregisterForLogout();
    await _settle();
    gate.complete(true);
    await logout;
    await _settle();
    expect(h.repo.unregistered, ['tok-1']);
    verify(() => h.messaging.deleteToken()).called(1);
    // The cancelled _start must not register afterwards.
    expect(h.repo.registered, isEmpty);
  });

  test('forced logout during _start: deleteToken only, no DELETE', () async {
    final gate = Completer<bool>();
    final h = _H(initGate: gate);
    await h.start();
    final logout = h.container
        .read(pushRegistrationProvider.notifier)
        .unregisterForLogout(forced: true);
    gate.complete(true);
    await logout;
    expect(h.repo.unregistered, isEmpty);
    verify(() => h.messaging.deleteToken()).called(1);
  });

  test('logout during a STUCK _start is bounded by the budget', () async {
    final h = _H(initGate: Completer<bool>());
    await h.start();
    await h.container
        .read(pushRegistrationProvider.notifier)
        .unregisterForLogout()
        .timeout(
          kPushLogoutBudget + const Duration(seconds: 1),
          onTimeout: () => fail('logout hung on a stuck Firebase init'),
        );
    verifyNever(() => h.messaging.deleteToken());
  });

  test('unawaited logout tail never touches the NEXT user: re-login before '
      'availability resolves -> token NOT deleted, no DELETE', () async {
    final gate = Completer<bool>();
    final h = _H(initGate: gate);
    await h.start();
    final logout = h.container
        .read(pushRegistrationProvider.notifier)
        .unregisterForLogout();
    await _settle();
    h.auth.set(const AuthSession.unauthenticated());
    await _settle();
    h.auth.set(_user('u2'));
    await _settle();
    gate.complete(true);
    await logout;
    await _settle();
    verifyNever(() => h.messaging.deleteToken());
    expect(h.repo.unregistered, isEmpty);
    expect(h.repo.registered, ['tok-1']); // u2's own registration only
  });

  test('registered state carries no token (toString cannot leak it)', () {
    expect(
      const PushRegistrationState.registered().toString(),
      isNot(contains('tok')),
    );
  });

  test(
    'auth wiped while the POST is in flight (no logout call): the stale _start '
    'sends NO Bearer-less DELETE',
    () async {
      final h = _H();
      h.repo.registerGate = Completer<void>();
      await h.start();
      // Auth drops to anonymous → build() reruns, generation moves on.
      h.auth.set(const AuthSession.unauthenticated());
      await _settle();
      h.repo.registerGate!.complete();
      await _settle();
      expect(h.repo.unregistered, isEmpty);
    },
  );

  test('A->B switch (no logout) while A\'s POST is in flight: A\'s superseded '
      '_start sends NO DELETE (it would carry B\'s Bearer)', () async {
    final h = _H();
    h.repo.registerGate = Completer<void>();
    await h.start();
    h.auth.set(_user('u2'));
    await _settle();
    h.repo.registerGate!.complete();
    await _settle();
    expect(h.repo.unregistered, isEmpty);
  });

  group('pushRevokePending flag', () {
    test('failed deleteToken at logout leaves the flag set', () async {
      final h = _H();
      await h.start();
      when(() => h.messaging.deleteToken()).thenThrow(StateError('offline'));
      await h.container
          .read(pushRegistrationProvider.notifier)
          .unregisterForLogout();
      expect(await h.storage.readPushRevokePending(), isTrue);
    });

    test('timed-out deleteToken at logout leaves the flag set', () async {
      final h = _H();
      await h.start();
      when(
        () => h.messaging.deleteToken(),
      ).thenAnswer((_) => Completer<void>().future);
      await h.container
          .read(pushRegistrationProvider.notifier)
          .unregisterForLogout();
      expect(await h.storage.readPushRevokePending(), isTrue);
    });

    test('successful deleteToken at logout clears the flag', () async {
      final h = _H();
      await h.start();
      await h.container
          .read(pushRegistrationProvider.notifier)
          .unregisterForLogout();
      expect(await h.storage.readPushRevokePending(), isFalse);
    });

    test('the flag is set BEFORE the revoke work begins', () async {
      final h = _H();
      await h.start();
      bool? flagAtDelete;
      when(() => h.messaging.deleteToken()).thenAnswer((_) async {
        flagAtDelete = await h.storage.readPushRevokePending();
      });
      await h.container
          .read(pushRegistrationProvider.notifier)
          .unregisterForLogout();
      expect(flagAtDelete, isTrue);
    });

    test('flag survives a logout wipe (deleteAll)', () async {
      final storage = FakeSecureStorage();
      await storage.writePushRevokePending();
      await storage.deleteAll();
      expect(await storage.readPushRevokePending(), isTrue);
      await storage.clearPushRevokePending();
      expect(await storage.readPushRevokePending(), isFalse);
    });

    test('next signed-in start retries deleteToken BEFORE getToken, then '
        'clears the flag', () async {
      final storage = FakeSecureStorage();
      await storage.writePushRevokePending();
      final h = _H(storage: storage);
      when(() => h.messaging.getToken()).thenAnswer((_) async {
        h.order.add('getToken');
        return 'tok-2';
      });
      await h.start();
      expect(
        h.order.indexOf('deleteToken'),
        lessThan(h.order.indexOf('getToken')),
      );
      expect(h.order.where((e) => e == 'deleteToken'), hasLength(1));
      expect(await storage.readPushRevokePending(), isFalse);
      expect(h.repo.registered, ['tok-2']);
    });

    test('signed-OUT start with the flag set also retries deleteToken and '
        'clears it; no getToken', () async {
      final storage = FakeSecureStorage();
      await storage.writePushRevokePending();
      final h = _H(auth: const AuthSession.unauthenticated(), storage: storage);
      await h.start();
      verify(() => h.messaging.deleteToken()).called(1);
      verifyNever(() => h.messaging.getToken());
      expect(await storage.readPushRevokePending(), isFalse);
    });

    test('signed-out start WITHOUT the flag makes no Firebase call', () async {
      final h = _H(auth: const AuthSession.unauthenticated());
      await h.start();
      verifyNever(() => h.messaging.deleteToken());
    });

    test('flag set but push unavailable: no deleteToken, flag kept', () async {
      final storage = FakeSecureStorage();
      await storage.writePushRevokePending();
      final h = _H(
        auth: const AuthSession.unauthenticated(),
        available: false,
        storage: storage,
      );
      await h.start();
      verifyNever(() => h.messaging.deleteToken());
      expect(await storage.readPushRevokePending(), isTrue);
    });

    test(
      'retry fails again: flag stays set and registration still proceeds',
      () async {
        final storage = FakeSecureStorage();
        await storage.writePushRevokePending();
        final h = _H(storage: storage);
        when(() => h.messaging.deleteToken()).thenThrow(StateError('offline'));
        await h.start();
        expect(await storage.readPushRevokePending(), isTrue);
        expect(h.repo.registered, ['tok-1']);
      },
    );

    test('revokeLocal sets the flag and clears it on success', () async {
      final h = _H();
      await h.start();
      bool? flagAtDelete;
      when(() => h.messaging.deleteToken()).thenAnswer((_) async {
        flagAtDelete = await h.storage.readPushRevokePending();
      });
      h.auth.set(const AuthSession.unauthenticated());
      await _settle();
      await h.container.read(pushRegistrationProvider.notifier).revokeLocal();
      expect(flagAtDelete, isTrue);
      expect(await h.storage.readPushRevokePending(), isFalse);
    });

    test('logout whose refresh-sub cancel STALLS past the budget still leaves '
        'the flag set after the deleteAll wipe', () async {
      final h = _H();
      // A subscription whose cancel() never completes (single-subscription:
      // a broadcast controller ignores the onCancel future).
      final stuck = StreamController<String>(
        onCancel: () => Completer<void>().future,
      );
      addTearDown(() => unawaited(stuck.close()));
      when(() => h.messaging.onTokenRefresh).thenAnswer((_) => stuck.stream);
      when(
        () => h.messaging.deleteToken(),
      ).thenAnswer((_) => Completer<void>().future);
      await h.start();
      await h.container
          .read(pushRegistrationProvider.notifier)
          .unregisterForLogout();
      await h.storage.deleteAll();
      expect(await h.storage.readPushRevokePending(), isTrue);
    });

    test(
      'stalled sub cancel released AFTER the next user registered: the old '
      'tail does not deleteToken u2 (exactly one deleteToken, u2 live)',
      () async {
        final h = _H();
        final cancelGate = Completer<void>();
        final stuck = StreamController<String>(
          onCancel: () => cancelGate.future,
        );
        addTearDown(() => unawaited(stuck.close()));
        when(() => h.messaging.onTokenRefresh).thenAnswer((_) => stuck.stream);
        await h.start();
        await h.container
            .read(pushRegistrationProvider.notifier)
            .unregisterForLogout(); // budget expires, tail parked on cancel
        h.auth.set(const AuthSession.unauthenticated());
        await _settle();
        when(() => h.messaging.getToken()).thenAnswer((_) async => 'tok-2');
        h.auth.set(_user('u2'));
        await _settle();
        expect(h.repo.registered, contains('tok-2'));
        final int deletesBefore = h.order
            .where((e) => e == 'deleteToken')
            .length;
        cancelGate.complete();
        await _settle();
        expect(h.order.where((e) => e == 'deleteToken').length, deletesBefore);
        expect(
          h.repo.registered.last,
          'tok-2',
        ); // u2 not revoked after it registered
        expect(h.order.where((e) => e == 'deleteToken'), hasLength(1));
      },
    );

    test('signed-in cold start reads the revoke flag exactly once', () async {
      final storage = _CountingReadStorage();
      final h = _H(storage: storage);
      // No `await authProvider.future` first: build() sees auth still loading.
      h.container.listen(pushRegistrationProvider, (_, _) {});
      await _settle();
      expect(storage.flagReads, 1);
      expect(h.repo.registered, ['tok-1']);
    });

    test('signed-out cold start (auth loading -> unauthenticated) still '
        'retries the owed revoke once', () async {
      final storage = _CountingReadStorage();
      await storage.writePushRevokePending();
      final h = _H(auth: const AuthSession.unauthenticated(), storage: storage);
      h.container.listen(pushRegistrationProvider, (_, _) {});
      await _settle();
      verify(() => h.messaging.deleteToken()).called(1);
      expect(await storage.readPushRevokePending(), isFalse);
    });

    test('no flag when push is unavailable (nothing to revoke)', () async {
      final h = _H(available: false);
      await h.start();
      await h.container
          .read(pushRegistrationProvider.notifier)
          .unregisterForLogout();
      expect(await h.storage.readPushRevokePending(), isFalse);
    });
  });

  test('logout whose auth is wiped before the DELETE goes out: NO Bearer-less '
      'DELETE, deleteToken still runs', () async {
    final gate = Completer<void>();
    final storage = _GatedWriteStorage(gate);
    final h = _H(storage: storage);
    await h.start();
    h.order.clear();
    final logout = h.container
        .read(pushRegistrationProvider.notifier)
        .unregisterForLogout();
    await _settle(); // cleanup parked on the flag write
    h.auth.set(const AuthSession.unauthenticated());
    await _settle();
    gate.complete();
    await logout;
    await _settle();
    expect(h.repo.unregistered, isEmpty);
    expect(h.order, contains('deleteToken'));
  });

  test('logout during _start whose auth is wiped before the DELETE: NO '
      'Bearer-less DELETE', () async {
    final tokenGate = Completer<String?>();
    final h = _H();
    await h.start();
    when(() => h.messaging.getToken()).thenAnswer((_) => tokenGate.future);
    // Re-login so a new _start parks on the (gated) getToken: token unknown.
    h.auth.set(_user('u2'));
    await _settle();
    final logout = h.container
        .read(pushRegistrationProvider.notifier)
        .unregisterForLogout();
    await _settle();
    h.auth.set(const AuthSession.unauthenticated());
    await _settle();
    tokenGate.complete('tok-9');
    await logout;
    await _settle();
    expect(h.repo.unregistered, isEmpty);
  });

  test('a cancelled register (own CancelToken) is a quiet outcome: nothing '
      'escapes, state settles', () async {
    final h = _H();
    h.repo.registerError = const DeviceTokenRegisterCancelled();
    await h.start();
    expect(h.state, const PushRegistrationState.registered());
  });

  test('revokeLocal: deleteToken only, no backend call, idle', () async {
    final h = _H();
    await h.start();
    h.order.clear();
    // revokeLocal runs after the auth wipe (anonymous), never mid-session.
    h.auth.set(const AuthSession.unauthenticated());
    await _settle();
    await h.container.read(pushRegistrationProvider.notifier).revokeLocal();
    expect(h.order, ['deleteToken']);
    expect(h.repo.unregistered, isEmpty);
    expect(h.state, const PushRegistrationState.idle());
    h.refresh.add('tok-late');
    await _settle();
    expect(h.repo.registered, ['tok-1']);
  });

  test('revokeLocal is a no-op when push is unavailable', () async {
    final h = _H(available: false);
    await h.start();
    await h.container.read(pushRegistrationProvider.notifier).revokeLocal();
    verifyNever(() => h.messaging.deleteToken());
  });

  test(
    'revokeLocal never throws / is bounded when deleteToken fails',
    () async {
      final h = _H();
      await h.start();
      when(() => h.messaging.deleteToken()).thenThrow(StateError('x'));
      h.auth.set(const AuthSession.unauthenticated());
      await _settle();
      await h.container.read(pushRegistrationProvider.notifier).revokeLocal();
      expect(h.state, const PushRegistrationState.idle());
    },
  );

  test('revokeLocal: wipe -> re-login before availability resolves -> the '
      'NEXT user\'s token is NOT deleted', () async {
    final gate = Completer<bool>();
    final h = _H(auth: const AuthSession.unauthenticated(), initGate: gate);
    await h.start();
    final revoke = h.container
        .read(pushRegistrationProvider.notifier)
        .revokeLocal();
    await _settle();
    h.auth.set(_user('u2'));
    await _settle();
    gate.complete(true);
    await revoke;
    await _settle();
    // revokeLocal itself never deletes (a next user is signed in). The flag it
    // persisted up-front is settled by u2's own _start BEFORE its getToken(),
    // so u2's fresh token is never the one deleted.
    verify(() => h.messaging.deleteToken()).called(1);
    expect(h.repo.registered, ['tok-1']);
    expect(await h.storage.readPushRevokePending(), isFalse);
  });

  test('revokeLocal: cold start, expired refresh token, availability resolves '
      'AFTER auth settles to unauthenticated -> flag persisted, deleteToken '
      'exactly once', () async {
    final gate = Completer<bool>();
    final h = _H(auth: _user('u1'), initGate: gate);
    await h.container.read(authProvider.future);
    h.container.listen(pushRegistrationProvider, (_, _) {});
    await _settle(); // push build() = generation G, _start parked on gate
    // auth wipe + revokeLocal queued in the SAME tick: the push rebuild is
    // lazy, so revokeLocal still sees generation G; the settle then rebuilds
    // push (G+1) while revokeLocal is parked on availability.
    h.auth.set(const AuthSession.unauthenticated());
    final revoke = h.container
        .read(pushRegistrationProvider.notifier)
        .revokeLocal();
    await _settle();
    expect(await h.storage.readPushRevokePending(), isTrue);
    verifyNever(() => h.messaging.deleteToken());
    gate.complete(true);
    await revoke;
    await _settle();
    verify(() => h.messaging.deleteToken()).called(1);
    expect(await h.storage.readPushRevokePending(), isFalse);
  });

  test(
    'account switch: new user re-registers (backend rebinds the token)',
    () async {
      final h = _H();
      await h.start();
      h.auth.set(_user('u2'));
      await _settle();
      expect(h.repo.registered, ['tok-1', 'tok-1']);
    },
  );

  test(
    'same-user token refresh (new access token) does not re-register',
    () async {
      final h = _H();
      await h.start();
      h.auth.set(
        const AuthSession.authenticated(
          user: User(id: 'u1', email: 'u1@e.com', role: UserRole.salonOwner),
          accessToken: 'at2',
        ),
      );
      await _settle();
      expect(h.repo.registered, ['tok-1']);
      verify(() => h.messaging.requestPermission()).called(1);
    },
  );

  test('logout then re-login as another user: state returns to registered '
      'with the NEW token (broadcast refresh stream)', () async {
    final h = _H();
    await h.start();
    await h.container
        .read(pushRegistrationProvider.notifier)
        .unregisterForLogout();
    h.auth.set(const AuthSession.unauthenticated());
    await _settle();
    expect(h.state, const PushRegistrationState.idle());
    when(() => h.messaging.getToken()).thenAnswer((_) async => 'tok-2');

    h.auth.set(_user('u2'));
    await _settle();

    expect(h.repo.registered, ['tok-1', 'tok-2']);
    expect(h.state, const PushRegistrationState.registered());
  });

  test('harness pin: a SINGLE-subscription onTokenRefresh stream makes the '
      'second user\'s listen() throw, so state stays idle although the token '
      'WAS registered (test artefact, not a production bug)', () async {
    final h = _H();
    final once = StreamController<String>();
    addTearDown(() => unawaited(once.close()));
    when(() => h.messaging.onTokenRefresh).thenAnswer((_) => once.stream);
    await h.start();
    await h.container
        .read(pushRegistrationProvider.notifier)
        .unregisterForLogout();
    h.auth.set(const AuthSession.unauthenticated());
    await _settle();
    when(() => h.messaging.getToken()).thenAnswer((_) async => 'tok-2');

    h.auth.set(_user('u2'));
    await _settle();

    expect(h.repo.registered, contains('tok-2'));
    expect(h.state, const PushRegistrationState.idle());
  });
}
