// `dismissOverlay` is idempotent: a second call for an overlay that is already
// popping must NOT pop the route beneath it.
//
// The bug (2026-10-15 sweep, "unverified" item): a dialog confirm handler that
// ran twice — two async continuations resuming after a double-tapped submit —
// called `dismissOverlay` twice. `Navigator.pop` pops the TOP present route,
// so the second call popped the screen under the dialog.
//
// Anti-vacuity: drop the `isCurrent` early-return in `dismissOverlay` and the
// host screen is popped (verified when written).
//
// No dependency (2026-10-15 perf LOW): for an overlay opened by
// `showDialogOnce`, `dismissOverlay` reads the route the helper already
// captured instead of `ModalRoute.of(context)` — the latter registered a
// route-status dependency from the callback and rebuilt the overlay content
// during its own exit animation. Anti-vacuity: make `dismissOverlay` use
// `ModalRoute.of(context)` alone and the build-count rows go RED (verified
// when written).

import 'dart:async';

import 'package:beautica_mobile/core/navigation/overlay_navigation.dart';
import 'package:beautica_mobile/core/navigation/single_flight.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('two dismissOverlay calls close the dialog only', (tester) async {
    final GlobalKey<NavigatorState> nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        home: const Scaffold(body: Text('root')),
      ),
    );
    final NavigatorState? navigator = nav.currentState;
    if (navigator == null) fail('navigator not mounted');
    unawaited(
      navigator.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(key: Key('host'), body: Text('host')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    late BuildContext dialogCtx;
    unawaited(
      showDialog<void>(
        context: tester.element(find.byKey(const Key('host'))),
        builder: (BuildContext ctx) {
          dialogCtx = ctx;
          return const AlertDialog(key: Key('dlg'), content: Text('d'));
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dlg')), findsOneWidget);

    dismissOverlay<void>(dialogCtx);
    dismissOverlay<void>(dialogCtx);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dlg')), findsNothing);
    expect(find.byKey(const Key('host')), findsOneWidget);
  });

  testWidgets('first dismissOverlay pops the top route even when the overlay '
      'is not the top route', (tester) async {
    // Pre-idempotency behaviour, kept: a push landing above the dialog (or
    // back pressed mid-request) — the first dismissal still pops the TOP
    // route. Anti-vacuity: an `!route.isCurrent` early-return leaves `above`
    // on screen (verified when written).
    final GlobalKey<NavigatorState> nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        home: const Scaffold(body: Text('root')),
      ),
    );
    final NavigatorState? navigator = nav.currentState;
    if (navigator == null) fail('navigator not mounted');

    late BuildContext dialogCtx;
    unawaited(
      showDialog<void>(
        context: tester.element(find.text('root')),
        builder: (BuildContext ctx) {
          dialogCtx = ctx;
          return const AlertDialog(key: Key('dlg'), content: Text('d'));
        },
      ),
    );
    await tester.pumpAndSettle();
    unawaited(
      navigator.push<void>(
        MaterialPageRoute<void>(
          builder: (_) =>
              const Scaffold(key: Key('above'), body: Text('above')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('above')), findsOneWidget);

    dismissOverlay<void>(dialogCtx);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('above')), findsNothing);
    expect(find.byKey(const Key('dlg')), findsOneWidget);
  });

  group('showDialogOnce overlays', () {
    late GlobalKey<NavigatorState> nav;

    // A NEW (non-const) MaterialApp each call: re-pumping it rebuilds the
    // Navigator, whose didUpdateWidget runs `changedExternalState` on every
    // route — what any app-level rebuild does (keyboard closing on dismiss →
    // MediaQuery change). A content element that subscribed to the overlay's
    // route status is then rebuilt mid-exit, because its `isCurrent` flipped.
    Widget app() => MaterialApp(
      navigatorKey: nav,
      home: const Scaffold(body: Text('root')),
    );

    Future<void> pumpHost(WidgetTester tester) async {
      nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(app());
      final NavigatorState? navigator = nav.currentState;
      if (navigator == null) fail('navigator not mounted');
      unawaited(
        navigator.push<void>(
          MaterialPageRoute<void>(
            builder: (_) =>
                const Scaffold(key: Key('host'), body: Text('host')),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('builder context: two dismissOverlay calls close the dialog '
        'only, and the dialog content is never rebuilt', (tester) async {
      await pumpHost(tester);
      int builds = 0;
      late BuildContext dialogCtx;
      unawaited(
        showDialogOnce<void>(
          context: tester.element(find.byKey(const Key('host'))),
          builder: (BuildContext ctx) {
            builds++;
            dialogCtx = ctx;
            return const AlertDialog(key: Key('dlg'), content: Text('d'));
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(builds, 1);
      final ModalRoute<Object?>? route = ModalRoute.of(
        tester.element(find.byKey(const Key('dlg'))),
      );
      if (route == null) fail('dialog route not found');

      dismissOverlay<void>(dialogCtx);
      dismissOverlay<void>(dialogCtx);
      await tester.pump();
      // Republish the route's status mid-exit WITHOUT forcing its page to
      // rebuild (an app-level rebuild would — `changedExternalState` re-runs
      // `buildPage`, which re-invokes the builder regardless). Only a context
      // subscribed to the route's status rebuilds here: `isCurrent` flipped.
      route.changedInternalState();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('dlg')), findsNothing);
      expect(find.byKey(const Key('host')), findsOneWidget);
      expect(builds, 1, reason: 'dismissal must not subscribe the content');
    });

    testWidgets('descendant context: two dismissOverlay calls close the '
        'dialog only, and the caller is never rebuilt', (tester) async {
      await pumpHost(tester);
      _CountingContent.builds = 0;
      unawaited(
        showDialogOnce<void>(
          context: tester.element(find.byKey(const Key('host'))),
          builder: (_) => const _CountingContent(),
        ),
      );
      await tester.pumpAndSettle();
      expect(_CountingContent.builds, 1);

      final BuildContext inner = tester.element(find.byType(_CountingContent));
      dismissOverlay<void>(inner);
      dismissOverlay<void>(inner);
      await tester.pump();
      await tester.pumpWidget(app()); // app-level rebuild during the exit
      await tester.pumpAndSettle();

      expect(find.byType(_CountingContent), findsNothing);
      expect(find.byKey(const Key('host')), findsOneWidget);
      expect(_CountingContent.builds, 1);
    });
  });
}

class _CountingContent extends StatelessWidget {
  const _CountingContent();

  static int builds = 0;

  @override
  Widget build(BuildContext context) {
    builds++;
    return const AlertDialog(content: Text('d'));
  }
}
