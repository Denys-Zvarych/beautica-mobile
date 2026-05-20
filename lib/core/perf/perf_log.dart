import 'dart:developer' as developer;

/// Temporary startup-timing helper. Emits a `developer.log` entry tagged
/// `beautica_perf` so the cold-start path can be measured on release builds
/// via `adb logcat | grep beautica_perf`. Remove together with all call
/// sites in a follow-up commit once the splash / login→register hotspot is
/// identified.
void perfLog(String event) {
  final ts = DateTime.now().millisecondsSinceEpoch;
  developer.log('$ts ms — $event', name: 'beautica_perf');
}
