// Phase 111 — E2E: «Улюблені», the CLIENT shell's second tab.
//
// WHY THIS FILE EXISTS, SEPARATELY FROM THE WIDGET TIER
// -----------------------------------------------------
// `test/features/favorites/` now covers the mapper, the notifier and the screen
// in isolation. Three contracts survive none of that isolation, because each
// one only exists where the REAL wire, the REAL router and the REAL shell meet:
//
//   1. THE WIRE→CARD PATH. Every widget test hands the screen an already-mapped
//      `FavoriteItem`. Nothing above the mapper proves that a hostile
//      `locationNote` arriving as JSON reaches a rendered `Text` STRIPPED, or
//      that a row whose `masterId` is blank is dropped before it can build a
//      card that navigates to go_router's "page not found". Both are pinned
//      here against bodies the fake backend actually serves.
//
//   2. THE DELETE, END TO END. The widget tier asserts a fake repository
//      recorded a call. This asserts the `DELETE /api/v1/favorites` request
//      genuinely went out with `targetType=MASTER` and the right `targetId`,
//      that it fired only AFTER the 5-second undo window closed, and that a
//      following refetch no longer returns the row — the half a client would
//      actually notice, and the half a fake repository cannot express.
//
//   3. THE BRANCH WIRING. `_openSearch` calls
//      `StatefulNavigationShell.of(context).goBranch(kClientSearchBranch)`,
//      which exists ONLY inside the real client shell. The empty state's CTA is
//      therefore untappable at the widget tier; here it is the last step of the
//      journey.
//
// CLOCK: nothing here is derived from `DateTime.now()`, and nothing on this
// screen renders a date. The fixtures are pure wire values, so the fake
// backend's payload and the app's pinned `kFixedNow` cannot disagree (M15).
//
// NO PATROL FLOW NEEDED: no native interaction anywhere in this journey — no OS
// dialog, deep link, FCM, WebView or biometric. In-app navigation, Riverpod
// state and HTTP only, so the standard integration_test tier is the right one.
//
// KEY POLICY (from AppHarness): all TAPS are key-based. The only `find.text`
// assertions are on WIRE values, and those values are deliberately Latin, so
// no `// i18n-finder-ok:` escape is needed anywhere in this file.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/favorites/presentation/widgets/favorite_cards.dart';
import 'package:beautica_mobile/features/favorites/presentation/widgets/favorites_filter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import 'support/app_harness.dart';

// ---------------------------------------------------------------------------
// Keys
// ---------------------------------------------------------------------------

const Key _kFavoritesBranch = Key('client-branch-favorites');
const Key _kNavTileFavorites = Key('client-nav-tile-1');
const Key _kEmptyState = Key('favorites-empty-state');
const Key _kFindMasterCta = Key('favorites-find-master-button');
const Key _kUndoButton = Key('favorites-undo-button');

Key _masterCard(String id) => Key('favorites-master-$id');
Key _salonCard(String id) => Key('favorites-salon-$id');
Key _dent(String id) => Key('favorites-dent-$id');

// ---------------------------------------------------------------------------
// Wire fixtures
// ---------------------------------------------------------------------------
//
// These are BACKEND DATA, not AppLocalizations copy, so they stay identical
// when EN ships.

/// The id the fake backend serves a full public master profile for, so tapping
/// this row resolves a REAL screen rather than an error body.
const String _kMasterId = 'master-aaa';
const String _kMasterFirst = 'Marta';
const String _kMasterLast = 'Honchar';
const String _kMasterName = '$_kMasterFirst $_kMasterLast';

const String _kSalonId = 'salon-xyz';
const String _kSalonName = 'Crystal Room';

/// An arrival note carrying a U+202E RIGHT-TO-LEFT OVERRIDE.
///
/// Written as an ESCAPE, never as a literal character, so this file does not
/// itself embed the control it is testing against. The backend validates
/// `locationNote` with `@Size(max = 1000)` and no character class at all, so
/// this is a payload a hostile provider can genuinely store — and
/// `ResultAddressBlock` renders the note with a bare `Text(note)`, which is why
/// `FavoriteMapper` has to strip it.
const String _kHostileNote = 'entrance \u202Efrom the yard';

/// What must actually reach the screen.
const String _kCleanNote = 'entrance from the yard';

// ---------------------------------------------------------------------------
// D2/D3/D4 field-test fixtures (mobile-qa, Phase 111 fix)
// ---------------------------------------------------------------------------
//
// The `setUp` rows above never set `salonId`/`salonName`/`categoryCode`/
// `categoryLabel`, so Tests 1-6 cannot exercise any of the three newly-live
// paths this fix ships. These constants/rows are for the tests below only.

const String _kAffiliatedMasterId = 'master-affiliated';
const String _kAffiliatedMasterName = 'Iryna Podolska';
const String _kEmployingSalonName = 'Crystal Room Spa';
const String _kAffiliatedStreet = 'Sichovykh Striltsiv';
const String _kAffiliatedBuildingNo = '9';

const String _kIndependentMasterId = 'master-independent';
const String _kIndependentMasterName = 'Oksana Bilyk';
const String _kIndependentStreet = 'Velyka Vasylkivska';
const String _kIndependentBuildingNo = '3';

const String _kCategoryNailsId = 'c1';
const String _kCategoryNailsLabel = 'Nails';
const String _kCategoryBrowsId = 'c2';
const String _kCategoryBrowsLabel = 'Brows';

/// A THIRD category, carried by a SALON row rather than a master row —
/// Test 8's own arm, closing the QA finding that no salon row's
/// `categoryCode`/`categoryLabel` ever travelled wire→mapper→`FavoriteChoice`
/// →chip→filter end to end (only the mapper-level arm existed before).
const String _kCategorySalonId = 'c3';
const String _kCategorySalonLabel = 'Spa';

/// A name long enough to force a two-line wrap at a 360dp phone width. Latin,
/// matching this file's no-`i18n-finder-ok` convention.
const String _kLongMasterName = 'Solomiya Constantinovska Zabrodska Marchenko';

Map<String, dynamic> _masterRow({
  required String masterId,
  String? firstName = _kMasterFirst,
  String? lastName = _kMasterLast,
  double? avgRating,
  String? locationNote,
  // D2/D3/D4 (field-test fix, Phase 111) — additive: every existing caller
  // that omits these keeps building the exact same JSON body it always did.
  String? salonId,
  String? salonName,
  String? street = 'Khreshchatyk',
  String? buildingNo = '22',
  String? categoryCode,
  String? categoryLabel,
}) => <String, dynamic>{
  'masterId': masterId,
  'firstName': firstName,
  'lastName': lastName,
  'avatarUrl': null,
  'cityLabel': 'Kyiv',
  'districtLabel': null,
  'avgRating': avgRating,
  'street': street,
  'buildingNo': buildingNo,
  'locationNote': locationNote,
  'salonId': salonId,
  'salonName': salonName,
  'categoryCode': categoryCode,
  'categoryLabel': categoryLabel,
};

Map<String, dynamic> _salonRow({String? categoryCode, String? categoryLabel}) =>
    <String, dynamic>{
      'salonId': _kSalonId,
      'name': _kSalonName,
      'avatarUrl': null,
      'cityLabel': 'Kyiv',
      'districtLabel': null,
      'avgRating': 4.8,
      'street': 'Sichovykh Striltsiv',
      'buildingNo': '9',
      'locationNote': null,
      'categoryCode': categoryCode,
      'categoryLabel': categoryLabel,
    };

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late FakeBackend fakeBackend;

  setUp(() {
    fakeBackend = FakeBackend()
      ..favoriteMasterRows = <Map<String, dynamic>>[
        _masterRow(
          masterId: _kMasterId,
          avgRating: 4.7,
          locationNote: _kHostileNote,
        ),
        // THE GHOST ROW. A blank `masterId` is a projection the client cannot
        // repair; the mapper DROPS it rather than repeating `booking_mapper`'s
        // `?? ''`, which succeeds into a card that navigates to
        // `/masters/` — go_router's "page not found".
        _masterRow(masterId: '   ', firstName: 'Ghost', lastName: 'Row'),
      ]
      ..favoriteSalonRows = <Map<String, dynamic>>[_salonRow()];
  });

  tearDown(AppHarness.tearDownHarness);

  /// Logs in as a CLIENT and lands on the «Улюблені» branch.
  Future<GoRouter> openFavorites(WidgetTester tester) async {
    final GoRouter router = await AppHarness.boot(tester, fakeBackend);
    await AppHarness.loginAs(tester, fakeBackend, UserRole.client);

    await AppHarness.tapVisible(tester, find.byKey(_kNavTileFavorites));
    await AppHarness.settle(tester);
    await AppHarness.pumpUntilFound(tester, find.byKey(_kFavoritesBranch));
    return router;
  }

  testWidgets('Test 1 — the wire reaches the cards SANITIZED, and a blank-id '
      'row never becomes a card', (WidgetTester tester) async {
    await openFavorites(tester);

    // Both endpoints were hit — the merged load is two real requests.
    expect(fakeBackend.listMasterFavoritesCalls, greaterThanOrEqualTo(1));
    expect(fakeBackend.listSalonFavoritesCalls, greaterThanOrEqualTo(1));

    // The two GOOD rows rendered, masters before salons.
    await AppHarness.pumpUntilFound(
      tester,
      find.byKey(_masterCard(_kMasterId)),
    );
    expect(find.byKey(_salonCard(_kSalonId)), findsOneWidget);
    expect(find.text(_kMasterName), findsOneWidget);
    expect(find.text(_kSalonName), findsOneWidget);

    // THE SANITIZATION PIN, end to end. The note arrived over the wire with a
    // bidi override in it and must be rendered without one.
    expect(find.text(_kCleanNote), findsOneWidget);
    expect(
      find.text(_kHostileNote),
      findsNothing,
      reason:
          'the raw note reached a Text widget — FavoriteMapper stopped '
          'sanitizing locationNote',
    );

    // THE DROP PIN. Exactly two cards, and none of them is the ghost.
    expect(find.byType(FavoriteMasterCard), findsOneWidget);
    expect(find.byType(FavoriteSalonCard), findsOneWidget);
    expect(find.text('Ghost Row'), findsNothing);
  });

  testWidgets('Test 2 — unlike opens a finite undo window; «Повернути» sends '
      'NOTHING', (WidgetTester tester) async {
    await openFavorites(tester);
    await AppHarness.pumpUntilFound(
      tester,
      find.byKey(_masterCard(_kMasterId)),
    );

    await AppHarness.tapVisible(
      tester,
      find.descendant(
        of: find.byKey(_masterCard(_kMasterId)),
        matching: find.byType(UnlikeHeart),
      ),
    );
    await AppHarness.pumpUntilFound(tester, find.byKey(_dent(_kMasterId)));

    // The slot is HELD — the neighbouring row did not move up, and nothing has
    // been sent yet. This assertion is only meaningful DURING the window, which
    // is exactly why it is taken here and not at the end state.
    expect(find.byKey(_salonCard(_kSalonId)), findsOneWidget);
    expect(
      fakeBackend.removeFavoriteCalls,
      0,
      reason:
          'the DELETE fired at the TAP instead of at the collapse — the '
          'undo window cannot undo anything the server already did',
    );

    // A BARE `tester.tap`, not `AppHarness.tapVisible`. That helper settles
    // BEFORE tapping, and on this screen settling means pumping until no frame
    // is scheduled — which the dent's 5 s draining hairline guarantees will not
    // happen until the window has already closed and taken the undo button with
    // it. The button is already on screen and hit-testable (the
    // `pumpUntilFound` above proved it), so there is nothing to wait for.
    expect(find.byKey(_kUndoButton), findsOneWidget);
    await tester.tap(find.byKey(_kUndoButton));
    await AppHarness.settle(tester);

    expect(find.byKey(_masterCard(_kMasterId)), findsOneWidget);
    expect(find.byKey(_dent(_kMasterId)), findsNothing);
    expect(fakeBackend.removeFavoriteCalls, 0);
  });

  testWidgets('Test 3 — letting the window expire sends ONE DELETE and the '
      'row is gone on the next refetch', (WidgetTester tester) async {
    await openFavorites(tester);
    await AppHarness.pumpUntilFound(
      tester,
      find.byKey(_masterCard(_kMasterId)),
    );

    await AppHarness.tapVisible(
      tester,
      find.descendant(
        of: find.byKey(_masterCard(_kMasterId)),
        matching: find.byType(UnlikeHeart),
      ),
    );
    await AppHarness.pumpUntilFound(tester, find.byKey(_dent(_kMasterId)));

    // Wait out the real 5 s window + the 280 ms collapse by POLLING for the
    // effect, never by sleeping a guessed duration.
    await AppHarness.pumpUntilCondition(
      tester,
      () => fakeBackend.removeFavoriteCalls == 1,
      description: 'the undo window to close and commit the DELETE',
      timeout: const Duration(seconds: 20),
    );

    // The request the backend actually received.
    expect(fakeBackend.lastRemoveFavoriteQuery?['targetType'], 'MASTER');
    expect(fakeBackend.lastRemoveFavoriteQuery?['targetId'], _kMasterId);
    expect(
      fakeBackend.addFavoriteCalls,
      0,
      reason:
          'an ADD went out for the favourite the client asked to REMOVE — '
          'the toggle notifier was not primed to true',
    );

    await AppHarness.pumpUntilGone(tester, find.byKey(_masterCard(_kMasterId)));
    expect(find.byKey(_salonCard(_kSalonId)), findsOneWidget);

    // And a pull-to-refresh REFETCHES and still does not bring it back. This is
    // the assertion no fake repository can make: the removal persisted.
    final int mastersBefore = fakeBackend.listMasterFavoritesCalls;
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, 320),
      touchSlopY: 0,
    );
    await AppHarness.settle(tester);
    await AppHarness.pumpUntilCondition(
      tester,
      () => fakeBackend.listMasterFavoritesCalls > mastersBefore,
      description: 'pull-to-refresh to re-issue GET /favorites/masters',
    );

    expect(find.byKey(_masterCard(_kMasterId)), findsNothing);
    expect(find.byKey(_salonCard(_kSalonId)), findsOneWidget);
  });

  testWidgets('Test 4 — tapping a card opens the PUBLIC master profile, and '
      'coming back keeps the list', (WidgetTester tester) async {
    final GoRouter router = await openFavorites(tester);
    await AppHarness.pumpUntilFound(
      tester,
      find.byKey(_masterCard(_kMasterId)),
    );

    await AppHarness.tapVisible(tester, find.byKey(_masterCard(_kMasterId)));
    await AppHarness.settle(tester);

    // A pushed leaf COLLAPSES to its parent path in `currentConfiguration.uri`,
    // so the ordinary resolver would report the branch root and pass whether or
    // not the profile ever mounted (see `wishlist_flow_test.dart`'s header).
    AppHarness.expectNestedPushLocation(router, '/masters/$_kMasterId');
    expect(
      fakeBackend.getPublicMasterCalls,
      greaterThanOrEqualTo(1),
      reason:
          'the profile route mounted without fetching the master — the '
          'push resolved to the wrong page',
    );

    // PLATFORM back, not `tester.pageBack()`: the public profile draws its own
    // VelvetTouch back disc, not a `CupertinoNavigationBarBackButton`, so
    // `pageBack` finds nothing. This is the gesture an Android client actually
    // makes, and it is the same idiom `client_shell_flow_test.dart` uses.
    final bool handled = await tester.binding.handlePopRoute();
    expect(handled, isTrue);
    await AppHarness.settle(tester);

    expect(find.byKey(_kFavoritesBranch), findsOneWidget);
    expect(find.byKey(_masterCard(_kMasterId)), findsOneWidget);
  });

  testWidgets('Test 5 — an empty list offers the search CTA, and it hops the '
      'shell to «Пошук»', (WidgetTester tester) async {
    fakeBackend
      ..favoriteMasterRows = <Map<String, dynamic>>[]
      ..favoriteSalonRows = <Map<String, dynamic>>[];

    final GoRouter router = await openFavorites(tester);
    await AppHarness.pumpUntilFound(tester, find.byKey(_kEmptyState));

    // The nothing-saved state, NOT the clear-the-filter one: no filter is set,
    // so "clear the filter" would be a direction with nothing behind it.
    expect(
      find.byKey(const Key('favorites-category-empty-state')),
      findsNothing,
    );
    expect(find.byType(FavoriteMasterCard), findsNothing);

    await AppHarness.tapVisible(tester, find.byKey(_kFindMasterCta));
    await AppHarness.settle(tester);

    // `goBranch(kClientSearchBranch)` — the one call in this screen that only
    // works inside the real shell, and therefore the one thing the widget tier
    // structurally cannot exercise.
    AppHarness.expectShellLocation(router, '/search');
    expect(find.byKey(_kFavoritesBranch), findsNothing);
  });

  testWidgets('Test 6 — a failing feed surfaces the error state, and retry '
      'recovers it', (WidgetTester tester) async {
    // The state a real client hits on a flaky connection, and the one an
    // "everything renders" flow never reaches. Boot with retry DISABLED so the
    // failure surfaces on the first attempt instead of after Riverpod's
    // backoff curve — this changes nothing about the app's behaviour, only how
    // long the harness waits before observing it.
    fakeBackend.forceListMasterFavoritesFailure(500);

    final GoRouter router = await AppHarness.boot(
      tester,
      fakeBackend,
      retry: (_, _) => null,
    );
    await AppHarness.loginAs(tester, fakeBackend, UserRole.client);
    await AppHarness.tapVisible(tester, find.byKey(_kNavTileFavorites));
    await AppHarness.settle(tester);

    await AppHarness.pumpUntilFound(
      tester,
      find.byKey(const Key('favorites-error')),
    );
    expect(find.byType(FavoriteSalonCard), findsNothing);

    fakeBackend.forceListMasterFavoritesFailure(null);
    await AppHarness.tapVisible(
      tester,
      find.byKey(const Key('error_state_retry_button')),
    );
    await AppHarness.settle(tester);

    await AppHarness.pumpUntilFound(
      tester,
      find.byKey(_masterCard(_kMasterId)),
    );
    expect(find.byKey(const Key('favorites-error')), findsNothing);
    expect(router, isNotNull);
  });

  testWidgets('Test 7 — a salon-affiliated master renders its affiliation '
      'line AND the employing salon\'s address; an INDEPENDENT master '
      'renders its own address and NO affiliation line', (
    WidgetTester tester,
  ) async {
    // D2 (mapper now maps salonName) + D3 (no client-side address
    // suppression for an affiliated master) end to end, against a body the
    // fake backend actually serves — not an already-mapped FavoriteItem.
    fakeBackend
      ..favoriteMasterRows = <Map<String, dynamic>>[
        _masterRow(
          masterId: _kAffiliatedMasterId,
          firstName: 'Iryna',
          lastName: 'Podolska',
          avgRating: 4.5,
          salonId: 'salon-crystal',
          salonName: _kEmployingSalonName,
          street: _kAffiliatedStreet,
          buildingNo: _kAffiliatedBuildingNo,
        ),
        _masterRow(
          masterId: _kIndependentMasterId,
          firstName: 'Oksana',
          lastName: 'Bilyk',
          avgRating: 4.2,
          street: _kIndependentStreet,
          buildingNo: _kIndependentBuildingNo,
        ),
      ]
      ..favoriteSalonRows = <Map<String, dynamic>>[];

    await openFavorites(tester);
    await AppHarness.pumpUntilFound(
      tester,
      find.byKey(_masterCard(_kAffiliatedMasterId)),
    );
    expect(find.byKey(_masterCard(_kIndependentMasterId)), findsOneWidget);

    // The affiliated card: name, affiliation line (salon name) AND the
    // salon's own street both render.
    expect(find.text(_kAffiliatedMasterName), findsOneWidget);
    expect(find.text(_kEmployingSalonName), findsOneWidget);
    expect(
      find.text('$_kAffiliatedStreet, $_kAffiliatedBuildingNo'),
      findsOneWidget,
    );

    // The independent card: its own street, but the OTHER master's salon
    // name never leaks onto it.
    expect(find.text(_kIndependentMasterName), findsOneWidget);
    expect(
      find.text('$_kIndependentStreet, $_kIndependentBuildingNo'),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(_masterCard(_kIndependentMasterId)),
        matching: find.text(_kEmployingSalonName),
      ),
      findsNothing,
      reason:
          'an independent master must not draw an affiliation line at all — '
          'D3 removed address suppression, not the affiliation-line gate',
    );
  });

  testWidgets('Test 8 — the category filter renders chips derived from the '
      'wire data (masters AND salons); selecting one filters the list, and '
      '«Скинути» clears it in one tap', (WidgetTester tester) async {
    // D4: categoryCode/categoryLabel now survive the mapper, so
    // `FavoritesInlineFilter` must render real chips instead of
    // `SizedBox.shrink()`. A SALON row carries its own category
    // (`_kCategorySalonId`/`_kCategorySalonLabel`) so the full wire→mapper→
    // `FavoriteChoice`→chip→filter path is exercised on the salon arm too,
    // not only through master rows — see the file header on why the
    // mapper-level salon test alone was a two-hop inference.
    fakeBackend
      ..favoriteMasterRows = <Map<String, dynamic>>[
        _masterRow(
          masterId: _kMasterId,
          categoryCode: _kCategoryNailsId,
          categoryLabel: _kCategoryNailsLabel,
        ),
        _masterRow(
          masterId: _kIndependentMasterId,
          firstName: 'Oksana',
          lastName: 'Bilyk',
          categoryCode: _kCategoryBrowsId,
          categoryLabel: _kCategoryBrowsLabel,
        ),
      ]
      ..favoriteSalonRows = <Map<String, dynamic>>[
        _salonRow(
          categoryCode: _kCategorySalonId,
          categoryLabel: _kCategorySalonLabel,
        ),
      ];

    await openFavorites(tester);
    await AppHarness.pumpUntilFound(
      tester,
      find.byKey(_masterCard(_kMasterId)),
    );
    expect(find.byKey(_masterCard(_kIndependentMasterId)), findsOneWidget);
    expect(find.byKey(_salonCard(_kSalonId)), findsOneWidget);

    final Finder pill = find.byKey(const Key('favorites-filter-pill'));
    expect(
      pill,
      findsOneWidget,
      reason:
          'three categorised rows exist over the wire — the pill must '
          'no longer render as SizedBox.shrink()',
    );

    await AppHarness.tapVisible(tester, pill);
    await AppHarness.settle(tester);
    // «Всі» + nails + brows + the SALON's own category.
    expect(find.byType(FavoriteCategoryChip), findsNWidgets(4));
    expect(
      find.byKey(const Key('favorites-chip-$_kCategorySalonId')),
      findsOneWidget,
      reason:
          "the salon row's own categoryCode/categoryLabel must reach the "
          'filter as its own chip, not only the two master categories',
    );

    await AppHarness.tapVisible(
      tester,
      find.byKey(const Key('favorites-chip-$_kCategoryNailsId')),
    );
    await AppHarness.settle(tester);

    expect(find.byKey(_masterCard(_kMasterId)), findsOneWidget);
    expect(find.byKey(_masterCard(_kIndependentMasterId)), findsNothing);
    expect(
      find.byKey(_salonCard(_kSalonId)),
      findsNothing,
      reason:
          'the salon carries a DIFFERENT category — nails must filter it '
          'out exactly like the brows master',
    );

    await AppHarness.tapVisible(
      tester,
      find.byKey(const Key('favorites-filter-reset')),
    );
    await AppHarness.settle(tester);

    expect(find.byKey(_masterCard(_kMasterId)), findsOneWidget);
    expect(find.byKey(_masterCard(_kIndependentMasterId)), findsOneWidget);
    expect(find.byKey(_salonCard(_kSalonId)), findsOneWidget);

    // Now select the SALON's own chip: the salon row must stay visible while
    // BOTH master rows — one on a different category, one on no category
    // match at all — filter out. This is the assertion the mapper-level test
    // cannot make: it proves the category travelled the full path, not just
    // that `FavoriteMapper` populated the field.
    await AppHarness.tapVisible(tester, pill);
    await AppHarness.settle(tester);
    await AppHarness.tapVisible(
      tester,
      find.byKey(const Key('favorites-chip-$_kCategorySalonId')),
    );
    await AppHarness.settle(tester);

    expect(find.byKey(_salonCard(_kSalonId)), findsOneWidget);
    expect(find.byKey(_masterCard(_kMasterId)), findsNothing);
    expect(find.byKey(_masterCard(_kIndependentMasterId)), findsNothing);
  });

  testWidgets('Test 9 — a long provider name wraps to a SECOND line at a '
      '360dp phone width, and the rating readout stays pinned to the FIRST '
      'line rather than drifting to the taller row\'s centre', (
    WidgetTester tester,
  ) async {
    // D1, end to end at a REAL narrow-phone surface — not a widget pumped in
    // isolation at a hand-picked column width.
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final List<String> nameParts = _kLongMasterName.split(' ');
    fakeBackend
      ..favoriteMasterRows = <Map<String, dynamic>>[
        _masterRow(
          masterId: _kMasterId,
          firstName: nameParts.first,
          lastName: nameParts.skip(1).join(' '),
          avgRating: 4.7,
        ),
      ]
      ..favoriteSalonRows = <Map<String, dynamic>>[];

    await openFavorites(tester);
    await AppHarness.pumpUntilFound(
      tester,
      find.byKey(_masterCard(_kMasterId)),
    );

    final Finder nameFinder = find.text(_kLongMasterName);
    expect(nameFinder, findsOneWidget);

    final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
      nameFinder,
    );
    final TextPainter painter = TextPainter(
      text: paragraph.text,
      textAlign: paragraph.textAlign,
      textDirection: paragraph.textDirection,
      textScaler: paragraph.textScaler,
      maxLines: paragraph.maxLines,
    )..layout(maxWidth: paragraph.constraints.maxWidth);
    final int lines = painter.computeLineMetrics().length;
    painter.dispose();
    expect(
      lines,
      2,
      reason:
          'a static maxLines:2 does not prove the layout actually used a '
          'second line at this real device width',
    );

    final double nameTop = tester.getTopLeft(nameFinder).dy;
    final double ratingTop = tester.getTopLeft(find.byType(RatingReadout)).dy;
    expect(
      ratingTop,
      closeTo(nameTop, 1.0),
      reason:
          'the rating readout drifted off the first line\'s top — the '
          'identity row is no longer top-aligned against the real app tree',
    );
  });
}
