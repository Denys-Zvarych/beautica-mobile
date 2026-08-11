// A SALON-sourced Beauty Passport favourite re-enters the salon booking flow
// at its EXISTING step-2 master picker, scoped to the favourited service.
//
// WHY THIS FILE EXISTS
// ---------------------
// `wishlist_rebook_test.dart` (widget tier) proves `WishlistRebookHost.rebook`
// pushes `RouteNames.salonBookingMasters` with a
// [SalonBookingMasterSelectionArgs] for a SALON row — but it does so behind a
// hand-rolled router with a STUB destination, so it cannot prove the thing
// that actually makes this product decision safe:
//
//   entering the salon booking flow's step 2 DIRECTLY, without its step 1
//   (`/booking/salon/services`) ever having rendered, is not a dead end.
//
// That is three separate contracts, and this file is the only place all three
// are exercised against the real router and real (faked-transport) endpoints:
//   1. the REAL `/booking/salon/masters` route's `extra` guard accepts the
//      payload the wish-list CTA builds (a wrong/absent extra bounces to
//      `clientHome` — see `app_router.dart`), and `SalonMasterSelectionScreen`
//      then resolves salon + catalogue + per-service coverage from its own
//      self-fetching family providers, with no step-1 draft state to inherit;
//   2. BACK from that screen returns to the wish list we pushed from — not
//      into a step 1 that never rendered, and not out of the app;
//   3. FORWARD still works: picking a covering master and tapping «Далі»
//      resolves the step-3 payload and reaches `/booking/salon/time`.
//
// The previous cut of this file tested a DIFFERENT destination — the salon's
// public profile deep-linked to a pre-filtered "Майстри" tab via
// `?serviceId=&tab=masters`. That was a second, parallel "masters who perform
// this service" UI on top of a step that already is exactly that; the route
// param, the router's query parsing and the screen-side seed have all been
// deleted. The in-profile filter reachable by TAPPING a service in the
// "Послуги" tab is a SEPARATE feature and still has its own regression guard
// in `salon_service_filter_flow_test.dart`.
//
// ⚠️ THE TRAP THIS FILE IS DELIBERATELY WRITTEN AROUND
// ------------------------------------------------------
// `/booking/salon/masters` is a TOP-LEVEL route pushed with `context.push`
// from a screen mounted INSIDE the CLIENT `StatefulShellRoute` (the Beauty
// Passport tab) — structurally identical to `wishlist_rebook_flow_test.dart`'s
// `/booking/new` push, which is why this file resolves location the same way:
// `AppHarness.expectLocation` (push-safe `ImperativeRouteMatch` unwrap), NEVER
// `AppHarness.shellLocation`/`matchedLocation` and NEVER a `router.go` to fake
// the transition. A `router.go`-driven version of this test — or one that read
// `currentConfiguration.uri` directly — would falsely stay green even if the
// production `context.push` call vanished entirely, because a `go` to the SAME
// target URL is indistinguishable from a push under either of those naive
// reads (see `wishlist_rebook_test.dart`'s file header for the exact
// mechanism, and `AppHarness.location`'s doc comment). The push shape matters
// doubly here: it is precisely what makes contract 2 (back returns to the wish
// list) true.
//
// FIXTURE COHERENCE — reuses `salon-xyz`, the SAME fixture
// `salon_service_filter_flow_test.dart` and `public_salon_profile_flow_test.dart`
// already exercise: catalogue service `salon-svc-shared` (NAILS, only
// `master-ccc` bookable out of an EIGHT-master roster) and
// `salon-svc-namefallback` (a real catalogue entry whose bookable-masters
// response is an empty 200 — nobody performs it).
//
// KEY POLICY (per AppHarness): every tap is key-based. Raw Ukrainian text
// appears only in CONTENT assertions (fixture/catalogue data, never app UI
// copy) — each such assertion carries `i18n-finder-ok` on the line above.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/passport/presentation/passport_screen.dart';
import 'package:beautica_mobile/features/wishlist/presentation/widgets/wishlist_compact_card.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

/// One SALON-sourced favourite, keyed to `salon-xyz` + [serviceDefId] — the
/// exact wire shape `GET /favorites/services` sends for the SALON arm (Phase
/// F's `sourceType: 'SALON'`), see `wishlist_mapper.dart`'s header.
List<Map<String, dynamic>> _salonWishlistRow(
  String serviceDefId,
  String serviceName,
) => <Map<String, dynamic>>[
  <String, dynamic>{
    'sourceType': 'SALON',
    'salonId': 'salon-xyz',
    'salonName': 'Салон «Вельвет»',
    'serviceDefId': serviceDefId,
    'serviceName': serviceName,
    'durationMinutes': 60,
    'priceDisplay': '400 ₴',
  },
];

/// Scrolls the passport page to the bottom so the wish-list block — below the
/// fold on the 800x600 flutter-tester surface — is laid out and tappable.
/// Mirrors `wishlist_rebook_flow_test.dart`'s helper of the same name.
Future<void> _scrollToWishList(WidgetTester tester) async {
  await tester.drag(find.byType(Scrollable).last, const Offset(0, -600));
  await tester.pumpAndSettle();
}

Future<void> _openPassportAndScrollToWishlist(
  WidgetTester tester,
  FakeBackend fb,
  GoRouter router,
) async {
  await AppHarness.loginAs(tester, fb, UserRole.client);
  // The passport nav tile only exists on the CLIENT home shell, so waiting
  // for it IS "login finished and home rendered" — no fixed sleep needed.
  // (`wishlist_rebook_flow_test.dart`'s older copy of this helper still uses
  // a 1s settle here; this file is new, so it starts on the condition wait.)
  await AppHarness.pumpUntilFound(
    tester,
    find.byKey(const Key('client-nav-tile-4')),
  );
  AppHarness.expectLocation(router, RouteNames.clientHome);

  await AppHarness.tapVisible(
    tester,
    find.byKey(const Key('client-nav-tile-4')),
  );
  await tester.pumpAndSettle();
  AppHarness.expectLocation(router, RouteNames.clientPassport);
  expect(find.byType(PassportScreen), findsOneWidget);

  await _scrollToWishList(tester);
  expect(find.byType(WishlistCompactCard), findsOneWidget);
}

/// Whether the top-level match is an [ImperativeRouteMatch] — the structural
/// fingerprint of `context.push` (see the file header's TRAP section).
bool _topIsImperativePush(GoRouter router) =>
    router.routerDelegate.currentConfiguration.matches.last
        is ImperativeRouteMatch;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  // =========================================================================
  // Test 1 — ACCEPTANCE: the CTA lands on the salon booking flow's step-2
  // master picker, scoped to the favourited service, with the roster narrowed
  // by the REAL per-service coverage fetch. Then continues FORWARD to step 3,
  // proving direct entry is not a one-way door.
  // =========================================================================
  testWidgets(
    'CLIENT taps a SALON-sourced favourite\'s «Обрати майстра» → the salon '
    'booking flow\'s step-2 master picker opens (via a real context.push) '
    'showing only the masters who perform that service, and «Далі» continues '
    'to step 3',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()
          ..currentRole = UserRole.client
          ..favoriteServiceRows = _salonWishlistRow(
            'salon-svc-shared',
            'Манікюр класичний',
          );
        final GoRouter router = await AppHarness.boot(tester, fb);

        await _openPassportAndScrollToWishlist(tester, fb, router);

        expect(fb.getBookableMastersCalls, 0);

        await tester.tap(
          find.byKey(const Key('wishlist_card_book_salon-svc-shared')),
        );
        // Condition wait, deliberately in TWO stages rather than one fixed
        // sleep. Stage 1 gates on step 2 being MOUNTED (its back control is
        // the one chrome element present in every state, including loading),
        // so a push that landed on the wrong route fails on the location
        // assertion two lines down — legibly — instead of timing out later
        // against a row finder that was never going to match.
        await AppHarness.pumpUntilFound(
          tester,
          find.byKey(const Key('salon-master-selection-back')),
        );

        // ── Landed on step 2 — never the salon profile (the deleted
        // deep-link cut) and never step 1 (RouteNames.salonBookingServices,
        // Phase F's reversed cut, which made the client re-pick the service
        // they had already favourited). ────────────────────────────────────
        AppHarness.expectLocation(router, RouteNames.salonBookingMasters);
        expect(
          _topIsImperativePush(router),
          isTrue,
          reason:
              'the salon-arm destination must be reached via context.push — '
              'see the file header\'s TRAP section',
        );
        expect(
          find.byKey(const Key('salon-master-selection-back')),
          findsOneWidget,
          reason:
              'the route guard accepted the wish-list CTA\'s extra and built '
              'the real step-2 screen — a wrong/absent extra would have '
              'bounced to clientHome instead',
        );

        // ── The roster is genuinely narrowed via the REAL coverage fetch,
        // issued for exactly the favourited service. Stage 2 of the condition
        // wait: the covering-master row only exists once ALL THREE of step
        // 2's self-fetching providers (salon detail, catalogue, coverage
        // fan-out) have landed, so waiting for it is precisely "the screen
        // finished loading" — with no guess at how long that takes.
        await AppHarness.pumpUntilFound(
          tester,
          find.byKey(const Key('salon_booking_master_row_master-ccc')),
        );
        expect(fb.getBookableMastersCalls, 1);
        expect(fb.requestedBookableMastersServiceDefIds, <String>{
          'salon-svc-shared',
        });
        expect(
          find.byKey(const Key('salon_booking_master_row_master-ccc')),
          findsOneWidget,
          reason:
              'master-ccc is the only one of salon-xyz\'s eight roster '
              'masters bookable for this service',
        );
        expect(
          find.byKey(const Key('salon_booking_master_row_master-aaa')),
          findsNothing,
          reason:
              'master-aaa does not perform this service — the coverage '
              'INTERSECTION must exclude them',
        );
        // i18n-finder-ok: the master name is backend fixture data.
        expect(find.textContaining('Гриценко'), findsWidgets);

        // ── FORWARD still works from a directly-entered step 2: picking the
        // covering master resolves the step-3 payload from data this screen
        // loaded itself, with nothing inherited from a step 1 that never
        // rendered. ────────────────────────────────────────────────────────
        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('salon_booking_master_row_master-ccc')),
        );
        await tester.pumpAndSettle();
        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('booking-summary-cta')),
        );
        // Step 3's own back control is the mounted-marker here, same shape as
        // stage 1 above — no fixed sleep for the push + day-availability load.
        await AppHarness.pumpUntilFound(
          tester,
          find.byKey(const Key('salon-time-back')),
        );

        AppHarness.expectLocation(router, RouteNames.salonBookingTime);
        expect(tester.takeException(), isNull);
      });
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  // =========================================================================
  // Test 2 — NOT A DEAD END: back from a directly-entered step 2 returns to
  // the wish list it was pushed from, never into the step 1 that never
  // rendered (and never out of the app).
  // =========================================================================
  testWidgets(
    'back from the directly-entered step-2 master picker returns to the '
    'Beauty Passport wish list, not to the salon booking flow\'s step 1',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()
          ..currentRole = UserRole.client
          ..favoriteServiceRows = _salonWishlistRow(
            'salon-svc-shared',
            'Манікюр класичний',
          );
        final GoRouter router = await AppHarness.boot(tester, fb);

        await _openPassportAndScrollToWishlist(tester, fb, router);
        await tester.tap(
          find.byKey(const Key('wishlist_card_book_salon-svc-shared')),
        );
        // Step 2 mounted — its back control is present in every state of that
        // screen, so this needs no guess at provider-load time.
        await AppHarness.pumpUntilFound(
          tester,
          find.byKey(const Key('salon-master-selection-back')),
        );
        AppHarness.expectLocation(router, RouteNames.salonBookingMasters);

        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('salon-master-selection-back')),
        );
        // The pop's own completion IS the condition — step 2's back control
        // leaving the tree. Also covers the wish-list refetch `rebook` fires
        // once the push resolves (see `wishlist_rebook.dart`'s
        // "refresh-after-return" section), which cannot start any earlier.
        await AppHarness.pumpUntilCondition(
          tester,
          () => find
              .byKey(const Key('salon-master-selection-back'))
              .evaluate()
              .isEmpty,
          description:
              'step 2 to leave the tree entirely — really popped, not '
              'merely covered',
        );
        await tester.pumpAndSettle();

        AppHarness.expectLocation(router, RouteNames.clientPassport);
        await _scrollToWishList(tester);
        expect(
          find.byKey(const Key('wishlist_card_book_salon-svc-shared')),
          findsOneWidget,
          reason:
              'the same wish-list entry is on screen again — the CTA is '
              're-tappable, which is what "not a dead end" means here',
        );
        expect(tester.takeException(), isNull);
      });
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  // =========================================================================
  // Test 3 — NOBODY PERFORMS IT: a favourite whose service no roster master
  // is bookable for renders step 2's own empty state, not a blank list.
  // This is also the shape a stale favourite degrades into — the per-service
  // coverage call is caught independently, so an unresolvable service reads
  // as "no bookable masters for it" rather than a screen-wide error.
  // =========================================================================
  testWidgets(
    'a favourited service no roster master performs lands on step 2 and '
    'renders the no-covering-master empty state — no rows, no crash',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()
          ..currentRole = UserRole.client
          ..favoriteServiceRows = _salonWishlistRow(
            'salon-svc-namefallback',
            'Манікюр класичний VIP',
          );
        final GoRouter router = await AppHarness.boot(tester, fb);

        await _openPassportAndScrollToWishlist(tester, fb, router);
        await tester.tap(
          find.byKey(const Key('wishlist_card_book_salon-svc-namefallback')),
        );
        // Same two-stage condition wait as test 1: mounted first (so a
        // mis-routed push fails on the location assertion, not on a timeout),
        // then the settled outcome — which here is the empty state rather
        // than a master row.
        await AppHarness.pumpUntilFound(
          tester,
          find.byKey(const Key('salon-master-selection-back')),
        );
        AppHarness.expectLocation(router, RouteNames.salonBookingMasters);
        await AppHarness.pumpUntilFound(
          tester,
          find.byKey(const Key('salon-master-selection-no-covering-master')),
        );

        expect(fb.requestedBookableMastersServiceDefIds, <String>{
          'salon-svc-namefallback',
        });
        expect(
          find.byKey(const Key('salon_booking_master_row_master-aaa')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('booking-summary-cta')),
          findsNothing,
          reason: 'there is nothing to confirm — the summary bar is withheld',
        );
        expect(tester.takeException(), isNull);
      });
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );
}
