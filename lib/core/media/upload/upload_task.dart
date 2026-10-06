// Phase 070 — handle for one in-flight upload: progress, result, cancel.

import 'dart:async';

/// An in-flight upload.
///
/// [progress] is a broadcast stream of send fractions in 0.0–1.0 (monotonic,
/// throttled to steps of >= 1 %, ending at 1.0 on success) that closes when
/// the task completes — success, failure or cancel. [result] completes with
/// the parsed value or errors with an `UploadFailure`.
final class UploadTask<T> {
  UploadTask({
    required this.progress,
    required this.result,
    required void Function() onCancel,
  }) : _onCancel = onCancel;

  final Stream<double> progress;
  final Future<T> result;
  final void Function() _onCancel;

  /// Aborts the request; [result] then errors with `UploadCancelledFailure`.
  /// Idempotent.
  void cancel() => _onCancel();
}
