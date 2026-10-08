// Phase 24.1a — [ProfileScaffold] back-affordance forwarding.
//
// `onBack` replaces the hard-wired `context.pop()`; `backLabel` /
// `backSemanticLabel` reach the rendered [VelvetTopBar]. With all three null
// the scaffold still pops, exactly as before.

import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/profile_scaffold.dart';
import 'package:beautica_mobile/shared/widgets/velvet_top_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../../helpers/pump_app.dart';

// Test-supplied label passed INTO the widget under test — not l10n copy.
const String _kBackLabel = 'Салон';

const Key _kHome = Key('ps_test_home');
const Key _kOpen = Key('ps_test_open');

/// `/` hosts a button that pushes `/profile` (the [ProfileScaffold]) so a
/// default `context.pop()` has somewhere to return to.
GoRouter _router(Widget Function() scaffold) => GoRouter(
  initialLocation: '/',
  routes: <RouteBase>[
    GoRoute(
      path: '/',
      builder: (BuildContext context, GoRouterState state) => Scaffold(
        key: _kHome,
        body: TextButton(
          key: _kOpen,
          onPressed: () => context.push('/profile'),
          child: const Text('open'),
        ),
      ),
    ),
    GoRoute(
      path: '/profile',
      builder: (BuildContext context, GoRouterState state) => scaffold(),
    ),
  ],
);

Future<void> _open(WidgetTester tester, Widget Function() scaffold) async {
  await tester.pumpRoutedApp(_router(scaffold));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(_kOpen));
  await tester.pumpAndSettle();
  expect(find.byType(ProfileScaffold), findsOneWidget);
}

void main() {
  testWidgets('default back (no onBack) pops the route', (tester) async {
    await _open(
      tester,
      () => const ProfileScaffold(title: 'Профіль', child: SizedBox()),
    );

    await tester.tap(find.byType(NeumorphicIconButton));
    await tester.pumpAndSettle();

    expect(find.byType(ProfileScaffold), findsNothing);
    expect(find.byKey(_kHome), findsOneWidget);
  });

  testWidgets('custom onBack is called instead of pop', (tester) async {
    var backs = 0;
    await _open(
      tester,
      () => ProfileScaffold(
        title: 'Профіль',
        onBack: () => backs++,
        child: const SizedBox(),
      ),
    );

    await tester.tap(find.byType(NeumorphicIconButton));
    await tester.pumpAndSettle();

    expect(backs, 1);
    expect(
      find.byType(ProfileScaffold),
      findsOneWidget,
      reason: 'a custom onBack must REPLACE the default pop, not add to it',
    );
  });

  testWidgets('backLabel + backSemanticLabel reach the rendered top bar', (
    tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await _open(
      tester,
      () => ProfileScaffold(
        title: 'Профіль',
        backLabel: _kBackLabel,
        backSemanticLabel: 'Назад до салону',
        onBack: () {},
        child: const SizedBox(),
      ),
    );

    expect(
      find.descendant(
        of: find.byType(NeumorphicIconButton),
        matching: find.text(_kBackLabel),
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Назад до салону'), findsOneWidget);

    handle.dispose();
  });

  testWidgets('fitWholeTitle reaches the VelvetTopBar (default false)', (
    tester,
  ) async {
    await _open(
      tester,
      () => ProfileScaffold(
        title: 'Профіль',
        backLabel: _kBackLabel,
        onBack: () {},
        fitWholeTitle: true,
        child: const SizedBox(),
      ),
    );
    expect(
      tester.widget<VelvetTopBar>(find.byType(VelvetTopBar)).fitWholeTitle,
      isTrue,
    );
    await _open(
      tester,
      () => const ProfileScaffold(title: 'Профіль', child: SizedBox()),
    );
    expect(
      tester.widget<VelvetTopBar>(find.byType(VelvetTopBar)).fitWholeTitle,
      isFalse,
    );
  });

  testWidgets('null backSemanticLabel keeps the bar default «Назад»', (
    tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await _open(
      tester,
      () => const ProfileScaffold(title: 'Профіль', child: SizedBox()),
    );

    expect(find.bySemanticsLabel('Назад'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(NeumorphicIconButton),
        matching: find.byType(Text),
      ),
      findsNothing,
    );

    handle.dispose();
  });

  testWidgets('showBack: false hides the back button even with onBack', (
    tester,
  ) async {
    await _open(
      tester,
      () => ProfileScaffold(
        title: 'Профіль',
        showBack: false,
        onBack: () {},
        backLabel: _kBackLabel,
        child: const SizedBox(),
      ),
    );

    expect(find.byType(NeumorphicIconButton), findsNothing);
    expect(find.text(_kBackLabel), findsNothing);
  });
}
