// Regression guard for the master/provider name line-wrap tweak on
// `BookingCard` (feat/booking-auto-confirm): the name `Text` was changed from
// `maxLines: 1` to `maxLines: 2` (+ `softWrap: true`, keeping
// `overflow: TextOverflow.ellipsis`) so a long «Ім'я Прізвище» wraps to a
// second line instead of being cut mid-name.
//
// `maxLines` is a single easily-reset scalar — a future refactor could silently
// revert it to 1 and no other booking test would notice (the overflow suite
// keys off the SERVICE name, not the master name). This pins the master-name
// `Text`'s wrapping contract directly on the widget property, not via a pixel
// render — cheap, deterministic, and impossible to satisfy by accident.
//
// The name `Text` is found by its `ValueKey('master-name-<id>')` (mirrors the
// card's sibling keys `time-` / `service-` / `price-` / `stub-`), so the finder
// couples to no localized string. The fixture uses a deliberately long
// two-word name so a real revert to `maxLines: 1` would also visibly clip.

import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

const String _cardId = 'wrap';
const Key _nameKey = ValueKey<String>('master-name-$_cardId');

Booking _booking() {
  final DateTime start = DateTime.utc(2026, 11, 28, 15);
  return Booking(
    id: _cardId,
    masterId: 'master-$_cardId',
    // A long, two-word name — the exact case the tweak exists to serve.
    masterFirstName: 'Олександра-Валентина',
    masterLastName: 'Коваленко-Тестівська-Довгопрізвищенко',
    masterAvatarUrl: null, // initials disc → no Image.network in the test
    masterType: 'INDEPENDENT_MASTER',
    salonName: null,
    serviceId: 'service-$_cardId',
    serviceName: 'Манікюр з покриттям',
    categoryName: 'Манікюр',
    cityLabel: 'Львів',
    districtLabel: 'Залізничний район',
    street: 'вулиця Тестова',
    buildingNo: '15А',
    durationMinutes: 90,
    price: 650,
    startAt: start,
    endAt: start.add(const Duration(minutes: 90)),
    status: BookingStatus.confirmed,
    canReview: false,
    masterProfessionalTitle: null,
  );
}

void main() {
  testWidgets(
    'master name Text wraps to two lines (maxLines: 2, softWrap, ellipsis)',
    (tester) async {
      await tester.pumpApp(
        Scaffold(
          body: BookingCard(booking: _booking(), onOpenDetails: () {}),
        ),
        // Narrow phone so the long name genuinely needs the second line.
        width: 320,
      );
      await tester.pump();

      final Text name = tester.widget<Text>(find.byKey(_nameKey));

      // The load-bearing contract: NEVER silently revert to a single line.
      expect(
        name.maxLines,
        2,
        reason:
            'master name must wrap to two lines — reverting to maxLines: 1 '
            'cuts a long «Ім\'я Прізвище» mid-name',
      );
      expect(name.softWrap, isTrue);
      // The ellipsis stays as the defensive floor for a pathological name.
      expect(name.overflow, TextOverflow.ellipsis);
    },
  );
}
