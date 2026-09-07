// mobile-perf MEDIUM follow-up (F3 fix's own race) — REGRESSION for a bug
// found while auditing the F3 short-circuit fix itself.
//
// [EffectiveScheduleNotifier] keeps two hand-rolled cache fields
// (`_lastOverridesSeen` / `_lastDays`) — plain instance fields on the
// long-lived `@riverpod class` notifier, written after `await` boundaries.
// Riverpod re-invokes `build()` on the SAME notifier instance whenever a
// watched dependency changes (`overridesProvider(range)` or
// [overridesRevisionProvider]) and does NOT cancel or await a prior
// in-flight invocation — Dart futures run to completion regardless. So two
// builds of the same instance can be in flight at once (e.g. two rapid
// writes touching the same range), and Riverpod's own supersede protection
// on `state` does NOT extend to these plain fields: an OLDER build whose
// network fetch resolves AFTER a NEWER build already wrote fresher data
// could clobber `_lastDays`/`_lastOverridesSeen` with stale data — served by
// every LATER short-circuited read until the range changes or the 5-minute
// TTL lapses.
//
// THE FIX (already landed, see `effective_schedule_notifier.dart`): a
// `_buildGen` counter bumped at the TOP of every `build()` (before any
// `await`); both write sites are guarded by `if (myGen == _buildGen)`.
//
// THIS TEST drives exactly that shape on the REAL provider graph (a fake
// repository with controllable per-call `Completer`s stands in for the
// network):
//   1. gen1 (OLDER) build starts, registers its `effectiveSchedule` call,
//      and is held — mirrors the first of two rapid writes.
//   2. gen2 (NEWER) build is forced on the SAME instance (a same-range
//      `overridesRevisionProvider` bump, exactly like a second rapid write
//      would cause) WHILE gen1 is still in flight, registers its OWN
//      `effectiveSchedule` call.
//   3. gen2 resolves FIRST with the FRESH page.
//   4. gen1 resolves LAST with a STALE page — the exact ordering the bug
//      needs.
//   5. A THIRD build, forced by a revision bump for a range that shares no
//      date with this one, short-circuits (see the notifier's header) and
//      serves whatever `_lastDays` holds WITHOUT calling `effectiveSchedule`
//      again — proving observably (not by reaching into the private field)
//      that the cache holds gen2's fresh page, not gen1's stale one.
//
// Must be RED with the `myGen == _buildGen` guards reverted to unconditional
// writes, and GREEN with the fix in place — see the QA report's
// mutation-verification log for the exact diff and observed failure.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/features/schedule/data/schedule_repository.dart';
import 'package:beautica_mobile/features/schedule/data/schedule_repository_provider.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_scope.dart';
import 'package:beautica_mobile/features/schedule/presentation/effective_schedule_notifier.dart';
import 'package:beautica_mobile/features/schedule/presentation/overrides_revision_provider.dart';
import 'package:beautica_mobile/features/schedule/presentation/schedule_range.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockScheduleRepository extends Mock implements ScheduleRepository {}

EffectiveDay _resolvedAs(DateTime date, EffectiveSource source) =>
    EffectiveDay(date: date, source: source, intervals: const []);

void main() {
  setUpAll(() {
    registerFallbackValue(DateTime(2026, 6, 1));
  });

  test("an older build's late-resolving fetch must not clobber a newer "
      'build\'s cached result', () async {
    final repo = _MockScheduleRepository();
    const ScheduleScope scope = ScheduleScope.own(masterId: 'm1');
    final range = ScheduleRange(
      from: DateTime(2026, 6, 15),
      to: DateTime(2026, 6, 15),
    );
    // Shares NO date with `range` — a revision bump carrying this range
    // must short-circuit rather than refetch (step 5).
    final otherRange = ScheduleRange(
      from: DateTime(2026, 9, 1),
      to: DateTime(2026, 9, 1),
    );

    when(
      () => repo.listOverrides(any(), any()),
    ).thenAnswer((_) async => const []);

    final completers = <Completer<List<EffectiveDay>>>[];
    when(() => repo.effectiveSchedule(any(), any())).thenAnswer((_) {
      final completer = Completer<List<EffectiveDay>>();
      completers.add(completer);
      return completer.future;
    });

    final container = ProviderContainer(
      retry: beauticaProviderRetry,
      overrides: [
        scheduleRepositoryProvider.overrideWith((ref, scope) => repo),
      ],
    );
    addTearDown(container.dispose);

    // ── 1. gen1 (OLDER) build starts and parks on its own
    // `effectiveSchedule` call.
    final ProviderSubscription<AsyncValue<List<EffectiveDay>>> sub = container
        .listen<AsyncValue<List<EffectiveDay>>>(
          effectiveScheduleProvider(scope, range),
          (_, _) {},
        );
    addTearDown(sub.close);

    await Future<void>.delayed(Duration.zero);
    expect(
      completers,
      hasLength(1),
      reason: "gen1's build should be parked on its effectiveSchedule call",
    );

    // ── 2. Force gen2 (NEWER) on the SAME instance — a same-range
    // revision bump, exactly like a second rapid write would cause —
    // WHILE gen1 is still in flight.
    container.read(overridesRevisionProvider(scope).notifier).bump(range);
    await Future<void>.delayed(Duration.zero);
    expect(
      completers,
      hasLength(2),
      reason: 'gen2 must fire its OWN effectiveSchedule call',
    );

    // ── 3. gen2 (NEWER) resolves FIRST, with the FRESH page.
    completers[1].complete(<EffectiveDay>[
      _resolvedAs(range.from, EffectiveSource.overrideCustom),
    ]);
    await Future<void>.delayed(Duration.zero);

    // ── 4. gen1 (OLDER) resolves LAST, with a STALE page — the exact
    // ordering the bug needs.
    completers[0].complete(<EffectiveDay>[
      _resolvedAs(range.from, EffectiveSource.noSchedule),
    ]);
    await Future<void>.delayed(Duration.zero);

    // ── 5. A THIRD build, forced by a revision bump for a NON-overlapping
    // range, must short-circuit off the cache rather than refetch.
    container.read(overridesRevisionProvider(scope).notifier).bump(otherRange);
    final List<EffectiveDay> served = await container.read(
      effectiveScheduleProvider(scope, range).future,
    );

    expect(
      completers,
      hasLength(2),
      reason:
          'the third build must short-circuit off the cache — no THIRD '
          'effectiveSchedule call',
    );
    expect(
      served.single.source,
      EffectiveSource.overrideCustom,
      reason:
          'the cache must reflect gen2 (the NEWER, faster build) — gen1 '
          'resolving LAST must not clobber it with the stale page',
    );
  });
}
