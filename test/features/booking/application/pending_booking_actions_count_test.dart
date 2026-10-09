// Phase 393 (24.7a) — `pendingBookingActionsCountProvider`.
//
// Pins: each scope variant reaches the repository with that exact scope,
// a repository failure surfaces as AsyncError (never a fake `0`), and family
// members are keyed per scope (two salons never share a count).

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/booking/application/pending_booking_actions_count.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockBookingRepository extends Mock implements BookingRepository {}

void main() {
  late _MockBookingRepository repo;
  late ProviderContainer container;

  setUpAll(() {
    registerFallbackValue(const PendingActionsScope.me(asMaster: false));
  });

  setUp(() {
    repo = _MockBookingRepository();
    container = ProviderContainer(
      // Riverpod 3 retries a failing provider; a test asserting the error
      // state must opt out or it waits out the backoff.
      retry: (_, _) => null,
      overrides: [bookingRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
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
}
