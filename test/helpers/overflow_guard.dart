// Overflow / layout guard harness (Phase 17.2).
//
// WHAT
// ----
// Installs a [FlutterError.onError] interceptor that RECORDS every layout
// overflow Flutter reports — i.e. the yellow/black "RenderFlex overflowed by N
// pixels" stripes — and, in a per-test `tearDown`, fails the test if any was
// recorded. Every OTHER framework error is forwarded to the default
// [FlutterError.presentError] so nothing else changes behaviour.
//
// WHY RECORD-THEN-FAIL (not throw inline)
// ---------------------------------------
// An overflow error is reported from inside the layout flush. THROWING from
// `FlutterError.onError` there makes `pumpAndSettle` re-run the dirty layout,
// re-report the same overflow, and never quiesce — the test hangs forever
// instead of failing (the same "deactivated-subtree re-report" deadlock class
// the 17.1 notes describe). So the guard never throws inline: it records the
// FIRST overflow's diagnostics and fails the test cleanly in `tearDown`, where
// throwing is safe. A `RenderFlex` overflow therefore turns into a hard, fast
// test failure with no manual `takeException()` needed.
//
// SCOPE
// -----
// [installOverflowGuard] is wired into:
//   • `test/flutter_test_config.dart`  — suite-wide, so it is ON BY DEFAULT for
//     every widget test (and any integration test on that config path).
//   • `test/helpers/pump_app.dart`     — every pumpApp/pumpRoutedApp call.
//   • the integration harness           — integration tests call it in setUp.
//
// The install is idempotent and chains to the CURRENT presenter, so the 17.1
// no-network net (on HttpOverrides) and font determinism (on the engine font
// collection) — neither of which lives on `FlutterError.onError` — are
// untouched.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Substrings that identify a layout-overflow [FlutterErrorDetails] message.
/// Flutter reports the canonical case as
/// "A RenderFlex overflowed by 14 pixels on the right." — matching either token
/// (case-sensitively, as Flutter emits them) also catches the rarer
/// `overflowed` phrasings without coupling to the exact sentence.
const List<String> _overflowMarkers = <String>['RenderFlex', 'overflowed'];

/// The recorder closure CURRENTLY installed on [FlutterError.onError], or null
/// if ours is not the live handler. Used to detect whether the live handler is
/// ours (no-op) or a FOREIGN handler we must re-wrap.
///
/// WHY A REFERENCE, NOT A BOOLEAN
/// ------------------------------
/// `flutter_test` reassigns `FlutterError.onError` to its own per-test reporter
/// for EVERY test. A one-shot boolean sentinel ("installed once, ever") would
/// see the suite-wide install as done and never re-wrap — so during the test
/// body the live handler is flutter_test's reporter, our recorder is bypassed,
/// and overflows are NEVER recorded (the guard silently does nothing). Keeping a
/// reference lets [installOverflowRecorder] notice "the live handler is not the
/// one I installed" and re-wrap the foreign handler as the delegate, restoring
/// interception while still forwarding to flutter_test's reporter.
FlutterExceptionHandler? _recorder;

/// True while a [FlutterErrorDetails] message matches a layout-overflow marker.
bool _isOverflow(FlutterErrorDetails details) {
  final String text = details.exceptionAsString();
  for (final String marker in _overflowMarkers) {
    if (text.contains(marker)) return true;
  }
  return false;
}

/// Installs (or re-installs) the [FlutterError.onError] RECORDER — wraps the
/// handler currently in force so the first layout overflow is recorded while
/// every other error is forwarded to that handler. Does NOT arm a `tearDown`,
/// so it is safe to call from outside a test (e.g. the suite-wide
/// `flutter_test_config.dart` `testExecutable`).
///
/// IDEMPOTENT, RE-WRAP AWARE: if the live handler is already our recorder this
/// is a no-op; if it is a FOREIGN handler (e.g. flutter_test's per-test reporter
/// installed after our suite-wide install) we re-wrap it so interception is
/// restored for the current test. The pump helpers call this on every pump via
/// [installOverflowGuard], so the recorder is always live during a pumped test.
///
/// On its own this only records; the recorded overflow is asserted either by
/// [installOverflowGuard] (in-test arming) or by the per-test `tearDown` it
/// registers. Tests that pump via [PumpApp] always go through
/// [installOverflowGuard], so they fail on overflow automatically.
void installOverflowRecorder() {
  // Already our handler in force → nothing to do.
  if (_recorder != null && identical(FlutterError.onError, _recorder)) return;

  // Capture the handler in force right now — normally
  // `FlutterError.presentError` at suite init, or flutter_test's per-test
  // reporter once a test is running. Non-overflow errors forward to it so the
  // default reporting (and the 17.1 net piggybacking on it) is intact.
  final FlutterExceptionHandler delegate =
      FlutterError.onError ?? FlutterError.presentError;

  FlutterExceptionHandler recorder;
  recorder = (FlutterErrorDetails details) {
    if (_isOverflow(details)) {
      // Re-present so the console diagnostic still names the offending widget,
      // then record (only the first) for the tearDown assertion. Do NOT throw
      // here — that would re-enter layout and hang pumpAndSettle.
      delegate(details);
      _recordedOverflow ??= details;
      return;
    }
    delegate(details);
  };
  _recorder = recorder;
  FlutterError.onError = recorder;
}

/// Installs the overflow guard for the CURRENT test: ensures the recorder is in
/// place, opens a fresh recording window, and registers a `tearDown` that fails
/// the test if any layout overflow was recorded — surfacing it as a clean
/// failure WITHOUT throwing during layout (which would deadlock pumpAndSettle).
///
/// MUST be called from inside a test (it uses `addTearDown`). Idempotent within
/// a test: the pump helpers call it on every pump, but the tearDown is armed
/// only once per test.
void installOverflowGuard() {
  installOverflowRecorder();

  // Per-test arming: fresh recording window + a tearDown that fails the test if
  // an overflow was seen. Guarded by [_armed] so multiple installs within one
  // test (config + pumpApp) register the tearDown only once.
  if (!_armed) {
    _armed = true;
    _recordedOverflow = null;
    addTearDown(() {
      final FlutterErrorDetails? overflow = _recordedOverflow;
      _armed = false;
      _recordedOverflow = null;
      if (overflow != null) {
        fail(
          'Layout overflow detected (Phase 17.2 guard): '
          '${overflow.exceptionAsString()}',
        );
      }
    });
  }
}

/// First overflow recorded in the current test window, or null.
FlutterErrorDetails? _recordedOverflow;

/// Whether the per-test reset + tearDown have been armed for the current test.
bool _armed = false;

/// Clears any recorded overflow for the current test. Useful for a test that
/// deliberately drives an overflow as an intermediate state and recovers — call
/// it after the recovery pump so the tearDown does not fail on the transient.
@visibleForTesting
void resetOverflowGuard() => _recordedOverflow = null;

/// The first layout overflow the recorder captured in the current window, or
/// null if none. Exposed for the harness meta-test
/// (`overflow_guard_meta_test.dart`), which deliberately drives an overflow and
/// asserts the recorder caught it — proving the guard's FAILING path, not just
/// its passing path. Reading this never mutates state.
@visibleForTesting
FlutterErrorDetails? get recordedOverflow => _recordedOverflow;

/// Forgets the recorder reference so the NEXT [installOverflowRecorder] re-wraps
/// whatever handler is currently in force. Exposed ONLY for the harness
/// meta-test, which installs the recorder over a probe delegate to prove
/// non-overflow errors are forwarded (not swallowed). No production callers.
@visibleForTesting
void resetInstalledSentinelForTest() => _recorder = null;
