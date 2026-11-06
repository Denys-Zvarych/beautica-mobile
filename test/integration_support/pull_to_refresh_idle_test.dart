// Guard for `integration_test/support/pull_to_refresh.dart`.
//
// `RefreshIndicator` silently DROPS a drag that lands while the previous
// refresh cycle is still open. A helper that returns as soon as the request is
// counted (the old passport `_pullToRefresh`) returns inside that cycle, so the
// next pull is lost. With `disableAnimations` (the emulator, animation scale 0)
// nothing drains the cycle for free, so this reproduces the device-only
// failure headlessly: the cycle stays open until a timer fires.
//
// Proves: with animations disabled, a second pull issued right after the first
// still arms the RefreshIndicator and is counted (the helper drains the open
// cycle before and after each pull).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/pull_to_refresh.dart';

void main() {
  testWidgets(
    'consecutive pulls are not dropped while a refresh cycle is still open',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAllTestValues);

      int calls = 0;
      Completer<void>? open;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RefreshIndicator(
              onRefresh: () {
                calls++;
                final Completer<void> c = open = Completer<void>();
                // The cycle stays open until the test-held completer is
                // completed — by a timer, so only elapsed pumping closes it.
                Timer(const Duration(milliseconds: 600), c.complete);
                return c.future;
              },
              child: ListView(
                children: const <Widget>[
                  SizedBox(height: 100, child: Text('a')),
                ],
              ),
            ),
          ),
        ),
      );

      await pullToRefresh(tester, () => calls);
      expect(calls, 1);
      expect(open!.isCompleted, isTrue, reason: 'helper must return idle');

      await pullToRefresh(tester, () => calls);
      expect(calls, 2, reason: 'second pull must not be silently dropped');
      expect(find.byType(RefreshProgressIndicator), findsNothing);
    },
  );
}
