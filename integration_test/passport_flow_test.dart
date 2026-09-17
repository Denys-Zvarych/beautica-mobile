// Phase 238 — E2E: CLIENT BEAUTY PASSPORT tab flow.
//
// WHY THIS FILE EXISTS
// --------------------
// The widget tier (test/features/passport/…) proves the rebuilt page and its
// two new widgets in isolation with mocked providers. The client-shell flow
// proves branch HOPPING in general. Neither exercises the REAL journey: a
// CLIENT logging in through the real login form against the fake backend,
// hopping to the BEAUTY PASSPORT tab (branch index 4), and seeing the page
// assemble itself from TWO independent endpoints —
// `GET /clients/me/passport` and `GET /favorites/services`.
//
// AN EMPTY-ONLY E2E IS NOT EVIDENCE
// ---------------------------------
// This flow once asserted the empty-state CTA and nothing else, with a header
// declaring the always-empty placeholder repository to be expected behaviour.
// It therefore passed ON the bug: the screen showed every client the empty
// state forever and the E2E called that a success. An empty-only E2E cannot
// distinguish "correctly empty" from "structurally incapable of being anything
// else". So the POPULATED case is the load-bearing one here, and the call
// counters (`getPassportCalls`, `listServiceFavoritesCalls`) pin that both
// endpoints are genuinely hit rather than short-circuited in a data layer.
//
// WHAT PHASE 238 CHANGED FOR THIS FILE
// ------------------------------------
// `PassportCard` (passport_table.dart) and the `_EmptyPassport` hero — with its
// `passport_find_master_button` — were DELETED. So:
//   • "the payload rendered" is now asserted against `PassportIdentityStrip`
//     (the standing lines) and `PassportDerivedBlock` (localities + average);
//   • the «Знайти майстра» invitation now belongs to the WISH LIST's own empty
//     state, so the CTA-navigates-to-search case below taps THAT button;
//   • the wish list is a third rendered surface with its own endpoint, and its
//     two-card line plus «Показати всі (N)» are asserted here for the first
//     time.
//
// FIXTURES ARE THE WORST CASE, from the approved preview's
// `docs/signup-designs/BeautyPassport/lib/screens/passport_data.dart`:
// «Шевченківський» (the district that used to clip to «Шев…»), «Ламінування та
// фарбування брів», «Анастасія Мельниченко», one FIXED price and one RANGE.
//
// CLOCK: nothing here is derived from `DateTime.now()`. `memberSinceYear` is a
// WIRE value and is a fixed literal in the fixture, so the fake backend's
// payload and the app's pinned `kFixedNow` clock cannot disagree.
//
// NO PATROL FLOW NEEDED: this journey involves no native interaction (no OS
// permission dialog, deep link, FCM, WebView, biometric) — only in-app
// navigation and Riverpod state — so a standard integration_test flow is the
// correct and sufficient tier. The screen-protection acquire/release contract
// is covered at the widget tier, where the native plugin is kDebugMode-guarded.
// (That contract is the app-switcher blur plus the shared reference count — it
// stopped involving FLAG_SECURE on 2026-08-20; see the header of
// `lib/core/security/screen_protection.dart`.)
//
// KEY POLICY (from AppHarness): all TAPS use key-based finders. Raw Ukrainian
// text appears in CONTENT ASSERTIONS only.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/home/presentation/widgets/hub_widgets.dart';
import 'package:beautica_mobile/features/home/presentation/widgets/passport_preview_card.dart';
import 'package:beautica_mobile/features/passport/presentation/passport_screen.dart';
import 'package:beautica_mobile/features/passport/presentation/widgets/passport_derived_block.dart';
import 'package:beautica_mobile/features/passport/presentation/widgets/passport_identity_strip.dart';
import 'package:beautica_mobile/features/shell/presentation/client_shell.dart';
import 'package:beautica_mobile/features/shell/presentation/widgets/client_bottom_nav.dart';
import 'package:beautica_mobile/features/wishlist/presentation/widgets/wishlist_compact_card.dart';
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

const Key _kIdentityStrip = Key('passport_identity_strip');
const Key _kDerivedBlock = Key('passport_derived_block');
const Key _kPassportError = Key('passport_error_state');
const Key _kWishlistEmpty = Key('wishlist_empty_state');
const Key _kWishlistError = Key('wishlist_error_state');
const Key _kWishlistShowAll = Key('wishlist_show_all_button');

// ---------------------------------------------------------------------------
// Wire fixtures. Declared ONCE so the fake-backend payload and the assertions
// cannot drift, and so the finders read the payload rather than re-typing it —
// these are BACKEND DATA, never AppLocalizations copy, so they stay identical
// when EN ships (hence the `i18n-finder-ok` notes at the assertion sites).
// ---------------------------------------------------------------------------

const List<String> _wireDistricts = <String>[
  'Шевченківський',
  'Голосіївський',
  'Печерський',
];
const List<String> _wireCities = <String>['Київ', 'Бровари'];

/// The AVERAGE the derived block renders through `passportBudgetAverage`.
/// Deliberately different from the band's `max` (2400): a page still wired to
/// the ceiling would print 2400 and fail here rather than passing by accident.
const int _wireBudgetAvg = 750;
const int _wireBudgetMax = 2400;

const int _wireReviewsWritten = 12;

/// Not the current year, and not derivable from any clock — so a screen that
/// re-derived the join year could not produce it.
const int _wireMemberSinceYear = 2021;

/// A POPULATED `GET /clients/me/passport` body. Every value is deliberately
/// distinguishable from the no-history body, so an assertion below cannot be
/// satisfied by the payload the flow previously (and only) exercised.
Map<String, dynamic> _populatedPassportBody() => <String, dynamic>{
  'favoriteDistricts': _wireDistricts,
  'favoriteCities': _wireCities,
  'budget': <String, dynamic>{
    'avg': _wireBudgetAvg,
    'min': 400,
    'max': _wireBudgetMax,
    'currency': 'UAH',
  },
  'bookingsConsidered': 7,
  'reviewsWritten': _wireReviewsWritten,
  'memberSinceYear': _wireMemberSinceYear,
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

/// The service name on the FIRST card — the longest realistic one, which wraps
/// to two lines in a compact card at every viewport and must never ellipsise.
const String _wireFirstServiceName = 'Ламінування та фарбування брів';

/// The master on the FIRST card — the longest realistic Ukrainian name.
const String _wireFirstMasterName = 'Анастасія Мельниченко';

/// The FIXED price the first card renders VERBATIM off the wire.
const String _wireFirstPriceDisplay = '1 200 ₴';

/// The service name on the SECOND card — the RANGE-priced one.
const String _wireSecondServiceName = 'Манікюр з покриттям гель-лак';

/// The backend's LONG-FORM range string for that second card. Asserted ABSENT:
/// the app re-formats a RANGE into its own frozen band, and the long form does
/// not fit the compact card (the one fix this redesign forbids is an ellipsis).
/// Hoisted to a constant so the finder carries no Cyrillic literal at the call
/// site (`scripts/forbid_cyrillic_finder.sh`).
const String _wireSecondPriceLongForm = 'від 600 до 900 ₴';

/// The band the app renders instead.
const String _wireSecondPriceBand = '600–900 ₴';

/// FIVE saved favourites, so the line shows exactly two and the overflow button
/// must state «Показати всі (5)».
List<Map<String, dynamic>> _favouriteRows() => <Map<String, dynamic>>[
  _favouriteRow(
    id: 'w1',
    serviceName: _wireFirstServiceName,
    firstName: 'Анастасія',
    lastName: 'Мельниченко',
    durationMinutes: 150,
    priceType: 'FIXED',
    priceMin: 1200,
    priceDisplay: _wireFirstPriceDisplay,
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
    // The backend's long form. The app RE-FORMATS a RANGE into its own en-dash
    // band, so this exact string must NOT appear on screen — see the assertion.
    priceDisplay: _wireSecondPriceLongForm,
  ),
  _favouriteRow(
    id: 'w3',
    serviceName: 'Нарощування вій — класика 2D',
    firstName: 'Олена',
    lastName: 'Ковальчук',
    durationMinutes: 60,
    priceType: 'FIXED',
    priceMin: 800,
    priceDisplay: '800 ₴',
  ),
  _favouriteRow(
    id: 'w4',
    serviceName: 'Корекція брів та фарбування хною',
    firstName: 'Софія',
    lastName: 'Романюк',
    durationMinutes: 45,
    priceType: 'FIXED',
    priceMin: 450,
    priceDisplay: '450 ₴',
  ),
  _favouriteRow(
    id: 'w5',
    serviceName: 'Педикюр апаратний з покриттям',
    firstName: 'Вікторія',
    lastName: 'Ткаченко',
    durationMinutes: 120,
    priceType: 'RANGE',
    priceMin: 700,
    priceMax: 1100,
    priceDisplay: 'від 700 до 1100 ₴',
  ),
];

/// The two sessions' passports. Every asserted field differs, and neither
/// year is derivable from any clock — so a page that leaked the first
/// session's member prints values this flow can name exactly.
const int _kSessionAYear = 2019;
const int _kSessionAReviews = 7;
const int _kSessionBYear = 2024;
const int _kSessionBReviews = 1;

/// The two sessions' own two-sided ratings, rendered by [MyRatingStatCard] as
/// `toStringAsFixed(1)` on the CLIENT home hub.
const double _kSessionARating = 4.9;
const double _kSessionBRating = 4.1;

/// A FULL `GET /clients/me/passport` body parameterised on the two fields the
/// session-boundary flow asserts. Deliberately populated rather than empty:
/// an empty payload renders the no-history state, where "the wrong account's
/// passport" and "no passport" would look the same.
Map<String, dynamic> _sessionPassportBody({
  required int memberSinceYear,
  required int reviewsWritten,
}) => <String, dynamic>{
  'favoriteDistricts': _wireDistricts,
  'favoriteCities': _wireCities,
  'budget': <String, dynamic>{
    'avg': _wireBudgetAvg,
    'min': 400,
    'max': _wireBudgetMax,
    'currency': 'UAH',
  },
  'bookingsConsidered': 7,
  'reviewsWritten': reviewsWritten,
  'memberSinceYear': memberSinceYear,
};

Future<AppLocalizations> _uk() =>
    AppLocalizations.delegate.load(const Locale('uk'));

/// Logs a CLIENT in and hops to the BEAUTY PASSPORT tab (flanking tile 4),
/// asserting the branch actually mounted.
Future<void> _openPassportTab(
  WidgetTester tester,
  FakeBackend fb,
  GoRouter router,
) async {
  await AppHarness.loginAs(tester, fb, UserRole.client);
  await tester.pumpAndSettle(const Duration(seconds: 1));
  AppHarness.expectLocation(router, RouteNames.clientHome);

  await tester.tap(find.byKey(const Key('client-nav-tile-4')));
  await tester.pumpAndSettle(const Duration(seconds: 1));

  AppHarness.expectLocation(router, RouteNames.clientPassport);
  expect(
    find.byType(ClientShell),
    findsOneWidget,
    reason: 'exactly one ClientShell must remain after hopping to passport',
  );
  expect(find.byType(ClientBottomNav), findsOneWidget);
  expect(
    find.byType(PassportScreen),
    findsOneWidget,
    reason: 'the index-4 branch must mount the REAL PassportScreen',
  );
  expect(
    find.byKey(const Key('client-branch-passport')),
    findsOneWidget,
    reason: 'PassportScreen must carry the client-branch-passport key',
  );
}

/// Scrolls the passport page to the bottom so the wish-list block — which sits
/// below the fold on the 800x600 flutter-tester surface — is built and laid out.
Future<void> _scrollToWishList(WidgetTester tester) async {
  await tester.drag(find.byType(Scrollable).last, const Offset(0, -600));
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'CLIENT with derived history and five favourites sees the whole rebuilt '
    'passport page off the wire',
    (tester) async {
      // THE LOAD-BEARING E2E CASE. It exercises the whole chain the widget suite
      // stubs out, twice over: Dio → ClientControllerApi → HttpPassportRepository
      // → PassportMapper → passportProvider → the strip + derived block, AND
      // Dio → FavoriteControllerApi → HttpWishlistRepository → WishlistMapper →
      // wishlistProvider → the two-card line.
      final fb = FakeBackend()
        ..currentRole = UserRole.client
        ..passportBody = _populatedPassportBody()
        ..favoriteServiceRows = _favouriteRows();
      final GoRouter router = await AppHarness.boot(tester, fb);

      await _openPassportTab(tester, fb, router);

      // Both endpoints were genuinely called — the assertion a placeholder
      // repository (which resolved with no network at all) could never satisfy.
      expect(
        fb.getPassportCalls,
        greaterThanOrEqualTo(1),
        reason:
            'the passport tab must hit GET /clients/me/passport — a screen '
            'that renders without calling the endpoint is the shipped bug',
      );
      expect(
        fb.listServiceFavoritesCalls,
        greaterThanOrEqualTo(1),
        reason: 'the wish-list section must hit GET /favorites/services',
      );

      final AppLocalizations l10n = await _uk();

      // ── 1. THE IDENTITY STRIP: the two STANDING lines ──────────────────────
      expect(find.byKey(_kIdentityStrip), findsOneWidget);
      expect(find.byType(PassportIdentityStrip), findsOneWidget);
      // SCOPED to the strip. Unlike the widget tier — which pumps the screen
      // alone — the E2E runs inside ClientShell, whose bottom-nav tile 4 is
      // ALSO labelled «BEAUTY PASSPORT». A page-wide `find.text` therefore
      // matches twice and says nothing about the strip.
      Finder inStrip(Finder f) =>
          find.descendant(of: find.byKey(_kIdentityStrip), matching: f);

      expect(inStrip(find.text(kBeautyPassportTitle)), findsOneWidget);
      expect(inStrip(find.text(kBeautyPassportSubtitle)), findsOneWidget);
      expect(
        inStrip(find.text(l10n.passportReviewsLeft(_wireReviewsWritten))),
        findsOneWidget,
        reason: 'the review count comes off the wire, not a placeholder',
      );
      expect(
        inStrip(find.text(l10n.passportMemberSince('$_wireMemberSinceYear'))),
        findsOneWidget,
        reason:
            'the join year is a WIRE value — a screen re-deriving it from a '
            'clock would print a different year here',
      );

      // ── 2. THE DERIVED BLOCK: BOTH locality lines + the average pill ───────
      expect(find.byKey(_kDerivedBlock), findsOneWidget);
      expect(find.byType(PassportDerivedBlock), findsOneWidget);
      // Districts line AND cities line — scoped to the block because the
      // profile block above renders the client's own city, which may coincide
      // with a derived favourite one.
      for (final String locality in <String>[
        ..._wireDistricts,
        ..._wireCities,
      ]) {
        expect(
          find.descendant(
            of: find.byKey(_kDerivedBlock),
            // i18n-finder-ok: locality names come from the wire fixture above,
            // never AppLocalizations.
            matching: find.text(locality),
          ),
          findsOneWidget,
          reason: 'derived locality «$locality» must render off the wire',
        );
      }
      expect(
        find.text(l10n.passportBudgetAverage(_wireBudgetAvg)),
        findsOneWidget,
        reason:
            'the AVERAGE pill, through the mapper\'s num → double widening '
            'and the screen\'s renderableWholePrice gate',
      );
      expect(
        find.text(l10n.passportBudgetAverage(_wireBudgetMax)),
        findsNothing,
        reason:
            'the page shows the average, never the ceiling — the fixture\'s '
            'max differs from its avg so this cannot pass by coincidence',
      );
      expect(find.text(l10n.passportBudgetUnknown), findsNothing);

      // ── 3. THE WISH LIST: exactly TWO cards + «Показати всі (5)» ───────────
      await _scrollToWishList(tester);

      expect(
        find.byType(WishlistCompactCard),
        findsNWidgets(2),
        reason:
            'the line shows exactly WishlistSection.previewCount cards — it is '
            'a LINE, not a rail',
      );
      // i18n-finder-ok: service and master names come from the wire fixture.
      expect(find.text(_wireFirstServiceName), findsOneWidget);
      expect(find.text(_wireFirstMasterName), findsOneWidget);
      expect(find.text(_wireSecondServiceName), findsOneWidget);
      // The FIXED price is the backend's own string, rendered VERBATIM.
      // i18n-finder-ok: the wire's pre-formatted price, never AppLocalizations.
      expect(find.text(_wireFirstPriceDisplay), findsOneWidget);
      // The RANGE is RE-FORMATTED into the app's en-dash band, so the backend's
      // long form must be nowhere on screen — the one assertion that proves
      // WishlistService.priceLabel ran rather than priceDisplay being drawn.
      expect(
        // i18n-finder-ok: the wire's long-form price string, never AppLocalizations.
        find.text(_wireSecondPriceLongForm),
        findsNothing,
        reason:
            'a RANGE entry must render the app\'s frozen «600–900 ₴» band, not '
            'the backend\'s long form — the long form does not fit the card',
      );
      // i18n-finder-ok: the app-formatted band, asserted as data.
      expect(find.text(_wireSecondPriceBand), findsOneWidget);

      expect(find.byKey(_kWishlistShowAll), findsOneWidget);
      expect(
        find.text(l10n.wishlistShowAll(5)),
        findsOneWidget,
        reason:
            'the overflow control states the FULL saved count, not the two '
            'cards on screen',
      );
      expect(find.text(l10n.wishlistShowAll(2)), findsNothing);

      // ── 4. None of the non-data states may appear ─────────────────────────
      expect(find.byKey(_kPassportError), findsNothing);
      expect(find.byKey(_kWishlistError), findsNothing);
      expect(find.byKey(_kWishlistEmpty), findsNothing);
      expect(
        find.byKey(const Key('passport_find_master_button')),
        findsNothing,
        reason:
            'the empty-passport hero and its CTA were deleted in Phase 238 — '
            'nothing may still render them',
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'a CLIENT with NO history sees the identity strip alone and an empty wish '
    'list — never an error, never a fabricated figure',
    (tester) async {
      // The counterpart. It proves the no-history rendering is EARNED from the
      // wire (empty lists, null budget, zero counts) rather than hardcoded, and
      // it is the case that used to be the ONLY one this flow covered.
      final fb = FakeBackend()..currentRole = UserRole.client;
      final GoRouter router = await AppHarness.boot(tester, fb);

      await _openPassportTab(tester, fb, router);

      expect(fb.getPassportCalls, greaterThanOrEqualTo(1));
      expect(fb.listServiceFavoritesCalls, greaterThanOrEqualTo(1));

      final AppLocalizations l10n = await _uk();

      // The strip STAYS — it is what makes a history-less passport meaningful,
      // and is exactly why Phase 238 could delete the empty hero outright.
      expect(find.byKey(_kIdentityStrip), findsOneWidget);
      // Scoped for the same reason as the flow above: the bottom-nav tile also
      // carries the «BEAUTY PASSPORT» label.
      Finder inStrip(Finder f) =>
          find.descendant(of: find.byKey(_kIdentityStrip), matching: f);

      expect(inStrip(find.text(l10n.passportReviewsLeft(0))), findsOneWidget);
      expect(
        inStrip(find.text(l10n.passportMemberSince('2021'))),
        findsOneWidget,
        reason:
            'the fake backend\'s default body carries a fixed memberSinceYear; '
            'a missing one would make the mapper throw and the section render '
            'its ERROR card instead',
      );

      // Nothing derivable ⇒ the whole block is dropped, not rendered empty.
      expect(
        find.byKey(_kDerivedBlock),
        findsNothing,
        reason:
            'no locality history AND no spend band ⇒ the caller omits the '
            'derived block entirely',
      );
      expect(
        find.byKey(_kPassportError),
        findsNothing,
        reason:
            'a legitimately empty payload is NOT a failure — collapsing the '
            'two is the defect class this page keeps being audited for',
      );

      await _scrollToWishList(tester);

      expect(find.byKey(_kWishlistEmpty), findsOneWidget);
      expect(find.text(l10n.wishlistEmptyMessage), findsOneWidget);
      expect(find.text(l10n.wishlistEmptyCta), findsOneWidget);
      expect(find.byType(WishlistCompactCard), findsNothing);
      expect(find.byKey(_kWishlistShowAll), findsNothing);
      expect(find.byKey(_kWishlistError), findsNothing);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'the WISH LIST empty-state CTA navigates the CLIENT to the search tab',
    (tester) async {
      // RE-POINTED, not deleted. The «Знайти майстра» invitation used to belong
      // to the passport's own empty hero; Phase 238 moved it to the wish list's
      // empty state, and this is the flow that proves the surviving CTA still
      // routes to discovery.
      final fb = FakeBackend()..currentRole = UserRole.client;
      final GoRouter router = await AppHarness.boot(tester, fb);

      await _openPassportTab(tester, fb, router);
      await _scrollToWishList(tester);

      final Finder cta = find.descendant(
        of: find.byKey(_kWishlistEmpty),
        // The empty state's CTA carries no Key of its own (HubEmptyState builds
        // a bare HubFilledButton), so the tap target is scoped by the state's
        // key and located by TYPE — locale-independent, and unambiguous inside
        // that subtree.
        matching: find.byType(HubFilledButton),
      );
      expect(cta, findsOneWidget);
      await tester.ensureVisible(cta);
      await tester.pumpAndSettle();
      await tester.tap(cta);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      AppHarness.expectLocation(router, RouteNames.clientSearch);
      expect(
        find.byType(ClientShell),
        findsOneWidget,
        reason: 'the CTA hop stays inside the client shell (goBranch)',
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  // ══════════════════════════════════════════════════════════════════════
  // SESSION BOUNDARY — the KEYLESS per-user cache (mobile-qa, Step 2.7
  // Rule 3b, 2026-09-18).
  //
  // `passportProvider` is `keepAlive` with a 5-minute TTL and takes NO family
  // key: there is exactly ONE member for every account that ever signs in on
  // the device. Nothing in its chain (`passportRepositoryProvider` →
  // `clientApiProvider` → `dioProvider`) watches anything auth-shaped, so
  // before the fix nothing rebuilt it and nothing evicted it across a logout
  // — client B opened «BEAUTY PASSPORT» and read client A's visit history,
  // budget band and join year.
  //
  // WHY IT IS NOT ENOUGH THAT `passport_session_boundary_test.dart` PINS IT.
  // That test drives `AuthNotifier.logout()` on a hand-built container with a
  // mocked repository. It cannot see the thing that actually has to happen on
  // a device: the REAL «Вийти» row → the REAL confirm dialog → `runLogoutFlow`
  // → the REAL secure-storage wipe → the REAL `/login` redirect → a REAL
  // second login, and only THEN the tab hop that re-reads the provider. The
  // fix under test is a `ref.watch(authProvider.select(authUserIdOrNull))`
  // inside `passport(Ref ref)`, and whether that select actually re-emits
  // depends on the real auth state machine passing through
  // `Unauthenticated` — which is exactly the hop only this tier runs.
  //
  // ANTI-VACUITY. The assertion is not "the page rendered". Both sessions
  // serve a FULL passport, and every asserted value differs between them:
  // session A joined 2019 with 7 reviews, session B joined 2024 with 1. The
  // leak renders a perfectly healthy page carrying the WRONG year, so the
  // absence assertion (A's year is gone) is the load-bearing half and the
  // refetch count is the corroboration, never the proof.
  //
  // NO PATROL FLOW: logout is an in-app dialog and a router redirect. No OS
  // permission prompt, no deep link, no notification, no WebView, no
  // biometric. `integration_test/patrol/` does not apply here either.
  // ══════════════════════════════════════════════════════════════════════
  testWidgets(
    'a SECOND client session on the same device reads its OWN passport, never '
    'the first session\'s cached one',
    (tester) async {
      final fb = FakeBackend()
        ..currentRole = UserRole.client
        ..passportBody = _sessionPassportBody(
          memberSinceYear: _kSessionAYear,
          reviewsWritten: _kSessionAReviews,
        )
        // `wishlistProvider` is the SECOND keyless keepAlive member on this
        // page, and it leaked the same way. Session A owns two favourites;
        // session B owns none, so a stale member renders A's cards to B.
        ..favoriteServiceRows = _favouriteRows()
        // …and `myRatingProvider` is the THIRD, on the CLIENT HOME hub this
        // journey passes through twice. Two ratings that render as two
        // different strings.
        ..myRatingAvgRating = _kSessionARating
        ..myRatingReviewCount = 11;
      final GoRouter router = await AppHarness.boot(tester, fb);
      final AppLocalizations l10n = await _uk();

      Finder inStrip(Finder f) =>
          find.descendant(of: find.byKey(_kIdentityStrip), matching: f);

      // ── SESSION A ──────────────────────────────────────────────────────
      await _openPassportTab(tester, fb, router);
      expect(
        fb.getPassportCalls,
        1,
        reason: 'the first session fetches its passport exactly once',
      );
      expect(
        inStrip(find.text(l10n.passportMemberSince('$_kSessionAYear'))),
        findsOneWidget,
      );
      expect(
        inStrip(find.text(l10n.passportReviewsLeft(_kSessionAReviews))),
        findsOneWidget,
      );
      await _scrollToWishList(tester);
      expect(
        find.byType(WishlistCompactCard),
        findsNWidgets(2),
        reason: 'session A owns two favourites',
      );
      expect(fb.listServiceFavoritesCalls, 1);

      // ── THE REAL LOGOUT ────────────────────────────────────────────────
      // Driven through the shipped UI, not through the notifier: the whole
      // point of this tier is that the eviction happens on the journey the
      // user actually takes.
      await tester.tap(find.byKey(const Key('client-nav-tile-0')));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(
        find.descendant(
          of: find.byType(MyRatingStatCard),
          matching: find.text(_kSessionARating.toStringAsFixed(1)),
        ),
        findsOneWidget,
        reason: 'the home hub pill shows session A\'s own rating',
      );
      await tester.tap(find.byKey(const Key('btn-menu-client')));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      AppHarness.expectLocation(router, RouteNames.clientMenu);

      final Finder logoutRow = find.byKey(const Key('row-logout'));
      expect(logoutRow, findsOneWidget);
      await tester.ensureVisible(logoutRow);
      await tester.pumpAndSettle();
      await tester.tap(logoutRow);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn-logout-confirm')));
      await tester.pumpAndSettle(const Duration(seconds: 3));
      AppHarness.expectLocation(router, RouteNames.login);

      // ── SESSION B, a DIFFERENT passport on the same endpoint ───────────
      fb.passportBody = _sessionPassportBody(
        memberSinceYear: _kSessionBYear,
        reviewsWritten: _kSessionBReviews,
      );
      fb.favoriteServiceRows = <Map<String, dynamic>>[];
      fb.myRatingAvgRating = _kSessionBRating;
      fb.myRatingReviewCount = 3;
      await _openPassportTab(tester, fb, router);

      // THE LOAD-BEARING PAIR. The leaked page renders fine — it just shows
      // the outgoing account's numbers — so "B's year is present" alone is
      // not enough; "A's year is gone" is what a stale member fails.
      expect(
        inStrip(find.text(l10n.passportMemberSince('$_kSessionBYear'))),
        findsOneWidget,
      );
      expect(
        inStrip(find.text(l10n.passportMemberSince('$_kSessionAYear'))),
        findsNothing,
        reason:
            'the outgoing session\'s join year is PII and must not survive '
            'the session boundary in a keyless keepAlive member',
      );
      expect(
        inStrip(find.text(l10n.passportReviewsLeft(_kSessionBReviews))),
        findsOneWidget,
      );
      expect(
        inStrip(find.text(l10n.passportReviewsLeft(_kSessionAReviews))),
        findsNothing,
      );
      expect(
        fb.getPassportCalls,
        2,
        reason:
            'the second session must go back to the wire — a served cache '
            'leaves this at 1, which is the shipped bug',
      );

      // ── AND THE SECOND KEYLESS MEMBER ON THE SAME PAGE ─────────────────
      await _scrollToWishList(tester);
      expect(
        find.byType(WishlistCompactCard),
        findsNothing,
        reason:
            'session B owns no favourites — a leaked wishlistProvider member '
            'renders session A\'s two cards here',
      );
      expect(find.byKey(_kWishlistEmpty), findsOneWidget);
      expect(
        fb.listServiceFavoritesCalls,
        2,
        reason: 'the wish list must go back to the wire for session B too',
      );

      // ── AND THE THIRD, ON THE HOME HUB ─────────────────────────────────
      await tester.tap(find.byKey(const Key('client-nav-tile-0')));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(
        find.descendant(
          of: find.byType(MyRatingStatCard),
          matching: find.text(_kSessionBRating.toStringAsFixed(1)),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(MyRatingStatCard),
          matching: find.text(_kSessionARating.toStringAsFixed(1)),
        ),
        findsNothing,
        reason:
            'the outgoing client\'s own two-sided rating must not survive '
            'into the incoming session\'s home hub',
      );
      expect(
        fb.getMyRatingCalls,
        2,
        reason: 'the rating pill must go back to the wire for session B too',
      );
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
