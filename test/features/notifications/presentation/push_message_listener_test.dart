// Phase 068 — PushMessageListener: foreground FCM message -> bell / feed
// refresh (trailing-debounced); gated on registered push + signed-in user.
// Runs under fakeAsync with explicit `elapse`.

import 'dart:async';

import 'package:beautica_mobile/core/push/firebase_messaging_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/notifications/domain/notifications_feed_state.dart';
import 'package:beautica_mobile/features/notifications/domain/push_registration_state.dart';
import 'package:beautica_mobile/features/notifications/presentation/notifications_feed_notifier.dart';
import 'package:beautica_mobile/features/notifications/presentation/push_message_listener.dart';
import 'package:beautica_mobile/features/notifications/presentation/push_registration_notifier.dart';
import 'package:beautica_mobile/features/notifications/presentation/unread_notifications_notifier.dart';
import 'package:fake_async/fake_async.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const String _id = '00000000-0000-4000-8000-0000000000aa';

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

class _PushStub extends PushRegistration {
  _PushStub(this._initial);
  final PushRegistrationState _initial;

  @override
  PushRegistrationState build() => _initial;

  void set(PushRegistrationState s) => state = s;
}

class _FakeUnread extends UnreadNotifications {
  static int calls = 0;

  @override
  FutureOr<int> build() => 0;

  @override
  Future<void> refreshAfterPush() async => calls++;
}

class _FakeFeed extends NotificationsFeed {
  static int calls = 0;
  static int builds = 0;

  @override
  Future<NotificationsFeedState> build() async {
    builds++;
    return const NotificationsFeedState(items: [], nextPage: 0, hasMore: false);
  }

  @override
  Future<void> refreshFromPush() async => calls++;
}

class _H {
  _H(
    this.async, {
    PushRegistrationState push = const PushRegistrationState.registered(),
    AuthSession? auth,
  }) {
    _FakeUnread.calls = 0;
    _FakeFeed.calls = 0;
    _FakeFeed.builds = 0;
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(() => _AuthStub(auth ?? _user('u1'))),
        pushRegistrationProvider.overrideWith(() => _PushStub(push)),
        firebaseForegroundMessagesProvider.overrideWithValue(() {
          subscriptions++;
          return stream.stream;
        }),
        unreadNotificationsProvider.overrideWith(_FakeUnread.new),
        notificationsFeedProvider.overrideWith(_FakeFeed.new),
      ],
    );
  }

  final FakeAsync async;
  final StreamController<RemoteMessage> stream =
      StreamController<RemoteMessage>.broadcast();
  int subscriptions = 0;
  late final ProviderContainer container;

  _AuthStub get auth => container.read(authProvider.notifier) as _AuthStub;
  _PushStub get push =>
      container.read(pushRegistrationProvider.notifier) as _PushStub;

  void settle() {
    async.flushMicrotasks();
    async.elapse(Duration.zero);
    async.flushMicrotasks();
  }

  void start() {
    container.read(authProvider);
    settle();
    container.listen(pushMessageListenerProvider, (_, _) {});
    settle();
  }

  /// Delivers the message only (no debounce elapse).
  void push1(Map<String, dynamic> data) {
    stream.add(RemoteMessage(data: data));
    settle();
  }

  /// Delivers the message and lets the debounce fire.
  void send(Map<String, dynamic> data) {
    push1(data);
    elapse(kPushRefreshDebounce);
  }

  void elapse(Duration d) {
    async.elapse(d);
    settle();
  }

  void dispose() {
    container.dispose();
    stream.close();
  }
}

/// Runs [body] in fakeAsync with a harness that is always disposed.
void _t(
  String name,
  void Function(_H h) body, {
  PushRegistrationState push = const PushRegistrationState.registered(),
  AuthSession? auth,
}) {
  test(name, () {
    fakeAsync((FakeAsync async) {
      final h = _H(async, push: push, auth: auth);
      try {
        body(h);
      } finally {
        h.dispose();
      }
    });
  });
}

Map<String, dynamic> _payload() => <String, dynamic>{
  'v': '1',
  'notificationId': _id,
  'type': 'BOOKING_CREATED',
  'targetKind': 'BOOKING',
  'bookingId': _id,
};

void main() {
  _t('feed absent: refreshes the unread count, never builds the feed', (h) {
    h.start();
    h.send(_payload());
    expect(_FakeUnread.calls, 1);
    expect(_FakeFeed.calls, 0);
    expect(_FakeFeed.builds, 0);
  });

  _t('feed alive: refreshes the feed, not the count directly', (h) {
    h.start();
    h.container.listen(notificationsFeedProvider, (_, _) {});
    h.settle();
    h.send(_payload());
    expect(_FakeFeed.calls, 1);
    expect(_FakeUnread.calls, 0);
  });

  _t('malformed payload (missing / non-UUID id) is ignored', (h) {
    h.start();
    h.send(<String, dynamic>{'type': 'BOOKING_CREATED'});
    h.send(<String, dynamic>{'notificationId': 'nope'});
    h.send(<String, dynamic>{'notificationId': 42});
    expect(_FakeUnread.calls, 0);
  });

  _t('unknown type / targetKind / v still refreshes, never throws', (h) {
    h.start();
    h.send(<String, dynamic>{
      'v': '9',
      'notificationId': _id,
      'type': 'SOMETHING_NEW',
      'targetKind': 'WAT',
    });
    expect(_FakeUnread.calls, 1);
  });

  _t('burst of N pushes inside the window -> exactly ONE refresh', (h) {
    h.start();
    for (var i = 0; i < 6; i++) {
      h.push1(_payload());
      h.elapse(const Duration(milliseconds: 500));
    }
    expect(_FakeUnread.calls, 0, reason: 'trailing: nothing during the burst');
    h.elapse(kPushRefreshDebounce);
    expect(_FakeUnread.calls, 1);
    h.elapse(const Duration(seconds: 30));
    expect(_FakeUnread.calls, 1);
  });

  _t(
    'sustained stream (1 s apart, 12 s) refreshes at the max wait, not never',
    (h) {
      h.start();
      for (var i = 0; i < 12; i++) {
        h.push1(_payload());
        h.elapse(const Duration(seconds: 1));
        if (i == 3) expect(_FakeUnread.calls, 0, reason: 'before max wait');
        if (i == 4) expect(_FakeUnread.calls, 1, reason: 'max wait at ~5 s');
        if (i == 9) expect(_FakeUnread.calls, 2, reason: 'next burst at ~10 s');
      }
      expect(_FakeUnread.calls, 2);
      h.elapse(kPushRefreshDebounce);
      expect(_FakeUnread.calls, 3, reason: 'once after the stream stops');
      h.elapse(const Duration(seconds: 30));
      expect(_FakeUnread.calls, 3, reason: 'both timers cleared');
    },
  );

  _t('max-wait timer is cancelled on logout', (h) {
    h.start();
    h.push1(_payload());
    h.elapse(const Duration(seconds: 1));
    h.push1(_payload());
    h.auth.set(const AuthSession.unauthenticated());
    h.settle();
    h.elapse(const Duration(seconds: 30));
    expect(_FakeUnread.calls, 0);
  });

  _t('a push after the window opens a new burst (second refresh)', (h) {
    h.start();
    h.send(_payload());
    h.send(_payload());
    expect(_FakeUnread.calls, 2);
  });

  _t('logout cancels the pending debounce: no refresh fires', (h) {
    h.start();
    h.push1(_payload());
    h.auth.set(const AuthSession.unauthenticated());
    h.settle();
    h.elapse(const Duration(seconds: 10));
    expect(_FakeUnread.calls, 0);
  });

  _t('user switch cancels the pending debounce of the previous session', (h) {
    h.start();
    h.push1(_payload());
    h.auth.set(_user('u2'));
    h.settle();
    h.elapse(const Duration(seconds: 10));
    expect(_FakeUnread.calls, 0);
  });

  _t('dispose cancels the pending debounce', (h) {
    h.start();
    h.push1(_payload());
    h.container.dispose();
    h.elapse(const Duration(seconds: 10));
    expect(_FakeUnread.calls, 0);
  });

  _t('signed out: no subscription', (h) {
    h.start();
    expect(h.subscriptions, 0);
    h.send(_payload());
    expect(_FakeUnread.calls, 0);
  }, auth: const AuthSession.unauthenticated());

  for (final PushRegistrationState s in <PushRegistrationState>[
    const PushRegistrationState.unavailable(),
    const PushRegistrationState.permissionDenied(),
    const PushRegistrationState.idle(),
  ]) {
    _t('push state ${s.runtimeType}: no subscription, no processing', (h) {
      h.start();
      expect(h.subscriptions, 0);
      h.send(_payload());
      expect(_FakeUnread.calls, 0);
    }, push: s);
  }

  _t('logout cancels the subscription; re-login re-subscribes once', (h) {
    h.start();
    expect(h.subscriptions, 1);
    expect(h.stream.hasListener, isTrue);
    h.auth.set(const AuthSession.unauthenticated());
    h.settle();
    expect(h.stream.hasListener, isFalse);
    h.send(_payload());
    expect(_FakeUnread.calls, 0);
    h.auth.set(_user('u2'));
    h.settle();
    expect(h.subscriptions, 2);
    h.send(_payload());
    expect(_FakeUnread.calls, 1);
  });

  _t('registration leaving `registered` cancels the subscription', (h) {
    h.start();
    h.push.set(const PushRegistrationState.idle());
    h.settle();
    expect(h.stream.hasListener, isFalse);
  });

  _t('dispose cancels the subscription', (h) {
    h.start();
    h.container.dispose();
    expect(h.stream.hasListener, isFalse);
  });
}
