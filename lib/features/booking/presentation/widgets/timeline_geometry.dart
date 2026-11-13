// Phase 482 — the timeline geometry shared by the single-day
// `BookingsTimelineGrid` and the week `WeekTimeGrid`.
//
// Promoted (not copied) out of `bookings_timeline_grid.dart`, where both
// functions were private (`_cardMinHeightFor`, `_minutesSinceDayStart`). The
// old grid now calls these — same expressions, same numbers.
//
// [minutesSinceDayStart] itself lives in `shared/time/kyiv_day.dart` (the
// domain-layer week model needs it and may not import presentation); it is
// re-exported here so a grid imports its geometry from ONE file.

import 'dart:math' as math;

import 'master_booking_card.dart';

export 'package:beautica_mobile/shared/time/kyiv_day.dart'
    show kyivMidnight, minutesSinceDayStart;

/// A booking's proportional-duration card floor — see
/// `bookings_timeline_grid.dart`'s "ADDENDUM 2" for the original derivation
/// and "ADDENDUM 8" for the current floor. Proportional to [durationMinutes]
/// against [hourHeight], floored at the MICRO card's natural height
/// ([MasterBookingCard.microLayoutNaturalHeight]) — the shortest box
/// `MasterBookingCard` can render anything legible in.
///
/// THE FLOOR IS THE SMALLEST OF THE CARD'S THREE NATURALS, ON PURPOSE. It used
/// to be [MasterBookingCard.estimatedNaturalHeight] (the COMPACT body's),
/// which meant every booking whose band was shorter than that got a box
/// taller than its own wall-clock footprint. Now that the card has a micro
/// shape, the floor drops with it and the overrun only survives below ~14
/// minutes.
///
/// STILL INDEPENDENT OF THE 30-MINUTE SLOT (`hourHeight / 2`): the slot
/// governs the gridlines, the card's own natural governs the card. Tying the
/// floor back to the slot would re-inflate every short card off its end-time
/// line.
///
/// A MINIMUM, not an exact size — [MasterBookingCard] applies it as a
/// `BoxConstraints.minHeight`, so real content taller than this value always
/// wins (see that widget's class doc).
double cardMinHeightFor(int durationMinutes, double hourHeight) {
  final double proportional = durationMinutes / 60.0 * hourHeight;
  return math.max(proportional, MasterBookingCard.microLayoutNaturalHeight);
}
