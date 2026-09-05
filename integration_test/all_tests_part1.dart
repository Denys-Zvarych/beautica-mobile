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
import 'salon_owner_landing_flow_test.dart' as salon_owner_landing;
import 'salon_shell_landing_flow_test.dart' as salon_shell_landing;
import 'owner_own_profile_flow_test.dart' as owner_own_profile;
import 'salon_shell_tab_sync_flow_test.dart' as salon_shell_tab_sync;
import 'client_home_hub_flow_test.dart' as client_home_hub;
import 'client_favorites_flow_test.dart' as client_favorites;
import 'client_my_bookings_cancel_flow_test.dart' as client_my_bookings_cancel;
import 'client_my_bookings_pagination_sort_flow_test.dart'
    as client_my_bookings_pagination_sort;
import 'client_my_bookings_partition_flow_test.dart'
    as client_my_bookings_partition;
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
import 'client_visit_render_flow_test.dart' as client_visit_render;
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
import 'forgot_password_otp_flow_test.dart' as forgot_password_otp;
import 'independent_multi_service_booking_flow_test.dart'
    as independent_multi_service_booking;
import 'logout_flow_test.dart' as logout;
import 'salon_management_profile_flow_test.dart' as salon_management_profile;
import 'salon_edit_forms_flow_test.dart' as salon_edit_forms;
import 'register_salon_flow_test.dart' as register_salon;
import 'salon_pending_invites_flow_test.dart' as salon_pending_invites;
import 'salon_staff_settings_flow_test.dart' as salon_staff_settings;
import 'salon_staff_settings_admin_gate_flow_test.dart'
    as salon_staff_settings_admin_gate;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('auth_login_flow', auth_login.main);
  // Phase 21.1 — SALON_OWNER landing regression (the Step 5 fix): fresh
  // login AND the post-registration done_to_app CTA both land on the My
  // Salons Hub, never the pre-Phase-21.1 `/` placeholder.
  group('salon_owner_landing_flow', salon_owner_landing.main);
  group('salon_shell_landing_flow', salon_shell_landing.main);
  // Phase 21.14 — the owner's own «Профіль» tab: the shell slot-2 swap plus
  // the `hasMasterProfile` tri-state and its 404 degrade, over the wire.
  group('owner_own_profile_flow', owner_own_profile.main);
  group('salon_shell_tab_sync_flow', salon_shell_tab_sync.main);
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
  // Phase 227 — the headline «Мої записи» server-side `partition` cutover
  // (Step 2.7 Rule 3b, mobile-qa) — an elapsed CONFIRMED booking reclassified
  // into Минулі by a partition-AWARE fake backend (the mocked-repository
  // unit/widget tiers cannot prove this), plus the rollout-safety-valve
  // negative control.
  group('client_my_bookings_partition_flow', client_my_bookings_partition.main);
  // Frozen RANGE price band end-to-end (Step 2.7 Rule 3b, mobile-qa) — a wire
  // `priceMaxAtBooking` surviving deserialization → BookingMapper →
  // Booking.priceMax → priceLabel onto the CLIENT list card, «Деталі запису»
  // and the add-to-calendar export, plus the MASTER timeline card and the
  // "null ceiling is a single price, not a missing value" case. Registered in
  // PART 1 beside the other bookings flows (the split is a process split, not
  // a semantic one) even though its second test drives the master surface.
  group('booking_price_band_flow', booking_price_band.main);
  // Elapsed CONFIRMED booking → read-only detail (Step 2.7 Rule 3b).
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

  // CLIENT multi-service VISIT journey (Step 2.7 Rule 3b) — a multi-service
  // visit renders as separate per-booking cards (no grouping), and cancelling
  // one leg routes through the per-booking `cancelBooking`, never any
  // appointment-level endpoint. The whole-visit review leg this used to also
  // cover was removed with `VisitDetailScreen`/`AppointmentReviewScreen` — see
  // `client_visit_render_flow_test.dart`'s header.
  group('client_visit_render_flow', client_visit_render.main);
  group('client_home_hub_flow', client_home_hub.main);
  group('client_favorites_flow', client_favorites.main);
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
  // CLIENT left-edge swipe-back → Home tab (Step 2.7 Rule 3b) — the gesture
  // twin of the R1 system-back flow in client_shell_flow_test.dart Test 7.
  group('client_shell_edge_swipe_back_flow', client_shell_edge_swipe_back.main);
  // AppHarness location-resolver contract (2026-07-31 debug chain): a
  // context.push onto a shell-nested leaf (/bookings/:bookingId) must leave
  // location() on the stale branch root while nestedPushLocation() sees the
  // leaf — pins the two resolvers apart so neither can be quietly conflated.
  group('shell_nested_push_resolver_contract', shell_nested_push_resolver.main);
  group('edit_profile_flow', edit_profile.main);
  group('edit_profile_redirect_flow', edit_profile_redirect.main);
  // Beautica OTP task Phase B6 — forgot-password email → OTP → new password.
  group('forgot_password_otp_flow', forgot_password_otp.main);
  group('logout_flow', logout.main);
  // Phase 21.2 QA follow-up (Step 2.7 Rule 3b) — SALON_OWNER editable salon
  // profile: real login → salonManageGuard admits a real session → PATCH
  // dirty-diff proven on the real wire body (mandate 3) → DELETE.
  group('salon_management_profile_flow', salon_management_profile.main);
  // Phase 21.10 QA follow-up (Step 2.7 Rule 3b) — the three new edit-form
  // routes (profile/address/contacts) reachable end-to-end via a real
  // SALON_OWNER session, plus the address form's locality-PAIR dirty-diff
  // regression pin (cityId/districtId diffed independently can submit an
  // invalid pair — see the file's own header doc).
  group('salon_edit_forms_flow', salon_edit_forms.main);
  // Phase 21.3 QA follow-up (Step 2.7 Rule 3b) — SALON_OWNER registers a new
  // salon end to end: real hub -> real «+ Додати салон» CTA push -> real
  // form fill -> real POST /api/v1/salons -> real pop -> the new salon
  // rendered on the hub via the real ref.invalidate(mySalonsProvider)
  // refetch, no manual refresh.
  group('register_salon_flow', register_salon.main);
  // Phase 21.11 QA follow-up (Step 2.7 Rule 3b) — «Надіслані запрошення»:
  // real settings-hub row push -> real GET /invites/pending -> real per-row
  // DELETE -> the cancel PERSISTS across a genuine autoDispose refetch (the
  // one thing an optimistic client-side removal cannot be told apart from at
  // the widget tier). Also carries the deliberately-RED pin for the missing
  // `pendingInvitesProvider` invalidation on invite-send.
  group('salon_pending_invites_flow', salon_pending_invites.main);
  group('salon_staff_settings_flow', salon_staff_settings.main);
  group(
    'salon_staff_settings_admin_gate_flow',
    salon_staff_settings_admin_gate.main,
  );
}
