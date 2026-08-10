// Regression + behavior pin for `AppHarness.tapVisible` — see
// `integration_test/support/app_harness.dart`'s doc comment on `tapVisible`
// and the bug it was introduced to fix (`salon_service_filter_flow_test.dart`'s
// below-the-fold service-row tap, diagnosed 2026-08-10: `RenderClipRect`
// rejects an out-of-box point WITHOUT descending into children, so a plain
// `tester.tap` on a below-the-fold row silently lands on whatever IS
// hit-testable behind it instead of throwing).
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b)
// -----------------------------------------
// `salon_service_filter_flow_test.dart` IS the reproduction for the specific
// bug — reverting the fix there reproduces the original hit-test failure
// exactly, and the dev already mutation-proved that. A second copy of that
// same reproduction would be redundant, not additional coverage.
//
// What that flow does NOT — and structurally cannot — exercise is
// `tapVisible`'s OWN failure mode: a widget that never becomes hit-testable
// for a genuine reason must fail with a clear, bounded `TestFailure`, never
// hang and never silently mis-tap. `tapVisible` is shared infrastructure now
// used across a growing number of E2E flows (see its call sites), so pinning
// both its happy path and its clean-timeout path at the widget tier — fast,
// no full app boot, no FakeBackend — earns its place.
//
// MUTATION-VERIFIED (manual, not committed): replacing the
// `AppHarness.tapVisible` call in the first test below with a plain
// `tester.tap(target, warnIfMissed: false)` turns `tapCount` red (stays 0 —
// the tap lands on the SingleChildScrollView's viewport, not the button),
// confirming the scroll-then-hit-test gate is load-bearing and this test is
// not a tautology.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/app_harness.dart';

void main() {
  testWidgets(
    'tapVisible scrolls a below-the-fold button into view and taps it — a '
    'plain tester.tap on the same finder would silently miss',
    (tester) async {
      int tapCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: <Widget>[
                  // Pushes the target well past the 800x600 flutter_test
                  // default surface — the same "cover + hero + tab bar +
                  // bottom shelf" mechanics that put the real service row at
                  // y≈494-547 in the bug this helper fixes.
                  const SizedBox(height: 900),
                  ElevatedButton(
                    key: const Key('target-button'),
                    onPressed: () => tapCount++,
                    child: const Text('target'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      final Finder target = find.byKey(const Key('target-button'));
      // EXISTENCE: the button is mounted even though it is off-screen — this
      // is exactly the `findsOneWidget` that passed on the original bug.
      expect(target, findsOneWidget);
      expect(
        target.hitTestable().evaluate(),
        isEmpty,
        reason: 'must start below the fold, or this test proves nothing',
      );

      await AppHarness.tapVisible(tester, target);

      expect(
        tapCount,
        1,
        reason:
            'tapVisible must scroll the button into view AND register the '
            'tap, not merely resolve the finder',
      );
    },
  );

  testWidgets(
    'tapVisible fails with a clear TestFailure — not a hang — when the '
    'target never becomes hit-testable',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IgnorePointer(
              // RenderIgnorePointer always fails hitTest while still being
              // built/laid out — the same family of render object named in
              // the original diagnosis (`RenderAbsorbPointer`/
              // `RenderOffstage`). Deliberately NOT `Offstage`: the default
              // `find.byKey` finder EXCLUDES offstage subtrees entirely
              // (`findsOneWidget` would report 0, not 1), which would not
              // reproduce "exists in the tree but never hit-testable" — the
              // actual shape of the production bug (a `ClipRect`-clipped
              // row still fully mounted and still findable by key).
              ignoring: true,
              child: ElevatedButton(
                key: const Key('unreachable-button'),
                onPressed: () {},
                child: const Text('unreachable'),
              ),
            ),
          ),
        ),
      );

      final Finder target = find.byKey(const Key('unreachable-button'));
      expect(target, findsOneWidget); // exists...
      expect(
        target.hitTestable().evaluate(),
        isEmpty,
      ); // ...but never hit-testable, and nothing will ever make it so.

      Object? thrown;
      try {
        await AppHarness.tapVisible(
          tester,
          target,
          timeout: const Duration(milliseconds: 200),
        );
      } catch (e) {
        thrown = e;
      }

      expect(
        thrown,
        isA<TestFailure>(),
        reason:
            'an unreachable target must fail loudly and promptly, not hang '
            'or fall through to a silent mis-tap',
      );
      expect(thrown.toString(), contains('timed out'));
    },
  );
}
