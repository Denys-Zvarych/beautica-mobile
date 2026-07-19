// Phase 7.10 — the master timeline body: the hour ruler + the absolutely-
// positioned booking-card grid, laid out from the overlap-lane assignment in
// `booking_lane_layout.dart`.
//
// Transcribed from the approved design's `_TimelineGrid`
// (`docs/signup-designs/SalonManagementDesign/lib/widgets/
// bookings_toolbar.dart:1336-1459`), WITH the design's latent negative-height
// bug fixed — see "R1" below. No providers, no navigation, no async: this is
// a pure rendering layer over a plain `List<Booking>`; Phase 7.11 wires it
// into the screen.
//
// ============================================================================
// R1 — THE BUG THE DESIGN HIDES, FIXED HERE
// ============================================================================
// The design computes its vertical extent from SCALAR hours-of-day:
//   final int firstHour = bookings.map((b) => b.dateTime.hour).reduce(min);
//   final double latestEndH = (latestEnd.hour - firstHour) + latestEnd.minute / 60.0;
//   final double gridHeight = latestEndH * _kHourH;
// `latestEnd.hour` discards the DATE, so `gridHeight` goes NEGATIVE whenever
// the last booking's end hour-of-day is numerically smaller than the first
// booking's start hour-of-day — reachable on a SINGLE day: a 23:30 booking
// with a 60-minute service ends 00:30 the next day (hour `0`), so with
// `firstHour = 9` the design's formula yields `(0 - 9) + 0.5 = -8.5` and the
// unguarded `SizedBox(height:)` throws. Single-day rendering (Phase 7.9)
// does NOT close this hole — it only closes the design's OTHER latent bug,
// cards from different days superimposing (moot here since every list this
// widget ever receives is one day's worth).
//
// THE FIX: compute the extent in MINUTES-SINCE-THE-SELECTED-KYIV-DAY'S-
// MIDNIGHT instead of scalar hours. A booking ending after midnight then
// yields a value > 1440 rather than wrapping to a small number, so
// monotonicity holds by construction and the subtraction cannot go negative.
// [_lastMinuteFloor] is the belt-and-braces floor on top of that: even if
// every booking were somehow malformed, the grid is never shorter than one
// hour.
//
// ============================================================================
// THE RULER IS THE KYIV WALL-CLOCK
// ============================================================================
// Every card's vertical position reads through [toBeauticaTime] — `Booking
// .startAt` is canonical UTC, so reading `.hour`/`.minute` off it directly
// would render the wrong row on any non-Kyiv device (and on CI's UTC
// runner). Never `.toLocal()`.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../domain/booking.dart';
import '../../domain/booking_lane_layout.dart';
import 'master_booking_card.dart';
import 'timeline_hour_ruler.dart';

/// The master timeline body for ONE Kyiv calendar day: an hour ruler plus an
/// absolutely-positioned, non-lazy card grid. Acceptable to fully materialise
/// (no lazy building) because the input is provably bounded to a single day
/// (Phase 7.9) — do NOT generalise this widget to an unbounded list.
///
/// SEC (LOW-5): the non-lazy `Stack` has a second cost beyond render work —
/// EVERY card's client-name-bearing `Semantics` node (`master_booking_card
/// .dart`) exists in the accessibility tree for the whole day at once, not
/// just the on-screen ones. The retired `ListView.builder` virtualized, so
/// only visible cards were ever exposed. `FLAG_SECURE` (acquired by the
/// hosting screen's `ScreenProtectionManager`) blocks screenshots/screen
/// recording but does NOT gate the Android Accessibility API, so a hostile
/// accessibility-service app can enumerate a full day's client names in one
/// sweep instead of only what is visible on screen. This is an ACCEPTED
/// trade-off, not an oversight: `size: 100` already bounds how much PII a
/// single day can ever expose this way (see `bookings_day_notifier.dart`),
/// and a lazily-built list cannot absolutely-position lanes against a shared
/// hour ruler — reintroducing one here would resurrect the R1-adjacent
/// layout bugs this non-lazy `Stack` exists to avoid. Do NOT restructure
/// this widget to "fix" either dimension of the trade-off.
class BookingsTimelineGrid extends StatelessWidget {
  const BookingsTimelineGrid({
    required this.bookings,
    required this.day,
    required this.onBookingTap,
    super.key,
  });

  /// One Kyiv day's bookings, in SERVER order (`startsAt` ASC) — rendered
  /// directly; never mutated or re-sorted here (see [assignLanes]).
  final List<Booking> bookings;

  /// The selected Kyiv calendar day, date-only — the anchor
  /// [_minutesSinceDayStart] measures every card position against.
  final DateTime day;

  /// Fires with the tapped booking. No `Navigator`/`context.push` in this
  /// leaf widget — the caller (Phase 7.11) owns navigation.
  final ValueChanged<Booking> onBookingTap;

  /// One hour of vertical space — MUST match
  /// `TimelineHourRuler._kHourH` so the ruler and the lane hairlines line up.
  static const double _kHourH = 72;

  /// One lane's card width.
  static const double _kCardW = 272;

  /// Floor so a 15-minute booking's card stays a real tap target.
  static const double _kMinCardHeight = 48;

  @override
  Widget build(BuildContext context) {
    final List<int> lanes = assignLanes(bookings);
    final int lanesCount = laneCount(lanes);

    // ------------------------------------------------------------------
    // R1 FIX — minutes-since-[day]'s-Kyiv-midnight, never scalar hours.
    //
    // [_minutesSinceDayStart] anchors every instant to the SAME Kyiv
    // midnight, so a booking ending after midnight yields a value > 1440
    // rather than wrapping to a small number — monotonicity holds by
    // construction and `lastMinute - firstMinute` cannot go negative. The
    // `math.max(..., firstMinute + 60)` floor is belt-and-braces on top of
    // that: even a single, zero-duration-adjacent booking still renders at
    // least one hour of ruler. See the file header's R1 section.
    // ------------------------------------------------------------------
    final int firstMinute = bookings.isEmpty
        ? 0
        : bookings
              .map((Booking b) => _minutesSinceDayStart(b.startAt, day))
              .reduce(math.min);
    final int lastMinuteCandidate = bookings.isEmpty
        ? firstMinute + 60
        : bookings
              .map(
                (Booking b) =>
                    _minutesSinceDayStart(b.startAt, day) + b.durationMinutes,
              )
              .reduce(math.max);
    // Floor: the grid is never shorter than one hour, whatever the data says.
    final int lastMinute = math.max(lastMinuteCandidate, firstMinute + 60);

    final double gridHeight = (lastMinute - firstMinute) / 60.0 * _kHourH;
    assert(gridHeight > 0, 'R1 invariant: gridHeight must always be positive');

    final int firstHour = firstMinute ~/ 60;
    final int lastHour = (lastMinute / 60.0).ceil();

    final double contentWidth = lanesCount == 0
        ? _kCardW
        : lanesCount * _kCardW + (lanesCount - 1) * VelvetSpacing.sm;

    return SingleChildScrollView(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TimelineHourRuler(firstHour: firstHour, lastHour: lastHour),
          const SizedBox(width: VelvetSpacing.sm),
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final double contentW = math.max(
                  contentWidth,
                  constraints.maxWidth,
                );
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: contentW,
                    height: gridHeight,
                    child: Stack(
                      key: const ValueKey<String>('timeline-lane-stack'),
                      children: <Widget>[
                        for (int i = firstHour; i <= lastHour; i++)
                          Positioned(
                            top: (i - firstHour) * _kHourH,
                            left: 0,
                            right: 0,
                            height: 1,
                            child: const ColoredBox(color: BrandColors.faint),
                          ),
                        for (int i = 0; i < bookings.length; i++)
                          _positionedCard(bookings[i], lanes[i], firstMinute),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _positionedCard(Booking booking, int lane, int firstMinute) {
    final int startMinute = _minutesSinceDayStart(booking.startAt, day);
    final double top = (startMinute - firstMinute) / 60.0 * _kHourH;
    final double height = math.max(
      _kMinCardHeight,
      booking.durationMinutes / 60.0 * _kHourH,
    );
    return Positioned(
      key: ValueKey<String>('timeline-card-position-${booking.id}'),
      top: top,
      left: lane * (_kCardW + VelvetSpacing.sm),
      width: _kCardW,
      height: height,
      // MEDIUM-1 (perf): `MasterBookingCard` is a `StatefulWidget` whose
      // press state drives an `AnimatedScale` (110ms) + `AnimatedContainer`
      // (150ms) — without a boundary, one card's press animation dirties the
      // whole shared `Stack` layer, so at the ~100-card ceiling a single tap
      // could repaint the entire grid. Same pattern as `calendar_button.dart`
      // and `booking_status_medallion.dart`.
      child: RepaintBoundary(
        child: MasterBookingCard(
          key: ValueKey<String>('timeline-card-${booking.id}'),
          booking: booking,
          onTap: () => onBookingTap(booking),
          width: _kCardW,
          height: height,
        ),
      ),
    );
  }
}

/// Minutes between [day]'s Kyiv midnight and [instant]'s Kyiv wall-clock —
/// the R1 fix's anchor. A booking ending after midnight yields a value
/// **greater than 1440** rather than wrapping to a small number, so
/// monotonicity holds by construction.
int _minutesSinceDayStart(DateTime instant, DateTime day) {
  final tz.TZDateTime local = toBeauticaTime(instant);
  final tz.TZDateTime midnight = tz.TZDateTime(
    beauticaZone,
    day.year,
    day.month,
    day.day,
  );
  return local.difference(midnight).inMinutes;
}
