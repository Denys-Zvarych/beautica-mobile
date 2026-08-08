// Phase 239 — E2E: the BEAUTY WISH LIST, from the passport line to «Усі
// збережені» and back.
//
// WHY THIS FILE EXISTS, SEPARATELY FROM passport_flow_test.dart
// ------------------------------------------------------------
// `passport_flow_test.dart` proves the wish list RENDERS: two cards, the right
// prices, «Показати всі (5)». It never leaves the passport page, and it never
// removes anything. So three contracts the track was built around had no E2E
// evidence at all:
//
//   1. THE NESTED ROUTE. «Показати всі (N)» does a `context.push` to
//      `/passport/wishlist`, declared as a CHILD of the passport branch so
//      swipe-back returns to the still-scrolled passport page. A pushed leaf
//      COLLAPSES to the parent path in `currentConfiguration.uri`, so a flow
//      asserting it with the ordinary resolver would report `/passport` and
//      pass whether or not the leaf ever mounted. This file uses
//      [AppHarness.expectNestedPushLocation], the one resolver that drills
//      through the ShellRouteMatch to the push's own match list.
//
//   2. THE SHARED-NOTIFIER CONTRACT (phase 237). One `wishlistProvider` backs
//      both surfaces, and the full-list page deliberately does NOT plumb an
//      `onChanged` callback back to the passport and deliberately does NOT
//      `ref.invalidate` (Riverpod 3 pauses covered consumers; the full-list
//      page COVERS the passport page, so an invalidate would dispose the
//      provider and defer the refetch to resume). The only way to prove that
//      actually works is to remove an entry on one surface and read the OTHER
//      one afterwards — which is exactly what a widget test of either screen
//      alone cannot do. The `listServiceFavoritesCalls` assertion is the
//      load-bearing half: the passport must be correct WITHOUT a refetch. A
//      page that re-fetched on resume would also look right, and would be a
//      different (and slower, and offline-broken) implementation.
//
//   3. THE LAST REMOVAL, ASSERTED MID-FLIGHT. The empty state was once gated on
//      `visibleCount`, which subtracts entries that are still animating out. So
//      the instant the final row's heart was tapped the count hit zero, the
//      empty card replaced the list, and it sat there for ~272 ms BEFORE the
//      DELETE was even sent — retracting back to a populated list if the call
//      failed. EVERY END-STATE ASSERTION PASSES ON THAT BUG: the list does end
//      up empty. Only an assertion taken WHILE the removal is in flight can
//      fail, so that is what this file takes.
//
// FIXTURES ARE THE WORST CASE, from the approved preview's
// `docs/signup-designs/BeautyPassport/lib/screens/passport_data.dart`:
// «Ламінування та фарбування брів», «Анастасія Мельниченко», one FIXED price
// and one RANGE, plus «Шевченківський» on the passport behind it.
//
// CLOCK: nothing here is derived from `DateTime.now()`. `memberSinceYear` is a
// WIRE value and a fixed literal in the fixture, so the fake backend's payload
// and the app's pinned `kFixedNow` clock cannot disagree — the one clock, one
// test rule. There is no date rendered on either wish-list surface.
//
// NO PATROL FLOW NEEDED: no native interaction anywhere in this journey (no OS
// dialog, deep link, FCM, WebView, biometric) — in-app navigation and Riverpod
// state only, so the standard integration_test tier is the correct one.
//
// KEY POLICY (from AppHarness): all TAPS use key-based finders. Raw Ukrainian
// text appears in CONTENT ASSERTIONS only.

import 'dart:async';

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/passport/presentation/passport_screen.dart';
import 'package:beautica_mobile/features/shell/presentation/client_shell.dart';
import 'package:beautica_mobile/features/wishlist/presentation/widgets/wishlist_compact_card.dart';
import 'package:beautica_mobile/features/wishlist/presentation/widgets/wishlist_count_pill.dart';
import 'package:beautica_mobile/features/wishlist/presentation/widgets/wishlist_heart_button.dart';
import 'package:beautica_mobile/features/wishlist/presentation/widgets/wishlist_removable.dart';
import 'package:beautica_mobile/features/wishlist/presentation/widgets/wishlist_removal.dart'
    show wishlistRemovalDelayProvider;
import 'package:beautica_mobile/features/wishlist/presentation/widgets/wishlist_row.dart';
import 'package:beautica_mobile/features/wishlist/presentation/wishlist_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
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

const Key _kWishlistScreen = Key('client-wishlist-screen');
const Key _kWishlistShowAll = Key('wishlist_show_all_button');
const Key _kWishlistBack = Key('wishlist_back_button');
const Key _kWishlistEmpty = Key('wishlist_empty_state');
const Key _kWishlistError = Key('wishlist_error_state');
const Key _kWishlistLoading = Key('wishlist_loading_state');

/// The heart on ONE full-width row, keyed by the entry it belongs to.
Key _rowHeart(String id) => Key('wishlist_row_heart_$id');

// ---------------------------------------------------------------------------
// Wire fixtures. Declared ONCE so the fake-backend payload and the assertions
// cannot drift. These are BACKEND DATA, never AppLocalizations copy, so they
// stay identical when EN ships (hence the `i18n-finder-ok` notes at the
// assertion sites).
// ---------------------------------------------------------------------------

/// A populated `GET /clients/me/passport` body, so the page behind the wish
/// list is the REAL one rather than a history-less shell. Its own rendering is
/// `passport_flow_test.dart`'s job; it is here only so the wish-list section
/// sits where it does in production, below a full-height page.
Map<String, dynamic> _populatedPassportBody() => <String, dynamic>{
  'favoriteDistricts': <String>['Шевченківський', 'Голосіївський'],
  'favoriteCities': <String>['Київ'],
  'budget': <String, dynamic>{
    'avg': 750,
    'min': 400,
    'max': 2400,
    'currency': 'UAH',
  },
  'bookingsConsidered': 7,
  'reviewsWritten': 12,
  'memberSinceYear': 2021,
};

/// One `FavoriteServiceResponse` row.
Map<String, dynamic> _favouriteRow({
  required String id,
  required String serviceName,
  required String firstName,
  required String lastName,
  required int durationMinutes,
  required String priceType,
  required num priceMin,
  num? priceMax,
  required String priceDisplay,
}) => <String, dynamic>{
  'masterServiceId': id,
  'masterId': 'master-$id',
  'serviceName': serviceName,
  'masterFirstName': firstName,
  'masterLastName': lastName,
  'durationMinutes': durationMinutes,
  'priceType': priceType,
  'priceMin': priceMin,
  'priceMax': ?priceMax,
  'priceDisplay': priceDisplay,
};

/// The longest realistic service name — wraps to two lines in a compact card at
/// every viewport and must never ellipsise. FIRST in the list, so removing it
/// is also the case that proves the passport line RE-FLOWS (the third entry
/// promotes into the freed slot) rather than merely losing a card.
const String _wireFirstServiceName = 'Ламінування та фарбування брів';

/// The longest realistic Ukrainian master name.
const String _wireFirstMasterName = 'Анастасія Мельниченко';

const String _wireSecondServiceName = 'Манікюр з покриттям гель-лак';
const String _wireThirdServiceName = 'Нарощування вій — класика 2D';
const String _wireFourthServiceName = 'Корекція брів та фарбування хною';
const String _wireFifthServiceName = 'Педикюр апаратний з покриттям';

/// The backend's LONG-FORM range string for the second entry. Asserted ABSENT
/// on the full-list page too: the app re-formats a RANGE into its own frozen
/// en-dash band on BOTH surfaces, and a full-width row is exactly where a
/// second, unhardened formatter would be easiest to slip in unnoticed.
/// Hoisted so the finder carries no Cyrillic literal at the call site
/// (`scripts/forbid_cyrillic_finder.sh`).
const String _wireSecondPriceLongForm = 'від 600 до 900 ₴';

/// The band the app renders instead.
const String _wireSecondPriceBand = '600–900 ₴';

/// FIVE saved favourites — three more than the passport line's two, so
/// «Показати всі (5)» has something to actually show.
List<Map<String, dynamic>> _favouriteRows() => <Map<String, dynamic>>[
  _favouriteRow(
    id: 'w1',
    serviceName: _wireFirstServiceName,
    firstName: 'Анастасія',
    lastName: 'Мельниченко',
    durationMinutes: 150,
    priceType: 'FIXED',
    priceMin: 1200,
    priceDisplay: '1 200 ₴',
  ),
  _favouriteRow(
    id: 'w2',
    serviceName: _wireSecondServiceName,
    firstName: 'Ірина',
    lastName: 'Бондаренко',
    durationMinutes: 90,
    priceType: 'RANGE',
    priceMin: 600,
    priceMax: 900,
    priceDisplay: _wireSecondPriceLongForm,
  ),
  _favouriteRow(
    id: 'w3',
    serviceName: _wireThirdServiceName,
    firstName: 'Олена',
    lastName: 'Ковальчук',
    durationMinutes: 60,
    priceType: 'FIXED',
    priceMin: 800,
    priceDisplay: '800 ₴',
  ),
  _favouriteRow(
    id: 'w4',
    serviceName: _wireFourthServiceName,
    firstName: 'Софія',
    lastName: 'Романюк',
    durationMinutes: 45,
    priceType: 'FIXED',
    priceMin: 450,
    priceDisplay: '450 ₴',
  ),
  _favouriteRow(
    id: 'w5',
    serviceName: _wireFifthServiceName,
    firstName: 'Вікторія',
    lastName: 'Ткаченко',
    durationMinutes: 120,
    priceType: 'RANGE',
    priceMin: 700,
    priceMax: 1100,
    priceDisplay: 'від 700 до 1100 ₴',
  ),
];

/// A ONE-entry wish list, for the last-removal flow.
List<Map<String, dynamic>> _singleFavouriteRow() => <Map<String, dynamic>>[
  _favouriteRow(
    id: 'w1',
    serviceName: _wireFirstServiceName,
    firstName: 'Анастасія',
    lastName: 'Мельниченко',
    durationMinutes: 150,
    priceType: 'FIXED',
    priceMin: 1200,
    priceDisplay: '1 200 ₴',
  ),
];

Future<AppLocalizations> _uk() =>
    AppLocalizations.delegate.load(const Locale('uk'));

// ---------------------------------------------------------------------------
// Journey helpers
// ---------------------------------------------------------------------------

/// Logs a CLIENT in and hops to the BEAUTY PASSPORT tab (flanking tile 4).
Future<void> _openPassportTab(
  WidgetTester tester,
  FakeBackend fb,
  GoRouter router,
) async {
  await AppHarness.loginAs(tester, fb, UserRole.client);
  await tester.pumpAndSettle();
  AppHarness.expectLocation(router, RouteNames.clientHome);

  await tester.tap(find.byKey(const Key('client-nav-tile-4')));
  await tester.pumpAndSettle();

  AppHarness.expectLocation(router, RouteNames.clientPassport);
  expect(find.byType(PassportScreen), findsOneWidget);
}

/// Scrolls the passport page to the bottom so the wish-list block — below the
/// fold on the 800x600 flutter-tester surface — is laid out and tappable.
Future<void> _scrollToWishList(WidgetTester tester) async {
  await tester.drag(find.byType(Scrollable).last, const Offset(0, -600));
  await tester.pumpAndSettle();
}

/// Scrolls the frontmost list back to its top.
///
/// `tester.ensureVisible` aligns the target with the viewport's LEADING edge,
/// so ensuring a row is tappable on the full-list page pushes the page header —
/// back control, «Beauty wish list» title and its count pill — out of the
/// `ListView`'s cache extent, where it is DISPOSED and no finder can see it.
/// That is a test-harness artefact, not a rendering fact, so the header is
/// scrolled back into existence before anything about it is asserted.
Future<void> _scrollListToTop(WidgetTester tester) async {
  await tester.drag(find.byType(Scrollable).last, const Offset(0, 2000));
  await tester.pumpAndSettle();
}

/// The number inside the section's count pill, wherever that pill currently is.
///
/// Read off the WIDGET rather than by matching rendered text: the pill draws a
/// bare numeral, and `find.text('4')` on a page that also shows durations and
/// prices is an assertion about the whole page, not about the pill.
int _pillCount(WidgetTester tester) =>
    tester.widget<WishlistCountPill>(find.byType(WishlistCountPill)).count;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  // -------------------------------------------------------------------------
  // 1. The nested route, and that the overflow page is genuinely the OVERFLOW.
  // -------------------------------------------------------------------------
  testWidgets(
    '«Показати всі (5)» pushes /passport/wishlist and lists EVERY favourite, '
    'including the three the two-card line could not show',
    (tester) async {
      final fb = FakeBackend()
        ..currentRole = UserRole.client
        ..passportBody = _populatedPassportBody()
        ..favoriteServiceRows = _favouriteRows();
      final GoRouter router = await AppHarness.boot(tester, fb);

      await _openPassportTab(tester, fb, router);
      await _scrollToWishList(tester);

      final AppLocalizations l10n = await _uk();

      // The passport line shows TWO cards and a pill stating FIVE — the count
      // is of what is SAVED, not of what is on screen.
      expect(find.byType(WishlistCompactCard), findsNWidgets(2));
      expect(_pillCount(tester), 5);
      expect(find.text(l10n.wishlistShowAll(5)), findsOneWidget);

      // ── The push ────────────────────────────────────────────────────────
      await tester.tap(find.byKey(_kWishlistShowAll));
      await tester.pumpAndSettle();

      // `expectNestedPushLocation`, NOT `expectLocation`: this leaf is a child
      // GoRoute of the passport branch reached by `context.push`, so
      // `currentConfiguration.uri` still reports `/passport`. The ordinary
      // resolver would pass here even if the push had never happened.
      AppHarness.expectNestedPushLocation(router, RouteNames.clientWishlist);
      expect(find.byType(WishlistScreen), findsOneWidget);
      expect(find.byKey(_kWishlistScreen), findsOneWidget);
      expect(
        find.byType(ClientShell),
        findsOneWidget,
        reason:
            'the leaf is nested INSIDE the passport branch, so the client '
            'shell stays mounted — that nesting is what buys swipe-back to '
            'the still-scrolled passport page',
      );

      // ── Every favourite is here, as a full-width row ────────────────────
      expect(
        find.byType(WishlistRow),
        findsNWidgets(5),
        reason:
            'the overflow page shows the WHOLE list — a page that reused the '
            'section\'s take(2) would render two and still look plausible',
      );
      expect(
        find.byType(WishlistCompactCard),
        findsNothing,
        reason:
            'the full-list page renders WishlistRow, never the passport '
            'page\'s compact card',
      );
      for (final String name in <String>[
        _wireFirstServiceName,
        _wireSecondServiceName,
        _wireThirdServiceName,
        _wireFourthServiceName,
        _wireFifthServiceName,
      ]) {
        // i18n-finder-ok: service names come from the wire fixture above.
        expect(
          find.text(name),
          findsOneWidget,
          reason: 'saved service «$name» must be listed on the overflow page',
        );
      }
      // The person glyph the compact card cannot afford; the full-width row
      // carries it, one per entry.
      expect(find.byIcon(Icons.person_outline_rounded), findsNWidgets(5));

      // The RANGE band is re-formatted HERE TOO — a second render site is
      // exactly where an unhardened `'$min–$max ₴'` would appear.
      expect(
        // i18n-finder-ok: the wire's long-form price string.
        find.text(_wireSecondPriceLongForm),
        findsNothing,
        reason:
            'a RANGE entry renders the app\'s frozen band on BOTH surfaces, '
            'never the backend\'s long form',
      );
      // i18n-finder-ok: the app-formatted band, asserted as data.
      expect(find.text(_wireSecondPriceBand), findsOneWidget);

      // The page's own counter agrees with the section's.
      expect(_pillCount(tester), 5);

      // Non-data states are absent, and the endpoint was hit exactly once —
      // the push must not re-fetch a list the shared provider already holds.
      expect(find.byKey(_kWishlistEmpty), findsNothing);
      expect(find.byKey(_kWishlistError), findsNothing);
      expect(find.byKey(_kWishlistLoading), findsNothing);
      expect(
        fb.listServiceFavoritesCalls,
        1,
        reason:
            'both surfaces read ONE cached provider — a second GET would mean '
            'the full-list page had its own fetch',
      );
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

  // -------------------------------------------------------------------------
  // 2. The shared-notifier contract (phase 237), across a real route change.
  // -------------------------------------------------------------------------
  testWidgets(
    'un-favouriting on the full-list page removes it there AND on the passport '
    'behind it, with no second fetch',
    (tester) async {
      final fb = FakeBackend()
        ..currentRole = UserRole.client
        ..passportBody = _populatedPassportBody()
        ..favoriteServiceRows = _favouriteRows();
      final GoRouter router = await AppHarness.boot(tester, fb);

      await _openPassportTab(tester, fb, router);
      await _scrollToWishList(tester);

      final AppLocalizations l10n = await _uk();

      // The first card on the passport line, before we touch anything.
      // i18n-finder-ok: wire fixture values.
      expect(find.text(_wireFirstServiceName), findsOneWidget);
      expect(find.text(_wireFirstMasterName), findsOneWidget);

      await tester.tap(find.byKey(_kWishlistShowAll));
      await tester.pumpAndSettle();
      AppHarness.expectNestedPushLocation(router, RouteNames.clientWishlist);

      // ── Remove the FIRST entry, on the full-list page ────────────────────
      final Finder heart = find.byKey(_rowHeart('w1'));
      expect(heart, findsOneWidget);
      await tester.ensureVisible(heart);
      await tester.pumpAndSettle();
      await tester.tap(heart);
      await tester.pumpAndSettle();

      // The wire call went out, keyed on the SERVICE target and the
      // masterServiceId — not on masterId, which the backend would answer 204
      // to just the same while removing nothing (or the wrong thing).
      expect(fb.removeFavoriteCalls, 1);
      expect(fb.lastRemoveFavoriteQuery?['targetType'], 'SERVICE');
      expect(
        fb.lastRemoveFavoriteQuery?['targetId'],
        'w1',
        reason:
            'the favourite is keyed on masterServiceId; keying it on masterId '
            'still returns 204 and removes the wrong row',
      );

      // Gone from THIS surface.
      expect(find.byType(WishlistRow), findsNWidgets(4));
      // i18n-finder-ok: wire fixture value.
      expect(find.text(_wireFirstServiceName), findsNothing);

      await _scrollListToTop(tester);
      expect(_pillCount(tester), 4);

      // ── Back to the passport — the OTHER surface ─────────────────────────
      await tester.tap(find.byKey(_kWishlistBack));
      await tester.pumpAndSettle();
      AppHarness.expectLocation(router, RouteNames.clientPassport);
      expect(find.byType(WishlistScreen), findsNothing);

      await _scrollToWishList(tester);

      // THE CONTRACT. No callback was plumbed and no invalidate was fired, so
      // if the two surfaces did not share one notifier this page would still
      // be showing the entry that was just deleted.
      // i18n-finder-ok: wire fixture values.
      expect(
        find.text(_wireFirstServiceName),
        findsNothing,
        reason:
            'the removed entry must be gone from the passport line too — one '
            'provider backs both surfaces',
      );
      expect(find.text(_wireFirstMasterName), findsNothing);
      expect(
        find.byType(WishlistCompactCard),
        findsNWidgets(2),
        reason:
            'the line still shows TWO cards — the third favourite promotes '
            'into the freed slot rather than the line shrinking to one',
      );
      // i18n-finder-ok: wire fixture values — w2 and w3 are now the line.
      expect(find.text(_wireSecondServiceName), findsOneWidget);
      expect(find.text(_wireThirdServiceName), findsOneWidget);

      expect(_pillCount(tester), 4);
      expect(find.text(l10n.wishlistShowAll(4)), findsOneWidget);
      expect(find.text(l10n.wishlistShowAll(5)), findsNothing);

      // …and none of it came from a refetch. This is the half that
      // distinguishes the shipped in-place mutation from a re-GET on resume,
      // which would look identical in every assertion above.
      expect(
        fb.listServiceFavoritesCalls,
        1,
        reason:
            'removeService mutates shared state in place; a refetch here '
            'would mean the passport was reading a NEW response, not the '
            'shared one — and would show stale data offline',
      );
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

  // -------------------------------------------------------------------------
  // 3. The LAST removal — asserted MID-FLIGHT, which is the only way it fails.
  // -------------------------------------------------------------------------
  testWidgets(
    'removing the LAST favourite reaches the empty state — and NOT before the '
    'wire call is even made',
    (tester) async {
      final fb = FakeBackend()
        ..currentRole = UserRole.client
        ..passportBody = _populatedPassportBody()
        ..favoriteServiceRows = _singleFavouriteRow();

      // Audit cycle 3 — the mid-flight window this test asserts (animation
      // started, wire call not yet sent) used to be reached by racing two
      // `tester.pump(fixedDuration)` calls against `WishlistRemovalHost`'s own
      // real-clock `Future.delayed(WishlistRemovable.duration)`.
      // `IntegrationTestWidgetsFlutterBinding` (which this file runs on even
      // headless, under `flutter test -d flutter-tester` — it extends
      // `LiveTestWidgetsFlutterBinding`, a REAL clock) makes that a genuine
      // race: it failed once and passed on two immediate reruns. Overriding
      // `wishlistRemovalDelayProvider` with a [Completer] this test controls
      // removes the wall-clock upper bound entirely — the collapse cannot
      // resolve into a wire call until `removalGate.complete()` is called
      // below, no matter how long real time takes to get there. The only
      // remaining timing requirement is a LOWER bound (wait past the heart's
      // 110 ms pop so `_removing.add` has actually run), which is safe to
      // overshoot generously since there is no upper bound left to race.
      final Completer<void> removalGate = Completer<void>();
      final GoRouter router = await AppHarness.boot(
        tester,
        fb,
        extraOverrides: <Object>[
          wishlistRemovalDelayProvider.overrideWithValue(
            () => removalGate.future,
          ),
        ],
      );

      await _openPassportTab(tester, fb, router);
      await _scrollToWishList(tester);

      final AppLocalizations l10n = await _uk();

      expect(find.byType(WishlistCompactCard), findsOneWidget);
      expect(_pillCount(tester), 1);

      await tester.tap(find.byKey(_kWishlistShowAll));
      await tester.pumpAndSettle();
      AppHarness.expectNestedPushLocation(router, RouteNames.clientWishlist);
      expect(find.byType(WishlistRow), findsOneWidget);
      expect(find.byKey(_kWishlistEmpty), findsNothing);

      // ── Tap the only heart, then STOP pumping and look ──────────────────
      //
      // The sequence is: heart pop (110 ms, real timer, untouched) → row
      // collapse → the GATED delay above → removeService → DELETE. A frame
      // taken while the gate is still open is a frame where the entry is
      // still in provider state and the request has NOT been sent — true no
      // matter how much real time this pump call actually takes.
      //
      // NO `pumpAndSettle` HERE — deliberately. Settling would block forever
      // waiting on the still-open gate (there would be no pending frames/
      // timers to settle against once the gated future itself is the only
      // thing left in flight — `pumpAndSettle` cannot know it will resolve).
      final Finder heart = find.byKey(_rowHeart('w1'));
      await tester.ensureVisible(heart);
      await tester.pumpAndSettle();
      await tester.tap(heart);

      // Comfortably past the heart's pop — safe to overshoot; the gated
      // collapse delay cannot resolve early regardless of how long this waits.
      //
      // Widened 3x -> 10x (mobile-qa, 2026-08-08): under two concurrent
      // CPU-saturating audit-agent processes this file returned an anomalous
      // +1/-2 in a five-file back-to-back run, while passing 3/3 alone. The
      // 3x margin (330 ms) assumed the process gets scheduled promptly enough
      // for the heart's OWN un-gated 110 ms `Future.delayed` to fire within
      // that wall-clock window; under severe host contention the single-
      // threaded isolate can be starved past that. The widen costs ~0.8s of
      // real test time and is risk-free per the overshoot argument above (the
      // assertions below are bounded by the COMPLETER gate, not by this
      // wait — confirmed by mutation: this wait can be set to Duration.zero
      // and every assertion in this block still passes, because nothing here
      // depends on the pop animation having actually completed).
      await tester.pump(WishlistHeartButton.popDuration * 10);

      expect(
        fb.removeFavoriteCalls,
        0,
        reason:
            'the wire call is made AFTER the exit animation — the removal '
            'gate is still open, so this is inside the window where the '
            'shipped bug showed «nothing saved» for a removal that had not '
            'yet been attempted',
      );
      expect(
        find.byKey(_kWishlistEmpty),
        findsNothing,
        reason:
            'THE REGRESSION GUARD. Gating the empty state on `visibleCount` '
            '(which subtracts entries mid-exit) put the empty card on screen '
            'here, ~272 ms before the DELETE and retracting it on failure. '
            'Every END-state assertion passes on that bug; only this one does '
            'not.',
      );
      expect(
        find.byType(WishlistRemovable),
        findsOneWidget,
        reason:
            'the LIST branch is still the one being rendered — `_buildList` '
            'has not swapped itself for the empty card. (The WishlistRow '
            'itself is already gone by design: WishlistRemovable replaces its '
            'child with a SizedBox on the first frame and animates the '
            'resulting SIZE change, so asserting on the row would assert the '
            'animation\'s shape rather than the gate under test.)',
      );

      // ── Release the gate and let it finish ───────────────────────────────
      removalGate.complete();
      await tester.pumpAndSettle();

      expect(fb.removeFavoriteCalls, 1);
      expect(fb.lastRemoveFavoriteQuery?['targetType'], 'SERVICE');
      expect(fb.lastRemoveFavoriteQuery?['targetId'], 'w1');

      expect(find.byType(WishlistRow), findsNothing);
      expect(find.byKey(_kWishlistEmpty), findsOneWidget);
      expect(find.text(l10n.wishlistEmptyMessage), findsOneWidget);
      expect(find.text(l10n.wishlistEmptyCta), findsOneWidget);
      expect(
        find.byKey(_kWishlistError),
        findsNothing,
        reason:
            'an emptied wish list is an INVITATION, never a failure — the two '
            'are separately pinned because collapsing them is the defect '
            'class this feature keeps being audited for',
      );

      await _scrollListToTop(tester);
      expect(
        _pillCount(tester),
        0,
        reason:
            'the list is genuinely empty, so «0» is TRUE here — the pill is '
            'suppressed only when there is no list to count (a failure, or a '
            'first load), which is a different claim',
      );

      // ── And the passport behind it agrees ────────────────────────────────
      await tester.tap(find.byKey(_kWishlistBack));
      await tester.pumpAndSettle();
      AppHarness.expectLocation(router, RouteNames.clientPassport);
      await _scrollToWishList(tester);

      expect(find.byType(WishlistCompactCard), findsNothing);
      expect(find.byKey(_kWishlistEmpty), findsOneWidget);
      expect(
        find.byKey(_kWishlistShowAll),
        findsNothing,
        reason: 'nothing left to show all of',
      );
      expect(fb.listServiceFavoritesCalls, 1);
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
