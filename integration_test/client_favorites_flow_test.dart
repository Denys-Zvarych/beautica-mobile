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
import 'package:flutter/material.dart';
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

Map<String, dynamic> _masterRow({
  required String masterId,
  String? firstName = _kMasterFirst,
  String? lastName = _kMasterLast,
  double? avgRating,
  String? locationNote,
}) => <String, dynamic>{
  'masterId': masterId,
  'firstName': firstName,
  'lastName': lastName,
  'avatarUrl': null,
  'cityLabel': 'Kyiv',
  'districtLabel': null,
  'avgRating': avgRating,
  'street': 'Khreshchatyk',
  'buildingNo': '22',
  'locationNote': locationNote,
};

Map<String, dynamic> _salonRow() => <String, dynamic>{
  'salonId': _kSalonId,
  'name': _kSalonName,
  'avatarUrl': null,
  'cityLabel': 'Kyiv',
  'districtLabel': null,
  'avgRating': 4.8,
  'street': 'Sichovykh Striltsiv',
  'buildingNo': '9',
  'locationNote': null,
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
}
