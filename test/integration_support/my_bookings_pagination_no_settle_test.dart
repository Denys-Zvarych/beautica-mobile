// Source-scan guard for `client_my_bookings_pagination_sort_flow_test.dart`
// (the CI flake: `settle` returns before the page lands on a slow emulator, a
// one-shot read then sees an unloaded provider). After the Записи nav tap, the
// Минулі tab tap and each past-list drag, a `pumpUntil*` must precede the
// first `upcomingState()` / `pastState()` / `expect(`.
// Limit: the scan only proves a `pumpUntil*` precedes the first read, not that
// its condition actually matches the tap that triggered the request.
import 'package:flutter_test/flutter_test.dart';

import 'no_settle_scan.dart';

void main() {
  test('pagination flow: pumpUntil* precedes the first state read', () {
    expectPumpUntilBeforeFirstRead(
      path:
          'integration_test/client_my_bookings_pagination_sort_flow_test.dart',
      triggers: <RegExp>[
        RegExp(
          r"await tester\.tap\(\s*find\.byKey\(\s*const Key\('client-nav-tile-3'\)\s*\)\s*,?\s*\);",
        ),
        RegExp(
          r'await tester\.tap\(\s*find\.byKey\(\s*const ValueKey<BookingTab>\(\s*BookingTab\.past\s*\)\s*\)\s*,?\s*\);',
        ),
        RegExp(
          r"await tester\.drag\(\s*find\.byKey\(\s*const ValueKey<String>\('my-bookings-list-past'\)\s*\)",
        ),
      ],
      // The getter declarations (`MyBookingsState xState() =>`) are not reads.
      firstRead: RegExp(
        r'(?<!MyBookingsState )\b(?:upcomingState|pastState)\(\)|\bexpect\(',
      ),
    );
  });
}
