/// Temporary startup-timing helper. Emits a `print` line prefixed with
/// `[BEAUTICA_PERF]` so the cold-start path can be measured on release
/// builds via `adb logcat | grep BEAUTICA_PERF`. `developer.log` is a
/// no-op in release because the VM service is disabled; `print` routes
/// through Flutter's message handler to Android logcat under the
/// `flutter` tag. Remove together with all call sites in a follow-up
/// commit once the splash / login→register hotspot is identified.
void perfLog(String event) {
  final ts = DateTime.now().millisecondsSinceEpoch;
  // Plain print so this reaches logcat in release builds.
  // Grep target: `grep BEAUTICA_PERF` in `adb logcat`.
  // ignore: avoid_print
  print('[BEAUTICA_PERF] $ts ms — $event');
}
