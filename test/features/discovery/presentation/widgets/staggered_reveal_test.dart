// Phase 13.x (Variant A «Рейка + послуги») — widget tests for
// [SearchStaggeredReveal], the one-shot staggered fade-up entrance.
//
// The widget drives a single 1000 ms controller on mount; each child reveals on
// its own [Interval] slice (opacity 0→1 + an 18 px slide-up). Once the entrance
// completes, the gate flips and `reveal(...)` returns the BARE child with no
// animation wrappers — so steady-state rebuilds allocate nothing.
//
// Coverage:
//   • the wrapped child is always present in the tree and reaches full opacity
//     after the 1000 ms entrance (revealed, not stuck hidden);
//   • mid-entrance the child is wrapped in a FadeTransition (animation machinery
//     is live while running);
//   • post-completion `reveal` returns the bare child — NO FadeTransition
//     wrapper remains (the gate short-circuit).
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
      'post-completion the gate returns the bare child (no FadeTransition)',
      (tester) async {
        await _pumpReveal(tester);
        await tester.pumpAndSettle(const Duration(milliseconds: 1200));

        // The status listener flips the gate on completion + setState; the next
        // build returns the child directly with no animation wrappers.
        expect(
          find.ancestor(
            of: find.byKey(const Key('reveal_probe')),
            matching: find.byType(FadeTransition),
          ),
          findsNothing,
          reason: 'the completed gate must short-circuit to the bare child',
        );
      },
    );
  });
}
