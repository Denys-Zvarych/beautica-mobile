// Phase 14.12/14.13 QA follow-up — E2E: CLIENT salon booking journey.
// Extended in Phase 14.16/14.17 (mobile-qa Rule 3b) to continue through the
// real step-3 "Час" time-picker screen instead of stopping at the
// master-assignment step.
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
//   • [salonMasterServiceCoverageProvider]'s Phase 23.x rewire actually
//     round-tripping `GET /salons/{salonId}/services/{serviceDefId}/masters`
//     — ONE call per client-selected service, never a roster fan-out —
//     correctly surfacing only the masters the endpoint returns as bookable
//     and never rendering one it omits;
//   • the full click-through chain (services → masters → confirm → time
//     picker → confirm) landing on the coming-soon placeholder, never the
//     independent-master `SlotPickerScreen` (that screen assumes a single
//     `masterId`, which a salon booking never has).
//
// PHASE 23.x REWIRE: `salonMasterServiceCoverageProvider` used to fan
// `GET /masters/{id}/services` out over the salon's FULL roster (up to 8
// concurrent calls) and derive coverage by intersecting each master's own
// service list against the client's selection. That meant a master with an
// active assignment but NO usable weekly schedule still showed up as
// "covers this service", opening a calendar with every date disabled once
// picked — the exact production bug report this session fixes. The new
// dedicated endpoint filters server-side (active + actively assigned + usable
// schedule) and is called ONCE PER SELECTED SERVICE instead of once per
// roster master, so THIS test's job changed from "prove the fan-out reaches
// every roster master" to "prove the call count scales with the selection,
// not the roster, and that a master the endpoint omits never renders" — see
// the assertions right after "Далі" below.
//
// PHASE 14.16/14.17 EXTENSION: "Підтвердити" on `SalonMasterSelectionScreen`
// now retargets to the real `SalonTimeScreen` (Phase 14.16 Step 1) instead of
// jumping straight to the coming-soon placeholder — this test's tail was
// updated to match, and now ALSO drives the per-master date+time picks (real
// `GET /masters/{id}/working-days` + `GET /masters/{id}/slots` calls for BOTH
// eligible roster masters, not just one — see `fake_backend.dart`'s
// Phase 14.16/14.17 route block, added alongside this extension to avoid
// repeating the exact Phase 14.13 bug where only `master-aaa` had routes
// registered and every other roster master 404'd), the auto-advance between
// slides, and the manual dot-tap pager navigation, before the schedule
// confirm bar's own "Підтвердити" finally reaches the coming-soon
// placeholder.
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
// bookable once both salon services are selected — see `fake_backend.dart`'s
// "GET /api/v1/salons/salon-xyz/services/{serviceDefId}/masters" section for
// the full coverage split. The other 6 roster masters (including
// `master-eee`, standing in for the "Роман" scheduleless-master bug report)
// are simply never returned by either route — proving the server-omission
// contract end to end, not just that a client-side filter hides them.
//
// KEY POLICY: navigation taps are key-based (client-nav-search-center,
// search_show_masters_cta, salon_card_salon-xyz, salon-book-cta,
// salon-booking-category-BROWS, salon_booking_service_tile_<id>,
// booking-summary-cta, salon_booking_master_row_<id>,
// salon-assign-confirm-cta, salon-time-pager-dot-<i>,
// booking-calendar-day-<n>, salon-slot-chip-<iso>, schedule-confirm-cta).
// Raw find.text(...) is used only for content assertions on fixture data,
// never for tapping.
//
// Step 2.7 Rule 3b: this is the real user journey (new screens + 4 new
// routes + a keepAlive provider fanning a real HTTP call out over a real
// roster) the widget tier cannot prove end to end. Also carries the ONLY
// real-app exercise of `BookingSummaryBar`'s expand toggle + per-item "×"
// remove affordance (mobile-qa audit, added alongside that feature) — see
// the "Per-item remove affordance" block below.

import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_booking_coming_soon_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_master_selection_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_service_selection_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_time_screen.dart';
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
    // `currentConfiguration.uri` deliberately EXCLUDES `ImperativeRouteMatch`
    // entries (see go_router's `RouteMatchList.uri` doc comment) — every
    // route this flow reaches after the initial `/search` tab (the salon
    // profile + all 3 salon-booking routes) is pushed imperatively via
    // `context.push`/`context.go` ON TOP OF the CLIENT `StatefulShellRoute`,
    // so `.uri` would keep reporting the shell branch's root ('/search')
    // instead of the actually-displayed screen. `matches.last.matchedLocation`
    // is what go_router's own `ImperativeRouteMatch` uses internally and is
    // always the full absolute path (see `match.dart`), so it reflects the
    // real current screen regardless of shell nesting.
    final String current =
        router.routerDelegate.currentConfiguration.matches.last.matchedLocation;
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
      await AppHarness.settle(tester);

      // Reach the salon profile via the SAME real UI chain
      // `public_salon_profile_flow_test.dart` already proves (discovery →
      // search-results → tap the salon card) rather than a raw
      // `router.push` — this is the actual path a CLIENT takes, and it
      // exercises the real ShellRoute/bottom-nav navigation stack instead
      // of a programmatic jump.
      await tester.tap(find.byKey(const Key('client-nav-search-center')));
      await AppHarness.settle(tester);
      await tester.tap(find.byKey(const Key('search_show_masters_cta')));
      // The shared `/search/masters` fixture unconditionally returns
      // `totalPages: 2` on page 0, so `masterHasMore` is already `true` the
      // instant page 0 lands — BEFORE any scroll. The results screen's
      // trailing `_LoadMoreSpinner` is not scroll-gated (it's laid out
      // eagerly whenever `hasMore` is true and the short 2-item list
      // undershoots the viewport), so its indeterminate spinner starts
      // ticking immediately and no `pumpAndSettle`/`AppHarness.settle` can
      // ever converge here — settling must wait until AFTER the scroll-drain
      // below resolves `masterHasMore` to `false`. Pump-until-condition
      // instead of guessing a fixed wall-clock duration: the fake backend's
      // `DioAdapter` resolves the page-0 fetch on plain microtasks (no
      // Timer/Future.delayed anywhere in `search_results_notifier.dart`), so
      // bare `pump()` calls (no Duration — nothing to advance a fake clock
      // by) drain the route push + fetch in however many frames it actually
      // takes, bounded so a genuine regression still fails fast instead of
      // hanging.
      await tester.pump();
      for (
        int i = 0;
        i < 30 && find.byKey(const Key('results_list')).evaluate().isEmpty;
        i++
      ) {
        await tester.pump();
      }

      expect(
        find.byKey(const Key('results_list')),
        findsOneWidget,
        reason: 'must land on the search results screen after the tap',
      );

      // Drain the shared fixture's forced second page so the trailing
      // `_LoadMoreSpinner` stops spinning and every subsequent settle can
      // converge.
      final ScrollableState scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(const Key('results_list')),
          matching: find.byType(Scrollable),
        ),
      );
      final ScrollPosition position = scrollable.position;
      // The 2-item first page (1 master + 1 salon) undershoots the
      // viewport, so `maxScrollExtent == pixels == 0` already — a bare
      // `jumpTo(maxScrollExtent)` is a genuine Flutter no-op (jumpTo only
      // notifies listeners when the target differs from the current
      // `pixels`) and would never fire the `_onScroll` listener that calls
      // `loadMore()`. Force a real pixel delta first so the final jumpTo is
      // guaranteed to notify.
      position.jumpTo(position.pixels + 1);
      position.jumpTo(position.maxScrollExtent);
      await AppHarness.settle(
        tester,
      ); // masters page 1 drains → masterHasMore=false

      final Finder salonCard = find.byKey(const Key('salon_card_salon-xyz'));
      expect(salonCard, findsOneWidget);
      await tester.tap(salonCard);
      await AppHarness.settle(tester);
      expectLocation(router, '/salons/salon-xyz');
      expect(find.byType(PublicSalonProfileScreen), findsOneWidget);

      // ── Tap "Записатись на послугу" → service selection (NOT a crash) ──
      final Finder bookCta = find.byKey(const Key('salon-book-cta'));
      expect(bookCta, findsOneWidget);
      await tester.tap(bookCta);
      await AppHarness.settle(tester);

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
      await AppHarness.settle(tester);

      // BROWS starts collapsed — expand it to reach the exclusive tile.
      await tester.tap(find.byKey(const Key('salon-booking-category-BROWS')));
      await AppHarness.settle(tester);
      final Finder exclusiveTile = find.byKey(
        const Key('salon_booking_service_tile_salon-svc-exclusive'),
      );
      expect(exclusiveTile, findsOneWidget);
      await tester.tap(exclusiveTile);
      await AppHarness.settle(tester);

      // ── Per-item "×" remove affordance (mobile-qa Rule 3b follow-up) ────
      // Widget tests already prove this SECOND deselection path converges to
      // the same state as unchecking the catalogue tile, but only against
      // fully-stubbed providers. This is the ONE place in the suite that
      // drives the real GestureDetector hit-test + Semantics node through a
      // real routed screen with the real ValueListenableBuilder toggle —
      // neither `salon_service_selection_screen_test.dart` nor this file
      // previously tapped the expand toggle or the remove icon at all.
      await tester.tap(find.byKey(const Key('booking-summary-expand-toggle')));
      await AppHarness.settle(tester);
      final Finder removeExclusive = find.byKey(
        const Key('booking-summary-remove-salon-svc-exclusive'),
      );
      expect(removeExclusive, findsOneWidget);
      await tester.tap(removeExclusive);
      await AppHarness.settle(tester);

      // The catalogue tile's own selection indicator reflects the removal —
      // the two paths land on identical state in the real app, not just in
      // an isolated widget test.
      expect(
        find.descendant(
          of: exclusiveTile,
          matching: find.byKey(const ValueKey<bool>(true)),
        ),
        findsNothing,
        reason:
            'removing salon-svc-exclusive via the shelf must deselect its '
            'catalogue tile too — both paths drive the same _toggleService',
      );

      // mobile-qa gap: the assertion above only proves the REMOVED tile
      // deselects — it can't distinguish that from a regression that wipes
      // the whole selection set (both look identical once only one service
      // was ever selected at a time). salon-svc-shared was also selected
      // going into this removal, so re-check it explicitly survives, and
      // that the CTA is still enabled off that lone survivor — in the REAL
      // app, not an isolated widget test.
      expect(
        find.descendant(
          of: sharedTile,
          matching: find.byKey(const ValueKey<bool>(true)),
        ),
        findsOneWidget,
        reason:
            'removing salon-svc-exclusive via the shelf must NOT deselect '
            'salon-svc-shared — a regression that clears the whole '
            'selection instead of just the tapped id would slip past a '
            'single-survivor-blind check',
      );
      expect(
        tester
            .widget<NeumorphicButton>(
              find.byKey(const Key('booking-summary-cta')),
            )
            .onPressed,
        isNotNull,
        reason:
            'salon-svc-shared remains selected — the "Далі" CTA must stay '
            'enabled through the shelf-driven removal of the other service',
      );

      // Re-select it via the catalogue tile (the flow below needs both
      // services selected) — this also proves the catalogue tap still works
      // after a shelf-driven removal, i.e. the two triggers do not desync.
      await tester.tap(exclusiveTile);
      await AppHarness.settle(tester);
      expect(
        find.descendant(
          of: exclusiveTile,
          matching: find.byKey(const ValueKey<bool>(true)),
        ),
        findsOneWidget,
      );

      // ── "Далі" → master assignment ──────────────────────────────────────
      final Finder nextCta = find.byKey(const Key('booking-summary-cta'));
      expect(nextCta, findsOneWidget);
      await tester.tap(nextCta);
      // Settles the real async route-push step after the tap AND the real
      // `salonMasterServiceCoverageProvider` calls — Phase 23.x rewire: ONE
      // `GET /salons/{salonId}/services/{serviceDefId}/masters` call per
      // selected service, never a roster fan-out.
      await AppHarness.settle(tester);

      expectLocation(router, RouteNames.salonBookingMasters);
      expect(find.byType(SalonMasterSelectionScreen), findsOneWidget);
      expect(
        tester.takeException(),
        isNull,
        reason:
            'a per-service getBookableMasters call must never throw here — '
            'a regression that let one selected service\'s failure blank the '
            'whole grid (instead of degrading gracefully) would land here on '
            'the error state instead',
      );

      // ── Call SHAPE proof (the rewire's core scaling claim) ──────────────
      // Exactly 2 calls — one per SELECTED service — never one per roster
      // master (would be up to 8). This is what changed: pre-rewire this
      // assertion checked the fan-out reached every roster master; the new
      // endpoint means the roster size is irrelevant to the call count.
      expect(
        fb.getBookableMastersCalls,
        2,
        reason:
            'salonMasterServiceCoverageProvider must call getBookableMasters '
            'exactly once per selected service (salon-svc-shared, '
            'salon-svc-exclusive) — never once per roster master',
      );
      expect(
        fb.requestedBookableMastersServiceDefIds,
        <String>{'salon-svc-shared', 'salon-svc-exclusive'},
        reason:
            'both selected services\' serviceDefIds must have been queried, '
            'and NOTHING else (no roster masterId ever reaches this call\'s '
            'path parameter)',
      );

      // ── Only the 2 BOOKABLE masters render (of 8 on the roster) — proves
      // the server-omission contract end to end: master-eee (standing in for
      // "Роман", the scheduleless-master bug report) is never returned by
      // EITHER bookable-masters route and therefore never rendered, exactly
      // like a real backend that server-filters an unusable-schedule master
      // out of the response instead of sending a broken calendar. ──────────
      expect(
        find.byKey(const Key('salon_booking_master_row_master-ccc')),
        findsOneWidget,
        reason: 'master-ccc is bookable for salon-svc-shared',
      );
      expect(
        find.byKey(const Key('salon_booking_master_row_master-ddd')),
        findsOneWidget,
        reason: 'master-ddd is bookable for salon-svc-exclusive',
      );
      for (final String omittedId in <String>[
        'master-aaa', // reuses the Phase 13.5 fixture — never returned here
        'master-eee', // scheduleless-master bug stand-in — server-omitted
        'master-fff',
        'master-ggg',
        'master-hhh',
        'master-iii',
      ]) {
        expect(
          find.byKey(Key('salon_booking_master_row_$omittedId')),
          findsNothing,
          reason:
              '$omittedId was never returned by either bookable-masters '
              'route and must never render on the master-assignment step',
        );
      }

      // ── Pick both eligible masters → each is the sole candidate for its
      // service → auto-attach → "Підтвердити" becomes enabled ────────────
      await tester.tap(
        find.byKey(const Key('salon_booking_master_row_master-ccc')),
      );
      await AppHarness.settle(tester);
      await tester.tap(
        find.byKey(const Key('salon_booking_master_row_master-ddd')),
      );
      await AppHarness.settle(tester);

      final Finder confirmCta = find.byKey(
        const Key('salon-assign-confirm-cta'),
      );
      expect(confirmCta, findsOneWidget);
      await tester.tap(confirmCta);
      await AppHarness.settle(tester);

      // ── Phase 14.16/14.17 — "Підтвердити" now lands on the REAL step-3
      // "Час" screen (SalonTimeScreen), never the independent-master
      // SlotPickerScreen (that flow assumes a single masterId, which a salon
      // booking never has) and never a direct jump to the coming-soon
      // placeholder — that hand-off only happens once BOTH assigned masters
      // (master-ccc, master-ddd) are fully scheduled, via the confirm bar
      // built later in this test. ─────────────────────────────────────────
      expectLocation(router, RouteNames.salonBookingTime);
      expect(find.byType(SalonTimeScreen), findsOneWidget);
      expect(
        tester.takeException(),
        isNull,
        reason:
            'reaching the salon time-picker step must never throw — this '
            'exercises salonMasterServiceCoverageProvider\'s per-master '
            'assignment feeding into a REAL PageView.builder over two '
            'separately-fetched masters',
      );

      // Two eligible masters (master-ccc, master-ddd) assigned in the
      // previous step → exactly two slider slides/dots.
      expect(find.byKey(const Key('salon-time-pager-dot-0')), findsOneWidget);
      expect(find.byKey(const Key('salon-time-pager-dot-1')), findsOneWidget);

      // Scopes an interaction/assertion to one master's slide — needed
      // because BOTH slides can be simultaneously mounted (mobile-perf's
      // current±1 keep-alive bound), so an unscoped `booking-calendar-day-N`/
      // `salon-slot-chip-<iso>` key could otherwise match either slide.
      // `skipOffstage: false` so a kept-alive-but-currently-scrolled-off
      // slide is still reachable, mirroring
      // `salon_time_screen_test.dart`'s identical `withinSlide` helper.
      Finder withinSlide(String masterId, Finder matching) => find.descendant(
        of: find.byKey(
          Key('salon-schedule-page-$masterId'),
          skipOffstage: false,
        ),
        matching: matching,
        skipOffstage: false,
      );

      final DateTime today = DateTime.now();
      final int workingDaysCallsBeforeTime = fb.getWorkingDaysCalls;
      final int slotsCallsBeforeTime = fb.getMasterSlotsCalls;
      final String todaysMorningSlotIso = DateTime(
        today.year,
        today.month,
        today.day,
        10,
      ).toIso8601String();

      // ── Master-ccc's slide (current, index 0) — pick today's date over
      // the REAL `GET /masters/master-ccc/working-days` route, then the
      // fetched 10:00 slot over the REAL
      // `GET /masters/master-ccc/slots` route ─────────────────────────────
      await tester.tap(
        withinSlide(
          'master-ccc',
          find.byKey(Key('booking-calendar-day-${today.day}')),
        ),
      );
      await AppHarness.settle(tester);
      expect(
        fb.getWorkingDaysCalls,
        greaterThan(workingDaysCallsBeforeTime),
        reason:
            'picking a date on master-ccc\'s slide must hit the real '
            'working-days endpoint, not render from stale/absent state',
      );

      final Finder ccdMorningSlot = withinSlide(
        'master-ccc',
        find.byKey(Key('salon-slot-chip-$todaysMorningSlotIso')),
      );
      expect(ccdMorningSlot, findsOneWidget);
      await tester.tap(ccdMorningSlot);
      await AppHarness.settle(tester);
      expect(
        fb.getMasterSlotsCalls,
        greaterThan(slotsCallsBeforeTime),
        reason:
            'picking master-ccc\'s date must hit the real slots endpoint '
            'for master-ccc specifically, not a stale/shared fixture',
      );
      // ── Phase 14.16/14.17 bugfix regression guard ───────────────────────
      // The REAL request's `serviceId` query param must be master-ccc's own
      // per-master ASSIGNMENT id (`assign-master-ccc-salon-svc-shared`,
      // `MasterServiceResponse.id`), never the salon-wide CATALOG id
      // (`salon-svc-shared`, `ServiceDefinitionResponse.id`) that
      // `salon-svc-shared` itself is. Sending the catalog id is exactly the
      // bug that made the real backend 404 with "masterService not found" —
      // the widget tier (`salon_time_screen_test.dart`) proves this against
      // a hand-written fake; this is the ONE place it is proven against a
      // real end-to-end request/response round trip.
      expect(
        fb.lastMasterCccSlotsServiceId,
        'assign-master-ccc-salon-svc-shared',
        reason:
            'the slots request must carry master-ccc\'s own service-'
            'ASSIGNMENT id, not the salon-wide catalog id',
      );
      expect(fb.lastMasterCccSlotsServiceId, isNot('salon-svc-shared'));

      // ── Auto-advance: completing master-ccc's date+time slides the
      // PageView onto the next unscheduled master (master-ddd) with NO
      // manual tap — proving `nextUnscheduledIndex` genuinely drives the
      // REAL PageController over two independently-fetched masters, not
      // just the one hardcoded roster master a prior Phase 14.13 bug would
      // have left this untested against. ──────────────────────────────────
      final Finder dddCalendarDay = withinSlide(
        'master-ddd',
        find.byKey(Key('booking-calendar-day-${today.day}')),
      );
      expect(
        dddCalendarDay,
        findsOneWidget,
        reason:
            'the slider must auto-advance onto master-ddd\'s date phase '
            'once master-ccc is fully scheduled',
      );

      await tester.tap(dddCalendarDay);
      await AppHarness.settle(tester);

      final Finder dddMorningSlot = withinSlide(
        'master-ddd',
        find.byKey(Key('salon-slot-chip-$todaysMorningSlotIso')),
      );
      expect(dddMorningSlot, findsOneWidget);
      await tester.tap(dddMorningSlot);
      await AppHarness.settle(tester);
      // Same regression guard as master-ccc above, for the SECOND slide —
      // proves the fix resolves each master's OWN assignment id
      // independently, not a coincidentally-correct single-master case.
      expect(
        fb.lastMasterDddSlotsServiceId,
        'assign-master-ddd-salon-svc-exclusive',
        reason:
            'the slots request must carry master-ddd\'s own service-'
            'ASSIGNMENT id, not the salon-wide catalog id',
      );
      expect(fb.lastMasterDddSlotsServiceId, isNot('salon-svc-exclusive'));

      // ── Manual pager navigation (dot-tap) also works in the real app —
      // complements the auto-advance proof above with the OTHER way a
      // client can move between slides. ───────────────────────────────────
      await tester.tap(find.byKey(const Key('salon-time-pager-dot-0')));
      await AppHarness.settle(tester);
      expect(
        find.byKey(const Key('salon-schedule-page-master-ccc')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('salon-time-pager-dot-1')));
      await AppHarness.settle(tester);

      // ── Both masters fully scheduled — the confirm bar's "Підтвердити"
      // enables, and tapping it is PURE forward navigation to the existing
      // coming-soon placeholder, NEVER a `POST /bookings` call ────────────
      final Finder scheduleConfirmCta = find.byKey(
        const Key('schedule-confirm-cta'),
      );
      final NeumorphicButton scheduleCta = tester.widget<NeumorphicButton>(
        scheduleConfirmCta,
      );
      expect(
        scheduleCta.onPressed,
        isNotNull,
        reason:
            'both master-ccc and master-ddd have a date+time now — the '
            'confirm bar must enable',
      );

      await tester.tap(scheduleConfirmCta);
      await AppHarness.settle(tester);

      // ── Lands on the coming-soon placeholder — NEVER the
      // independent-master SlotPickerScreen (that flow assumes a single
      // masterId, which a salon booking never has) ───────────────────────
      expectLocation(router, RouteNames.salonBookingComingSoon);
      expect(find.byType(SalonBookingComingSoonScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }, timeout: const Timeout(Duration(seconds: 90)));
}
