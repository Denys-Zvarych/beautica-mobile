// Phase 393 (24.7a) — `pendingBookingActionsCountProvider`.
//
// Pins: each scope variant reaches the repository with that exact scope,
// a repository failure surfaces as AsyncError (never a fake `0`), and family
// members are keyed per scope (two salons never share a count).

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/pending_booking_actions_count.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockBookingRepository extends Mock implements BookingRepository {}

const User _u1 = User(
  id: 'u1',
  email: 'u1@beautica.ua',
  role: UserRole.salonOwner,
  firstName: 'Оля',
  lastName: 'Коваль',
);
const User _u2 = User(
  id: 'u2',
  email: 'u2@beautica.ua',
  role: UserRole.salonOwner,
  firstName: 'Ірина',
  lastName: 'Бондар',
);
const AuthSession _as1 = AuthSession.authenticated(
  user: _u1,
  accessToken: 't1',
);
const AuthSession _as2 = AuthSession.authenticated(
  user: _u2,
  accessToken: 't2',
);

class _MutableAuthNotifier extends AuthNotifier {
  _MutableAuthNotifier(this._initial);
  final AuthSession _initial;

  @override
  Future<AuthSession> build() async => _initial;

  void setSession(AuthSession s) => state = AsyncData<AuthSession>(s);
}

void main() {
  late _MockBookingRepository repo;
  late ProviderContainer container;
  late _MutableAuthNotifier auth;

  setUpAll(() {
    registerFallbackValue(const PendingActionsScope.me(asMaster: false));
  });

  setUp(() async {
    repo = _MockBookingRepository();
    auth = _MutableAuthNotifier(_as1);
    container = ProviderContainer(
      // Riverpod 3 retries a failing provider; a test asserting the error
      // state must opt out or it waits out the backoff.
      retry: (_, _) => null,
      overrides: [
        bookingRepositoryProvider.overrideWithValue(repo),
        authProvider.overrideWith(() => auth),
      ],
    );
    addTearDown(container.dispose);
    // Settle auth first: build() watches the user id.
    await container.read(authProvider.future);
  });

  Future<int> read(PendingActionsScope scope) =>
      container.read(pendingBookingActionsCountProvider(scope).future);

  test('.me(asMaster: false) calls the repository with that scope', () async {
    const scope = PendingActionsScope.me(asMaster: false);
    when(
      () => repo.getPendingActionsCount(
        scope,
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) async => 3);

    expect(await read(scope), 3);
    verify(
      () => repo.getPendingActionsCount(
        scope,
        cancelToken: any(named: 'cancelToken'),
      ),
    ).called(1);
  });

  test('.me(asMaster: true) calls the repository with that scope', () async {
    const scope = PendingActionsScope.me(asMaster: true);
    when(
      () => repo.getPendingActionsCount(
        scope,
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) async => 2);

    expect(await read(scope), 2);
    verify(
      () => repo.getPendingActionsCount(
        scope,
        cancelToken: any(named: 'cancelToken'),
      ),
    ).called(1);
    verifyNever(
      () => repo.getPendingActionsCount(
        const PendingActionsScope.me(asMaster: false),
        cancelToken: any(named: 'cancelToken'),
      ),
    );
  });

  test('.salon calls the repository with that scope', () async {
    const scope = PendingActionsScope.salon('s1');
    when(
      () => repo.getPendingActionsCount(
        scope,
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) async => 5);

    expect(await read(scope), 5);
    verify(
      () => repo.getPendingActionsCount(
        scope,
        cancelToken: any(named: 'cancelToken'),
      ),
    ).called(1);
  });

  test('repository failure is AsyncError, not 0 data', () async {
    const scope = PendingActionsScope.salon('s1');
    when(
      () => repo.getPendingActionsCount(
        scope,
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) async => throw const NetworkFailure());
    final sub = container.listen(
      pendingBookingActionsCountProvider(scope),
      (_, _) {},
    );

    await expectLater(read(scope), throwsA(isA<NetworkFailure>()));
    final value = sub.read();
    expect(value.hasError, isTrue);
    expect(value.hasValue, isFalse);
  });

  test('family keys are per scope: two salons do not share a count', () async {
    const a = PendingActionsScope.salon('a');
    const b = PendingActionsScope.salon('b');
    expect(a, isNot(b));
    expect(
      pendingBookingActionsCountProvider(a),
      isNot(pendingBookingActionsCountProvider(b)),
    );
    expect(
      pendingBookingActionsCountProvider(a),
      pendingBookingActionsCountProvider(const PendingActionsScope.salon('a')),
    );

    when(
      () => repo.getPendingActionsCount(
        a,
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) async => 1);
    when(
      () => repo.getPendingActionsCount(
        b,
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) async => 9);
    final subA = container.listen(
      pendingBookingActionsCountProvider(a),
      (_, _) {},
    );
    final subB = container.listen(
      pendingBookingActionsCountProvider(b),
      (_, _) {},
    );
    expect(await read(a), 1);
    expect(await read(b), 9);
    expect(subA.read().value, 1);
    expect(subB.read().value, 9);
  });

  test('disposing the provider cancels the in-flight request token', () async {
    const scope = PendingActionsScope.salon('s1');
    final Completer<int> pending = Completer<int>();
    when(
      () => repo.getPendingActionsCount(
        scope,
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) => pending.future);

    final sub = container.listen(
      pendingBookingActionsCountProvider(scope),
      (_, _) {},
    );
    final CancelToken token =
        verify(
              () => repo.getPendingActionsCount(
                scope,
                cancelToken: captureAny(named: 'cancelToken'),
              ),
            ).captured.single
            as CancelToken;
    expect(token.isCancelled, isFalse);

    sub.close();
    await Future<void>.delayed(Duration.zero); // autoDispose is scheduled
    expect(token.isCancelled, isTrue);
    pending.complete(1);
  });

  test('a cancelled request is swallowed, never an error state', () async {
    const scope = PendingActionsScope.salon('s1');
    when(
      () => repo.getPendingActionsCount(
        scope,
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((inv) async {
      final CancelToken t = inv.namedArguments[#cancelToken] as CancelToken;
      await Future<void>.delayed(Duration.zero);
      t.cancel();
      throw UnknownFailure(
        cause: DioException.requestCancelled(
          requestOptions: RequestOptions(path: '/x'),
          reason: null,
        ),
      );
    });

    final sub = container.listen(
      pendingBookingActionsCountProvider(scope),
      (_, _) {},
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(sub.read().hasError, isFalse);
    // The swallow path's DESIGNED placeholder: a cancelled token is only ever
    // reached via dispose/invalidate (no live reader sees it), so it settles
    // as 0 rather than an error. Pinned so a rethrow regresses visibly; the
    // "0 never reaches a live listener" half is the invalidate test below.
    expect(sub.read(), const AsyncData<int>(0));
  });

  test('invalidate with a mounted listener and in-flight request never '
      'shows a spurious 0 and ends at the new build\'s value', () async {
    const scope = PendingActionsScope.salon('s1');
    final List<Completer<int>> pending = <Completer<int>>[];
    when(
      () => repo.getPendingActionsCount(
        scope,
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((inv) {
      final Completer<int> c = Completer<int>();
      pending.add(c);
      final CancelToken t = inv.namedArguments[#cancelToken] as CancelToken;
      // Mirror the real repo: a cancelled token fails the request.
      unawaited(
        t.whenCancel.then((_) {
          if (!c.isCompleted) {
            c.completeError(
              UnknownFailure(
                cause: DioException.requestCancelled(
                  requestOptions: RequestOptions(path: '/x'),
                  reason: null,
                ),
              ),
            );
          }
        }),
      );
      return c.future;
    });

    final List<AsyncValue<int>> events = <AsyncValue<int>>[];
    final sub = container.listen(
      pendingBookingActionsCountProvider(scope),
      (_, next) => events.add(next),
      fireImmediately: true,
    );
    await Future<void>.delayed(Duration.zero);
    expect(pending, hasLength(1));

    container.invalidate(pendingBookingActionsCountProvider(scope));
    await Future<void>.delayed(Duration.zero);
    expect(pending, hasLength(2));
    pending[1].complete(5);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(sub.read(), const AsyncData<int>(5));
    expect(events.where((e) => e.hasError), isEmpty);
    expect(
      events.where((e) => e.hasValue && e.value == 0),
      isEmpty,
      reason: 'a cancelled superseded request must not leak AsyncData(0)',
    );
    expect(events.last, const AsyncData<int>(5));
  });

  // Phase 394 (24.7b) — app-resume refetch with a 15 s minimum gap.
  group('resume refetch', () {
    const scope = PendingActionsScope.me(asMaster: false);
    late DateTime now;
    late ProviderContainer c;
    late _MutableAuthNotifier auth;

    // Drives a background→foreground cycle on the test binding.
    void resume(WidgetTester tester) {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }

    // New fetches since the previous call (own counter: mocktail's verify
    // fails on zero matches).
    int fetches = 0;
    int fetchCount() {
      final int n = fetches;
      fetches = 0;
      return n;
    }

    setUp(() async {
      // future-date-ok: injected clock; nothing reads the wall clock here
      now = DateTime.utc(2026, 10, 9, 12);
      fetches = 0;
      auth = _MutableAuthNotifier(_as1);
      when(
        () => repo.getPendingActionsCount(
          scope,
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((_) async {
        fetches++;
        return 1;
      });
      c = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          bookingRepositoryProvider.overrideWithValue(repo),
          clockProvider.overrideWithValue(() => now),
          authProvider.overrideWith(() => auth),
        ],
      );
      addTearDown(c.dispose);
      await c.read(authProvider.future);
    });

    testWidgets('resume before 15 s does not refetch; at/after 15 s does', (
      tester,
    ) async {
      final sub = c.listen(
        pendingBookingActionsCountProvider(scope),
        (_, _) {},
      );
      addTearDown(sub.close);
      await tester.pump(Duration.zero);
      expect(fetchCount(), 1);

      now = now.add(const Duration(seconds: 14));
      resume(tester);
      await tester.pump(Duration.zero);
      expect(fetchCount(), 0, reason: '14 s < gap: no new fetch');

      now = now.add(const Duration(seconds: 1)); // exactly 15 s since build
      resume(tester);
      await tester.pump(Duration.zero);
      expect(fetchCount(), 1, reason: '15 s == gap: refetch');

      // The refetch rebuilt the provider, restarting the gap window.
      now = now.add(const Duration(seconds: 5));
      resume(tester);
      await tester.pump(Duration.zero);
      expect(fetchCount(), 0, reason: '5 s since the rebuild: throttled');
    });

    testWidgets('disposing removes the listener: no refetch after dispose', (
      tester,
    ) async {
      final sub = c.listen(
        pendingBookingActionsCountProvider(scope),
        (_, _) {},
      );
      await tester.pump(Duration.zero);
      expect(fetchCount(), 1);

      sub.close();
      await tester.pump(Duration.zero); // autoDispose
      now = now.add(const Duration(minutes: 5));
      resume(tester);
      await tester.pump(Duration.zero);
      expect(fetchCount(), 0);
    });

    testWidgets('logout: element rebuilds signed-out; resume makes no call', (
      tester,
    ) async {
      final sub = c.listen(
        pendingBookingActionsCountProvider(scope),
        (_, _) {},
      );
      addTearDown(sub.close);
      await tester.pump(Duration.zero);
      expect(fetchCount(), 1);

      auth.setSession(const AuthSession.unauthenticated());
      await tester.pump(Duration.zero);
      expect(fetchCount(), 0, reason: 'signed out: no request');
      expect(sub.read(), const AsyncData<int>(0));

      now = now.add(const Duration(minutes: 5));
      resume(tester);
      await tester.pump(Duration.zero);
      expect(fetchCount(), 0, reason: 'resume after logout must not fetch');
    });

    testWidgets('account switch: resume never uses the old scope\'s user', (
      tester,
    ) async {
      final sub = c.listen(
        pendingBookingActionsCountProvider(scope),
        (_, _) {},
      );
      addTearDown(sub.close);
      await tester.pump(Duration.zero);
      expect(fetchCount(), 1);

      auth.setSession(_as2);
      await tester.pump(Duration.zero);
      // The switch rebuilds the element for the NEW user exactly once.
      expect(fetchCount(), 1, reason: 'rebuild for the new identity');

      // Only the new build's listener is alive: one resume = one refetch,
      // not two (the old build's listener must be gone/guarded).
      now = now.add(const Duration(minutes: 5));
      resume(tester);
      await tester.pump(Duration.zero);
      expect(fetchCount(), 1, reason: 'single refetch, new user only');
    });
  });
}
