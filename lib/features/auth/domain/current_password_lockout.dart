// M517 (AUTH-D19) — the client-side mirror of the backend's per-account
// current-password lockout on the phone-change and email add / change verify
// steps.
//
// The backend answers 400 `CURRENT_PASSWORD_INVALID` both for a wrong password
// AND for any password while the account is locked, so the wire never says
// "locked". The app therefore counts the wrong-password answers itself with
// the SAME rule (AUTH-D19, as AUTH-08): 10 wrong passwords within 15 minutes,
// the window restarting on each failure, lock both verify steps; a correct
// password clears the count. It is a UX mirror only — the server stays the
// boundary. The tally is persisted per user id (device-scoped secure
// storage, [CurrentPasswordLockoutStore]) so an app restart inside the window
// keeps the lock.
//
// Pure Dart: absolute instants only (no calendar day is derived here).

/// Wrong current passwords that lock the verify steps (AUTH-D19).
const int kCurrentPasswordLockoutThreshold = 10;

/// The lockout window; it restarts on each failure (AUTH-D19).
const Duration kCurrentPasswordLockoutWindow = Duration(minutes: 15);

/// Immutable failure tally for one account.
final class CurrentPasswordLockout {
  const CurrentPasswordLockout({this.failures = 0, this.lastFailureAt});

  /// Parses one stored entry; anything malformed reads as no failures (the
  /// server stays the boundary — never a crash).
  factory CurrentPasswordLockout.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return const CurrentPasswordLockout();
    final Object? failures = json['failures'];
    final Object? last = json['lastFailureAt'];
    return CurrentPasswordLockout(
      failures: failures is int && failures > 0 ? failures : 0,
      lastFailureAt: last is String ? DateTime.tryParse(last) : null,
    );
  }

  /// Consecutive wrong passwords, each within the window of the previous one.
  final int failures;

  /// Instant of the latest wrong password; `null` = none yet.
  final DateTime? lastFailureAt;

  /// Whether the window of the latest failure is still open at [now].
  bool _windowOpen(DateTime now) {
    final DateTime? last = lastFailureAt;
    // instant-ok: lockout window is an absolute 15-minute span, not a day.
    return last != null &&
        now.isBefore(last.add(kCurrentPasswordLockoutWindow));
  }

  Map<String, dynamic> toJson() {
    final DateTime? last = lastFailureAt;
    return <String, dynamic>{
      'failures': failures,
      if (last != null) 'lastFailureAt': last.toUtc().toIso8601String(),
    };
  }

  /// The instant the lock lifts when locked at [now]; `null` when not locked.
  DateTime? unlocksAt(DateTime now) {
    final DateTime? last = lastFailureAt;
    if (last == null || !isLockedAt(now)) return null;
    return last.add(kCurrentPasswordLockoutWindow);
  }

  /// Whether both verify steps are locked at [now].
  bool isLockedAt(DateTime now) =>
      failures >= kCurrentPasswordLockoutThreshold && _windowOpen(now);

  /// The tally after one more wrong password at [now]: a failure after the
  /// window closed starts a new count.
  CurrentPasswordLockout recordFailure(DateTime now) => CurrentPasswordLockout(
    failures: _windowOpen(now) ? failures + 1 : 1,
    lastFailureAt: now,
  );
}
