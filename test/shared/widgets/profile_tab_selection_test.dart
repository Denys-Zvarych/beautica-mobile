// Widget tests for `ProfileTabSelection` + `ProfileTabSection`
// (lib/shared/widgets/profile_tab_selection.dart).
//
// Phase 351 (D15, mobile-qa gap-fix 2026-09-25) — the ONE tab-selection
// mechanism shared by all three master profile screens
// (`PublicMasterProfileScreen`, `MasterProfileScreen`,
// `SalonMasterProfileScreen`). The phase doc named this file explicitly.
//
// User decision 2026-09-26 — the stat cards are display-only and never call
// `selectProfileTab`; the mixin's former `revealTabBar` reveal-scroll
// heuristic and `profileTabBarAnchor` (their only caller) were removed with
// it. What remains here pins the mixin's two surviving guarantees: the
// `ValueNotifier`-driven rebuild isolation, and the explicit disposal
// contract.
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

/// Minimal host `State` applying the mixin under test.
class _TabSelectionHarness extends StatefulWidget {
  const _TabSelectionHarness();

  @override
  State<_TabSelectionHarness> createState() => _TabSelectionHarnessState();
}

class _TabSelectionHarnessState extends State<_TabSelectionHarness>
    with ProfileTabSelection<_TabSelectionHarness> {
  @override
  void dispose() {
    disposeProfileTabSelection();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ProfileTabSection(
        notifier: profileTabNotifier,
        builder: (BuildContext context, int tab) =>
            Text('tab-$tab', key: const Key('tab-body')),
      ),
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
