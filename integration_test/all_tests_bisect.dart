// TEMPORARY bisection entrypoint (2026-07-01) — see all_tests_part1.dart's
// header comment for the full incident. Round 1 confirmed the culprit is
// among {client_home_hub, client_logout, client_profile_settings,
// client_search}. Round 2 — Set A: 2 controls + client_home_hub +
// client_logout.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'auth_login_flow_test.dart' as auth_login;
import 'client_home_hub_flow_test.dart' as client_home_hub;
import 'client_logout_flow_test.dart' as client_logout;
import 'edit_profile_flow_test.dart' as edit_profile;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('auth_login_flow', auth_login.main);
  group('edit_profile_flow', edit_profile.main);
  group('client_home_hub_flow', client_home_hub.main);
  group('client_logout_flow', client_logout.main);
}
