// Phase 293 D3 — the first pixel baseline for `BookingCard`'s salon-name row.
//
// WHY THIS FILE EXISTS
// --------------------
// Phase 293 promoted `BookingCard`'s inline salon-name row into the shared
// `BookingSalonRow` widget so a later phase (294) can reuse it on
// `MasterBookingCard` without hand-copying the glyph + text pairing. Per
// CLAUDE.md's REUSE-FIRST rule and this phase's own D3 acceptance criterion,
// the promotion is only "golden-verified, not eyeballed" if a golden actually
// RENDERS `BookingCard` with a `salonName` set — before this file, `grep -a
// -rn "BookingCard" test/golden/` matched zero files. The one golden that
// grep hit on a substring, `salon_archive_card_golden_test.dart`, renders
// `MasterBookingCard` — a different widget — so the promotion had NO pixel
// baseline of any kind protecting it. Mutating `BookingSalonRow`'s icon size
// from 12 to 20 left every existing test green (see the mutation log in the
// QA report that added this file).
//
// WHAT THIS BASELINE IS
// ----------------------
// Generated against the ORIGINAL (pre-promotion) `booking_card.dart` — the
// revision with the salon row still inlined in `_identity()`, before
// `BookingSalonRow` existed — then re-run UNCHANGED against the refactored,
// `BookingSalonRow`-backed card. A green run WITHOUT `--update-goldens` is the
// proof the promotion is D3-compliant: identical bytes before and after. If
// this ever needs regenerating, the promotion changed rendering and is
// WRONG — do not regenerate to make it pass
// (`project_golden_not_acceptance.md`: a regenerated golden is
// self-referential and proves nothing).
//
// THREE CELLS
// -----------
//   1. live (CONFIRMED)   — the lively accent/secondary palette.
//   2. dimmed (CANCELLED) — the muted/faint palette swap.
//   3. long salon name    — ellipsises to one line instead of wrapping or
//      pushing the card wider.
//
// Single width/scale cell (360dp × 1.0x): this baseline exists to pin the
// SALON ROW specifically, not to re-sweep `BookingCard`'s own responsive
// matrix — that's already covered by
// `booking_surfaces_overflow_test.dart`'s 9-cell stress grid.
//
// CLOCK: `_kStart` is a pinned past UTC literal; none of these three cells
// read a live clock.

import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_card.dart';
import 'package:flutter/material.dart';

import 'helpers/golden_pump.dart';

final DateTime _kStart = DateTime.utc(2026, 6, 10, 9);

Booking _booking({
  required String id,
  required BookingStatus status,
  required String salonName,
}) => Booking(
  id: id,
  masterId: 'master-$id',
  masterFirstName: 'Софія',
  masterLastName: 'Бондар',
  masterAvatarUrl: null,
  masterType: 'SALON_MASTER',
  salonName: salonName,
  serviceId: 'service-$id',
  serviceName: 'Манікюр з покриттям',
  durationMinutes: 90,
  price: 650,
  startAt: _kStart,
  endAt: _kStart.add(const Duration(minutes: 90)),
  status: status,
  canReview: false,
);

void main() {
  goldenTest(
    'booking card salon row 360dp text-1x',
    fileName: 'booking_card_salon_row_360_1x',
    constraints: BoxConstraints.tight(const Size(360, 900)),
    textScaleFactor: 1.0,
    pumpWidget: goldenPumpWidget(width: 360),
    builder: () => GoldenTestGroup(
      columns: 1,
      children: <Widget>[
        GoldenTestScenario(
          name: 'live (CONFIRMED)',
          child: BookingCard(
            booking: _booking(
              id: 'a',
              status: BookingStatus.confirmed,
              salonName: 'Lviv Nails Studio',
            ),
            onOpenDetails: () {},
          ),
        ),
        GoldenTestScenario(
          name: 'dimmed (CANCELLED)',
          child: BookingCard(
            booking: _booking(
              id: 'b',
              status: BookingStatus.cancelled,
              salonName: 'Lviv Nails Studio',
            ),
            onOpenDetails: () {},
          ),
        ),
        GoldenTestScenario(
          name: 'long salon name ellipsises',
          child: BookingCard(
            booking: _booking(
              id: 'c',
              status: BookingStatus.confirmed,
              salonName:
                  'Салон краси та естетичної косметології «Прекрасна Довга Мить»',
            ),
            onOpenDetails: () {},
          ),
        ),
      ],
    ),
  );
}
