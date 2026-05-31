// Phase 5.2 — Duration formatter for service minutes.
//
// Single call site: DurationMinutes.format(minutes) → "45 хв" / "1 год" / "1 год 30 хв".
//
// Pure Dart — no Flutter imports.

/// Formats a duration expressed as total [minutes] into a Ukrainian short label.
///
/// Examples:
/// ```dart
/// DurationMinutes.format(30)  // "30 хв"
/// DurationMinutes.format(60)  // "1 год"
/// DurationMinutes.format(90)  // "1 год 30 хв"
/// ```
abstract final class DurationMinutes {
  static String format(int minutes) {
    if (minutes < 60) return '$minutes хв';
    final int h = minutes ~/ 60;
    final int m = minutes % 60;
    return m == 0 ? '$h год' : '$h год $m хв';
  }
}
