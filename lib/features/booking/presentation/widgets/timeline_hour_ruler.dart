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

import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

import 'timeline_density.dart';

/// The gutter column of hour labels beside [BookingsTimelineGrid]'s lane
/// area — one label per hour from [firstHour] to [lastHour] inclusive.
class TimelineHourRuler extends StatelessWidget {
  const TimelineHourRuler({
    required this.firstHour,
    required this.lastHour,
    this.density = TimelineDensity.master,
    super.key,
  }) : assert(lastHour >= firstHour, 'lastHour must not precede firstHour');

  /// Hours-since-day-start of the first (topmost) label.
  final int firstHour;

  /// Hours-since-day-start of the last (bottommost, emphasised) label.
  final int lastHour;

  /// Phase 21.12 — the scope's geometry token. Defaults to
  /// [TimelineDensity.master], which resolves [TimelineDensity.rulerWidth] to
  /// `42` and [TimelineDensity.hourHeight] to `120` — byte-for-byte the two
  /// constants this widget used to hold, so every pre-existing call site (the
  /// grid's own, and the tests that pump this widget bare) renders exactly as
  /// before without passing anything.
  ///
  /// The salon board passes [TimelineDensity.salon]. It MUST be the same token
  /// the hosting [BookingsTimelineGrid] was handed — the grid passes its own
  /// down, so they cannot disagree.
  final TimelineDensity density;

  /// The retired `_kRulerWidth`, kept as the name the ADDENDUM prose in
  /// `bookings_timeline_grid.dart` and `bookings_discovery_view.dart` cites.
  /// Equal to `TimelineDensity.master.rulerWidth` by construction (pinned by
  /// `test/features/booking/presentation/widgets/salon_bookings_board_test
  /// .dart`'s «TimelineDensity.master reduces to the shipped constants» group
  /// — NOT by `bookings_timeline_grid_test.dart`, which this doc used to name
  /// and which asserts nothing about these two constants); read [density] on
  /// any render path.
  ///
  /// Finding #7 (design-parity pass): 42dp, down from the design's own 46dp —
  /// combined with `BookingsTimelineGrid`'s own reduced ruler↔grid gap, this
  /// nudges the whole timeline grid slightly left, closer to the approved
  /// design. Still comfortably fits "23:00" at [VelvetText.timelineHourLabel]'s
  /// 11 sp at ordinary and moderately scaled-up text sizes.
  static const double kMasterRulerWidth = 42;

  /// The retired `_kHourH`, kept for the same reason as [kMasterRulerWidth].
  ///
  /// History: `72` → `112` → `168` → **`120`**. It used to be a single number
  /// spelled TWICE — here and as `BookingsTimelineGrid._kHourH` — coupled only
  /// by a comment plus a test asserting they agree. Both now read
  /// [TimelineDensity.hourHeight], so they cannot desync at all; see
  /// `timeline_density.dart`'s header. `bookings_timeline_grid.dart`'s
  /// "ADDENDUM 8" is still where the MASTER scope's `120` is justified (short
  /// version: the MICRO card layout removed the `56dp` legibility floor that
  /// was forcing the scale up to `168`, and `120` is the smallest round scale
  /// at which a 60-minute band still clears the full layout's natural height —
  /// `118dp` since the card's ROW-1 GLYPH pass, so the clearance is `2dp`).
  static const double kMasterHourHeight = 120;

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
  /// labels are always laid out at `top: i * hourHeight`, i.e. `>= 0` by
  /// construction, for every `i` including `0`.
  ///
  /// Phase 21.12 — DELIBERATELY NOT scaled by [density]. It is half a MEASURED
  /// label height, and [TimelineDensity]'s locked rule is that geometry scales
  /// and typography does not: the label is the same 11 sp glyph at every
  /// scale, so the distance that centres it on its line is the same too.
  /// Scaling it (as the partial design preview does) would hang every
  /// salon-scope label ~2dp below its own hour line. See
  /// `timeline_density.dart`'s "WHAT IS NOT HERE, AND WHY".
  static const double labelCenteringNudge = 7;

  /// Blank space kept below the LAST hour label so the bottom-most card is not
  /// flush against the end of the scroll — `VelvetSpacing.lg`, the same
  /// bottom-of-list breathing room the rest of the app uses.
  static const double _kTrailingMargin = VelvetSpacing.lg;

  /// The rendered height of one hour label at the ambient text scale, measured
  /// rather than assumed.
  ///
  /// [VelvetText.timelineHourLabelAccent] (the BOTTOM-most label, and the one
  /// this height has to clear) inherits Nunito's natural line height instead of
  /// pinning an explicit `height:`, so the label box is a font-metric product
  /// — ~15dp at 11sp / textScaler 1.0 — that no arithmetic here can honestly
  /// predict. A one-shot [TextPainter] on a fixed-width digit string is the
  /// derivation: it reads the real style through the real [TextScaler], so a
  /// font swap or an accessibility text-size bump moves this with it.
  ///
  /// The string is "00:00" and not the real label because every label is five
  /// characters of tabular-width digits and a colon — same line box, and this
  /// way the measurement does not depend on which hours the day spans.
  static double _labelHeight(BuildContext context) {
    final TextPainter painter = TextPainter(
      text: TextSpan(text: '00:00', style: VelvetText.timelineHourLabelAccent),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final double height = painter.height;
    painter.dispose();
    return height;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final int totalHours = lastHour - firstHour;
    // Phase 21.12 — read off [density] rather than the retired per-file
    // constants. At [TimelineDensity.master] these resolve to 42 / 120, which
    // is exactly what the constants held.
    final double rulerWidth = density.rulerWidth;
    final double hourHeight = density.hourHeight;
    return Semantics(
      label: l10n.masterBookingsTimelineHourRulerSemantics,
      container: true,
      child: SizedBox(
        width: rulerWidth,
        // THE TRAILING DEAD HOUR IS GONE (2026-07-24)
        // -----------------------------------------------------------------
        // This was `(totalHours + 1) * hourHeight`, i.e. one FULL empty hour
        // below the last label — 168dp at the old scale, on every single day.
        // `BookingsTimelineGrid` draws its last gridline at
        // `totalHours * hourHeight`, so that extra hour was pure dead scroll
        // beyond the end of the ruled area, and (since the ruler and the lane
        // stack sit in the same `Row`) it usually DOMINATED the row's height,
        // making the whole timeline scroll past its own content.
        //
        // The honest extent is: the last label's own top offset, plus enough
        // room to actually draw that label, plus a bottom margin so the last
        // card is not flush against the scroll end. Nothing is guessed — the
        // label term is measured (see [_labelHeight]).
        height:
            totalHours * hourHeight + _labelHeight(context) + _kTrailingMargin,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            for (int i = 0; i <= totalHours; i++)
              Positioned(
                top: i * hourHeight,
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
