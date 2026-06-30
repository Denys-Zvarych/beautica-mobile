// Phase 17.3 — Aggregating E2E entrypoint (L87 + L88).
//
// WHY THIS FILE EXISTS
// --------------------
// CI used to run the 5 E2E flow files as 5 separate `flutter test` processes
// (a per-file `for` loop). That was a correctness fix for an earlier bug:
// directory-mode batching (`flutter test integration_test/`) launches the app
// once and CANNOT relaunch it between files, so only the FIRST flow ran and the
// rest died with "Unable to start the app on the device".
//
// The per-file loop fixed correctness but cold-boots the whole emulator app
// path 5× (one `flutter test` process per flow) — several minutes of CI
// wall-clock spent re-launching the same app.
//
// This file recovers that cost. It is a SINGLE aggregating entrypoint: one
// `flutter test integration_test/all_tests.dart` run = one isolate = one app
// process. Each flow's `testWidgets` still pumps a FRESH app via
// `AppHarness.boot()` and tears global state down via `AppHarness.tearDownHarness`
// between tests — so the re-launch happens per-`testWidgets` (the supported
// mechanism), NOT per-file (the broken mechanism). All 5 flows run in sequence
// in the same isolate.
//
// L88 — COMPLETE FAILURE REPORTING
// --------------------------------
// Because this is one `flutter test` invocation with no `|| exit 1` fail-fast
// wrapper, the run continues past a failing `testWidgets` and reports EVERY
// failure across all 5 flows at the end. `flutter test`'s own non-zero exit on
// any failure is the CI gate.
//
// RE-LAUNCH SAFETY (verified before writing this file)
// ----------------------------------------------------
//   • Each flow exposes a callable top-level `void main()` that only registers
//     `setUp`/`tearDown`/`testWidgets` — no eager side effects.
//   • `IntegrationTestWidgetsFlutterBinding.ensureInitialized()` is idempotent;
//     each flow main() also calls it, which is harmless after the first call.
//   • The only cross-flow global is `AppStartTime._start`; every flow registers
//     `tearDown(AppHarness.tearDownHarness)`, which resets it. `FakeBackend` is
//     instance-scoped per test (its own `Dio`), and each `testWidgets` builds a
//     fresh `ProviderScope`, so providers/secure-storage do not leak between
//     flows.
//
// CONVENTION
// ----------
// Imports exactly the 5 flow mains (aliased) and nothing from `support/` as a
// test. `support/` holds shared helpers (AppHarness, FakeBackend), not runnable
// tests, so it is never invoked here.

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
import 'logout_flow_test.dart' as logout;
import 'passport_flow_test.dart' as passport;
import 'public_master_profile_flow_test.dart' as public_master_profile;
import 'register_flow_test.dart' as register;
import 'register_locality_persistence_flow_test.dart'
    as register_locality_persistence;
import 'schedule_edit_flow_test.dart' as schedule_edit;
import 'schedule_first_create_flow_test.dart' as schedule_first_create;
import 'service_crud_flow_test.dart' as service_crud;
import 'service_edit_category_type_test.dart' as service_edit_category_type;
import 'support_contact_flow_test.dart' as support_contact;

void main() {
  // Initialise the integration binding ONCE for the whole aggregated run.
  // Each flow main() also calls this; ensureInitialized() is idempotent, so the
  // subsequent calls are no-ops.
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Register every flow's tests in sequence. Each main() only registers
  // groups/testWidgets (plus its own setUp/tearDown), so the order below is the
  // execution order. Each testWidgets pumps a fresh app via AppHarness.boot()
  // and resets global state via AppHarness.tearDownHarness — the per-test
  // re-launch model that directory-mode batching cannot provide.
  group('auth_login_flow', auth_login.main);
  group('client_home_hub_flow', client_home_hub.main);
  group('client_logout_flow', client_logout.main);
  group('client_profile_settings_flow', client_profile_settings.main);
  group('client_search_flow', client_search.main);
  group('client_shell_flow', client_shell.main);
  group('edit_profile_flow', edit_profile.main);
  group('edit_profile_redirect_flow', edit_profile_redirect.main);
  group('logout_flow', logout.main);
  group('passport_flow', passport.main);
  group('public_master_profile_flow', public_master_profile.main);
  group('register_flow', register.main);
  group(
    'register_locality_persistence_flow',
    register_locality_persistence.main,
  );
  group('schedule_edit_flow', schedule_edit.main);
  group('schedule_first_create_flow', schedule_first_create.main);
  group('service_crud_flow', service_crud.main);
  group('service_edit_category_type', service_edit_category_type.main);
  group('support_contact_flow', support_contact.main);
}
