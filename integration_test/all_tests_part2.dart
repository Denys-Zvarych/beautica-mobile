// Phase 17.3 — Aggregating E2E entrypoint, PART 2 of 2 (2026-07-01 split).
//
// See `all_tests_part1.dart` for the full rationale. This file carries the
// remaining 12 of 22 flows (updated by the Beautica OTP task Phase B6
// additions + the salon-master booking-bug flow) so each `flutter test`
// process in CI reports a bounded number of
// tests instead of aggregating all of them into one long-lived run.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'passport_flow_test.dart' as passport;
import 'public_master_profile_flow_test.dart' as public_master_profile;
import 'public_salon_profile_flow_test.dart' as public_salon_profile;
import 'register_flow_test.dart' as register;
import 'register_locality_persistence_flow_test.dart'
    as register_locality_persistence;
import 'salon_booking_flow_test.dart' as salon_booking;
import 'salon_master_book_flow_test.dart' as salon_master_book;
import 'salon_service_filter_flow_test.dart' as salon_service_filter;
import 'schedule_edit_flow_test.dart' as schedule_edit;
import 'schedule_first_create_flow_test.dart' as schedule_first_create;
import 'service_crud_flow_test.dart' as service_crud;
import 'service_edit_category_type_test.dart' as service_edit_category_type;
import 'service_preselection_flow_test.dart' as service_preselection;
import 'settings_change_password_flow_test.dart' as settings_change_password;
import 'support_contact_flow_test.dart' as support_contact;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('passport_flow', passport.main);
  group('public_master_profile_flow', public_master_profile.main);
  group('public_salon_profile_flow', public_salon_profile.main);
  group('register_flow', register.main);
  group(
    'register_locality_persistence_flow',
    register_locality_persistence.main,
  );
  group('salon_booking_flow', salon_booking.main);
  // Salon-master booking bug (Step 2.7 Rule 3b) — corner book button →
  // master-scoped ServiceSelectorSheet shows ONLY that master's services.
  group('salon_master_book_flow', salon_master_book.main);
  group('salon_service_filter_flow', salon_service_filter.main);
  group('schedule_edit_flow', schedule_edit.main);
  group('schedule_first_create_flow', schedule_first_create.main);
  group('service_crud_flow', service_crud.main);
  group('service_edit_category_type', service_edit_category_type.main);
  // Search service-filter → booking pre-selection (Step 2.7 Rule 3b) — exact
  // serviceTypeSlug pre-check on the master + salon booking catalogues.
  group('service_preselection_flow', service_preselection.main);
  // Beautica OTP task Phase B6 — settings change-password → OTP → forced logout.
  group('settings_change_password_flow', settings_change_password.main);
  group('support_contact_flow', support_contact.main);
}
