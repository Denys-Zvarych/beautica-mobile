// Phase 345 D5 — the FIRST pixel baseline for the salon «Архів» row.
//
// WHY THIS FILE EXISTS
// --------------------
// Phase 343 gave `MasterBookingCard` its attribution row — the "whose booking
// was this" line that only the salon host renders — and phase 345 D5 recorded
// the load-bearing fact that motivated this file: **there was no golden
// rendering `MasterBookingCard` by name at all.** `grep -a -rn
// "MasterBookingCard" test/golden/` returned zero files. The single baseline
// that touches this widget, `salon_bookings_board_golden_test.dart`, reaches it
// TRANSITIVELY through `bookings_timeline_grid.dart` and contains the card's
// name nowhere — so a name-grep for coverage of this widget was, and would
// remain, misleading.
//
// The card is also the one surface in the 342–345 track whose whole change is
// VISUAL. Everything else the track shipped is a query parameter, a family key,
// a route or a redirect — things a diff review can read. An extra name line
// inside a dense card, at three text scales and three widths, is not.
//
// WHAT THIS BASELINE IS NOT
// -------------------------
// It was generated from the tree it tests, so it is SELF-REFERENTIAL and is
// **not acceptance for phase 343's attribution row**
// (`project_golden_not_acceptance`). Correctness of the row — that it renders
// only when `showMasterAttribution` is true, that it carries the PERFORMING
// master's name rather than the viewer's, and that two masters render
// differently — is established independently, against rendered text and not
// against these bytes, by:
//
//   * `test/features/booking/presentation/master_booking_card_test.dart` (the
//     flag's own cases), and
//   * `integration_test/salon_archive_flow_test.dart`, which reads the two
//     names off the real render and asserts they DIFFER — mutation-proven
//     (collapsing the fixture to one master, and flipping the route's
//     `showMasterAttribution` to false, each turn it RED; observed
//     2026-09-19).
//
// This PNG's job from here is unintended pixel DRIFT, and nothing more. Do not
// cite it as evidence that the attribution row is correct.
//
// THE THREE CELLS
// ---------------
// Each width/scale pair renders one column of three cards, differing in
// exactly one axis each, so any pixel difference outside that axis is a
// regression:
//
//   1. WITHOUT attribution — the master hosts' shape, unchanged since before
//      phase 343. It is the CONTROL: if the attribution row ever leaked into
//      the default, this cell moves.
//   2. WITH attribution — the salon host's shape, same booking, same status,
//      same price. The ONLY intended delta between cells 1 and 2 is the name
//      line.
//   3. WITH attribution AND the «Відгук» CTA — a second performing master, so
//      the pair of names is visible side by side in one image, plus the
//      additive review slot the salon archive is the second host of.
//
// ⚠ `minHeight: MasterBookingCard.fullLayoutMinHeight` ON EVERY CELL, AND IT IS
// LOAD-BEARING. The card picks its body from `minHeight` alone
// (`_MasterBookingCardState._layout`), and a NULL `minHeight` resolves to the
// COMPACT body — which has no attribution row at all. The first draft of this
// file omitted it, and the mutation probe caught it immediately: forcing
// `attribute = false` in `master_booking_card.dart:1572` left all six baselines
// BYTE-IDENTICAL, i.e. the golden pinned nothing it claimed to. The archive
// screen passes `fullLayoutMinHeight` (`master_archive_screen.dart:1163`), so
// these cells now capture the body the archive actually renders. Re-probed
// after the fix: the same mutation turns all six RED. Do not drop this line.
//
// CLOCK: every instant here is a pinned UTC literal and the card reads no
// clock on these three cells — `now` is only consulted for the «Виконано»
// start-time gate (`onComplete != null`), which none of them pass. Nothing
// drifts with the host clock or `TZ`.
//
// MATRIX: the repo-standard `kGoldenWidths` × `kGoldenTextScales` sweep
// (320/360/414 dp × 1.0/1.3), which is the widest device coverage this
// alchemist harness offers — it has no tablet or desktop viewport, and
// inventing one for a single card would be a new convention rather than
// coverage. Recorded rather than silently narrowed.

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_booking_card.dart';
import 'package:flutter/material.dart';

import 'helpers/golden_pump.dart';

/// 09:00–10:30 Kyiv on a pinned past day. A literal, never `DateTime.now()`
/// and never a now-relative anchor: the card prints this range verbatim, so a
/// drifting anchor would silently re-typeset every baseline.
// future-date-ok: pinned past Kyiv wall-clock fixture — see the file header.
final DateTime _kStart = DateTime.utc(2026, 6, 10, 6);

Booking _row({
  required String id,
  required String masterFirstName,
  required String masterLastName,
  BookingStatus status = BookingStatus.completed,
  bool providerCanReviewClient = false,
}) => Booking(
  id: id,
  masterId: 'master-$id',
  masterFirstName: masterFirstName,
  masterLastName: masterLastName,
  masterType: 'SALON_MASTER',
  clientFirstName: 'Марія',
  clientLastName: 'Іванюк',
  serviceId: 'service-1',
  serviceName: 'Манікюр з покриттям',
  durationMinutes: 90,
  price: 450,
  startAt: _kStart,
  endAt: _kStart.add(const Duration(minutes: 90)),
  status: status,
  canReview: false,
  providerCanReviewClient: providerCanReviewClient,
);

void main() {
  for (final double width in kGoldenWidths) {
    for (final double scale in kGoldenTextScales) {
      final String suffix = widthScaleSuffix(width, scale);

      goldenTest(
        'salon archive card ${width.toInt()}dp text-${scale}x',
        fileName: 'salon_archive_card_$suffix',
        constraints: BoxConstraints.tight(Size(width, kGoldenHeight)),
        textScaleFactor: scale,
        pumpWidget: goldenPumpWidget(width: width),
        builder: () => GoldenTestGroup(
          columns: 1,
          children: <Widget>[
            GoldenTestScenario(
              name: 'no attribution (the master hosts)',
              child: _Cell(
                child: MasterBookingCard(
                  booking: _row(
                    id: 'a',
                    masterFirstName: 'Софія',
                    masterLastName: 'Бондар',
                  ),
                  onTap: () {},
                  minHeight: MasterBookingCard.fullLayoutMinHeight,
                ),
              ),
            ),
            GoldenTestScenario(
              name: 'with attribution (the salon host)',
              child: _Cell(
                child: MasterBookingCard(
                  booking: _row(
                    id: 'b',
                    masterFirstName: 'Софія',
                    masterLastName: 'Бондар',
                  ),
                  onTap: () {},
                  minHeight: MasterBookingCard.fullLayoutMinHeight,
                  showMasterAttribution: true,
                ),
              ),
            ),
            GoldenTestScenario(
              name: 'attribution + «Відгук», second master',
              child: _Cell(
                child: MasterBookingCard(
                  booking: _row(
                    id: 'c',
                    masterFirstName: 'Марія',
                    masterLastName: 'Гриценко',
                    providerCanReviewClient: true,
                  ),
                  onTap: () {},
                  onReview: () {},
                  minHeight: MasterBookingCard.fullLayoutMinHeight,
                  showMasterAttribution: true,
                ),
              ),
            ),
          ],
        ),
      );
    }
  }
}

/// The archive's own list geometry around one card: the brand base behind it
/// and the list's horizontal padding, so the capture shows the card at the
/// width it actually gets on the archive screen rather than edge-to-edge.
class _Cell extends StatelessWidget {
  const _Cell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: BrandColors.base,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: child,
    ),
  );
}
