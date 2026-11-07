// Source-scan guard for two CI-only emulator flakes (settle returns before a
// real-clock / async step lands; a one-shot read then sees the old state):
//  - wishlist_remove_failure_flow_test: after the un-heart tap, a pumpUntil*
//    must precede the first expect( (the DELETE dispatch).
//  - salon_management_profile_flow_test: after each confirmDeleteSalon call
//    AND after the 2-salon test's inline btn-confirm-delete-salon tap (the
//    helper's own body is excluded), a pumpUntilCondition( must precede the
//    first AppHarness.location read (the /salons/mine resolver forwards
//    asynchronously).
// The race itself is emulator-only (no headless repro); this pins the waits.
import 'package:flutter_test/flutter_test.dart';

import 'no_settle_scan.dart';

void main() {
  test('wishlist remove failure: pumpUntil* after heart tap', () {
    expectPumpUntilBeforeFirstRead(
      path: 'integration_test/wishlist_remove_failure_flow_test.dart',
      triggers: <RegExp>[RegExp(r'await tester\.tap\(heart\);')],
      firstRead: RegExp(r'\bexpect\('),
    );
  });

  test('salon profile: pumpUntil* after confirmDeleteSalon before location', () {
    expectPumpUntilBeforeFirstRead(
      path: 'integration_test/salon_management_profile_flow_test.dart',
      triggers: <RegExp>[
        RegExp(r'await confirmDeleteSalon\(tester, router\);'),
        RegExp(
          r"await tester\.tap\(find\.byKey\(const Key\('btn-confirm-delete-salon'\)\)\);",
        ),
      ],
      waitPattern: RegExp(r'pumpUntilCondition\('),
      skipInsideFunctions: <String>['confirmDeleteSalon'],
      firstRead: RegExp(r'AppHarness\.location\(router\)'),
    );
  });
}
