// Source-scan guard (the lull race is not reproducible headless: it needs the
// emulator's animations-off timing). `applyConfirmedFilter(tester);` in
// `master_archive_flow_test.dart` ends on a single pump; an
// `AppHarness.settle` right after it can return before the filtered page
// lands (nothing keeps frames scheduled across the fetch lull). A `settle` may
// only drain the sheet pop; the first `expect(` after the apply must be
// preceded by a `pumpUntil*` that waits for the filtered page.
// The same rule covers every other network-triggering tap in that file whose
// result is read by a one-shot `expect(`: the `master-archive-clear-filters`
// tap, the `complete-booking-confirm` tap and the
// `leave-client-feedback-submit` tap.
// Limit: the scan only proves a `pumpUntil*` precedes the first read, not that
// its condition actually matches the tap that triggered the request.
import 'package:flutter_test/flutter_test.dart';

import 'no_settle_scan.dart';

void main() {
  test(
    'network-triggering taps are followed by pumpUntil* before the first expect',
    () {
      final List<RegExp> triggers = <RegExp>[
        RegExp(r'await applyConfirmedFilter\(tester\);'),
        RegExp(
          r"await tester\.tap\(\s*find\.byKey\(\s*const Key\('master-archive-clear-filters'\)\s*\)\s*,?\s*\);",
        ),
        RegExp(
          r"await tester\.tap\(\s*find\.byKey\(\s*const Key\('complete-booking-confirm'\)\s*\)\s*,?\s*\);",
        ),
        RegExp(
          r"await tester\.tap\(\s*find\.byKey\(\s*const Key\('leave-client-feedback-submit'\)\s*\)\s*,?\s*\);",
        ),
      ];
      expectPumpUntilBeforeFirstRead(
        path: 'integration_test/master_archive_flow_test.dart',
        triggers: triggers,
        firstRead: RegExp(r'expect\('),
      );
    },
  );
}
