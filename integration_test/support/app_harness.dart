// Phase 17.3 — Shared app harness for integration tests.
//
// WHAT
// ----
// Single boot path for ALL E2E journeys. Boots the REAL app (real Scaffold,
// real go_router, real Riverpod notifiers) via a [ProviderScope] with:
//   • dioProvider           → FakeBackend.dio (no real socket)
//   • clockProvider         → fixed DateTime (2026-06-14 12:00 UTC)
//   • secureStorageProvider → FakeSecureStorage (no platform channel)
//
// The [AuthNotifier] is NOT overridden — the real build() runs but hits the
// fake SecureStorage (no refresh token → Unauthenticated on cold start). Tests
// that need an authenticated session call [AppHarness.loginAs] after boot to
// drive through the real login flow against the fake backend.
//
// OVERFLOW GUARD
// --------------
// Wires the Phase 17.2 overflow guard via [installOverflowGuard] in [setUp],
// matching the unit-test suite. Any RenderFlex overflow in the E2E tree fails
// the test at tearDown, surfacing it as a clean test failure rather than a
// yellow stripe.
//
// SPLASH GATE (RC1 FIX)
// ---------------------
// [AppStartTime._start] is null when the harness boots (main() is never called
// in tests). A null _start causes [AppStartTime.elapsed()] to return
// Duration.zero, which is always < _minSplashDuration (3 000 ms).
// [authRedirectForLocation] therefore keeps re-routing to /splash forever,
// so /login never mounts and find.byKey('login_email') finds nothing.
//
// Fix: [boot()] applies [applyE2eBootPolicy], which backdates
// [AppStartTime.setStartForTest] by 5 s, making elapsed() ≈ 5 s > 3 s. This
// unblocks the auth redirect on the first pumpAndSettle(). [tearDownHarness()]
// resets it so state does not bleed between tests. Tests that call [boot()]
// MUST register tearDownHarness in their tearDown:
//
//   setUp(installOverflowGuard);
//   tearDown(AppHarness.tearDownHarness);
//
// SHARED BOOT POLICY
// ------------------
// The rules that must hold for EVERY E2E boot — overflow guard, the
// off-screen-tap guard, the text-input mock registration, the timezone
// database, and the splash-gate priming above — are NOT defined in this file.
// They live in `integration_test/support/e2e_boot_policy.dart` and are applied
// by a single [applyE2eBootPolicy] call in [boot], because the patrol tier's
// harness must apply the identical set and a hand-mirrored copy is guaranteed
// to drift (it did — see that file's header). Add cross-tier policy there.
//
// KEY-BASED NAVIGATION POLICY (ENFORCED)
// ----------------------------------------
// ALL navigation taps in integration_test/ MUST use key-based finders:
//
//   ALLOWED:
//     await tester.tap(find.byKey(const Key('login_submit')));
//     await tester.tap(find.byKey(const ValueKey('step1_submit')));
//
//   FORBIDDEN for tapping (raw-text tap driver = flake source):
//     await tester.tap(find.text('Увійти'));   // ← BAN: text tap driver
//
//   ALLOWED for content assertions:
//     expect(find.text('Вітаємо!'), findsOneWidget);  // ← OK: assertion
//
// RATIONALE: Ukrainian string literals change with l10n updates and differ
// across locales; key-based finders are locale-invariant and rename-proof.
// This convention is enforced by convention (not a lint gate) because
// flutter_test has no cheap custom lint for integration_test/ paths.
//
// ROUTER REFERENCE (RC2 FIX)
// --------------------------
// [boot()] returns the live [GoRouter] instance that was wired into the
// [MaterialApp.router]. Tests that need to assert the current route or navigate
// programmatically MUST hold this reference:
//
//   final GoRouter router = await AppHarness.boot(tester, fb);
//
// Use [AppHarness.location(router)] to read the current location — it is
// locale-invariant, does NOT depend on [GoRouter.of(context)] (which would
// require a context that is a DESCENDANT of [InheritedGoRouter], i.e. inside
// the router's subtree, not at the MaterialApp level), and — unlike a raw
// [router.routerDelegate.currentConfiguration.uri] read — resolves correctly
// after a `context.push` (see [location]'s own doc comment for why the raw
// read is a trap). [AppHarness.expectLocation] wraps it for the common
// `startsWith` assertion.
//
// USAGE
// -----
//   setUp(installOverflowGuard);
//   tearDown(AppHarness.tearDownHarness);
//
//   testWidgets('login flow', (tester) async {
//     final fb = FakeBackend();
//     final router = await AppHarness.boot(tester, fb);
//     await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
//     // assert route
//     AppHarness.expectLocation(router, '/master/profile');
//   });

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../test/helpers/fakes/fake_secure_storage.dart';
import 'e2e_boot_policy.dart';
import 'fake_backend.dart';

export 'fake_backend.dart' show FakeBackend, kFixedNow;
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

/// Shared boot path and convenience helpers for Phase 17.3 E2E tests.
abstract final class AppHarness {
  AppHarness._(); // non-instantiable

  // ── Cascade guard (Fix #2) ─────────────────────────────────────────────────

  /// Bounded settle window for EVERY [pumpAndSettle] on the shared boot/login
  /// path. The flutter_test default [pumpAndSettle] timeout is 10 MINUTES,
  /// which is far longer than the per-test [Timeout(Duration(seconds: 45))] used
  /// by the aggregated suite (integration_test/all_tests.dart, one isolate for
  /// 17 flows). When a flow hangs in an unbounded pumpAndSettle, the test-level
  /// Timeout completes the test future WHILE a pump is still in flight, leaving
  /// the single per-isolate [IntegrationTestWidgetsFlutterBinding] mid-frame —
  /// corrupting it for EVERY subsequent test (1 hang → ~50 cascade failures).
  ///
  /// Capping pumpAndSettle at 20 s (< the 45 s test Timeout) makes a hang throw
  /// `FlutterError("pumpAndSettle timed out")` SYNCHRONOUSLY inside the test
  /// body BEFORE the harness-level abort fires: the test fails as exactly ONE
  /// clean failure, [addTearDown] unmounts normally, and the next test boots
  /// from a clean tree.
  static const Duration settleTimeout = Duration(seconds: 20);

  /// [pumpAndSettle] bounded by [settleTimeout]. Preserves the default
  /// 100 ms interval / [EnginePhase.sendSemanticsUpdate] phase semantics —
  /// only the timeout is constrained. Use on the shared boot/login path so a
  /// single hang cannot cascade across the aggregated isolate (see [settleTimeout]).
  static Future<void> settle(
    WidgetTester tester, {
    Duration interval = const Duration(milliseconds: 100),
  }) {
    return tester.pumpAndSettle(
      interval,
      EnginePhase.sendSemanticsUpdate,
      settleTimeout,
    );
  }

  // ── Bounded pump-until (spinner-safe) ───────────────────────────────────────

  /// Pumps in small, bounded steps until [finder] resolves to at least one
  /// widget, or [timeout] elapses.
  ///
  /// Every discovery-results submit can render a trailing INDETERMINATE
  /// `_LoadMoreSpinner` the instant `SearchResultsState.hasMore` is true —
  /// which it always is on the very first page against [FakeBackend], whose
  /// `/search/masters` fixture deliberately seeds `totalPages: 2` so a
  /// `loadMore` scroll has a genuine second page to fetch (search_results_
  /// screen.dart's `_ResultsList`). An indeterminate `CircularProgressIndicator`
  /// drives its own `AnimationController.repeat()`, which keeps
  /// `SchedulerBinding.hasScheduledFrame` permanently true — so
  /// `pumpAndSettle()` can never observe "no more frames scheduled" and hangs
  /// until the enclosing `testWidgets` [Timeout] kills it (typically ~90 s,
  /// tripping `LiveTestWidgetsFlutterBinding`'s `'_pendingFrame == null'`
  /// invariant in `postTest`). Do NOT reach for `pumpAndSettle()` after any
  /// action that can leave that spinner mounted (a filters submit, a sort
  /// change, a re-search) — use this instead.
  ///
  /// Polls every [step] (default 100 ms — well inside [FakeBackend]'s
  /// sub-second in-memory response time) up to [timeout] (default 10 s, a
  /// generous multiple of that). Ends with one extra plain [WidgetTester.pump]
  /// so the frame that just made [finder] match is fully built/laid out before
  /// the caller inspects it. Throws a [TestFailure] (not a raw hang) when
  /// [finder] never appears, so a genuine regression still fails fast and
  /// legibly instead of riding the full per-test timeout.
  static Future<void> pumpUntilFound(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 10),
    Duration step = const Duration(milliseconds: 100),
  }) async {
    final DateTime deadline = DateTime.now().add(timeout);
    while (finder.evaluate().isEmpty) {
      if (DateTime.now().isAfter(deadline)) {
        throw TestFailure(
          'AppHarness.pumpUntilFound timed out after $timeout waiting for '
          '$finder to appear (polled every $step).',
        );
      }
      await tester.pump(step);
    }
    await tester.pump();
  }

  /// Pumps until [condition] is true, or [timeout] elapses.
  ///
  /// The counterpart to [pumpUntilFound] for effects that are NOT in the widget
  /// tree — a captured wire param, a POST counter, a repository call. Do NOT
  /// smuggle these through `find.byWidgetPredicate((_) => <bool>)`: that finder
  /// matches EVERY widget when the bool is true and NONE when it is false, so
  /// it works by accident, walks the whole tree on every poll, and reports the
  /// useless "Found 0 widgets with widget matching predicate: []" instead of
  /// naming the condition that never came true.
  static Future<void> pumpUntilCondition(
    WidgetTester tester,
    bool Function() condition, {
    required String description,
    Duration timeout = const Duration(seconds: 10),
    Duration step = const Duration(milliseconds: 100),
  }) async {
    final DateTime deadline = DateTime.now().add(timeout);
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        throw TestFailure(
          'AppHarness.pumpUntilCondition timed out after $timeout waiting for '
          '$description (polled every $step).',
        );
      }
      await tester.pump(step);
    }
    await tester.pump();
  }

  // ── Boot ──────────────────────────────────────────────────────────────────

  /// Pumps the REAL app with the fake backend and fixed-clock overrides.
  ///
  /// Returns the live [GoRouter] instance wired into [MaterialApp.router] so
  /// tests can assert the current location via [location]/[expectLocation]
  /// and navigate programmatically without relying on [GoRouter.of(context)],
  /// which fails at the [MaterialApp] level (requires a descendant context).
  ///
  /// After this call the app is sitting on /login (the fake [SecureStorage] has
  /// no stored refresh token → [AuthNotifier] settles to Unauthenticated →
  /// redirect to /login). Call [loginAs] to advance to an authenticated home.
  ///
  /// RC1 fix: sets [AppStartTime] to 5 s ago so the splash-duration gate
  /// (3 000 ms) is already satisfied when the first [pumpAndSettle] runs.
  /// Call [tearDownHarness] in [tearDown] to reset this state between tests.
  /// [storage] lets a caller inject its OWN [FakeSecureStorage] so it can read
  /// the refresh token before/after a flow (e.g. the logout-wipe assertion).
  /// When omitted, boot constructs a fresh one. Either way the harness installs
  /// EXACTLY ONE [secureStorageProvider] override — passing a storage via
  /// [extraOverrides] would override the provider twice (Riverpod 3.x throws
  /// "Tried to override a provider twice within the same container"). The caller
  /// already holds the instance it passed in, so the storage is reachable for
  /// assertions without a separate accessor.
  ///
  /// [retry] is forwarded to [ProviderScope.retry], which sets the retry
  /// policy for EVERY provider in the harness container. It exists for one
  /// specific need: asserting a FAILURE surface (an error state and its
  /// «retry» affordance).
  ///
  /// Riverpod 3 retries a failed provider automatically — ten times, with
  /// exponential backoff (`ProviderContainer.defaultRetry`: 200 ms doubling
  /// to a 6 400 ms ceiling, ~38 s in total). Until that budget is spent the
  /// provider re-enters `AsyncLoading` between attempts, so `AsyncValue.when`
  /// keeps taking its `loading` branch and the `error` branch never renders.
  /// A test that stubs a failing endpoint and then looks for the error state
  /// therefore finds the LOADING state instead — not because the error state
  /// is broken, but because the framework is still transparently retrying
  /// underneath it.
  ///
  /// Passing `(_, _) => null` disables that auto-retry so the failure surfaces
  /// on the first attempt, letting the test assert the error branch and its
  /// manual «retry» button deterministically and in milliseconds rather than
  /// after a 38-second real-time wait. It changes NOTHING about the app's own
  /// behaviour — only how long the harness waits before observing it.
  ///
  /// DEFAULT = THE PRODUCTION PREDICATE
  /// ----------------------------------
  /// [retry] defaults to [beauticaProviderRetry] — the very predicate
  /// `main.dart` installs on the root scope — so an E2E boot resolves error
  /// paths exactly as the shipped app does. The paragraphs above describe
  /// `ProviderContainer.defaultRetry`, which this harness used to inherit by
  /// defaulting to `null`; that made every flow validate a blanket-retry policy
  /// production had already removed, so a deterministic failure the user would
  /// see as an error screen was silently retried away in test. The E2E tier is
  /// the LAST place that skew should exist — its whole claim is "this is the
  /// real app".
  static Future<GoRouter> boot(
    WidgetTester tester,
    FakeBackend fakeBackend, {
    FakeSecureStorage? storage,
    List<Object> extraOverrides = const <Object>[],
    Duration? Function(int retryCount, Object error)? retry =
        beauticaProviderRetry,
  }) async {
    // ── SHARED BOOT POLICY — ONE definition, BOTH E2E tiers ─────────────────
    //
    // Overflow guard, off-screen-tap guard
    // (`WidgetController.hitTestWarningShouldBeFatal`), text-input mock
    // registration, timezone database, and the splash-gate priming all live in
    // `e2e_boot_policy.dart` and are applied by this ONE call. They used to be
    // inlined here AND hand-mirrored in
    // `integration_test/patrol/support/patrol_harness.dart` — which drifted
    // (the tap guard reached only this tier), so the whole patrol tier kept the
    // flake class the guard removes. Add new cross-tier policy THERE, never
    // here, or the mirror comes back. See that file's header for the full
    // rationale and for what is deliberately NOT shared.
    applyE2eBootPolicy(tester);

    final effectiveStorage = storage ?? FakeSecureStorage();

    await tester.pumpWidget(
      ProviderScope(
        retry: retry,
        // ProviderScope.overrides accepts List<Override>; we cast so callers
        // can pass a plain list without importing the internal Override type.
        // ignore: avoid_dynamic_calls
        overrides: <Object>[
          ...e2eProviderOverrides(
            fakeBackend: fakeBackend,
            storage: effectiveStorage,
          ),
          ...extraOverrides,
        ].cast(),
        child: const E2eHarnessApp(),
      ),
    );

    // Allow the splash screen to resolve and the auth guard to redirect to
    // /login (unauthenticated cold start) or the role-appropriate home.
    // Bounded by [settleTimeout] (Fix #2) so a hang here cannot wedge the
    // shared aggregated isolate.
    await settle(tester);

    // AGGREGATION FIX (Phase 17.3) — unmount the app tree at tearDown.
    //
    // all_tests.dart runs all 5 E2E flows in ONE isolate via
    // group('<flow>', <flow>.main). flutter_test does NOT fully reset the
    // persistent overlay between testWidgets in a shared isolate (the suites
    // used to run as 5 separate processes). Without an explicit unmount, the
    // prior test's MaterialApp.router / Navigator / overlay entries survive
    // into the next test, overlaying the fresh /login screen — the
    // login_submit button ends up under RenderOffstage/RenderAbsorbPointer,
    // tester.tap() "would not hit test", _submit() never runs, and
    // fb.loginCalls stays 0 (failing the 2nd/3rd login flow).
    //
    // addTearDown runs LIFO, BEFORE the flow's own
    // tearDown(AppHarness.tearDownHarness), so it fully unmounts the current
    // MaterialApp.router (Navigator + all overlay entries) and disposes the
    // ProviderScope/keepAlive router container before the next test boots.
    addTearDown(() async {
      // RESILIENT UNMOUNT (Phase 17.3 cascade guard) — when a test TIMES OUT,
      // its in-flight pump is interrupted and the shared LiveTest binding can be
      // left mid-frame. An unguarded pumpWidget/pumpAndSettle here then collides
      // with that interrupted pump and corrupts the binding for EVERY subsequent
      // test in the isolate — one per-test timeout cascades into 50 failures.
      // Guarding the unmount localises the blast radius: a single timed-out test
      // fails exactly ONE test, and the next test still boots from a clean tree.
      try {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      } catch (_) {
        // Binding was left in a bad state by an interrupted/timed-out test —
        // swallow so this teardown cannot turn one failure into a suite wipe.
      }
    });

    // RC2 — read the live GoRouter from the ProviderScope container. The
    // container is accessible from the ProviderScope element's context.
    // appRouterProvider is keepAlive: true and is guaranteed to be
    // initialized after pumpAndSettle() because _HarnessApp calls
    // ref.watch(appRouterProvider) in its build().
    final container = ProviderScope.containerOf(
      tester.element(find.byType(E2eHarnessApp)),
    );
    return container.read(appRouterProvider);
  }

  // ── Router location (push-safe) ──────────────────────────────────────────

  /// Resolves the router's current logical location, correctly accounting for
  /// an [ImperativeRouteMatch] — the match kind [GoRouter.push] (i.e.
  /// `context.push`) produces. go_router 17.x DELIBERATELY EXCLUDES
  /// [ImperativeRouteMatch] entries from both [RouteMatchList.uri] and
  /// [RouteMatchList.fullPath] (see go_router's `match.dart`,
  /// `RouteMatchList.uri` doc comment + `_generateFullPath`'s
  /// `match is! ImperativeRouteMatch` filter). So reading either directly
  /// after a push keeps reporting the PRE-push location FOREVER, even though
  /// the push succeeded and the new screen is mounted.
  ///
  /// This is not hypothetical: it shipped twice — `ab34c0a` (nav-bar-hide)
  /// and again in `master_bookings_flow_test.dart` /
  /// `logout_flow_test.dart` (the latter is also the true root cause of the
  /// long-standing "btn-menu-master not navigating" backlog MEDIUM, which was
  /// never a real navigation regression). `scripts/forbid_naive_router_location.sh`
  /// now gates every other direct `.uri` / `.fullPath` read in `test/` and
  /// `integration_test/` — route through THIS helper instead.
  ///
  /// Resolution: if the last top-level match is an [ImperativeRouteMatch],
  /// read the location from ITS OWN nested `matches.uri` (the match list
  /// produced by that specific push); otherwise (a plain redirect outcome —
  /// no push on top) [RouteMatchList.uri] is already correct.
  ///
  /// NOTE: flows that push ON TOP OF a `StatefulShellRoute` branch (the
  /// CLIENT shell) resolve location differently —
  /// `currentConfiguration.matches.last.matchedLocation` walks the shell's
  /// own leaf chain and is intentionally NOT this helper (see
  /// `salon_booking_flow_test.dart` / `service_preselection_flow_test.dart`
  /// for that variant and why it diverges).
  static String location(GoRouter router) {
    final RouteMatchList configuration =
        router.routerDelegate.currentConfiguration;
    final RouteMatchBase? lastMatch = configuration.matches.isEmpty
        ? null
        : configuration.matches.last;
    final Uri uri = lastMatch is ImperativeRouteMatch
        ? lastMatch.matches.uri
        : configuration.uri;
    return uri.toString();
  }

  /// Resolves the current location for a flow that PUSHES ON TOP OF a
  /// [StatefulShellRoute] branch (the CLIENT 5-tab shell).
  ///
  /// [location] is the wrong resolver there: every route reached after the
  /// initial branch root (a salon/master profile, the booking sub-routes) is
  /// pushed imperatively ONTO the shell, so `configuration.uri` keeps
  /// reporting the BRANCH ROOT (`/search`) rather than the displayed screen,
  /// and [location]'s own `ImperativeRouteMatch` unwrap resolves the push's
  /// nested match list, not the shell's leaf chain.
  /// `matches.last.matchedLocation` is what go_router's own
  /// [ImperativeRouteMatch] uses internally and is always the full absolute
  /// path (see go_router's `match.dart`), so it reflects the real current
  /// screen regardless of shell nesting.
  ///
  /// Collapsed here (2026-07-22 audit) from three hand-copied duplicates in
  /// `salon_booking_flow_test.dart`, `service_preselection_flow_test.dart` and
  /// `independent_multi_service_booking_flow_test.dart`, so the shell variant
  /// gets the same [expectLocation] matching rule as everything else instead
  /// of drifting on its own.
  static String shellLocation(GoRouter router) {
    // router-location-ok: the shell-push resolver deliberately reads the leaf
    // match chain; see this method's doc comment for why `.uri` is wrong here.
    return router
        .routerDelegate
        .currentConfiguration
        .matches
        .last
        .matchedLocation;
  }

  /// Resolves the current location for a route reached via `context.push`
  /// that is NESTED under the currently-active [StatefulShellRoute] branch's
  /// OWN route tree — e.g. `/search/results`, declared in app_router.dart as
  /// a child `GoRoute` of `/search` inside the CLIENT shell's search branch
  /// ("Nested under the search branch so it pushes onto that branch's
  /// navigator"), as opposed to a route declared entirely outside the shell.
  ///
  /// Neither [location] nor [shellLocation] resolves this shape:
  ///  * [location]'s only special case is "the TOP-level match IS an
  ///    [ImperativeRouteMatch]". But [RouteMatchList.push] (go_router's
  ///    `match.dart`, `_createNewMatchUntilIncompatible`) recurses INTO the
  ///    existing top-level [ShellRouteMatch] — rather than appending a new
  ///    top-level entry — whenever the freshly-matched target's own top
  ///    segment is the SAME shell route already active. So `matches.last`
  ///    stays a [ShellRouteMatch], the special case never fires, and
  ///    [location] falls back to the stale pre-push `configuration.uri`
  ///    (confirmed empirically: it keeps reading `/search` after a push to
  ///    `/search/results`).
  ///  * [shellLocation] reads `matches.last.matchedLocation` — but
  ///    [ShellRouteMatch.copyWith] (what `push` uses to graft the new leaf
  ///    in) never updates `matchedLocation`; it stays whatever it was when
  ///    THIS [ShellRouteMatch] was first created (the branch's own root), so
  ///    it is equally stale for this shape (also confirmed empirically —
  ///    both resolvers report `/search`, never `/search/results`).
  ///
  /// This mirrors go_router's OWN internal recovery for exactly this shape
  /// (`GoRouteInformationParser.restoreRouteInformation`): drill through
  /// [ShellRouteMatch.matches] until an [ImperativeRouteMatch] surfaces, then
  /// read ITS OWN freshly-matched nested `RouteMatchList.uri` — which [push]
  /// DOES set correctly, it is only the outer wrapper(s) that go stale.
  /// Falls back to [location] if no nested [ImperativeRouteMatch] is found
  /// (a plain, non-nested case — behaves identically to [location] there).
  static String nestedPushLocation(GoRouter router) {
    RouteMatchBase match =
        router.routerDelegate.currentConfiguration.matches.last;
    while (match is! ImperativeRouteMatch) {
      if (match is ShellRouteMatch && match.matches.isNotEmpty) {
        match = match.matches.last;
      } else {
        break;
      }
    }
    if (match case final ImperativeRouteMatch imperative) {
      // router-location-ok: reading the resolved push's OWN nested match
      // list (not the stale outer `currentConfiguration.uri`) is exactly
      // what this drill-down resolver exists to do.
      return imperative.matches.uri.toString();
    }
    return location(router);
  }

  /// [expectLocation] for a route reached via [nestedPushLocation]'s shape —
  /// a `context.push` nested under the currently-active shell branch's own
  /// route tree (see [nestedPushLocation]'s doc comment).
  static void expectNestedPushLocation(GoRouter router, String expected) =>
      _expectPath(
        nestedPushLocation(router),
        expected,
        'AppHarness.expectNestedPushLocation',
      );

  /// Convenience assertion built on [location]. See [expectShellLocation] for
  /// the [StatefulShellRoute] variant.
  ///
  /// MATCHING IS SEGMENT-AWARE, NOT `startsWith` (2026-07-22 audit)
  /// --------------------------------------------------------------
  /// This helper used to assert `startsWith(expected)`, and 26 hand-copied
  /// duplicates of it across `integration_test/` did the same. A raw prefix
  /// match is far weaker than it reads:
  ///   • `expectLocation(router, RouteNames.home)` reduces to
  ///     `startsWith('/')` — TRUE for every one of the ~59 routes in the app.
  ///     Two flows shipped that exact assertion believing it pinned a landing
  ///     screen.
  ///   • `expectLocation(router, '/booking')` silently accepts
  ///     `/bookings/abc` — a different screen in a different shell branch.
  ///
  /// The rule is the one production already uses at
  /// `lib/routing/auth_redirect.dart:291`: equal, or followed by a `/`
  /// separator. A `?` boundary is accepted too, because [location] returns the
  /// full URI including any query string (e.g. `/invite/accept?token=…`),
  /// which `matchedLocation` never carries.
  ///
  /// Flows that need something else (exact equality against a location WITH a
  /// query, `isNot(...)`, etc.) should call [location] directly.
  static void expectLocation(GoRouter router, String expected) =>
      _expectPath(location(router), expected, 'AppHarness.expectLocation');

  /// [expectLocation] for flows that push on top of a [StatefulShellRoute]
  /// branch — same matching rule, resolved via [shellLocation].
  static void expectShellLocation(GoRouter router, String expected) =>
      _expectPath(
        shellLocation(router),
        expected,
        'AppHarness.expectShellLocation',
      );

  /// Shared segment-aware comparison behind [expectLocation] /
  /// [expectShellLocation].
  static void _expectPath(String current, String expected, String caller) {
    // `'/'` can never be a meaningful expectation: EVERY location starts with
    // it, so the assertion is unfalsifiable. Fail loudly at the call site
    // rather than passing vacuously. Assert an exact landing path instead
    // (`RouteNames.clientHome`, `RouteNames.masterProfile`, …); if you really
    // do mean the literal `/` route, use `expect(AppHarness.location(router),
    // equals(RouteNames.home))`.
    expect(
      expected,
      isNot('/'),
      reason:
          '$caller was handed "/" — every location in the app satisfies that, '
          'so the assertion can never fail. Assert the concrete landing route '
          'instead, or use expect(AppHarness.location(router), equals("/")).',
    );

    final bool matches =
        current == expected ||
        current.startsWith('$expected/') ||
        current.startsWith('$expected?');

    expect(
      matches,
      isTrue,
      reason:
          'Expected router location to be $expected (or a sub-route of it), '
          'got $current',
    );
  }

  // ── Tear-down ─────────────────────────────────────────────────────────────

  /// Undoes the per-test half of the shared boot policy — see
  /// [resetE2eBootPolicy] for the full rationale (splash-gate reset + the
  /// host-side GL settle delay the CI emulator needs between relaunches).
  ///
  /// Must be called in [tearDown] in every test file that uses [boot], so the
  /// splash-gate override does not leak into subsequent tests. Idempotent.
  ///
  /// Delegates rather than reimplements: the patrol tier's own
  /// `PatrolHarness.tearDownHarness` calls the SAME function, so the two can no
  /// longer drift apart (they previously carried two hand-copied bodies).
  static Future<void> tearDownHarness() => resetE2eBootPolicy();

  // ── Text-field introspection ──────────────────────────────────────────────

  /// The live text currently held by the [EditableText] under [fieldKey], or
  /// `null` when no such field is mounted.
  ///
  /// Reads [EditableTextState.textEditingValue] rather than the widget's
  /// controller so it reflects what the ENGINE-side editing state actually
  /// committed — which is exactly what silently diverges from the value passed
  /// to `tester.enterText` when the text-input mock is unregistered (see the
  /// `testTextInput.register()` comment in [boot]).
  ///
  /// The project's field keys sit on composite widgets (e.g.
  /// `NeumorphicTextField`), so the [EditableText] is looked up as a
  /// DESCENDANT, not as the keyed widget itself.
  static String? _fieldText(WidgetTester tester, String fieldKey) {
    final Finder editable = find.descendant(
      of: find.byKey(ValueKey<String>(fieldKey)),
      matching: find.byType(EditableText),
    );
    if (editable.evaluate().isEmpty) return null;
    return tester
        .state<EditableTextState>(editable.first)
        .textEditingValue
        .text;
  }

  /// Asserts the field under [fieldKey] actually holds [expected].
  ///
  /// Use immediately after `tester.enterText` on any shared path that must work
  /// in non-debug builds: an unregistered text-input mock makes `enterText` a
  /// SILENT no-op once asserts are stripped, and without this check the failure
  /// only surfaces much later as a misleading tap/navigation assertion.
  static void _expectFieldText(
    WidgetTester tester,
    String fieldKey,
    String expected,
  ) {
    expect(
      _fieldText(tester, fieldKey),
      expected,
      reason:
          'tester.enterText did not land in "$fieldKey". In a non-debug build '
          'this is almost always the unregistered text-input mock: enterText '
          'posts its editing state with client id -1 '
          '(IntegrationTestWidgetsFlutterBinding.registerTestTextInput == '
          'false), and the -1 escape hatch in '
          'TextInput._handleTextInputInvocation lives inside an '
          'assert(() {...}()) block that profile/release STRIPS, so the value '
          'is discarded without error. AppHarness.boot must call '
          'tester.binding.testTextInput.register() — check it is still there.',
    );
  }

  /// Pumps until [FakeBackend.loginCalls] advances past [callsBefore], and
  /// reports whether it did — WITHOUT throwing.
  ///
  /// The non-throwing contract is the point. [pumpUntilCondition] is the right
  /// tool when a missing condition IS the failure, but here a negative result
  /// is a legitimate branch: [loginAs] wants to retry the tap once and, failing
  /// that, report through its own field-aware diagnostic (which names WHY the
  /// submit did not take — dropped `enterText` vs. an absorbed tap). Throwing a
  /// generic "condition never came true" here would pre-empt that far better
  /// message.
  ///
  /// Bounded well under [settleTimeout] — [FakeBackend] serves from memory, so
  /// anything approaching this bound is a genuine "the tap never landed", not
  /// slowness.
  static Future<bool> _pumpUntilLoginDispatched(
    WidgetTester tester,
    FakeBackend fakeBackend,
    int callsBefore, {
    Duration timeout = const Duration(seconds: 5),
    Duration step = const Duration(milliseconds: 50),
  }) async {
    final DateTime deadline = DateTime.now().add(timeout);
    while (fakeBackend.loginCalls == callsBefore) {
      if (DateTime.now().isAfter(deadline)) return false;
      await tester.pump(step);
    }
    return true;
  }

  // ── Convenience: drive the login flow to completion ───────────────────────

  /// Drives the real login form with the fixture email for [role], taps Submit,
  /// and waits for the app to settle on the authenticated home screen.
  ///
  /// Navigation is key-driven (no raw-text tap drivers per policy).
  static Future<void> loginAs(
    WidgetTester tester,
    FakeBackend fakeBackend,
    UserRole role,
  ) async {
    fakeBackend.currentRole = role;

    final email = switch (role) {
      UserRole.client => 'client@beautica.ua',
      UserRole.salonOwner => 'owner@beautica.ua',
      UserRole.independentMaster => 'master@beautica.ua',
      _ => 'master@beautica.ua',
    };

    // Drain any in-flight splash→login redirect / route transition BEFORE
    // touching the form. Flake guard (phase 17.1): boot()'s single pumpAndSettle
    // can return just before the auth-resolution microtask fires the
    // /splash→/login redirect, so without this the form is mid-transition. A tap
    // during a transition lands on the route barrier (RenderAbsorbPointer /
    // RenderOffstage / RenderIgnorePointer in the hit path) and is SWALLOWED, so
    // _submit() never runs (loginCalls stays 0 → "Expected 1, Actual 0").
    // Bounded by [settleTimeout] (Fix #2): a hang here fails ONE test cleanly
    // instead of corrupting the shared isolate's binding mid-frame.
    await settle(tester);

    // READINESS, NOT EXISTENCE (phase 26.x flake fix). `settle` only proves no
    // frame is scheduled — it does NOT prove the login form is mounted. Any
    // change that shifts auth resolution by even one microtask (e.g. adding an
    // interceptor to FakeBackend's Dio, which inserts an extra async hop into
    // every response) can make the settle above return while the router is
    // still on /splash, and the very next `enterText` then fails with
    // "Found 0 widgets with key [<'login_email'>]". Wait on the widgets we are
    // about to drive instead of assuming the settle implied them.
    await pumpUntilFound(
      tester,
      find.byKey(const ValueKey<String>('login_email')),
    );
    await pumpUntilFound(
      tester,
      find.byKey(const ValueKey<String>('login_password')),
    );

    // We should be on the login screen — fill the fields and submit.
    await tester.enterText(
      find.byKey(const ValueKey<String>('login_email')),
      email,
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('login_password')),
      'Secret1234',
    );
    await settle(tester);

    // TEXT-INJECTION GUARD — assert the fields ACTUALLY took the text before
    // blaming the tap. `tester.enterText` posts its editing state with the
    // connection id `TestTextInput._client ?? -1`, and
    // `IntegrationTestWidgetsFlutterBinding.registerTestTextInput` is `false`,
    // so the id is `-1` unless `boot()` registered the mock. The `-1` escape
    // hatch in `TextInput._handleTextInputInvocation` sits inside an
    // `assert(() {...}())`, which profile/release STRIPS — so in a non-debug
    // build the value is silently discarded and every field stays empty.
    //
    // This assertion converts that silent drop into a one-line diagnosis AT THE
    // CAUSE, in any build mode. It is the regression test for the
    // `testTextInput.register()` call in [boot] (see its comment).
    _expectFieldText(tester, 'login_email', email);
    _expectFieldText(tester, 'login_password', 'Secret1234');

    // Ensure the submit button is on-screen + interactive before tapping
    // (best-effort: only scrolls if the form has a Scrollable ancestor).
    final Finder submit = find.byKey(const ValueKey<String>('login_submit'));

    // Existence first — otherwise `ensureVisible` throws "Found 0 widgets" and
    // the bare `catch (_)` below SWALLOWS it, deferring the failure to the tap
    // where it reads as an unrelated absorption problem.
    await pumpUntilFound(tester, submit);
    try {
      await tester.ensureVisible(submit);
      await settle(tester);
    } catch (_) {
      // No scrollable ancestor / already fully visible — nothing to do.
    }

    // …then INTERACTABILITY. `hitTestable()` is the readiness condition the
    // plain finder cannot express: during an in-flight route transition the
    // login subtree is mounted but sits under a RenderAbsorbPointer /
    // RenderIgnorePointer / RenderOffstage, so it EXISTS while every tap on it
    // is swallowed (see the flake-guard comment at the top of this method).
    // Waiting on `.hitTestable()` — the idiom already used across the
    // client_search / public_salon / service_duplicate flows — waits for the
    // barrier to lift rather than retrying the tap and hoping.
    await pumpUntilFound(tester, submit.hitTestable());

    // Tap submit and confirm it actually triggered _submit(). If the tap was
    // absorbed (loginCalls did not advance), settle and retry ONCE, then fail
    // loudly AT THE CAUSE rather than as a confusing downstream navigation
    // assertion. loginCalls is captured relative to its prior value so repeat
    // loginAs() calls within one test stay correct.
    final int callsBefore = fakeBackend.loginCalls;
    await tester.tap(submit);

    // WAIT ON THE OBSERVABLE, NOT A PUMP COUNT.
    //
    // This used to be a bare `pump(); pump();` followed by
    // `if (loginCalls == callsBefore) { retry }` — i.e. it treated "two frames
    // elapsed" as "the request has definitely been dispatched". That is the
    // same existence-vs-readiness assumption as the finders above, just
    // expressed on a frame count instead of a widget, and it is FALSE the
    // moment anything adds an async hop to the Dio pipeline. Installing
    // ErrorMapperInterceptor on FakeBackend's Dio does exactly that: even an
    // onError-only interceptor is walked by Dio's request chain, so the adapter
    // handler (which increments [FakeBackend.loginCalls]) now lands one
    // microtask later than it used to.
    //
    // The concrete failure that produced: tap #1 SUCCEEDS, `loginCalls` has not
    // caught up after two pumps, the guard concludes "absorbed" and enters the
    // retry branch — but its `settle()` lets the login complete and the router
    // navigate to the authenticated home, so `login_submit` is gone and the
    // retry `tap()` dies with "Found 0 widgets with key [<'login_submit'>]".
    // A green login was reported as an absorbed tap.
    //
    // Polling the counter is not a sleep and not a retry mask: `loginCalls` IS
    // the condition the guard wants to know about, and the bound is short
    // (FakeBackend answers from memory in well under a frame). The retry below
    // is now reachable ONLY when the call genuinely never happened.
    final bool dispatched = await _pumpUntilLoginDispatched(
      tester,
      fakeBackend,
      callsBefore,
    );
    if (!dispatched) {
      await settle(tester);
      // Re-check interactability before tapping again. Without this the retry
      // can fire at a moment when the login screen has already been replaced,
      // turning a recoverable situation into a raw "Found 0 widgets" crash that
      // buries the honest diagnostic below.
      if (submit.hitTestable().evaluate().isNotEmpty) {
        await tester.tap(submit);
        // Result deliberately not captured: the expect() below reads
        // `loginCalls` directly and is the single authority on the outcome.
        await _pumpUntilLoginDispatched(tester, fakeBackend, callsBefore);
      }
    }
    // DIAGNOSE HONESTLY. The pre-2026-07-22 version of this guard asserted
    // "the button was absorbed by an in-flight overlay/route transition"
    // unconditionally — which was FLATLY WRONG on the profile drive (the real
    // cause was silently-dropped `enterText`, see [boot]) and cost a full
    // investigation. Re-read the fields AT THE POINT OF FAILURE and only claim
    // absorption when they are actually populated; otherwise say so plainly.
    // A guard that confidently states the wrong cause is worse than one that
    // admits it does not know.
    final String? emailAtFailure = _fieldText(tester, 'login_email');
    final String? passwordAtFailure = _fieldText(tester, 'login_password');
    final bool fieldsPopulated =
        (emailAtFailure != null && emailAtFailure.isNotEmpty) &&
        (passwordAtFailure != null && passwordAtFailure.isNotEmpty);
    expect(
      fakeBackend.loginCalls,
      greaterThan(callsBefore),
      reason: fieldsPopulated
          ? 'login_submit tap did not trigger _submit(), and BOTH credential '
                'fields are populated at the point of failure '
                '(login_email="$emailAtFailure") — so the most likely cause is '
                'the button being absorbed by an in-flight overlay/route '
                'transition (see the app_harness flake guard).'
          : 'login_submit tap did not trigger _submit(), and the credential '
                'fields are NOT populated at the point of failure '
                '(login_email=${emailAtFailure == null ? '<not mounted>' : '"$emailAtFailure"'}, '
                'login_password=${passwordAtFailure == null ? '<not mounted>' : '${passwordAtFailure.length} chars'}) '
                '— LoginScreen._submit() bailed at its own empty-field '
                'validation. This is NOT tap absorption. Either the screen was '
                'remounted between enterText and the tap, or the injected text '
                'was dropped (see the testTextInput.register() comment in '
                'AppHarness.boot).',
    );

    // Pump until all auth microtasks and router redirects settle:
    //   1. pump()     — tap event is processed; _submit() suspends at await login()
    //   2. pump()     — login() HTTP fake-backend call resolves (microtask),
    //                    authProvider → AsyncData(Authenticated), AuthRefreshNotifier
    //                    fires, GoRouter redirect runs, router navigates
    //   3. pump()     — Router widget rebuilds with new route; new screen mounts;
    //                    masterProfileProvider fetch fires (for INDEPENDENT_MASTER)
    //   4–5. pump()   — masterProfileProvider resolves; AnimationController.forward()
    //                    starts the 1100 ms entrance animation
    //   pumpAndSettle — advances the fake clock through the full animation duration
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await settle(tester);
  }
}

// The real MaterialApp.router that this harness pumps is [E2eHarnessApp], in
// `e2e_boot_policy.dart`. It used to be a private `_HarnessApp` here plus a
// byte-identical private `_PatrolHarnessApp` in the patrol harness — one more
// strand of the mirror this refactor removed.
