// Phase 7.10 — the hour-label gutter for the master timeline
// (`BookingsTimelineGrid`).
//
// Transcribed from the approved design's `_TimelineGrid` time-label column
// (`docs/signup-designs/SalonManagementDesign/lib/widgets/
// bookings_toolbar.dart:1385-1411`) — floating right-aligned hour labels, no
// card/background (the design draws none here), one per [_kHourH] of
// vertical space.
//
// [firstHour]/[lastHour] are HOURS-SINCE-THE-SELECTED-KYIV-DAY'S-MIDNIGHT
// offsets, NOT wall-clock hours — they can exceed 23 when the timeline's
// extent crosses into the next calendar day (see `bookings_timeline_grid
// .dart`'s R1 fix header). [_wallClockLabel] is what turns such an offset
// back into a real clock reading: hour 24 reads "00:00", hour 25 reads
// "01:00" — never "24:00"/"25:00".

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

/// The gutter column of hour labels beside [BookingsTimelineGrid]'s lane
/// area — one label per hour from [firstHour] to [lastHour] inclusive.
class TimelineHourRuler extends StatelessWidget {
  const TimelineHourRuler({
    required this.firstHour,
    required this.lastHour,
    super.key,
  }) : assert(lastHour >= firstHour, 'lastHour must not precede firstHour');

  /// Hours-since-day-start of the first (topmost) label.
  final int firstHour;

  /// Hours-since-day-start of the last (bottommost, emphasised) label.
  final int lastHour;

  /// Column width — wide enough for "23:00" right-aligned.
  ///
  /// Finding #7 (design-parity pass): 42dp, down from the design's own 46dp —
  /// combined with `BookingsTimelineGrid`'s own reduced ruler↔grid gap, this
  /// nudges the whole timeline grid slightly left, closer to the approved
  /// design. Still comfortably fits "23:00" at [VelvetText.timelineHourLabel]'s
  /// 11 sp at ordinary and moderately scaled-up text sizes.
  static const double _kRulerWidth = 42;

  /// One hour of vertical space — MUST match
  /// `BookingsTimelineGrid._kHourH` so the ruler and the lane hairlines line
  /// up pixel-for-pixel.
  static const double _kHourH = 72;

  /// The vertical distance each label's text visually sits ABOVE its own
  /// hour line so the text centres on the line instead of hanging below it.
  ///
  /// This constant does NOT nudge the labels themselves (see the clipping
  /// bug this avoids, below) — [BookingsTimelineGrid] applies it as a
  /// leading `Padding` on the gridline/card `Stack` instead, shifting THAT
  /// stack down by this amount so the same 7dp visual relationship holds
  /// between every label and its line.
  ///
  /// CLIPPING BUG (fixed): an earlier version subtracted this constant from
  /// each label's own `top`, which for `i == 0` produced `top: -7` — 7dp
  /// above this widget's own origin. `TimelineHourRuler`'s `Stack` uses
  /// `clipBehavior: Clip.none` so it doesn't clip that itself, but the
  /// ANCESTOR `SingleChildScrollView` in `bookings_timeline_grid.dart` (the
  /// real vertical scroller for the whole timeline) defaults to
  /// `Clip.hardEdge`, and at rest (scroll offset 0, Android's clamping
  /// physics giving no overscroll) that permanently clipped the very top of
  /// the first hour label. Shifting the OTHER stack down instead means no
  /// label `top` can ever go negative in the first place — the ruler's own
  /// labels are always laid out at `top: i * _kHourH`, i.e. `>= 0` by
  /// construction, for every `i` including `0`.
  static const double labelCenteringNudge = 7;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final int totalHours = lastHour - firstHour;
    return Semantics(
      label: l10n.masterBookingsTimelineHourRulerSemantics,
      container: true,
      child: SizedBox(
        width: _kRulerWidth,
        height: (totalHours + 1) * _kHourH,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            for (int i = 0; i <= totalHours; i++)
              Positioned(
                top: i * _kHourH,
                right: 0,
                child: Text(
                  _wallClockLabel(firstHour + i),
                  textAlign: TextAlign.right,
                  style: i == totalHours
                      ? VelvetText.timelineHourLabelAccent
                      : VelvetText.timelineHourLabel,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Renders an hours-since-day-start offset as its wall-clock label —
/// `hour % 24` so an offset of 24 reads "00:00" and 25 reads "01:00" rather
/// than "24:00"/"25:00".
String _wallClockLabel(int hoursSinceDayStart) {
  final int wallClockHour = hoursSinceDayStart % 24;
  return '${wallClockHour.toString().padLeft(2, '0')}:00';
}
