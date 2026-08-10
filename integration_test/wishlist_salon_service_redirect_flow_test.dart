// Phase G — a SALON-sourced Beauty Passport favourite redirects to the
// salon's own profile, masters tab, FILTERED to the favourited service.
//
// WHY THIS FILE EXISTS
// ---------------------
// `wishlist_rebook_test.dart` (widget tier) proves `WishlistRebookHost.rebook`
// pushes `RouteNames.salonPublicProfile(salonId, serviceId: serviceDefId)` for
// a SALON row, behind a hand-rolled router with a stub destination. It cannot
// prove the two contracts this phase actually ships:
//   1. the REAL `/salons/:salonId` route parses `?serviceId=&tab=masters`
//      into `PublicSalonProfileScreen`'s `initialServiceId`/
//      `initialMastersTab`, which then resolves the id against a REAL,
//      freshly-fetched `GET /salons/{id}/services` catalogue and seeds
//      `salonServiceFilterProvider` — a chain of THREE providers/routes this
//      file is the only place that exercises end to end;
//   2. the two failure-adjacent shapes that chain can hit for real: a
//      resolvable id with ZERO performing masters (the catalogue still knows
//      the service; nobody offers it), and an id ABSENT from the catalogue
//      entirely (a stale/withdrawn favourite) — the latter must clear the
//      filter and render the plain masters tab, never a raw-id chip or a
//      crash.
//
// ⚠️ THE TRAP THIS FILE IS DELIBERATELY WRITTEN AROUND
// ------------------------------------------------------
// `/salons/:salonId` is a TOP-LEVEL route pushed with `context.push` from a
// screen mounted INSIDE the CLIENT `StatefulShellRoute` (the Beauty Passport
// tab) — structurally identical to `wishlist_rebook_flow_test.dart`'s
// `/booking/new` push, which is why this file resolves location the same
// way: `AppHarness.expectLocation` (push-safe `ImperativeRouteMatch` unwrap),
// NEVER `AppHarness.shellLocation`/`matchedLocation` and NEVER a `router.go`
// to fake the transition. A `router.go`-driven version of this test — or one
// that read `currentConfiguration.uri` directly — would falsely stay green
// even if the production `context.push` call vanished entirely, because a
// `go` to the SAME target URL is indistinguishable from a push under either
// of those naive reads (see `wishlist_rebook_test.dart`'s file header for the
// exact mechanism, and `AppHarness.location`'s doc comment). This file goes
// one step further than the widget-tier test and drives the REAL button tap
// end to end, then separately asserts the top match really is an
// `ImperativeRouteMatch` — belt and suspenders.
//
// FIXTURE COHERENCE — reuses `salon-xyz`, the SAME fixture
// `salon_service_filter_flow_test.dart` and `public_salon_profile_flow_test.dart`
// already exercise: catalogue services `salon-svc-shared` (NAILS, only
// `master-ccc` bookable), `salon-svc-namefallback` (NAILS, a real catalogue
// entry with an EMPTY bookable-masters response — added by this phase to
// `fake_backend.dart` specifically so "resolvable id, zero performers" has a
// clean 200 to hit instead of an unregistered-route network error), and an id
// that never existed in the catalogue at all (`salon-svc-withdrawn`) for the
// unresolvable-id path.
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
  // fixed-wait-ok: settles a real async route-push + provider-load step; not a total-wait guess.
  await tester.pumpAndSettle(const Duration(seconds: 1));
  AppHarness.expectLocation(router, RouteNames.clientHome);

  await tester.tap(find.byKey(const Key('client-nav-tile-4')));
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
  // Test 1 — ACCEPTANCE: a resolvable favourite lands directly on the
  // filtered Майстри tab, chip named from the REAL catalogue, roster narrowed
  // by the REAL coverage fan-out.
  // =========================================================================
  testWidgets(
    'CLIENT taps a SALON-sourced favourite\'s «Обрати майстра» → the salon\'s '
    'own profile opens with the Майстри tab pre-filtered to the '
    'favourited service, via a real context.push',
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
        // The seed resolves off a deferred microtask once the catalogue
        // fetch lands — settle generously rather than assume one frame.
        // fixed-wait-ok: settles a real async route-push + two parallel provider-load steps.
        await tester.pumpAndSettle(const Duration(seconds: 1));

        // ── Landed on salon-xyz's OWN profile — never the salon booking flow
        // (RouteNames.salonBookingServices, Phase F's reversed cut). ────────
        AppHarness.expectLocation(
          router,
          RouteNames.salonPublicProfile(
            'salon-xyz',
            serviceId: 'salon-svc-shared',
          ),
        );
        expect(
          _topIsImperativePush(router),
          isTrue,
          reason:
              'the salon-arm destination must be reached via context.push — '
              'see the file header\'s TRAP section',
        );
        expect(find.byKey(const Key('salon-profile-name')), findsOneWidget);

        // ── Landed on the Майстри tab with NO tab tap — the chip alone
        // proves it (it only ever renders inside _MastersTab). ─────────────
        final Finder chip = find.byKey(const Key('salon-masters-filter-chip'));
        expect(chip, findsOneWidget);
        // i18n-finder-ok: the service name is backend catalogue fixture data.
        expect(
          find.descendant(
            of: chip,
            matching: find.textContaining('Манікюр класичний'),
          ),
          findsOneWidget,
          reason:
              'the chip must show the NAME resolved from the real catalogue '
              'fetch, never the raw serviceDefId',
        );

        // ── The roster is genuinely narrowed via the REAL coverage fetch ──
        expect(fb.getBookableMastersCalls, 1);
        expect(fb.requestedBookableMastersServiceDefIds, <String>{
          'salon-svc-shared',
        });
        expect(
          find.byKey(const Key('salon-master-card-master-ccc')),
          findsOneWidget,
          reason:
              'master-ccc is the only roster master performing this '
              'service',
        );
        expect(
          find.byKey(const Key('salon-master-card-master-aaa')),
          findsNothing,
          reason:
              'master-aaa does not perform this service — hidden while '
              'the deep-link filter is active',
        );
        expect(tester.takeException(), isNull);
      });
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

  // =========================================================================
  // Test 2 — EMPTY-ROSTER PATH: the catalogue resolves the service (a real
  // name for the chip) but NO master performs it.
  // =========================================================================
  testWidgets(
    'a favourited service that no roster master performs still resolves its '
    'name for the chip, and renders the dedicated for-service empty state '
    '— not a blank grid, not a crash',
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
        // fixed-wait-ok: settles a real async route-push + two parallel provider-load steps.
        await tester.pumpAndSettle(const Duration(seconds: 1));

        AppHarness.expectLocation(
          router,
          RouteNames.salonPublicProfile(
            'salon-xyz',
            serviceId: 'salon-svc-namefallback',
          ),
        );

        final Finder chip = find.byKey(const Key('salon-masters-filter-chip'));
        expect(
          chip,
          findsOneWidget,
          reason:
              'the service IS in the catalogue — the chip must still show '
              'its resolved name even though nobody performs it',
        );
        // i18n-finder-ok: the service name is backend catalogue fixture data.
        expect(
          find.descendant(
            of: chip,
            matching: find.textContaining('Манікюр класичний VIP'),
          ),
          findsOneWidget,
        );

        expect(
          find.byKey(const Key('salon-masters-for-service-empty')),
          findsOneWidget,
          reason:
              'zero performing masters must render the dedicated for-service '
              'empty state, not a blank grid',
        );
        expect(
          find.byKey(const Key('salon-master-card-master-aaa')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      });
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

  // =========================================================================
  // Test 3 — UNRESOLVABLE-ID PATH: a stale/withdrawn favourite whose service
  // id is no longer in the catalogue at all.
  // =========================================================================
  testWidgets(
    'a favourite pointing at a serviceDefId the catalogue no longer carries '
    'lands on the Майстри tab UNFILTERED — no chip, no raw-id label, no '
    'crash, full roster',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()
          ..currentRole = UserRole.client
          ..favoriteServiceRows = _salonWishlistRow(
            'salon-svc-withdrawn',
            'Послуга, якої вже нема',
          );
        final GoRouter router = await AppHarness.boot(tester, fb);

        await _openPassportAndScrollToWishlist(tester, fb, router);
        await tester.tap(
          find.byKey(const Key('wishlist_card_book_salon-svc-withdrawn')),
        );
        // fixed-wait-ok: settles a real async route-push + provider-load step.
        await tester.pumpAndSettle(const Duration(seconds: 1));

        AppHarness.expectLocation(
          router,
          RouteNames.salonPublicProfile(
            'salon-xyz',
            serviceId: 'salon-svc-withdrawn',
          ),
        );
        expect(find.byKey(const Key('salon-profile-name')), findsOneWidget);

        expect(
          find.byKey(const Key('salon-masters-filter-chip')),
          findsNothing,
          reason:
              'an id absent from the catalogue must clear the filter — no '
              'chip labelled with a raw id or a blank string',
        );
        // Coverage must never even be queried for an id the filter never
        // actually applied.
        expect(fb.getBookableMastersCalls, 0);

        // The FULL, unfiltered roster renders (capped to the first 6, same
        // as a plain profile visit).
        expect(
          find.byKey(const Key('salon-master-card-master-aaa')),
          findsOneWidget,
          reason:
              'the unfiltered masters tab still renders — this is the '
              'SAME screen a plain salon-card tap would show, not a dead end',
        );
        expect(tester.takeException(), isNull);
      });
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
