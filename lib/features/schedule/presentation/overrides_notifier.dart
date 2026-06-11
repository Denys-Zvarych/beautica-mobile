// Phase 15.1 — Overrides family AsyncNotifier.
//
// Manages per-date override CRUD for a bounded visible [ScheduleRange] (the
// time-off list / calendar month). [build] loads the overrides in the range via
// [ScheduleRepository.listOverrides]; each row is a single-date
// [ScheduleOverride] (the mapper never groups spans — the screen groups
// consecutive identical rows into spans for display).
//
// [putOverride] / [putSpan] / [clearOverride] mutate, then reload the range. The
// effective-schedule notifier `ref.watch`es `overridesProvider(range)`, so this
// reload alone makes the calendar recompute + re-fetch the fresh effective
// schedule — NO manual `ref.invalidate(effectiveScheduleProvider)` is needed (it
// would only fire a redundant second fetch). A multi-day span is expanded here
// (presentation layer) into one PUT per date — the repository and mapper stay
// strictly 1 row = 1 date.
//
// Bounded-cache keepAlive (same scheme as the effective-schedule family): the
// effective-schedule notifier `await`s `overridesProvider(range).future` as its
// gating dependency, so for a revisit (July → June → July) to serve instantly
// the overrides instance must ALSO survive being briefly unwatched — otherwise
// the disposed overrides provider re-fetches and the effective schedule, which
// depends on it, reloads behind its keepAlive. So after a SUCCESSFUL load this
// notifier pins itself for [_kOverridesCacheTtl] (≈5 min) via `ref.keepAlive()`
// and releases via a [Timer]; the timer is cancelled on dispose and re-set
// whenever `build` re-runs (e.g. the repo resolving the real masterId, or an
// `ref.invalidate`). A `_mutate` save updates `state` in place rather than
// re-running `build`, so it keeps the existing keepAlive link — which is correct:
// the range is being actively used, and the reactive effective-schedule rebuild
// still fires off the in-place state change. We pin only on success — a
// failed/loading load disposes normally so a revisit retries.

import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/errors/failures.dart';
import '../data/schedule_repository.dart';
import '../data/schedule_repository_provider.dart';
import '../domain/schedule_model.dart';
import 'schedule_range.dart';

part 'overrides_notifier.g.dart';

/// Hard upper bound on the number of dates a single [OverridesNotifier.putSpan]
/// call may expand to. A span beyond this is almost certainly a UI / date-math
/// bug (a year-long PUT storm), so it is rejected with a [ValidationFailure] —
/// the same typed error path the repository's range guard uses. Kept well below
/// the repository's `kMaxScheduleRangeDays` (366): a quarter is a generous cap
/// for a single "block off this period" action.
const int kMaxOverrideSpanDays = 92;

/// How many per-date PUTs [OverridesNotifier.putSpan] fires concurrently per
/// batch. Deliberately small: `/auth/*`-style per-IP rate limiting exists on
/// the backend, so a wide `Future.wait` would risk throttling. Six in-flight
/// PUTs cuts the round-trip count ~6× versus a serial loop while staying gentle
/// on the rate limiter.
const int _kPutSpanChunkSize = 6;

/// How long a successfully-loaded override range stays pinned after nothing
/// watches it. Mirrors `_kRangeCacheTtl` in the effective-schedule family: the
/// two providers cache as a pair (effective schedule gates on this one), so they
/// share the same revisit window — recently-viewed ranges resolve instantly,
/// and idle windows release after the TTL.
const Duration _kOverridesCacheTtl = Duration(minutes: 5);

/// Loads and mutates the per-date overrides for [range].
///
/// Generated provider name: `overridesProvider` (a family — call
/// `overridesProvider(range)`).
@riverpod
class OverridesNotifier extends _$OverridesNotifier {
  static const _tag = 'feature.schedule.overrides';

  @override
  Future<List<ScheduleOverride>> build(ScheduleRange range) async {
    // `watch` (not `read`): the schedule repository rebuilds when
    // `masterProfileProvider` resolves the masterId from '' → the real UUID.
    // An instance created pre-resolution must refetch once the authenticated
    // repository is available, otherwise it stays stuck on UnauthorizedFailure.
    final List<ScheduleOverride> overrides = await ref
        .watch(scheduleRepositoryProvider)
        .listOverrides(range.from, range.to);

    // SUCCESS path only: pin this range for [_kOverridesCacheTtl] so a revisit
    // hits the cache (and the effective-schedule notifier that gates on it does
    // too), then release. An `ref.invalidate` re-runs `build`, cancelling this
    // timer via `onDispose` and re-pinning with a fresh TTL — so the weekly-
    // template invalidate path still forces a refetch. A `_mutate` save updates
    // `state` in place (no `build` re-run) and keeps this link, which is correct
    // for an actively-used range.
    final link = ref.keepAlive();
    final timer = Timer(_kOverridesCacheTtl, link.close);
    ref.onDispose(timer.cancel);

    return overrides;
  }

  ScheduleRepository get _repo => ref.read(scheduleRepositoryProvider);

  /// Upserts a single-date [override] (its [ScheduleOverride.start] is the
  /// target date) and reloads this range. The effective-schedule notifier
  /// watches this provider, so the reload propagates to a fresh effective-
  /// schedule fetch automatically. A thrown [Failure] becomes an [AsyncError];
  /// the previously-resolved override list is left intact on failure.
  Future<void> putOverride(ScheduleOverride override) =>
      _mutate('putOverride', () => _repo.putOverride(override));

  /// Applies one override across every date of a multi-day span — expanding the
  /// span into one PUT per calendar date (the repository stays 1 row = 1 date).
  /// All dates share [span]'s kind / intervals.
  ///
  /// Rejects spans wider than [kMaxOverrideSpanDays] with a [ValidationFailure]
  /// (mirroring the repository range guard). Fires the per-date PUTs in bounded
  /// concurrency batches of [_kPutSpanChunkSize] rather than one serial round
  /// trip per day. On partial failure the surfaced error names the failing
  /// date(s); the post-op reload then reflects whatever actually persisted.
  Future<void> putSpan(ScheduleOverride span) {
    return _mutate('putSpan', () async {
      // Build the date-only list, re-truncating each step so a DST boundary
      // (where `+24h` can land at 23:00 / 01:00 of the wrong day) cannot skip
      // or duplicate a calendar date.
      final dates = <DateTime>[];
      var cursor = DateTime(span.start.year, span.start.month, span.start.day);
      final end = DateTime(span.end.year, span.end.month, span.end.day);
      while (!cursor.isAfter(end)) {
        dates.add(cursor);
        final next = cursor.add(const Duration(days: 1));
        cursor = DateTime(next.year, next.month, next.day);
      }

      if (dates.length > kMaxOverrideSpanDays) {
        throw const ValidationFailure(fieldErrors: <String, String>{});
      }

      ScheduleOverride perDayFor(DateTime date) =>
          span.kind == OverrideKind.dayOff
          ? ScheduleOverride.dayOff(start: date, end: date)
          : ScheduleOverride.custom(
              start: date,
              end: date,
              intervals: span.intervals
                  .map((w) => w.clone())
                  .toList(growable: false),
            );

      final failedDates = <DateTime>[];
      for (var i = 0; i < dates.length; i += _kPutSpanChunkSize) {
        final chunk = dates.sublist(
          i,
          (i + _kPutSpanChunkSize).clamp(0, dates.length),
        );
        final results = await Future.wait(
          chunk.map(
            (date) => _repo
                .putOverride(perDayFor(date))
                .then<Object?>((_) => null)
                .catchError((Object e) => e),
          ),
        );
        for (var j = 0; j < chunk.length; j++) {
          if (results[j] != null) failedDates.add(chunk[j]);
        }
      }

      if (failedDates.isNotEmpty) {
        final iso = failedDates
            .map((d) => d.toIso8601String().split('T').first)
            .join(', ');
        throw ValidationFailure(
          fieldErrors: const <String, String>{},
          serverMessage: 'Failed to save override for: $iso',
        );
      }
    });
  }

  /// Clears the override on [date] and reloads this range. As with
  /// [putOverride], the effective-schedule notifier watches this provider, so
  /// the reload propagates to a fresh effective-schedule fetch automatically.
  Future<void> clearOverride(DateTime date) =>
      _mutate('clearOverride', () => _repo.clearOverride(date));

  /// Runs a mutation and reloads the range on success. Wraps everything in
  /// [AsyncValue.guard] so a [Failure] surfaces as [AsyncError] without leaking
  /// a raw exception.
  ///
  /// On a successful reload the new override list becomes this provider's state;
  /// the effective-schedule notifier (which `ref.watch`es this provider) then
  /// rebuilds and re-fetches the fresh server-resolved schedule. No explicit
  /// `ref.invalidate(effectiveScheduleProvider)` is issued here — that would
  /// only trigger a redundant second effective-schedule fetch and widen the work
  /// beyond the single coherent refetch the dependency already produces.
  Future<void> _mutate(String op, Future<void> Function() action) async {
    if (kDebugMode) {
      log('$op for range=$range', name: _tag, level: 800);
    }
    state = const AsyncLoading<List<ScheduleOverride>>();
    final result = await AsyncValue.guard(() async {
      await action();
      return _repo.listOverrides(range.from, range.to);
    });
    state = result;
  }
}
