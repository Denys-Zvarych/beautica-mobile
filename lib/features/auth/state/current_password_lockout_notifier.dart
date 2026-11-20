// M517 (AUTH-D19) — holds the [CurrentPasswordLockout] tally per account for
// the app session, shared by the phone-change and the email add / change
// verify steps (ONE lockout for both paths, as on the server).
//
// Keyed by user id, so a second account signed in on the same device never
// inherits the first one's tally; kept alive for the app session (the server's
// window is 15 minutes, far shorter than a session).
//
// Persisted per user id ([CurrentPasswordLockoutStore]): [build] starts with
// the in-memory map and hydrates the stored tallies right after; every change
// is written through, in order. An account touched in memory before hydration
// resolves: a clear (correct password) wins over the stored tally; otherwise
// the pre-hydration failures are ADDED to a still-open stored tally (never a
// downgrade of a stored lock) and the merged tally is persisted.

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/time/clock_provider.dart';
import '../data/current_password_lockout_store.dart';
import '../domain/current_password_lockout.dart';

part 'current_password_lockout_notifier.g.dart';

@Riverpod(keepAlive: true)
class CurrentPasswordLockoutNotifier extends _$CurrentPasswordLockoutNotifier {
  @override
  Map<String, CurrentPasswordLockout> build() {
    unawaited(_hydrate());
    return const <String, CurrentPasswordLockout>{};
  }

  /// Serialises write-throughs so a clear never lands before the failure it
  /// follows.
  Future<void> _writes = Future<void>.value();

  /// Accounts recorded / cleared in memory before hydration resolved.
  final Set<String> _touched = <String>{};

  /// Accounts cleared (correct password) before hydration resolved — the
  /// stored tally never comes back for them.
  final Set<String> _clearedBeforeHydration = <String>{};

  bool _hydrated = false;

  Future<void> _hydrate() async {
    final Map<String, CurrentPasswordLockout> stored = await ref
        .read(currentPasswordLockoutStoreProvider)
        .readAll();
    if (!ref.mounted) return;
    _hydrated = true;
    final DateTime now = ref.read(clockProvider)();
    final Map<String, CurrentPasswordLockout> merged =
        <String, CurrentPasswordLockout>{};
    final Map<String, CurrentPasswordLockout> toPersist =
        <String, CurrentPasswordLockout>{};
    stored.forEach((String id, CurrentPasswordLockout fromStore) {
      if (_clearedBeforeHydration.contains(id)) return; // clear wins
      final CurrentPasswordLockout? inMemory = state[id];
      if (!_touched.contains(id) || inMemory == null) {
        merged[id] = fromStore;
        return;
      }
      final CurrentPasswordLockout combined = _combine(
        fromStore,
        inMemory,
        now,
      );
      merged[id] = combined;
      toPersist[id] = combined;
    });
    if (merged.isEmpty) return;
    state = <String, CurrentPasswordLockout>{...state, ...merged};
    toPersist.forEach(_persist);
  }

  /// Stored tally + failures recorded in memory before hydration: the stored
  /// count still in its window plus the in-memory count, under the later
  /// (stricter) last-failure instant.
  static CurrentPasswordLockout _combine(
    CurrentPasswordLockout fromStore,
    CurrentPasswordLockout inMemory,
    DateTime now,
  ) {
    final DateTime? storedLast = fromStore.lastFailureAt;
    // instant-ok: lockout window is an absolute 15-minute span, not a day.
    final bool storedOpen =
        storedLast != null &&
        now.isBefore(storedLast.add(kCurrentPasswordLockoutWindow));
    if (!storedOpen) return inMemory;
    final DateTime? memLast = inMemory.lastFailureAt;
    return CurrentPasswordLockout(
      failures: fromStore.failures + inMemory.failures,
      lastFailureAt: memLast == null || storedLast.isAfter(memLast)
          ? storedLast
          : memLast,
    );
  }

  void _persist(String userId, CurrentPasswordLockout? lockout) {
    if (!_hydrated) _touched.add(userId);
    final CurrentPasswordLockoutStore store = ref.read(
      currentPasswordLockoutStoreProvider,
    );
    _writes = _writes.then((_) => store.write(userId, lockout));
  }

  /// The instant [userId]'s lock lifts; `null` when not locked now.
  DateTime? unlocksAt(String userId) =>
      _of(userId).unlocksAt(ref.read(clockProvider)());

  CurrentPasswordLockout _of(String userId) =>
      state[userId] ?? const CurrentPasswordLockout();

  /// Whether [userId]'s verify steps are locked now.
  bool isLocked(String userId) =>
      _of(userId).isLockedAt(ref.read(clockProvider)());

  /// Records one wrong current password for [userId]; returns whether the
  /// account is now locked.
  bool recordFailure(String userId) {
    final DateTime now = ref.read(clockProvider)();
    final CurrentPasswordLockout next = _of(userId).recordFailure(now);
    state = <String, CurrentPasswordLockout>{...state, userId: next};
    _persist(userId, next);
    return next.isLockedAt(now);
  }

  /// A correct password clears [userId]'s tally (AUTH-D19).
  void clear(String userId) {
    if (!_hydrated) _clearedBeforeHydration.add(userId);
    if (!state.containsKey(userId)) {
      // Not in memory yet — but a stored tally may still be hydrating.
      _persist(userId, null);
      return;
    }
    state = <String, CurrentPasswordLockout>{...state}..remove(userId);
    _persist(userId, null);
  }
}
