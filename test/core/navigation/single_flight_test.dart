// Unit tests for the single-flight navigation helper
// (lib/core/navigation/single_flight.dart).
//
// Every multi-tap case taps WITHOUT pumping between taps: a pump lets the
// after-rebuild disable (or the pushed route covering the button) kick in and
// hides the bug the helper exists to close.

import 'dart:async';

import 'package:beautica_mobile/core/navigation/single_flight.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _Home extends StatefulWidget {
  const _Home();

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: <Widget>[
          // Stateless caller: the lock is keyed on the Builder's element.
          Builder(
            builder: (BuildContext ctx) => TextButton(
              key: const Key('open-b'),
              onPressed: () => ctx.pushOnce<void>('/b'),
              child: const Text('open'),
            ),
          ),
          Builder(
            builder: (BuildContext ctx) => TextButton(
              key: const Key('open-dialog'),
              onPressed: () => showDialogOnce<void>(
                context: ctx,
                builder: (_) => const AlertDialog(
                  key: Key('the-dialog'),
                  content: Text('d'),
                ),
              ),
              child: const Text('dialog'),
            ),
          ),
          Builder(
            builder: (BuildContext ctx) => TextButton(
              key: const Key('open-sheet'),
              onPressed: () => showModalBottomSheetOnce<void>(
                context: ctx,
                builder: (_) =>
                    const SizedBox(key: Key('the-sheet'), height: 100),
              ),
              child: const Text('sheet'),
            ),
          ),
        ],
      ),
    );
  }
}

/// A const caller: go_router re-running its page builder hands back the SAME
/// instance, so any rebuild it records came from a dependency it registered.
class _CountingCaller extends StatelessWidget {
  const _CountingCaller();

  static int builds = 0;

  @override
  Widget build(BuildContext context) {
    builds++;
    return const SizedBox();
  }
}

class _B extends StatelessWidget {
  const _B();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(key: Key('screen-b'), body: Text('B'));
}

GoRouter _router() => GoRouter(
  initialLocation: '/a',
  routes: <RouteBase>[
    GoRoute(path: '/a', builder: (_, _) => const _Home()),
    GoRoute(path: '/b', builder: (_, _) => const _B()),
  ],
);

Future<GoRouter> _pumpRouter(WidgetTester tester) async {
  final GoRouter router = _router();
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
  return router;
}

/// Whether an imperative (pushed) match for [location] is in the stack.
bool _hasPushed(GoRouter router, String location) =>
    router.routerDelegate.currentConfiguration.matches.any(
      (RouteMatchBase m) =>
          m is ImperativeRouteMatch && m.matchedLocation == location,
    );

Finder _bScreens() => find.byKey(const Key('screen-b'), skipOffstage: false);

/// Pins `singleFlightNow` to a hand-stepped clock for one test; returns the
/// stepper. Restored on tear-down.
void Function(Duration) _pinFlightClock() {
  final DateTime Function() original = singleFlightNow;
  addTearDown(() => singleFlightNow = original);
  DateTime now = DateTime.utc(2026, 10, 15, 12);
  singleFlightNow = () => now;
  return (Duration by) => now = now.add(by);
}

void main() {
  group('pushOnce', () {
    testWidgets('3 same-frame taps push exactly 1 route', (tester) async {
      await _pumpRouter(tester);

      await tester.tap(find.byKey(const Key('open-b')));
      await tester.tap(find.byKey(const Key('open-b')));
      await tester.tap(find.byKey(const Key('open-b')));
      await tester.pumpAndSettle();

      expect(_bScreens(), findsOneWidget);
    });

    testWidgets('re-opens after the route is popped', (tester) async {
      final GoRouter router = await _pumpRouter(tester);

      await tester.tap(find.byKey(const Key('open-b')));
      await tester.pumpAndSettle();
      expect(_bScreens(), findsOneWidget);

      router.pop();
      await tester.pumpAndSettle();
      expect(_bScreens(), findsNothing);

      await tester.tap(find.byKey(const Key('open-b')));
      await tester.tap(find.byKey(const Key('open-b')));
      await tester.pumpAndSettle();
      expect(_bScreens(), findsOneWidget);
    });

    testWidgets(
      'stack replacement (go) that never completes the push future does not '
      'leave the caller locked',
      (tester) async {
        final GoRouter router = await _pumpRouter(tester);
        final State<_Home> before = tester.state(find.byType(_Home));

        await tester.tap(find.byKey(const Key('open-b')));
        await tester.pumpAndSettle();
        expect(_bScreens(), findsOneWidget);

        // `go` drops the imperative /b match without completing its future.
        router.go('/a');
        await tester.pumpAndSettle();
        expect(_bScreens(), findsNothing);
        // Same page key: the caller element SURVIVED the go — the exact
        // shape that would otherwise hold the lock forever.
        expect(tester.state(find.byType(_Home)), same(before));

        await tester.tap(find.byKey(const Key('open-b')));
        await tester.tap(find.byKey(const Key('open-b')));
        await tester.pumpAndSettle();
        expect(_bScreens(), findsOneWidget);
      },
    );

    testWidgets('pop + push from the SAME element in one synchronous '
        'handler is not dropped', (tester) async {
      // go_router removes the popped match synchronously; its push future
      // completes only in a later microtask. Anti-vacuity: make `isStale`
      // return false and the second push is dropped (verified when written).
      final GoRouter router = await _pumpRouter(tester);
      final BuildContext ctx = tester.element(find.byKey(const Key('open-b')));
      unawaited(ctx.pushOnce<void>('/b'));
      await tester.pumpAndSettle();
      expect(_bScreens(), findsOneWidget);

      router.pop();
      unawaited(ctx.pushOnce<void>('/b'));
      await tester.pumpAndSettle();

      expect(_bScreens(), findsOneWidget);
    });

    testWidgets('a pushed screen can push from its own element', (
      tester,
    ) async {
      final GoRouter router = GoRouter(
        initialLocation: '/a',
        routes: <RouteBase>[
          GoRoute(path: '/a', builder: (_, _) => const _Home()),
          GoRoute(
            path: '/b',
            builder: (_, _) => Builder(
              builder: (BuildContext ctx) => Scaffold(
                key: const Key('screen-b'),
                body: TextButton(
                  key: const Key('open-c'),
                  onPressed: () => ctx.pushOnce<void>('/c'),
                  child: const Text('c'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/c',
            builder: (_, _) =>
                const Scaffold(key: Key('screen-c'), body: Text('C')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('open-b')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-c')));
      await tester.tap(find.byKey(const Key('open-c')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('screen-c'), skipOffstage: false),
        findsOneWidget,
      );
    });

    testWidgets('a concurrent push from ANOTHER element is never claimed: '
        'that route popping leaves this lock held', (tester) async {
      // Same frame: caller B pushes /b (an async redirect, so it has not
      // landed when B's probe first polls) and caller C pushes /c, which
      // lands at once. "Claim the first new match" made B's probe adopt
      // C's /c match; /c popping then marked B's lock stale although B's
      // own push was never seen to land or finish — B's re-tap went through.
      // Anti-vacuity: make `_isMine` claim any new match
      // (`return !_before.contains(m.completer);`, the old rule) and this
      // goes RED (verified when written).
      final GoRouter router = GoRouter(
        initialLocation: '/a',
        routes: <RouteBase>[
          GoRoute(
            path: '/a',
            builder: (_, _) => const Scaffold(
              body: Column(
                children: <Widget>[
                  SizedBox(key: Key('caller-b')),
                  SizedBox(key: Key('caller-c')),
                ],
              ),
            ),
          ),
          GoRoute(
            path: '/b',
            redirect: (_, _) async {
              await Future<void>.delayed(const Duration(milliseconds: 50));
              return null;
            },
            builder: (_, _) => const _B(),
          ),
          GoRoute(
            path: '/c',
            builder: (_, _) =>
                const Scaffold(key: Key('screen-c'), body: Text('C')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      final BuildContext callerB = tester.element(
        find.byKey(const Key('caller-b')),
      );
      final BuildContext callerC = tester.element(
        find.byKey(const Key('caller-c')),
      );

      unawaited(callerB.pushOnce<void>('/b'));
      unawaited(callerC.pushOnce<void>('/c'));
      await tester.pump(); // both probes poll: only /c is in the stack
      expect(_hasPushed(router, '/c'), isTrue);
      expect(_hasPushed(router, '/b'), isFalse);
      // fixed-wait-ok: crosses /b's 50 ms redirect delay (a TTL crossing) so
      // its timer is not left pending; pumpAndSettle is unusable here — B's
      // unlanded push keeps frames coming up to its landing bound, and
      // settling would time it out, erasing the state under test.
      await tester.pump(const Duration(milliseconds: 100));

      router.pop(); // /c — C's route, not B's
      await tester.pump();
      expect(_hasPushed(router, '/c'), isFalse);

      expect(isFlightOpen(callerB), isTrue);
      expect(isFlightOpen(callerC), isFalse);
    });

    testWidgets('a redirected push is still identified as this push (lock '
        'held past the landing bound)', (tester) async {
      // The probe identifies its match by the completer go_router created
      // for THIS push, which survives a redirect; a location comparison
      // would never match (/r landed as /b), time out, and let a duplicate
      // through. Anti-vacuity: stop `track` from recording the completer and
      // this goes RED with 2 /b screens (verified when written).
      final GoRouter router = GoRouter(
        initialLocation: '/a',
        routes: <RouteBase>[
          GoRoute(path: '/a', builder: (_, _) => const _Home()),
          GoRoute(path: '/b', builder: (_, _) => const _B()),
          GoRoute(path: '/r', redirect: (_, _) => '/b'),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      final BuildContext ctx = tester.element(find.byKey(const Key('open-b')));

      final void Function(Duration) advance = _pinFlightClock();

      unawaited(ctx.pushOnce<void>('/r'));
      await tester.pumpAndSettle();
      expect(_bScreens(), findsOneWidget);
      advance(const Duration(seconds: 10));

      expect(isFlightOpen(ctx), isTrue);
      unawaited(ctx.pushOnce<void>('/r'));
      await tester.pumpAndSettle();
      expect(_bScreens(), findsOneWidget);
    });

    testWidgets('a push that never lands and never completes does not lock '
        'the element for its lifetime', (tester) async {
      // Anti-vacuity: drop the deadline branch of `_Flight.isStale` and the
      // lock stays held — the re-tap is dropped (verified when written).
      final Completer<String?> never = Completer<String?>();
      final GoRouter router = GoRouter(
        initialLocation: '/a',
        routes: <RouteBase>[
          GoRoute(path: '/a', builder: (_, _) => const _Home()),
          GoRoute(path: '/b', builder: (_, _) => const _B()),
          GoRoute(
            path: '/never',
            redirect: (_, _) => never.future,
            builder: (_, _) => const SizedBox(),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      final BuildContext ctx = tester.element(find.byKey(const Key('open-b')));

      final void Function(Duration) advance = _pinFlightClock();

      unawaited(ctx.pushOnce<void>('/never'));
      await tester.pump();
      expect(isFlightOpen(ctx), isTrue, reason: 'still landing: held');

      // Frames alone never release it: the deadline is wall-clock.
      for (int i = 0; i < 5; i++) {
        await tester.pump();
      }
      advance(const Duration(milliseconds: 1900));
      expect(isFlightOpen(ctx), isTrue, reason: 'before the deadline: held');

      advance(const Duration(milliseconds: 200));
      expect(isFlightOpen(ctx), isFalse);

      unawaited(ctx.pushOnce<void>('/b'));
      await tester.pumpAndSettle();
      expect(_bScreens(), findsOneWidget);
    });
  });

  group('frame cost', () {
    testWidgets('an unsettled flight requests no frames', (tester) async {
      // A push whose route never lands must not keep the engine rendering
      // (the old per-frame poll forced ~120 back-to-back frames).
      // Anti-vacuity: re-add `SchedulerBinding.instance.scheduleFrame()` to
      // the flight's entry or its post-frame callback and this goes RED.
      final Completer<String?> never = Completer<String?>();
      final GoRouter router = GoRouter(
        initialLocation: '/a',
        routes: <RouteBase>[
          GoRoute(path: '/a', builder: (_, _) => const _Home()),
          GoRoute(
            path: '/never',
            redirect: (_, _) => never.future,
            builder: (_, _) => const SizedBox(),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      final BuildContext ctx = tester.element(find.byKey(const Key('open-b')));

      unawaited(ctx.pushOnce<void>('/never'));
      expect(isFlightOpen(ctx), isTrue);
      expect(
        SchedulerBinding.instance.hasScheduledFrame,
        isFalse,
        reason: 'entry must not request a frame',
      );

      // The test binding only draws when a frame is scheduled: force one so
      // the flight's post-frame claim actually runs.
      SchedulerBinding.instance.scheduleFrame();
      await tester.pump();
      expect(isFlightOpen(ctx), isTrue);
      expect(
        SchedulerBinding.instance.hasScheduledFrame,
        isFalse,
        reason: 'the post-frame claim must not request another frame',
      );
    });
  });

  group('caller dependencies', () {
    // The helper must NOT register a route-status dependency on the caller
    // (e.g. via `ModalRoute.of(callerContext)`): that rebuilds the caller on
    // every push/pop above it — the cost the portfolio rail's perf pins
    // forbid. Anti-vacuity: read `ModalRoute.of(context)` inside `_runOnce`
    // and both rows go RED (verified when written).
    testWidgets('opening + closing a guarded dialog and a pushed route does '
        'not rebuild the caller', (tester) async {
      _CountingCaller.builds = 0;
      final GoRouter router = GoRouter(
        initialLocation: '/a',
        routes: <RouteBase>[
          GoRoute(
            path: '/a',
            builder: (_, _) => const Scaffold(body: _CountingCaller()),
          ),
          GoRoute(path: '/b', builder: (_, _) => const _B()),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      final int baseline = _CountingCaller.builds;
      final BuildContext caller = tester.element(find.byType(_CountingCaller));

      unawaited(
        showDialogOnce<void>(
          context: caller,
          builder: (_) => const AlertDialog(content: Text('d')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      unawaited(caller.pushOnce<void>('/b'));
      await tester.pumpAndSettle();
      router.pop();
      await tester.pumpAndSettle();

      expect(_CountingCaller.builds, baseline);
    });
  });

  group('runOnce', () {
    testWidgets('drops a second call while the first is open and releases '
        'when it completes', (tester) async {
      await tester.pumpWidget(const SizedBox());
      final BuildContext ctx = tester.element(find.byType(SizedBox));
      final Completer<int> first = Completer<int>();
      int calls = 0;

      final Future<int?> a = runOnce<int>(ctx, () {
        calls++;
        return first.future;
      });
      final Future<int?> b = runOnce<int>(ctx, () async {
        calls++;
        return 2;
      });
      expect(isFlightOpen(ctx), isTrue);
      expect(await b, isNull);

      first.complete(1);
      expect(await a, 1);
      expect(isFlightOpen(ctx), isFalse);
      expect(calls, 1);

      expect(await runOnce<int>(ctx, () async => 3), 3);
    });

    testWidgets('two different elements do not share a lock', (tester) async {
      await tester.pumpWidget(
        const Row(
          textDirection: TextDirection.ltr,
          children: <Widget>[
            SizedBox(key: Key('x')),
            SizedBox(key: Key('y')),
          ],
        ),
      );
      final BuildContext x = tester.element(find.byKey(const Key('x')));
      final BuildContext y = tester.element(find.byKey(const Key('y')));
      final Completer<void> hold = Completer<void>();

      unawaited(runOnce<void>(x, () => hold.future));
      expect(await runOnce<int>(y, () async => 7), 7);
      hold.complete();
    });

    testWidgets('a nested guarded call from inside the action runs '
        '(re-entrancy)', (tester) async {
      await tester.pumpWidget(const SizedBox());
      final BuildContext ctx = tester.element(find.byType(SizedBox));

      final int? out = await runOnce<int>(ctx, () async {
        await Future<void>.value();
        return runOnce<int>(ctx, () async => 42);
      });

      expect(out, 42);
    });

    testWidgets('an unmounted element: no-op call, and a pending flight does '
        'not leak into the next element', (tester) async {
      await tester.pumpWidget(
        const Row(
          textDirection: TextDirection.ltr,
          children: <Widget>[
            SizedBox(key: Key('gone')),
            SizedBox(key: Key('idle')),
          ],
        ),
      );
      final BuildContext stale = tester.element(find.byKey(const Key('gone')));
      final BuildContext idle = tester.element(find.byKey(const Key('idle')));
      final Completer<void> hold = Completer<void>();
      unawaited(runOnce<void>(stale, () => hold.future));

      await tester.pumpWidget(const SizedBox(key: Key('fresh')));
      expect(stale.mounted, isFalse);

      int calls = 0;
      expect(
        await runOnce<int>(stale, () async {
          calls++;
          return 1;
        }),
        isNull,
      );
      expect(calls, 0);
      // An unmounted element that never flew: still a no-op.
      expect(
        await runOnce<int>(idle, () async {
          calls++;
          return 1;
        }),
        isNull,
      );
      expect(calls, 0);

      final BuildContext fresh = tester.element(find.byKey(const Key('fresh')));
      expect(isFlightOpen(fresh), isFalse);
      expect(await runOnce<int>(fresh, () async => 1), 1);

      // Completing the orphaned flight after unmount must not throw.
      hold.complete();
      await tester.pump();
    });

    testWidgets('a multi-step flow (dialog, then a write) keeps its lock '
        'after the dialog closes', (tester) async {
      await _pumpRouter(tester);
      final BuildContext ctx = tester.element(
        find.byKey(const Key('open-dialog')),
      );
      final Completer<void> write = Completer<void>();
      int writes = 0;
      Future<void> flow() => runOnce<void>(ctx, () async {
        await showDialog<void>(
          context: ctx,
          builder: (_) =>
              const AlertDialog(key: Key('confirm'), content: Text('ok?')),
        );
        writes++;
        await write.future;
      });

      unawaited(flow());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('confirm')), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(writes, 1);

      // The caller's route is current again while the write is in flight —
      // that must NOT read as a stale lock for a generic flow.
      unawaited(flow());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('confirm')), findsNothing);
      expect(writes, 1);

      write.complete();
      await tester.pumpAndSettle();
      expect(isFlightOpen(ctx), isFalse);
    });

    testWidgets('the lock is released when the action throws', (tester) async {
      await tester.pumpWidget(const SizedBox());
      final BuildContext ctx = tester.element(find.byType(SizedBox));

      await expectLater(
        runOnce<void>(ctx, () async => throw StateError('boom')),
        throwsStateError,
      );
      expect(isFlightOpen(ctx), isFalse);
      expect(await runOnce<int>(ctx, () async => 5), 5);
    });
  });

  group('showDialogOnce / showModalBottomSheetOnce', () {
    // Programmatic calls, not taps: a SYNCHRONOUS `showDialog` from a tap
    // handler is already shielded by Navigator's own pointer absorber (it
    // flips `RenderAbsorbPointer.absorbing` on push), so same-frame taps on
    // such a button never reach the handler twice. The exposure is a show
    // call that runs after an `await` in the handler — three such
    // continuations landing in one frame is what these calls reproduce.
    testWidgets('3 same-frame calls open exactly 1 dialog, and it re-opens '
        'after dismissal', (tester) async {
      await _pumpRouter(tester);
      final BuildContext ctx = tester.element(
        find.byKey(const Key('open-dialog')),
      );
      Future<void> open() => showDialogOnce<void>(
        context: ctx,
        builder: (_) =>
            const AlertDialog(key: Key('the-dialog'), content: Text('d')),
      );

      unawaited(open());
      unawaited(open());
      unawaited(open());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('the-dialog')), findsOneWidget);

      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('the-dialog')), findsNothing);

      unawaited(open());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('the-dialog')), findsOneWidget);
    });

    testWidgets(
      'a dialog removed with the page under it does not leave the caller '
      'locked',
      (tester) async {
        // Declarative pages: the caller lives on page 1; the dialog attaches
        // to page 2 (the top page). Dropping page 2 removes the pageless dialog
        // while the caller survives. Pins the platform fact the helper relies
        // on instead of a probe: Flutter completes the removed dialog's
        // future, which releases the lock.
        final ValueNotifier<bool> twoPages = ValueNotifier<bool>(true);
        addTearDown(twoPages.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: ValueListenableBuilder<bool>(
              valueListenable: twoPages,
              builder: (_, bool both, _) => Navigator(
                pages: <Page<void>>[
                  const MaterialPage<void>(
                    key: ValueKey<String>('p1'),
                    child: Scaffold(body: SizedBox(key: Key('caller'))),
                  ),
                  if (both)
                    const MaterialPage<void>(
                      key: ValueKey<String>('p2'),
                      child: Scaffold(body: Text('p2')),
                    ),
                ],
                onDidRemovePage: (_) {},
              ),
            ),
          ),
        );
        final BuildContext caller = tester.element(
          find.byKey(const Key('caller'), skipOffstage: false),
        );
        Future<void> open() => showDialogOnce<void>(
          context: caller,
          useRootNavigator: false,
          builder: (_) =>
              const AlertDialog(key: Key('the-dialog'), content: Text('d')),
        );

        unawaited(open());
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('the-dialog')), findsOneWidget);

        twoPages.value = false;
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('the-dialog')), findsNothing);

        unawaited(open());
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('the-dialog')), findsOneWidget);
      },
    );

    testWidgets('dismiss + reopen on the SAME context in one synchronous '
        'handler is not dropped', (tester) async {
      // The popped dialog's future completes only in a later microtask; the
      // overlay probe sees the route inactive at once and lets the reopen
      // through. Anti-vacuity: make `_OverlayProbe.present` return null and
      // the reopen is dropped (verified when written).
      await _pumpRouter(tester);
      final BuildContext ctx = tester.element(
        find.byKey(const Key('open-dialog')),
      );
      late BuildContext first;
      unawaited(
        showDialogOnce<void>(
          context: ctx,
          builder: (BuildContext d) {
            first = d;
            return const AlertDialog(key: Key('first'), content: Text('1'));
          },
        ),
      );
      await tester.pumpAndSettle();

      Navigator.of(first).pop();
      unawaited(
        showDialogOnce<void>(
          context: ctx,
          builder: (_) =>
              const AlertDialog(key: Key('second'), content: Text('2')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('first')), findsNothing);
      expect(find.byKey(const Key('second')), findsOneWidget);
    });

    testWidgets('3 same-frame calls open exactly 1 sheet', (tester) async {
      await _pumpRouter(tester);
      final BuildContext ctx = tester.element(
        find.byKey(const Key('open-sheet')),
      );
      Future<void> open() => showModalBottomSheetOnce<void>(
        context: ctx,
        builder: (_) => const SizedBox(key: Key('the-sheet'), height: 100),
      );

      unawaited(open());
      unawaited(open());
      unawaited(open());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('the-sheet')), findsOneWidget);
    });
  });
}
