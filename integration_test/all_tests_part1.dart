// Phase 17.3 — Aggregating E2E entrypoint, PART 1 of 2 (2026-07-01 split).
//
// WHY THIS FILE EXISTS (supersedes the single all_tests.dart CI entrypoint)
// --------------------------------------------------------------------
// `integration_test/all_tests.dart` aggregated every flow into ONE
// `flutter test` process. That was fine at 5 flows (10 tests), but the suite
// has since grown to 19 flows. CI started failing with the formal test
// reporter acknowledging only 1 test ("🎉 1 test passed") while every flow's
// own assertions still logged ✅ via raw `dart:developer log` — then the
// process crashed at final teardown, taking the emulator/adb link down with
// it ("adb: device 'emulator-5554' not found" right after the suite
// finished). The working theory: `flutter test` reports pass/fail over a
// fragile adb-forwarded VM-service channel, one round-trip per registered
// test; a single process carrying too many tests degrades that channel
// before its own clean shutdown.
//
// This file (+ `all_tests_part2.dart`) splits the flows (19, 21 after
// the Beautica OTP task Phase B6 additions) into two smaller `flutter test`
// invocations run sequentially in one emulator session (see pr-validate.yml)
// — same boot-cost amortization as before, just two shorter-lived processes
// instead of one very long one.
//
// RE-LAUNCH SAFETY — identical guarantees to the original all_tests.dart:
//   • Each flow exposes a callable top-level `void main()` that only registers
//     `setUp`/`tearDown`/`testWidgets` — no eager side effects.
//   • `IntegrationTestWidgetsFlutterBinding.ensureInitialized()` is idempotent.
//   • The only cross-flow global is `AppStartTime._start`; every flow registers
//     `tearDown(AppHarness.tearDownHarness)`, which resets it. `FakeBackend` is
//     instance-scoped per test, and each `testWidgets` builds a fresh
//     `ProviderScope`, so providers/secure-storage do not leak between flows.
//
// L88 — COMPLETE FAILURE REPORTING preserved: no `|| exit 1` fail-fast
// wrapper on either invocation, so each half reports every failure within it.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'auth_login_flow_test.dart' as auth_login;
import 'client_home_hub_flow_test.dart' as client_home_hub;
import 'client_logout_flow_test.dart' as client_logout;
import 'client_profile_settings_flow_test.dart' as client_profile_settings;
import 'client_search_flow_test.dart' as client_search;
import 'client_shell_flow_test.dart' as client_shell;
import 'edit_profile_flow_test.dart' as edit_profile;
import 'edit_profile_redirect_flow_test.dart' as edit_profile_redirect;
import 'forgot_password_otp_flow_test.dart' as forgot_password_otp;
import 'logout_flow_test.dart' as logout;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('auth_login_flow', auth_login.main);
  group('client_home_hub_flow', client_home_hub.main);
  group('client_logout_flow', client_logout.main);
  group('client_profile_settings_flow', client_profile_settings.main);
  group('client_search_flow', client_search.main);
  group('client_shell_flow', client_shell.main);
  group('edit_profile_flow', edit_profile.main);
  group('edit_profile_redirect_flow', edit_profile_redirect.main);
  // Beautica OTP task Phase B6 — forgot-password email → OTP → new password.
  group('forgot_password_otp_flow', forgot_password_otp.main);
  group('logout_flow', logout.main);
}
