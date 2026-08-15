// mobile-qa MEDIUM regression guard (2026-08-12) — the TTL-pin contract
// itself, which nothing previously pinned.
//
// THE BUG (found while auditing the F3 short-circuit fix): the cache-hit
// short-circuit in `EffectiveScheduleNotifier.build` returned the cached page
// WITHOUT calling `ref.keepAlive()` — only the real-fetch success path did.
// Riverpod releases a build's own `keepAlive()` link the instant that build
// is superseded by the next one, so a rebuild that took the short-circuit
// finished with ZERO active pins. If nothing was watching once that build's
// own listener went away, Riverpod's real autoDispose eviction check (a
// genuine `Timer(Duration.zero, ...)`, not a microtask — see
// `bookings_day_notifier_test.dart`'s bounded-keepAlive group for the same
// mechanism) tore the instance down and silently recreated it on the next
// read, wiping `_lastDays`/`_lastOverridesSeen` and defeating the 5-minute
// TTL cache this notifier's header promises.
//
// THE FIX (already landed): `_pinForTtl()` extracts the
// keepAlive-link/Timer/onDispose triplet and is now called from BOTH the
// short-circuit return (`effective_schedule_notifier.dart:~229`) and the
// real-fetch success path (`:~246`), so every completed `build()` — cache
// hit or real fetch — ends with exactly one live pin.
//
// SHAPE OF THIS TEST (found the hard way, via a discarded first draft — see
// the QA report's mutation-verification log): the short-circuit rebuild only
// runs EAGERLY, IN PLACE, on the same instance while something is ACTIVELY
// watching it at the moment `overridesRevisionProvider` bumps — that is what
// "page away and back" actually means in production: the master is still on
// the page when an unrelated save lands elsewhere, THEN navigates away. A
// bump fired while GENUINELY unwatched does not reach the short-circuit at
// all — Riverpod disposes the stale, unwatched instance outright rather than
// eagerly recomputing a value nobody is reading, which is a level up from
// (and orthogonal to) the bug under test. So the sequence below deliberately
// keeps a live `container.listen` open THROUGH the bump (step 2-3), and only
// closes it AFTER the short-circuit has completed (step 4) — that is the
// exact moment the pre-fix code's zero-pin gap became observable.
//
// A discarded earlier draft skipped the "close AFTER, not around" ordering
// and called `container.listen` BEFORE the initial `.future` read (instead
// of after, as every other passing test in this file does) — that ordering
// alone produced spurious extra `effectiveSchedule` calls unrelated to the
// keepAlive bug, a false signal. `container.read(...future)` FIRST, THEN
// `container.listen(...)` — matching
// `effective_schedule_cross_range_revision_test.dart` — avoids it.
//
// `effective_schedule_cross_session_isolation_test.dart` found the original
// bug via mutation-probing, but its FINAL version holds ONE live
// `container.listen` open for the ENTIRE test specifically to sidestep this
// exact disposal complexity (see that file's header) — it was never meant to
// (and cannot) prove the short-circuit re-pins on its own, only that
// isolation holds given SOME live pin exists. THIS test is the one that
// actually closes the listener between the short-circuit and the next read,
// so survival depends entirely on `_pinForTtl()` having been called from the
// short-circuit branch.
//
// A `testWidgets` host (not a plain `test`) is used deliberately so
// `tester.pump(duration)` can drive Flutter's `FakeAsync` binding: it lets
// Riverpod's real `Timer(Duration.zero, ...)` eviction check actually fire
// while genuinely unwatched, AND lets fake time jump the full 5-minute TTL
// without the suite actually waiting 5 real minutes — the same technique
// `master_schedule_screen_test.dart`'s `_drainKeepAliveTimers` uses.
//
// Mutation-verified (see the QA report for the transcript): removing the
// `_pinForTtl()` call from ONLY the short-circuit path (leaving the
// real-fetch path's call intact) turns this RED — `fetchCount` goes to 2
// (a silent dispose-and-recreate) where the fix keeps it at 1; restoring the
// call turns it GREEN again.

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/features/schedule/data/schedule_repository.dart';
import 'package:beautica_mobile/features/schedule/data/schedule_repository_provider.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/features/schedule/presentation/effective_schedule_notifier.dart';
import 'package:beautica_mobile/features/schedule/presentation/overrides_revision_provider.dart';
import 'package:beautica_mobile/features/schedule/presentation/schedule_range.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockScheduleRepository extends Mock implements ScheduleRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(DateTime(2026, 6, 1));
  });

  testWidgets(
    'a cache-hit rebuild re-pins the TTL — the instance survives losing its '
    'last watcher right after the short-circuit and still serves its cache, '
    'then is genuinely evicted once the TTL actually lapses',
    (tester) async {
      final repo = _MockScheduleRepository();
      final range = ScheduleRange(
        from: DateTime(2026, 6, 15),
        to: DateTime(2026, 6, 15),
      );
      // Shares NO date with `range` — a revision bump carrying this range
      // makes the SHORT-CIRCUIT path reachable (no overrides change, no
      // overlap) instead of a real refetch. This is the exact path that
      // used to skip `_pinForTtl()`.
      final otherRange = ScheduleRange(
        from: DateTime(2026, 9, 1),
        to: DateTime(2026, 9, 1),
      );

      when(
        () => repo.listOverrides(any(), any()),
      ).thenAnswer((_) async => const <ScheduleOverride>[]);

      var fetchCount = 0;
      when(() => repo.effectiveSchedule(any(), any())).thenAnswer((_) async {
        fetchCount++;
        return <EffectiveDay>[
          EffectiveDay(
            date: range.from,
            source: EffectiveSource.template,
            intervals: const <WorkInterval>[],
          ),
        ];
      });

      final container = ProviderContainer(
        retry: beauticaProviderRetry,
        overrides: [scheduleRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      // ── 1. Resolve the range once — one real fetch. The real-fetch path
      // has always pinned unconditionally (even before the fix), so this
      // step alone proves nothing about the bug; it just seeds the cache.
      final List<EffectiveDay> first = await container.read(
        effectiveScheduleProvider(range).future,
      );
      expect(first.single.source, EffectiveSource.template);
      expect(fetchCount, 1);

      // ── 2. Attach a live listener — mirrors the master still being on
      // the page (calendar widget watching this range) when an unrelated
      // save lands elsewhere. Deliberately attached AFTER the initial read
      // (see header) to match the established, verified-working order.
      final ProviderSubscription<AsyncValue<List<EffectiveDay>>> sub = container
          .listen<AsyncValue<List<EffectiveDay>>>(
            effectiveScheduleProvider(range),
            (_, _) {},
          );

      // ── 3. A DISJOINT-range revision bump WHILE watched forces an
      // EAGER, in-place rebuild on the SAME instance — this is the
      // short-circuit path (no overrides change, no overlap): it must
      // serve the cached page with NO additional network call.
      container.read(overridesRevisionProvider.notifier).bump(otherRange);
      final List<EffectiveDay> servedWhileWatched = await container.read(
        effectiveScheduleProvider(range).future,
      );
      expect(
        servedWhileWatched.single.source,
        EffectiveSource.template,
        reason: 'the short-circuit must serve the cached page',
      );
      expect(
        fetchCount,
        1,
        reason: 'no extra network call — the short-circuit fired',
      );

      // ── 4. Navigate away: close the ONLY listener. This is the exact
      // moment the pre-fix bug lived in — the short-circuit build that
      // JUST completed (step 3) either left an active TTL pin (fixed) or
      // zero pins (bug) behind it.
      sub.close();

      // Give Riverpod's real `Timer(Duration.zero, ...)` autoDispose
      // eviction check a genuine chance to run while NOTHING is watching.
      await tester.pump(Duration.zero);

      // ── 5. Read again — with the fix, the short-circuit's re-pin kept
      // the SAME instance alive, so this serves the cache: still exactly
      // ONE real fetch. Pre-fix, the instance was disposed the moment the
      // eviction check ran (zero active pins), silently recreated here
      // with a null cache, and this read issues a SECOND real fetch.
      final List<EffectiveDay> servedAfterNavigatingAway = await container.read(
        effectiveScheduleProvider(range).future,
      );
      expect(
        servedAfterNavigatingAway.single.source,
        EffectiveSource.template,
        reason: "served from the surviving instance's cache",
      );
      expect(
        fetchCount,
        1,
        reason:
            'the short-circuit build must re-pin the TTL on its way out — '
            'a disposed-and-recreated instance would refetch here',
      );

      // ── 6. The pin must be a TTL, not a permanent leak: advance fake
      // time PAST `_kRangeCacheTtl` (5 min), again with zero active
      // watchers. Step 5's re-pin release Timer must fire, close the
      // keepAlive link, and let autoDispose genuinely evict the instance
      // this time. Crossing `_kRangeCacheTtl` (a real 5-minute Timer) is the
      // thing under test — there is no observable state to pump-until for
      // "has the TTL lapsed" short of the fetch this pump exists to enable.
      // fixed-wait-ok: a fixed duration past the TTL is correct here.
      await tester.pump(const Duration(minutes: 6));

      final List<EffectiveDay> afterTtl = await container.read(
        effectiveScheduleProvider(range).future,
      );
      expect(afterTtl.single.source, EffectiveSource.template);
      expect(
        fetchCount,
        2,
        reason:
            'past the TTL the instance must have been evicted — a fresh '
            'read must genuinely refetch. A permanent pin (the OPPOSITE '
            'failure mode from the one this test guards) would leave this '
            'at 1 forever.',
      );

      // Test-side timer hygiene only (mirrors `master_schedule_screen_test.
      // dart`'s `_drainKeepAliveTimers`): step 6's fresh instance itself
      // pinned unconditionally on its own successful fetch, leaving its OWN
      // 5-minute release Timer pending. Drain it so FakeAsync's teardown
      // sees zero pending timers — this has no bearing on the assertions
      // above, which have already run.
      // fixed-wait-ok: draining a real 5-minute release Timer, same reasoning as the annotated pump above.
      await tester.pump(const Duration(minutes: 6));
      await tester.pumpAndSettle();
    },
  );
}
