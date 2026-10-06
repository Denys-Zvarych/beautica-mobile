// Deterministic waiting for plain `test()`s that drive real file IO: polls a
// CONDITION by yielding to the event loop instead of sleeping on the wall
// clock, so a slow machine cannot flake it and a fast one never over-waits.

import 'package:flutter_test/flutter_test.dart';

/// Yields to the event loop until [cond] holds; fails after [maxTurns] turns.
Future<void> until(bool Function() cond, {int maxTurns = 5000}) async {
  for (var i = 0; i < maxTurns; i++) {
    if (cond()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('condition not met after $maxTurns event-loop turns');
}
