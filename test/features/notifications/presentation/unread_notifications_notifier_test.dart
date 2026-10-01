// Phase 360 — UnreadNotifications: resume fetch, periodic polling, pause /
// logout / user-switch, 429 back-off, error tolerance, in-flight coalescing
// and salon-independence.
//
// Everything runs under fakeAsync with explicit `elapse` — never
// `pumpAndSettle`, which does not fire Timers. Lifecycle is driven through the
// real binding (`handleAppLifecycleStateChanged`) so the `AppLifecycleListener`
// the notifier owns is exercised for real.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/notifications/data/notification_repository.dart';
import 'package:beautica_mobile/features/notifications/domain/app_notification.dart';
import 'package:beautica_mobile/features/notifications/presentation/unread_notifications_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_shell_provider.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const Duration _interval = Duration(seconds: 10);

class _FakeRepo implements NotificationRepository {
  int calls = 0;
  Future<int> Function() handler = () async => 0;

  @override
  Future<int> unreadCount() {
    calls++;
    return handler();
  }

  @override
  Future<NotificationPage> fetchPage({required int page, required int size}) =>
      throw UnimplementedError();

  @override
  Future<void> markRead(String id) => throw UnimplementedError();

  @override
  Future<int> markAllRead({DateTime? upTo}) => throw UnimplementedError();
}

class _AuthStub extends AuthNotifier {
  _AuthStub(this._initial);
  final AsyncValue<AuthSession> _initial;

  @override
  Future<AuthSession> build() async =>
      _initial.value ?? const AuthSession.unauthenticated();

  void set(AsyncValue<AuthSession> v) => state = v;
}

AsyncValue<AuthSession> _session(String id, {String token = 'token'}) =>
    AsyncData<AuthSession>(
      AuthSession.authenticated(
        user: User(id: id, email: '$id@e.com', role: UserRole.salonOwner),
        accessToken: token,
      ),
    );

const AsyncValue<AuthSession> _loggedOut = AsyncData<AuthSession>(
  AuthSession.unauthenticated(),
);

class _H {
  _H(this.async, {AsyncValue<AuthSession>? auth, Duration? jitter}) {
    final AsyncValue<AuthSession> initial = auth ?? _session('u1');
    final DateTime start = DateTime.utc(2026, 1, 1);
    container = ProviderContainer(
      overrides: [
        notificationRepositoryProvider.overrideWithValue(repo),
        pollIntervalProvider.overrideWithValue(_interval),
        if (jitter != null) pollJitterProvider.overrideWithValue(jitter),
        // DateTime.now is not faked by fakeAsync: derive the instant from it.
        clockProvider.overrideWithValue(() => start.add(async.elapsed)),
        authProvider.overrideWith(() => _AuthStub(initial)),
      ],
    );
  }

  final FakeAsync async;
  final _FakeRepo repo = _FakeRepo();
  late final ProviderContainer container;

  /// Settles the auth stub, builds the notifier and lets the first fetch land.
  void start() {
    container.read(authProvider);
    async.flushMicrotasks();
    container.listen(unreadNotificationsProvider, (_, _) {});
    async.flushMicrotasks();
  }

  int? get value => container.read(unreadNotificationsProvider).value;
  UnreadNotifications get notifier =>
      container.read(unreadNotificationsProvider.notifier);
  _AuthStub get auth => container.read(authProvider.notifier) as _AuthStub;

  /// Walks the real platform transition chain (the listener asserts it).
  void background() {
    _walk(const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]);
    async.flushMicrotasks();
  }

  void foreground() {
    _walk(const [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]);
    async.flushMicrotasks();
  }

  void inactive() {
    _walk(const [AppLifecycleState.inactive]);
    async.flushMicrotasks();
  }

  void elapse(Duration d) {
    async.elapse(d);
    async.flushMicrotasks();
  }
}

void _walk(List<AppLifecycleState> states) {
  for (final AppLifecycleState s in states) {
    TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(s);
  }
}

void _run(
  void Function(_H h) body, {
  AsyncValue<AuthSession>? auth,
  Duration? jitter,
}) {
  fakeAsync((FakeAsync async) {
    final _H h = _H(async, auth: auth, jitter: jitter);
    try {
      body(h);
    } finally {
      h.container.dispose();
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // The binding is global: leave every test starting from `resumed`.
    final AppLifecycleState? current =
        TestWidgetsFlutterBinding.instance.lifecycleState;
    if (current == AppLifecycleState.paused) {
      _walk(const [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]);
    } else if (current == AppLifecycleState.inactive) {
      _walk(const [AppLifecycleState.resumed]);
    }
  });

  test('should_addJitterToPollPeriod_when_jitterOverridden', () {
    const Duration jitter = Duration(seconds: 4);
    _run(jitter: jitter, (h) {
      h.repo.handler = () async => 1;
      h.start();
      expect(h.repo.calls, 1); // initial fetch
      // No tick at the bare interval: the period is interval + jitter.
      h.elapse(_interval);
      expect(h.repo.calls, 1);
      h.elapse(jitter);
      expect(h.repo.calls, 2);
    });
  });

  test('should_defaultPollJitterToZero_when_notOverridden', () {
    // Production (`main.dart`) overrides the jitter with a random value; every
    // test relies on the un-overridden default being exactly zero so the poll
    // period is the bare interval and fake-async ticks stay deterministic.
    final ProviderContainer c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(pollJitterProvider), Duration.zero);
  });

  test('should_fetchOnResume', () {
    _run((h) {
      h.repo.handler = () async => 3;
      h.start();
      expect(h.repo.calls, 1);
      expect(h.value, 3);

      h.background();
      h.elapse(const Duration(seconds: 20));
      h.foreground();
      expect(h.repo.calls, 2);
    });
  });

  test('should_throttleRapidResumes', () {
    _run((h) {
      h.start();
      expect(h.repo.calls, 1);

      // Resumes within 15 s of the last successful fetch: no request.
      h.background();
      h.foreground();
      h.background();
      h.foreground();
      expect(h.repo.calls, 1);

      // An explicit refresh is exempt from the gap.
      h.notifier.refresh();
      h.async.flushMicrotasks();
      expect(h.repo.calls, 2);

      // Past the gap a resume fetches again.
      h.background();
      h.elapse(const Duration(seconds: 16));
      h.foreground();
      expect(h.repo.calls, 3);
    });
  });

  test('should_pollEveryInterval_whileResumed', () {
    _run((h) {
      h.start();
      expect(h.repo.calls, 1);
      h.elapse(_interval);
      expect(h.repo.calls, 2);
      h.elapse(_interval);
      expect(h.repo.calls, 3);
      h.elapse(_interval * 2);
      expect(h.repo.calls, 5);
    });
  });

  test('should_stopPolling_whenPaused', () {
    _run((h) {
      h.start();
      final int before = h.repo.calls;
      h.inactive();
      h.elapse(_interval * 10);
      expect(h.repo.calls, before);
    });
  });

  test('should_resetToZeroAndStop_onLogout', () {
    _run((h) {
      h.repo.handler = () async => 5;
      h.start();
      expect(h.value, 5);

      h.auth.set(_loggedOut);
      h.async.flushMicrotasks();
      expect(h.value, 0);

      final int before = h.repo.calls;
      h.elapse(_interval * 5);
      h.background();
      h.foreground();
      expect(h.repo.calls, before);
      expect(h.value, 0);
    });
  });

  test('should_backOffForRetryAfter_on429', () {
    _run((h) {
      h.repo.handler = () async =>
          throw const NotificationsRateLimitedFailure(retryAfterSeconds: 35);
      h.start();
      expect(h.repo.calls, 1);

      // Several intervals inside the window: nothing fires.
      h.elapse(const Duration(seconds: 34));
      expect(h.repo.calls, 1);

      h.repo.handler = () async => 4;
      h.elapse(const Duration(seconds: 1));
      expect(h.repo.calls, 2);
      expect(h.value, 4);

      // Polling resumed on the normal cadence.
      h.elapse(_interval);
      expect(h.repo.calls, 3);
    });
  });

  test('should_backOffForDefault120s_when429HasNoRetryAfter', () {
    _run((h) {
      h.repo.handler = () async =>
          throw const NotificationsRateLimitedFailure();
      h.start();
      h.elapse(const Duration(seconds: 119));
      expect(h.repo.calls, 1);
      h.repo.handler = () async => 1;
      h.elapse(const Duration(seconds: 1));
      expect(h.repo.calls, 2);
    });
  });

  test('should_notFetchOnResume_whileBackingOff', () {
    _run((h) {
      h.repo.handler = () async =>
          throw const NotificationsRateLimitedFailure(retryAfterSeconds: 60);
      h.start();
      h.background();
      h.foreground();
      expect(h.repo.calls, 1);
    });
  });

  test('should_keepLastValue_onNetworkError', () {
    _run((h) {
      h.repo.handler = () async => 4;
      h.start();
      expect(h.value, 4);

      h.repo.handler = () async => throw const NetworkFailure();
      h.elapse(_interval);
      expect(h.repo.calls, 2);
      expect(h.value, 4);
      expect(h.container.read(unreadNotificationsProvider).hasError, isFalse);

      h.repo.handler = () async => 5;
      h.elapse(_interval);
      expect(h.repo.calls, 3);
      expect(h.value, 5);
    });
  });

  test('should_resetOnUserSwitch', () {
    _run((h) {
      h.repo.handler = () async => 7;
      h.start();
      expect(h.value, 7);

      h.repo.handler = () async => 2;
      h.auth.set(_session('u2'));
      h.elapse(Duration.zero);
      expect(h.repo.calls, 2);
      expect(h.value, 2);
    });
  });

  test('should_notRefetch_onSameUserTokenRefresh', () {
    _run((h) {
      h.repo.handler = () async => 6;
      h.start();
      h.auth.set(_session('u1', token: 'rotated'));
      h.async.flushMicrotasks();
      expect(h.repo.calls, 1);
      expect(h.value, 6);
    });
  });

  test('should_notRefetchOrReset_when_activeSalonChanges', () {
    _run((h) {
      h.repo.handler = () async => 9;
      h.start();
      expect(h.value, 9);
      final int before = h.repo.calls;

      h.container.listen(salonShellProvider('salon-1'), (_, _) {});
      h.container.listen(salonShellProvider('salon-2'), (_, _) {});
      h.container.read(salonShellProvider('salon-1').notifier).select(2);
      h.container.read(salonShellProvider('salon-2').notifier).select(1);
      h.async.flushMicrotasks();

      expect(h.repo.calls, before);
      expect(h.value, 9);
    });
  });

  test('should_coalesceConcurrentRefresh_intoOneRequest', () {
    _run((h) {
      h.start();
      final int before = h.repo.calls;
      final Completer<int> gate = Completer<int>();
      h.repo.handler = () => gate.future;

      final Future<void> a = h.notifier.refresh();
      final Future<void> b = h.notifier.refresh();
      // A timer tick + resume landing while it is still in flight.
      h.elapse(_interval);
      expect(h.repo.calls, before + 1);
      expect(identical(a, b), isTrue);

      gate.complete(8);
      h.async.flushMicrotasks();
      expect(h.value, 8);

      // Once settled, the next refresh issues a fresh request.
      h.repo.handler = () async => 1;
      h.notifier.refresh();
      h.async.flushMicrotasks();
      expect(h.repo.calls, before + 2);
    });
  });

  test('should_setCountAndDecrement_flooringAtZero', () {
    _run((h) {
      h.repo.handler = () async => 2;
      h.start();
      h.notifier.decrement(forUserId: 'u1');
      expect(h.value, 1);
      h.notifier.decrement(forUserId: 'u1');
      h.notifier.decrement(forUserId: 'u1');
      expect(h.value, 0);
      h.notifier.setCount(12, forUserId: 'u1');
      expect(h.value, 12);
      h.notifier.setCount(-3, forUserId: 'u1');
      expect(h.value, 0);
    });
  });

  test('should_incrementByDelta_andIgnoreNonPositiveOrForeignUser', () {
    _run((h) {
      h.repo.handler = () async => 2;
      h.start();
      h.notifier.increment(forUserId: 'u1');
      expect(h.value, 3);
      h.notifier.increment(forUserId: 'u1', by: 4);
      expect(h.value, 7);
      h.notifier.increment(forUserId: 'u1', by: 0);
      h.notifier.increment(forUserId: 'u1', by: -2);
      expect(h.value, 7);
      h.notifier.increment(forUserId: 'someone-else');
      expect(h.value, 7);
    });
  });

  test('should_dropAFetchThatWasInFlightAcrossAnIncrement', () {
    _run((h) {
      h.start();
      final Completer<int> stale = Completer<int>();
      h.repo.handler = () => stale.future;
      h.notifier.refresh();
      h.async.flushMicrotasks();

      // Same `_version` rule as decrement / setCount: the increment makes the
      // request stale, so its (pre-mutation) answer is dropped.
      h.notifier.increment(forUserId: 'u1');
      final int afterIncrement = h.value!;
      h.repo.handler = () async => afterIncrement;
      stale.complete(99);
      h.async.flushMicrotasks();

      expect(h.value, afterIncrement);
    });
  });

  test('should_exposeHasUnreadBoolean', () {
    _run((h) {
      h.repo.handler = () async => 2;
      h.start();
      h.container.listen(hasUnreadNotificationsProvider, (_, _) {});
      expect(h.container.read(hasUnreadNotificationsProvider), isTrue);
      h.notifier.setCount(0, forUserId: 'u1');
      expect(h.container.read(hasUnreadNotificationsProvider), isFalse);
    });
  });

  test('should_notFetch_whenSignedOutFromStart', () {
    _run((h) {
      h.start();
      h.elapse(_interval * 3);
      expect(h.repo.calls, 0);
      expect(h.value, 0);
    }, auth: _loggedOut);
  });

  // ---- audit cycle 1 ----

  test('should_dropStaleFetch_whenSetCountLandedWhileInFlight', () {
    _run((h) {
      h.repo.handler = () async => 3;
      h.start();
      final Completer<int> gate = Completer<int>();
      h.repo.handler = () => gate.future;
      h.notifier.refresh();
      h.async.flushMicrotasks();
      final int inFlight = h.repo.calls;

      h.notifier.setCount(0, forUserId: 'u1');
      h.repo.handler = () async => 0;
      gate.complete(5);
      h.async.flushMicrotasks();
      expect(h.value, 0, reason: 'stale 5 dropped');
      // start (1) + in-flight refresh (2) + the single follow-up (3).
      expect(inFlight, 2);
      expect(h.repo.calls, 3, reason: 'one follow-up only');

      // One extra interval: only the normal tick, no further follow-up.
      h.elapse(_interval);
      expect(h.repo.calls, 4, reason: 'exactly one tick after the follow-up');
    });
  });

  test('should_notCoalesceRefreshOntoPreMutationRequest', () {
    _run((h) {
      h.start();
      final Completer<int> stale = Completer<int>();
      h.repo.handler = () => stale.future;
      h.notifier.refresh();
      h.async.flushMicrotasks();
      final int before = h.repo.calls;

      h.notifier.decrement(forUserId: 'u1');
      h.repo.handler = () async => 9;
      h.notifier.refresh();
      h.async.flushMicrotasks();
      expect(h.repo.calls, before + 1, reason: 'fresh request, not joined');
      expect(h.value, 9);

      // The stale one landing afterwards is still dropped.
      stale.complete(2);
      h.async.flushMicrotasks();
      expect(h.value, 9);
    });
  });

  test('should_notDuplicateRequest_whenUserSwitchesMidFetch', () {
    _run((h) {
      h.start();
      final Completer<int> gateA = Completer<int>();
      h.repo.handler = () => gateA.future;
      h.notifier.refresh();
      h.async.flushMicrotasks();

      final Completer<int> gateB = Completer<int>();
      h.repo.handler = () => gateB.future;
      final int before = h.repo.calls;
      h.auth.set(_session('u2'));
      h.elapse(Duration.zero);
      expect(h.repo.calls, before + 1, reason: 'exactly one request for B');

      // A's stale future settling must not clear B's in-flight slot...
      gateA.complete(99);
      h.async.flushMicrotasks();
      // ...so a refresh while B is still pending joins it.
      h.notifier.refresh();
      h.async.flushMicrotasks();
      expect(h.repo.calls, before + 1);

      gateB.complete(2);
      h.async.flushMicrotasks();
      expect(h.value, 2);
    });
  });

  test('should_survive_nonFailureException', () {
    _run((h) {
      h.repo.handler = () async => 4;
      h.start();
      h.repo.handler = () async => throw StateError('boom');
      h.elapse(_interval);
      expect(h.value, 4);
      expect(h.container.read(unreadNotificationsProvider).hasError, isFalse);
      h.repo.handler = () async => 6;
      h.elapse(_interval);
      expect(h.value, 6);
    });
  });

  test('should_honourRetryAfter3600', () {
    _run((h) {
      h.repo.handler = () async =>
          throw const NotificationsRateLimitedFailure(retryAfterSeconds: 3600);
      h.start();
      h.elapse(const Duration(seconds: 3599));
      expect(h.repo.calls, 1);
      h.repo.handler = () async => 1;
      h.elapse(const Duration(seconds: 1));
      expect(h.repo.calls, 2);
    });
  });

  test('should_floorRetryAfterTo30s', () {
    _run((h) {
      h.repo.handler = () async =>
          throw const NotificationsRateLimitedFailure(retryAfterSeconds: 1);
      h.start();
      h.elapse(const Duration(seconds: 29));
      expect(h.repo.calls, 1);
      h.repo.handler = () async => 1;
      h.elapse(const Duration(seconds: 1));
      expect(h.repo.calls, 2);
    });
  });

  test('should_ignoreMutation_forPreviousUser', () {
    _run((h) {
      h.repo.handler = () async => 2;
      h.start();
      h.auth.set(_session('u2'));
      h.elapse(Duration.zero);
      expect(h.value, 2);

      h.notifier.setCount(7, forUserId: 'u1');
      expect(h.value, 2);
      h.notifier.decrement(forUserId: 'u1');
      expect(h.value, 2);
      h.notifier.setCount(7, forUserId: 'u2');
      expect(h.value, 7);
    });
  });

  test('should_ignoreLateSuccess_afterLogout', () {
    _run((h) {
      h.start();
      final Completer<int> gate = Completer<int>();
      h.repo.handler = () => gate.future;
      h.notifier.refresh();
      h.async.flushMicrotasks();

      h.auth.set(_loggedOut);
      h.async.flushMicrotasks();
      gate.complete(8);
      h.async.flushMicrotasks();
      expect(h.value, 0);
    });
  });

  test('should_ignoreLateResponse_afterUserSwitch', () {
    _run((h) {
      h.start();
      final Completer<int> gate = Completer<int>();
      h.repo.handler = () => gate.future;
      h.notifier.refresh();
      h.async.flushMicrotasks();

      h.repo.handler = () async => 1;
      h.auth.set(_session('u2'));
      h.elapse(Duration.zero);
      expect(h.value, 1);
      gate.complete(8);
      h.async.flushMicrotasks();
      expect(h.value, 1);
    });
  });

  test('should_ignoreLate429_afterUserSwitch', () {
    _run((h) {
      h.start();
      final Completer<int> gate = Completer<int>();
      h.repo.handler = () => gate.future;
      h.notifier.refresh();
      h.async.flushMicrotasks();

      h.repo.handler = () async => 1;
      h.auth.set(_session('u2'));
      h.elapse(Duration.zero);
      gate.completeError(
        const NotificationsRateLimitedFailure(retryAfterSeconds: 600),
      );
      h.async.flushMicrotasks();

      // B is NOT suspended: the next tick still fetches.
      final int before = h.repo.calls;
      h.elapse(_interval);
      expect(h.repo.calls, before + 1);
    });
  });

  test('should_notFetchOnResume_whenSignedOut', () {
    _run((h) {
      h.start();
      h.background();
      h.elapse(const Duration(seconds: 60));
      h.foreground();
      expect(h.repo.calls, 0);
    }, auth: _loggedOut);
  });

  test('should_notRequest_onLifecycleEvent_afterContainerDispose', () {
    fakeAsync((FakeAsync async) {
      final _H h = _H(async);
      h.start();
      h.background();
      final int before = h.repo.calls;
      h.container.dispose();
      h.async.elapse(const Duration(seconds: 60));
      h.foreground();
      expect(h.repo.calls, before);
    });
  });

  test('should_notNotifyHasUnreadListener_onSameCountPoll', () {
    _run((h) {
      h.repo.handler = () async => 3;
      h.start();
      int fired = 0;
      h.container.listen(hasUnreadNotificationsProvider, (_, _) => fired++);
      h.elapse(_interval);
      h.elapse(_interval);
      expect(h.repo.calls, 3);
      expect(fired, 0);
    });
  });

  test('should_applyBackoff_when429ArrivesWhileBackgrounded', () {
    _run((h) {
      h.start();
      final Completer<int> gate = Completer<int>();
      h.repo.handler = () => gate.future;
      h.notifier.refresh();
      h.async.flushMicrotasks();

      h.background();
      gate.completeError(
        const NotificationsRateLimitedFailure(retryAfterSeconds: 60),
      );
      h.async.flushMicrotasks();

      // Resume while suspended: no fetch, no polling restart.
      h.foreground();
      final int before = h.repo.calls;
      h.elapse(const Duration(seconds: 59));
      expect(h.repo.calls, before);

      // Back-off ends (foregrounded): polling resumes with a fetch.
      h.repo.handler = () async => 2;
      h.elapse(const Duration(seconds: 1));
      expect(h.repo.calls, before + 1);
      expect(h.value, 2);
    });
  });

  test(
    'should_stayQuietAndFetchOnceOnResume_whenBackoffEndsWhileBackgrounded',
    () {
      _run((h) {
        h.repo.handler = () async =>
            throw const NotificationsRateLimitedFailure(retryAfterSeconds: 60);
        h.start();
        expect(h.repo.calls, 1);

        h.background();
        h.repo.handler = () async => 8;
        // Back-off elapses while paused: no request, no timer restarted.
        h.elapse(const Duration(seconds: 300));
        expect(h.repo.calls, 1);

        // Foregrounded: exactly one request, then the normal cadence.
        h.foreground();
        expect(h.repo.calls, 2);
        expect(h.value, 8);
        h.elapse(_interval);
        expect(h.repo.calls, 3);
      });
    },
  );

  // ---- audit cycle 2 ----

  test('should_reconcileWithOneFollowUp_whenStaleFetchDropped', () {
    _run((h) {
      h.repo.handler = () async => 3;
      h.start();
      final Completer<int> gate = Completer<int>();
      h.repo.handler = () => gate.future;
      h.notifier.refresh();
      h.async.flushMicrotasks();
      final int before = h.repo.calls;

      h.notifier.setCount(1, forUserId: 'u1');
      h.repo.handler = () async => 8;
      gate.complete(99);
      h.async.flushMicrotasks();

      // start (1) + in-flight refresh (2) + the single follow-up (3).
      expect(before, 2);
      expect(h.repo.calls, 3, reason: 'exactly one follow-up');
      expect(h.value, 8, reason: 'follow-up wins over the mutation');
      h.async.flushMicrotasks();
      expect(h.repo.calls, 3, reason: 'no loop');

      // One extra interval: only the normal tick, no further follow-up.
      h.elapse(_interval);
      expect(h.repo.calls, 4, reason: 'exactly one tick after the follow-up');
    });
  });

  test('should_notRefetchOnResume_afterFailedFetch_withinGap', () {
    _run((h) {
      h.repo.handler = () async => throw const NetworkFailure();
      h.start();
      expect(h.repo.calls, 1);

      h.background();
      h.elapse(const Duration(seconds: 5));
      h.foreground();
      expect(h.repo.calls, 1);

      h.background();
      h.elapse(const Duration(seconds: 11));
      h.foreground();
      expect(h.repo.calls, 2);
    });
  });

  test('should_notRefetchOnResume_afterUnexpectedError_withinGap', () {
    _run((h) {
      h.repo.handler = () async => throw StateError('boom');
      h.start();
      h.background();
      h.foreground();
      expect(h.repo.calls, 1);
    });
  });

  test('should_fetchOnResume_whenClockMovedBackwards', () {
    _run((h) {
      final DateTime start = DateTime.utc(2026, 1, 1);
      Duration skew = Duration.zero;
      h.container.dispose();
      final ProviderContainer c = ProviderContainer(
        overrides: [
          notificationRepositoryProvider.overrideWithValue(h.repo),
          pollIntervalProvider.overrideWithValue(_interval),
          clockProvider.overrideWithValue(
            () => start.add(h.async.elapsed + skew),
          ),
          authProvider.overrideWith(() => _AuthStub(_session('u1'))),
        ],
      );
      addTearDown(c.dispose);
      c.read(authProvider);
      h.async.flushMicrotasks();
      c.listen(unreadNotificationsProvider, (_, _) {});
      h.async.flushMicrotasks();
      expect(h.repo.calls, 1);

      h.background();
      skew = const Duration(hours: -1);
      h.foreground();
      expect(h.repo.calls, 2);
      c.dispose();
    });
  });

  test('should_keepCount_onSameUserRebuild_andResetOnUserSwitch', () {
    _run((h) {
      h.repo.handler = () async => 4;
      h.start();
      expect(h.value, 4);

      h.repo.handler = () => Completer<int>().future; // never lands
      h.container.invalidate(unreadNotificationsProvider);
      h.async.flushMicrotasks();
      expect(h.value, 4, reason: 'same user: dot must not flicker off');

      h.auth.set(_session('u2'));
      h.async.flushMicrotasks();
      expect(h.value, 0, reason: 'user switch resets');
    });
  });
}
