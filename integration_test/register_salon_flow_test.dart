// Phase 21.3 QA follow-up — E2E: SALON_OWNER registers a new salon end to
// end against a REAL (fake) HTTP boundary.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b)
// ----------------------------------------
// `test/features/salon/presentation/register_salon_screen_test.dart` proves
// the screen + `RegisterSalon` notifier against a hand-rolled two-route
// `GoRouter` with `salonRepositoryProvider` STUBBED by `FakeSalonRepository`
// (an in-memory fake, never a real HTTP round trip) — see that file's own
// `_router()`. That cannot catch:
//   • the REAL route registered in `app_router.dart` (`mySalonsGuard`
//     admitting a real, fully-authenticated SALON_OWNER session at
//     `/salons/register`, reached via the REAL `/salons/mine` hub's own
//     `my_salons_add_cta` CTA — `context.push`, not a test-only stub route);
//   • `SalonCreateDto.toJson()` surviving a REAL wire round trip (the exact
//     body `POST /api/v1/salons` receives);
//   • the full `ref.invalidate(mySalonsProvider)` → hub refetch loop against
//     a REAL `GET /api/v1/salons/mine` — the widget-tier test only proves the
//     invalidation call happened (`_CountingMySalons`), never that the hub
//     SCREEN actually re-renders with the new salon after a real create.
//
// This file drives the real thing: real login → real `/salons/mine` hub →
// real CTA tap → real form fill → real `POST /api/v1/salons` → real pop →
// the new salon rendered on the hub, all without a manual refresh.
//
// NO PATROL FLOW: nothing here touches an OS permission dialog, deep link,
// notification, WebView, or biometric.
//
// AUDIT-FIX CYCLE 3 — mobile-qa MEDIUM regression pin (mid-submit back nav)
// ---------------------------------------------------------------------------
// Cycle 2's own CRITICAL fix (`ref.watch(registerSalonProvider)` in
// `RegisterSalonScreen.build()`) only keeps the provider alive while the
// screen stays MOUNTED. Nothing originally stopped a user backing out (top
// bar icon OR the system back gesture/hardware button) while `POST /salons`
// was still in flight — that unmounts the screen, drops the watch, and
// reproduces the SAME `UnmountedRefException` via a narrower,
// navigation-triggered path. The cycle-3 fix is TWO independent guards:
//   • `PopScope(canPop: !_submitting, ...)` — blocks the SYSTEM back
//     gesture/hardware button.
//   • `_onBack()`'s own `if (_submitting) { ...; return; }` — blocks the
//     top-bar icon's EXPLICIT imperative `context.pop()`.
//
// Both tests below prove `PopScope.canPop: false` does NOT cover an
// imperative `context.pop()` — confirmed independently against this
// project's pinned `go_router: 17.2.3` (`GoRouterDelegate.pop()` calls
// `NavigatorState.pop()` directly — the UNCONDITIONAL pop path, which never
// consults `Route.popDisposition`/`canPop` at all; only `Navigator.maybePop`
// — what a system back gesture drives — does). So the two mechanisms are
// NOT redundant: disabling either one independently reopens exactly ONE of
// the two paths — see each test's own mutation-verification note in the QA
// report.
//
// WHY THIS BELONGS HERE, NOT IN THE WIDGET TIER
// -----------------------------------------------
// The disposal race this pins can only be OPENED by a genuinely suspended
// `await` — `test/features/salon/presentation/register_salon_screen_test
// .dart`'s `FakeSalonRepository.create()` resolves in a single, effectively
// synchronous microtask, so the autoDispose window never opens there (this
// is exactly why the cycle-2 CRITICAL itself was invisible to that file).
// A widget test asserting "back mid-submit does not crash" against that fake
// would be structurally unable to go red — it would pass whether or not the
// screen-side guards existed. These tests hold the REAL `POST /api/v1/salons`
// request open with a `Completer`-gated Dio interceptor (added from the TEST
// side, mirroring `master_bookings_flow_test.dart`'s identical
// "day-scoped skeleton while the first day load is in flight" gate — see
// that file's own header for the precedent), so the back attempt below is
// deterministically mid-flight, not a timing race.

import 'dart:async';

import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/salon/presentation/my_salons_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/register_salon_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

/// The default single-primary-salon fixture (`FakeBackend.mySalons`'
/// `salon-owner-1` row) carries NO `phone` — [RegisterSalonScreen]'s own
/// contact-prefill therefore has nothing to seed, so this flow fills phone
/// itself (required) rather than relying on prefill, keeping the fixture the
/// SAME default every other salon-owner flow in this suite already boots
/// with (`salon_owner_landing_flow_test.dart` etc.) instead of forking one.
const String _newSalonName = 'Салон Місяця';

/// `UaPhoneInputFormatter` reformats the raw digits with spaces as they are
/// typed, so the wire body carries this FORMATTED string, not the raw one
/// entered by [_fillValidForm].
const String _formattedPhone = '+380 50 123 45 67';

/// Real login → real `/salons/mine` hub → real CTA tap → RegisterSalonScreen
/// mounted. Shared by all three tests below.
Future<GoRouter> _openRegisterForm(WidgetTester tester, FakeBackend fb) async {
  final GoRouter router = await AppHarness.boot(tester, fb);

  await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
  // fixed-wait-ok: settles the real async login/route-transition step.
  await tester.pumpAndSettle(const Duration(seconds: 1));

  // Real login lands a SALON_OWNER on their primary salon's shell
  // (`salon_owner_landing_flow_test.dart`), not the hub — navigate to the
  // hub itself first; the CTA tap immediately below is what exercises the
  // REAL in-app push this file exists to cover.
  router.go(RouteNames.mySalons);
  // fixed-wait-ok: settles the real async route-push step.
  await tester.pumpAndSettle(const Duration(seconds: 1));
  expect(find.byType(MySalonsScreen), findsOneWidget);

  await tester.tap(find.byKey(const Key('my_salons_add_cta')));
  await tester.pumpAndSettle();
  expect(
    find.byType(RegisterSalonScreen),
    findsOneWidget,
    reason:
        'the CTA must reach the REAL /salons/register route — a '
        'shadowed/missing literal would silently resolve the dynamic '
        '/salons/:salonId sibling instead',
  );
  return router;
}

/// Fills every required field with a valid value (name, oblast → city-kyiv
/// leaf-of-no-districts, street, building, phone). Instagram is left empty
/// (optional).
Future<void> _fillValidForm(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('salon_name')), _newSalonName);
  await tester.pump();

  await tester.tap(find.byKey(const Key('locality_row_oblast')));
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const ValueKey<String>('locality_picker_tile_oblast-kyiv')),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const Key('locality_row_city')));
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const ValueKey<String>('locality_picker_tile_city-kyiv')),
  );
  await tester.pumpAndSettle();

  await tester.enterText(
    find.byKey(const Key('salon_street')),
    'вул. Хрещатик',
  );
  await tester.pump();
  await tester.enterText(find.byKey(const Key('salon_building')), '5');
  await tester.pump();

  // Required, and NOT prefilled — the default fixture's primary salon
  // carries no phone (see file header).
  await tester.enterText(find.byKey(const Key('salon_phone')), '+380501234567');
  await tester.pump();
}

/// Mutable box a gated interceptor flips to `true` the instant it reaches
/// the request it is about to hold open — the POSITIVE, pollable condition
/// `AppHarness.pumpUntilCondition` waits on below, replacing a guessed fixed
/// wait for "has the tap's async chain reached the interceptor yet".
class _GateReached {
  bool value = false;
}

/// Adds a Dio interceptor (test-side, not `support/fake_backend.dart`'s own
/// routing — mirrors `master_bookings_flow_test.dart`'s identical gate) that
/// holds the first `POST /api/v1/salons` request open until [gate]
/// completes. Lets a test attempt a back-navigation deterministically WHILE
/// the real round trip is still in flight, instead of racing real time.
/// Returns a [_GateReached] box a caller can poll via
/// `AppHarness.pumpUntilCondition` to know the request has actually reached
/// (and suspended on) the gate, rather than guessing how long that takes.
_GateReached _gateCreateSalonRequest(FakeBackend fb, Completer<void> gate) {
  final _GateReached reached = _GateReached();
  fb.dio.interceptors.add(
    InterceptorsWrapper(
      onRequest:
          (RequestOptions options, RequestInterceptorHandler handler) async {
            if (options.method == 'POST' && options.path == '/api/v1/salons') {
              reached.value = true;
              await gate.future;
            }
            handler.next(options);
          },
    ),
  );
  return reached;
}

/// Post-release assertions shared by the two mid-submit-back tests: the
/// gated POST landed exactly once, the screen popped back to the hub, and
/// the hub shows the new salon via the real invalidate → refetch loop — the
/// SAME acceptance criterion the plain happy-path test proves, now proven
/// to SURVIVE a blocked back attempt along the way.
Future<void> _expectSubmitCompletedAndHubRefreshed(
  WidgetTester tester,
  FakeBackend fb,
  int getMySalonsCallsBeforeCreate,
) async {
  expect(fb.createSalonCalls, 1);
  expect(find.byType(RegisterSalonScreen), findsNothing);
  expect(find.byType(MySalonsScreen), findsOneWidget);
  expect(
    fb.getMySalonsCalls,
    greaterThan(getMySalonsCallsBeforeCreate),
    reason:
        'the blocked back attempt must not have prevented submit() from '
        'completing and invalidating mySalonsProvider',
  );
  expect(find.text(_newSalonName), findsOneWidget);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'SALON_OWNER: hub -> «+ Додати салон» -> fill -> submit -> back on the '
    'hub with the new salon visible, no manual refresh',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.salonOwner;
      await _openRegisterForm(tester, fb);
      final int getMySalonsCallsBeforeCreate = fb.getMySalonsCalls;

      await _fillValidForm(tester);

      await tester.tap(find.byKey(const Key('create_salon')));
      await tester.pumpAndSettle();
      // fixed-wait-ok: gives the real async POST round trip + the notifier's
      // invalidate/pop sequence a chance to fully land before asserting.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(
        fb.createSalonCalls,
        1,
        reason: 'a valid submit must reach POST /api/v1/salons exactly once',
      );
      final Map<String, dynamic> body = fb.lastCreateSalonBody!;
      expect(body['name'], _newSalonName);
      expect(body['cityId'], 'city-kyiv');
      expect(body.containsKey('districtId'), isFalse);
      expect(body['street'], 'вул. Хрещатик');
      expect(body['buildingNo'], '5');
      expect(body['phone'], _formattedPhone);

      // Popped back to the hub — the resolved SCREEN TYPE, not merely a
      // matching location string.
      expect(find.byType(RegisterSalonScreen), findsNothing);
      expect(find.byType(MySalonsScreen), findsOneWidget);

      // The hub refetched (ref.invalidate(mySalonsProvider) -> next read) —
      // a real extra GET /api/v1/salons/mine landed, not merely the stale
      // pre-create cache.
      expect(
        fb.getMySalonsCalls,
        greaterThan(getMySalonsCallsBeforeCreate),
        reason:
            'RegisterSalon.submit must invalidate mySalonsProvider so the '
            'hub refetches on its next read — without it the hub would '
            'render the pre-create cached list for the rest of the session',
      );

      // The new salon renders WITHOUT a manual refresh.
      expect(
        find.text(_newSalonName),
        findsOneWidget,
        reason:
            'the new salon must appear on the hub immediately after the pop '
            '— proving the full create -> invalidate -> refetch -> render '
            'loop, not just that the wire call fired',
      );
    },
  );

  testWidgets(
    'a system back gesture mid-submit is BLOCKED by PopScope.canPop — the '
    'screen stays mounted, no UnmountedRefException, and submit still '
    'completes with the hub refreshed once released',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.salonOwner;
      await _openRegisterForm(tester, fb);
      final int getMySalonsCallsBeforeCreate = fb.getMySalonsCalls;
      await _fillValidForm(tester);

      final Completer<void> gate = Completer<void>();
      final _GateReached reached = _gateCreateSalonRequest(fb, gate);

      await tester.tap(find.byKey(const Key('create_salon')));
      // NOT pumpAndSettle — the gated POST never resolves until `gate`
      // completes below, so pumpAndSettle would hang to its timeout.
      // Pump-until-condition on `reached.value` (flipped by the interceptor
      // itself the instant it reaches the held request) instead of a guessed
      // fixed delay — waits exactly as long as the tap's async chain takes to
      // reach the (now-suspended) await inside the gated request, no longer.
      await AppHarness.pumpUntilCondition(
        tester,
        () => reached.value,
        description:
            'the gated POST /api/v1/salons request to reach the interceptor '
            'and suspend on the Completer',
      );

      // Attempt the SYSTEM back gesture / hardware back button while the
      // request is still held open — the same technique already established
      // by `test/features/shell/client_shell_detail_pop_test.dart`'s own
      // "system-back parity" group.
      final bool handled = await tester.binding.handlePopRoute();
      await tester.pump();

      expect(
        handled,
        isTrue,
        reason:
            'PopScope must CONSUME the system back while a submit is in '
            'flight (didPop: false), not let it fall through unhandled',
      );
      expect(
        find.byType(RegisterSalonScreen),
        findsOneWidget,
        reason:
            'canPop:false must block the pop — the screen must stay '
            'mounted while POST /salons is in flight, or the '
            'ref.watch(registerSalonProvider) keep-alive is moot and '
            'submit()\'s post-await ref.invalidate(mySalonsProvider) throws '
            'UnmountedRefException',
      );

      // Release the gate — submit() resumes, and (because the screen is
      // still mounted) ref.invalidate(mySalonsProvider) must complete
      // WITHOUT throwing. An UnmountedRefException here would surface as an
      // uncaught test failure, exactly like the cycle-2 CRITICAL's original
      // repro — no explicit try/catch needed to prove it.
      gate.complete();
      // Pump-until-condition on the REAL terminal state (the screen popped)
      // instead of a guessed fixed delay — `find.byType(RegisterSalonScreen)`
      // is UNAMBIGUOUS, unlike `find.text(_newSalonName)`: that finder also
      // matches the `salon_name` field's own still-mounted `EditableText`
      // (flutter_test's text finder matches EditableText content, not just
      // `Text` widgets) for as long as RegisterSalonScreen itself is still
      // on screen — polling on it would report "found" on the very first
      // check, before the pop/refetch chain ever ran (caught by actually
      // running this test, not assumed). Once the screen is confirmed gone,
      // a plain pumpAndSettle is safe: MySalonsScreen carries no
      // perpetually-repeating shimmer here (unlike the day-scoped bookings
      // skeleton elsewhere in this suite), so the refetch settles normally.
      await AppHarness.pumpUntilGone(tester, find.byType(RegisterSalonScreen));
      await tester.pumpAndSettle();

      await _expectSubmitCompletedAndHubRefreshed(
        tester,
        fb,
        getMySalonsCallsBeforeCreate,
      );
    },
  );

  testWidgets(
    'a top-bar back-icon tap mid-submit is BLOCKED by _onBack\'s own guard '
    '(PopScope.canPop does NOT cover an imperative context.pop()) — the '
    'screen stays mounted, no UnmountedRefException, and submit still '
    'completes with the hub refreshed once released',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.salonOwner;
      await _openRegisterForm(tester, fb);
      final int getMySalonsCallsBeforeCreate = fb.getMySalonsCalls;
      await _fillValidForm(tester);

      final Completer<void> gate = Completer<void>();
      final _GateReached reached = _gateCreateSalonRequest(fb, gate);

      await tester.tap(find.byKey(const Key('create_salon')));
      // Pump-until-condition, not a guessed fixed delay — see the system-back
      // test's identical use of this idiom for the full rationale.
      await AppHarness.pumpUntilCondition(
        tester,
        () => reached.value,
        description:
            'the gated POST /api/v1/salons request to reach the interceptor '
            'and suspend on the Completer',
      );

      // The top-bar back icon (SectionScaffold's NeumorphicIconButton) has
      // no dedicated Key on this screen (RegisterSalonScreen never passes
      // `backKey:`) — adding one would be a `lib/` edit outside this task's
      // scope. `NeumorphicIconButton` is not used anywhere else in this
      // screen's tree (VelvetField/LocalityCascade never render one), so
      // `find.byType` is unambiguous here — the established fallback per
      // this suite's own "Key first, byType second" convention.
      expect(find.byType(NeumorphicIconButton), findsOneWidget);
      await tester.tap(find.byType(NeumorphicIconButton));
      await tester.pump();

      expect(
        find.byType(RegisterSalonScreen),
        findsOneWidget,
        reason:
            '_onBack\'s own `if (_submitting) return;` guard must block the '
            'imperative context.pop() while POST /salons is in flight — '
            'PopScope.canPop does not cover this path at all (go_router '
            "17.2.3's GoRouterDelegate.pop() calls NavigatorState.pop() "
            'directly, which never consults Route.popDisposition/canPop — '
            'only Navigator.maybePop, driven by the system back gesture, '
            'does)',
      );

      // Release the gate — submit() resumes, and (because the screen is
      // still mounted) ref.invalidate(mySalonsProvider) must complete
      // WITHOUT throwing.
      gate.complete();
      // Pump-until-condition on the REAL terminal state (the screen popped)
      // instead of a guessed fixed delay — `find.byType(RegisterSalonScreen)`
      // is UNAMBIGUOUS, unlike `find.text(_newSalonName)`: that finder also
      // matches the `salon_name` field's own still-mounted `EditableText`
      // (flutter_test's text finder matches EditableText content, not just
      // `Text` widgets) for as long as RegisterSalonScreen itself is still
      // on screen — polling on it would report "found" on the very first
      // check, before the pop/refetch chain ever ran (caught by actually
      // running this test, not assumed). Once the screen is confirmed gone,
      // a plain pumpAndSettle is safe: MySalonsScreen carries no
      // perpetually-repeating shimmer here (unlike the day-scoped bookings
      // skeleton elsewhere in this suite), so the refetch settles normally.
      await AppHarness.pumpUntilGone(tester, find.byType(RegisterSalonScreen));
      await tester.pumpAndSettle();

      await _expectSubmitCompletedAndHubRefreshed(
        tester,
        fb,
        getMySalonsCallsBeforeCreate,
      );
    },
  );
}
