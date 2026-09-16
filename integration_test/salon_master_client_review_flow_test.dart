// Phase 333 / 334 — E2E: the SALON_MASTER's client-review journey.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b — integration-test gate)
// --------------------------------------------------------------
// Two separate capabilities land on the SAME screen for a role that previously
// could not reach it at all, and each already has a bespoke widget-tier test
// that pins one slice against a hand-built `GoRouter` + container:
//
//   • M333 — the read-only SALON_MASTER keeps the «Залишити відгук про
//     клієнта» CTA. `booking_detail_client_feedback_cta_test.dart` proves the
//     CTA's presence/push in isolation; `leave_client_feedback_screen_test`
//     proves the form against a MOCKED `ClientReviewRepository`.
//   • Phase 334 — «Відгук клієнта», the client's own review rendered back to
//     the provider, gated on `Booking.reviewByClient` being non-null, which
//     ONLY `GET /bookings/{id}` ever answers.
//
// Neither tier drives any of this:
//   • the REAL `/staff/**` admission in `auth_redirect.dart` letting a
//     SALON_MASTER reach `/staff/bookings/:id` AND `/staff/bookings/:id/review`
//     through the ACTUAL redirect callback wired into `appRouter`;
//   • the REAL route-order resolution (`/staff/bookings/archive` declared
//     before `/staff/bookings/:bookingId`) survived by a REAL navigation;
//   • the REAL `clientReviewRouteBuilder` / `detailRouteBuilder` overrides
//     keeping every push inside the `/staff/*` subtree rather than bouncing
//     off the `/master/*` gate;
//   • the phase-331 read-only gate sitting BELOW the COMPLETED arm in
//     `_providerActions`, i.e. the CTA surviving for a role whose transition
//     buttons are all suppressed;
//   • the REAL wire body of `POST /client-reviews` (a mocked-repository test
//     proves the DART call site is right; it cannot prove the WIRE is);
//   • the REAL `GET /bookings/{id}` → `BookingMapper` → `ClientReviewSection`
//     chain for phase 334's `reviewByClient`, which no listing ever carries.
//
// Modelled on `salon_master_bookings_nav_flow_test.dart` (the sibling journey
// for the same role) and `master_archive_review_flow_test.dart` (the same
// review journey for the INDEPENDENT_MASTER). The archive is the entry point
// because a COMPLETED booking is where `providerCanReviewClient` turns true,
// and the archive is where a salon master's COMPLETED bookings live
// (app_router.dart's own phase-332 comment on that route).
//
// ANTI-VACUITY (M14). Every ABSENCE assertion here is paired, in the SAME
// pump, with a PRESENCE assertion on unrelated detail-screen chrome
// (`booking-detail-back`, which only `_DetailBody` draws — never the loading
// or error scaffold). Without that pairing a `findsNothing` would pass
// identically on a blank page, a spinner, or an error state.
//
// NO PATROL FLOW: nothing here touches an OS permission dialog, a deep link,
// FCM/local notifications, a WebView or a biometric prompt. It is a pure
// screen / route / provider / GET+POST journey, so Step 2.7 Rule 3b's
// `integration_test/patrol/` requirement does not apply. Stated explicitly
// (mobile-qa), not omitted.
//
// FINDERS: widget Keys and widget TYPES only. The one `find.text` is on the
// review COMMENT, which is fixture DATA (the client's own words echoed back
// verbatim), not UI copy — identical in every locale.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/leave_client_feedback_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/master_archive_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/master_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/client_review_section.dart';
import 'package:beautica_mobile/features/master/presentation/salon_master_profile_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/overflow_guard.dart';
import '../test/helpers/velvet_snack_matchers.dart';
import 'support/app_harness.dart';

/// The client's review COMMENT the fake serves on `GET /bookings/booking-1`.
///
/// Fixture DATA, not UI copy — the app echoes it back byte-for-byte in every
/// locale, so asserting on it is locale-independent (unlike a `find.text` on a
/// translated label, which `forbid_cyrillic_finder.sh` exists to stop).
const String _kClientReviewComment = 'Майстриня чудова, все сподобалось.';

/// The rating the SALON_MASTER taps in scenario 1.
///
/// Deliberately NOT 5 (the value every sibling flow submits) and NOT the
/// `reviewByClient` fixture's own 4: `FakeBackend.lastClientReviewRating`
/// starts `null` and no other seed carries a 3, so the post-submit assertion
/// can only go green if THIS tap actually travelled the wire (a fixture value
/// that already equals the expectation asserts nothing).
const int _kSubmittedRating = 3;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  AppLocalizations l10nOf(WidgetTester tester, Type screen) =>
      AppLocalizations.of(tester.element(find.byType(screen)));

  /// A far-past instant, deterministic regardless of the runner's wall clock
  /// or `TZ`. Same reasoning as `master_archive_review_flow_test.dart`'s
  /// helper of the same name: `FakeBackend._partitionOf` compares against
  /// `serverNow` (the harness's injected [kFixedNow]), so only a genuinely
  /// far-past instant classifies into the archive's PAST list whenever this
  /// suite happens to run. Fixture clock and app clock are therefore the SAME
  /// clock — the invariant that matters (M15), not "never read now()".
  DateTime elapsedStart(int daysBeforeFixedNow) =>
      kFixedNow.subtract(Duration(days: daysBeforeFixedNow, hours: 2));

  /// Seeds `booking-1` as a finished, still-reviewable visit on BOTH surfaces
  /// the journey touches: the archive LIST row (`seedManyBookingsDataset`) and
  /// the single-booking DETAIL fetch (the fake's top-level mutable fields,
  /// which `_seededBookingJson` is built from). The two must agree or the
  /// pushed detail screen shows a different booking than the card tapped.
  FakeBackend seedCompletedBooking() {
    final fb = FakeBackend()..currentRole = UserRole.salonMaster;
    final DateTime start = elapsedStart(2);
    fb.seedManyBookingsDataset(<Map<String, dynamic>>[
      fb.datasetBookingRow(
        id: 'booking-1',
        status: 'COMPLETED',
        startsAt: start,
        providerCanReviewClient: true,
      ),
    ]);
    fb.bookingStatus = 'COMPLETED';
    fb.bookingStartsAt = start.toIso8601String();
    fb.bookingEndsAt = start.add(const Duration(minutes: 90)).toIso8601String();
    // Explicit even though it is already the fake's default, so these tests do
    // not silently depend on that default.
    fb.bookingProviderCanReviewClient = true;
    return fb;
  }

  /// Cold start → REAL login as the fixture SALON_MASTER → «Записи» nav tile →
  /// header archive button → [MasterArchiveScreen] at
  /// `/staff/bookings/archive`. Every step is a real tap through the real
  /// router; nothing is pushed imperatively.
  Future<GoRouter> openArchive(WidgetTester tester, FakeBackend fb) async {
    final GoRouter router = await AppHarness.boot(tester, fb);
    await AppHarness.loginAs(tester, fb, UserRole.salonMaster);
    await AppHarness.settle(tester);

    expect(find.byType(SalonMasterProfileScreen), findsOneWidget);
    AppHarness.expectLocation(router, RouteNames.salonMasterProfile);

    await AppHarness.tapVisible(
      tester,
      find.byKey(const Key('master-nav-tile-1')),
    );
    await AppHarness.settle(tester);
    // Pin the resolved page TYPE, not the location string alone — a string
    // assertion passes under go_router's literal-before-dynamic shadowing even
    // when a different page built.
    expect(find.byType(MasterBookingsScreen), findsOneWidget);
    AppHarness.expectLocation(router, RouteNames.salonMasterBookings);

    await AppHarness.tapVisible(
      tester,
      find.byKey(const Key('master-bookings-open-archive')),
    );
    await AppHarness.settle(tester);
    expect(find.byType(MasterArchiveScreen), findsOneWidget);
    AppHarness.expectNestedPushLocation(
      router,
      RouteNames.salonMasterBookingsArchive,
    );
    return router;
  }

  /// [openArchive] + a real tap on the archive ROW (not its «Відгук» slot),
  /// landing on `/staff/bookings/booking-1`.
  Future<GoRouter> openBookingDetail(
    WidgetTester tester,
    FakeBackend fb,
  ) async {
    final GoRouter router = await openArchive(tester, fb);

    expect(
      find.byKey(const Key('master-booking-card-booking-1')),
      findsOneWidget,
      reason: 'the COMPLETED booking must be listed in the archive',
    );
    await AppHarness.tapVisible(
      tester,
      find.byKey(const Key('master-booking-card-booking-1')),
    );
    await AppHarness.settle(tester);

    expect(find.byType(BookingDetailScreen), findsOneWidget);
    AppHarness.expectNestedPushLocation(
      router,
      RouteNames.salonMasterBookingDetail('booking-1'),
    );
    return router;
  }

  /// The detail screen's own loaded-body chrome — drawn by `_DetailBody`
  /// ONLY, never by the loading or error scaffold. Every `findsNothing`
  /// assertion in this file is paired with this one so an absence can never
  /// pass because the screen failed to render (M14).
  void expectDetailBodyRendered() {
    expect(
      find.byKey(const Key('booking-detail-back')),
      findsOneWidget,
      reason:
          'ANTI-VACUITY — `_DetailBody` must actually be on screen, otherwise '
          'the absence assertion beside this one would pass on a spinner, an '
          'error state, or a blank page.',
    );
  }

  // ==========================================================================
  // 1. THE LOAD-BEARING CASE — the full M333 journey, end to end.
  // ==========================================================================
  testWidgets(
    'SALON_MASTER walks profile → «Записи» → «Архів» → a COMPLETED booking\'s '
    'detail, and the «Залишити відгук про клієнта» CTA takes them to the REAL '
    'form at /staff/bookings/booking-1/review, whose submit puts the exact '
    'bookingId + rating on a REAL POST /client-reviews',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final FakeBackend fb = seedCompletedBooking();
        final GoRouter router = await openBookingDetail(tester, fb);

        expectDetailBodyRendered();

        // ── M333: the read-only role KEEPS the review CTA ─────────────────
        // `_providerActions` gates it on `providerCanReviewClient` in the
        // COMPLETED arm, which sits ABOVE the phase-331 `transitionsEnabled`
        // read-only gate on purpose. If that ordering is ever swapped this
        // goes red — which is the whole point of asserting it through the
        // real session rather than a hand-built container.
        expect(
          find.byKey(const Key('booking-detail-leave-client-feedback')),
          findsOneWidget,
          reason:
              'a SALON_MASTER is read-only for TRANSITIONS, not for reviews — '
              'backend phase 316 grants this role exactly this one write',
        );

        // ── Tap it → the form is PUSHED inside the /staff/* subtree ───────
        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('booking-detail-leave-client-feedback')),
        );
        await AppHarness.settle(tester);

        expect(find.byType(LeaveClientFeedbackScreen), findsOneWidget);
        AppHarness.expectNestedPushLocation(
          router,
          RouteNames.salonMasterClientReview('booking-1'),
        );

        // The FORM, not `_NotReviewable`. Both render inside
        // `LeaveClientFeedbackScreen`, so `findsOneWidget` on the screen type
        // alone cannot tell them apart — assert the star input and the submit
        // button, which only the form branch draws, and the unavailable
        // branch's own back button's ABSENCE.
        expect(
          find.byKey(const Key('leave-client-feedback-stars')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('leave-client-feedback-submit')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('leave-client-feedback-unavailable-back')),
          findsNothing,
          reason:
              'the pre-gate must have resolved REVIEWABLE — if this role ever '
              'gets a 403/409 on the detail pre-fetch the form silently '
              'degrades to `_NotReviewable`, and every assertion below would '
              'then be about a screen the master cannot act on',
        );

        // ── Rate + submit ─────────────────────────────────────────────────
        await AppHarness.tapVisible(
          tester,
          find.byKey(const ValueKey<String>('review-star-$_kSubmittedRating')),
        );
        await AppHarness.settle(tester);

        final AppLocalizations feedbackL10n = l10nOf(
          tester,
          LeaveClientFeedbackScreen,
        );

        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('leave-client-feedback-submit')),
        );
        await AppHarness.settle(tester);

        // ── The REAL wire body, not a Dart-level mock argument ────────────
        expect(
          fb.createClientReviewCalls,
          1,
          reason: 'exactly one POST /client-reviews reached the backend',
        );
        expect(fb.lastClientReviewBookingId, 'booking-1');
        expect(
          fb.lastClientReviewRating,
          _kSubmittedRating,
          reason:
              'the rating tapped must be the rating serialized — 3 appears in '
              'no fixture, so this cannot pass on a default',
        );

        expectVelvetSnack(
          feedbackL10n.clientReviewSubmitSuccess,
          variant: VelvetSnackVariant.success,
        );
        expect(
          find.byType(LeaveClientFeedbackScreen),
          findsNothing,
          reason: 'a successful submit pops back to the detail',
        );
        expect(find.byType(BookingDetailScreen), findsOneWidget);
        AppHarness.expectNestedPushLocation(
          router,
          RouteNames.salonMasterBookingDetail('booking-1'),
        );

        // Drain the dwell Timer so none is pending at teardown.
        await pumpPastVelvetSnack(tester);
      });
    },
  );

  // ==========================================================================
  // 2. The CTA obeys the SERVER, not the role.
  // ==========================================================================
  testWidgets(
    'CONTROL — when the server answers providerCanReviewClient=false the CTA '
    'is absent from the SAME screen reached by the SAME journey',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final FakeBackend fb = seedCompletedBooking()
          ..bookingProviderCanReviewClient = false;

        await openBookingDetail(tester, fb);

        expectDetailBodyRendered();
        expect(
          find.byKey(const Key('booking-detail-leave-client-feedback')),
          findsNothing,
          reason:
              'the CTA is server-gated, not role-gated: the identical '
              'SALON_MASTER session that shows it above must not show it once '
              'the booking says the client is already reviewed',
        );
      });
    },
  );

  // ==========================================================================
  // 3. Phase 334 — the client's review renders back to the SALON_MASTER.
  // ==========================================================================
  testWidgets(
    'Phase 334 — «Відгук клієнта» renders on the SALON_MASTER\'s detail '
    'screen when GET /bookings/{id} carries reviewByClient',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final FakeBackend fb = seedCompletedBooking()
          ..bookingReviewByClient = <String, Object?>{
            'rating': 4,
            'comment': _kClientReviewComment,
          };

        await openBookingDetail(tester, fb);
        expectDetailBodyRendered();

        // `-d flutter-tester` is 800x600 and the recap column scrolls; the
        // section is LAST in it (deliberately — see the render site's comment)
        // so it is below the fold on this window. The body is a
        // `SingleChildScrollView`, so the element exists and `ensureVisible`
        // can reach it; a `findsOneWidget` alone would not prove the provider
        // can actually SEE it.
        final Finder section = find.byType(ClientReviewSection);
        expect(section, findsOneWidget);
        await tester.ensureVisible(section);
        await AppHarness.settle(tester);

        expect(
          find.byKey(const Key('client-review-booking-1')),
          findsOneWidget,
          reason:
              'the shared ReviewCard keyed by the BOOKING id — the review '
              'payload carries no id of its own',
        );
        // Fixture DATA echoed verbatim, not UI copy — see the const's doc.
        expect(find.text(_kClientReviewComment), findsOneWidget);
      });
    },
  );

  // ==========================================================================
  // 4. No review → no section, and no empty state either.
  // ==========================================================================
  testWidgets(
    'Phase 334 — with no reviewByClient on the wire the section is absent '
    'entirely (no placeholder), on a detail screen proven to have rendered',
    (tester) async {
      await mockNetworkImagesFor(() async {
        // `bookingReviewByClient` left null → the fake omits the key entirely,
        // exactly as the real backend does for an unreviewed booking.
        final FakeBackend fb = seedCompletedBooking();

        await openBookingDetail(tester, fb);

        expectDetailBodyRendered();
        expect(
          find.byType(ClientReviewSection),
          findsNothing,
          reason:
              'a null review draws NOTHING — deliberately no «Відгуку немає» '
              'placeholder, because on every listing surface a null means '
              '"this surface does not answer that question"',
        );
        expect(find.byKey(const Key('client-review-booking-1')), findsNothing);
      });
    },
  );
}
