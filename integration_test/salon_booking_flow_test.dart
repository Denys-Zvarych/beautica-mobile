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
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/create_booking_request.dart';
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
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

// ---------------------------------------------------------------------------
// Phase 14.18 — recording fake BookingRepository injected into the harness so
// the salon confirmation screen's N `POST /bookings` submit runs against an
// in-memory fake instead of the real generated Dio client. Overriding the
// repository provider (rather than registering the wire route in the
// DioAdapter) is deliberate: it avoids the generated booking client's
// real-Dio timer (backlog #185's timer-leak pattern) while still exercising
// the REAL `SalonBookingSubmit` notifier + confirm/success screens + router
// pushReplacement end to end. Each configured master fails EXACTLY ONCE (then
// succeeds on retry), so the partial-failure/retry path is driveable.
class _FakeBookingRepository implements BookingRepository {
  _FakeBookingRepository({Set<String> failOnce = const <String>{}})
    : _failOnce = <String>{...failOnce};

  final Set<String> _failOnce;
  // mobile-qa gap-fix — masterId → an arbitrary Failure to throw exactly
  // once (then clear), for scenarios where the plain `ConflictFailure` the
  // constructor's `failOnce` set always throws is the WRONG failure shape —
  // e.g. a CLIENT_BOOKING_CONFLICT test needs a typed
  // `ClientBookingConflictFailure` with specific field values, not a generic
  // conflict. Checked BEFORE `_failOnce` so a call site can use either knob.
  final Map<String, Failure> _failOnceWith = <String, Failure>{};
  final List<CreateBookingRequest> requests = <CreateBookingRequest>[];

  /// Configures [masterId]'s NEXT `createBooking` call to throw [failure]
  /// exactly once; every subsequent call for that master succeeds normally.
  void failWith(String masterId, Failure failure) =>
      _failOnceWith[masterId] = failure;

  int callsFor(String masterId) =>
      requests.where((CreateBookingRequest r) => r.masterId == masterId).length;

  List<CreateBookingRequest> requestsFor(String masterId) => requests
      .where((CreateBookingRequest r) => r.masterId == masterId)
      .toList(growable: false);

  @override
  Future<Booking> createBooking(CreateBookingRequest req) async {
    requests.add(req);
    final Failure? typed = _failOnceWith.remove(req.masterId);
    if (typed != null) throw typed;
    if (_failOnce.remove(req.masterId)) throw const ConflictFailure();
    return Booking(
      id: 'booking-${req.masterId}',
      masterId: req.masterId,
      masterFirstName: 'Майстер',
      masterLastName: 'Салону',
      masterType: 'SALON_MASTER',
      serviceId: req.serviceId,
      serviceName: 'Послуга',
      durationMinutes: 60,
      price: 500,
      startAt: req.startAt,
      endAt: req.startAt.add(const Duration(minutes: 60)),
      status: BookingStatus.pending,
      canReview: false,
    );
  }

  @override
  Future<PageResponse<Booking>> getMyBookings({
    required Set<BookingStatus> statuses,
    required bool ascending,
    required int page,
    int size = kBookingsPageSize,
  }) => throw UnimplementedError();

  @override
  Future<Booking> getBookingById(String id) => throw UnimplementedError();

  @override
  Future<void> createReview({
    required String bookingId,
    required int rating,
    String? comment,
  }) => throw UnimplementedError();

  @override
  Future<void> cancelBooking(String id, {String? reason}) =>
      throw UnimplementedError();

  @override
  Future<Booking> rescheduleBooking(String id, DateTime newStartAt) =>
      throw UnimplementedError();
}

// ---------------------------------------------------------------------------
// mobile-qa regression coverage (Phase 14.18 bugfix follow-up) — Step 2.7
// Rule 3b: the `showSucceededStatus` gate fix (see
// `test/features/booking/presentation/widgets/salon_appointment_card_test.dart`'s
// file header for the full bug narrative) touches a real user journey
// (salon submit → partial failure → retry), so it needs end-to-end coverage,
// not only the widget tier.
//
// `_FakeBookingRepository` above resolves every call on a plain `async`
// function with no real `await`, so every request is already settled by the
// time a single `pump()` looks — it can never hold the retry's in-flight
// window open long enough to observe it. This gated variant queues a
// `Completer` per call instead, so the test can resolve master-one and
// master-two independently and inspect the screen while master-two's retry
// POST is still pending — the exact window the FIRST (buggy) attempt at this
// fix got wrong (see `salon_booking_confirm_screen.dart`'s
// `_AppointmentCardSlot` doc comment).
// ---------------------------------------------------------------------------
class _GatedBookingRepository implements BookingRepository {
  final Map<String, List<Completer<Booking>>> _queue =
      <String, List<Completer<Booking>>>{};
  final List<CreateBookingRequest> requests = <CreateBookingRequest>[];

  int callsFor(String masterId) =>
      requests.where((CreateBookingRequest r) => r.masterId == masterId).length;

  @override
  Future<Booking> createBooking(CreateBookingRequest req) {
    requests.add(req);
    final Completer<Booking> completer = Completer<Booking>();
    _queue
        .putIfAbsent(req.masterId, () => <Completer<Booking>>[])
        .add(completer);
    return completer.future;
  }

  /// Resolves the OLDEST not-yet-resolved call for [masterId] as a success.
  void succeed(String masterId) {
    final Completer<Booking> completer = _queue[masterId]!.removeAt(0);
    completer.complete(
      Booking(
        id: 'booking-$masterId',
        masterId: masterId,
        masterFirstName: 'Майстер',
        masterLastName: 'Салону',
        masterType: 'SALON_MASTER',
        serviceId: 'assign-$masterId',
        serviceName: 'Послуга',
        durationMinutes: 60,
        price: 500,
        startAt: DateTime.now().add(const Duration(days: 1)),
        endAt: DateTime.now().add(const Duration(days: 1, minutes: 60)),
        status: BookingStatus.pending,
        canReview: false,
      ),
    );
  }

  /// Rejects the OLDEST not-yet-resolved call for [masterId] as [failure].
  void fail(String masterId, Failure failure) {
    final Completer<Booking> completer = _queue[masterId]!.removeAt(0);
    completer.completeError(failure);
  }

  @override
  Future<PageResponse<Booking>> getMyBookings({
    required Set<BookingStatus> statuses,
    required bool ascending,
    required int page,
    int size = kBookingsPageSize,
  }) => throw UnimplementedError();

  @override
  Future<Booking> getBookingById(String id) => throw UnimplementedError();

  @override
  Future<void> createReview({
    required String bookingId,
    required int rating,
    String? comment,
  }) => throw UnimplementedError();

  @override
  Future<void> cancelBooking(String id, {String? reason}) =>
      throw UnimplementedError();

  @override
  Future<Booking> rescheduleBooking(String id, DateTime newStartAt) =>
      throw UnimplementedError();
}

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
      final repo = _FakeBookingRepository();
      final GoRouter router = await AppHarness.boot(
        tester,
        fb,
        extraOverrides: <Object>[
          bookingRepositoryProvider.overrideWithValue(repo),
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

      expectLocation(router, RouteNames.salonBookingTime);
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
      await tester.tap(
        withinSlide(
          'master-ccc',
          find.byKey(Key('booking-calendar-day-${today.day}')),
        ),
      );
      await AppHarness.settle(tester);

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

      expectLocation(router, RouteNames.salonBookingTime);
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
      await tester.tap(
        withinSlide(
          'master-ccc',
          find.byKey(Key('booking-calendar-day-${today.day}')),
        ),
      );
      await AppHarness.settle(tester);

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

      expectLocation(router, RouteNames.salonBookingConfirm);
      expect(find.byType(SalonBookingConfirmScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      // No booking has been written by merely reaching the confirm screen.
      expect(repo.requests, isEmpty);

      // One appointment card per assigned master (master-ccc, master-ddd).
      expect(
        find.byKey(const ValueKey<String>('salon-confirm-appt-master-ccc')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('salon-confirm-appt-master-ddd')),
        findsOneWidget,
      );

      // ── mobile-qa Rule 3b (KNOWN COVERAGE GAPS): the shared salon-address
      // card, the grand-total card, and each appointment card's ★rating had
      // no end-to-end proof against the REAL public-salon-profile response
      // and the REAL bookable-masters roster. ──────────────────────────────
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

      // Grand total across BOTH masters: salon-svc-shared (400 ₴/60 min,
      // raw backend `priceDisplay` fixture) + salon-svc-exclusive (300
      // ₴/45 min) = 700 ₴ / 1 год 45 хв. The sum itself is CLIENT-computed
      // and CLIENT-formatted (BookingRecap._BookingTotals) — it is not a
      // pass-through of either fixture string, even though both the fixtures
      // and the client formatter now render the same "₴" glyph.
      final Finder confirmGrandTotal = find.byKey(
        const Key('salon-confirm-grand-total-card'),
      );
      expect(confirmGrandTotal, findsOneWidget);
      expect(
        find.descendant(
          of: confirmGrandTotal,
          // i18n-finder-ok: summed price is real fixture-derived data, not translated UI copy.
          matching: find.text('700 ₴'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: confirmGrandTotal,
          // i18n-finder-ok: summed duration is real fixture-derived data, not translated UI copy.
          matching: find.text('1 год 45 хв'),
        ),
        findsOneWidget,
      );

      final Finder confirmCccCard = find.byKey(
        const ValueKey<String>('salon-confirm-appt-master-ccc'),
      );
      final Finder confirmDddCard = find.byKey(
        const ValueKey<String>('salon-confirm-appt-master-ddd'),
      );
      expect(
        find.descendant(of: confirmCccCard, matching: find.text('4.6')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: confirmDddCard, matching: find.text('4.8')),
        findsOneWidget,
      );

      // ── Submit: one `POST /bookings` per master → all succeed → success
      // screen. This is the Phase 14.18 booking-WRITE the flow now performs
      // end to end (Step 2.7 Rule 3b). ────────────────────────────────────
      await tester.tap(find.byKey(const Key('salon-confirm-submit-cta')));
      await AppHarness.settle(tester);

      expectLocation(router, RouteNames.salonBookingSuccess);
      expect(find.byType(SalonBookingSuccessScreen), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Exactly one booking per master, each carrying that master's OWN
      // service-ASSIGNMENT id (never the salon-wide catalog id) — the same
      // masterService-not-found regression guarded at the slots step, now
      // proven all the way through the booking write.
      expect(repo.callsFor('master-ccc'), 1);
      expect(repo.callsFor('master-ddd'), 1);
      expect(
        repo.requestsFor('master-ccc').single.serviceId,
        'assign-master-ccc-salon-svc-shared',
      );
      expect(
        repo.requestsFor('master-ddd').single.serviceId,
        'assign-master-ddd-salon-svc-exclusive',
      );

      // Both created appointments are recapped on the success screen.
      expect(
        find.byKey(const ValueKey<String>('salon-success-appt-master-ccc')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('salon-success-appt-master-ddd')),
        findsOneWidget,
      );

      // ── mobile-qa Rule 3b: the same shared address/grand-total/rating
      // info-parity gaps, now proven on the CONFIRMED recap too. ──────────
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

      final Finder successGrandTotal = find.byKey(
        const Key('salon-success-grand-total-card'),
      );
      expect(successGrandTotal, findsOneWidget);
      expect(
        find.descendant(
          of: successGrandTotal,
          // i18n-finder-ok: summed price is real fixture-derived data (client-
          // computed + client-formatted total, not the raw backend string),
          // not translated UI copy.
          matching: find.text('700 ₴'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: successGrandTotal,
          // i18n-finder-ok: summed duration is real fixture-derived data, not translated UI copy.
          matching: find.text('1 год 45 хв'),
        ),
        findsOneWidget,
      );

      final Finder successCccCard = find.byKey(
        const ValueKey<String>('salon-success-appt-master-ccc'),
      );
      final Finder successDddCard = find.byKey(
        const ValueKey<String>('salon-success-appt-master-ddd'),
      );
      expect(
        find.descendant(of: successCccCard, matching: find.text('4.6')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: successDddCard, matching: find.text('4.8')),
        findsOneWidget,
      );
    });
  }, timeout: const Timeout(Duration(seconds: 120)));

  // ── Phase 14.18 partial-failure variant (Step 2.7 Rule 3b) ──────────────
  // The full search→salon→services→masters→time journey is already proven end
  // to end by the flow above; this variant targets the NEW partial-failure
  // path specifically, reached via a real `router.push` of the confirm route
  // (through the REAL CLIENT route guard) with a fully-resolved two-master
  // `SalonBookingConfirmArgs`. One master's first `POST /bookings` fails with
  // a 409 (stale slot) → the confirm screen STAYS, the failed card shows its
  // error + the CTA flips to «Повторити»; retrying re-submits ONLY the failed
  // master and reaches success.
  testWidgets(
    'CLIENT salon confirm: a 409 on one master keeps the confirm screen; '
    'retry re-submits only the failed master and reaches success',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()..currentRole = UserRole.client;
        // master-ddd's first booking fails (409), then succeeds on retry.
        final repo = _FakeBookingRepository(failOnce: const <String>{'m-two'});
        final GoRouter router = await AppHarness.boot(
          tester,
          fb,
          extraOverrides: <Object>[
            bookingRepositoryProvider.overrideWithValue(repo),
          ],
        );

        await AppHarness.loginAs(tester, fb, UserRole.client);
        await AppHarness.settle(tester);

        SalonBookingAppointment appt(String masterId, String firstName) =>
            SalonBookingAppointment(
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
                primaryServiceAssignmentId: 'assign-$masterId',
              ),
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

        expectLocation(router, RouteNames.salonBookingConfirm);
        expect(find.byType(SalonBookingConfirmScreen), findsOneWidget);

        // First submit → m-two fails (409) → stay on confirm.
        await tester.tap(find.byKey(const Key('salon-confirm-submit-cta')));
        await AppHarness.settle(tester);

        expectLocation(router, RouteNames.salonBookingConfirm);
        expect(find.byType(SalonBookingConfirmScreen), findsOneWidget);
        expect(find.byType(SalonBookingSuccessScreen), findsNothing);
        expect(repo.callsFor('m-one'), 1);
        expect(repo.callsFor('m-two'), 1);

        // Retry → m-two now succeeds (fail-once consumed) → success.
        await tester.tap(find.byKey(const Key('salon-confirm-submit-cta')));
        await AppHarness.settle(tester);

        expectLocation(router, RouteNames.salonBookingSuccess);
        expect(find.byType(SalonBookingSuccessScreen), findsOneWidget);
        // m-one booked once (never re-sent); m-two booked twice (fail + retry),
        // both reusing its stable idempotency key.
        expect(repo.callsFor('m-one'), 1);
        expect(repo.callsFor('m-two'), 2);
        expect(
          repo
              .requestsFor('m-two')
              .map((CreateBookingRequest r) => r.idempotencyKey)
              .toSet(),
          <String>{'idem-m-two'},
        );
        expect(tester.takeException(), isNull);
      });
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  // ── mobile-qa gap-fix (Step 2.7 Rule 3b) — CLIENT_BOOKING_CONFLICT on ONE
  // master must surface on that master's card only and must NOT fail the
  // whole batch, exactly like the generic-409 partial-failure test above.
  // The client already has an overlapping booking with a THIRD, unrelated
  // master/salon — m-two's own slot is perfectly fine, this is the CLIENT
  // double-booking themselves, not a slot conflict. ─────────────────────────
  testWidgets(
    'CLIENT salon confirm: a CLIENT_BOOKING_CONFLICT on one master surfaces '
    'on that master\'s card only — the other master still succeeds and the '
    'whole batch is not failed',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()..currentRole = UserRole.client;
        final DateTime clashStart = DateTime.utc(2026, 7, 15, 14);
        final ClientBookingConflictFailure conflict =
            ClientBookingConflictFailure(
              conflictingBookingId: 'other-booking-1',
              serviceName: 'Педикюр апаратний',
              masterName: 'Ірина Шевченко',
              startsAt: clashStart,
              endsAt: clashStart.add(const Duration(minutes: 45)),
            );
        final repo = _FakeBookingRepository();
        final GoRouter router = await AppHarness.boot(
          tester,
          fb,
          extraOverrides: <Object>[
            bookingRepositoryProvider.overrideWithValue(repo),
          ],
        );

        await AppHarness.loginAs(tester, fb, UserRole.client);
        await AppHarness.settle(tester);

        SalonBookingAppointment appt(String masterId, String firstName) =>
            SalonBookingAppointment(
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
                primaryServiceAssignmentId: 'assign-$masterId',
              ),
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
        expectLocation(router, RouteNames.salonBookingConfirm);

        // m-two's write fails with the CLIENT's own conflict (unrelated
        // third booking) — swap in the failing behaviour on the recording
        // fake by throwing per-call via a tiny wrapper.
        repo.failWith('m-two', conflict);

        final l10n = AppLocalizations.of(
          tester.element(find.byType(SalonBookingConfirmScreen)),
        );
        final Finder mOneCard = find.byKey(
          const ValueKey<String>('salon-confirm-appt-m-one'),
        );
        final Finder mTwoCard = find.byKey(
          const ValueKey<String>('salon-confirm-appt-m-two'),
        );

        await tester.tap(find.byKey(const Key('salon-confirm-submit-cta')));
        await AppHarness.settle(tester);

        // The batch is NOT failed — still on confirm, m-one settled fine.
        expectLocation(router, RouteNames.salonBookingConfirm);
        expect(find.byType(SalonBookingSuccessScreen), findsNothing);
        expect(repo.callsFor('m-one'), 1);
        expect(repo.callsFor('m-two'), 1);

        // The conflict surfaces on m-two's card ONLY, as the SAME composed
        // sentence the independent-master dialog uses — never a generic
        // conflict message, and never on m-one's card.
        final String expectedMessage = l10n.bookingErrClientConflict(
          'Педикюр апаратний',
          'Ірина Шевченко',
          formatBookingWindow(
            clashStart,
            clashStart.add(const Duration(minutes: 45)),
          ),
        );
        expect(
          find.descendant(of: mTwoCard, matching: find.text(expectedMessage)),
          findsOneWidget,
          reason:
              'm-two\'s own card must surface the CLIENT_BOOKING_CONFLICT '
              'sentence naming the THIRD, unrelated clashing booking',
        );
        expect(
          find.descendant(
            of: mOneCard,
            matching: find.text(l10n.salonBookingAppointmentSucceeded),
          ),
          findsOneWidget,
          reason:
              'm-one must be entirely unaffected — its own write succeeded '
              'and its card shows the success line, not m-two\'s conflict',
        );
        expect(
          find.descendant(of: mOneCard, matching: find.text(expectedMessage)),
          findsNothing,
          reason: 'the conflict message must never bleed onto m-one\'s card',
        );

        // Retry: m-two's own slot was always fine — the conflict clears on
        // retry (the recording fake only fails the ONE configured call) and
        // the client reaches success.
        await tester.tap(find.byKey(const Key('salon-confirm-submit-cta')));
        await AppHarness.settle(tester);

        expectLocation(router, RouteNames.salonBookingSuccess);
        expect(find.byType(SalonBookingSuccessScreen), findsOneWidget);
        expect(repo.callsFor('m-one'), 1);
        expect(repo.callsFor('m-two'), 2);
        expect(tester.takeException(), isNull);
      });
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  // ── Phase 14.18 showSucceededStatus regression guard (Step 2.7 Rule 3b) ──
  // No native surface is involved here (no OS permission dialog, no deep
  // link, no FCM/local notification, no WebView, no biometric) — this is
  // pure Dart/Riverpod state driving a pure Flutter widget tree, so no
  // Patrol test is added alongside this one.
  testWidgets(
    'CLIENT salon confirm: the already-succeeded master\'s «Заплановано» '
    'status survives BOTH the settled partial failure AND the retry\'s own '
    'in-flight window — the regression guard for the showSucceededStatus '
    'gate (first attempt wrongly gated on live hasFailures alone)',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()..currentRole = UserRole.client;
        final repo = _GatedBookingRepository();
        final GoRouter router = await AppHarness.boot(
          tester,
          fb,
          extraOverrides: <Object>[
            bookingRepositoryProvider.overrideWithValue(repo),
          ],
        );

        await AppHarness.loginAs(tester, fb, UserRole.client);
        await AppHarness.settle(tester);

        SalonBookingAppointment appt(String masterId, String firstName) =>
            SalonBookingAppointment(
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
                primaryServiceAssignmentId: 'assign-$masterId',
              ),
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

        expectLocation(router, RouteNames.salonBookingConfirm);
        expect(find.byType(SalonBookingConfirmScreen), findsOneWidget);

        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(find.byType(SalonBookingConfirmScreen)),
        );
        final Finder mOneCard = find.byKey(
          const ValueKey<String>('salon-confirm-appt-m-one'),
        );
        final Finder mTwoCard = find.byKey(
          const ValueKey<String>('salon-confirm-appt-m-two'),
        );

        // First submit: m-one succeeds, m-two fails (409) — both gated so
        // the pass only settles once BOTH are resolved.
        await tester.tap(find.byKey(const Key('salon-confirm-submit-cta')));
        await tester.pump();
        repo.succeed('m-one');
        await tester.pump();
        repo.fail('m-two', const ConflictFailure());
        await AppHarness.settle(tester);

        // SETTLED, PARTIAL FAILURE: m-one's checkmark is visible at rest —
        // hasFailures=true keeps it showing.
        expectLocation(router, RouteNames.salonBookingConfirm);
        expect(find.byType(SalonBookingSuccessScreen), findsNothing);
        expect(
          find.descendant(
            of: mOneCard,
            matching: find.text(l10n.salonBookingAppointmentSucceeded),
          ),
          findsOneWidget,
          reason:
              'settled with a partial failure: m-one\'s already-succeeded '
              'status must stay visible',
        );
        expect(
          find.descendant(of: mTwoCard, matching: find.text(l10n.errConflict)),
          findsOneWidget,
        );

        // Retry: tap «Повторити». The pre-loop reset clears m-two's failure
        // (hasFailures → false) atomically with inFlight → true — the exact
        // window the buggy hasFailures-only gate got wrong. m-two's retry
        // POST is gated (pending) so this in-flight frame is observable.
        await tester.tap(find.byKey(const Key('salon-confirm-submit-cta')));
        await tester.pump();

        expect(
          find.descendant(
            of: mOneCard,
            matching: find.text(l10n.salonBookingAppointmentSucceeded),
          ),
          findsOneWidget,
          reason:
              'MID-RETRY: hasFailures has already been reset to false for '
              'the new pass and m-two\'s retry POST has not resolved yet — '
              'inFlight=true must be what keeps m-one\'s checkmark visible '
              'here, in the REAL end-to-end app, not just an isolated '
              'widget test',
        );

        // Resolve the retry → settles all-succeeded → success screen.
        repo.succeed('m-two');
        await AppHarness.settle(tester);

        expectLocation(router, RouteNames.salonBookingSuccess);
        expect(find.byType(SalonBookingSuccessScreen), findsOneWidget);
        expect(repo.callsFor('m-one'), 1);
        expect(repo.callsFor('m-two'), 2);
        expect(tester.takeException(), isNull);
      });
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );
}
