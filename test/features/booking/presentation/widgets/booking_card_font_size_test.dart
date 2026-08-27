// Regression guard for the 2026-07-15 compact-card font pass on `BookingCard`
// (feat/booking-auto-confirm): every text on the «МОЇ ЗАПИСИ» card was stepped
// DOWN one notch via new compact `VelvetText.booking*` tokens
// (bookingDayNumber 21→18, bookingTime 17→14, bookingCardName 12,
// bookingCardService 11, bookingCardPrice 10, bookingCardCaption 10,
// bookingCardSubtle 10).
//
// A font size is a single easily-reset scalar. A future edit could silently
// bump a token back up, or re-point a card `Text` at a larger shared token
// (`cardTitle` 14, `bodyStrong` 12, `statValue` 17 …), and no other booking
// test would notice — the overflow suite only proves nothing CLIPS, not that
// the type stayed compact, and a bigger-but-still-fitting font sails past it.
//
// This pins the compact contract two ways, so neither drift path is silent:
//
//   1. WIDGET level — pump a real BookingCard and read the RESOLVED `fontSize`
//      of each keyed body `Text` (time / master-name / service / price). This
//      catches BOTH a token bump AND a call-site swapped to a bigger token,
//      because it reads what actually renders. Keyed finders
//      (`time-`/`master-name-`/`service-`/`price-<id>`) couple to no localized
//      string (M2).
//   2. TOKEN level — assert every compact `VelvetText.booking*` token's
//      `fontSize` stays at or below its intended ceiling. This additionally
//      covers the two texts the card does NOT key — the date-stub day number
//      and the stub month / salon caption — and the professional-title subtle
//      line, so a bump there fails too.
//
// Ceilings are `<=`, not `==`: a FURTHER reduction is fine (still compact), an
// INCREASE fails. The whole point is "can't silently jump back UP".

import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

const String _cardId = 'fs';

/// The intended compact ceiling for each keyed card `Text`, in logical px.
/// Sourced from the 2026-07-15 compact-card pass in `velvet_text.dart`.
const double _timeCeiling = 14; // VelvetText.bookingTime
const double _nameCeiling = 12; // VelvetText.bookingCardName
const double _serviceCeiling = 11; // VelvetText.bookingCardService
const double _priceCeiling = 10; // VelvetText.bookingCardPrice

/// The two non-keyed card texts + the subtle title line, guarded at the token
/// level only.
const double _dayNumberCeiling = 18; // VelvetText.bookingDayNumber
const double _captionCeiling = 10; // VelvetText.bookingCardCaption
const double _subtleCeiling = 10; // VelvetText.bookingCardSubtle

/// A CONFIRMED booking so the price line renders (`price-` key exists), with a
/// salon + professional title so every body line is present.
Booking _booking() {
  final DateTime start = DateTime.utc(2026, 11, 28, 15);
  return Booking(
    id: _cardId,
    masterId: 'master-$_cardId',
    masterFirstName: 'Марія',
    masterLastName: 'Іванюк',
    masterAvatarUrl: null, // initials disc → no Image.network in the test
    masterType: 'SALON_MASTER',
    salonName: 'Lviv Nails Studio',
    serviceId: 'service-$_cardId',
    serviceName: 'Манікюр з покриттям',
    categoryName: 'NAIL_SERVICE',
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
    masterProfessionalTitle: 'Майстриня манікюру',
  );
}

double _keyedFontSize(WidgetTester tester, String key) {
  final Text text = tester.widget<Text>(
    find.byKey(ValueKey<String>('$key-$_cardId')),
  );
  final double? size = text.style?.fontSize;
  expect(
    size,
    isNotNull,
    reason: 'the «$key» card Text must carry an explicit fontSize token',
  );
  return size!;
}

void main() {
  group('BookingCard compact fonts — widget level', () {
    testWidgets(
      'every keyed body Text renders at or below its compact ceiling',
      (tester) async {
        await tester.pumpApp(
          Scaffold(
            body: BookingCard(booking: _booking(), onOpenDetails: () {}),
          ),
          width: 360,
        );
        await tester.pump();

        expect(
          _keyedFontSize(tester, 'time'),
          lessThanOrEqualTo(_timeCeiling),
          reason: 'date-stub time must stay compact (<= $_timeCeiling)',
        );
        expect(
          _keyedFontSize(tester, 'master-name'),
          lessThanOrEqualTo(_nameCeiling),
          reason: 'master name must stay compact (<= $_nameCeiling)',
        );
        expect(
          _keyedFontSize(tester, 'service'),
          lessThanOrEqualTo(_serviceCeiling),
          reason: 'service name must stay compact (<= $_serviceCeiling)',
        );
        expect(
          _keyedFontSize(tester, 'price'),
          lessThanOrEqualTo(_priceCeiling),
          reason: 'price figure must stay compact (<= $_priceCeiling)',
        );
      },
    );
  });

  group('BookingCard compact fonts — token level', () {
    // Guards the compact tokens directly, so a bump in velvet_text.dart fails
    // even for the two texts the card does not key (day number + caption) and
    // the subtle professional-title line.
    test('bookingDayNumber stays <= $_dayNumberCeiling', () {
      expect(
        VelvetText.bookingDayNumber.fontSize,
        lessThanOrEqualTo(_dayNumberCeiling),
      );
    });
    test('bookingTime stays <= $_timeCeiling', () {
      expect(VelvetText.bookingTime.fontSize, lessThanOrEqualTo(_timeCeiling));
    });
    test('bookingCardName stays <= $_nameCeiling', () {
      expect(
        VelvetText.bookingCardName.fontSize,
        lessThanOrEqualTo(_nameCeiling),
      );
    });
    test('bookingCardService stays <= $_serviceCeiling', () {
      expect(
        VelvetText.bookingCardService.fontSize,
        lessThanOrEqualTo(_serviceCeiling),
      );
    });
    test('bookingCardPrice stays <= $_priceCeiling', () {
      expect(
        VelvetText.bookingCardPrice.fontSize,
        lessThanOrEqualTo(_priceCeiling),
      );
    });
    test('bookingCardCaption stays <= $_captionCeiling', () {
      expect(
        VelvetText.bookingCardCaption.fontSize,
        lessThanOrEqualTo(_captionCeiling),
      );
    });
    test('bookingCardSubtle stays <= $_subtleCeiling', () {
      expect(
        VelvetText.bookingCardSubtle.fontSize,
        lessThanOrEqualTo(_subtleCeiling),
      );
    });
  });
}
