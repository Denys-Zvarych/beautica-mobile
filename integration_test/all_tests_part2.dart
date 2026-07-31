// Phase 17.3 — Aggregating E2E entrypoint, PART 2 of 2 (2026-07-01 split).
//
// See `all_tests_part1.dart` for the full rationale. This file carries the
// remaining 13 of 23 flows (updated by the Beautica OTP task Phase B6
// additions, the salon-master booking-bug flow, and the master-home
// add-services CTA flow) so each `flutter test` process in CI reports a
// bounded number of tests instead of aggregating all of them into one
// long-lived run.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'master_appointment_child_booking_actions_flow_test.dart'
    as master_appointment_child_booking_actions;
import 'master_booking_provider_actions_flow_test.dart'
    as master_booking_provider_actions;
import 'master_bookings_flow_test.dart' as master_bookings;
import 'master_home_add_services_flow_test.dart' as master_home_add_services;
import 'master_leave_client_feedback_flow_test.dart'
    as master_leave_client_feedback;
import 'master_profile_address_block_flow_test.dart'
    as master_profile_address_block;
import 'master_received_reviews_flow_test.dart' as master_received_reviews;
import 'passport_flow_test.dart' as passport;
import 'public_master_profile_flow_test.dart' as public_master_profile;
import 'public_salon_profile_flow_test.dart' as public_salon_profile;
import 'register_flow_test.dart' as register;
import 'register_locality_persistence_flow_test.dart'
    as register_locality_persistence;
import 'salon_booking_flow_test.dart' as salon_booking;
import 'salon_service_filter_flow_test.dart' as salon_service_filter;
import 'schedule_edit_flow_test.dart' as schedule_edit;
import 'schedule_first_create_flow_test.dart' as schedule_first_create;
import 'schedule_override_conflict_flow_test.dart'
    as schedule_override_conflict;
import 'service_crud_flow_test.dart' as service_crud;
import 'service_duplicate_flow_test.dart' as service_duplicate;
import 'service_edit_category_type_test.dart' as service_edit_category_type;
import 'service_preselection_flow_test.dart' as service_preselection;
import 'harness_retry_policy_flow_test.dart' as harness_retry_policy;
import 'service_setup_field_error_flow_test.dart' as service_setup_field_error;
import 'settings_change_password_flow_test.dart' as settings_change_password;
import 'support_contact_flow_test.dart' as support_contact;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Master-home zero-services «Додати послуги» CTA → /services/setup
  // (Step 2.7 Rule 3b — master home → service-setup journey).
  // Phase 7.2/7.6 — the INDEPENDENT_MASTER «Мої записи» → day rail →
  // PROVIDER-view booking detail journey (Step 2.7 Rule 3b).
  group('master_bookings_flow', master_bookings.main);
  // Harness ratchet — pins AppHarness.boot's DEFAULT retry predicate to the
  // production one. Not a user journey: it guards the boot policy every other
  // flow in this file inherits.
  group('harness_retry_policy_flow', harness_retry_policy.main);
  // Track 27.x Wave A — the PROVIDER decline/complete round trip against a
  // real HTTP boundary (Step 2.7 Rule 3b).
  group(
    'master_booking_provider_actions_flow',
    master_booking_provider_actions.main,
  );
  // Track 27.x/MO-6 — the same PROVIDER decline/complete round trip, but for
  // an appointment-child (multi-service visit) booking: routes to
  // AppointmentRepository instead of the per-booking endpoints, reschedule
  // hidden (Step 2.7 Rule 3b).
  group(
    'master_appointment_child_booking_actions_flow',
    master_appointment_child_booking_actions.main,
  );
  group('master_home_add_services_flow', master_home_add_services.main);
  // Track 7.x Wave B — the PROVIDER leave-client-feedback journey (detail →
  // «ВІДГУК ПРО КЛІЄНТА» → submit) against a real HTTP boundary (Step 2.7
  // Rule 3b).
  group('master_leave_client_feedback_flow', master_leave_client_feedback.main);
  // Phase 219/220/221 — own-profile split address lines + tap-to-expand
  // location note, driven against a real GET /masters/me response (Step 2.7
  // Rule 3b).
  group('master_profile_address_block_flow', master_profile_address_block.main);
  group('master_received_reviews_flow', master_received_reviews.main);
  group('passport_flow', passport.main);
  group('public_master_profile_flow', public_master_profile.main);
  group('public_salon_profile_flow', public_salon_profile.main);
  group('register_flow', register.main);
  group(
    'register_locality_persistence_flow',
    register_locality_persistence.main,
  );
  group('salon_booking_flow', salon_booking.main);
  group('salon_service_filter_flow', salon_service_filter.main);
  group('schedule_edit_flow', schedule_edit.main);
  group('schedule_first_create_flow', schedule_first_create.main);
  // 2026-07-26 booking-conflict design (Step 2.7 Rule 3b) — save a day-off
  // through the REAL conflict-preview → confirm → write pipeline: no
  // conflicts saves straight through, a conflict gates behind
  // DayOffConflictDialog, confirming declines the conflicting booking,
  // backing out persists nothing at all.
  group('schedule_override_conflict_flow', schedule_override_conflict.main);
  group('service_crud_flow', service_crud.main);
  // Service-create 409 DUPLICATE_SERVICE → inline service-type error, form stays
  // open, never errServer (Step 2.7 Rule 3b — the catalogue duplicate fix E2E).
  group('service_duplicate_flow', service_duplicate.main);
  group('service_edit_category_type', service_edit_category_type.main);
  // Search service-filter → booking pre-selection (Step 2.7 Rule 3b) — exact
  // serviceTypeSlug pre-check on the master + salon booking catalogues.
  group('service_preselection_flow', service_preselection.main);
  // Service-setup per-field 400 → inline row error (Step 2.7 Rule 3b) — the
  // bulk-save validation-error display fix, end-to-end.
  group('service_setup_field_error_flow', service_setup_field_error.main);
  // Beautica OTP task Phase B6 — settings change-password → OTP → forced logout.
  group('settings_change_password_flow', settings_change_password.main);
  group('support_contact_flow', support_contact.main);
}
