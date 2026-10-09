// Phase 386 (backend 355 + 356) - E2E: the SALON_OWNER and SALON_ADMIN complete
// a salon booking and rate the client.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b - integration-test gate)
// ---------------------------------------------------------------
// At a salon only the owner and the assigned admin complete a booking and rate
// the client; a SALON_MASTER does neither (see
// `salon_master_client_review_flow_test.dart`). The admin leg was dead until
// backend 356: both `BookingDetailScreen` and `LeaveClientFeedbackScreen` load
// via `GET /bookings/{id}`, which 403'd for an admin. Widget tiers mock the
// repository and cannot prove the REAL chain:
//   salon board -> tap booking -> `/salon/bookings/:id` detail -> «Завершити»
//   (PATCH /complete) -> server-gated CTA -> `/salon/bookings/:id/review` ->
//   rating + comment -> POST /client-reviews -> back on detail, CTA gone.
//
// ANTI-VACUITY: every absence assertion is paired with a presence assertion on
// chrome drawn only by the loaded detail body (`booking-detail-back`).
//
// NO PATROL FLOW: no OS dialog / deep link / FCM / WebView / biometric.
//
// FINDERS: widget Keys and types only (no Cyrillic literals).

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/leave_client_feedback_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_timeline_grid.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_shell_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/overflow_guard.dart';
import '../test/helpers/velvet_snack_matchers.dart';
import 'support/app_harness.dart';

/// The rating tapped. Not 5 (sibling default) so it can only reach the wire
/// via this tap.
const int _kRating = 4;

/// Fixture DATA typed into the comment field, echoed on the wire.
const String _kComment = 'Приємний клієнт.';

const Key _kCta = Key('booking-detail-leave-client-feedback');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  /// Login as [role] -> salon board -> tap `booking-1` -> the real detail.
  /// `booking-1` is a CONFIRMED salon booking that started an hour before the
  /// app clock (both pinned to [kFixedNow]), so «Завершити» is offered.
  Future<({GoRouter router, FakeBackend fb})> openDetail(
    WidgetTester tester,
    UserRole role,
  ) async {
    final DateTime start = kFixedNow.subtract(const Duration(hours: 1));
    final FakeBackend fb = FakeBackend()
      ..currentRole = role
      ..bookingMasterType = 'SALON_MASTER'
      ..bookingStatus = 'CONFIRMED'
      ..bookingStartsAt = start.toIso8601String()
      ..bookingEndsAt = start.add(const Duration(hours: 3)).toIso8601String()
      // Raw seed: reviewable once COMPLETED. Role-gating is the fake's job.
      ..bookingProviderCanReviewClient = true;
    fb.salonBoardBookings = <Map<String, dynamic>>[
      fb.salonBoardBookingRow(
        id: 'booking-1',
        masterId: 'master-aaa',
        masterFirstName: 'Софія',
        masterLastName: 'Бондар',
        startsAt: start,
        duration: const Duration(hours: 3),
      ),
    ];
    final GoRouter router = await AppHarness.boot(tester, fb);
    await AppHarness.loginAs(tester, fb, role);
    await AppHarness.pumpUntilFound(
      tester,
      find.byType(SalonShellScreen),
      timeout: const Duration(seconds: 20),
    );
    final Finder bookingsTab = find.byKey(const Key('salon-nav-tile-1'));
    await AppHarness.pumpUntilFound(
      tester,
      bookingsTab.hitTestable(),
      timeout: const Duration(seconds: 20),
    );
    await tester.tap(bookingsTab);
    await tester.pump();
    await AppHarness.pumpUntilFound(
      tester,
      find.byType(BookingsTimelineGrid),
      timeout: const Duration(seconds: 20),
    );
    final Finder card = find.byKey(
      const ValueKey<String>('timeline-card-booking-1'),
    );
    await AppHarness.pumpUntilFound(
      tester,
      card.hitTestable(),
      timeout: const Duration(seconds: 20),
    );
    await tester.tap(card);
    await tester.pump();
    await AppHarness.pumpUntilFound(
      tester,
      find.byType(BookingDetailScreen),
      timeout: const Duration(seconds: 20),
    );
    AppHarness.expectLocation(
      router,
      RouteNames.salonStaffBookingDetail('booking-1'),
    );
    await AppHarness.pumpUntilFound(
      tester,
      find.byKey(const Key('booking-detail-back')),
      timeout: const Duration(seconds: 20),
    );
    await AppHarness.settle(tester);
    return (router: router, fb: fb);
  }

  Future<void> journey(WidgetTester tester, UserRole role) async {
    await mockNetworkImagesFor(() async {
      final (:router, :fb) = await openDetail(tester, role);

      // Pre-complete: the CONFIRMED booking offers complete, not the CTA.
      expect(find.byKey(const Key('booking-detail-complete')), findsOneWidget);
      expect(find.byKey(_kCta), findsNothing);

      // ── Complete ────────────────────────────────────────────────────────
      await AppHarness.tapVisible(
        tester,
        find.byKey(const Key('booking-detail-complete')),
      );
      await AppHarness.settle(tester);
      await AppHarness.tapVisible(
        tester,
        find.byKey(const Key('complete-booking-confirm')),
      );
      await AppHarness.settle(tester);

      expect(fb.completeBookingCalls, 1);
      expect(find.byKey(const Key('booking-detail-back')), findsOneWidget);
      expect(
        find.byKey(const Key('booking-detail-complete')),
        findsNothing,
        reason: 'terminal footer after the completed re-fetch',
      );

      // ── The server-gated CTA appears for owner/admin ───────────────────
      expect(find.byKey(_kCta), findsOneWidget);
      await AppHarness.tapVisible(tester, find.byKey(_kCta));
      await AppHarness.settle(tester);

      expect(find.byType(LeaveClientFeedbackScreen), findsOneWidget);
      AppHarness.expectLocation(
        router,
        RouteNames.salonStaffClientReview('booking-1'),
      );
      // The FORM, not the ineligible branch (the admin's detail fetch succeeded).
      expect(
        find.byKey(const Key('leave-client-feedback-submit')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('leave-client-feedback-unavailable-back')),
        findsNothing,
      );

      // ── Rate + comment + submit ────────────────────────────────────────
      await AppHarness.tapVisible(
        tester,
        find.byKey(const ValueKey<String>('review-star-$_kRating')),
      );
      final Finder comment = find.descendant(
        of: find.byType(LeaveClientFeedbackScreen),
        matching: find.byType(TextField),
      );
      expect(comment, findsOneWidget);
      await tester.enterText(comment, _kComment);
      await AppHarness.settle(tester);
      await AppHarness.tapVisible(
        tester,
        find.byKey(const Key('leave-client-feedback-submit')),
      );
      await AppHarness.settle(tester);

      expect(fb.createClientReviewCalls, 1);
      expect(fb.lastClientReviewBookingId, 'booking-1');
      expect(fb.lastClientReviewRating, _kRating);
      expect(fb.lastClientReviewComment, _kComment);

      // ── Back on detail, CTA gone ───────────────────────────────────────
      expect(find.byType(LeaveClientFeedbackScreen), findsNothing);
      expect(find.byType(BookingDetailScreen), findsOneWidget);
      expect(find.byKey(const Key('booking-detail-back')), findsOneWidget);
      expect(find.byKey(_kCta), findsNothing);
      // Drain the success snack's dwell timer.
      await pumpPastVelvetSnack(tester);
    });
  }

  testWidgets(
    'SALON_OWNER: board -> detail -> complete -> rate the client (POST) -> CTA gone',
    (tester) => journey(tester, UserRole.salonOwner),
  );

  testWidgets(
    'SALON_ADMIN: board -> detail (GET /bookings/{id} allowed, backend 356) '
    '-> complete -> rate the client (POST) -> CTA gone',
    (tester) => journey(tester, UserRole.salonAdmin),
  );
}
