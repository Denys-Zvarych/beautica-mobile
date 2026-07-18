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
import 'client_my_bookings_cancel_flow_test.dart' as client_my_bookings_cancel;
import 'client_my_bookings_pagination_sort_flow_test.dart'
    as client_my_bookings_pagination_sort;
import 'client_elapsed_booking_readonly_flow_test.dart'
    as client_elapsed_booking_readonly;
import 'client_leave_review_flow_test.dart' as client_leave_review;
import 'client_reschedule_flow_test.dart' as client_reschedule;
import 'client_logout_flow_test.dart' as client_logout;
import 'client_profile_settings_flow_test.dart' as client_profile_settings;
import 'client_search_flow_test.dart' as client_search;
import 'search_prefill_survives_name_edit_flow_test.dart'
    as search_prefill_survives_name_edit;
import 'client_shell_flow_test.dart' as client_shell;
import 'client_shell_edge_swipe_back_flow_test.dart'
    as client_shell_edge_swipe_back;
import 'edit_profile_flow_test.dart' as edit_profile;
import 'edit_profile_redirect_flow_test.dart' as edit_profile_redirect;
import 'forgot_password_otp_flow_test.dart' as forgot_password_otp;
import 'independent_multi_service_booking_flow_test.dart'
    as independent_multi_service_booking;
import 'logout_flow_test.dart' as logout;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('auth_login_flow', auth_login.main);
  // Independent-master MULTI-SERVICE booking (Step 2.7 Rule 3b) — acceptance +
  // partial-failure/same-key-retry (re-authored from the removed
  // client_booking_conflict_flow against the new per-appointment contract).
  group(
    'independent_multi_service_booking_flow',
    independent_multi_service_booking.main,
  );
  // My Bookings → Booking Detail → Cancel journey (Step 2.7 Rule 3b).
  group('client_my_bookings_cancel_flow', client_my_bookings_cancel.main);
  // My Bookings pagination/sort regression (Step 2.7 Rule 3b, mobile-qa) —
  // Bug B (dropped `sort` param) + Bug A (per-status fan-out+merge) against a
  // REAL (statuses, sort, page) fake-backend slice, not hand-picked buckets.
  group(
    'client_my_bookings_pagination_sort_flow',
    client_my_bookings_pagination_sort.main,
  );
  // Elapsed CONFIRMED booking → read-only detail (Step 2.7 Rule 3b).
  group(
    'client_elapsed_booking_readonly_flow',
    client_elapsed_booking_readonly.main,
  );
  // CLIENT reschedule journey (Step 2.7 Rule 3b) — detail «Перенести» → slot
  // picker → new date+time → confirm (RESCHEDULE mode) → PATCH /reschedule →
  // success, plus both provider invalidations + the Home-Hub entry point.
  group('client_reschedule_flow', client_reschedule.main);
  // CLIENT leave-review journey (Step 2.7 Rule 3b) — COMPLETED booking detail
  // → «Залишити відгук» → rate 5 + comment → POST /reviews → success pops back
  // and the invalidated detail hides the entry CTA.
  group('client_leave_review_flow', client_leave_review.main);
  group('client_home_hub_flow', client_home_hub.main);
  group('client_logout_flow', client_logout.main);
  group('client_profile_settings_flow', client_profile_settings.main);
  group('client_search_flow', client_search.main);
  // Search prefill survives a mid-session name edit (refreshUser) — the
  // `.select(user.id)` narrowing regression (Step 2.7 Rule 3b).
  group(
    'search_prefill_survives_name_edit_flow',
    search_prefill_survives_name_edit.main,
  );
  group('client_shell_flow', client_shell.main);
  // CLIENT left-edge swipe-back → Home tab (Step 2.7 Rule 3b) — the gesture
  // twin of the R1 system-back flow in client_shell_flow_test.dart Test 7.
  group('client_shell_edge_swipe_back_flow', client_shell_edge_swipe_back.main);
  group('edit_profile_flow', edit_profile.main);
  group('edit_profile_redirect_flow', edit_profile_redirect.main);
  // Beautica OTP task Phase B6 — forgot-password email → OTP → new password.
  group('forgot_password_otp_flow', forgot_password_otp.main);
  group('logout_flow', logout.main);
}
