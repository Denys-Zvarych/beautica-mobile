// Phase 274 — the ONE half-open time-window overlap predicate.
//
// Shared by the slot picker's client-side conflict exclusion
// (`slot_picker_screen.dart`'s `SlotTimeScreen`, via `excludeWindows` on
// `BookingSlotPickerArgs`) and, per phase-274 D2/the phase-275 file table,
// the salon multi-service schedule hub's own re-validation across all
// scheduled drafts. ONE implementation, two call sites — never a second
// hand-rolled copy (mobile-backlog REUSE-FIRST).
//
// THE COMPARISON IS HALF-OPEN. Strict inequality on BOTH sides: a window
// ending exactly when another begins is NOT a conflict. This mirrors the
// backend's own half-open interval semantics:
//   - the `no_overlapping_bookings` EXCLUDE constraint uses
//     `tstzrange(starts_at, ends_at, '[)')` (`V113__remove_pending_booking
//     _status.sql:49-52`);
//   - the client-conflict predicate is literally
//     `starts_at < :requestedEndsAt AND ends_at > :requestedStartsAt`
//     (`BookingRepository`'s native query).
// A naive `<=`/`>=` comparison would forbid legitimate BACK-TO-BACK
// bookings — the single most common thing a client wants when booking
// several services in one salon visit. See phase-274 D3.
//
// Pure Dart: no Flutter imports. The predicate takes plain `DateTime`
// start/end pairs rather than a `DateTimeRange` so it stays callable from
// pure-Dart code (a notifier's conflict derivation, a domain-layer test)
// without pulling in `package:flutter/material.dart` — callers holding a
// `DateTimeRange` just pass its `.start`/`.end`.

/// Whether window `[aStart, aEnd)` overlaps window `[bStart, bEnd)`,
/// half-open on both ends — two windows that only TOUCH (one's end equals
/// the other's start) do NOT overlap.
bool timeWindowsOverlap({
  required DateTime aStart,
  required DateTime aEnd,
  required DateTime bStart,
  required DateTime bEnd,
}) {
  // Strict both sides — `aStart.isBefore(bEnd)` is `aStart < bEnd`, and
  // `aEnd.isAfter(bStart)` is `aEnd > bStart`. Neither flips to
  // isBefore-or-equal / isAfter-or-equal: that is exactly the change the
  // phase-274 mutation check applies to prove the back-to-back cases go RED.
  return aStart.isBefore(bEnd) && aEnd.isAfter(bStart);
}
