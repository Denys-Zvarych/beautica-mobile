// Phase 480 — the bounded keepAlive LRU, promoted out of
// `bookings_day_notifier.dart` (where it shipped as `DayKeepAliveLru`) so the
// week notifier (`bookings_week_notifier.dart`) pins its prev/current/next
// weeks with the SAME bookkeeping instead of a copy of it.
//
// `DayKeepAliveLru` is now `KeepAliveLru<BookingsDayQuery>` with capacity 3 —
// byte-identical behaviour; every member below is the original body with the
// key type generalised. The reasoning behind each member (FIX A `contains`,
// the `liveQueries` snapshot, the `_watched` REFERENCE COUNT, the logout
// `clear` sweep) is unchanged and documented on the member itself.

import 'dart:collection';

import 'package:flutter_riverpod/misc.dart';

/// A small LRU set of `KeepAliveLink`s, one per recently-touched family key
/// [K] — the bounded middle ground between a blanket `ref.keepAlive()`
/// (unbounded) and plain autoDispose (evicts on every unwatch). [touch] is
/// called from every owning notifier's `build`; touching an already-tracked
/// key replaces its link (rather than accumulating a duplicate one, which a
/// retry-triggered rebuild of the SAME key would otherwise do) and marks it
/// most-recently-used.
///
/// Always reached through a container-scoped provider
/// (`dayKeepAliveLruProvider`, `weekKeepAliveLruProvider`), never a bare
/// top-level global, so two containers never see one another's links.
class KeepAliveLru<K> {
  KeepAliveLru({required this.capacity})
    : assert(capacity > 0, 'a keepAlive LRU must pin at least one key');

  /// How many DISTINCT keys this LRU pins simultaneously.
  final int capacity;

  final LinkedHashMap<K, KeepAliveLink> _links =
      LinkedHashMap<K, KeepAliveLink>();

  /// Whether [query] currently holds one of the [capacity] budget slots —
  /// i.e. its notifier element has built at least once this session and has
  /// not (yet) been evicted.
  ///
  /// FIX A (mobile-debugger) — the ONLY cheap, correct signal callers outside
  /// the owning notifier have for "is this family member the kind of
  /// PINNED-BUT-UNWATCHED element a bare `ref.invalidate` can race Riverpod's
  /// own disposal scheduler on". `ProviderScheduler._performDispose`
  /// RE-CHECKS `ref._keepAliveLinks` at task-FIRE time, not at schedule time,
  /// so re-establishing a link synchronously — before the scheduler's queued
  /// task ever runs — reliably cancels a disposal already queued against this
  /// element.
  ///
  /// `true` does NOT distinguish "actively watched right now" from "pinned
  /// but nobody is currently watching it" — [touch] runs unconditionally on
  /// every build. `false` means the key was never built this session (or was
  /// already evicted-and-disposed) — invalidating THAT is a genuine no-op.
  bool contains(K query) => _links.containsKey(query);

  /// Every key currently holding one of the [capacity] budget slots — i.e.
  /// every candidate [contains] would answer `true` for — snapshotted into a
  /// `List` at call time.
  ///
  /// For a caller doing a BARE FAMILY fan-out that cannot name a key to check
  /// [contains] against. Snapshotted (not a live view) because callers
  /// iterate this list while invalidating/reading members of the family, and
  /// an eager `ref.read` back re-touches [touch] on the SAME key — so the
  /// underlying map can mutate mid-iteration if a caller iterated it directly.
  List<K> get liveQueries => _links.keys.toList(growable: false);

  /// Keys with at least one Riverpod listener RIGHT NOW — paused (covered by
  /// an opaque route) or active, doesn't matter; only whether a subscription
  /// exists at all.
  ///
  /// Backed by [markWatched]/[markUnwatched], wired from the owning
  /// notifier's `build` via `ref.onAddListener`/`onRemoveListener` — those
  /// fire on raw listener-COUNT changes only, so pausing/resuming a covered
  /// consumer never touches this map, only a genuine subscribe/unsubscribe
  /// does.
  ///
  /// A REFERENCE COUNT, not a `Set<K>` (mobile-qa LOW, empirically probed in
  /// `bookings_day_notifier_test.dart`'s "isWatched contract" group):
  /// `ProviderContainer.read` is literally `listen(...)` + `sub.close()`, so
  /// every plain `ref.read` of a member opens and immediately closes its OWN
  /// transient subscription, hitting `markWatched` then `markUnwatched` in
  /// the same synchronous step. Against a `Set` that pair nets to "absent"
  /// even while a real listener is still open; against a count it nets to a
  /// no-op.
  final Map<K, int> _watched = <K, int>{};

  /// Whether [query] currently has at least one live Riverpod subscription
  /// (paused or active) — see [_watched]'s doc. `false` means either the key
  /// was never built this session, OR it built and every subscriber has since
  /// unsubscribed, leaving it pinned by [touch]'s keepAlive link alone:
  /// exactly the "genuinely zero-listener" case an invalidation fan-out must
  /// eager-read to avoid racing Riverpod's queued disposal.
  bool isWatched(K query) => (_watched[query] ?? 0) > 0;

  /// Records that [query] gained a live subscription — including a transient
  /// one `ProviderContainer.read` opens and closes internally (see
  /// [_watched]'s doc), which is exactly why this increments a count instead
  /// of setting a flag.
  void markWatched(K query) =>
      _watched.update(query, (int count) => count + 1, ifAbsent: () => 1);

  /// Records that [query] lost a live subscription. A transient
  /// `ProviderContainer.read` firing this only ever undoes its own paired
  /// [markWatched], never a real listener's.
  void markUnwatched(K query) {
    final int? count = _watched[query];
    if (count == null) return;
    if (count <= 1) {
      _watched.remove(query);
    } else {
      _watched[query] = count - 1;
    }
  }

  void touch(K query, KeepAliveLink link) {
    // A rebuild of a key already tracked (e.g. the error state's «retry»
    // invalidating the SAME key) replaces the link instead of leaking a
    // second one for it.
    _links.remove(query)?.close();
    _links[query] = link;
    // `LinkedHashMap` iterates in insertion order, so the first key is the
    // least-recently-touched one once every touch above re-inserts at the
    // end.
    while (_links.length > capacity) {
      _links.remove(_links.keys.first)?.close();
    }
  }

  /// Closes [query]'s [KeepAliveLink] and forgets the key, freeing its slot.
  ///
  /// Phase 480 — for an invalidation fan-out that wants a pinned-but-
  /// UNWATCHED member DROPPED rather than refetched: with its link closed and
  /// no listener left, the invalidated element is disposed instead of
  /// rebuilt, and the next visit builds (and [touch]es) it afresh. A no-op
  /// for a key not tracked. Listener counts are untouched — they belong to
  /// live subscriptions, not to the pin.
  void evict(K query) => _links.remove(query)?.close();

  /// Closes every held [KeepAliveLink] and forgets all tracked keys.
  ///
  /// Called from `AuthNotifier.logout` (mobile-security HIGH, 2026-07-19) as
  /// a deterministic sweep of THIS class's own bookkeeping. It is NOT what
  /// reclaims an unwatched member's cached PII — the owning notifier's
  /// `authProvider` id watch already does that the moment the identity
  /// changes. What [clear] prevents is [_links] accumulating "zombie"
  /// entries: `runOnDispose()` detaches a link from the Riverpod element's
  /// `Ref`, never from this map, so without this sweep a logged-out key's slot
  /// would keep pointing at an already-severed link — silently wasting one of
  /// the [capacity] budget slots — until a future [touch] for that same key
  /// happens to overwrite it.
  void clear() {
    for (final KeepAliveLink link in _links.values) {
      link.close();
    }
    _links.clear();
    // Same "zombie entry" reasoning as `_links`, for the listener counts.
    _watched.clear();
  }
}
