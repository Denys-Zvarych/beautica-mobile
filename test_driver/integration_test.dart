// Host-side driver for `flutter drive` runs of the integration_test flows.
//
// WHY THIS FILE EXISTS (the debug↔release divergence safeguard, 2026-06-18)
// ------------------------------------------------------------------------
// `flutter test integration_test/...` ALWAYS runs JIT/debug with asserts ON, so
// it catches the "debug-fails / release-works" direction (our logout
// CircularDependencyError). It has NO `--profile` flag, so it canNOT catch the
// INVERSE risk — "release-fails / debug-works", where a stripped assert CHANGES
// behaviour. `flutter drive --profile --driver test_driver/integration_test.dart
// --target integration_test/<flow>.dart` runs the SAME flow in profile mode
// (asserts stripped, AOT — release-like), so a release-only divergence on a
// critical flow fails CI. This driver is the host half that `flutter drive`
// requires; the device half is the flow's own `main()` under integration_test/.
//
// `integrationDriver()` is the canonical no-op host driver from the
// integration_test package — it simply awaits the on-device results and reports
// them as the process exit code.

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
