// Shared assertion for [RevealTransition]'s ONE structural invariant: the
// `RepaintBoundary` sits BELOW both transitions, never above them.
//
// WHY A HELPER AND NOT `find.descendant(of: SlideTransition, matching:
// RepaintBoundary)`
// ---------------------------------------------------------------------------
// That finder cannot fail. A loaded profile tree carries `RepaintBoundary`s of
// its own (every `Scrollable`, every `Hero`, `NeumorphicCard` subtrees), so a
// boundary is a descendant of a `SlideTransition` whether or not the reveal put
// one there — and hoisting the boundary ABOVE `FadeTransition` leaves it a
// descendant of the reveal all the same. The header of
// `lib/core/widgets/reveal_transition.dart` records that every type-based
// candidate assertion stayed green under exactly that mutation, which is the
// reason the widget class exists at all.
//
// What CAN fail is the ORDER. These two functions read it two different ways:
//
//   * [revealShapeChain] — the first three shape-relevant widget types in
//     depth-first order below a `RevealTransition`. Correct: fade, slide,
//     boundary. Hoisted: boundary, fade, slide.
//   * [expectBoundaryInsideTransitions] — and then the same claim again at the
//     RENDER level, walking UP from the `RenderRepaintBoundary` and requiring
//     it to pass through `RenderFractionalTranslation` and then
//     `RenderAnimatedOpacity`. That is the relationship the paint path actually
//     obeys (`RenderAnimatedOpacity.paint` → `pushOpacity` → `paintChild`
//     every frame), so it is the half that says the isolation is REAL rather
//     than merely well-nested in the widget tree.
//
// Neither reads a constructor field. `RevealTransition.child` is a field; that
// the boundary is between the transitions and it is a TREE relationship, and
// only the tree can be asked.

import 'package:beautica_mobile/core/widgets/reveal_transition.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// The widget types whose relative order inside a [RevealTransition] IS the
/// invariant. Anything else in the chain (the `FractionalTranslation` that
/// [SlideTransition] builds, the host's own content) is skipped.
const Set<Type> _kShapeTypes = <Type>{
  FadeTransition,
  SlideTransition,
  RepaintBoundary,
};

/// The correct order: both transitions, then the boundary they isolate.
const List<Type> kRevealShape = <Type>[
  FadeTransition,
  SlideTransition,
  RepaintBoundary,
];

/// The first three of [_kShapeTypes] encountered depth-first below the single
/// [RevealTransition] matched by [reveal].
///
/// `skipOffstage: false` is the caller's business — pass a finder that already
/// carries it when the reveal under test may be inside an `IndexedStack`.
List<Type> revealShapeChain(WidgetTester tester, Finder reveal) {
  final Element root = reveal.evaluate().single;
  expect(
    root.widget,
    isA<RevealTransition>(),
    reason:
        'revealShapeChain must be pointed at a RevealTransition — it is that '
        'type, not a bare FadeTransition/SlideTransition pair, that makes a '
        'reveal isolable from the unrelated transitions in a profile tree.',
  );

  final List<Type> chain = <Type>[];
  void visit(Element element) {
    if (chain.length == kRevealShape.length) return;
    if (_kShapeTypes.contains(element.widget.runtimeType)) {
      chain.add(element.widget.runtimeType);
      if (chain.length == kRevealShape.length) return;
    }
    element.visitChildren(visit);
  }

  root.visitChildren(visit);
  return chain;
}

/// Asserts the boundary is the transitions' CHILD, in the widget tree and again
/// in the render tree.
///
/// [reason] is appended to both failures so a screen-level call site can say
/// which keyed section it was looking at.
void expectBoundaryInsideTransitions(
  WidgetTester tester,
  Finder reveal, {
  String reason = '',
}) {
  final String suffix = reason.isEmpty ? '' : ' ($reason)';

  expect(
    revealShapeChain(tester, reveal),
    kRevealShape,
    reason:
        'the RepaintBoundary must be BELOW both transitions$suffix. A boundary '
        'above them isolates nothing: RenderAnimatedOpacity.paint and '
        'RenderFractionalTranslation.paint both call paintChild on every one '
        'of the ~60 frames of the entrance, so the section repaints per frame '
        'instead of rasterising once. Reading [RepaintBoundary, '
        'FadeTransition, SlideTransition] here means the boundary was hoisted '
        'back OUT — see lib/core/widgets/reveal_transition.dart.',
  );

  // And the same claim at the render level, which is the one the paint path
  // actually obeys.
  final RenderObject boundary = tester.renderObject(
    find
        .descendant(
          of: reveal,
          matching: find.byType(RepaintBoundary, skipOffstage: false),
          skipOffstage: false,
        )
        .first,
  );
  expect(boundary, isA<RenderRepaintBoundary>());

  final List<String> ancestors = <String>[];
  RenderObject? parent = boundary.parent;
  // Six hops is generous: the correct shape reaches RenderAnimatedOpacity in
  // two. Bounded so a hoisted boundary fails on the assertion rather than
  // walking to the root of the app.
  for (int i = 0; i < 6 && parent != null; i++) {
    ancestors.add(parent.runtimeType.toString());
    parent = parent.parent;
  }

  expect(
    ancestors,
    containsAllInOrder(<String>[
      'RenderFractionalTranslation',
      'RenderAnimatedOpacity',
    ]),
    reason:
        'walking UP from the RenderRepaintBoundary must pass through the '
        'slide and then the fade$suffix — that IS "the boundary is inside the '
        'transitions" stated in the tree that paints. Found: $ancestors.',
  );
}
