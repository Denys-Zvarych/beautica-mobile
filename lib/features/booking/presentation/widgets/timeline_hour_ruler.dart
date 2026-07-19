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
  static const double _kRulerWidth = 46;

  /// One hour of vertical space — MUST match
  /// `BookingsTimelineGrid._kHourH` so the ruler and the lane hairlines line
  /// up pixel-for-pixel.
  static const double _kHourH = 72;

  /// Nudges each label so its text vertically centres on its hour line
  /// instead of hanging below it.
  static const double _kLabelCenteringNudge = 7;

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
                top: i * _kHourH - _kLabelCenteringNudge,
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
