// MO-5 — unit tests for the «Мої записи» grouping + visit-summary derivations.
//
// Pure Dart: no widget tree. Proves [groupBookingsByAppointment] collapses a
// visit's per-service rows into ONE [VisitBookingEntry] (order-preserving),
// leaves legacy `appointmentId == null` rows as [SingleBookingEntry]s, and that
// [VisitBookingEntryX] derives the card summary (count, summed duration, ordered
// names, single-price / band label, earliest start, shared status) purely from
// the grouped rows — no network.
//
// WHY EVERY INSTANT HERE IS A FIXED PAST LITERAL
// ----------------------------------------------
// Every derivation under test is a pure function of the grouped rows:
// `startAt` is the MINIMUM of the rows' starts (asserted as an exact literal
// below), `serviceNames` is ordered by start instant, and `showsPrice` is a
// pure status predicate (`BookingDisplayX.showsPrice`) — none of them reads
// `DateTime.now()`, and nothing here touches `BookingDisplayX.isPast`. What
// matters is the ORDERING between the rows (10:00 before 11:00), not their
// distance from "now", so `futureBookingStart()` would only make the
// `expect(visit.startAt, …)` assertion non-deterministic. A literal in a past
// year can never become "upcoming" and is exempt from
// `scripts/forbid_stale_future_date_fixture.sh` automatically.

import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/my_bookings_entry.dart';
import 'package:flutter_test/flutter_test.dart';

Booking _b({
  required String id,
  String? appointmentId,
  BookingStatus status = BookingStatus.confirmed,
  String serviceName = 'Манікюр',
  int durationMinutes = 60,
  double price = 500,
  double? priceMax,
  DateTime? startAt,
}) {
  final DateTime start = startAt ?? DateTime.utc(2020, 7, 20, 10);
  return Booking(
    id: id,
    masterId: 'm1',
    masterFirstName: 'Марія',
    masterLastName: 'Іванюк',
    masterAvatarUrl: null,
    masterType: 'INDEPENDENT_MASTER',
    salonName: null,
    serviceId: 's-$id',
    serviceName: serviceName,
    categoryName: 'Манікюр',
    cityLabel: 'Львів',
    districtLabel: null,
    street: null,
    buildingNo: null,
    durationMinutes: durationMinutes,
    price: price,
    priceMax: priceMax,
    startAt: start,
    endAt: start.add(Duration(minutes: durationMinutes)),
    status: status,
    canReview: false,
    clientComment: null,
    providerComment: null,
    clientCancellationNote: null,
    masterProfessionalTitle: null,
    locationNote: null,
    appointmentId: appointmentId,
  );
}

void main() {
  group('groupBookingsByAppointment', () {
    test('legacy null-appointmentId rows stay single, order preserved', () {
      final List<MyBookingsEntry> entries = groupBookingsByAppointment(
        <Booking>[_b(id: 'a'), _b(id: 'b')],
      );

      expect(entries, hasLength(2));
      expect(entries[0], isA<SingleBookingEntry>());
      expect(entries[1], isA<SingleBookingEntry>());
      expect((entries[0] as SingleBookingEntry).booking.id, 'a');
      expect((entries[1] as SingleBookingEntry).booking.id, 'b');
    });

    test('rows sharing an appointmentId collapse into one visit entry', () {
      final List<MyBookingsEntry> entries = groupBookingsByAppointment(
        <Booking>[
          _b(id: 'v1', appointmentId: 'appt-1'),
          _b(id: 'v2', appointmentId: 'appt-1'),
        ],
      );

      expect(entries, hasLength(1));
      final MyBookingsEntry entry = entries.single;
      expect(entry, isA<VisitBookingEntry>());
      final VisitBookingEntry visit = entry as VisitBookingEntry;
      expect(visit.appointmentId, 'appt-1');
      expect(visit.bookings.map((Booking b) => b.id), <String>['v1', 'v2']);
    });

    test('mixed legacy + visit preserves first-seen order', () {
      final List<MyBookingsEntry> entries =
          groupBookingsByAppointment(<Booking>[
            _b(id: 'legacy-1'),
            _b(id: 'v1', appointmentId: 'appt-1'),
            _b(id: 'legacy-2'),
            _b(id: 'v2', appointmentId: 'appt-1'),
          ]);

      expect(entries, hasLength(3));
      expect(entries[0], isA<SingleBookingEntry>());
      expect((entries[0] as SingleBookingEntry).booking.id, 'legacy-1');
      // The visit takes the position of its FIRST row (index 1), the later row
      // folds in rather than creating a new entry.
      expect(entries[1], isA<VisitBookingEntry>());
      expect((entries[1] as VisitBookingEntry).bookings, hasLength(2));
      expect(entries[2], isA<SingleBookingEntry>());
      expect((entries[2] as SingleBookingEntry).booking.id, 'legacy-2');
    });

    test('two distinct visits do not merge', () {
      final List<MyBookingsEntry> entries =
          groupBookingsByAppointment(<Booking>[
            _b(id: 'v1', appointmentId: 'appt-1'),
            _b(id: 'w1', appointmentId: 'appt-2'),
            _b(id: 'v2', appointmentId: 'appt-1'),
          ]);

      expect(entries, hasLength(2));
      expect((entries[0] as VisitBookingEntry).appointmentId, 'appt-1');
      expect((entries[0] as VisitBookingEntry).bookings, hasLength(2));
      expect((entries[1] as VisitBookingEntry).appointmentId, 'appt-2');
      expect((entries[1] as VisitBookingEntry).bookings, hasLength(1));
    });
  });

  group('VisitBookingEntryX', () {
    VisitBookingEntry visitOf(List<Booking> rows) =>
        groupBookingsByAppointment(rows).single as VisitBookingEntry;

    test('serviceCount / summedDuration / ordered names / lead / start', () {
      final VisitBookingEntry visit = visitOf(<Booking>[
        _b(
          id: 'v2',
          appointmentId: 'appt-1',
          serviceName: 'Педикюр',
          durationMinutes: 90,
          startAt: DateTime.utc(2020, 7, 20, 11),
        ),
        _b(
          id: 'v1',
          appointmentId: 'appt-1',
          serviceName: 'Манікюр',
          durationMinutes: 60,
          startAt: DateTime.utc(2020, 7, 20, 10),
        ),
      ]);

      expect(visit.serviceCount, 2);
      expect(visit.summedDurationMinutes, 150);
      // Ordered by start instant — Манікюр (10:00) before Педикюр (11:00),
      // regardless of the wire order.
      expect(visit.serviceNames, <String>['Манікюр', 'Педикюр']);
      expect(visit.lead.id, 'v1');
      expect(visit.startAt, DateTime.utc(2020, 7, 20, 10));
      expect(visit.status, BookingStatus.confirmed);
    });

    test('single-price total renders one figure', () {
      final VisitBookingEntry visit = visitOf(<Booking>[
        _b(id: 'v1', appointmentId: 'appt-1', price: 300),
        _b(id: 'v2', appointmentId: 'appt-1', price: 350),
      ]);
      expect(visit.priceLabel, '650 ₴');
    });

    test('a ranged item makes the total a band', () {
      final VisitBookingEntry visit = visitOf(<Booking>[
        _b(id: 'v1', appointmentId: 'appt-1', price: 300, priceMax: 500),
        _b(id: 'v2', appointmentId: 'appt-1', price: 200),
      ]);
      // floor 300+200 = 500, ceiling 500+200 = 700.
      expect(visit.priceLabel, '500–700 ₴');
    });

    test('showsPrice follows the shared status rule', () {
      expect(
        visitOf(<Booking>[
          _b(id: 'v1', appointmentId: 'a', status: BookingStatus.confirmed),
        ]).showsPrice,
        isTrue,
      );
      expect(
        visitOf(<Booking>[
          _b(id: 'v1', appointmentId: 'a', status: BookingStatus.cancelled),
        ]).showsPrice,
        isFalse,
      );
    });
  });
}
