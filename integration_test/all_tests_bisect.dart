// TEMPORARY bisection entrypoint (2026-07-01) — see all_tests_part1.dart's
// header comment for the full incident. Round 2 confirmed the culprit is
// client_home_hub OR client_logout (both ran ✅ in round 2, crash persisted).
// Round 3 — isolate client_home_hub alone (drop client_logout) to see which
// one alone reproduces the crash.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'auth_login_flow_test.dart' as auth_login;
import 'client_home_hub_flow_test.dart' as client_home_hub;
import 'edit_profile_flow_test.dart' as edit_profile;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('auth_login_flow', auth_login.main);
  group('edit_profile_flow', edit_profile.main);
  group('client_home_hub_flow', client_home_hub.main);
}
