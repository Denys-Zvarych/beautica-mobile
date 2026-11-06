import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_harness.dart';

/// Drags [scrollable] (default: the first `ListView`) DOWN to arm a
/// `RefreshIndicator` and waits until the refetch landed AND the indicator is
/// idle again.
///
/// `RefreshIndicator._shouldStart` drops a new drag silently while the
/// previous cycle is still in `refresh`/`done`. A helper that returns the
/// moment the request is COUNTED returns INSIDE that cycle, so a consecutive
/// pull is lost. Real devices (vsync, emulator animation scale 0 →
/// `disableAnimations`) do not drain the cycle for free the way a headless
/// `pumpAndSettle` does, hence the explicit idle waits at both ends.
Future<void> pullToRefresh(
  WidgetTester tester,
  int Function() getCalls, {
  Finder? scrollable,
  String description = 're-issue of the GET after a pull',
}) async {
  final Finder indicator = find.byType(RefreshProgressIndicator);
  // A previous pull's cycle must be idle or this drag is dropped.
  await AppHarness.pumpUntilGone(tester, indicator);
  final int before = getCalls();
  await tester.drag(
    scrollable ?? find.byType(ListView).first,
    const Offset(0, 320),
    touchSlopY: 0,
  );
  await AppHarness.pumpUntilCondition(
    tester,
    () => getCalls() > before || indicator.evaluate().isNotEmpty,
    description: 'drag did not arm RefreshIndicator ($description)',
  );
  await AppHarness.pumpUntilCondition(
    tester,
    () => getCalls() > before,
    description: description,
  );
  await AppHarness.pumpUntilGone(tester, indicator);
}
