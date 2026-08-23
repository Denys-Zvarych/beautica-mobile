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

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/data/appointment_repository.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/domain/appointment.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/create_appointment_request.dart';
import 'package:beautica_mobile/features/booking/domain/salon_booking_confirm_args.dart';
import 'package:beautica_mobile/features/booking/domain/salon_master_schedule.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_booking_confirm_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_booking_success_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_master_selection_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_service_selection_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_time_screen.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:beautica_mobile/features/salon/presentation/public_salon_profile_screen.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/overflow_guard.dart';
import '../test/helpers/pump_app.dart';
import 'support/app_harness.dart';

/// mobile-qa audit-fix cycle 2: taps the pinned step-3 CTA
/// (`schedule-confirm-cta`) and settles. Commit `92644d2e` retired the old
/// auto-advance contract (a date tap alone used to swap a slide into its
/// time chips, and a slot tap alone used to advance the pager to the next
/// unscheduled master) — both transitions are CTA-driven now (see
/// `salon_time_screen.dart`'s `_handleNext` and
/// `salon_booking_schedule_notifier.dart`'s `enterTimePhase`). Mirrors
/// `salon_time_screen_test.dart`'s identical `_tapNextCta` helper (see that
/// file's doc comment) rather than inventing a second way to do the same
/// thing — acts on whichever slide is CURRENTLY ACTIVE in the pager.
Future<void> _tapNextCta(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('schedule-confirm-cta')));
  await AppHarness.settle(tester);
}

/// Locates one appointment [card]'s own «Разом» subtotal ROW — not a bare
/// price-text finder, which can't tell the subtotal apart from a same-priced
/// per-service line item above it (a master with exactly one service: the
/// line item and the summed total legitimately coincide, e.g. master-ccc's
/// single 400 ₴ service). Scopes via `_TotalRow`'s OWN accessibility label
/// (`booking_recap.dart`: `Semantics(label: l10n.bookingTotalSemantics(…))`,
/// which always starts with the same localized `bookingTotalLabel` word as
/// its visible "Разом" heading) — an existing structural anchor already
/// shipping in production, reused as-is (REUSE-FIRST: no widget touched).
Finder _totalRowFinder(WidgetTester tester, Finder card) {
  final AppLocalizations l10n = AppLocalizations.of(tester.element(card));
  return find.descendant(
    of: card,
    matching: find.bySemanticsLabel(
      RegExp('^${RegExp.escape(l10n.bookingTotalLabel)}'),
    ),
  );
}

// ---------------------------------------------------------------------------
// mobile-qa repair (pager port QA pass): the confirm/success screens have not
// called `bookingRepositoryProvider` since the Phase 271 / CARD RESTORATION
// rework — each appointment now submits via ONE
// `AppointmentSubmit.submitVisit` → `appointmentRepositoryProvider
// .createAppointment` call (see `salon_booking_confirm_screen.dart`'s
// `_submitOne`). The PRE-EXISTING `_FakeBookingRepository`/
// `_GatedBookingRepository` this replaces were `BookingRepository`-typed and
// overridden at `bookingRepositoryProvider` — a provider the production code
// path never reads any more, so every `repo.callsFor(...)` assertion built on
// them silently asserted against a fake NOTHING ever called (proven: `flutter
// test` on the pre-pager-port baseline reproduces the identical `Expected: 1
// / Actual: 0` failures — this break predates the pager rework and is NOT
// caused by it). This fake is `AppointmentRepository`-typed and overridden at
// `appointmentRepositoryProvider`, matching the REAL write path — mirrors
// `independent_multi_service_booking_flow_test.dart`'s
// `_FakeAppointmentRepository` precedent.
class _FakeAppointmentRepository implements AppointmentRepository {
  final Map<String, Failure> _failOnceWith = <String, Failure>{};
  final List<CreateAppointmentRequest> requests = <CreateAppointmentRequest>[];

  /// Configures [masterId]'s NEXT `createAppointment` call to throw
  /// [failure] exactly once; every subsequent call for that master succeeds
  /// normally (including a later resubmit carrying
  /// `allowClientOverlap: true`).
  void failWith(String masterId, Failure failure) =>
      _failOnceWith[masterId] = failure;

  int callsFor(String masterId) => requests
      .where((CreateAppointmentRequest r) => r.masterId == masterId)
      .length;

  List<CreateAppointmentRequest> requestsFor(String masterId) => requests
      .where((CreateAppointmentRequest r) => r.masterId == masterId)
      .toList(growable: false);

  @override
  Future<Appointment> createAppointment(CreateAppointmentRequest req) async {
    requests.add(req);
    final Failure? typed = _failOnceWith.remove(req.masterId);
    if (typed != null) throw typed;
    final DateTime end = req.startAt.add(const Duration(minutes: 60));
    return Appointment(
      id: 'appt-${req.masterId}',
      status: BookingStatus.confirmed,
      masterId: req.masterId,
      masterFirstName: 'Майстер',
      masterLastName: 'Салону',
      masterType: 'SALON_MASTER',
      startAt: req.startAt,
      endAt: end,
      totalDurationMinutes: 60,
      totalPrice: 500,
      items: <AppointmentItem>[
        for (final String id in req.masterServiceIds)
          AppointmentItem(
            bookingId: 'booking-$id',
            masterServiceId: id,
            serviceName: 'Послуга',
            startAt: req.startAt,
            endAt: end,
            durationMinutes: 60,
            price: 500,
          ),
      ],
    );
  }

  @override
  Future<Appointment> getAppointment(String id) => throw UnimplementedError();

  @override
  Future<Appointment> rescheduleAppointmentItem(
    String appointmentId,
    String bookingId,
    DateTime newStartAt,
  ) => throw UnimplementedError();

  @override
  Future<void> cancelAppointment(String id, {String? note}) =>
      throw UnimplementedError();

  @override
  Future<void> completeAppointment(String id) => throw UnimplementedError();
  @override
  Future<void> completeAppointmentService(
    String appointmentId,
    String bookingId,
  ) => throw UnimplementedError();

  @override
  Future<void> declineAppointment(String id, {String? comment}) =>
      throw UnimplementedError();

  @override
  Future<void> declineAppointmentService(
    String appointmentId,
    String bookingId, {
    String? comment,
  }) => throw UnimplementedError();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets('CLIENT books a salon service end to end: profile CTA → service '
      'selection → master assignment (ineligible masters filtered, eligible '
      'masters auto-attached) → coming-soon placeholder', (tester) async {
    await mockNetworkImagesFor(() async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      final repo = _FakeAppointmentRepository();
      final GoRouter router = await AppHarness.boot(
        tester,
        fb,
        extraOverrides: <Object>[
          appointmentRepositoryProvider.overrideWithValue(repo),
        ],
      );

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
      AppHarness.expectShellLocation(router, '/salons/salon-xyz');
      expect(find.byType(PublicSalonProfileScreen), findsOneWidget);

      // ── Tap "Записатись на послугу" → service selection (NOT a crash) ──
      final Finder bookCta = find.byKey(const Key('salon-book-cta'));
      expect(bookCta, findsOneWidget);
      await tester.tap(bookCta);
      await AppHarness.settle(tester);

      AppHarness.expectShellLocation(router, RouteNames.salonBookingServices);
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
      await tester.ensureVisible(exclusiveTile);
      await AppHarness.settle(tester);
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

      AppHarness.expectShellLocation(router, RouteNames.salonBookingMasters);
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

      // ── mobile-qa Rule 3b (KNOWN COVERAGE GAP fix): the bottom bar on this
      // master-assignment step now ALWAYS shows the client's selected
      // services in the same expandable `SelectedServicesShelf` the
      // service-selection step already used (previously it showed only the
      // "N assigned" progress counter, so the client lost sight of what they
      // picked). Proves the shelf's toggle genuinely expands against the REAL
      // `_AssignConfirmBar` and shows BOTH still-selected services — the
      // shelf always renders the client's FULL original selection,
      // independent of assignment state (neither master has been picked
      // yet here). ─────────────────────────────────────────────────────────
      await tester.tap(find.byKey(const Key('booking-summary-expand-toggle')));
      await AppHarness.settle(tester);
      final Finder masterStepShelfList = find.byKey(
        const Key('booking-summary-expanded-list'),
      );
      expect(masterStepShelfList, findsOneWidget);
      expect(
        find.descendant(
          of: masterStepShelfList,
          // i18n-finder-ok: real fixture wire data (salon-svc-shared's catalogue name), not translated UI copy.
          matching: find.text('Манікюр класичний'),
        ),
        findsOneWidget,
        reason:
            'the master-assignment step\'s pinned shelf must still show '
            'salon-svc-shared once expanded, exactly like the '
            'service-selection step did',
      );
      expect(
        find.descendant(
          of: masterStepShelfList,
          // i18n-finder-ok: real fixture wire data (salon-svc-exclusive's catalogue name), not translated UI copy.
          matching: find.text('Корекція брів'),
        ),
        findsOneWidget,
        reason:
            'and salon-svc-exclusive too — the shelf must never lose sight '
            'of either service the client picked on the previous step',
      );
      // Collapse back down before continuing — subsequent taps on this
      // screen target the body (master rows), not the bottom bar, but
      // leaving the shelf's own itemized list mounted needlessly grows the
      // pinned bar's height for no reason.
      await tester.tap(find.byKey(const Key('booking-summary-expand-toggle')));
      await AppHarness.settle(tester);

      // ── mobile-qa Rule 3b (card-unification audit): the picker's rows
      // render the SHARED `MasterStrip(showRating: true)` card end to end
      // against the REAL bookable-masters response — pin the ACTUAL rating
      // digits reach the screen through the whole real chain (never proven
      // outside an isolated widget test until now). master-ccc/master-ddd's
      // ratings come straight from `_salonMasters` above (4.6/9, 4.8/15).
      final Finder masterCccRow = find.byKey(
        const Key('salon_booking_master_row_master-ccc'),
      );
      final Finder masterDddRow = find.byKey(
        const Key('salon_booking_master_row_master-ddd'),
      );
      expect(
        find.descendant(of: masterCccRow, matching: find.text('4.6')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: masterCccRow, matching: find.text('(9)')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: masterDddRow, matching: find.text('4.8')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: masterDddRow, matching: find.text('(15)')),
        findsOneWidget,
      );

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
      AppHarness.expectShellLocation(router, RouteNames.salonBookingTime);
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

      // ── mobile-qa Rule 3b (KNOWN COVERAGE GAP fix): the time step's
      // pinned `ScheduleConfirmBar` also now ALWAYS shows the client's
      // selected services (flattened across every assigned master) in the
      // SAME shelf — proves the toggle expands against the REAL screen and
      // shows both services, before any date/time has been picked. ────────
      await tester.tap(find.byKey(const Key('booking-summary-expand-toggle')));
      await AppHarness.settle(tester);
      final Finder timeStepShelfList = find.byKey(
        const Key('booking-summary-expanded-list'),
      );
      expect(timeStepShelfList, findsOneWidget);
      expect(
        find.descendant(
          of: timeStepShelfList,
          // i18n-finder-ok: real fixture wire data (salon-svc-shared's catalogue name), not translated UI copy.
          matching: find.text('Манікюр класичний'),
        ),
        findsOneWidget,
        reason:
            'the time step\'s pinned shelf must show salon-svc-shared '
            '(master-ccc\'s assigned service) once expanded',
      );
      expect(
        find.descendant(
          of: timeStepShelfList,
          // i18n-finder-ok: real fixture wire data (salon-svc-exclusive's catalogue name), not translated UI copy.
          matching: find.text('Корекція брів'),
        ),
        findsOneWidget,
        reason:
            'and salon-svc-exclusive (master-ddd\'s assigned service) too — '
            'the shelf flattens EVERY assigned master\'s services, not just '
            'the currently-visible slide\'s',
      );
      // Collapse back down before driving the calendar/slot taps below —
      // those target keys scoped to each master's slide, unaffected either
      // way, but there is no reason to leave the itemized list mounted.
      await tester.tap(find.byKey(const Key('booking-summary-expand-toggle')));
      await AppHarness.settle(tester);

      // Two eligible masters (master-ccc, master-ddd) assigned in the
      // previous step → exactly two slider slides/dots.
      expect(find.byKey(const Key('salon-time-pager-dot-0')), findsOneWidget);
      expect(find.byKey(const Key('salon-time-pager-dot-1')), findsOneWidget);

      // mobile-qa Rule 3b: the schedule page's identity card is the SAME
      // shared `MasterStrip` — its ★rating must reach the current (master-ccc)
      // slide through the real chain too.
      expect(
        find.descendant(
          of: find.byKey(const Key('salon-schedule-page-master-ccc')),
          matching: find.text('4.6'),
        ),
        findsOneWidget,
      );

      // Scopes an interaction/assertion to one master's slide — needed
      // because BOTH slides can be simultaneously mounted (mobile-perf's
      // current±1 keep-alive bound), so an unscoped `booking-calendar-day-N`/
      // `salon-slot-chip-<iso>` key could otherwise match either slide.
      // `skipOffstage: false` so a kept-alive-but-currently-scrolled-off
      // slide is still reachable, mirroring
      // `salon_time_screen_test.dart`'s identical `withinSlide` helper.
      Finder slideOf(String masterId) =>
          find.byKey(Key('salon-schedule-page-$masterId'), skipOffstage: false);
      Finder withinSlide(String masterId, Finder matching) => find.descendant(
        of: slideOf(masterId),
        matching: matching,
        skipOffstage: false,
      );

      final DateTime today = kyivToday(() => kFixedNow);
      final int slotsCallsBeforeTime = fb.getMasterSlotsCalls;
      // `DateTime.utc` — the real chip key is built from the parsed UTC
      // `startAt.toIso8601String()`, which `_availableSlotsEnvelope` emits at
      // `availableSlotUtcStarts.first` (07:00Z, the fixture's documented
      // "morning" slot). A bare local `DateTime(...)` constructor here has no
      // trailing `Z` and performs no hour conversion, so the string could
      // never equal the real key on any host timezone.
      final String todaysMorningSlotIso = DateTime.utc(
        today.year,
        today.month,
        today.day,
        7,
      ).toIso8601String();

      // ── mobile-qa audit-fix cycle 1: pin the REAL working-days fetch
      // contract instead of the retired per-day-tap assertion below (proven
      // to fail identically with the pager work fully stashed out — a
      // pre-existing, pager-unrelated break). `MasterSchedulePage` fetches
      // `workingDaysProvider(_workingDaysQuery)` keyed on the VISIBLE MONTH,
      // on mount and on month change — never on a same-month day tap (see
      // `master_schedule_page.dart`'s `_workingDaysQuery`/`build`). Prove
      // BOTH halves over master-ccc's REAL slide/route pair: (1) navigating
      // to a different month hits `/masters/master-ccc/working-days` again,
      // (2) tapping a day already inside the month fetched on mount does
      // NOT. Half (2) is the one that would have caught the actual
      // regression this test is meant to guard (a dropped or duplicated
      // fetch), which the old "every tap increments" premise could not,
      // since it was never true.
      final int workingDaysCallsAtMount = fb.getWorkingDaysCalls;
      await tester.tap(
        withinSlide(
          'master-ccc',
          find.byKey(const Key('booking-calendar-next-month')),
        ),
      );
      await AppHarness.settle(tester);
      expect(
        fb.getWorkingDaysCalls,
        greaterThan(workingDaysCallsAtMount),
        reason:
            "navigating master-ccc's calendar to a new month must hit the "
            'real working-days endpoint for that month — the per-month '
            'fetch contract `_workingDaysQuery` implements',
      );
      await tester.tap(
        withinSlide(
          'master-ccc',
          find.byKey(const Key('booking-calendar-prev-month')),
        ),
      );
      await AppHarness.settle(tester);

      final int workingDaysCallsBeforeTodayTap = fb.getWorkingDaysCalls;

      // ── Master-ccc's slide (current, index 0) — pick today's date, which
      // is already inside the month fetched on mount, so it must NOT
      // re-fetch working-days; the FETCHED-state calendar renders today as
      // tappable straight from that already-resolved data. The slot fetch
      // below is a genuinely separate `GET /masters/master-ccc/slots`
      // round-trip triggered by entering the time phase. ──────────────────
      await tester.tapCalendarDay(today.day, within: slideOf('master-ccc'));
      await AppHarness.settle(tester);
      expect(
        fb.getWorkingDaysCalls,
        equals(workingDaysCallsBeforeTodayTap),
        reason:
            "tapping today's date must NOT trigger a new working-days "
            'fetch — today is already inside the month fetched on mount; a '
            'per-day-tap refetch would regress the per-month contract',
      );

      // mobile-qa audit-fix cycle 2: commit master-ccc's picked date into
      // the TIME phase via the step-3 CTA — commit 92644d2e retired the
      // old auto-advance-on-date-tap contract, so the date pick alone no
      // longer swaps this slide to its slot grid.
      await _tapNextCta(tester);

      // ── Phase 14.16/14.17 back-navigation BUGFIX regression guard
      // (Step 2.7 Rule 3b) — end-to-end proof, over the REAL router/
      // backend chain, of the exact production bug: once master-ccc's date
      // was picked, this slide's in-widget `AnimatedSwitcher` swapped from
      // the calendar to the time-slot grid with NO route behind that
      // transition, so pressing back used to pop the ENTIRE
      // `SalonTimeScreen` route all the way out to master-selection instead
      // of returning just this slide to its calendar — losing the client's
      // place. The widget tier (`salon_time_screen_test.dart`) proves both
      // back affordances (the in-app arrow AND the Android system back
      // gesture) against a hand-written fake; this is the ONE place the fix
      // is proven against the real `GoRouter`/`AppHarness` stack this
      // journey actually runs on. ────────────────────────────────────────
      expect(
        withinSlide('master-ccc', find.byKey(const ValueKey<String>('time'))),
        findsOneWidget,
        reason:
            'picking the date must have swapped this slide into the '
            'time phase before the back press below is meaningful',
      );

      await tester.tap(find.byKey(const Key('salon-time-back')));
      await AppHarness.settle(tester);

      AppHarness.expectShellLocation(router, RouteNames.salonBookingTime);
      expect(
        find.byType(SalonTimeScreen),
        findsOneWidget,
        reason:
            'back from the time phase must NOT pop the whole screen out to '
            'master-selection — the exact production bug this guards',
      );
      expect(find.byType(SalonMasterSelectionScreen), findsNothing);
      expect(
        withinSlide(
          'master-ccc',
          find.byKey(const Key('booking-month-calendar')),
        ),
        findsOneWidget,
        reason:
            'master-ccc\'s slide must have reverted to its OWN calendar, '
            'not lost the client\'s place in the flow',
      );
      expect(
        withinSlide('master-ccc', find.byKey(const ValueKey<String>('time'))),
        findsNothing,
      );

      // Re-pick the date so the flow below (slot selection) proceeds
      // exactly as it did before this regression guard was inserted.
      await tester.tapCalendarDay(today.day, within: slideOf('master-ccc'));
      await AppHarness.settle(tester);
      // mobile-qa audit-fix cycle 2: the swipe-back guard below targets
      // `salon-schedule-time-edge-back-swipe`, a hit-strip that only exists
      // in the TIME phase (`master_schedule_page.dart`'s `_timePhase`) — so
      // this slide must be committed into it via the CTA first.
      await _tapNextCta(tester);

      // ── Left-edge swipe-back regression guard (mobile-qa Rule 3b, salon
      // "Час" swipe-back gap-fix) — end-to-end proof, over the REAL
      // router/backend chain, of the THIRD phase-back affordance: a
      // rightward drag on `MasterSchedulePage`'s left-edge hit-strip
      // (`salon-schedule-time-edge-back-swipe`) restores the swipe-back
      // feel the route-level `PopScope(canPop: false)` silently disarms
      // (Cupertino never arms its own edge-drag recognizer while `canPop`
      // is false). The widget tier (`salon_time_screen_test.dart`) already
      // proves this against a hand-written fake; this is the ONE place it
      // is proven against the real `GoRouter`/`AppHarness` stack this
      // journey actually runs on — and specifically that it lands the
      // client back on master-ccc's OWN calendar, never a route pop out to
      // master-selection. ─────────────────────────────────────────────────
      await tester.drag(
        withinSlide(
          'master-ccc',
          find.byKey(const Key('salon-schedule-time-edge-back-swipe')),
        ),
        const Offset(120, 0),
      );
      await AppHarness.settle(tester);

      AppHarness.expectShellLocation(router, RouteNames.salonBookingTime);
      expect(
        find.byType(SalonTimeScreen),
        findsOneWidget,
        reason:
            'the edge swipe is a slide-local gesture, never a route pop — '
            'SalonTimeScreen itself must stay mounted',
      );
      expect(find.byType(SalonMasterSelectionScreen), findsNothing);
      expect(
        withinSlide(
          'master-ccc',
          find.byKey(const Key('booking-month-calendar')),
        ),
        findsOneWidget,
        reason:
            "the edge swipe must land the client back on master-ccc's OWN "
            'calendar, not on master-selection',
      );
      expect(
        withinSlide('master-ccc', find.byKey(const ValueKey<String>('time'))),
        findsNothing,
      );

      // Re-pick the date once more so the rest of the flow (slot selection)
      // proceeds exactly as it did before this guard was inserted.
      await tester.tapCalendarDay(today.day, within: slideOf('master-ccc'));
      await AppHarness.settle(tester);
      // mobile-qa audit-fix cycle 2: the slot chip below only mounts once
      // this slide is committed into its TIME phase.
      await _tapNextCta(tester);

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

      // ── CTA-driven pager advance (mobile-qa audit-fix cycle 2 — commit
      // 92644d2e retired the old auto-advance-off-a-slot-tap contract):
      // master-ccc now has both a date and a time, so this SECOND CTA
      // press (the first committed the date into the TIME phase above)
      // reads `nextUnscheduledIndex` and animates the REAL PageController
      // onto the next unscheduled master (master-ddd) — proving that
      // lookup genuinely drives the pager over two independently-fetched
      // masters, not just the one hardcoded roster master a prior Phase
      // 14.13 bug would have left this untested against. ─────────────────
      await _tapNextCta(tester);

      final Finder dddCalendarDay = withinSlide(
        'master-ddd',
        find.byKey(Key('booking-calendar-day-${today.day}')),
      );
      expect(
        dddCalendarDay,
        findsOneWidget,
        reason:
            'the CTA press above must have advanced the pager onto '
            "master-ddd's date phase now that master-ccc is fully "
            'scheduled',
      );

      await tester.tapCalendarDay(today.day, within: slideOf('master-ddd'));
      await AppHarness.settle(tester);
      // mobile-qa audit-fix cycle 2: commit master-ddd's picked date into
      // the TIME phase the same way master-ccc's was above.
      await _tapNextCta(tester);

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
      // enables, and tapping it is PURE forward navigation to the step-4
      // confirmation screen (Phase 14.18 — replaced the retired coming-soon
      // placeholder), NOT a `POST /bookings` call yet (the submit lives on
      // the confirm screen), and NEVER the independent-master SlotPickerScreen
      // (that flow assumes a single masterId, which a salon booking never
      // has). ─────────────────────────────────────────────────────────────
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

      AppHarness.expectShellLocation(router, RouteNames.salonBookingConfirm);
      expect(find.byType(SalonBookingConfirmScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      // No booking has been written by merely reaching the confirm screen.
      expect(repo.requests, isEmpty);

      // ── PAGER REWORK (2026-08-23): one master's card on screen at a time,
      // paged via the centred `‹ N / M ›` control — NOT both simultaneously
      // mounted, and no visit-wide grand total anywhere. ───────────────────
      final Finder confirmCccCard = find.byKey(
        const ValueKey<String>('salon-confirm-appt-master-ccc'),
      );
      final Finder confirmDddCard = find.byKey(
        const ValueKey<String>('salon-confirm-appt-master-ddd'),
      );
      final Finder confirmPrev = find.byKey(
        const Key('appointment-pager-prev'),
      );
      final Finder confirmNext = find.byKey(
        const Key('appointment-pager-next'),
      );

      // Page 0: master-ccc mounted, master-ddd NOT (PageView.builder only
      // builds the current page).
      expect(confirmCccCard, findsOneWidget);
      expect(confirmDddCard, findsNothing);
      // i18n-finder-ok: numeric pager counter, not translated UI copy.
      expect(find.text('1 / 2'), findsOneWidget);
      expect(
        tester.widget<GestureDetector>(confirmPrev).onTapUp,
        isNull,
        reason: 'page 0 is the first master — the prev arrow must be inert',
      );
      expect(tester.widget<GestureDetector>(confirmNext).onTapUp, isNotNull);

      // The grand-total card is GONE — asserting its key is absent, not just
      // that a stale value is absent, so a regression that re-adds ANY card
      // under that key (even with a different total) still fails this.
      expect(
        find.byKey(const Key('salon-confirm-grand-total-card')),
        findsNothing,
      );
      // i18n-finder-ok: summed price is real fixture-derived data, not translated UI copy.
      expect(find.text('700 ₴'), findsNothing);

      // ── mobile-qa Rule 3b (KNOWN COVERAGE GAPS): the shared salon-address
      // card and each appointment card's ★rating/subtotal had no end-to-end
      // proof against the REAL public-salon-profile response and the REAL
      // bookable-masters roster. ────────────────────────────────────────────
      final Finder confirmAddressCard = find.byKey(
        const Key('salon-confirm-address-card'),
      );
      expect(confirmAddressCard, findsOneWidget);
      expect(
        find.descendant(
          of: confirmAddressCard,
          // i18n-finder-ok: address is real fixture wire data, not translated UI copy.
          matching: find.text('вул. Хрещатик, 12'),
        ),
        findsOneWidget,
        reason:
            'the real `publicSalonProfileProvider` response must resolve '
            "into the address card's value — salon-xyz has no legacy "
            '`city` field (Phase 10.6+ taxonomy-only fixture), so the line '
            'is street+buildingNo only, no trailing city',
      );

      // master-ccc's OWN subtotal (salon-svc-shared, 400 ₴/60 min raw
      // backend `priceDisplay` fixture) + rating, on page 0.
      expect(
        find.descendant(of: confirmCccCard, matching: find.text('4.6')),
        findsOneWidget,
      );
      // Scoped to the «Разом» ROW itself (via its own accessibility label —
      // see `_totalRowFinder`), not a bare price-text finder — master-ccc has
      // exactly one 400 ₴ service, so its line-item price and its own
      // subtotal legitimately COINCIDE at "400 ₴" and a bare `find.text`
      // matches both (2 widgets), unable to tell a correct render from a
      // regression that dropped the subtotal and left only the line item.
      final Finder cccTotalRow = _totalRowFinder(tester, confirmCccCard);
      expect(
        cccTotalRow,
        findsOneWidget,
        reason:
            "master-ccc's own «Разом» subtotal row must survive the pager "
            'rework even with the visit-wide total gone',
      );
      expect(
        find.descendant(of: cccTotalRow, matching: find.text('400 ₴')),
        findsOneWidget,
        reason:
            "master-ccc's «Разом» subtotal must read 400 ₴ — its one "
            'salon-svc-shared service at that price',
      );

      // ── Page via the NEXT arrow → master-ddd's page. ─────────────────────
      await tester.tap(confirmNext);
      await AppHarness.settle(tester);

      expect(confirmDddCard, findsOneWidget);
      expect(confirmCccCard, findsNothing);
      // i18n-finder-ok: numeric pager counter, not translated UI copy.
      expect(find.text('2 / 2'), findsOneWidget);
      expect(
        tester.widget<GestureDetector>(confirmNext).onTapUp,
        isNull,
        reason: 'page 1 is the LAST master — the next arrow must be inert',
      );
      expect(tester.widget<GestureDetector>(confirmPrev).onTapUp, isNotNull);

      // master-ddd's OWN subtotal (salon-svc-exclusive, 300 ₴/45 min) +
      // rating, on page 1 — never master-ccc's.
      expect(
        find.descendant(of: confirmDddCard, matching: find.text('4.8')),
        findsOneWidget,
      );
      // Same finder-scoping as master-ccc's subtotal above: master-ddd also
      // has exactly one service (salon-svc-exclusive, 300 ₴), so its
      // line-item price and its own «Разом» subtotal coincide at "300 ₴" —
      // a bare `find.text` can't tell them apart.
      final Finder dddTotalRow = _totalRowFinder(tester, confirmDddCard);
      expect(dddTotalRow, findsOneWidget);
      expect(
        find.descendant(of: dddTotalRow, matching: find.text('300 ₴')),
        findsOneWidget,
      );

      // Page back to master-ccc before submitting — proves the prev arrow
      // round-trips, and leaves the visible page irrelevant to the submit
      // below (the CTA submits the WHOLE visit regardless of which page is
      // on screen — `_submit()` iterates `widget.args.appointments`, not
      // mounted widgets).
      await tester.tap(confirmPrev);
      await AppHarness.settle(tester);
      expect(confirmCccCard, findsOneWidget);

      // ── Submit: one `POST /appointments` per master → all succeed →
      // success screen. This is the booking-WRITE the flow performs end to
      // end (Step 2.7 Rule 3b). ─────────────────────────────────────────────
      await tester.tap(find.byKey(const Key('salon-confirm-submit-cta')));
      await AppHarness.settle(tester);

      AppHarness.expectShellLocation(router, RouteNames.salonBookingSuccess);
      expect(find.byType(SalonBookingSuccessScreen), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Exactly one `createAppointment` per master, REGARDLESS of which page
      // was on screen when the CTA was tapped — the pager must never let
      // only the visible master submit. Each carries that master's OWN
      // service-ASSIGNMENT id (never the salon-wide catalog id) — the same
      // masterService-not-found regression guarded at the slots step, now
      // proven all the way through the write.
      expect(repo.callsFor('master-ccc'), 1);
      expect(repo.callsFor('master-ddd'), 1);
      expect(repo.requestsFor('master-ccc').single.masterServiceIds, <String>[
        'assign-master-ccc-salon-svc-shared',
      ]);
      expect(repo.requestsFor('master-ddd').single.masterServiceIds, <String>[
        'assign-master-ddd-salon-svc-exclusive',
      ]);

      // ── Success screen: same pager rework — one master's recap + its OWN
      // «Додати в календар» pill(s) at a time, no visit-wide grand total. ──
      final Finder successCccCard = find.byKey(
        const ValueKey<String>('salon-success-appt-master-ccc'),
      );
      final Finder successDddCard = find.byKey(
        const ValueKey<String>('salon-success-appt-master-ddd'),
      );
      final Finder successNext = find.byKey(
        const Key('appointment-pager-next'),
      );

      expect(successCccCard, findsOneWidget);
      expect(successDddCard, findsNothing);
      // i18n-finder-ok: numeric pager counter, not translated UI copy.
      expect(find.text('1 / 2'), findsOneWidget);
      expect(
        find.byKey(const Key('salon-success-grand-total-card')),
        findsNothing,
      );
      // i18n-finder-ok: summed price is real fixture-derived data, not translated UI copy.
      expect(find.text('700 ₴'), findsNothing);

      // ── mobile-qa Rule 3b: the same shared address/rating info-parity
      // gaps, now proven on the CONFIRMED recap too. ───────────────────────
      final Finder successAddressCard = find.byKey(
        const Key('salon-success-address-card'),
      );
      expect(successAddressCard, findsOneWidget);
      expect(
        find.descendant(
          of: successAddressCard,
          // i18n-finder-ok: address is real fixture wire data, not translated UI copy.
          matching: find.text('вул. Хрещатик, 12'),
        ),
        findsOneWidget,
      );

      expect(
        find.descendant(of: successCccCard, matching: find.text('4.6')),
        findsOneWidget,
      );
      // master-ccc's ONE booking (one service) → ONE calendar pill, on
      // page 0 — the 1-service-1-booking calendar-button contract.
      expect(
        find.byKey(const ValueKey<String>('salon-success-calendar-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('salon-success-add-calendar-0-0')),
        findsOneWidget,
      );

      await tester.tap(successNext);
      await AppHarness.settle(tester);

      expect(successDddCard, findsOneWidget);
      expect(successCccCard, findsNothing);
      // i18n-finder-ok: numeric pager counter, not translated UI copy.
      expect(find.text('2 / 2'), findsOneWidget);
      expect(
        find.descendant(of: successDddCard, matching: find.text('4.8')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('salon-success-calendar-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('salon-success-add-calendar-1-0')),
        findsOneWidget,
      );
    });
  }, timeout: const Timeout(Duration(seconds: 120)));

  // ── Partial-failure variant (Step 2.7 Rule 3b) — mobile-qa repair ────────
  // The full search→salon→services→masters→time journey is already proven end
  // to end by the flow above; this variant targets the partial-failure path
  // specifically, reached via a real `router.push` of the confirm route
  // (through the REAL CLIENT route guard) with a fully-resolved two-master
  // `SalonBookingConfirmArgs`. m-two's FIRST `POST /appointments` fails with
  // a 409 (stale slot) → the confirm screen STAYS with the single inline
  // error banner; retrying resubmits EVERY appointment from the start
  // (`_submit()` iterates `widget.args.appointments`, not a per-master
  // status — see `salon_booking_confirm_screen.dart`'s file header
  // "INTERIM STATE" note: there is deliberately no retry-only-the-failed-
  // ones tracking yet) and reaches success. This is a REPAIR, not just a
  // pager-key fix: the pre-existing `_FakeBookingRepository` this test used
  // was `BookingRepository`-typed at `bookingRepositoryProvider`, a provider
  // the confirm screen has not read since before the pager rework — every
  // `repo.callsFor(...)` below silently asserted 0 against a fake nothing
  // ever called (reproduced on the pre-pager-port baseline too — PRE-
  // EXISTING, unrelated to this port). The title's old "retry re-submits
  // ONLY the failed master" claim was ALSO stale against the current
  // sequential-full-resubmit contract — corrected below.
  testWidgets(
    'CLIENT salon confirm: a 409 on one master keeps the confirm screen; '
    'retry resubmits every appointment (including the already-succeeded '
    'one, deduped server-side by its stable idempotency key) and reaches '
    'success',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()..currentRole = UserRole.client;
        // m-two's first createAppointment fails (409), then succeeds.
        final repo = _FakeAppointmentRepository()
          ..failWith('m-two', const ConflictFailure());
        final GoRouter router = await AppHarness.boot(
          tester,
          fb,
          extraOverrides: <Object>[
            appointmentRepositoryProvider.overrideWithValue(repo),
          ],
        );

        await AppHarness.loginAs(tester, fb, UserRole.client);
        await AppHarness.settle(tester);

        SalonBookingAppointment appt(
          String masterId,
          String firstName,
        ) => SalonBookingAppointment(
          schedule: SalonMasterSchedule(
            masterId: masterId,
            firstName: firstName,
            lastName: 'Майстер',
            type: MasterType.salonMaster,
            services: <SalonCatalogService>[
              SalonCatalogService(
                id: 'svc-$masterId',
                name: 'Манікюр',
                durationLabel: '1 год',
                priceDisplay: '500 ₴',
                durationMinutes: 60,
                priceType: ServicePriceType.fixed,
                priceMin: 500,
              ),
            ],
            orderedMasterServiceIds: <String>['assign-$masterId'],
          ),
          // instant-ok: arbitrary future filler for a directly-pushed confirm/success fixture, never compared against a calendar day
          startAt: DateTime.now().add(const Duration(days: 1)),
          idempotencyKey: 'idem-$masterId',
        );

        unawaited(
          router.push(
            RouteNames.salonBookingConfirm,
            extra: SalonBookingConfirmArgs(
              salonId: 'salon-xyz',
              appointments: <SalonBookingAppointment>[
                appt('m-one', 'Олена'),
                appt('m-two', 'Софія'),
              ],
            ),
          ),
        );
        await AppHarness.settle(tester);

        AppHarness.expectShellLocation(router, RouteNames.salonBookingConfirm);
        expect(find.byType(SalonBookingConfirmScreen), findsOneWidget);

        // First submit → m-two fails (409) → stay on confirm.
        await tester.tap(find.byKey(const Key('salon-confirm-submit-cta')));
        await AppHarness.settle(tester);

        AppHarness.expectShellLocation(router, RouteNames.salonBookingConfirm);
        expect(find.byType(SalonBookingConfirmScreen), findsOneWidget);
        expect(find.byType(SalonBookingSuccessScreen), findsNothing);
        expect(repo.callsFor('m-one'), 1);
        expect(repo.callsFor('m-two'), 1);

        // Retry → m-two now succeeds (fail-once consumed) → success.
        await tester.tap(find.byKey(const Key('salon-confirm-submit-cta')));
        await AppHarness.settle(tester);

        AppHarness.expectShellLocation(router, RouteNames.salonBookingSuccess);
        expect(find.byType(SalonBookingSuccessScreen), findsOneWidget);
        // Current contract (no retry-only-the-failed-ones tracking): the
        // retry resubmits BOTH appointments from the start — m-one twice
        // (already succeeded on attempt 1, resubmitted harmlessly on
        // attempt 2 — the server de-dupes on the reused idempotency key),
        // m-two twice (fail + retry).
        expect(repo.callsFor('m-one'), 2);
        expect(repo.callsFor('m-two'), 2);
        expect(
          repo
              .requestsFor('m-one')
              .map((CreateAppointmentRequest r) => r.idempotencyKey)
              .toSet(),
          <String>{'idem-m-one'},
          reason:
              'm-one\'s resubmit must reuse its ORIGINAL idempotency '
              'key, never mint a new one',
        );
        expect(
          repo
              .requestsFor('m-two')
              .map((CreateAppointmentRequest r) => r.idempotencyKey)
              .toSet(),
          <String>{'idem-m-two'},
        );
        expect(tester.takeException(), isNull);
      });
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  // ── mobile-qa repair — CLIENT_BOOKING_CONFLICT on one master opens the
  // NON-destructive `ClientBookingConflictDialog` (owner decision,
  // 2026-08-22 — see `salon_booking_confirm_screen.dart`'s file header
  // CLIENT-SELF-OVERLAP note), never a per-card message — the PRE-EXISTING
  // version of this test asserted a per-card conflict SENTENCE and a
  // per-card «Заплановано» success status, neither of which exists any
  // more (no per-master submit status at all — see that same file header's
  // INTERIM STATE note); it also overrode the wrong provider
  // (`bookingRepositoryProvider`, never read by this path — see the repair
  // note on the 409 test above). Rewritten to drive the REAL dialog: the
  // client already has an overlapping booking with a THIRD, unrelated
  // master/salon — m-two's own slot is perfectly fine, this is the CLIENT
  // double-booking themselves, not a slot conflict. Confirming resubmits
  // m-two ONLY, with `allowClientOverlap: true`, inside the SAME CTA tap
  // (the dialog await lives inside `_submitOne`, not a second submit) —
  // m-one is entirely unaffected. ───────────────────────────────────────────
  testWidgets(
    'CLIENT salon confirm: a CLIENT_BOOKING_CONFLICT on one master opens '
    'the non-destructive conflict dialog; confirming resubmits ONLY that '
    'master and reaches success, leaving the other master untouched',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()..currentRole = UserRole.client;
        // The client's PRE-EXISTING clashing booking, delivered as a 409
        // payload — not a fixture that must read as "upcoming". It reaches only
        // `ClientBookingConflictFailure.userMessage` → `formatBookingWindow`, a
        // pure absolute formatter with no `now()` in it, and no assertion below
        // reads the rendered date; a fixed instant is more deterministic here.
        // future-date-ok: clashing booking's own window, see note above.
        final DateTime clashStart = DateTime.utc(2026, 7, 15, 14);
        final ClientBookingConflictFailure conflict =
            ClientBookingConflictFailure(
              conflictingBookingId: 'other-booking-1',
              serviceName: 'Педикюр апаратний',
              masterName: 'Ірина Шевченко',
              startsAt: clashStart,
              endsAt: clashStart.add(const Duration(minutes: 45)),
            );
        final repo = _FakeAppointmentRepository();
        final GoRouter router = await AppHarness.boot(
          tester,
          fb,
          extraOverrides: <Object>[
            appointmentRepositoryProvider.overrideWithValue(repo),
          ],
        );

        await AppHarness.loginAs(tester, fb, UserRole.client);
        await AppHarness.settle(tester);

        SalonBookingAppointment appt(
          String masterId,
          String firstName,
        ) => SalonBookingAppointment(
          schedule: SalonMasterSchedule(
            masterId: masterId,
            firstName: firstName,
            lastName: 'Майстер',
            type: MasterType.salonMaster,
            services: <SalonCatalogService>[
              SalonCatalogService(
                id: 'svc-$masterId',
                name: 'Манікюр',
                durationLabel: '1 год',
                priceDisplay: '500 ₴',
                durationMinutes: 60,
                priceType: ServicePriceType.fixed,
                priceMin: 500,
              ),
            ],
            orderedMasterServiceIds: <String>['assign-$masterId'],
          ),
          // instant-ok: arbitrary future filler for a directly-pushed confirm/success fixture, never compared against a calendar day
          startAt: DateTime.now().add(const Duration(days: 1)),
          idempotencyKey: 'idem-$masterId',
        );

        unawaited(
          router.push(
            RouteNames.salonBookingConfirm,
            extra: SalonBookingConfirmArgs(
              salonId: 'salon-xyz',
              appointments: <SalonBookingAppointment>[
                appt('m-one', 'Олена'),
                appt('m-two', 'Софія'),
              ],
            ),
          ),
        );
        await AppHarness.settle(tester);
        AppHarness.expectShellLocation(router, RouteNames.salonBookingConfirm);

        // m-two's write fails with the CLIENT's own conflict (unrelated
        // third booking).
        repo.failWith('m-two', conflict);

        // ONE tap on the CTA drives the WHOLE journey here: m-one submits
        // and succeeds, then m-two's conflict opens the dialog INSIDE the
        // same `_submitOne` call (awaited before `_submit`'s loop can move
        // on) — unlike the generic-409 test above, there is no separate
        // "tap again" step; confirming the dialog resubmits m-two in place.
        await tester.tap(find.byKey(const Key('salon-confirm-submit-cta')));
        await AppHarness.settle(tester);

        // Still on confirm — the dialog is up, m-one already settled.
        AppHarness.expectShellLocation(router, RouteNames.salonBookingConfirm);
        expect(find.byType(SalonBookingSuccessScreen), findsNothing);
        expect(repo.callsFor('m-one'), 1);
        expect(repo.callsFor('m-two'), 1);

        final Finder dialog = find.byKey(
          const Key('client-booking-conflict-dialog'),
        );
        expect(
          dialog,
          findsOneWidget,
          reason:
              'a CLIENT_BOOKING_CONFLICT must open the non-destructive '
              'dialog, never the bottom error banner',
        );
        expect(
          find.byKey(const Key('salon-confirm-submit-error')),
          findsNothing,
          reason:
              'the bottom banner is reserved for every OTHER failure — '
              'see the CLIENT-SELF-OVERLAP file-header note',
        );

        // The dialog names m-two's NEW booking and the THIRD, unrelated
        // clashing booking the server reported — never a generic sentence.
        final Finder existingRow = find.byKey(
          const Key('client-booking-conflict-existing'),
        );
        expect(
          find.descendant(
            of: existingRow,
            // i18n-finder-ok: fixture-derived clash data, not translated UI copy.
            matching: find.text('Педикюр апаратний'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: existingRow,
            matching: find.textContaining('Ірина Шевченко'),
          ),
          findsOneWidget,
        );
        final Finder newRow = find.byKey(
          const Key('client-booking-conflict-new'),
        );
        expect(
          find.descendant(of: newRow, matching: find.textContaining('Софія')),
          findsOneWidget,
          reason:
              "the dialog's own booking side must name m-two "
              '(Софія), never m-one',
        );

        // Confirm — resubmits ONLY m-two, with allowClientOverlap: true.
        await tester.tap(
          find.byKey(const Key('client-booking-conflict-proceed')),
        );
        await AppHarness.settle(tester);

        AppHarness.expectShellLocation(router, RouteNames.salonBookingSuccess);
        expect(find.byType(SalonBookingSuccessScreen), findsOneWidget);
        // m-one untouched (never resubmitted); m-two resubmitted exactly
        // once more (fail + confirmed resubmit).
        expect(repo.callsFor('m-one'), 1);
        expect(repo.callsFor('m-two'), 2);
        expect(
          repo.requestsFor('m-two').last.allowClientOverlap,
          isTrue,
          reason:
              "the confirmed resubmit must carry allowClientOverlap: "
              'true — the ONE-SHOT flag this dialog exists to set',
        );
        expect(
          repo.requestsFor('m-one').single.allowClientOverlap,
          isFalse,
          reason:
              "m-one's own submit must never inherit m-two's overlap "
              'flag',
        );
        expect(tester.takeException(), isNull);
      });
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  // ── RETIRED (mobile-qa repair, 2026-08-23): the `showSucceededStatus`
  // regression guard this test protected no longer has a subject. It
  // asserted an already-succeeded master's «Заплановано» per-card status
  // survived a partial failure + a mid-retry in-flight window — but
  // `SalonAppointmentCard`'s own file header (`widgets/salon_appointment_card
  // .dart`) is explicit that the per-appointment submit-status enum
  // (`status`/`failure`/`showSucceededStatus`) was NOT restored: "per-master
  // submit status is a later phase's job". There is no per-card status of
  // any kind on the current confirm screen — `find.text
  // (l10n.salonBookingAppointmentSucceeded)` (an ARB key with, as of this
  // repair, no remaining production consumer — flagged to
  // `docs/mobile-phases/mobile-backlog.md` for a follow-up ARB-parity
  // cleanup pass) could never have matched anything, and this test's
  // `_GatedBookingRepository` was ALSO `BookingRepository`-typed at
  // `bookingRepositoryProvider` — the same wrong-provider defect as the two
  // repaired tests above, so it never drove the real write path at all. Not
  // weakened into a smoke test: DELETED, because its premise is gone, not
  // because it was inconvenient to fix. The one piece of remaining value —
  // "the retry resubmits everything and reaches success" — is covered by
  // the repaired 409-partial-failure test above (`repo.callsFor('m-one'),
  // 2`). See the QA audit report for the full CRITICAL/pre-existing finding.
}
