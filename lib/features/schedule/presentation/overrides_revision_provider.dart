// Phase 15.1 follow-up — one-way revision counter breaking the
// overrides↔effective-schedule cycle.
//
// [EffectiveScheduleNotifier.build] reactively watches `overridesProvider`, so
// [OverridesNotifier] can never call `ref.invalidate(effectiveScheduleProvider)`
// (or `ref.refresh`) after a mutation — doing so would close a real watch
// cycle: `overridesProvider` write → invalidate `effectiveScheduleProvider` →
// which watches `overridesProvider` → ... `test/core/provider_cycle_guard_test.dart`
// and `scripts/verify_guards.sh`'s `forbid_provider_self_invalidation.sh` exist
// specifically to catch this shape (mirroring the historical
// `AuthNotifier.logout()` bug).
//
// But a range-scoped reactive watch alone isn't enough either: `overridesProvider`
// and `effectiveScheduleProvider` are both families keyed on the exact
// [ScheduleRange] (`from`/`to`), so a write under a MONTH-spanning range (the
// schedule editor) never reactively touches a SINGLE-DAY range's instance (e.g.
// «Мої записи» viewing that same date) — they're distinct family members, and
// each pins itself stale via `ref.keepAlive()` for up to 5 minutes.
//
// [OverridesRevision] is the fix: a provider that depends on NOTHING (its
// `build` reads no other provider), so bumping it can never form a cycle no
// matter what watches it. [OverridesNotifier._mutate] bumps it after every
// successful write; [EffectiveScheduleNotifier.build] watches it alongside its
// own range-scoped `overridesProvider(range)` watch. The result: ANY override
// write, at ANY range, invalidates EVERY live effective-schedule window,
// one-way, with zero risk of a back-edge into `OverridesNotifier`.
//
// mobile-perf MEDIUM follow-up: the plain `int` counter this provider used to
// hold forced EVERY live-or-pinned `effectiveScheduleProvider` instance to
// refetch on ANY write, anywhere — a master paging through several months
// plus several single days, then saving one override, fired a concurrent,
// uncoalesced refetch across all of them. [OverridesRevisionEvent] carries
// the WRITTEN [ScheduleRange] instead, so a watcher can compare it against
// its OWN range via [ScheduleRange.overlaps] and skip the refetch when the
// two provably share no date — see `effective_schedule_notifier.dart`'s
// `build` for the read side. This provider still watches nothing and still
// exposes no invalidate/refresh of its own, so it remains exactly as
// cycle-safe as the plain counter it replaces.
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/schedule_scope.dart';
import 'schedule_range.dart';

part 'overrides_revision_provider.g.dart';

/// One bump's payload: the [ScheduleRange] the write that caused this bump
/// actually touched. `writtenRange` is `null` only for the provider's
/// initial (never-bumped) state — every real [bump] call sets it.
///
/// Deliberately carries no `==`/`hashCode` override, so every instance
/// (including two bumps for the same [writtenRange] in a row) is distinct
/// by identity. That is what makes `bump` a real notification every time:
/// Riverpod's default `updateShouldNotify` already fires on identity
/// change alone, with no sequence counter needed to force it — this class
/// used to also carry a monotonic `seq` field for that purpose, but it was
/// never read anywhere (dead weight relative to what it claimed to do).
/// Do NOT add an `==`/`hashCode` here as a "cleanup" — that would make two
/// same-range bumps compare equal and change [EffectiveScheduleNotifier]'s
/// watchers to skip a notification that must fire.
class OverridesRevisionEvent {
  const OverridesRevisionEvent({required this.writtenRange});

  final ScheduleRange? writtenRange;
}

/// Bumped by [OverridesNotifier] after every successful override write
/// (`putOverride` / `putSpan` / `clearOverride`) for [scope], regardless of
/// that write's own [ScheduleRange]. Watched by [EffectiveScheduleNotifier
/// .build] purely as a recompute-or-skip signal — see [OverridesRevisionEvent]'s
/// doc.
///
/// A FAMILY keyed on [ScheduleScope] (Phase 312 — was a single container-wide
/// counter): a write for one viewed master must only force THAT master's own
/// live effective-schedule windows to recompute, never a DIFFERENT master's
/// pinned calendar an owner/admin happens to also have visited this session.
///
/// Deliberately watches nothing: that is what makes bumping it safe to call
/// from [OverridesNotifier] without forming a watch cycle back into itself.
///
/// Generated provider name: `overridesRevisionProvider` (a family — call
/// `overridesRevisionProvider(scope)`).
@riverpod
class OverridesRevision extends _$OverridesRevision {
  @override
  OverridesRevisionEvent build(ScheduleScope scope) =>
      const OverridesRevisionEvent(writtenRange: null);

  /// Signals "an override changed somewhere, at [writtenRange]" to every
  /// watcher. Called only after a successful write — a failed mutation
  /// leaves prior effective-schedule windows untouched, matching
  /// [OverridesNotifier]'s existing "pin only on success" behaviour. Always
  /// assigns a FRESH [OverridesRevisionEvent] instance (never mutates or
  /// reuses `state`), which is what actually makes this a notification —
  /// see [OverridesRevisionEvent]'s doc.
  void bump(ScheduleRange writtenRange) {
    state = OverridesRevisionEvent(writtenRange: writtenRange);
  }
}
