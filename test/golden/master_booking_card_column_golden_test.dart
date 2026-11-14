// Phase 481 — `MasterBookingCard(column: true, fillServices: true)`, the
// «3 дні» narrow-column density, and `FreeTimeCard(column: true)`.
//
// 100 dp wide (a 360 dp phone's day column), every stored status at the three
// heights that exercise each layout: 34 dp (30 min at 1.0), 60 dp, 90 dp; plus
// the free marker at 34 / 45 dp. Reviewed against the MasterWeekBookings
// preview's `WeekBookingBlock` / `DeclaredFreeMarker`.
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/declared_time_cards.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_booking_card.dart';
import 'package:flutter/material.dart';

import 'helpers/golden_pump.dart';

const double _kColumnWidth = 100;
const List<double> _kHeights = <double>[34, 60, 90];
const double _kSceneWidth = 1500;

// future-date-ok: pinned Kyiv wall-clock fixture (10:00 Kyiv).
final DateTime _kStart = DateTime.utc(2026, 7, 20, 7);

Booking _row(BookingStatus status, int minutes) => Booking(
  id: '${status.name}-$minutes',
  masterId: 'master-1',
  masterFirstName: 'Оля',
  masterLastName: 'Коваль',
  masterType: 'INDEPENDENT_MASTER',
  clientFirstName: 'Олена',
  clientLastName: 'Коваленко',
  serviceId: 'service-1',
  serviceName: 'Манікюр з покриттям, корекція брів',
  durationMinutes: minutes,
  price: 650,
  startAt: _kStart,
  endAt: _kStart.add(Duration(minutes: minutes)),
  status: status,
  canReview: false,
);

const List<BookingStatus> _kStatuses = <BookingStatus>[
  BookingStatus.confirmed,
  BookingStatus.completed,
  BookingStatus.notCompleted,
  BookingStatus.cancelled,
  BookingStatus.declined,
];

void main() {
  for (final double scale in kGoldenTextScales) {
    final String suffix = scale == 1.0 ? '1x' : '1_3x';

    goldenTest(
      'master booking card column density text-${scale}x',
      fileName: 'master_booking_card_column_$suffix',
      constraints: BoxConstraints.tight(
        const Size(_kSceneWidth, kGoldenHeight),
      ),
      textScaleFactor: scale,
      pumpWidget: goldenPumpWidget(width: _kSceneWidth),
      builder: () => GoldenTestGroup(
        columns: _kStatuses.length,
        children: <Widget>[
          for (final double h in _kHeights)
            for (final BookingStatus status in _kStatuses)
              GoldenTestScenario(
                name: '${status.name} ${h.toInt()}dp',
                child: _Cell(
                  height: h,
                  child: MasterBookingCard(
                    booking: _row(status, 90),
                    onTap: () {},
                    column: true,
                    fillServices: true,
                  ),
                ),
              ),
          for (final double h in <double>[34, 45])
            GoldenTestScenario(
              name: 'free ${h.toInt()}dp',
              child: _Cell(
                height: h,
                child: const FreeTimeCard(
                  time: TimeOfDay(hour: 11, minute: 30),
                  column: true,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: BrandColors.base,
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: SizedBox(width: _kColumnWidth, height: height, child: child),
    ),
  );
}
