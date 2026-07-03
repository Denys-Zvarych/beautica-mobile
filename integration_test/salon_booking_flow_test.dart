// Phase 14.12/14.13 QA follow-up — E2E: CLIENT salon booking journey.
//
// WHY THIS FILE EXISTS
// --------------------
// This session shipped a brand-new user journey (public salon profile → book
// → select services → assign masters → coming-soon placeholder) AND fixed a
// real backend-crash bug: the booking CTA used to push [RouteNames.bookingNew]
// with `salon.id` misused as a `masterId`, 404ing server-side with
// `NotFoundException: Master not found` (see `public_salon_profile_screen.dart`'s
// `_BookingShelf`). The widget tier
// (salon_service_selection_screen_test.dart, salon_master_selection_screen_test.dart)
// proves each screen in isolation with EVERY provider stubbed — it cannot
// catch:
//   • the CTA actually reaching `SalonServiceSelectionScreen` over a REAL
//     route push, not the old buggy destination;
//   • [salonMasterServiceCoverageProvider]'s bounded fan-out actually
//     round-tripping `GET /masters/{id}/services` for the REAL salon roster
//     (8 masters) over the wire, correctly filtering ineligible masters and
//     surfacing only the ones who cover a selected service;
//   • the full click-through chain (services → masters → confirm) landing on
//     the coming-soon placeholder, never the independent-master
//     `SlotPickerScreen` (that screen assumes a single `masterId`, which a
//     salon booking never has).
//
// FIXTURE COHERENCE: reuses the SAME `salon-xyz` fixture + 8-master roster
// already seeded for `public_salon_profile_flow_test.dart`
// (`FakeBackend._salonMasters` / `_salonServiceCategories`). Reaches the
// salon profile via the SAME real UI chain that sibling file already proves
// (discovery search → results → tap the salon card), not a raw
// `router.push` — that keeps this test on the one navigation path already
// known to settle deterministically against the real ShellRoute/bottom-nav
// stack. Of the 8 roster masters, only `master-ccc` (covers
// `salon-svc-shared`) and `master-ddd` (covers `salon-svc-exclusive`) are
// eligible once both salon services are selected — see `fake_backend.dart`'s
// "GET /api/v1/masters/{masterId}/services" section for the full coverage
// split and why `master-aaa` is deliberately ineligible here (it reuses the
// UNRELATED Phase 13.5 public-profile fixture, which covers neither salon
// service).
//
// KEY POLICY: navigation taps are key-based (client-nav-search-center,
// search_show_masters_cta, salon_card_salon-xyz, salon-book-cta,
// salon-booking-category-BROWS, salon_booking_service_tile_<id>,
// booking-summary-cta, salon_booking_master_row_<id>,
// salon-assign-confirm-cta). Raw find.text(...) is used only for content
// assertions on fixture data, never for tapping.
//
// Step 2.7 Rule 3b: this is the real user journey (new screens + 3 new
// routes + a keepAlive provider fanning a real HTTP call out over a real
// roster) the widget tier cannot prove end to end.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_booking_coming_soon_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_master_selection_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_service_selection_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/public_salon_profile_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  void expectLocation(GoRouter router, String expected) {
    final String current = router.routerDelegate.currentConfiguration.uri
        .toString();
    expect(
      current,
      startsWith(expected),
      reason: 'Expected router location to start with $expected, got $current',
    );
  }

  testWidgets('CLIENT books a salon service end to end: profile CTA → service '
      'selection → master assignment (ineligible masters filtered, eligible '
      'masters auto-attached) → coming-soon placeholder', (tester) async {
    await mockNetworkImagesFor(() async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      final GoRouter router = await AppHarness.boot(tester, fb);

      await AppHarness.loginAs(tester, fb, UserRole.client);
      // fixed-wait-ok: settles the real async login/route-transition step.
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Reach the salon profile via the SAME real UI chain
      // `public_salon_profile_flow_test.dart` already proves (discovery →
      // search-results → tap the salon card) rather than a raw
      // `router.push` — this is the actual path a CLIENT takes, and it
      // exercises the real ShellRoute/bottom-nav navigation stack instead
      // of a programmatic jump.
      await tester.tap(find.byKey(const Key('client-nav-search-center')));
      // fixed-wait-ok: settles the real async route-push step after the tap.
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await tester.tap(find.byKey(const Key('search_show_masters_cta')));
      // fixed-wait-ok: settles the real async route-push step after the tap.
      await tester.pumpAndSettle(const Duration(seconds: 1));

      final Finder salonCard = find.byKey(const Key('salon_card_salon-xyz'));
      expect(salonCard, findsOneWidget);
      await tester.tap(salonCard);
      // fixed-wait-ok: settles the real async route-push step after the tap.
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expectLocation(router, '/salons/salon-xyz');
      expect(find.byType(PublicSalonProfileScreen), findsOneWidget);

      // ── Tap "Записатись на послугу" → service selection (NOT a crash) ──
      final Finder bookCta = find.byKey(const Key('salon-book-cta'));
      expect(bookCta, findsOneWidget);
      await tester.tap(bookCta);
      // fixed-wait-ok: settles the real async route-push step after the tap.
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expectLocation(router, RouteNames.salonBookingServices);
      expect(find.byType(SalonServiceSelectionScreen), findsOneWidget);
      expect(
        tester.takeException(),
        isNull,
        reason:
            'reaching the salon service-selection step must never throw '
            '— this is the regression proof for the old bookingNew '
            '(masterId-misuse) crash',
      );

      // NAILS category is expanded by default → its shared service tile is
      // immediately tappable.
      final Finder sharedTile = find.byKey(
        const Key('salon_booking_service_tile_salon-svc-shared'),
      );
      expect(sharedTile, findsOneWidget);
      await tester.tap(sharedTile);
      await tester.pumpAndSettle();

      // BROWS starts collapsed — expand it to reach the exclusive tile.
      await tester.tap(find.byKey(const Key('salon-booking-category-BROWS')));
      await tester.pumpAndSettle();
      final Finder exclusiveTile = find.byKey(
        const Key('salon_booking_service_tile_salon-svc-exclusive'),
      );
      expect(exclusiveTile, findsOneWidget);
      await tester.tap(exclusiveTile);
      await tester.pumpAndSettle();

      // ── "Далі" → master assignment ──────────────────────────────────────
      final Finder nextCta = find.byKey(const Key('booking-summary-cta'));
      expect(nextCta, findsOneWidget);
      await tester.tap(nextCta);
      // fixed-wait-ok: settles the real async route-push step after the tap
      // AND the real `salonMasterServiceCoverageProvider` fan-out over the
      // 8-master roster.
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expectLocation(router, RouteNames.salonBookingMasters);
      expect(find.byType(SalonMasterSelectionScreen), findsOneWidget);
      expect(
        tester.takeException(),
        isNull,
        reason:
            'the bounded fan-out over the real 8-master roster must never '
            'throw — an unregistered roster master would fail the whole '
            '`Future.wait` batch and land here on the error state instead',
      );

      // The bounded fan-out reached EVERY roster master, not just the
      // first chunk — proves the chunk loop covers the full roster over
      // the real wire, not only `_kFetchChunkSize` (8) of the 8-master
      // roster's first (and only, here) chunk.
      expect(
        fb.requestedSalonRosterMasterIds,
        containsAll(<String>[
          'master-ccc',
          'master-ddd',
          'master-eee',
          'master-fff',
          'master-ggg',
          'master-hhh',
          'master-iii',
        ]),
        reason:
            'the coverage fan-out must query every roster master (except '
            'master-aaa, which reuses the pre-existing Phase 13.5 route)',
      );

      // ── Only the 2 ELIGIBLE masters render (of 8 on the roster) ────────
      expect(
        find.byKey(const Key('salon_booking_master_row_master-ccc')),
        findsOneWidget,
        reason: 'master-ccc covers salon-svc-shared — eligible',
      );
      expect(
        find.byKey(const Key('salon_booking_master_row_master-ddd')),
        findsOneWidget,
        reason: 'master-ddd covers salon-svc-exclusive — eligible',
      );
      for (final String ineligibleId in <String>[
        'master-aaa', // reuses the Phase 13.5 fixture — covers neither
        'master-eee',
        'master-fff',
        'master-ggg',
        'master-hhh',
        'master-iii',
      ]) {
        expect(
          find.byKey(Key('salon_booking_master_row_$ineligibleId')),
          findsNothing,
          reason:
              '$ineligibleId covers neither selected salon service and '
              'must never render on the master-assignment step',
        );
      }

      // ── Pick both eligible masters → each is the sole candidate for its
      // service → auto-attach → "Підтвердити" becomes enabled ────────────
      await tester.tap(
        find.byKey(const Key('salon_booking_master_row_master-ccc')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('salon_booking_master_row_master-ddd')),
      );
      await tester.pumpAndSettle();

      final Finder confirmCta = find.byKey(
        const Key('salon-assign-confirm-cta'),
      );
      expect(confirmCta, findsOneWidget);
      await tester.tap(confirmCta);
      // fixed-wait-ok: settles the real async route-push step after the tap.
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // ── Lands on the coming-soon placeholder — NEVER the
      // independent-master SlotPickerScreen (that flow assumes a single
      // masterId, which a salon booking never has) ───────────────────────
      expectLocation(router, RouteNames.salonBookingComingSoon);
      expect(find.byType(SalonBookingComingSoonScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }, timeout: const Timeout(Duration(seconds: 90)));
}
