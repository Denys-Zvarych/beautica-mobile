// Phase 266 (mobile-qa Rule 3b) — E2E: a `getBookableMasters` call FAILING
// for one selected service must surface the retryable-error row, never the
// terminal "nobody performs this" row — and a successful retry must recover
// the row into a normal, pickable master.
//
// WHY THIS FILE EXISTS
// --------------------
// `salon_master_coverage_notifier_test.dart` and
// `salon_master_selection_screen_test.dart` already prove [SalonCoverage.
// degradedServiceIds]/[retryService] against a hand-written fake repository
// with every provider stubbed. Neither can catch:
//   • the REAL `SalonRepository.getBookableMasters` → `_mapDioException`
//     chain actually turning a wire-level 500 into a `Failure` the
//     notifier's `on Failure catch` block recognises (a mapper regression
//     here would make this test's degraded row never appear, while every
//     stubbed unit/widget test above stays green);
//   • the real route push + real `salonMasterServiceCoverageProvider` family
//     key reaching this screen through the same navigation chain
//     `salon_booking_flow_test.dart` proves for the ALL-SUCCESS case — this
//     file is that flow's one-service-fails sibling, not a duplicate of it;
//   • the retry tap driving a SECOND real HTTP round trip through the same
//     Dio/DioAdapter pipeline, merging back into the SAME screen without a
//     full provider invalidate (D4) — unobservable from a hand-rolled fake
//     repository that has no request/response wire shape to get wrong.
//
// FIXTURE COHERENCE: reuses the SAME `salon-xyz` fixture, roster, and
// 2-selected-service (salon-svc-shared, salon-svc-exclusive) setup as
// `salon_booking_flow_test.dart` — this file only diverges from it at the
// master-assignment step, where `salon-svc-shared`'s `getBookableMasters`
// call is forced to fail via `FakeBackend.forceBookableMastersFailure`
// (mirrors `forcePassportFailure`'s "set, then call again with null to
// recover" convention). `salon-svc-exclusive` (master-ddd) is left
// succeeding throughout, so this test also proves the OTHER, healthy
// service's coverage survives untouched while its sibling is degraded — the
// same "one service's failure must not blank the others" contract
// `salon_master_coverage_notifier_test.dart` pins at the unit tier.
//
// KEY POLICY: navigation taps are key-based (client-nav-search-center,
// search_show_masters_cta, salon_card_salon-xyz, salon-book-cta,
// salon-booking-category-BROWS, salon_booking_service_tile_<id>,
// booking-summary-cta, salon_booking_master_row_<id>,
// salon_booking_retry_service_<id>, salon-assign-confirm-cta). Raw
// `find.text(...)` is never used for tapping in this file.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
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

  testWidgets(
    'CLIENT salon booking: a failed getBookableMasters call for ONE selected '
    'service renders the retry row (never the terminal uncovered row), and '
    'a successful retry recovers that service into a pickable master',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()..currentRole = UserRole.client;
        final GoRouter router = await AppHarness.boot(tester, fb);

        await AppHarness.loginAs(tester, fb, UserRole.client);
        await AppHarness.settle(tester);

        // ── Reach the salon profile via the same real UI chain
        // `salon_booking_flow_test.dart` already proves ────────────────────
        await tester.tap(find.byKey(const Key('client-nav-search-center')));
        await AppHarness.settle(tester);
        await tester.tap(find.byKey(const Key('search_show_masters_cta')));
        await tester.pump();
        for (
          int i = 0;
          i < 30 && find.byKey(const Key('results_list')).evaluate().isEmpty;
          i++
        ) {
          await tester.pump();
        }
        expect(find.byKey(const Key('results_list')), findsOneWidget);

        final ScrollableState scrollable = tester.state<ScrollableState>(
          find.descendant(
            of: find.byKey(const Key('results_list')),
            matching: find.byType(Scrollable),
          ),
        );
        final ScrollPosition position = scrollable.position;
        position.jumpTo(position.pixels + 1);
        position.jumpTo(position.maxScrollExtent);
        await AppHarness.settle(tester);

        final Finder salonCard = find.byKey(const Key('salon_card_salon-xyz'));
        expect(salonCard, findsOneWidget);
        await tester.tap(salonCard);
        await AppHarness.settle(tester);
        expect(find.byType(PublicSalonProfileScreen), findsOneWidget);

        await tester.tap(find.byKey(const Key('salon-book-cta')));
        await AppHarness.settle(tester);
        expect(find.byType(SalonServiceSelectionScreen), findsOneWidget);

        // Select the SAME two services `salon_booking_flow_test.dart` picks
        // (salon-svc-shared -> master-ccc only; salon-svc-exclusive ->
        // master-ddd only), so this test's ONLY variable is the injected
        // failure below.
        final Finder sharedTile = find.byKey(
          const Key('salon_booking_service_tile_salon-svc-shared'),
        );
        expect(sharedTile, findsOneWidget);
        await tester.tap(sharedTile);
        await AppHarness.settle(tester);

        await tester.tap(find.byKey(const Key('salon-booking-category-BROWS')));
        await AppHarness.settle(tester);
        final Finder exclusiveTile = find.byKey(
          const Key('salon_booking_service_tile_salon-svc-exclusive'),
        );
        expect(exclusiveTile, findsOneWidget);
        await tester.ensureVisible(exclusiveTile);
        await AppHarness.settle(tester);
        await tester.tap(exclusiveTile);
        await AppHarness.settle(tester);

        // ── Inject the failure BEFORE the coverage fetch fires — the tap
        // below is what triggers `salonMasterServiceCoverageProvider.build`,
        // which issues one `getBookableMasters` call per selected service.
        fb.forceBookableMastersFailure('salon-svc-shared', 500);

        final Finder nextCta = find.byKey(const Key('booking-summary-cta'));
        expect(nextCta, findsOneWidget);
        await AppHarness.tapVisible(tester, nextCta);
        await AppHarness.settle(tester);

        AppHarness.expectShellLocation(router, RouteNames.salonBookingMasters);
        expect(find.byType(SalonMasterSelectionScreen), findsOneWidget);
        expect(
          tester.takeException(),
          isNull,
          reason:
              'a per-service getBookableMasters failure must degrade '
              'gracefully — it must never surface as an unhandled '
              'exception or blank the whole screen',
        );

        // Both services were queried exactly once each — the failing one
        // is NOT retried automatically by `build()` itself (D3: the catch
        // block is the only thing added to the fetch).
        expect(fb.getBookableMastersCalls, 2);
        expect(fb.requestedBookableMastersServiceDefIds, <String>{
          'salon-svc-shared',
          'salon-svc-exclusive',
        });

        // ── master-ccc (the ONLY candidate for the now-degraded
        // salon-svc-shared) must be ABSENT — its coverage never resolved.
        // master-ddd (salon-svc-exclusive, untouched) must still render —
        // proves one service's failure does not blank its sibling's
        // coverage. ─────────────────────────────────────────────────────────
        expect(
          find.byKey(const Key('salon_booking_master_row_master-ccc')),
          findsNothing,
          reason:
              "master-ccc is salon-svc-shared's only bookable master — with "
              'that call failed, master-ccc must not render as a pickable '
              'row (that would silently invent coverage the backend never '
              'returned)',
        );
        final Finder masterDddRow = find.byKey(
          const Key('salon_booking_master_row_master-ddd'),
        );
        expect(
          masterDddRow,
          findsOneWidget,
          reason:
              "salon-svc-exclusive's own call succeeded — master-ddd must "
              "still render, proving salon-svc-shared's failure did not "
              "blank its sibling's coverage",
        );

        // Pick master-ddd — the only eligible master on screen — which also
        // flips `hasPicks` true and mounts the grouping-preview card that
        // renders the degraded row (see `_MasterGroupingPreview.degraded`
        // and its `hasPicks` gate in
        // `salon_master_selection_screen.dart`).
        await AppHarness.tapVisible(tester, masterDddRow);
        await AppHarness.settle(tester);

        // ── THE regression proof: a failed service renders the RETRY row,
        // never the terminal `_UncoveredRow`. ──────────────────────────────
        final Finder degradedRow = find.byKey(
          const Key('salon_booking_degraded_service_salon-svc-shared'),
        );
        expect(
          degradedRow,
          findsOneWidget,
          reason:
              'salon-svc-shared\'s coverage fetch failed — it must render '
              'the retryable-error row, not silently read as "nobody '
              'performs this service"',
        );
        expect(
          find.byKey(const Key('salon-master-selection-empty')),
          findsNothing,
          reason:
              'salon-svc-exclusive has a real, resolved master (master-ddd) '
              '— the screen must never fall into the fully-empty-roster '
              'branch just because a SIBLING service degraded',
        );

        final Finder retryButton = find.byKey(
          const Key('salon_booking_retry_service_salon-svc-shared'),
        );
        expect(retryButton, findsOneWidget);

        // ── Retry while STILL failing — the row must stay degraded, never
        // silently flip to a healthy state without an actual successful
        // response. ─────────────────────────────────────────────────────────
        await AppHarness.tapVisible(tester, retryButton);
        await AppHarness.settle(tester);
        expect(
          find.byKey(
            const Key('salon_booking_degraded_service_salon-svc-shared'),
          ),
          findsOneWidget,
          reason:
              'retrying against a STILL-failing endpoint must leave the '
              'service degraded, not clear the error optimistically',
        );
        expect(
          find.byKey(const Key('salon_booking_master_row_master-ccc')),
          findsNothing,
        );

        // ── The failed retry above armed `salon_master_coverage_notifier
        // .dart`'s `_kRetryCooldown` (3s) — `SalonMasterServiceCoverage.
        // retryService` refuses a further call for this id until it elapses
        // (guard order: membership -> settled -> in-flight -> cooldown), so
        // tapping again immediately would be a no-op (`onTap: null` while
        // `cooldown` is true), not a genuine second network call. This is a
        // REAL `dart:async` `Timer` (not the pinned `clockProvider`, which
        // never advances on its own — see that guard's own doc), and
        // `IntegrationTestWidgetsFlutterBinding` (a `LiveTestWidgetsFlutter
        // Binding`) schedules a `pump(duration)` frame behind a REAL
        // `Timer(duration, ...)` — so this genuinely waits out the real
        // cooldown window instead of fast-forwarding a fake clock (which
        // `AutomatedTestWidgetsFlutterBinding.pump` would do, but this
        // binding is not that). `pumpAndSettle` alone would NOT wait long
        // enough on its own, since nothing is animating meanwhile.
        // fixed-wait-ok: crossing the real 3s retry cooldown so a genuine
        // dart:async Timer fires and clears retryCooldownUntil — there is no
        // condition to pump-until here (the guard is real elapsed wall-clock
        // time, not a widget/state to wait for), and pump-until-condition
        // would busy-loop for the same duration anyway.
        await tester.pump(const Duration(seconds: 4));
        await AppHarness.settle(tester);

        // ── Now let the backend recover, and retry again — the SAME
        // fire-and-forget entry point the row's tap already drives (D4:
        // refetch exactly this one service, merge in place). ───────────────
        fb.forceBookableMastersFailure('salon-svc-shared', null);
        final int callsBeforeSuccessfulRetry = fb.getBookableMastersCalls;

        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('salon_booking_retry_service_salon-svc-shared')),
        );
        await AppHarness.settle(tester);

        expect(
          fb.getBookableMastersCalls,
          greaterThan(callsBeforeSuccessfulRetry),
          reason:
              'the retry tap must issue a REAL second getBookableMasters '
              'call for salon-svc-shared, not replay a cached result',
        );

        // The degraded row is gone, and master-ccc — salon-svc-shared's
        // real, now-resolved bookable master — renders as a normal, pickable
        // row: the flow can continue past the point the original bug froze
        // it at.
        expect(
          find.byKey(
            const Key('salon_booking_degraded_service_salon-svc-shared'),
          ),
          findsNothing,
          reason:
              'a successful retry must clear the degraded row for '
              'salon-svc-shared',
        );
        final Finder masterCccRow = find.byKey(
          const Key('salon_booking_master_row_master-ccc'),
        );
        expect(
          masterCccRow,
          findsOneWidget,
          reason:
              'salon-svc-shared\'s retry succeeded — master-ccc must now '
              'render as a normal pickable row, proving the flow can '
              'continue past the point the original bug stranded it at',
        );

        // ── The flow can continue: pick master-ccc too, and both selected
        // services now have exactly one candidate each, so the assign-
        // confirm CTA enables. ──────────────────────────────────────────────
        await AppHarness.tapVisible(tester, masterCccRow);
        await AppHarness.settle(tester);

        final Finder confirmCta = find.byKey(
          const Key('salon-assign-confirm-cta'),
        );
        expect(confirmCta, findsOneWidget);
        await AppHarness.tapVisible(tester, confirmCta);
        await AppHarness.settle(tester);

        AppHarness.expectShellLocation(router, RouteNames.salonBookingTime);
        expect(
          tester.takeException(),
          isNull,
          reason:
              'the recovered flow must reach the real step-3 time screen '
              'exactly like the all-success sibling flow does',
        );
      });
    },
  );
}
