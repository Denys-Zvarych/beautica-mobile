// Shared invariant TAIL for the `ProviderSubscription`-closed crash class
// (mobile-debugger, this track — see `booking_calendar_invalidation.dart`'s
// FIX A/B doc for the full, citation-backed mechanism).
//
// THE RECIPE THIS HARNESS SHARES (steps 3-7 of 7)
// --------------------------------------------------
//   1. Pin key K — visit it so the family member builds (LOCAL to the
//      caller: which screen, which key type).
//   2. Swap away — the SAME still-mounted screen re-keys its OWN `ref.watch`
//      to a DIFFERENT key via local mutable state (a rail tap, a sort
//      toggle, a week-nav arrow) — K's element drops to zero listeners,
//      alive only via its own keepAlive link/timer (LOCAL to the caller).
//   3. Cover — push an opaque route on top (SHARED — this file, via the
//      `router` argument).
//   4. Invalidate — run the exact production invalidation that touches K,
//      through a real `WidgetRef` (SHARED trigger point, caller supplies
//      WHICH invalidation via [invalidate]).
//   5. Pop back (SHARED — this file).
//   6. Re-establish the watch on K — swap the local key back (LOCAL to the
//      caller: a different rail tap / sort toggle / week-nav arrow, so
//      caller supplies it via [reestablishWatch]).
//   7. Assert NO `FlutterError` was thrown, and K resolves to a data/empty
//      state within a BOUNDED pump budget — never `pumpAndSettle` (SHARED —
//      this file).
//
// WHY steps 1-2 and 6 stay OUT of this file
// -------------------------------------------
// They are genuinely different per family: a booking day is pinned by
// visiting it then tapping a DIFFERENT rail chip (plus the real 220ms
// debounce); a review sort is pinned by loading the default sort then
// tapping the sort icon and picking a different one; a schedule week is
// pinned by viewing it then tapping the week-nav arrow. Forcing these into
// one shared shape would produce a lowest-common-denominator interface that
// fights every caller — see `integration_test/support/reschedule_assertions
// .dart`'s identical "share the assertion tail, not the whole flow" scoping
// decision, which this file mirrors.
//
// NEVER `pumpAndSettle` — see [expectKeepAlivePinRaceClosed]'s own doc.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'pump_app.dart';

/// Runs steps 3-7 of the keepAlive pin-race recipe (see file header) and
/// asserts the race is closed.
///
/// Callers are expected to have ALREADY run steps 1-2 (pin key K, swap away
/// so K becomes pinned-but-unwatched) and pushed nothing further — this
/// function itself performs the COVER (step 3), so [router]'s current top
/// route must still be the screen holding K when this is called.
///
/// - [invalidate]: performs the EXACT production invalidation that touches
///   K, through a real `WidgetRef` reached from the covering route (mirrors
///   `booking_calendar_invalidation.dart`'s own extracted-function precedent
///   — never a hand-copied approximation of the real call). Typically a
///   `tester.tap` on a `Consumer`+button wired to the real function.
/// - [reestablishWatch]: re-keys the screen back onto K (step 6) — a rail
///   tap, a sort-sheet selection, a week-nav arrow — AFTER this function has
///   popped the cover route.
/// - [loadingFinder]: matches the SKELETON/shimmer state for K (never
///   settles — see the `never pumpAndSettle` note below).
/// - [resolvedFinder]: matches K's resolved (data or empty) state once the
///   race has NOT struck.
/// - [timeout]: bounded budget for [loadingFinder] to disappear — passed
///   straight through to `pumpUntilGone`.
///
/// NEVER `pumpAndSettle`: the skeleton/shimmer states this recipe exercises
/// use a repeating animation that never reaches quiescence, so
/// `pumpAndSettle` would hang. `pumpUntilGone`/`pumpUntilFound`
/// (`test/helpers/pump_app.dart`) poll in bounded steps instead — the "never
/// pumpAndSettle, but still bounded" shape this recipe requires throughout.
Future<void> expectKeepAlivePinRaceClosed(
  WidgetTester tester,
  GoRouter router, {
  required String coverRouteKey,
  required FutureOr<void> Function() invalidate,
  required FutureOr<void> Function() reestablishWatch,
  required Finder loadingFinder,
  required Finder resolvedFinder,
  Duration timeout = const Duration(seconds: 10),
}) async {
  // --- step 3: cover with an opaque route -----------------------------
  unawaited(router.push(coverRouteKey));
  await tester.pumpAndSettle();

  // --- step 4: the EXACT production invalidation ----------------------
  final FutureOr<void> invalidateResult = invalidate();
  if (invalidateResult is Future<void>) await invalidateResult;
  await tester.pump();

  // --- step 5: pop back --------------------------------------------------
  router.pop();
  await tester.pump();

  // --- step 6: re-establish the watch on K --------------------------------
  final FutureOr<void> reestablishResult = reestablishWatch();
  if (reestablishResult is Future<void>) await reestablishResult;

  // --- step 7: bounded budget, NEVER pumpAndSettle ------------------------
  await tester.pumpUntilGone(loadingFinder, timeout: timeout);

  expect(
    tester.takeException(),
    isNull,
    reason:
        'THE DEFECT: a bare invalidate on a pinned-but-unwatched key used to '
        'race Riverpod\'s own disposal scheduler and throw "Bad state: '
        'ProviderSubscription.read on a subscription that was closed" right '
        'here',
  );
  expect(
    resolvedFinder,
    findsOneWidget,
    reason:
        'the key must resolve to a real state (data or empty) — a stuck '
        'skeleton is the SAME defect wearing a different costume (silently '
        'caught by the per-Element error boundary)',
  );
  expect(loadingFinder, findsNothing);
}
