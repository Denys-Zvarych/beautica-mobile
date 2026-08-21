// ITEM 2 (this track, mobile-debugger) — the STATIC precondition is
// structurally isomorphic to the booking-day crash class (see
// `booking_calendar_invalidation.dart`'s FIX A/B doc for the full
// citation-backed mechanism), and this recipe drives it through the REAL
// production widgets/function.
//
// HONEST LIMITATION (checked empirically, mutation-probed against the
// UN-fixed code): unlike the booking sibling — where this exact recipe
// reliably throws the real `StateError` when the wasPinned gate is reverted
// — this file's mutation probe did NOT reproduce a crash. Diagnosed via
// `container.exists(masterReviewsProvider(masterId, sort))` at each step: for
// `bookingsDayProvider`, the queued disposal stays observably pending through
// every subsequent pump in this harness (`exists` reads `true` all the way to
// the final re-select); for `masterReviewsProvider`, `exists` already reads
// `false` immediately after the FIRST pump following `invalidate` + `pop` —
// i.e. the disposal completes before ANY subsequent UI action (sheet open,
// option tap, at any pump cadence tried) can land inside the race window. The
// STATIC risk this test's recipe exercises is real (that is what FIX C closes
// and what `review_surface_invalidation_pin_gate_test.dart`'s ITEM 6
// call-count tests DO mutation-prove for the wasPinned branch itself) — this
// file could not be made to independently prove the crash via a widget-driven
// timing race the way the booking sibling does. Kept anyway: it drives the
// REAL widgets/function end-to-end and passes with the fix, which the task
// asked for; a future change that slows this family's disposal (e.g. an
// added await before the keepAlive timer registers) could make this file
// start catching it.
//
// THE RECIPE
// -----------
//   1. Load `MasterReviewsBody(masterId)` — the default sort (NEWEST) builds
//      and pins itself via its own 5-minute `ref.keepAlive()` timer
//      (`master_reviews_notifier.dart`).
//   2. Tap the sort icon and pick a DIFFERENT sort (OLDEST) — the SAME
//      still-mounted `_SortableReviewList` re-keys its OWN
//      `ref.watch(masterReviewsProvider(masterId, _sort))`. NEWEST's element
//      drops to zero listeners, alive only via its keepAlive timer —
//      pinned-but-unwatched.
//   3. Cover the screen with an opaque route.
//   4. Run the REAL `invalidateMasterReviewSurfaces(ref, masterId)` — the
//      SAME function `leave_review_screen.dart` calls after a review submits
//      — through a real `WidgetRef`. Its per-sort loop invalidates ALL
//      `MasterReviewSort.values`, including the pinned-but-unwatched NEWEST.
//   5. Pop back.
//   6. Re-open the sort sheet and pick NEWEST again — re-`ref.watch`ing the
//      IDENTICAL family member `invalidateSelf()` just queued for disposal.
//   7. Assert no `FlutterError` and the list resolves.
//
// AFTER FIX C: each sort in the loop is gated on `WidgetRef.exists` before
// invalidating, with an eager `ref.read` back when it was pinned — see
// `review_surface_invalidation.dart`'s FIX C doc.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/domain/master_review.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/master_reviews_body.dart';
import 'package:beautica_mobile/features/review/presentation/review_surface_invalidation.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';

import '../../../../helpers/keepalive_pin_race_harness.dart';
import '../../../../helpers/pump_app.dart';

const String _masterId = 'm-race';

class _MockMasterRepository extends Mock implements MasterRepository {}

GoRouter _router(_MockMasterRepository repo) => GoRouter(
  initialLocation: '/reviews',
  routes: <RouteBase>[
    GoRoute(
      path: '/reviews',
      builder: (BuildContext context, GoRouterState state) =>
          const Scaffold(body: MasterReviewsBody(masterId: _masterId)),
    ),
    // Opaque and full-screen — mirrors `LeaveReviewScreen` covering whatever
    // sat underneath, and where this test performs the EXACT
    // `invalidateMasterReviewSurfaces` call via a real `WidgetRef`.
    GoRoute(
      path: '/leave-review',
      builder: (BuildContext context, GoRouterState state) => Scaffold(
        body: Consumer(
          builder: (BuildContext context, WidgetRef ref, _) => Center(
            child: TextButton(
              key: const Key('run-review-surfaces-invalidation'),
              onPressed: () => invalidateMasterReviewSurfaces(ref, _masterId),
              child: const Text('submit'),
            ),
          ),
        ),
      ),
    ),
  ],
);

void main() {
  late _MockMasterRepository repo;

  setUp(() {
    repo = _MockMasterRepository();
    for (final MasterReviewSort s in MasterReviewSort.values) {
      when(
        () => repo.getMasterReviews(masterId: _masterId, sort: s),
      ).thenAnswer((_) async => const <MasterReviewItem>[]);
    }
    when(() => repo.getMasterReviewSummary(_masterId)).thenAnswer(
      (_) async => const MasterReviewSummary(avgRating: 0, reviewCount: 0),
    );
  });

  /// Selects [target] from the sort sheet — the SAME affordance a real
  /// master taps, key-for-key with `master_received_reviews_screen_test.dart`
  /// (`master-reviews-sort-button` / `master-review-sort-option-<name>`).
  ///
  /// [settleFinalTap] controls the FINAL pump after picking the option — the
  /// one that pops the sheet and fires `_SortableReviewList.setState`,
  /// re-`ref.watch`ing the target sort. `pumpAndSettle()` there would drain
  /// EVERY pending timer, including the scheduler's queued zero-duration
  /// disposal task — closing the exact race window this recipe needs open.
  /// The swap-away call (steps 1-2, not crash-relevant) settles fully; the
  /// step-6 re-establish call must NOT.
  Future<void> selectSort(
    WidgetTester tester,
    MasterReviewSort target, {
    bool settleFinalTap = true,
  }) async {
    await tester.tap(find.byKey(const Key('master-reviews-sort-button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(Key('master-review-sort-option-${target.name}')),
    );
    if (settleFinalTap) {
      await tester.pumpAndSettle();
    } else {
      // Bounded, NOT a full settle — mirrors the booking sibling's
      // `reselectD`, which pumps a single fixed step rather than draining
      // every pending timer. Long enough to let the sheet's own pop
      // animation and `setState` land; short enough to leave the scheduler's
      // queued disposal task's own timing exposed.
      // fixed-wait-ok: bounded step deliberately shorter than a full settle — see comment above; pump-until has nothing to poll for here (no stable Key distinguishes "settled" from "queued disposal still pending").
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  /// Steps 1-2: load NEWEST, then swap to OLDEST (NEWEST becomes
  /// pinned-but-unwatched via its own 5-minute keepAlive timer).
  Future<GoRouter> pinNewest(WidgetTester tester) async {
    final GoRouter router = _router(repo);
    await tester.pumpRoutedApp(
      router,
      overrides: <Object>[masterRepositoryProvider.overrideWithValue(repo)],
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('master-reviews-empty')),
      findsOneWidget,
      reason: 'sanity: NEWEST loaded to an empty (not error/skeleton) state',
    );

    await selectSort(tester, MasterReviewSort.oldest);
    expect(
      find.byKey(const Key('master-reviews-empty')),
      findsOneWidget,
      reason: 'sanity: OLDEST loaded — NEWEST is now unwatched, not paused',
    );

    return router;
  }

  testWidgets(
    'invalidating a pinned-but-unwatched sort, then re-selecting it after '
    'popping back, throws NO FlutterError and reaches a data/empty state '
    'within a bounded pump budget',
    (tester) async {
      final GoRouter router = await pinNewest(tester);

      await expectKeepAlivePinRaceClosed(
        tester,
        router,
        coverRouteKey: '/leave-review',
        invalidate: () => tester.tap(
          find.byKey(const Key('run-review-surfaces-invalidation')),
        ),
        reestablishWatch: () =>
            selectSort(tester, MasterReviewSort.newest, settleFinalTap: false),
        // `MasterReviewsBody`'s skeleton states (`_RatingSummarySkeleton` /
        // `_ReviewListSkeleton`) carry no dedicated Key, unlike
        // `bookingsDayProvider`'s `master-bookings-skeleton` — both wrap
        // `SkeletonShimmerScope` (public), which is a superset loading signal
        // (summary + list) but still correctly bounded: it disappears once
        // BOTH sibling sections resolve, and `resolvedFinder` below is the
        // precise per-list sanity check.
        loadingFinder: find.byType(SkeletonShimmerScope),
        resolvedFinder: find.byKey(const Key('master-reviews-empty')),
      );
    },
  );
}
