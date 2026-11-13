// Phase 487 — BookingCreateSeed: the empty week-grid tap's `?at=` hint
// (query round-trip, malformed input, DST wall clock) and pickSeededSlot (D3).
//
// Every fixture year is in the PAST on purpose: the seed and the picker are
// pure over their inputs and never read the clock, so no instant here is ever
// compared against "now".
import 'package:beautica_mobile/features/booking/domain/booking_create_seed.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot.dart';
import 'package:flutter_test/flutter_test.dart';

BookingSlot _slot(DateTime startUtc, {bool available = true}) => BookingSlot(
  startAt: startUtc,
  endAt: startUtc.add(const Duration(minutes: 60)),
  available: available,
);

void main() {
  group('query round-trip', () {
    test('toQuery renders Kyiv wall clock YYYY-MM-DDTHH:mm', () {
      final BookingCreateSeed seed = BookingCreateSeed(
        day: DateTime(2025, 11, 12),
        minute: 14 * 60 + 30,
      );
      expect(seed.toQuery(), '2025-11-12T14:30');
      expect(BookingCreateSeed.fromQuery(seed.toQuery()), seed);
    });

    test('zero-pads month, day, hour and minute', () {
      final BookingCreateSeed seed = BookingCreateSeed(
        day: DateTime(2025, 1, 5),
        minute: 0,
      );
      expect(seed.toQuery(), '2025-01-05T00:00');
      expect(BookingCreateSeed.fromQuery('2025-01-05T00:00'), seed);
    });

    test('last minute of the day round-trips', () {
      expect(
        BookingCreateSeed.fromQuery('2025-12-31T23:59'),
        BookingCreateSeed(day: DateTime(2025, 12, 31), minute: 1439),
      );
    });

    test('appendTo adds ?at= or &at=', () {
      final BookingCreateSeed seed = BookingCreateSeed(
        day: DateTime(2025, 11, 12),
        minute: 870,
      );
      expect(
        seed.appendTo('/master/bookings/new'),
        '/master/bookings/new?at=2025-11-12T14:30',
      );
      expect(seed.appendTo('/x?y=1'), '/x?y=1&at=2025-11-12T14:30');
      expect(
        withBookingCreateSeed('/master/bookings/new', seed),
        '/master/bookings/new?at=2025-11-12T14:30',
      );
    });

    test('withBookingCreateSeed(null) leaves the path untouched', () {
      expect(
        withBookingCreateSeed('/master/bookings/new', null),
        '/master/bookings/new',
      );
    });

    test('the query key is `at`', () {
      expect(bookingCreateSeedQueryKey, 'at');
    });
  });

  group('malformed / absent → null', () {
    for (final String? raw in <String?>[
      null,
      '',
      'abc',
      '2025-11-12',
      '2025-11-12T14',
      '2025-11-12 14:30',
      '2025-11-12T14:30Z',
      '2025-11-12T14:30:00',
      '25-11-12T14:30',
      '2025-13-01T10:00',
      '2025-00-10T10:00',
      '2025-02-30T10:00',
      '2025-11-00T10:00',
      '2025-11-12T24:00',
      '2025-11-12T10:60',
      ' 2025-11-12T14:30',
    ]) {
      test('fromQuery(${raw == null ? 'null' : "'$raw'"}) is null', () {
        expect(BookingCreateSeed.fromQuery(raw), isNull);
      });
    }
  });

  group('DST days keep wall-clock time', () {
    // Kyiv: spring forward 2025-03-30 03:00 → 04:00 (UTC+2 → UTC+3);
    // fall back 2025-10-26 04:00 → 03:00 (UTC+3 → UTC+2).
    test(
      'spring-forward day: query keeps 14:30 and matches the 14:30 slot',
      () {
        final BookingCreateSeed? seed = BookingCreateSeed.fromQuery(
          '2025-03-30T14:30',
        );
        expect(seed, isNotNull);
        expect(seed?.minute, 870);
        expect(seed?.toQuery(), '2025-03-30T14:30');
        // 14:30 Kyiv (EEST, +3) = 11:30 UTC; 13:30 Kyiv = 10:30 UTC.
        final BookingSlot exact = _slot(DateTime.utc(2025, 3, 30, 11, 30));
        final List<BookingSlot> slots = <BookingSlot>[
          _slot(DateTime.utc(2025, 3, 30, 10, 30)),
          exact,
        ];
        expect(seed == null ? null : pickSeededSlot(slots, seed), exact);
      },
    );

    test('fall-back day: query keeps 14:30 and matches the 14:30 slot', () {
      final BookingCreateSeed? seed = BookingCreateSeed.fromQuery(
        '2025-10-26T14:30',
      );
      expect(seed?.toQuery(), '2025-10-26T14:30');
      // 14:30 Kyiv (EET, +2) = 12:30 UTC; 11:30 UTC is 13:30 Kyiv that day.
      final BookingSlot exact = _slot(DateTime.utc(2025, 10, 26, 12, 30));
      final List<BookingSlot> slots = <BookingSlot>[
        _slot(DateTime.utc(2025, 10, 26, 11, 30)),
        exact,
      ];
      expect(seed == null ? null : pickSeededSlot(slots, seed), exact);
    });
  });

  group('pickSeededSlot (D3)', () {
    // 2025-11-12 is EET (+2): Kyiv HH:mm = UTC (HH-2):mm.
    final BookingCreateSeed seed = BookingCreateSeed(
      day: DateTime(2025, 11, 12),
      minute: 13 * 60, // 13:00 Kyiv
    );
    BookingSlot kyiv(int h, int m, {bool available = true}) =>
        _slot(DateTime.utc(2025, 11, 12, h - 2, m), available: available);

    test('exact match wins', () {
      final BookingSlot exact = kyiv(13, 0);
      expect(
        pickSeededSlot(<BookingSlot>[kyiv(10, 0), exact, kyiv(13, 30)], seed),
        exact,
      );
    });

    test('EXPLICIT_TIMES (10:00, 13:15) + seed 13:00 → 13:15', () {
      final BookingSlot later = kyiv(13, 15);
      expect(pickSeededSlot(<BookingSlot>[kyiv(10, 0), later], seed), later);
    });

    test('nearest LATER slot, not the first in the list', () {
      final BookingSlot nearest = kyiv(14, 0);
      expect(
        pickSeededSlot(<BookingSlot>[kyiv(16, 0), nearest, kyiv(15, 0)], seed),
        nearest,
      );
    });

    test('nothing later → the last earlier slot', () {
      final BookingSlot lastEarlier = kyiv(12, 30);
      expect(
        pickSeededSlot(<BookingSlot>[
          kyiv(9, 0),
          lastEarlier,
          kyiv(11, 0),
        ], seed),
        lastEarlier,
      );
    });

    test('an unavailable exact slot is skipped', () {
      final BookingSlot later = kyiv(13, 30);
      expect(
        pickSeededSlot(<BookingSlot>[
          kyiv(13, 0, available: false),
          later,
        ], seed),
        later,
      );
    });

    test('no available slot → null (never invents one)', () {
      expect(pickSeededSlot(const <BookingSlot>[], seed), isNull);
      expect(
        pickSeededSlot(<BookingSlot>[kyiv(13, 0, available: false)], seed),
        isNull,
      );
    });

    test('slots on another Kyiv day are ignored', () {
      // 23:30 UTC on 12 Nov = 01:30 Kyiv on 13 Nov.
      expect(
        pickSeededSlot(<BookingSlot>[
          _slot(DateTime.utc(2025, 11, 12, 23, 30)),
        ], seed),
        isNull,
      );
    });
  });
}
