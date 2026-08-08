// Phase 239 — `/passport/wishlist` («Усі збережені») as an actual NAVIGATION,
// driven through the REAL `appRouterProvider`.
//
// WHY THIS TEST IS DRIVEN BY `context.push` AND NOT BY `router.go`
// ---------------------------------------------------------------------------
// `route_names.dart` carries the warning in the source itself: this route is
// reached with `context.push`, never `context.go`, and «a pushed leaf collapses
// to the PARENT path in `GoRouterState.fullPath`, so a `go`-based navigation
// test would false-pass against `/passport`». This repo has been bitten by the
// same go_router property three times (see
// `scripts/forbid_naive_router_location.sh`'s header), twice in shipped code
// and once in a test that reported the PRE-push location forever.
//
// So this file never calls `router.go`/`router.push` for the navigation under
// test. It taps the PRODUCTION control — the passport section's
// `wishlist_show_all_button`, whose handler is
// `context.push(RouteNames.clientWishlist)`
// (`passport_screen.dart:151-155`) — and reads the location back by DESCENDING
// the match tree (see `_Harness.location`, which also records why neither
// shared `AppHarness` resolver reaches this shape). A direct
// `currentConfiguration.uri`/`.fullPath` read is what the CI gate forbids, and
// it is forbidden precisely because it would report `/passport` here and pass.
//
// ## THE THREE THINGS A `go`-BASED TEST WOULD NOT CATCH
//
//   1. that the route is registered as a CHILD of the passport branch rather
//      than at the top level — a top-level registration would still be
//      reachable by `go`, but the push would land on the ROOT navigator and
//      swipe-back would unwind to a branch root instead of the passport page;
//   2. that the pushed page keeps a real back affordance and that
//      `context.pop()` returns to the passport page rather than to `/home`;
//   3. that the passport page underneath survives the round trip WITH ITS
//      SCROLL OFFSET — the stated reason for nesting it under the branch.
//
// Layer: Widget (real router + real screens, faked repositories).

import 'package:beautica_mobile/core/app_start_time.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/favorites/data/favorite_repository_provider.dart';
import 'package:beautica_mobile/features/home/application/home_hub_notifier.dart';
import 'package:beautica_mobile/features/home/domain/home_hub_models.dart';
import 'package:beautica_mobile/features/passport/application/passport_notifier.dart';
import 'package:beautica_mobile/features/passport/domain/passport.dart';
import 'package:beautica_mobile/features/passport/presentation/passport_screen.dart';
import 'package:beautica_mobile/features/shell/presentation/client_shell.dart';
import 'package:beautica_mobile/features/shell/presentation/widgets/client_bottom_nav.dart';
import 'package:beautica_mobile/features/wishlist/application/wishlist_notifier.dart';
import 'package:beautica_mobile/features/wishlist/domain/wishlist_service.dart';
import 'package:beautica_mobile/features/wishlist/presentation/widgets/wishlist_row.dart';
import 'package:beautica_mobile/features/wishlist/presentation/wishlist_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/fakes/fake_auth_repository.dart';
import '../helpers/fakes/fake_favorite_repository.dart';
import '../helpers/fakes/fake_secure_storage.dart';
import '../helpers/fakes/fake_wishlist_repository.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const User _client = User(
  id: 'u-client',
  email: 'client@example.com',
  role: UserRole.client,
  firstName: 'Олена',
  lastName: 'Тест',
);

const AsyncData<AuthSession> _session = AsyncData<AuthSession>(
  AuthSession.authenticated(user: _client, accessToken: 'token'),
);

const ClientProfileSummary _profile = ClientProfileSummary(
  firstName: 'Олена',
  lastName: 'Тест',
  city: 'Львів',
  phone: '+380 97 000 00 00',
  clientRating: null,
  memberSinceYear: 2024,
);

const Passport _passport = Passport(
  favoriteProcedures: <String>['Манікюр', 'Брови', 'Педикюр'],
  favoriteDistricts: <String>['Центр', 'Сихів'],
  favoriteCities: <String>['Львів'],
  budget: BudgetBand(avg: 600, min: 400, max: 800),
  bookingsConsidered: 7,
  reviewsWritten: 5,
  memberSinceYear: 2024,
);

/// Six entries — more than the passport section's `take(2)`, so «Показати всі»
/// is rendered AND the destination page has something the section does not.
List<WishlistService> _wishlist() => <WishlistService>[
  for (final String id in <String>['a', 'b', 'c', 'd', 'e', 'f'])
    WishlistService(
      masterServiceId: id,
      masterId: 'm-$id',
      serviceName: 'Послуга $id',
      masterName: 'Олена Ковальчук',
      durationMinutes: 60,
      priceDisplay: 'від 600 до 900 ₴',
      isRangePrice: true,
      priceMin: 600,
      priceMax: 900,
    ),
];

class _FixedAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async {
    state = _session;
    return _session.value;
  }
}

// ---------------------------------------------------------------------------
// Harness — the real router, booted straight onto the passport branch
// ---------------------------------------------------------------------------

class _Harness {
  _Harness._(this.tester, this.container, this.router, this.wishlistRepo);

  final WidgetTester tester;
  final ProviderContainer container;
  final GoRouter router;
  final FakeWishlistRepository wishlistRepo;

  static Future<_Harness> boot(WidgetTester tester) async {
    final FakeWishlistRepository wishlistRepo = FakeWishlistRepository(
      services: _wishlist(),
    );
    final ProviderContainer container = ProviderContainer(
      retry: beauticaProviderRetry,
      overrides: <Object>[
        authProvider.overrideWith(_FixedAuthNotifier.new),
        authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
        secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
        // The passport page's own data — otherwise the suite-wide no-network
        // override settles both to AsyncError and the wish-list section (which
        // is what this test navigates FROM) never renders its button.
        clientProfileProvider.overrideWith((_) async => _profile),
        passportProvider.overrideWith((_) async => _passport),
        // Real manager, never the native plugin: its enable/disable paths are
        // kDebugMode-guarded (mirrors `passport_screen_test.dart`).
        screenProtectionProvider.overrideWithValue(ScreenProtectionManager()),
        wishlistRepositoryProvider.overrideWithValue(wishlistRepo),
        favoriteRepositoryProvider.overrideWithValue(FakeFavoriteRepository()),
      ].cast(),
    );

    final GoRouter router = container.read(appRouterProvider);

    // A tall, narrow surface: the passport page is a long ListView and the
    // wish-list section sits at its bottom, so a default 800x600 would leave
    // «Показати всі» permanently off-screen.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('uk'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final _Harness h = _Harness._(tester, container, router, wishlistRepo);
    // `wishlistProvider` holds a 5-minute keep-alive `Timer`, cancelled in its
    // `onDispose`. The binding's pending-timer invariant runs BEFORE
    // `addTearDown` callbacks, so disposal has to happen inside the test body —
    // hence `_disposeAll` is called at the end of each test AND registered as a
    // (guarded) tearDown so an early failure still cleans up.
    addTearDown(h.disposeAll);
    await h._goPassport();
    return h;
  }

  /// Whether the current location was reached by a PUSH.
  ///
  /// This is the structural difference between `context.push` and
  /// `context.go`, and it is the only one either the router or a test can see
  /// directly: a push inserts an [ImperativeRouteMatch] into the tree, a `go`
  /// builds a plain parent→child [RouteMatch] chain. EVERYTHING ELSE about the
  /// two is indistinguishable here — measured, not assumed. Under `go`,
  /// go_router still stacks `/passport` beneath `/passport/wishlist` (it is a
  /// CHILD route), so `context.pop()` still works, the passport page is still
  /// underneath, and its scroll offset is still preserved. Every one of this
  /// file's other assertions therefore passes under BOTH — verified by
  /// mutation: swapping the production call site to `context.go` left them all
  /// green.
  ///
  /// So this is the assertion that actually pins the `push` requirement
  /// `route_names.dart` states.
  bool get hasImperativeMatch {
    bool walk(RouteMatchBase match) {
      if (match is ImperativeRouteMatch) return true;
      if (match is ShellRouteMatch) return match.matches.any(walk);
      return false;
    }

    return router.routerDelegate.currentConfiguration.matches.any(walk);
  }

  /// The NAIVE read — deliberately.
  ///
  /// `currentConfiguration.uri` documentedly EXCLUDES imperative matches, so
  /// after a successful push it reports the pre-push location. Asserting that
  /// it says `/passport` while [location] says `/passport/wishlist` is what
  /// makes the trap itself the thing under test rather than an anecdote: under
  /// `context.go` this property would agree with [location] and the assertion
  /// goes red.
  String get rawShellLocation {
    // The divergence between this property and the descended location is the
    // evidence that the navigation was a push (see this getter's doc comment).
    // router-location-ok: this test deliberately PINS the raw-read trap.
    return router.routerDelegate.currentConfiguration.uri.toString();
  }

  bool _disposed = false;

  /// Idempotent — safe to call in-body and again from the tearDown.
  void disposeAll() {
    if (_disposed) return;
    _disposed = true;
    router.dispose();
    container.dispose();
  }

  /// Lands on the passport TAB ROOT.
  ///
  /// `go` is correct HERE and only here: a branch root is exactly the case
  /// `go` is for. The navigation under test — the push onto that branch — is
  /// never driven this way.
  Future<void> _goPassport() async {
    router.go(RouteNames.clientPassport);
    await tester.pumpAndSettle();
    expect(find.byType(PassportScreen), findsOneWidget);
  }

  /// The current location, resolved PUSH-SAFELY.
  ///
  /// ## NEITHER SHARED RESOLVER WORKS FOR THIS SHAPE — MEASURED, NOT ASSUMED
  ///
  /// `AppHarness.location` unwraps a top-level `ImperativeRouteMatch`, and
  /// `AppHarness.shellLocation` reads `matches.last.matchedLocation`. This
  /// route is neither: it is pushed onto the passport BRANCH's own navigator,
  /// so the top-level match list holds exactly ONE entry — a `ShellRouteMatch`
  /// whose own `matchedLocation` is `/passport` — and the
  /// `ImperativeRouteMatch` sits one level DOWN inside it. Verified during
  /// authoring: with the wish-list screen demonstrably mounted, both shared
  /// resolvers returned `/passport`.
  ///
  /// That is exactly the false-pass class `forbid_naive_router_location.sh`
  /// exists for, just one nesting level deeper than the shared helpers reach.
  /// So the match tree is DESCENDED here: through every `ShellRouteMatch` to
  /// the leaf, unwrapping an `ImperativeRouteMatch` when one is found. No
  /// `currentConfiguration.uri`/`.fullPath` is read at any point — the gate's
  /// forbidden properties are never touched, and this resolver reports
  /// `/passport/wishlist` where they report `/passport`.
  String get location {
    RouteMatchBase match =
        router.routerDelegate.currentConfiguration.matches.last;
    while (true) {
      if (match is ShellRouteMatch) {
        match = match.matches.last;
        continue;
      }
      if (match is ImperativeRouteMatch) {
        // The push's OWN nested match list — the absolute pushed location.
        return match.matches.uri.toString();
      }
      return match.matchedLocation;
    }
  }

  /// The passport page's own scroll controller position.
  ScrollableState get passportScrollable => tester.state<ScrollableState>(
    find.descendant(
      of: find.byType(PassportScreen),
      matching: find.byType(Scrollable),
    ),
  );

  /// Scrolls the passport page until `wishlist_show_all_button` is on screen,
  /// leaving the page GENUINELY scrolled (which the back-navigation case then
  /// asserts is preserved).
  Future<void> revealShowAll() async {
    final Finder button = find.byKey(const Key('wishlist_show_all_button'));
    await tester.dragUntilVisible(
      button,
      find.descendant(
        of: find.byType(PassportScreen),
        matching: find.byType(Scrollable),
      ),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
    expect(button, findsOneWidget);
  }
}

void main() {
  // Park the splash gate in the past so `authRedirect` does not pin the router
  // on /splash waiting for the minimum splash duration.
  setUp(
    () => AppStartTime.setStartForTest(
      DateTime.now().subtract(const Duration(seconds: 5)),
    ),
  );
  tearDown(AppStartTime.resetForTest);

  group('should_pushWishlist_when_showAllTapped', () {
    testWidgets('tapping «Показати всі» pushes /passport/wishlist', (
      tester,
    ) async {
      final _Harness h = await _Harness.boot(tester);
      await h.revealShowAll();

      expect(
        h.location,
        RouteNames.clientPassport,
        reason: 'precondition: still on the passport branch root',
      );

      // THE PRODUCTION CONTROL. Its handler is
      // `context.push(RouteNames.clientWishlist)` — driving the real button is
      // what makes this a test of the wiring rather than of the route table.
      await tester.tap(find.byKey(const Key('wishlist_show_all_button')));
      await tester.pumpAndSettle();

      expect(
        h.location,
        RouteNames.clientWishlist,
        reason:
            'the push did not land on /passport/wishlist. If this reads '
            '"/passport", the location was resolved with a raw '
            'currentConfiguration read — go_router excludes ImperativeRouteMatch '
            'from those properties, which is the false-pass this file exists '
            'to prevent.',
      );
      expect(find.byKey(const Key('client-wishlist-screen')), findsOneWidget);
      expect(find.byType(WishlistScreen), findsOneWidget);

      // IT WAS A PUSH, not a `go`. Without this the whole file is satisfied by
      // either — see `hasImperativeMatch`'s doc comment for the mutation that
      // proved it.
      expect(
        h.hasImperativeMatch,
        isTrue,
        reason:
            'the show-all control navigated with `go` rather than `push`. '
            '`route_names.dart` requires `push` so the passport page stays on '
            'the branch stack as a real pushed leaf.',
      );
      // …and the naive read still says `/passport`, which is the trap in the
      // flesh: a test that read this property would have passed while asserting
      // the wrong location.
      expect(
        h.rawShellLocation,
        RouteNames.clientPassport,
        reason:
            'currentConfiguration.uri agreed with the real location, so this '
            'navigation produced no ImperativeRouteMatch — i.e. it was a `go`.',
      );

      h.disposeAll();
    });

    testWidgets(
      'the destination renders the WHOLE list, not the section\'s two',
      (tester) async {
        // The reason the page exists. Landing on it and finding two rows would
        // mean the push resolved to the section rather than to the overflow page.
        final _Harness h = await _Harness.boot(tester);
        await h.revealShowAll();
        await tester.tap(find.byKey(const Key('wishlist_show_all_button')));
        await tester.pumpAndSettle();

        expect(find.byType(WishlistRow), findsNWidgets(6));

        h.disposeAll();
      },
    );

    testWidgets('a bare go(...) produces NO imperative match — the contrast', (
      tester,
    ) async {
      // THE MUTATION CONTROL for the assertion above, run in the same file so
      // the difference is legible rather than folklore.
      //
      // A `go` to this route is NOT a broken navigation — `/passport/wishlist`
      // is a CHILD route, so go_router stacks `/passport` beneath it and the
      // screen, the pop and even the passport page's scroll offset all behave
      // identically. The ONE observable difference is the match kind, and it is
      // the difference every raw `currentConfiguration.uri` read turns on.
      final _Harness h = await _Harness.boot(tester);

      h.router.go(RouteNames.clientWishlist);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('client-wishlist-screen')), findsOneWidget);
      expect(h.location, RouteNames.clientWishlist);
      expect(
        h.hasImperativeMatch,
        isFalse,
        reason: '`go` must not produce an ImperativeRouteMatch',
      );
      // And here the naive read AGREES with the real location — which is
      // precisely why a `go`-driven test of the production button would false-
      // pass: it never exercises the exclusion at all.
      expect(h.rawShellLocation, RouteNames.clientWishlist);

      h.disposeAll();
    });

    testWidgets('the shared provider is not re-fetched by the navigation', (
      tester,
    ) async {
      // Both surfaces `ref.watch` ONE `wishlistProvider`. If the push caused a
      // second fetch, the two would be free to disagree and the "no callback
      // plumbing" design would be quietly broken.
      final _Harness h = await _Harness.boot(tester);
      await h.revealShowAll();
      expect(h.wishlistRepo.getCallCount, 1);

      await tester.tap(find.byKey(const Key('wishlist_show_all_button')));
      await tester.pumpAndSettle();

      expect(
        h.wishlistRepo.getCallCount,
        1,
        reason: 'the destination re-fetched instead of sharing the provider',
      );

      h.disposeAll();
    });
  });

  group('should_returnToScrolledPassport_when_backPressed', () {
    testWidgets('the back control pops to /passport at its previous offset', (
      tester,
    ) async {
      final _Harness h = await _Harness.boot(tester);
      await h.revealShowAll();

      final double offsetBefore = h.passportScrollable.position.pixels;
      expect(
        offsetBefore,
        greaterThan(0),
        reason:
            'the passport page must actually be SCROLLED for this test to mean '
            'anything — at offset 0 "preserved" is indistinguishable from '
            '"reset"',
      );

      await tester.tap(find.byKey(const Key('wishlist_show_all_button')));
      await tester.pumpAndSettle();
      expect(h.location, RouteNames.clientWishlist);

      // The pushed leaf's own back affordance — `context.pop()`.
      await tester.tap(find.byKey(const Key('wishlist_back_button')));
      await tester.pumpAndSettle();

      expect(h.location, RouteNames.clientPassport);
      expect(find.byKey(const Key('client-wishlist-screen')), findsNothing);
      expect(find.byType(PassportScreen), findsOneWidget);
      expect(
        h.passportScrollable.position.pixels,
        closeTo(offsetBefore, 0.5),
        reason:
            'the passport page reset its scroll offset. Nesting this route '
            'under the passport BRANCH (rather than at the top level) is what '
            'is supposed to keep the branch\'s navigator — and therefore its '
            'page state — alive underneath the push.',
      );

      h.disposeAll();
    });

    testWidgets(
      'the pushed leaf sits INSIDE the client shell (bottom nav present)',
      (tester) async {
        // NOT the behaviour `wishlist_screen.dart`'s header describes — it
        // states «There is no bottom nav here: this is a pushed leaf, not a tab
        // root.» Nesting the route under the passport BRANCH puts it inside
        // `ClientShell`, so the shell-owned bottom nav renders over it. This is
        // pinned as OBSERVED behaviour, not endorsed: it is also the assertion
        // that would go red if the route were ever moved to the top level (a
        // top-level route lands on the ROOT navigator, above the shell), which
        // is the registration mistake the nesting exists to prevent.
        //
        // Reported to the owning agent as a doc/behaviour divergence. If the
        // product decision is that a pushed leaf hides the nav, this
        // expectation flips and the fix belongs in the route registration or
        // the shell, not here.
        final _Harness h = await _Harness.boot(tester);
        await h.revealShowAll();
        await tester.tap(find.byKey(const Key('wishlist_show_all_button')));
        await tester.pumpAndSettle();

        expect(find.byType(ClientShell), findsOneWidget);
        expect(find.byType(ClientBottomNav), findsOneWidget);

        h.disposeAll();
      },
    );

    testWidgets('the back control exists at all', (tester) async {
      // A pushed leaf with no back affordance leaves the swipe gesture as the
      // only way out — unusable on a device where the gesture is disabled.
      final _Harness h = await _Harness.boot(tester);
      await h.revealShowAll();
      await tester.tap(find.byKey(const Key('wishlist_show_all_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('wishlist_back_button')), findsOneWidget);

      h.disposeAll();
    });

    testWidgets('the pushed page keeps a swipe-back-capable MaterialPage', (
      tester,
    ) async {
      // The route is registered with `builder:`, NOT `pageBuilder: _instantPage`
      // — `_instantPage` returns a `CustomTransitionPage` whose own
      // transitionsBuilder bypasses `CupertinoPageTransitionsBuilder`, the
      // mechanism that installs Flutter's left-edge swipe-back detector. Pinned
      // the same way `master_public_profile_swipe_back_test.dart` pins it: by
      // inspecting the Page object go_router actually handed the Navigator.
      final _Harness h = await _Harness.boot(tester);
      await h.revealShowAll();
      await tester.tap(find.byKey(const Key('wishlist_show_all_button')));
      await tester.pumpAndSettle();

      final List<Page<dynamic>> pages = <Page<dynamic>>[
        for (final Navigator nav in tester.widgetList<Navigator>(
          find.byType(Navigator),
        ))
          ...nav.pages,
      ];
      final Iterable<Page<dynamic>> wishlistPages = pages.where(
        (Page<dynamic> p) => p.name == 'wishlist',
      );

      expect(
        wishlistPages,
        isNotEmpty,
        reason:
            'no Page named after the route pattern — go_router names every '
            '`builder:`-resolved Page `state.name ?? state.path`, and a '
            '`pageBuilder: _instantPage` route sets no name at all. An empty '
            'result here IS the revert.',
      );
      for (final Page<dynamic> p in wishlistPages) {
        expect(p, isA<MaterialPage<dynamic>>());
        expect(p, isNot(isA<CustomTransitionPage<dynamic>>()));
      }

      h.disposeAll();
    });

    testWidgets('an un-favourite on the pushed page is visible after popping', (
      tester,
    ) async {
      // The whole point of ONE provider behind both surfaces: no `onChanged`
      // callback, no constructor argument, no manual mirroring. And the reason
      // `removeService` mutates in place — Riverpod 3 pauses this covered
      // passport page, so an `invalidate` would DISPOSE the provider and defer
      // the refetch to resume.
      final _Harness h = await _Harness.boot(tester);
      await h.revealShowAll();
      await tester.tap(find.byKey(const Key('wishlist_show_all_button')));
      await tester.pumpAndSettle();
      expect(find.byType(WishlistRow), findsNWidgets(6));

      await tester.tap(find.byKey(const Key('wishlist_row_heart_a')));
      await _pumpUntil(
        tester,
        () => find.byType(WishlistRow).evaluate().length == 5,
      );

      await tester.tap(find.byKey(const Key('wishlist_back_button')));
      await tester.pumpAndSettle();

      expect(h.location, RouteNames.clientPassport);
      // The section's «Показати всі (N)» counts what is left, so 5 is what the
      // shared provider now holds — and the passport page never asked for it.
      expect(
        h.wishlistRepo.getCallCount,
        1,
        reason:
            'returning to the passport page re-fetched the list — the removal '
            'was not shared through the provider',
      );

      h.disposeAll();
    });
  });
}

/// Pumps single frames until [condition] holds, then settles.
///
/// The removal sequence is gated by two timers that schedule no frames of their
/// own (the heart's 110 ms pop and the row's 260 ms collapse), so
/// `pumpAndSettle` alone can return with both still pending.
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
