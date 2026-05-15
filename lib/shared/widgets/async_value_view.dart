// Phase 1.5 — `AsyncValue` extension for concise screen wiring.
//
// `AsyncValueViewX.view(...)` is a thin wrapper over `AsyncValue.when` that:
//   - Supplies `LoadingSkeleton` as the default loading state.
//   - Maps any non-`Failure` error to `UnknownFailure` before passing it to
//     `ErrorState`, so the caller never needs to manually wrap.
//   - Keeps the `error` branch optional — callers can override it if a screen
//     needs a custom error UI (e.g., a full-page illustration instead of the
//     standard icon + message).
//
// Usage in a `ConsumerWidget.build`:
//
// ```dart
// ref.watch(masterProfileProvider).view(
//   data: (master) => MasterDetails(master: master),
// );
// ```
//
// Or with a custom loading and error widget:
//
// ```dart
// ref.watch(masterProfileProvider).view(
//   data: (master) => MasterDetails(master: master),
//   loading: const LoadingSkeleton.card(),
//   error: (e, st) => ErrorState(
//     failure: e is Failure ? e : UnknownFailure(cause: e),
//     onRetry: () => ref.invalidate(masterProfileProvider),
//   ),
// );
// ```

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/loading_skeleton.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Extension that adds the [view] helper to any [AsyncValue].
extension AsyncValueViewX<T> on AsyncValue<T> {
  /// Renders the correct widget for each [AsyncValue] state.
  ///
  /// - [data] — called with the resolved value; must return a [Widget].
  /// - [loading] — widget shown while loading; defaults to [LoadingSkeleton].
  /// - [error] — builder called with the raw error and stack trace; defaults
  ///   to [ErrorState] wrapping any non-[Failure] in [UnknownFailure].
  Widget view({
    required Widget Function(T data) data,
    Widget? loading,
    Widget Function(Object e, StackTrace st)? error,
  }) => when(
    data: data,
    loading: () => loading ?? const LoadingSkeleton(),
    error: (e, st) =>
        error?.call(e, st) ??
        ErrorState(failure: e is Failure ? e : UnknownFailure(cause: e)),
  );
}
