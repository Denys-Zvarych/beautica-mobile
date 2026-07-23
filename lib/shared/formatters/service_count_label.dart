// Phase 14.1 — Ukrainian plural helper for "N послуг" style count labels.
//
// Mirrors the pre-existing, accepted `_serviceWordUk` / `_countLabel` private
// helpers already duplicated in `services_list_screen.dart` (master's own
// catalogue) and the approved booking preview apps
// (`docs/signup-designs/BookingServiceSelection/lib/widgets/booking_summary.dart`)
// — those are explicitly NOT routed through ARB ICU plural rules ("will
// migrate to ARB once copy is approved" — LOW backlog). Hoisted here as a
// single shared helper so the booking feature's THREE call sites (service
// selector summary, slot-picker summary, category header badges) don't
// re-duplicate the same plural logic a third/fourth time.
//
// Pure Dart — no Flutter imports.

/// Formats [count] with its correctly-declined Ukrainian "послуга/послуги/послуг"
/// noun, e.g. `formatServiceCountUk(1)` → "1 послуга".
String formatServiceCountUk(int count) {
  final int mod100 = count % 100;
  final int mod10 = count % 10;
  final String word;
  if (mod100 >= 11 && mod100 <= 14) {
    word = 'послуг';
  } else if (mod10 == 1) {
    word = 'послуга';
  } else if (mod10 >= 2 && mod10 <= 4) {
    word = 'послуги';
  } else {
    word = 'послуг';
  }
  return '$count $word';
}
