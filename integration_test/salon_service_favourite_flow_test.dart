// Phase F — E2E: hearting a SALON-catalogue service gives the BEAUTY WISH
// LIST a SALON-sourced origin.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b)
// ---------------------------------------
// `service_favourite_flow_test.dart` is this file's MASTER-arm sibling — it
// proves a real heart tap on the booking service-selection sheet POSTs
// `(SERVICE, masterServiceId)` and the Beauty Passport genuinely reads it
// back. Phase F shipped the identical affordance on the SALON catalogue
// (`SalonServiceSelectionScreen`, `FavoriteTargetType.salonService`), and
// `salon_service_selection_screen_test.dart` (widget tier) already proves the
// heart renders and POSTs the right target type — against a STUBBED
// `favoriteRepositoryProvider`. Neither of those proves the other half: that a
// real `POST /favorites` with `SALON_SERVICE` actually lands somewhere the
// Beauty Passport can read back as a SALON row (storefront glyph, salon name,
// verbatim price — Phase F's whole render contract).
//
// `wishlist_salon_service_redirect_flow_test.dart` (Phase G) exercises the
// PASSPORT → tap → salon-profile-redirect direction against a SALON row it
// seeds directly onto `FakeBackend.favoriteServiceRows` — it never drives a
// real heart tap, so it cannot catch a regression in the favouriting half
// (e.g. the fake, or the real backend, failing to persist a SALON_SERVICE add
// at all). This file is the one place both halves of the SALON-arm journey
// are proven end to end: a REAL tap → a REAL POST → a REAL read-back.
//
// THE REAL JOURNEY, THE REAL ROUTE
// ---------------------------------
// Login → push salon-xyz's public profile → «Записатись на послугу»
// (`salon-book-cta`) → `SalonServiceSelectionScreen` → the NAILS category is
// expanded by default → tap the heart on `salon-svc-shared` → the POST fires
// with `(SALON_SERVICE, salon-svc-shared)` → back out to the client shell →
// the BEAUTY PASSPORT tab → the wish-list section shows the freshly-
// favourited SALON row.
//
// NO PATROL FLOW NEEDED: no native interaction anywhere in this journey.
//
// KEY POLICY (per AppHarness): every tap is key-based. Raw Ukrainian text
// appears only in CONTENT assertions (the salon's name / the service name are
// backend fixture data, not app copy), each carrying `i18n-finder-ok`.

import 'dart:async';

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_service_selection_screen.dart';
import 'package:beautica_mobile/features/passport/presentation/passport_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/public_salon_profile_screen.dart';
import 'package:beautica_mobile/features/wishlist/presentation/widgets/wishlist_compact_card.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

// ---------------------------------------------------------------------------
// Keys
// ---------------------------------------------------------------------------

const Key _kSalonBookCta = Key('salon-book-cta');
const Key _kHeartSalonSvcShared = Key('booking_service_heart_salon-svc-shared');
const Key _kNavTilePassport = Key('client-nav-tile-4');

/// `salon-xyz`'s catalogue entry this flow favourites — a real, seeded FIXED
/// NAILS service (see `FakeBackend._salonServiceCategories`), in the category
/// that is expanded by default so no category tap is needed first.
const String _serviceDefId = 'salon-svc-shared';
// i18n-finder-ok: backend fixture data (service name), not app UI copy.
const String _serviceName = 'Манікюр класичний';
// i18n-finder-ok: backend fixture data (salon name), not app UI copy.
const String _salonName = 'Студія Краси «Камелія»';

/// Scrolls the passport page to the bottom so the wish-list block — below the
/// fold on the 800x600 flutter-tester surface — is laid out and tappable.
/// Mirrors `service_favourite_flow_test.dart`'s helper of the same name.
Future<void> _scrollToWishList(WidgetTester tester) async {
  await tester.drag(find.byType(Scrollable).last, const Offset(0, -600));
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'CLIENT hearts a service on the salon catalogue → POSTs a SALON_SERVICE '
    'favorite → the BEAUTY PASSPORT wish list shows a SALON-sourced row',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()..currentRole = UserRole.client;
        final GoRouter router = await AppHarness.boot(tester, fb);

        // ── Log in, reach the real SalonServiceSelectionScreen via the real
        // CTA chain ────────────────────────────────────────────────────────
        await AppHarness.loginAs(tester, fb, UserRole.client);
        // fixed-wait-ok: settles a real async route-push + provider-load step; not a total-wait guess.
        await tester.pumpAndSettle(const Duration(seconds: 1));
        AppHarness.expectLocation(router, RouteNames.clientHome);

        unawaited(router.push(RouteNames.salonPublicProfile('salon-xyz')));
        // fixed-wait-ok: settles a real async route-push + provider-load step; not a total-wait guess.
        await tester.pumpAndSettle(const Duration(seconds: 1));
        expect(find.byType(PublicSalonProfileScreen), findsOneWidget);

        await tester.tap(find.byKey(_kSalonBookCta));
        // fixed-wait-ok: settles a real async route-push + provider-load step; not a total-wait guess.
        await tester.pumpAndSettle(const Duration(seconds: 1));
        AppHarness.expectLocation(router, RouteNames.salonBookingServices);
        expect(find.byType(SalonServiceSelectionScreen), findsOneWidget);

        // NAILS is the first category and is expanded on load — the tile is
        // already on screen, no category tap needed.
        expect(
          find.byKey(const Key('salon_booking_service_tile_$_serviceDefId')),
          findsOneWidget,
        );

        // ── Before: outline heart, no POST yet ─────────────────────────────
        final Finder heart = find.byKey(_kHeartSalonSvcShared);
        expect(heart, findsOneWidget);
        expect(
          find.descendant(
            of: heart,
            matching: find.byIcon(Icons.favorite_border_rounded),
          ),
          findsOneWidget,
          reason: "salon-xyz's catalogue starts un-favourited on a fresh login",
        );
        expect(fb.addFavoriteCalls, 0);

        // ── Tap the heart → optimistic fill + a REAL POST /favorites ──────
        await tester.tap(heart);
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: heart,
            matching: find.byIcon(Icons.favorite_rounded),
          ),
          findsOneWidget,
          reason: 'the heart fills immediately (optimistic)',
        );
        expect(fb.addFavoriteCalls, 1);
        expect(fb.lastAddFavoriteBody?['targetType'], 'SALON_SERVICE');
        expect(
          fb.lastAddFavoriteBody?['targetId'],
          _serviceDefId,
          reason:
              'the favourited target must be the service_definitions id '
              '(serviceDefId), never a masterServiceId — this catalogue row '
              'has no master assignment at all',
        );

        // ── Leave the booking flow entirely, go to the BEAUTY PASSPORT tab ──
        router.go(RouteNames.clientHome);
        await tester.pumpAndSettle();
        AppHarness.expectLocation(router, RouteNames.clientHome);

        await tester.tap(find.byKey(_kNavTilePassport));
        await tester.pumpAndSettle();
        AppHarness.expectLocation(router, RouteNames.clientPassport);
        expect(find.byType(PassportScreen), findsOneWidget);

        await _scrollToWishList(tester);

        // ── THE CONTRACT: the just-favourited SALON service is genuinely on
        // the wish list, rendered as a SALON row — not merely POSTed, and not
        // rendered as if it were a MASTER row. Without a real backend round
        // trip AND a real read-back, this half of Phase F has no origin at
        // all. ───────────────────────────────────────────────────────────
        expect(
          find.byType(WishlistCompactCard),
          findsOneWidget,
          reason:
              'the wish list must show exactly the one service just '
              'favourited from the salon catalogue',
        );
        // i18n-finder-ok: backend fixture data.
        expect(find.text(_serviceName), findsOneWidget);
        // The SALON attribution line — the salon's name, never a master's.
        // i18n-finder-ok: backend fixture data.
        expect(find.text(_salonName), findsOneWidget);
        // The storefront glyph is the SALON-row signal (see
        // `wishlist_entry_labels.dart`'s `attributionIcon`) — a person glyph
        // here would mean the row was mapped onto the MASTER arm instead.
        expect(find.byIcon(Icons.storefront_rounded), findsWidgets);
        expect(find.byIcon(Icons.person_outline_rounded), findsNothing);
        expect(
          fb.favoriteServiceRows.any(
            (Map<String, dynamic> r) =>
                r['serviceDefId'] == _serviceDefId &&
                r['sourceType'] == 'SALON',
          ),
          isTrue,
          reason:
              'the fake backend must have actually persisted the '
              'SALON_SERVICE favourite as a SALON-shaped row for the wish '
              'list read to be real, not coincidental',
        );
      });
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
