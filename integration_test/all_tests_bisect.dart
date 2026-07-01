// TEMPORARY bisection entrypoint (2026-07-01) — NOT part of the permanent
// suite. Used to narrow down which newly-merged flow corrupts the
// IntegrationTestWidgetsFlutterBinding's final teardown (crashes the
// emulator/adb link at the very end of the flutter test process even though
// every individual testWidgets passes). Delete once the culprit is found and
// fixed; do not leave this wired into CI permanently.
//
// Round 1 — Half A: 2 known-safe controls (ran fine pre-merge) + first 4 of
// the 7 newly-merged flows from all_tests_part1.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'auth_login_flow_test.dart' as auth_login;
import 'client_home_hub_flow_test.dart' as client_home_hub;
import 'client_logout_flow_test.dart' as client_logout;
import 'client_profile_settings_flow_test.dart' as client_profile_settings;
import 'client_search_flow_test.dart' as client_search;
import 'edit_profile_flow_test.dart' as edit_profile;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('auth_login_flow', auth_login.main);
  group('edit_profile_flow', edit_profile.main);
  group('client_home_hub_flow', client_home_hub.main);
  group('client_logout_flow', client_logout.main);
  group('client_profile_settings_flow', client_profile_settings.main);
  group('client_search_flow', client_search.main);
}
