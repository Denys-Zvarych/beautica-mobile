// Phase 239 follow-up (mobile-qa) — the FAILED un-favourite, end to end.
//
// WHY THIS FILE EXISTS, SEPARATELY FROM wishlist_flow_test.dart
// ---------------------------------------------------------------
// `wishlist_flow_test.dart` proves the SUCCESSFUL remove path — on both
// surfaces, and the last-entry-to-empty race. It never makes
// `DELETE /api/v1/favorites` fail, so `WishlistNotifier.removeService`'s
// revert branch (see that file's doc comment, "## The un-favourite is
// optimistic AND reversible") had unit/widget coverage only, never an E2E
// against the real Dio interceptor chain (`ErrorMapperInterceptor` +
// `FavoriteToggleNotifier.toggle`'s own catch). This file closes that gap,
// using the re-registration hook `FakeBackend.forceRemoveFavoriteFailure`
// (`support/fake_backend.dart:1118`).
//
// SURFACE CHOSEN: the full «Усі збережені» page (`WishlistScreen`), NOT the
// passport's two-card line.
// ---------------------------------------------------------------------------
// The restore claim under test is POSITIONAL — "at its ORIGINAL INDEX", not
// merely "back in the list somewhere". The passport line only ever renders
// `take(2)`, so removing and restoring a middle entry out of 3 could complete
// with the line rendering identically either way (the promoted-then-demoted
// third card would flicker through, but a widget test only samples discrete
// frames). The full-list page renders every entry as an ordered
// `ListView.builder` keyed on `wishlistProvider`'s own list
// (`wishlist_screen.dart:244-267`), so `tester.widgetList<WishlistRow>(...)`
// gives the EXACT order the notifier holds — the one place "restored at
// index 1 of 3" and "restored at index 2 (appended)" cannot look the same.
//
// THREE ENTRIES, MIDDLE ONE REMOVED
// -----------------------------------
// A 1-entry or last-entry fixture cannot distinguish "restored at the right
// position" from "restored anywhere" — clamping/append and correct-index
// restoration produce an identical final list in both those shapes. Removing
// the MIDDLE of three (w2, index 1) is the smallest fixture where the two
// implementations diverge: a wrong "append on failure" would restore the
// order to [w1, w3, w2] instead of [w1, w2, w3].
//
// MID-FLIGHT ASSERTION, THE SAME DISCIPLINE AS wishlist_flow_test.dart's
// LAST-REMOVAL CASE
// ---------------------------------------------------------------------------
// This track already shipped a bug where every END-state assertion passed:
// the empty state was gated on a count that subtracts entries mid-animation,
// so the empty card showed BEFORE the wire call was even sent and retracted
// on failure — invisible to any test that only checks where things land.
// The same discipline applies here: this file asserts the entry is GONE
// optimistically while the DELETE is genuinely in flight (gated open by a
// [Completer]-backed Dio interceptor added from the test side, mirroring
// `master_bookings_flow_test.dart`'s day-scoped skeleton gate), BEFORE
// completing the gate with a failure response and asserting the restore.
//
// A synchronous `thenThrow`-shaped failure would prove nothing here — it
// would collapse the optimistic-removal window to zero, and the mid-flight
// assertions below would never have a chance to observe it. The gate is
// therefore added at the Dio `onRequest` phase (before the fake backend's own
// route handler ever runs), so `removeService`'s optimistic edit is
// observably ahead of the wire call resolving, no wall-clock race involved —
// the gate only opens when this test calls `.complete()`.
//
// `wishlistRemovalDelayProvider` (the exit-animation collapse delay,
// `wishlist_removal.dart`) is overridden to resolve immediately: this file is
// not testing that collapse window (already covered by
// `wishlist_flow_test.dart`'s last-removal case) and a real 260 ms timer here
// would only add wall-clock noise to a test whose actual subject is the wire
// call. The heart's own 110 ms pop (`WishlistHeartButton.popDuration`) is
// NOT overridable and is left to run for real — `pumpAndSettle` under
// `IntegrationTestWidgetsFlutterBinding` (a real clock even headless) drains
// it the same way `wishlist_flow_test.dart`'s surviving-entries case does.
//
// FAILURE SURFACE: `WishlistRemovalHost.requestRemoval`
// (`wishlist_removal.dart:118-126`) calls
// `showErrorSnack(context, failure.userMessage(context))` on any non-null
// [Failure] — the shipped VelvetSnack surface, asserted via
// `expectVelvetSnack` exactly as every other failure flow in this suite does.
// `forceRemoveFavoriteFailure(500)` maps through `ErrorMapperInterceptor`
// (500–599 → `ServerFailure`) to `l10n.errServer` — asserted, not invented.
//
// NO PATROL FLOW NEEDED: no native interaction anywhere in this journey.

import 'dart:async';

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/passport/presentation/passport_screen.dart';
import 'package:beautica_mobile/features/wishlist/presentation/widgets/wishlist_removal.dart'
    show wishlistRemovalDelayProvider;
import 'package:beautica_mobile/features/wishlist/presentation/widgets/wishlist_row.dart';
import 'package:beautica_mobile/features/wishlist/presentation/wishlist_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import '../test/helpers/velvet_snack_matchers.dart';
import 'support/app_harness.dart';

// ---------------------------------------------------------------------------
// Keys
// ---------------------------------------------------------------------------

const Key _kWishlistShowAll = Key('wishlist_show_all_button');

/// The heart on ONE full-width row, keyed by the entry it belongs to.
Key _rowHeart(String id) => Key('wishlist_row_heart_$id');

// ---------------------------------------------------------------------------
// Wire fixtures — THREE entries, so removing the MIDDLE one is distinguishable
// from "restored anywhere" (see file header).
// ---------------------------------------------------------------------------

const String _serviceNameW1 = 'Ламінування та фарбування брів';
const String _serviceNameW2 = 'Манікюр з покриттям гель-лак';
const String _serviceNameW3 = 'Нарощування вій — класика 2D';

Map<String, dynamic> _favouriteRow({
  required String id,
  required String serviceName,
  required String firstName,
  required String lastName,
}) => <String, dynamic>{
  'masterServiceId': id,
  'masterId': 'master-$id',
  'serviceName': serviceName,
  'masterFirstName': firstName,
  'masterLastName': lastName,
  'durationMinutes': 60,
  'priceType': 'FIXED',
  'priceMin': 500,
  'priceDisplay': '500 ₴',
};

List<Map<String, dynamic>> _threeFavouriteRows() => <Map<String, dynamic>>[
  _favouriteRow(
    id: 'w1',
    serviceName: _serviceNameW1,
    firstName: 'Анастасія',
    lastName: 'Мельниченко',
  ),
  _favouriteRow(
    id: 'w2',
    serviceName: _serviceNameW2,
    firstName: 'Ірина',
    lastName: 'Бондаренко',
  ),
  _favouriteRow(
    id: 'w3',
    serviceName: _serviceNameW3,
    firstName: 'Олена',
    lastName: 'Ковальчук',
  ),
];

Future<AppLocalizations> _uk() =>
    AppLocalizations.delegate.load(const Locale('uk'));

// ---------------------------------------------------------------------------
// Journey helper
// ---------------------------------------------------------------------------

/// Logs a CLIENT in, hops to the passport tab, and pushes through to the
/// full-list «Усі збережені» page.
Future<void> _openWishlistPage(
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

  await tester.drag(find.byType(Scrollable).last, const Offset(0, -600));
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(_kWishlistShowAll));
  await tester.pumpAndSettle();
  AppHarness.expectNestedPushLocation(router, RouteNames.clientWishlist);
  expect(find.byType(WishlistScreen), findsOneWidget);
}

/// The ordered list of `favoriteTargetId`s currently rendered as full-width
/// rows — read off the WIDGETS themselves (not text/position math), so this
/// is a direct assertion of `wishlistProvider`'s own list order.
List<String> _rowOrder(WidgetTester tester) => tester
    .widgetList<WishlistRow>(find.byType(WishlistRow))
    .map((WishlistRow w) => w.item.favoriteTargetId)
    .toList();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'a FAILED un-favourite of the MIDDLE entry disappears optimistically '
    'mid-flight, then restores at its ORIGINAL index and tells the user it '
    'failed',
    (tester) async {
      final fb = FakeBackend()
        ..currentRole = UserRole.client
        ..favoriteServiceRows = _threeFavouriteRows();

      // The exit-animation collapse delay is not this test's subject (see
      // file header) — resolve it immediately so the only real wait left is
      // the heart's own 110 ms pop, which `pumpAndSettle` drains for real.
      final GoRouter router = await AppHarness.boot(
        tester,
        fb,
        extraOverrides: <Object>[
          wishlistRemovalDelayProvider.overrideWithValue(
            () => Future<void>.value(),
          ),
        ],
      );

      await _openWishlistPage(tester, fb, router);

      // ── 1. All three present, in wire order. ────────────────────────────
      expect(find.byType(WishlistRow), findsNWidgets(3));
      expect(_rowOrder(tester), <String>['w1', 'w2', 'w3']);
      // i18n-finder-ok: wire fixture value.
      expect(find.text(_serviceNameW2), findsOneWidget);

      // ── Arm the failure AND gate the DELETE open, from the test side ────
      //
      // `forceRemoveFavoriteFailure` re-registers the route so the NEXT
      // `DELETE /api/v1/favorites` the fake backend actually PROCESSES
      // answers 500 instead of 204. The interceptor below is a SEPARATE gate
      // in front of that: it holds the request at the Dio `onRequest` phase —
      // before it ever reaches the fake backend's route handler — so this
      // test can inspect app state at a moment provably BEFORE the wire call
      // has resolved, not merely before some real-clock guess would land.
      fb.forceRemoveFavoriteFailure(500);
      final Completer<void> deleteGate = Completer<void>();
      int deleteDispatchCount = 0;
      fb.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest:
              (
                RequestOptions options,
                RequestInterceptorHandler handler,
              ) async {
                if (options.method == 'DELETE' &&
                    options.path.endsWith('/favorites') &&
                    deleteDispatchCount == 0) {
                  deleteDispatchCount++;
                  await deleteGate.future;
                }
                handler.next(options);
              },
        ),
      );

      // ── 2. Un-heart the MIDDLE entry. ────────────────────────────────────
      final Finder heart = find.byKey(_rowHeart('w2'));
      expect(heart, findsOneWidget);
      await tester.ensureVisible(heart);
      await tester.pumpAndSettle();
      await tester.tap(heart);

      // Drains the heart's real 110 ms pop, the (now-instant) collapse delay,
      // and `removeService`'s optimistic edit — then stalls on the gate,
      // which holds no scheduled frame/animation open, so `pumpAndSettle`
      // returns rather than hanging.
      await tester.pumpAndSettle();

      // ── 3. MID-FLIGHT: gone optimistically, wire call dispatched but NOT
      //        yet answered. ──────────────────────────────────────────────
      expect(
        deleteDispatchCount,
        1,
        reason: 'the DELETE must already be dispatched at this point',
      );
      expect(
        fb.removeFavoriteCalls,
        0,
        reason:
            'the request is held at the Dio layer, BEFORE the fake backend '
            "route handler runs — proves this is genuinely mid-flight, not "
            'merely "before some guessed delay"',
      );
      expect(
        find.byType(WishlistRow),
        findsNWidgets(2),
        reason:
            'removeService already dropped w2 from provider state — optimistic '
            'removal happens BEFORE the wire call, not after it fails',
      );
      // i18n-finder-ok: wire fixture value.
      expect(find.text(_serviceNameW2), findsNothing);
      expect(_rowOrder(tester), <String>['w1', 'w3']);
      expect(
        find.byType(VelvetSnack),
        findsNothing,
        reason:
            'no failure has been reported yet — the DELETE has not answered',
      );

      // ── 4. Release the gate with the FAILURE response. ──────────────────
      deleteGate.complete();
      await tester.pump();
      await pumpVelvetSnackIn(tester);

      // The wire call reached the fake backend exactly once, and it was the
      // MIDDLE entry that was requested — not a different id.
      expect(fb.removeFavoriteCalls, 1);
      expect(fb.lastRemoveFavoriteQuery?['targetType'], 'SERVICE');
      expect(fb.lastRemoveFavoriteQuery?['targetId'], 'w2');

      // ── 5. RESTORED AT ITS ORIGINAL INDEX — not appended. ───────────────
      //
      // The load-bearing assertion: an "append on failure" bug would restore
      // the order to [w1, w3, w2], which findsNWidgets/text-presence checks
      // alone cannot tell apart from the correct [w1, w2, w3].
      expect(find.byType(WishlistRow), findsNWidgets(3));
      expect(
        _rowOrder(tester),
        <String>['w1', 'w2', 'w3'],
        reason:
            'w2 must be restored at index 1 — its ORIGINAL position — not '
            'appended to the end of the list',
      );
      // i18n-finder-ok: wire fixture value.
      expect(find.text(_serviceNameW2), findsOneWidget);

      // ── 6. The user is told it failed. ──────────────────────────────────
      final AppLocalizations l10n = await _uk();
      expectVelvetSnack(l10n.errServer, variant: VelvetSnackVariant.error);

      await pumpPastVelvetSnack(tester);
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
