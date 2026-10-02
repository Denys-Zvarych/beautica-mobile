import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show visibleForTesting;

/// Compile-time slice names for [StartupTrace]. Constants only: no PII, no
/// dynamic strings. Each shows up in the DevTools timeline as `boot:<name>`.
abstract final class StartupSlice {
  static const String timezones = 'timezones';
  static const String fonts = 'fonts';
  static const String certPinning = 'certPinning';
  static const String container = 'container';
}

/// Test-only observer of slice boundaries: receives the full timeline event
/// name (`boot:<name>`) and `true` on slice start, `false` on slice finish.
typedef StartupTraceRecorder = void Function(String eventName, bool started);

/// Phase 075 (10.1) — named timeline slices around the pre-`runApp` boot
/// steps so a profile-mode trace shows where cold-start time goes (MP4).
///
/// Both [sync] and [async] emit the SAME event type (a `TimelineTask` async
/// `b`/`e` pair named `boot:<name>`), so `scripts/measure_startup.sh` parses a
/// single shape from `build/start_up_timeline.json`. Cost is near zero when
/// the timeline stream is off, so there is no `kReleaseMode` branching.
/// Behaviour of the body is unchanged: the value is returned and any
/// exception is rethrown.
abstract final class StartupTrace {
  static const String _prefix = 'boot:';

  /// Test seam. Only consulted inside an `assert`, so it is compiled out of
  /// release builds (zero release cost).
  @visibleForTesting
  static StartupTraceRecorder? debugRecorder;

  static developer.TimelineTask _begin(String name) {
    final String eventName = '$_prefix$name';
    final developer.TimelineTask task = developer.TimelineTask();
    task.start(eventName);
    assert(() {
      debugRecorder?.call(eventName, true);
      return true;
    }());
    return task;
  }

  static void _end(developer.TimelineTask task, String name) {
    task.finish();
    assert(() {
      debugRecorder?.call('$_prefix$name', false);
      return true;
    }());
  }

  /// Runs [body] inside a `boot:<name>` timeline slice.
  static T sync<T>(String name, T Function() body) {
    final developer.TimelineTask task = _begin(name);
    try {
      return body();
    } finally {
      _end(task, name);
    }
  }

  /// Runs [body] inside a `boot:<name>` timeline slice. The slice is finished
  /// in `finally`, so a throwing body never leaves it open.
  static Future<T> async<T>(String name, Future<T> Function() body) async {
    final developer.TimelineTask task = _begin(name);
    try {
      return await body();
    } finally {
      _end(task, name);
    }
  }
}
