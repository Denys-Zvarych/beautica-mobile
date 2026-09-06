// mobile-qa re-audit (cycle 2, 2026-09-05) — the pin `RevealTransition` was
// CREATED FOR and shipped without.
//
// WHAT WAS UNPINNED
// ---------------------------------------------------------------------------
// Phase 21.16 promoted six hand-copied `_reveal(fade, slide, child)` helpers
// into `lib/core/widgets/reveal_transition.dart`, and in doing so fixed four of
// them: the `RepaintBoundary` had been sitting ABOVE the two transitions, where
// it isolates nothing. The widget was deliberately made a CLASS rather than a
// top-level function so the corrected placement would be assertable — its own
// header (`reveal_transition.dart:38-45`) records that "every candidate
// assertion stayed green with the boundary hoisted" over the bare
// `FadeTransition` / `SlideTransition` / `RepaintBoundary` types, and that
// `find.byType(RevealTransition)` plus a per-call-site [Key] is what makes a
// reveal isolable.
//
// That assertion was never written. Measured before this file existed
// (mobile-build-verifier, 2026-09-05): `RevealTransition` appeared in NO test,
// none of the 27 keys appeared in any test, and hoisting the boundary back
// outside `SlideTransition` left all 1845 tests GREEN. The cycle's entire
// MEDIUM fix was unasserted and the keys were dead weight.
//
// WHY THE OBVIOUS ASSERTION DOES NOT WORK
// ---------------------------------------------------------------------------
// `find.descendant(of: find.byType(SlideTransition), matching:
// find.byType(RepaintBoundary))` is satisfied by the hoisted shape too — the
// boundary is still somewhere under the reveal, and a real profile tree carries
// unrelated boundaries (`Scrollable`, `Hero`) and unrelated slides (the page
// route's own transition) besides. What distinguishes the two shapes is the
// ORDER, which `test/helpers/reveal_boundary.dart` reads twice: as the
// depth-first widget chain, and as the render-object ancestry the paint path
// actually walks.
//
// MUTATION-VERIFIED (2026-09-05). With `RevealTransition.build` rewritten to
//
//     RepaintBoundary(
//       child: FadeTransition(
//         opacity: fade,
//         child: SlideTransition(position: slide, child: child),
//       ),
//     )
//
// every structural test in this file goes RED (the chain reads
// `[RepaintBoundary, FadeTransition, SlideTransition]`, and walking up from the
// boundary reaches neither `RenderFractionalTranslation` nor
// `RenderAnimatedOpacity`), and so does the keyed real-screen pin in
// `test/features/salon/presentation/admin_own_profile_screen_test.dart`.
// Restoring the file turns them all GREEN again. See this audit's report for
// the recorded counts.

import 'package:beautica_mobile/core/widgets/reveal_transition.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';
import '../../helpers/reveal_boundary.dart';

const Key _kReveal = Key('reveal-under-test');
const Key _kContent = Key('reveal-content');

/// A reveal at an arbitrary MID-entrance point: neither animation is at its
/// resting value, so nothing here can be green merely because the widgets
/// degenerated to no-ops.
Widget _midEntranceReveal({Widget? child}) => RevealTransition(
  key: _kReveal,
  fade: const AlwaysStoppedAnimation<double>(0.4),
  slide: const AlwaysStoppedAnimation<Offset>(Offset(0, 0.2)),
  child: child ?? const SizedBox(key: _kContent, height: 40, width: 40),
);

/// Counts how many times its `State` was created, so an unmount is observable.
class _MountCounter extends StatefulWidget {
  const _MountCounter();

  static int mounts = 0;

  @override
  State<_MountCounter> createState() => _MountCounterState();
}

class _MountCounterState extends State<_MountCounter> {
  @override
  void initState() {
    super.initState();
    _MountCounter.mounts++;
  }

  @override
  Widget build(BuildContext context) =>
      const SizedBox(key: _kContent, height: 40, width: 40);
}

void main() {
  group('RevealTransition — the RepaintBoundary is the transitions\' CHILD', () {
    testWidgets('fade, then slide, then the boundary', (tester) async {
      await tester.pumpApp(_midEntranceReveal());

      expectBoundaryInsideTransitions(
        tester,
        find.byKey(_kReveal),
        reason: 'the bare widget, nothing else in the tree',
      );
    });

    testWidgets('and still, with decoy boundaries and slides on both sides of '
        'it — the case that defeated every type-only assertion', (
      tester,
    ) async {
      // This is the shape of a real profile screen, compressed: a boundary
      // ABOVE the reveal (a Scrollable's, a Hero's) and a slide + boundary pair
      // BELOW it inside the section's own content. Under the hoisted bug, a
      // `find.descendant(of: SlideTransition, matching: RepaintBoundary)` is
      // satisfied by the inner pair alone and reports nothing wrong.
      await tester.pumpApp(
        RepaintBoundary(
          child: _midEntranceReveal(
            child: const SlideTransition(
              position: AlwaysStoppedAnimation<Offset>(Offset(0, 0.1)),
              child: RepaintBoundary(
                child: SizedBox(key: _kContent, height: 40, width: 40),
              ),
            ),
          ),
        ),
      );

      // Sanity: the decoys really are present, so the isolation below is doing
      // work rather than describing an empty tree.
      expect(
        find.byType(RepaintBoundary),
        findsAtLeastNWidgets(3),
        reason:
            'outer decoy + the reveal\'s own + the inner decoy, plus whatever '
            'MaterialApp contributes — if this is not met the decoy tree was '
            'not built and the isolation claim below is untested.',
      );
      expect(
        find.byType(SlideTransition),
        findsAtLeastNWidgets(2),
        reason:
            'the reveal\'s own slide plus the decoy inside its child — the '
            'MaterialApp page route contributes one more, which is exactly '
            'the ambient noise this file exists to see past.',
      );

      // The naive assertion the header says cannot fail: it passes here on the
      // CORRECT shape and would pass identically on the hoisted one. Asserted
      // so that a future reader who reaches for it sees why it was rejected.
      expect(
        find.descendant(
          of: find.byType(SlideTransition).last,
          matching: find.byType(RepaintBoundary),
        ),
        findsWidgets,
        reason:
            'documented decoy — a boundary IS under a slide either way. This '
            'is the assertion that must NOT be relied on.',
      );

      expectBoundaryInsideTransitions(
        tester,
        find.byKey(_kReveal),
        reason: 'byType(RevealTransition)/byKey isolates past both decoys',
      );
    });

    testWidgets('at rest as well as mid-entrance — the shape is '
        'UNCONDITIONAL', (tester) async {
      // A completed entrance must not be allowed to short-circuit to the bare
      // child: `Widget.canUpdate` compares runtimeType, so a shape that
      // collapses at the end unmounts every State beneath it. Both halves are
      // asserted — the structure survives, and so does the child's State.
      _MountCounter.mounts = 0;

      await tester.pumpApp(_midEntranceReveal(child: const _MountCounter()));
      expect(_MountCounter.mounts, 1);
      expectBoundaryInsideTransitions(tester, find.byKey(_kReveal));

      // Rebuild at the RESTING values the controller lands on.
      await tester.pumpApp(
        const RevealTransition(
          key: _kReveal,
          fade: AlwaysStoppedAnimation<double>(1.0),
          slide: AlwaysStoppedAnimation<Offset>(Offset.zero),
          child: _MountCounter(),
        ),
      );

      expectBoundaryInsideTransitions(
        tester,
        find.byKey(_kReveal),
        reason: 'the finished entrance keeps its wrappers',
      );
      expect(
        _MountCounter.mounts,
        1,
        reason:
            'the child\'s State must survive the entrance completing — a '
            'second mount means the shape changed underneath it, which is how '
            'the search screen once dismissed its own keyboard 1000 ms after '
            'mount (see staggered_reveal.dart\'s header).',
      );
    });
  });
}
