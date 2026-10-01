// Phase 069 — PendingPushTap: background taps + the one cold-start read, held
// while the session resolves, dropped when signed out / user changes.

import 'dart:async';

import 'package:beautica_mobile/core/push/firebase_messaging_provider.dart';
import 'package:beautica_mobile/core/push/push_available_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/notifications/domain/app_notification.dart';
import 'package:beautica_mobile/features/notifications/domain/push_tap.dart';
import 'package:beautica_mobile/features/notifications/presentation/pending_push_tap_notifier.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

const String _id1 = '00000000-0000-4000-8000-0000000000a1';
const String _id2 = '00000000-0000-4000-8000-0000000000a2';
const String _bk = '00000000-0000-4000-8000-0000000000b1';

class _MockMessaging extends Mock implements FirebaseMessaging {}

class _AuthStub extends AuthNotifier {
  _AuthStub(this.gate);
  final Completer<AuthSession> gate;

  @override
  Future<AuthSession> build() => gate.future;

  void set(AuthSession s) => state = AsyncData<AuthSession>(s);
}

AuthSession _user(String id) => AuthSession.authenticated(
  user: User(id: id, email: '$id@e.com', role: UserRole.client),
  accessToken: 'at',
);

Map<String, dynamic> _data(String id) => <String, dynamic>{
  'notificationId': id,
  'type': 'BOOKING_CREATED',
  'targetKind': 'BOOKING',
  'bookingId': _bk,
};

Future<void> _settle() async {
  for (int i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _H {
  _H({bool available = true, RemoteMessage? initial}) {
    when(() => messaging.getInitialMessage()).thenAnswer((_) async {
      initialReads++;
      return initial;
    });
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(() => auth),
        pushAvailableProvider.overrideWith((ref) async => available),
        firebaseMessagingProvider.overrideWithValue(messaging),
        firebaseOpenedAppMessagesProvider.overrideWithValue(() {
          subscriptions++;
          return opened.stream;
        }),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(opened.close);
  }

  final _MockMessaging messaging = _MockMessaging();
  final Completer<AuthSession> gate = Completer<AuthSession>();
  late final _AuthStub auth = _AuthStub(gate);
  final StreamController<RemoteMessage> opened =
      StreamController<RemoteMessage>.broadcast();
  late final ProviderContainer container;
  int initialReads = 0;
  int subscriptions = 0;

  PushTap? get tap => container.read(pendingPushTapProvider);

  Future<void> start() async {
    container.listen(authProvider, (_, _) {});
    container.listen(pendingPushTapProvider, (_, _) {});
    await _settle();
  }

  Future<void> resolve(AuthSession s) async {
    gate.complete(s);
    await _settle();
  }
}

void main() {
  test('should_readInitialMessageOnce_andHoldItWhileSessionResolves', () async {
    final _H h = _H(initial: RemoteMessage(data: _data(_id1)));
    await h.start();
    expect(h.initialReads, 1);
    expect(h.tap?.notificationId, _id1); // held: session still loading
    await h.resolve(_user('u1'));
    expect(h.tap?.notificationId, _id1);
    expect(h.initialReads, 1);
  });

  test('should_replacePendingTap_when_onMessageOpenedAppFires', () async {
    final _H h = _H(initial: RemoteMessage(data: _data(_id1)));
    await h.start();
    await h.resolve(_user('u1'));
    h.opened.add(RemoteMessage(data: _data(_id2)));
    await _settle();
    expect(h.tap?.notificationId, _id2);
    expect(h.tap?.target, const NotificationTarget.booking(bookingId: _bk));
  });

  test('should_ignoreMalformedPayload', () async {
    final _H h = _H();
    await h.start();
    await h.resolve(_user('u1'));
    h.opened.add(
      const RemoteMessage(data: <String, dynamic>{'notificationId': 'x'}),
    );
    await _settle();
    expect(h.tap, isNull);
  });

  test('should_dropTap_when_sessionResolvesAnonymous', () async {
    final _H h = _H(initial: RemoteMessage(data: _data(_id1)));
    await h.start();
    expect(h.tap, isNotNull);
    await h.resolve(const AuthSession.unauthenticated());
    expect(h.tap, isNull);
  });

  test('should_notReplayLaunchTap_when_coldStartSignedOut_thenSignIn', () async {
    final _H h = _H(initial: RemoteMessage(data: _data(_id1)));
    h.container.listen(authProvider, (_, _) {});
    await h.resolve(const AuthSession.unauthenticated());
    // The pending-tap notifier is first built AFTER the session settled signed out.
    h.container.listen(pendingPushTapProvider, (_, _) {});
    await _settle();
    expect(h.initialReads, 0);
    h.auth.set(_user('u2'));
    await _settle();
    expect(h.initialReads, 0, reason: 'launch tap forfeited while signed out');
    expect(h.tap, isNull);
  });

  test('should_notReplayLaunchTap_when_resolvedAnonymousThenSignIn', () async {
    final _H h = _H(initial: RemoteMessage(data: _data(_id1)));
    await h.start();
    await h.resolve(const AuthSession.unauthenticated());
    h.auth.set(_user('u2'));
    await _settle();
    expect(h.tap, isNull);
    expect(h.initialReads, lessThanOrEqualTo(1));
  });

  test('should_dropTap_when_userSwitches', () async {
    final _H h = _H();
    await h.start();
    await h.resolve(_user('u1'));
    h.opened.add(RemoteMessage(data: _data(_id1)));
    await _settle();
    expect(h.tap, isNotNull);
    h.auth.set(_user('u2'));
    await _settle();
    expect(h.tap, isNull);
  });

  test('should_notReplayTap_afterLogoutAndLogin_orReadInitialAgain', () async {
    final _H h = _H(initial: RemoteMessage(data: _data(_id1)));
    await h.start();
    await h.resolve(_user('u1'));
    h.auth.set(const AuthSession.unauthenticated());
    await _settle();
    expect(h.tap, isNull);
    h.auth.set(_user('u2'));
    await _settle();
    expect(h.tap, isNull);
    expect(h.initialReads, 1);
  });

  test('should_cancelSubscription_when_signedOut_andIgnoreTaps', () async {
    final _H h = _H();
    await h.start();
    await h.resolve(const AuthSession.unauthenticated());
    expect(h.opened.hasListener, isFalse);
    h.opened.add(RemoteMessage(data: _data(_id1)));
    await _settle();
    expect(h.tap, isNull);
  });

  test('should_resubscribe_after_signInFollowingLogout', () async {
    final _H h = _H();
    await h.start();
    await h.resolve(const AuthSession.unauthenticated());
    h.auth.set(_user('u1'));
    await _settle();
    expect(h.opened.hasListener, isTrue);
    h.opened.add(RemoteMessage(data: _data(_id2)));
    await _settle();
    expect(h.tap?.notificationId, _id2);
  });

  test('should_beNoOp_when_pushUnavailable', () async {
    final _H h = _H(
      available: false,
      initial: RemoteMessage(data: _data(_id1)),
    );
    await h.start();
    await h.resolve(_user('u1'));
    expect(h.initialReads, 0);
    expect(h.subscriptions, 0);
    expect(h.tap, isNull);
  });

  test('take_should_returnAndClear', () async {
    final _H h = _H();
    await h.start();
    await h.resolve(_user('u1'));
    h.opened.add(RemoteMessage(data: _data(_id1)));
    await _settle();
    expect(h.container.read(pendingPushTapProvider.notifier).take(), isNotNull);
    expect(h.tap, isNull);
  });

  test('should_cancelSubscription_when_containerDisposed', () async {
    final _H h = _H();
    await h.start();
    await h.resolve(_user('u1'));
    expect(h.opened.hasListener, isTrue);
    h.container.dispose();
    await _settle();
    expect(h.opened.hasListener, isFalse);
  });
}
