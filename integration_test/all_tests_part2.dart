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

import 'kyiv_day_boundary_flow_test.dart' as kyiv_day_boundary;
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
import 'salon_service_favourite_flow_test.dart' as salon_service_favourite;
import 'salon_service_filter_flow_test.dart' as salon_service_filter;
import 'schedule_edit_flow_test.dart' as schedule_edit;
import 'schedule_first_create_flow_test.dart' as schedule_first_create;
import 'schedule_override_conflict_flow_test.dart'
    as schedule_override_conflict;
import 'service_favourite_flow_test.dart' as service_favourite;
import 'service_append_flow_test.dart' as service_append;
import 'service_crud_flow_test.dart' as service_crud;
import 'service_duplicate_flow_test.dart' as service_duplicate;
import 'service_edit_category_type_test.dart' as service_edit_category_type;
import 'service_preselection_flow_test.dart' as service_preselection;
import 'harness_retry_policy_flow_test.dart' as harness_retry_policy;
import 'service_setup_field_error_flow_test.dart' as service_setup_field_error;
import 'settings_change_password_flow_test.dart' as settings_change_password;
import 'support_contact_flow_test.dart' as support_contact;
import 'velvet_snack_flow_test.dart' as velvet_snack;
import 'wishlist_flow_test.dart' as wishlist;
import 'wishlist_rebook_flow_test.dart' as wishlist_rebook;
import 'wishlist_remove_failure_flow_test.dart' as wishlist_remove_failure;
import 'wishlist_salon_service_redirect_flow_test.dart'
    as wishlist_salon_service_redirect;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Master-home zero-services «Додати послуги» CTA → /services/setup
  // (Step 2.7 Rule 3b — master home → service-setup journey).
  // Phase 7.2/7.6 — the INDEPENDENT_MASTER «Мої записи» → day rail →
  // PROVIDER-view booking detail journey (Step 2.7 Rule 3b).
  group('master_bookings_flow', master_bookings.main);
  // Kyiv-day-authority audit (backlog :226, mobile-qa 2026-08-02) — pins the
  // «Мої записи» day-scoped landing fetch AND the booked-days rail window to
  // the KYIV calendar day, never the UTC/device one, against a real
  // fake-backed HTTP boundary (Step 2.7 Rule 3b). Registered here, beside
  // `master_bookings_flow`, whose screen it drives.
  group('kyiv_day_boundary_flow', kyiv_day_boundary.main);
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
  // Phase 239 — the wish list's own journey: the nested /passport/wishlist
  // push, the shared-notifier removal across both surfaces, and the LAST
  // removal asserted mid-flight. Registered beside passport_flow because the
  // two share the same page and the same fake-backend fixtures.
  group('wishlist_flow', wishlist.main);
  // Phase 241 (mobile-qa) — «Записатись» rebooks a wish-list entry into the
  // REAL booking flow (pre-seeded + slot-scoped), plus the stale-service 404
  // race surfacing as a normal booking-flow failure and dropping the dead
  // entry afterward.
  group('wishlist_rebook_flow', wishlist_rebook.main);
  // mobile-qa (2026-08-08) — the FAILED un-favourite: optimistic removal
  // asserted mid-flight, restore at the ORIGINAL index (not appended), and
  // the failure snack. Closes the last known Beauty Passport track gap.
  group('wishlist_remove_failure_flow', wishlist_remove_failure.main);
  // Phase G — a SALON-sourced favourite redirects to the salon's own
  // profile, Майстри tab, filtered to the favourited service (never the
  // salon booking flow — Phase F's reversed cut). Registered beside the
  // other wishlist flows because it shares their fixtures and harness.
  group(
    'wishlist_salon_service_redirect_flow',
    wishlist_salon_service_redirect.main,
  );
  group('public_master_profile_flow', public_master_profile.main);
  group('public_salon_profile_flow', public_salon_profile.main);
  group('register_flow', register.main);
  group(
    'register_locality_persistence_flow',
    register_locality_persistence.main,
  );
  group('salon_booking_flow', salon_booking.main);
  // Phase F — a real heart tap on the salon catalogue POSTs a SALON_SERVICE
  // favorite that the Beauty Passport genuinely reads back as a SALON row.
  // The MASTER-arm sibling of `service_favourite_flow`, registered beside it.
  group('salon_service_favourite_flow', salon_service_favourite.main);
  group('salon_service_filter_flow', salon_service_filter.main);
  group('schedule_edit_flow', schedule_edit.main);
  group('schedule_first_create_flow', schedule_first_create.main);
  // 2026-07-26 booking-conflict design (Step 2.7 Rule 3b) — save a day-off
  // through the REAL conflict-preview → confirm → write pipeline: no
  // conflicts saves straight through, a conflict gates behind
  // DayOffConflictDialog, confirming declines the conflicting booking,
  // backing out persists nothing at all.
  group('schedule_override_conflict_flow', schedule_override_conflict.main);
  // Phase 240 (mobile-qa) — hearting a SERVICE on the booking service-
  // selection sheet is a REAL POST /favorites; the wish list read-back is the
  // "origin story" the phase exists for.
  group('service_favourite_flow', service_favourite.main);
  // APPEND: a master WITH a catalogue opens /services/setup from the list FAB,
  // the type they already offer renders inert, and the bulk POST carries only
  // the new one (Step 2.7 Rule 3b — the one-screen add-services consolidation).
  group('service_append_flow', service_append.main);
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
  // VelvetSnack AS A FEATURE (mobile-qa, Step 2.7 Rule 3b) — a real
  // failure-path error snack raised + auto-retired, a success snack
  // surviving the context.pop() that follows it, and single-slot
  // pre-emption against a real (non-same-tick) second trigger.
  group('velvet_snack_flow', velvet_snack.main);
}
