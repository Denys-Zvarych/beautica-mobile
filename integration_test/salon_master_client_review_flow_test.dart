// Phase 333 / 334 / 386 — E2E: the SALON_MASTER's client-review journey.
// Phase 386 (backend 355) FLIPPED scenario 1: a SALON_MASTER never sees the
// «Залишити відгук про клієнта» CTA; the M333 narrative below is historical.
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

import 'dart:async';

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/leave_client_feedback_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/master_archive_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/master_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/client_review_section.dart';
import 'package:beautica_mobile/features/master/presentation/salon_master_profile_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

/// The client's review COMMENT the fake serves on `GET /bookings/booking-1`.
///
/// Fixture DATA, not UI copy — the app echoes it back byte-for-byte in every
/// locale, so asserting on it is locale-independent (unlike a `find.text` on a
/// translated label, which `forbid_cyrillic_finder.sh` exists to stop).
const String _kClientReviewComment = 'Майстриня чудова, все сподобалось.';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

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
  // 1. THE LOAD-BEARING CASE - phase 386 (backend 355): a SALON_MASTER never
  //    rates the client. This REPLACES the phase-333 journey in which the
  //    read-only role kept the CTA.
  // ==========================================================================
  testWidgets('Phase 386 - SALON_MASTER on a COMPLETED booking whose seed says '
      'reviewable never sees the CTA, a directly pushed review route shows the '
      'ineligible state, and POST /client-reviews is never called', (
    tester,
  ) async {
    await mockNetworkImagesFor(() async {
      // The raw seed is `true`: only the role-aware fake (the real server's
      // phase-355 rule) turns it into `false` for this viewer.
      final FakeBackend fb = seedCompletedBooking();
      final GoRouter router = await openBookingDetail(tester, fb);

      expectDetailBodyRendered();
      expect(
        find.byKey(const Key('booking-detail-leave-client-feedback')),
        findsNothing,
        reason:
            'backend 355: a SALON_MASTER is never offered the client '
            'review, even on a booking they performed',
      );

      // Deep-link style push of the form route: the screen pre-gates on the
      // fresh detail and must degrade to the ineligible state.
      unawaited(router.push(RouteNames.salonMasterClientReview('booking-1')));
      await AppHarness.settle(tester);

      expect(find.byType(LeaveClientFeedbackScreen), findsOneWidget);
      expect(
        find.byKey(const Key('leave-client-feedback-unavailable-back')),
        findsOneWidget,
        reason: 'POSITIVE: the ineligible branch actually rendered',
      );
      expect(
        find.byKey(const Key('leave-client-feedback-submit')),
        findsNothing,
      );
      expect(fb.createClientReviewCalls, 0);
    });
  });

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
