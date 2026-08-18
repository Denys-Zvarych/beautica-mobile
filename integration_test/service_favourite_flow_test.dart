// Phase 240 — E2E: hearting a SERVICE on the booking service-selection sheet
// gives the BEAUTY WISH LIST its origin.
//
// WHY THIS FILE EXISTS
// ---------------------
// `service_selector_sheet_test.dart` (widget tier) proves the heart renders
// filled/outline and reverts on a failed add, all against a STUBBED
// `wishlistProvider` override. It never proves the two halves of the origin
// story actually connect: a REAL `POST /favorites` fired by a REAL tap on the
// REAL booking flow, landing somewhere the REAL BEAUTY PASSPORT can show it.
// Per the phase doc: *"the only test that will prove the feature end to
// end"* — this is that test.
//
// THE REAL JOURNEY, THE REAL ROUTE
// ---------------------------------
// Login → push the public master profile → «Записатись» → ServiceSelectorSheet
// (Phase 14.1 Step 1) → expand the NAILS category → tap the heart on
// `pub-assign-1` (master-aaa's real, seeded FIXED-price service) → the POST
// fires with `(SERVICE, pub-assign-1)` → back out to the client shell → the
// BEAUTY PASSPORT tab → the wish-list section shows the freshly-favourited
// service.
//
// NO PATROL FLOW NEEDED: no native interaction anywhere in this journey.
//
// KEY POLICY (per AppHarness): every tap is key-based. Raw Ukrainian text
// appears only in CONTENT assertions (master-aaa's name / the service name
// are backend fixture data, not app copy).

import 'dart:async';

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/service_selector_sheet.dart';
import 'package:beautica_mobile/features/master/presentation/public_master_profile_screen.dart';
import 'package:beautica_mobile/features/passport/presentation/passport_screen.dart';
import 'package:beautica_mobile/features/wishlist/presentation/widgets/wishlist_compact_card.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

// ---------------------------------------------------------------------------
// Keys
// ---------------------------------------------------------------------------

const Key _kBookCta = Key('public-master-book-cta');
const Key _kNailsCategory = Key('booking_category_NAILS');
const Key _kHeartPubAssign1 = Key('booking_service_heart_pub-assign-1');
const Key _kNavTilePassport = Key('client-nav-tile-4');

/// The master-aaa fixture service this flow favourites — a FIXED-price NAILS
/// service, seeded verbatim in `FakeBackend._publicMasterServices` AND its
/// `_masterAaaFavoriteServiceFields` favourite-display mirror.
const String _serviceId = 'pub-assign-1';
// i18n-finder-ok: backend fixture data (service name), not app UI copy.
const String _serviceName = 'Манікюр з покриттям';
// i18n-finder-ok: backend fixture data (master's name), not app UI copy.
const String _masterName = 'Софія Бондар';

/// Scrolls the passport page to the bottom so the wish-list block — below the
/// fold on the 800x600 flutter-tester surface — is laid out and tappable.
/// Mirrors `wishlist_flow_test.dart`'s helper of the same name.
Future<void> _scrollToWishList(WidgetTester tester) async {
  await tester.drag(find.byType(Scrollable).last, const Offset(0, -600));
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'CLIENT hearts a service on the booking service-selection sheet → POSTs '
    'a SERVICE favorite → the BEAUTY PASSPORT wish list shows the entry',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      final GoRouter router = await AppHarness.boot(tester, fb);

      // ── Log in, reach the real ServiceSelectorSheet via the real CTA ──────
      await AppHarness.loginAs(tester, fb, UserRole.client);
      // fixed-wait-ok: settles a real async route-push + provider-load step; not a total-wait guess.
      await tester.pumpAndSettle(const Duration(seconds: 1));
      AppHarness.expectLocation(router, RouteNames.clientHome);

      unawaited(router.push(RouteNames.masterPublicProfile('master-aaa')));
      // fixed-wait-ok: settles a real async route-push + provider-load step; not a total-wait guess.
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.byType(PublicMasterProfileScreen), findsOneWidget);

      await tester.tap(find.byKey(_kBookCta));
      // fixed-wait-ok: settles a real async route-push + provider-load step; not a total-wait guess.
      await tester.pumpAndSettle(const Duration(seconds: 1));
      AppHarness.expectLocation(router, RouteNames.bookingNew);
      expect(find.byType(ServiceSelectorSheet), findsOneWidget);

      await tester.tap(find.byKey(_kNailsCategory));
      await tester.pumpAndSettle();

      // ── Rule 3b content check for the 2026-08-10 price-relocation fix ──────
      // `service_catalogue_accordion_overflow_test.dart` (widget tier) proves
      // this same tile survives the narrow-width / high-textScale STRESS
      // matrix without overflowing or starving the name. This flow renders
      // the identical tile against a REAL fixture, at the real sheet's
      // default surface — so it is the right place to prove the CONTENT is
      // right (name + price + duration all present, heart alongside them),
      // not to re-run the layout stress a fixed-size E2E surface can't
      // reproduce anyway.
      expect(
        find.byKey(const Key('catalogue-service-name-pub-assign-1')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('catalogue-service-name-pub-assign-1')),
            )
            .data,
        _serviceName,
      );
      // The meta line's key now sits on a `Wrap` (2026-08-10 round-2 fix —
      // price and duration are two independent `Text` descendants, not one
      // merged `Text.rich`), so the content check finds each figure as its
      // own descendant instead of flattening a single `Text.textSpan`.
      final Finder metaLine = find.byKey(
        const Key('catalogue-service-meta-pub-assign-1'),
      );
      expect(
        find.descendant(of: metaLine, matching: find.textContaining('500 ₴')),
        findsOneWidget,
        reason: "pub-assign-1's FIXED priceDisplay must render on the tile",
      );
      expect(
        find.descendant(
          of: metaLine,
          matching: find.textContaining('1 год 30 хв'),
        ),
        findsOneWidget,
        reason:
            "pub-assign-1's 90-minute effectiveDurationMinutes must format "
            'to "1 год 30 хв" and render on the tile',
      );

      // ── Before: outline heart, no POST yet ─────────────────────────────
      final Finder heart = find.byKey(_kHeartPubAssign1);
      expect(heart, findsOneWidget);
      expect(
        find.descendant(
          of: heart,
          matching: find.byIcon(Icons.favorite_border_rounded),
        ),
        findsOneWidget,
        reason: 'master-aaa\'s service starts un-favourited on a fresh login',
      );
      expect(fb.addFavoriteCalls, 0);

      // ── Tap the heart → optimistic fill + a REAL POST /favorites ──────────
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
      expect(fb.lastAddFavoriteBody?['targetType'], 'SERVICE');
      expect(
        fb.lastAddFavoriteBody?['targetId'],
        _serviceId,
        reason:
            'the favourited target must be the master_services row id '
            '(masterServiceId), never the service-definition id',
      );

      // ── Leave the booking flow entirely, go to the BEAUTY PASSPORT tab ────
      router.go(RouteNames.clientHome);
      await tester.pumpAndSettle();
      AppHarness.expectLocation(router, RouteNames.clientHome);

      await tester.tap(find.byKey(_kNavTilePassport));
      await tester.pumpAndSettle();
      AppHarness.expectLocation(router, RouteNames.clientPassport);
      expect(find.byType(PassportScreen), findsOneWidget);

      await _scrollToWishList(tester);

      // ── THE CONTRACT: the just-favourited service is genuinely on the
      // wish list — not merely POSTed. This is the whole point of the phase:
      // without a real backend round trip AND a real read-back, the wish
      // list has no origin at all. ─────────────────────────────────────────
      expect(
        find.byType(WishlistCompactCard),
        findsOneWidget,
        reason:
            'the wish list must show exactly the one service just favourited '
            'from the booking sheet',
      );
      // i18n-finder-ok: backend fixture data.
      expect(find.text(_serviceName), findsOneWidget);
      expect(find.text(_masterName), findsOneWidget);
      expect(
        fb.favoriteServiceRows.any(
          (Map<String, dynamic> r) => r['masterServiceId'] == _serviceId,
        ),
        isTrue,
        reason:
            'the fake backend must have actually persisted the SERVICE '
            'favourite for the wish list read to be real, not coincidental',
      );
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
