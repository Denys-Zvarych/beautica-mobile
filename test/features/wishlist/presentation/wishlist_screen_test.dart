// Phase 239 — [WishlistScreen], the «Усі збережені» overflow page.
//
// THE FOUR STATES, AND WHY THE ERROR ONE IS NOT OPTIONAL HERE
// ---------------------------------------------------------------------------
// `wishlist_states.dart`'s own header records the defect this file exists to
// stop recurring: a 401 was pixel-identical to "nothing saved yet", and the
// always-empty passport bug hid behind that for a whole phase. So EMPTY and
// ERROR are pinned separately and against each other — each asserts the other
// state's card is absent, which is the only shape that can fail when the two
// are collapsed back into one.
//
// ## THREE RIVERPOD TRAPS THIS FILE IS BUILT AROUND
//
// 1. `ref.invalidate` on this provider is BANNED from the removal path.
//    Riverpod 3 pauses covered consumers, and this page COVERS the passport
//    page; invalidating an autoDispose provider whose only remaining listeners
//    are paused DISPOSES it and defers the refetch to resume, so the removal
//    would appear to do nothing until the user navigated back.
//    `removeService` mutates state in place instead — and
//    `FakeWishlistRepository.getCallCount` is what turns that from a comment
//    into an assertion.
// 2. `AsyncLoading(retrying: true)` satisfies `hasError`, so the screen must
//    branch `isLoading → hasError → value`. The error fixture is therefore a
//    NON-TRANSIENT `ServerFailure`: `beauticaProviderRetry` (which
//    `pumpApp` installs, exactly as production does) retries a
//    `NetworkFailure`, which would park the provider mid-retry — reporting
//    `hasError` while still `isLoading`, i.e. the trap itself.
// 3. `FakeWishlistRepository` throws ASYNCHRONOUSLY on purpose. A synchronous
//    throw during build short-circuits the retry machinery entirely and
//    exercises a shape the real transport cannot produce.
//
// ## REMOVAL IS ANIMATED, SO EVERY REMOVAL TEST PUMPS PAST TWO TIMERS
//
// `WishlistHeartButton` fires its callback only after its pop
// (`popDuration`, 110 ms), and `WishlistRemovalHost.requestRemoval` then waits
// `WishlistRemovable.duration` (260 ms) BEFORE telling the notifier. A bare
// `pump()` reads the state before either has run. `pumpAndSettle` covers both.
//
// Layer: Widget. Navigation out of this page (`context.push` from the passport
// section, `context.pop` from the back button) is pinned at the router tier in
// `test/routing/wishlist_route_test.dart` — a widget test has no router.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/favorites/data/favorite_repository_provider.dart';
import 'package:beautica_mobile/features/favorites/domain/favorite_target.dart';
import 'package:beautica_mobile/features/wishlist/application/wishlist_notifier.dart';
import 'package:beautica_mobile/features/wishlist/domain/wishlist_service.dart';
import 'package:beautica_mobile/features/wishlist/presentation/widgets/wishlist_count_pill.dart';
import 'package:beautica_mobile/features/wishlist/presentation/widgets/wishlist_row.dart';
import 'package:beautica_mobile/features/wishlist/presentation/wishlist_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fakes/fake_favorite_repository.dart';
import '../../../helpers/fakes/fake_wishlist_repository.dart';
import '../../../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const User _client = User(
  id: 'u1',
  email: 'client@example.com',
  role: UserRole.client,
  firstName: 'Test',
  lastName: 'Client',
);

/// Settles `authProvider` immediately — `favoriteToggleProvider` watches it, so
/// a loading→data transition mid-test would re-run its build and wipe the map
/// the removal depends on.
class _StubAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async =>
      const AuthSession.authenticated(user: _client, accessToken: 'token');
}

/// Five distinct entries — enough that «renders every favourite» cannot pass on
/// a page that silently renders `take(2)` like the passport section does.
List<WishlistService> _five() => <WishlistService>[
  _svc('a', 'Манікюр комбінований', 90, min: 600, max: 900),
  _svc('b', 'Нарощування вій — класика 2D', 120),
  _svc('c', 'Ламінування брів', 45, min: 450, max: 700),
  _svc('d', 'Педикюр апаратний', 75),
  _svc('e', 'Стрижка та укладка', 60, min: 800, max: 1400),
];

WishlistService _svc(
  String id,
  String name,
  int minutes, {
  double? min,
  double? max,
}) => WishlistService(
  masterServiceId: id,
  masterId: 'm-$id',
  serviceName: name,
  masterName: 'Олена Ковальчук',
  durationMinutes: minutes,
  // A RANGE row carries the long backend form on the wire; a FIXED one carries
  // the single figure. Both shapes are present so the page is exercised against
  // the real mix rather than one synthetic price type.
  priceDisplay: min == null
      ? '800 ₴'
      : 'від ${min.toInt()} до ${max!.toInt()} ₴',
  isRangePrice: min != null,
  priceMin: min,
  priceMax: max,
);

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

class _Harness {
  _Harness({List<WishlistService>? services, Failure? failure, Duration? delay})
    : wishlist = FakeWishlistRepository(
        services: services ?? <WishlistService>[],
        failure: failure,
        delay: delay ?? Duration.zero,
      );

  final FakeWishlistRepository wishlist;
  final FakeFavoriteRepository favorites = FakeFavoriteRepository();

  List<Object> get overrides => <Object>[
    wishlistRepositoryProvider.overrideWithValue(wishlist),
    favoriteRepositoryProvider.overrideWithValue(favorites),
    authProvider.overrideWith(_StubAuthNotifier.new),
  ];

  Future<void> pump(WidgetTester tester, {double width = 360}) async {
    await tester.pumpApp(
      const WishlistScreen(),
      overrides: overrides,
      width: width,
    );
    await tester.pumpAndSettle();
  }
}

Finder _row(String id) => find.byKey(Key('wishlist_row_heart_$id'));

/// Pumps single frames until [condition] holds, then settles.
///
/// PUMP-UNTIL-CONDITION, not a guessed sleep. The removal sequence is gated by
/// two timers that schedule NO frames of their own — the heart's 110 ms pop and
/// `WishlistRemovalHost`'s 260 ms wait — so `pumpAndSettle` alone can return
/// with both still pending (it stops as soon as nothing is animating). Waiting
/// on the OBSERVABLE effect instead is deterministic and stops the moment the
/// real work lands.
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxFrames = 120,
}) async {
  for (int i = 0; i < maxFrames && !condition(); i++) {
    // A single-frame advance inside a pump-until-condition loop.
    // fixed-wait-ok: this IS pump-until — the loop exits on the condition.
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pumpAndSettle();
}

/// The counter pill's rendered numeral, or null when the pill is absent.
String? _pillCount(WidgetTester tester) {
  final Finder pill = find.byType(WishlistCountPill);
  if (pill.evaluate().isEmpty) return null;
  return tester.widget<WishlistCountPill>(pill).count.toString();
}

void main() {
  // -------------------------------------------------------------------------
  // LOADED
  // -------------------------------------------------------------------------
  group('should_renderEveryFavourite_when_listHasFive', () {
    testWidgets('all five rows render — this page does NOT take(2)', (
      tester,
    ) async {
      final _Harness h = _Harness(services: _five());
      await h.pump(tester);

      expect(find.byKey(const Key('client-wishlist-screen')), findsOneWidget);
      expect(find.byType(WishlistRow), findsNWidgets(5));
      for (final String id in <String>['a', 'b', 'c', 'd', 'e']) {
        expect(
          _row(id),
          findsOneWidget,
          reason:
              'entry «$id» is missing. The passport section renders take(2); '
              'this page is the overflow destination and must render all of '
              'them.',
        );
        expect(find.byKey(Key('wishlist_row_book_$id')), findsOneWidget);
      }
    });

    testWidgets('the counter pill states the full list length', (tester) async {
      final _Harness h = _Harness(services: _five());
      await h.pump(tester);

      expect(_pillCount(tester), '5');
    });

    testWidgets('the rendered rows carry the real data, not placeholders', (
      tester,
    ) async {
      // A smoke assertion on row COUNT alone would pass against five empty
      // cards. These are per-entry values only correct data binding produces.
      final _Harness h = _Harness(services: _five());
      await h.pump(tester);

      final Iterable<WishlistRow> rows = tester.widgetList<WishlistRow>(
        find.byType(WishlistRow),
      );
      expect(
        rows.map((WishlistRow r) => r.item.serviceName).toList(),
        <String>[
          'Манікюр комбінований',
          'Нарощування вій — класика 2D',
          'Ламінування брів',
          'Педикюр апаратний',
          'Стрижка та укладка',
        ],
        reason: 'the backend ranks this list — wire order must be preserved',
      );
      // The phase-239 band, re-derived — the long backend form must not render.
      expect(rows.first.item.priceLabel, '600–900 ₴');
      expect(rows.first.item.priceDisplay, 'від 600 до 900 ₴');
      // i18n-finder-ok: a formatted money value, identical in every locale.
      expect(find.text('600–900 ₴'), findsOneWidget);
      // i18n-finder-ok: formatted duration data for the fixture's 90 minutes.
      expect(find.text('1 год 30 хв'), findsOneWidget);
    });

    testWidgets('neither the empty nor the error card is present', (
      tester,
    ) async {
      final _Harness h = _Harness(services: _five());
      await h.pump(tester);

      expect(find.byKey(const Key('wishlist_empty_state')), findsNothing);
      expect(find.byKey(const Key('wishlist_error_state')), findsNothing);
      expect(find.byKey(const Key('wishlist_loading_state')), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // EMPTY
  // -------------------------------------------------------------------------
  group('should_renderEmptyState_when_listIsEmpty', () {
    testWidgets('the empty card renders and no rows do', (tester) async {
      final _Harness h = _Harness(services: <WishlistService>[]);
      await h.pump(tester);

      expect(find.byKey(const Key('wishlist_empty_state')), findsOneWidget);
      expect(find.byType(WishlistRow), findsNothing);
    });

    testWidgets('the empty card is NOT the error card', (tester) async {
      // The regression that hid the always-empty passport bug for a phase: a
      // 401 rendered pixel-identically to "nothing saved yet". These two must
      // never both be satisfiable by one widget.
      final _Harness h = _Harness(services: <WishlistService>[]);
      await h.pump(tester);

      expect(find.byKey(const Key('wishlist_error_state')), findsNothing);
      expect(find.byKey(const Key('wishlist_retry_button')), findsNothing);
    });

    testWidgets('the counter pill reads 0 rather than disappearing', (
      tester,
    ) async {
      // An empty list legitimately COUNTS. Only the failure path suppresses the
      // pill, because a number beside "could not load" would assert something
      // the page does not know.
      final _Harness h = _Harness(services: <WishlistService>[]);
      await h.pump(tester);

      expect(_pillCount(tester), '0');
    });
  });

  // -------------------------------------------------------------------------
  // ERROR + RETRY
  // -------------------------------------------------------------------------
  group('should_renderErrorState_when_fetchFails', () {
    testWidgets('the error card and its retry button render', (tester) async {
      // A NON-TRANSIENT ServerFailure on purpose — see the file header, trap 2.
      final _Harness h = _Harness(
        failure: const ServerFailure(statusCode: null),
      );
      await h.pump(tester);

      expect(find.byKey(const Key('wishlist_error_state')), findsOneWidget);
      expect(find.byKey(const Key('wishlist_retry_button')), findsOneWidget);
    });

    testWidgets('the error card is NOT the empty card', (tester) async {
      final _Harness h = _Harness(
        failure: const ServerFailure(statusCode: null),
      );
      await h.pump(tester);

      expect(find.byKey(const Key('wishlist_empty_state')), findsNothing);
      expect(find.byType(WishlistRow), findsNothing);
    });

    testWidgets('no counter pill sits beside a "could not load" card', (
      tester,
    ) async {
      final _Harness h = _Harness(
        failure: const ServerFailure(statusCode: null),
      );
      await h.pump(tester);

      expect(
        _pillCount(tester),
        isNull,
        reason:
            'a count beside the failure card would assert a number the page '
            'does not have — 0 there reads as "nothing saved", which is the '
            'empty state, not this one',
      );
    });

    testWidgets('should_reloadList_when_retryTapped', (tester) async {
      final _Harness h = _Harness(
        failure: const ServerFailure(statusCode: null),
      );
      await h.pump(tester);
      expect(h.wishlist.getCallCount, 1);

      // The backend recovers between the failure and the retry.
      h.wishlist
        ..failure = null
        ..services = _five();

      await tester.tap(find.byKey(const Key('wishlist_retry_button')));
      await tester.pumpAndSettle();

      expect(
        h.wishlist.getCallCount,
        greaterThan(1),
        reason: 'retry did not re-fetch — the invalidate never fired',
      );
      expect(find.byKey(const Key('wishlist_error_state')), findsNothing);
      expect(find.byType(WishlistRow), findsNWidgets(5));
      expect(_pillCount(tester), '5');
    });

    testWidgets('retry does NOT flash the error card back under the finger', (
      tester,
    ) async {
      // `AsyncLoading(retrying: true)` still reports `hasError`. A screen that
      // branched `hasError` first (or used `.when()`) would repaint the failure
      // card the instant the client tapped «Спробувати знову». The delay keeps
      // the reload in flight across the assertion.
      final _Harness h = _Harness(
        failure: const ServerFailure(statusCode: null),
      );
      await h.pump(tester);

      h.wishlist
        ..failure = null
        ..services = _five()
        ..delay = const Duration(milliseconds: 300);

      await tester.tap(find.byKey(const Key('wishlist_retry_button')));

      // Every frame of the in-flight reload is checked, not one sampled
      // moment: `AsyncLoading(retrying: true)` is a transient state, and a
      // single sample could easily miss the frame the failure card would
      // reappear on.
      bool sawInFlight = false;
      for (int i = 0; i < 60; i++) {
        // A single-frame advance; the loop exits on the condition and the
        // assertion runs on EVERY frame, so nothing here is a guessed sleep.
        // fixed-wait-ok: pump-until-condition, one frame at a time.
        await tester.pump(const Duration(milliseconds: 16));
        if (find.byType(WishlistRow).evaluate().isNotEmpty) break;
        sawInFlight = true;
        expect(
          find.byKey(const Key('wishlist_error_state')),
          findsNothing,
          reason:
              'the failure card came straight back mid-reload (frame $i) — '
              'the screen is branching hasError before isLoading',
        );
      }
      expect(
        sawInFlight,
        isTrue,
        reason:
            'the reload resolved within one frame, so no in-flight frame was '
            'ever examined — the 300 ms fake delay is not taking effect and '
            'this test is vacuous',
      );

      await tester.pumpAndSettle();
      expect(find.byType(WishlistRow), findsNWidgets(5));
    });
  });

  // -------------------------------------------------------------------------
  // LOADING
  // -------------------------------------------------------------------------
  group('should_renderLoadingState_when_firstFetchIsInFlight', () {
    testWidgets('the skeleton renders while the first fetch is pending', (
      tester,
    ) async {
      final _Harness h = _Harness(
        services: _five(),
        delay: const Duration(milliseconds: 300),
      );
      await tester.pumpApp(
        const WishlistScreen(),
        overrides: h.overrides,
        width: 360,
      );
      await tester.pump(); // start the fetch, do not settle it

      expect(find.byKey(const Key('wishlist_loading_state')), findsOneWidget);
      expect(find.byType(WishlistRow), findsNothing);
      expect(
        find.byKey(const Key('wishlist_error_state')),
        findsNothing,
        reason: 'a pending first load is not a failure',
      );

      await tester.pumpAndSettle();
      expect(find.byKey(const Key('wishlist_loading_state')), findsNothing);
      expect(find.byType(WishlistRow), findsNWidgets(5));
    });
  });

  // -------------------------------------------------------------------------
  // REMOVAL
  // -------------------------------------------------------------------------
  group('should_decrementCountPill_when_entryUnfavourited', () {
    testWidgets('the pill ticks 5 → 4 and the row leaves', (tester) async {
      final _Harness h = _Harness(services: _five());
      await h.pump(tester);
      expect(_pillCount(tester), '5');

      await tester.tap(_row('c'));
      // Past the heart pop (110 ms) AND the row's collapse (260 ms) — the
      // notifier is not told until both have run.
      await _pumpUntil(tester, () => h.favorites.removeCalls.isNotEmpty);

      expect(_pillCount(tester), '4');
      expect(_row('c'), findsNothing);
      expect(find.byType(WishlistRow), findsNWidgets(4));
    });

    testWidgets('it removes the TAPPED entry, not the first one', (
      tester,
    ) async {
      // Keying the removal on anything but the tapped row's own
      // `masterServiceId` would delete the wrong favourite and still return
      // 204 — silent, and invisible to a count-only assertion.
      final _Harness h = _Harness(services: _five());
      await h.pump(tester);

      await tester.tap(_row('c'));
      await _pumpUntil(tester, () => h.favorites.removeCalls.isNotEmpty);

      expect(
        tester
            .widgetList<WishlistRow>(find.byType(WishlistRow))
            .map((WishlistRow r) => r.item.masterServiceId)
            .toList(),
        <String>['a', 'b', 'd', 'e'],
      );
      expect(
        h.favorites.removeCalls.single,
        const FavoriteTarget(type: FavoriteTargetType.service, id: 'c'),
      );
      expect(
        h.favorites.addCalls,
        isEmpty,
        reason:
            'an unseen target reads as `false` in the toggle map and toggling '
            'false is an ADD — the list must prime it first',
      );
    });

    testWidgets('the removal does NOT re-fetch the list', (tester) async {
      // THE OFFSTAGE-PAUSE TRAP. This page covers the passport page; an
      // `invalidate` here would dispose the provider rather than reload it and
      // the refetch would land on resume. `getCallCount` is what makes the ban
      // observable instead of merely commented.
      final _Harness h = _Harness(services: _five());
      await h.pump(tester);
      expect(h.wishlist.getCallCount, 1);

      await tester.tap(_row('c'));
      await _pumpUntil(tester, () => h.favorites.removeCalls.isNotEmpty);

      expect(
        h.wishlist.getCallCount,
        1,
        reason:
            'the removal triggered a refetch — on a covered route Riverpod 3 '
            'would dispose this provider instead of reloading it, and the '
            'removal would appear to do nothing until the user navigated back',
      );
    });

    testWidgets('the list never flashes its skeleton on a removal', (
      tester,
    ) async {
      // `removeService` writes AsyncData straight over AsyncData. A path
      // through AsyncLoading would blink the three-bar skeleton over a fully
      // loaded list on every un-favourite.
      final _Harness h = _Harness(services: _five());
      await h.pump(tester);

      await tester.tap(_row('c'));
      for (int i = 0; i < 40; i++) {
        // A single-frame advance; the loop exits on the condition and the
        // assertion runs on EVERY frame, so nothing here is a guessed sleep.
        // fixed-wait-ok: pump-until-condition, one frame at a time.
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          find.byKey(const Key('wishlist_loading_state')),
          findsNothing,
          reason: 'the skeleton appeared mid-removal (frame $i)',
        );
        if (h.favorites.removeCalls.isNotEmpty) break;
      }
      expect(h.favorites.removeCalls, hasLength(1));
      await tester.pumpAndSettle();
      expect(find.byType(WishlistRow), findsNWidgets(4));
    });

    testWidgets('removing the LAST entry lands on the empty state', (
      tester,
    ) async {
      final _Harness h = _Harness(
        services: <WishlistService>[_svc('solo', 'Манікюр', 60)],
      );
      await h.pump(tester);
      expect(_pillCount(tester), '1');

      await tester.tap(_row('solo'));
      await _pumpUntil(tester, () => h.favorites.removeCalls.isNotEmpty);

      expect(find.byKey(const Key('wishlist_empty_state')), findsOneWidget);
      expect(find.byType(WishlistRow), findsNothing);
      expect(_pillCount(tester), '0');
      expect(
        find.byKey(const Key('wishlist_error_state')),
        findsNothing,
        reason: 'an emptied list is not a failure',
      );
    });

    testWidgets('a FAILED removal restores the row and the count', (
      tester,
    ) async {
      // `WishlistRemovalHost` clears its `_removing` flag on BOTH paths. If it
      // did not, the restored entry would be permanently collapsed by a stale
      // animation flag while still present in state — a data/UI divergence no
      // notifier-only test can see.
      final _Harness h = _Harness(services: _five());
      h.favorites.removeResult = const NetworkFailure();
      await h.pump(tester);

      await tester.tap(_row('c'));
      await _pumpUntil(tester, () => h.favorites.removeCalls.isNotEmpty);

      expect(_row('c'), findsOneWidget, reason: 'the row must animate back in');
      expect(find.byType(WishlistRow), findsNWidgets(5));
      expect(_pillCount(tester), '5');
      expect(
        tester
            .widgetList<WishlistRow>(find.byType(WishlistRow))
            .map((WishlistRow r) => r.item.masterServiceId)
            .toList(),
        <String>['a', 'b', 'c', 'd', 'e'],
        reason: 'restored AT ITS ORIGINAL INDEX — the backend ranks this list',
      );
    });

    testWidgets('a double-tap on a leaving row fires ONE request', (
      tester,
    ) async {
      final _Harness h = _Harness(services: _five());
      await h.pump(tester);

      await tester.tap(_row('c'));
      // Mid-collapse: the heart has fired but the notifier has not been told
      // yet, so the row is still mounted and still tappable.
      await _pumpUntil(
        tester,
        () => find.byKey(const Key('wishlist_row_heart_c')).evaluate().isEmpty,
        maxFrames: 10,
      );
      if (_row('c').evaluate().isNotEmpty) {
        await tester.tap(_row('c'), warnIfMissed: false);
      }
      await _pumpUntil(tester, () => h.favorites.removeCalls.isNotEmpty);

      expect(h.favorites.removeCalls, hasLength(1));
      expect(find.byType(WishlistRow), findsNWidgets(4));
    });
  });

  // -------------------------------------------------------------------------
  // Page chrome
  // -------------------------------------------------------------------------
  group('page chrome', () {
    testWidgets('the back control is present on every state', (tester) async {
      // This is a pushed LEAF, not a tab root: without a back affordance the
      // only way out is the swipe gesture.
      for (final _Harness h in <_Harness>[
        _Harness(services: _five()),
        _Harness(services: <WishlistService>[]),
        _Harness(failure: const ServerFailure(statusCode: null)),
      ]) {
        await h.pump(tester);
        expect(find.byKey(const Key('wishlist_back_button')), findsOneWidget);
      }
    });

    testWidgets('no «Показати всі» button — this IS the overflow page', (
      tester,
    ) async {
      final _Harness h = _Harness(services: _five());
      await h.pump(tester);

      expect(find.byKey(const Key('wishlist_show_all_button')), findsNothing);
    });

    testWidgets('renders without overflow on a 320 dp phone at 1.3x text', (
      tester,
    ) async {
      // The overflow guard `pumpApp` installs fails the test on any RenderFlex
      // overflow, so reaching the assertion is the result.
      final _Harness h = _Harness(services: _five());
      await tester.pumpApp(
        const WishlistScreen(),
        overrides: h.overrides,
        width: 320,
        textScaleFactor: 1.3,
      );
      await tester.pumpAndSettle();

      expect(find.byType(WishlistRow), findsNWidgets(5));
    });
  });
}
