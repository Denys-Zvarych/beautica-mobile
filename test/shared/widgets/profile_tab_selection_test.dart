// Widget tests for `ProfileTabSelection` + `ProfileTabSection`
// (lib/shared/widgets/profile_tab_selection.dart).
//
// Phase 351 (D15, mobile-qa gap-fix 2026-09-25) — the ONE card->tab mechanism
// shared by all three master profile screens (`PublicMasterProfileScreen`,
// `MasterProfileScreen`, `SalonMasterProfileScreen`). The phase doc named
// this file explicitly; it did not get written when the mixin shipped. Every
// guarantee about the mixin was inherited transitively through the three
// screens' own card-tap tests, which prove "the RIGHT tab shows" but never
// isolate the mixin's own two behaviours: the reveal-scroll heuristic (below
// the fold vs. already visible) and the explicit disposal contract. Both are
// exercised here directly against the mixin, with no screen in the way.
//
// The mixin's `selectProfileTab` mutates a `ValueNotifier` (mobile-perf LOW,
// Phase 351 audit-fix cycle 1) rather than calling `setState` — so a bare tap
// + `pump()` will NOT show a stale value; the `ProfileTabSection`
// `ValueListenableBuilder` rebuilds on its own the instant the notifier's
// value changes.

import 'package:beautica_mobile/shared/widgets/profile_tab_selection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

/// Minimal host `State` applying the mixin under test. A tall
/// `SingleChildScrollView` with the tab-bar anchor placed [spacerBefore]
/// logical pixels down, so a test controls whether the anchor starts inside
/// or below the viewport fold. [reduceMotion] wraps the tree in a
/// `MediaQuery` with `disableAnimations: true` so a reveal jumps instantly
/// (`Duration.zero`) instead of animating over 250ms — deterministic without
/// a fixed-duration pump.
class _TabSelectionHarness extends StatefulWidget {
  const _TabSelectionHarness({
    this.spacerBefore = 0,
    this.reduceMotion = false,
  });

  final double spacerBefore;
  final bool reduceMotion;

  @override
  State<_TabSelectionHarness> createState() => _TabSelectionHarnessState();
}

class _TabSelectionHarnessState extends State<_TabSelectionHarness>
    with ProfileTabSelection<_TabSelectionHarness> {
  final ScrollController scrollController = ScrollController();

  @override
  void dispose() {
    disposeProfileTabSelection();
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget scaffold = Scaffold(
      body: SingleChildScrollView(
        controller: scrollController,
        child: Column(
          children: <Widget>[
            SizedBox(height: widget.spacerBefore, key: const Key('spacer')),
            KeyedSubtree(
              key: profileTabBarAnchor,
              child: Container(
                key: const Key('anchor'),
                height: 48,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 2000, key: Key('trailing-spacer')),
            ProfileTabSection(
              notifier: profileTabNotifier,
              builder: (BuildContext context, int tab) =>
                  Text('tab-$tab', key: const Key('tab-body')),
            ),
          ],
        ),
      ),
    );
    if (!widget.reduceMotion) return scaffold;
    return MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: scaffold,
    );
  }
}

void main() {
  group('ProfileTabSelection — selectProfileTab', () {
    testWidgets(
      'sets the notifier AND rebuilds the ProfileTabSection body — no bare '
      'setState needed',
      (tester) async {
        await tester.pumpApp(const _TabSelectionHarness());
        expect(find.text('tab-0'), findsOneWidget);

        final _TabSelectionHarnessState state = tester
            .state<_TabSelectionHarnessState>(
              find.byType(_TabSelectionHarness),
            );
        state.selectProfileTab(2);
        await tester.pump();

        expect(state.profileTab, 2);
        expect(find.text('tab-2'), findsOneWidget);
        expect(find.text('tab-0'), findsNothing);
      },
    );

    testWidgets('the default revealTabBar (false) never scrolls, even when '
        'the anchor is below the fold', (tester) async {
      await tester.pumpApp(
        const _TabSelectionHarness(spacerBefore: 2000, reduceMotion: true),
        width: 320,
        height: 568,
      );

      final _TabSelectionHarnessState state = tester
          .state<_TabSelectionHarnessState>(find.byType(_TabSelectionHarness));
      expect(state.scrollController.offset, 0);

      state.selectProfileTab(1); // revealTabBar defaults to false
      await tester.pumpAndSettle();

      expect(
        state.scrollController.offset,
        0,
        reason:
            'a plain ProfileTabBar.onSelect tap (revealTabBar: false) must '
            'never move the scroll position — only a card tap does',
      );
    });
  });

  group('ProfileTabSelection — revealTabBar scroll heuristic', () {
    testWidgets('with revealTabBar, the anchor lands inside the viewport on a '
        '320x568 surface at text scale 2.0 when it starts below the fold', (
      tester,
    ) async {
      await tester.pumpApp(
        const _TabSelectionHarness(spacerBefore: 2000, reduceMotion: true),
        width: 320,
        height: 568,
        textScaleFactor: 2.0,
      );

      final _TabSelectionHarnessState state = tester
          .state<_TabSelectionHarnessState>(find.byType(_TabSelectionHarness));

      // Below the fold BEFORE the reveal — the crux of the test: if this
      // assertion cannot pass, "reveal" proves nothing.
      final Rect viewportBefore = tester.getRect(
        find.byType(SingleChildScrollView),
      );
      final Rect anchorBefore = tester.getRect(find.byKey(const Key('anchor')));
      expect(
        anchorBefore.top >= viewportBefore.bottom,
        isTrue,
        reason:
            'the anchor must start OFF-SCREEN for this test to mean '
            'anything',
      );

      state.selectProfileTab(2, revealTabBar: true);
      // The scroll is scheduled via a post-frame callback and then driven
      // by an AnimationController (Duration.zero under reduceMotion, but
      // still ticker-driven) — pumpAndSettle drains both.
      await tester.pumpAndSettle();

      final Rect viewportAfter = tester.getRect(
        find.byType(SingleChildScrollView),
      );
      final Rect anchorAfter = tester.getRect(find.byKey(const Key('anchor')));
      expect(
        anchorAfter.top >= viewportAfter.top &&
            anchorAfter.bottom <= viewportAfter.bottom,
        isTrue,
        reason:
            'the tab-bar anchor must be fully inside the viewport after a '
            'card tap reveals it',
      );
    });

    testWidgets(
      'no scroll when the bar is ALREADY visible — Scrollable.ensureVisible '
      'is a documented no-op, this pins that the mixin relies on it rather '
      'than unconditionally jumping',
      (tester) async {
        await tester.pumpApp(
          const _TabSelectionHarness(spacerBefore: 0, reduceMotion: true),
          width: 320,
          height: 568,
        );

        final _TabSelectionHarnessState state = tester
            .state<_TabSelectionHarnessState>(
              find.byType(_TabSelectionHarness),
            );
        expect(state.scrollController.offset, 0);

        state.selectProfileTab(1, revealTabBar: true);
        await tester.pumpAndSettle();

        expect(
          state.scrollController.offset,
          0,
          reason:
              'the anchor was already on screen — the scroll offset '
              'must not move at all',
        );
      },
    );
  });

  group('ProfileTabSelection — disposeProfileTabSelection', () {
    testWidgets(
      'disposes profileTabNotifier on State.dispose — no listener can be '
      'attached afterwards',
      (tester) async {
        await tester.pumpApp(const _TabSelectionHarness());
        final _TabSelectionHarnessState state = tester
            .state<_TabSelectionHarnessState>(
              find.byType(_TabSelectionHarness),
            );
        final ValueNotifier<int> notifier = state.profileTabNotifier;

        // Unmount the harness -> State.dispose() -> disposeProfileTabSelection().
        await tester.pumpWidget(const SizedBox.shrink());

        expect(
          () => notifier.addListener(() {}),
          throwsFlutterError,
          reason:
              'profileTabNotifier must be disposed by State.dispose(), not '
              'leaked — mirrors every other AnimationController/ '
              'CurvedAnimation this mixin\'s doc comment says callers must '
              'release themselves',
        );
      },
    );
  });
}
