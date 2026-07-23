// Unit — [ShellBackDispatcher.handleBack] decision table, in isolation.
//
// Fast + precise coverage of the three branches of the back policy, with a
// MOCK [StatefulNavigationShell] (currentIndex + goBranch stubbed) and a REAL
// mounted [Navigator] behind the active branch key so `canPop()` is a genuine
// NavigatorState answer (not a fake bool). The full gesture / PopScope wiring is
// proven at the widget tier in
// test/features/shell/client_shell_detail_pop_test.dart.

import 'dart:async';

import 'package:beautica_mobile/shared/navigation/shell_back_dispatcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _MockShell extends Mock implements StatefulNavigationShell {
  // [StatefulNavigationShell] is a [Widget] (Diagnosticable), whose `toString`
  // carries a `{DiagnosticLevel minLevel}` param mocktail's own `toString`
  // override does not match. Re-declare the diagnostic signature so the mock
  // conforms to the interface.
  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) =>
      'MockStatefulNavigationShell';
}

/// Mounts a real [Navigator] under [key]. When [pushed] is true a second route
/// is pushed so the navigator can pop (a detail page on top); otherwise it holds
/// a single root route (`canPop` == false).
Future<void> _mountBranchNavigator(
  WidgetTester tester,
  GlobalKey<NavigatorState> key, {
  required bool pushed,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Navigator(
        key: key,
        onGenerateRoute: (RouteSettings settings) => MaterialPageRoute<void>(
          builder: (_) => const SizedBox.shrink(),
          settings: settings,
        ),
      ),
    ),
  );
  if (pushed) {
    // The push Future resolves only when this route is later popped, so it is
    // intentionally not awaited here (awaiting would hang the test).
    unawaited(
      key.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const SizedBox.shrink()),
      ),
    );
    await tester.pumpAndSettle();
  }
}

void main() {
  const int homeIndex = 0;

  late _MockShell shell;
  late List<GlobalKey<NavigatorState>> keys;

  setUp(() {
    shell = _MockShell();
    keys = <GlobalKey<NavigatorState>>[
      GlobalKey<NavigatorState>(),
      GlobalKey<NavigatorState>(),
      GlobalKey<NavigatorState>(),
    ];
    // goBranch returns void — stub it so the mock does not throw when called.
    when(
      () =>
          shell.goBranch(any(), initialLocation: any(named: 'initialLocation')),
    ).thenReturn(null);
  });

  ShellBackDispatcher dispatcher() => ShellBackDispatcher(
    navigationShell: shell,
    branchNavigatorKeys: keys,
    homeIndex: homeIndex,
  );

  testWidgets(
    'active branch canPop → pops it, returns true, does NOT goBranch',
    (tester) async {
      when(() => shell.currentIndex).thenReturn(2); // non-Home, but…
      await _mountBranchNavigator(tester, keys[2], pushed: true);

      final bool consumed = dispatcher().handleBack();
      await tester.pumpAndSettle();

      expect(consumed, isTrue, reason: 'popping a detail consumes the back');
      expect(
        keys[2].currentState!.canPop(),
        isFalse,
        reason: 'the pushed detail route was popped (branch back at its root)',
      );
      verifyNever(
        () => shell.goBranch(
          any(),
          initialLocation: any(named: 'initialLocation'),
        ),
      );
    },
  );

  testWidgets(
    'branch at root + non-Home → goBranch(Home, initialLocation:false), '
    'returns true',
    (tester) async {
      when(() => shell.currentIndex).thenReturn(2);
      await _mountBranchNavigator(tester, keys[2], pushed: false);

      final bool consumed = dispatcher().handleBack();

      expect(consumed, isTrue, reason: 'the tab hop consumes the back');
      verify(() => shell.goBranch(homeIndex, initialLocation: false)).called(1);
    },
  );

  testWidgets(
    'branch at root + on Home → no-op, returns false, never goBranch',
    (tester) async {
      when(() => shell.currentIndex).thenReturn(homeIndex);
      await _mountBranchNavigator(tester, keys[homeIndex], pushed: false);

      final bool consumed = dispatcher().handleBack();

      expect(
        consumed,
        isFalse,
        reason:
            'the Home root has nothing to do — back falls through to the OS',
      );
      verifyNever(
        () => shell.goBranch(
          any(),
          initialLocation: any(named: 'initialLocation'),
        ),
      );
    },
  );
}
