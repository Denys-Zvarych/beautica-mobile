// Phase 13.x (Variant A «Рейка + послуги») — widget tests for
// [SearchStaggeredReveal], the one-shot staggered fade-up entrance.
//
// The widget drives a single 1000 ms controller on mount; each child reveals on
// its own [Interval] slice (opacity 0→1 + an 18 px slide-up). The wrappers are
// UNCONDITIONAL — the same shape running and completed — so the revealed
// subtree's elements (and any `State` inside them) are never re-inflated.
//
// Coverage:
//   • the wrapped child is always present in the tree and reaches full opacity
//     after the 1000 ms entrance (revealed, not stuck hidden);
//   • mid-entrance the child is wrapped in a FadeTransition (animation machinery
//     is live while running);
//   • post-completion the FadeTransition wrapper is STILL there — the structural
//     stability that keeps the search field's focus + keyboard alive (defect F).
//     An earlier build short-circuited to the bare child here, which changed the
//     slot's widget runtimeType and unmounted the EditableText underneath.
//
// No providers / network. Hosted under a BARE Directionality (NOT MaterialApp)
// so the only FadeTransition / Transform in the tree is the one the reveal
// itself emits — a MaterialApp route wraps content in its own page-transition
// FadeTransitions, which would mask the reveal's own wrapper.

import 'package:beautica_mobile/features/discovery/presentation/widgets/staggered_reveal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps a single-child [SearchStaggeredReveal] over the full 0.0→1.0 interval
/// so the child is governed by the whole entrance.
Future<void> _pumpReveal(WidgetTester tester) {
  return tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: SearchStaggeredReveal(
        builder: (BuildContext context, SearchRevealFn reveal) {
          return reveal(
            start: 0.0,
            end: 1.0,
            child: const Text('revealed-child', key: Key('reveal_probe')),
          );
        },
      ),
    ),
  );
}

/// The effective opacity applied to the probe by the surrounding FadeTransition
/// (1.0 when no FadeTransition wraps it — i.e. post-completion bare child).
double _probeOpacity(WidgetTester tester) {
  final Finder fade = find.ancestor(
    of: find.byKey(const Key('reveal_probe')),
    matching: find.byType(FadeTransition),
  );
  if (fade.evaluate().isEmpty) return 1.0;
  return tester.widget<FadeTransition>(fade.first).opacity.value;
}

void main() {
  group('SearchStaggeredReveal', () {
    testWidgets('reveals its child to full opacity after the 1000ms entrance', (
      tester,
    ) async {
      await _pumpReveal(tester);

      // The child is in the tree from the first frame (it is never removed —
      // only faded/translated).
      expect(find.byKey(const Key('reveal_probe')), findsOneWidget);

      // Drive past the full entrance duration; the child must be fully visible.
      await tester.pumpAndSettle(const Duration(milliseconds: 1200));

      expect(find.byKey(const Key('reveal_probe')), findsOneWidget);
      expect(
        _probeOpacity(tester),
        1.0,
        reason: 'after the entrance completes the child must be fully visible',
      );
    });

    testWidgets('wraps the child in a FadeTransition while the entrance runs', (
      tester,
    ) async {
      await _pumpReveal(tester);
      // One frame in, well before the 1000 ms entrance finishes.
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.ancestor(
          of: find.byKey(const Key('reveal_probe')),
          matching: find.byType(FadeTransition),
        ),
        findsOneWidget,
        reason: 'mid-entrance the child is governed by a FadeTransition',
      );
    });

    testWidgets(
      'post-completion the wrapper shape is unchanged (element identity holds)',
      (tester) async {
        await _pumpReveal(tester);

        // Element identity of the revealed child, captured mid-entrance.
        final Element before = tester.element(
          find.byKey(const Key('reveal_probe')),
        );

        await tester.pumpAndSettle(const Duration(milliseconds: 1200));

        // FORCE A POST-COMPLETION PARENT REBUILD.
        //
        // Without this the test has a hole: `reveal(...)` is only ever invoked
        // while the controller is still running, so re-introducing JUST the
        // `if (_controller.isCompleted) return child;` early-return — without
        // the status listener that used to trigger the rebuild — would leave
        // this test green. In production the branch IS reached, because the real
        // search screen rebuilds constantly on provider changes. Re-pumping the
        // tree reproduces exactly that.
        await _pumpReveal(tester);
        await tester.pump();

        // Same wrappers, same element — the completed entrance must NOT swap the
        // slot's widget type, or every State beneath it (an EditableText, say)
        // would be torn down and rebuilt.
        expect(
          find.ancestor(
            of: find.byKey(const Key('reveal_probe')),
            matching: find.byType(FadeTransition),
          ),
          findsOneWidget,
          reason:
              'the wrapper shape must be identical running and completed — '
              'including on a rebuild that happens AFTER completion',
        );
        expect(
          identical(
            tester.element(find.byKey(const Key('reveal_probe'))),
            before,
          ),
          isTrue,
          reason: 'the revealed child element must survive the entrance',
        );
      },
    );
  });
}
