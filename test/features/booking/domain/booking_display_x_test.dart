// QA (track 14.x booking) — unit suite for the [BookingDisplayX] extension.
//
// These getters are the SINGLE derivation point for "does money still apply",
// "who acted on this booking", "what are the master's initials" and "what is
// the composed address" — every booking surface (card, detail, cancel dialog,
// notes) reads them, so a drift here is a drift everywhere. Pure Dart: no
// widget tree, no ProviderScope.

import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_display_x.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:flutter_test/flutter_test.dart';

Booking _booking({
  required BookingStatus status,
  String masterFirstName = 'Марія',
  String masterLastName = 'Іванюк',
  String? salonName,
  String? cityLabel = 'Львів',
  String? districtLabel,
  String? street,
  String? buildingNo,
  int durationMinutes = 90,
}) {
  final DateTime start = DateTime.utc(2026, 7, 20, 15);
  return Booking(
    id: 'b1',
    masterId: 'm1',
    masterFirstName: masterFirstName,
    masterLastName: masterLastName,
    masterAvatarUrl: null,
    masterType: salonName != null ? 'SALON_MASTER' : 'INDEPENDENT_MASTER',
    salonName: salonName,
    serviceId: 's1',
    serviceName: 'Манікюр',
    categoryName: 'Манікюр',
    cityLabel: cityLabel,
    districtLabel: districtLabel,
    street: street,
    buildingNo: buildingNo,
    durationMinutes: durationMinutes,
    price: 650,
    startAt: start,
    endAt: start.add(Duration(minutes: durationMinutes)),
    status: status,
    canReview: false,
    clientComment: null,
    providerComment: null,
    clientCancellationNote: null,
    masterProfessionalTitle: null,
    locationNote: null,
  );
}

void main() {
  group('masterName / masterInitials', () {
    test('joins first + last name', () {
      expect(
        _booking(status: BookingStatus.confirmed).masterName,
        'Марія Іванюк',
      );
    });

    test('initials take the first letter of each name, upper-cased', () {
      expect(_booking(status: BookingStatus.confirmed).masterInitials, 'МІ');
    });

    test('falls back to "?" when both names are empty', () {
      expect(
        _booking(
          status: BookingStatus.confirmed,
          masterFirstName: '',
          masterLastName: '',
        ).masterInitials,
        '?',
      );
    });

    test('uses only the available letter when one name is empty', () {
      expect(
        _booking(
          status: BookingStatus.confirmed,
          masterLastName: '',
        ).masterInitials,
        'М',
      );
    });
  });

  group('atSalon / providerGenitive — drives «Салон» vs «Майстер» copy', () {
    test('a booking carrying a salonName is atSalon', () {
      expect(
        _booking(
          status: BookingStatus.declined,
          salonName: 'Lviv Nails',
        ).atSalon,
        isTrue,
      );
    });

    test('an independent-master booking (no salonName) is NOT atSalon', () {
      expect(_booking(status: BookingStatus.declined).atSalon, isFalse);
    });

    test('providerGenitive is «салону» at a salon, «майстра» otherwise', () {
      expect(
        _booking(
          status: BookingStatus.declined,
          salonName: 'Lviv Nails',
        ).providerGenitive,
        'салону',
      );
      expect(
        _booking(status: BookingStatus.declined).providerGenitive,
        'майстра',
      );
    });
  });

  group(
    'showsPrice — money is a true statement only for confirmed/completed',
    () {
      test('CONFIRMED shows the price', () {
        expect(_booking(status: BookingStatus.confirmed).showsPrice, isTrue);
      });

      test('COMPLETED shows the price', () {
        expect(_booking(status: BookingStatus.completed).showsPrice, isTrue);
      });

      test('CANCELLED suppresses the price', () {
        expect(_booking(status: BookingStatus.cancelled).showsPrice, isFalse);
      });

      test('DECLINED suppresses the price', () {
        expect(_booking(status: BookingStatus.declined).showsPrice, isFalse);
      });

      test(
        'NOT_COMPLETED suppresses the price (a no-show bill is ambiguous)',
        () {
          expect(
            _booking(status: BookingStatus.notCompleted).showsPrice,
            isFalse,
          );
        },
      );

      test('PENDING suppresses the price (not confirmed/completed)', () {
        expect(_booking(status: BookingStatus.pending).showsPrice, isFalse);
      });
    },
  );

  group('canAddToCalendar — CONFIRMED only', () {
    test('CONFIRMED can add to calendar', () {
      expect(
        _booking(status: BookingStatus.confirmed).canAddToCalendar,
        isTrue,
      );
    });

    for (final BookingStatus s in <BookingStatus>[
      BookingStatus.pending,
      BookingStatus.completed,
      BookingStatus.cancelled,
      BookingStatus.declined,
      BookingStatus.notCompleted,
    ]) {
      test('$s cannot add to calendar', () {
        expect(_booking(status: s).canAddToCalendar, isFalse);
      });
    }
  });

  group('addressLine / hasDestination', () {
    test('composes city + street + building when present', () {
      final Booking b = _booking(
        status: BookingStatus.confirmed,
        cityLabel: 'Львів',
        street: 'вул. Городоцька',
        buildingNo: '12',
      );
      expect(b.addressLine, contains('Львів'));
      expect(b.addressLine, contains('вул. Городоцька'));
      expect(b.addressLine, contains('12'));
    });

    test('addressLine is null when the provider has no location at all', () {
      final Booking b = _booking(
        status: BookingStatus.confirmed,
        cityLabel: null,
        districtLabel: null,
        street: null,
        buildingNo: null,
      );
      expect(b.addressLine, isNull);
    });

    test('hasDestination is true when there is a salon but no address', () {
      final Booking b = _booking(
        status: BookingStatus.confirmed,
        salonName: 'Lviv Nails',
        cityLabel: null,
      );
      expect(b.hasDestination, isTrue);
    });

    test('hasDestination is false with neither salon nor address', () {
      final Booking b = _booking(
        status: BookingStatus.confirmed,
        cityLabel: null,
        districtLabel: null,
        street: null,
        buildingNo: null,
      );
      expect(b.hasDestination, isFalse);
    });
  });
}
