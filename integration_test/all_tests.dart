// Phase 17.3 — Aggregating E2E entrypoint (L87 + L88).
//
// CI no longer runs this file directly (2026-07-01): at 19 flows, this single
// long-lived `flutter test` process started crashing the emulator at final
// teardown (see `all_tests_part1.dart` for the full incident). CI now runs
// `all_tests_part1.dart` + `all_tests_part2.dart` instead — the same flows
// (19, 21 after the Beautica OTP task Phase B6 additions, then 22 with the
// salon-master booking-bug flow), split in two.
// This file is kept for local convenience (running the FULL suite in one shot
// against a connected emulator); update all THREE files together when
// adding/removing a flow.
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
import 'client_my_bookings_cancel_flow_test.dart' as client_my_bookings_cancel;
import 'client_my_bookings_pagination_sort_flow_test.dart'
    as client_my_bookings_pagination_sort;
import 'client_my_bookings_partition_flow_test.dart'
    as client_my_bookings_partition;
import 'client_visit_render_flow_test.dart' as client_visit_render;
import 'booking_price_band_flow_test.dart' as booking_price_band;
import 'booking_unknown_status_readonly_flow_test.dart'
    as booking_unknown_status_readonly;
import 'client_elapsed_booking_readonly_flow_test.dart'
    as client_elapsed_booking_readonly;
import 'client_booking_rating_visibility_flow_test.dart'
    as client_booking_rating_visibility;
import 'client_leave_review_flow_test.dart' as client_leave_review;
import 'client_review_refreshes_master_surfaces_flow_test.dart'
    as client_review_refreshes_master_surfaces;
import 'client_review_refreshes_salon_surfaces_flow_test.dart'
    as client_review_refreshes_salon_surfaces;
import 'client_reschedule_flow_test.dart' as client_reschedule;
import 'client_logout_flow_test.dart' as client_logout;
import 'client_profile_location_save_overrides_search_touch_flow_test.dart'
    as client_profile_location_save_overrides_search_touch;
import 'client_profile_settings_flow_test.dart' as client_profile_settings;
import 'client_search_flow_test.dart' as client_search;
import 'client_search_query_with_filters_flow_test.dart'
    as client_search_query_with_filters;
import 'client_search_query_shrink_flow_test.dart'
    as client_search_query_shrink;
import 'search_prefill_survives_name_edit_flow_test.dart'
    as search_prefill_survives_name_edit;
import 'client_shell_flow_test.dart' as client_shell;
import 'shell_nested_push_resolver_contract_test.dart'
    as shell_nested_push_resolver;
import 'client_shell_edge_swipe_back_flow_test.dart'
    as client_shell_edge_swipe_back;
import 'edit_profile_flow_test.dart' as edit_profile;
import 'edit_profile_redirect_flow_test.dart' as edit_profile_redirect;
import 'harness_retry_policy_flow_test.dart' as harness_retry_policy;
import 'forgot_password_otp_flow_test.dart' as forgot_password_otp;
import 'independent_multi_service_booking_flow_test.dart'
    as independent_multi_service_booking;
import 'kyiv_day_boundary_flow_test.dart' as kyiv_day_boundary;
import 'logout_flow_test.dart' as logout;
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
import 'service_favourite_flow_test.dart' as service_favourite;
import 'service_append_flow_test.dart' as service_append;
import 'service_crud_flow_test.dart' as service_crud;
import 'service_duplicate_flow_test.dart' as service_duplicate;
import 'service_edit_category_type_test.dart' as service_edit_category_type;
import 'service_preselection_flow_test.dart' as service_preselection;
import 'service_setup_field_error_flow_test.dart' as service_setup_field_error;
import 'settings_change_password_flow_test.dart' as settings_change_password;
import 'support_contact_flow_test.dart' as support_contact;
import 'velvet_snack_flow_test.dart' as velvet_snack;
import 'wishlist_flow_test.dart' as wishlist;
import 'wishlist_rebook_flow_test.dart' as wishlist_rebook;
import 'wishlist_remove_failure_flow_test.dart' as wishlist_remove_failure;

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
  // Independent-master MULTI-SERVICE booking (Step 2.7 Rule 3b) — two services
  // → two POST /bookings (distinct service/start/key) → success, plus the
  // partial-failure/same-key-retry path (re-authored from the removed
  // client_booking_conflict_flow against the new per-appointment contract).
  group(
    'independent_multi_service_booking_flow',
    independent_multi_service_booking.main,
  );
  // My Bookings → Booking Detail → Cancel journey (Step 2.7 Rule 3b) — the
  // auto-confirm state machine end-to-end against a mutating fake backend.
  group('client_my_bookings_cancel_flow', client_my_bookings_cancel.main);
  // My Bookings pagination/sort regression (Step 2.7 Rule 3b, mobile-qa) —
  // Bug B (dropped `sort` param) + Bug A (per-status fan-out+merge) against a
  // REAL (statuses, sort, page) fake-backend slice, not hand-picked buckets.
  group(
    'client_my_bookings_pagination_sort_flow',
    client_my_bookings_pagination_sort.main,
  );
  // Phase 227 — the headline «Мої записи» server-side `partition` cutover
  // (Step 2.7 Rule 3b, mobile-qa) — an elapsed CONFIRMED booking reclassified
  // into Минулі by a partition-AWARE fake backend (the mocked-repository
  // unit/widget tiers cannot prove this), plus the rollout-safety-valve
  // negative control.
  group('client_my_bookings_partition_flow', client_my_bookings_partition.main);
  // MO-5 — multi-service VISIT render/detail/cancel (Step 2.7 Rule 3b): a
  // visit's per-service `/bookings/me` rows collapse into ONE grouped card, its
  // detail loads via getAppointment, and cancel routes to cancelAppointment
  // (never the per-booking cancelBooking on a child).
  group('client_visit_render_flow', client_visit_render.main);
  // Frozen RANGE price band end-to-end (Step 2.7 Rule 3b, mobile-qa) — a wire
  // `priceMaxAtBooking` surviving deserialization → BookingMapper →
  // Booking.priceMax → priceLabel onto the CLIENT list card, «Деталі запису»
  // and the add-to-calendar export, plus the MASTER timeline card and the
  // "null ceiling is a single price, not a missing value" case. Registered in
  // PART 1 beside the other bookings flows (the split is a process split, not
  // a semantic one) even though its second test drives the master surface.
  group('booking_price_band_flow', booking_price_band.main);
  // Elapsed CONFIRMED booking → read-only detail (Step 2.7 Rule 3b) — same
  // harness/detail as the cancel flow, but the seed window is pushed into the
  // past so reschedule + cancel + add-to-calendar drop away and only
  // «Записатись знову» is offered.
  // Unrecognised backend status → read-only, powerless detail (Step 2.7
  // Rule 3b, security S1) — the `BookingStatus.unknown` decode contract driven
  // from the WIRE, which no widget test can reach: the row must survive the
  // mapper (it used to be silently DROPPED) and must grant nothing (it used to
  // fall back to CONFIRMED, unlocking the local add-to-calendar write).
  group(
    'booking_unknown_status_readonly_flow',
    booking_unknown_status_readonly.main,
  );
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
  // CLIENT review-staleness regression (Step 2.7 Rule 3b, mobile-qa) — the
  // REPORTED bug: a client who viewed a master's public profile, then left a
  // review WITHOUT restarting the app, saw a stale rating / review count and
  // none of their own review. The three master surfaces are independent
  // 5-minute `keepAlive` caches; `invalidateMasterReviewSurfaces` fans out to
  // all of them (all four review SORT buckets included).
  group(
    'client_review_refreshes_master_surfaces_flow',
    client_review_refreshes_master_surfaces.main,
  );
  // Phase 233 — the SALON half of the same bug, unblocked by phase 232's
  // `Booking.salonId`. Same journey, same three independent 5-minute
  // `keepAlive` caches, keyed on the salon instead of the master;
  // `invalidateSalonReviewSurfaces` fans out to all of them (all four salon
  // SORT buckets included). The fake's salon aggregate is seeded SMALL and
  // reconciled (4.0 → 4.2 across five reviews) so the assertions can tell a
  // genuine refetch from a cache hit BY VALUE.
  group(
    'client_review_refreshes_salon_surfaces_flow',
    client_review_refreshes_salon_surfaces.main,
  );
  // Phase 240 rating visibility (Step 2.7 Rule 3b, mobile-qa) — the REPORTED
  // bug's journey: a master's rating reaching «Деталі запису» and «Залишити
  // відгук» off the WIRE (which no mocked-repository tier can prove), and
  // BOTH cards taping through to that master's public reviews. Plus the
  // pre-240 stale-`0.0`-with-absent-count negative control, which is a
  // property of the wire alone.
  group(
    'client_booking_rating_visibility_flow',
    client_booking_rating_visibility.main,
  );

  group('client_home_hub_flow', client_home_hub.main);
  group('client_logout_flow', client_logout.main);
  group('client_profile_settings_flow', client_profile_settings.main);
  group('client_search_flow', client_search.main);
  // Search-query + filters SIMULTANEITY (Step 2.7 Rule 3b) — a Cyrillic `q`
  // reaching /search/masters + /search/salons TOGETHER with location.cityId,
  // category and a price bound on the SAME request, plus the results
  // screen receiving them intact. (The results screen no longer hosts a search
  // field; the shrink/below-minimum contract lives in the flow below.)
  group(
    'client_search_query_with_filters_flow',
    client_search_query_with_filters.main,
  );
  // Search-query SHRINK round trip (Step 2.7 Rule 3b) — the direction every
  // other search test misses. Applies «манікюр», renders its results, goes
  // back, shortens to «ма» and asserts the error state, the blocked CTA, the
  // surviving typed characters and — the original defect — that the stale
  // result set is genuinely unreachable (no second GET for the pre-shrink
  // term). Plus the empty-box escape hatch.
  group('client_search_query_shrink_flow', client_search_query_shrink.main);
  // Search prefill survives a mid-session name edit (refreshUser) — the
  // `.select(user.id)` narrowing regression (Step 2.7 Rule 3b).
  group(
    'search_prefill_survives_name_edit_flow',
    search_prefill_survives_name_edit.main,
  );
  // Five-times-patched regression (Step 2.7 Rule 3b, mobile-qa) — a profile-
  // location save must ALWAYS win over an earlier manual pick made through
  // Пошук's OWN locality picker (`_userTouchedLocality`), composing all three
  // legs (Search's real picker touch → real routing to Location edit → real
  // save → real ClientShell tab switch back into Search) that no single
  // existing flow covers together.
  group(
    'client_profile_location_save_overrides_search_touch_flow',
    client_profile_location_save_overrides_search_touch.main,
  );
  group('client_shell_flow', client_shell.main);
  // AppHarness location-resolver contract (2026-07-31 debug chain): a
  // context.push onto a shell-nested leaf (/bookings/:bookingId) must leave
  // location() on the stale branch root while nestedPushLocation() sees the
  // leaf — pins the two resolvers apart so neither can be quietly conflated.
  group('shell_nested_push_resolver_contract', shell_nested_push_resolver.main);
  // CLIENT left-edge swipe-back → Home tab (Step 2.7 Rule 3b) — the gesture
  // twin of the R1 system-back flow in client_shell_flow_test.dart Test 7.
  group('client_shell_edge_swipe_back_flow', client_shell_edge_swipe_back.main);
  group('edit_profile_flow', edit_profile.main);
  group('edit_profile_redirect_flow', edit_profile_redirect.main);
  // Beautica OTP task Phase B6 — forgot-password email → OTP → new password.
  group('forgot_password_otp_flow', forgot_password_otp.main);
  // Harness ratchet — pins AppHarness.boot's DEFAULT retry predicate to the
  // production one. Not a user journey: it guards the boot policy every other
  // flow in this file inherits.
  group('harness_retry_policy_flow', harness_retry_policy.main);
  group('logout_flow', logout.main);
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
