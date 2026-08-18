// Phase 244 — bookingsInsideScheduleWindow: the ONE filtering computation
// behind the master's own «Мої записи» working-hours window (see
// `bookings_timeline_grid.dart`'s doc on the function — mobile-security HIGH
// fix, this feature). Pure-logic tests; no widget pumped.
//
// The perf contract pinned here (mobile-perf MEDIUM in the same doc) is
// load-bearing, not cosmetic: `BookingsDiscoveryView`'s `_visibleBookingsFor`
// memo and `BookingsTimelineGrid`'s `didUpdateWidget` both gate on
// `identical(oldList, newList)`. If this function ever starts returning a
// freshly-allocated (but equal) list when nothing was filtered, both memo
// gates silently stop short-circuiting and the O(N log N) layout recompute
// fires on every rebuild — this is documented as having regressed TWICE.

import 'package:flutter_test/flutter_test.dart';

import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_timeline_grid.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/schedule_timeline_window.dart';
import 'package:beautica_mobile/shared/formatters/api_date.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../../helpers/booking_fixture_dates.dart';

final DateTime _day = dateOnly(toBeauticaTime(futureBookingStart()));

DateTime _kyivAtUtc(int hour, [int minute = 0]) => tz.TZDateTime(
  beauticaZone,
  _day.year,
  _day.month,
  _day.day,
  hour,
  minute,
).toUtc();

Booking _booking({required String id, required DateTime startAtUtc}) => Booking(
  id: id,
  masterId: 'master-1',
  masterFirstName: 'Оля',
  masterLastName: 'Коваль',
  masterType: 'INDEPENDENT_MASTER',
  clientFirstName: 'Марія',
  clientLastName: 'Іванюк',
  serviceId: 'service-1',
  serviceName: 'Манікюр',
  durationMinutes: 30,
  price: 500,
  startAt: startAtUtc,
  endAt: startAtUtc.add(const Duration(minutes: 30)),
  status: BookingStatus.confirmed,
  canReview: false,
);

void main() {
  setUpAll(initBeauticaTimeZones);

  // 09:00-18:00 interval window => firstMinute 540, windowEndMinute 1080.
  const ScheduleTimelineWindow window = ScheduleTimelineWindow(
    firstMinute: 540,
    windowEndMinute: 1080,
    isExplicitTimes: false,
  );

  group('filtering', () {
    test('excludes a booking starting BEFORE the window', () {
      final List<Booking> bookings = <Booking>[
        _booking(id: 'early', startAtUtc: _kyivAtUtc(8)),
        _booking(id: 'inside', startAtUtc: _kyivAtUtc(9)),
      ];

      final List<Booking> result = bookingsInsideScheduleWindow(
        bookings,
        _day,
        window,
      );

      expect(result.map((Booking b) => b.id), <String>['inside']);
    });

    test('excludes a booking starting AFTER the window', () {
      final List<Booking> bookings = <Booking>[
        _booking(id: 'inside', startAtUtc: _kyivAtUtc(9)),
        _booking(id: 'late', startAtUtc: _kyivAtUtc(20)),
      ];

      final List<Booking> result = bookingsInsideScheduleWindow(
        bookings,
        _day,
        window,
      );

      expect(result.map((Booking b) => b.id), <String>['inside']);
    });

    test('keeps a booking that STARTS inside the window even though it ENDS '
        'past it — the filter is start-only, matching includesStart', () {
      // Starts 17:45 (inside), a 90-minute duration would end 19:15 — well
      // past the 18:00 window end. Still kept: the widening past the
      // window bottom is the GRID's job (scheduleFirstMinute/
      // scheduleWindowEndMinute widening), not this filter's.
      final Booking endsAfter = Booking(
        id: 'ends-after',
        masterId: 'master-1',
        masterFirstName: 'Оля',
        masterLastName: 'Коваль',
        masterType: 'INDEPENDENT_MASTER',
        clientFirstName: 'Марія',
        clientLastName: 'Іванюк',
        serviceId: 'service-1',
        serviceName: 'Манікюр',
        durationMinutes: 90,
        price: 500,
        startAt: _kyivAtUtc(17, 45),
        endAt: _kyivAtUtc(17, 45).add(const Duration(minutes: 90)),
        status: BookingStatus.confirmed,
        canReview: false,
      );

      final List<Booking> result = bookingsInsideScheduleWindow(
        <Booking>[endsAfter],
        _day,
        window,
      );

      expect(result, <Booking>[endsAfter]);
    });
  });

  group('boundary sweep', () {
    test('a start exactly at firstMinute (09:00) is kept', () {
      final List<Booking> bookings = <Booking>[
        _booking(id: 'at-first', startAtUtc: _kyivAtUtc(9)),
      ];
      expect(
        bookingsInsideScheduleWindow(
          bookings,
          _day,
          window,
        ).map((Booking b) => b.id),
        <String>['at-first'],
      );
    });

    test('a start exactly at windowEndMinute (18:00) is excluded', () {
      final List<Booking> bookings = <Booking>[
        _booking(id: 'at-end', startAtUtc: _kyivAtUtc(18)),
      ];
      expect(bookingsInsideScheduleWindow(bookings, _day, window), isEmpty);
    });

    test('every booking excluded returns an empty list', () {
      final List<Booking> bookings = <Booking>[
        _booking(id: 'a', startAtUtc: _kyivAtUtc(6)),
        _booking(id: 'b', startAtUtc: _kyivAtUtc(21)),
      ];
      expect(bookingsInsideScheduleWindow(bookings, _day, window), isEmpty);
    });

    test('the FIRST booking in the list excluded, the rest kept', () {
      final List<Booking> bookings = <Booking>[
        _booking(id: 'excluded-first', startAtUtc: _kyivAtUtc(6)),
        _booking(id: 'kept-1', startAtUtc: _kyivAtUtc(9)),
        _booking(id: 'kept-2', startAtUtc: _kyivAtUtc(10)),
      ];
      expect(
        bookingsInsideScheduleWindow(
          bookings,
          _day,
          window,
        ).map((Booking b) => b.id),
        <String>['kept-1', 'kept-2'],
      );
    });

    test('the LAST booking in the list excluded, the rest kept', () {
      final List<Booking> bookings = <Booking>[
        _booking(id: 'kept-1', startAtUtc: _kyivAtUtc(9)),
        _booking(id: 'kept-2', startAtUtc: _kyivAtUtc(10)),
        _booking(id: 'excluded-last', startAtUtc: _kyivAtUtc(21)),
      ];
      expect(
        bookingsInsideScheduleWindow(
          bookings,
          _day,
          window,
        ).map((Booking b) => b.id),
        <String>['kept-1', 'kept-2'],
      );
    });
  });

  group('cross-day exclusion (defensive invariant)', () {
    // Production never hands this function a booking dated on a different
    // calendar day than [day] it is called for — `BookingsDayNotifier`
    // forwards the SAME Kyiv day as both `from` and `to`
    // (`bookings_day_notifier.dart`'s file header, "The day token is a KYIV
    // calendar day"), and the real backend resolves that into a HALF-OPEN
    // `Europe/Kyiv` instant range, `[from.atStartOfDay(KYIV),
    // to.plusDays(1).atStartOfDay(KYIV))`
    // (`BookingService#getMyBookings`'s Phase 26.2 doc) — the same zone id
    // (`Europe/Kyiv`) and the same calendar-day boundary this function's own
    // `tz.TZDateTime(beauticaZone, day.year, day.month, day.day)` midnight
    // uses. So a same-day guarantee holds end-to-end and this function
    // should never actually need to reject an off-day booking outside a
    // test. Pinned anyway, defensively, exactly like the identity perf
    // contract below: if a future change ever weakens that guarantee (a
    // fake/mock fed straight to a provider, a manual `ref.read` bypassing
    // the notifier, a future caller that queries a RANGE instead of a single
    // day), this function must still refuse to render the wrong day's
    // booking rather than silently widen the window.
    test('excludes a booking dated a week AFTER [day], even though its '
        'time-of-day sits well inside the window', () {
      final DateTime otherDay = _day.add(const Duration(days: 7));
      final Booking farFuture = _booking(
        id: 'far-future',
        startAtUtc: tz.TZDateTime(
          beauticaZone,
          otherDay.year,
          otherDay.month,
          otherDay.day,
          10, // 10:00 Kyiv — well inside 09:00-18:00, on the WRONG day.
        ).toUtc(),
      );

      final List<Booking> result = bookingsInsideScheduleWindow(
        <Booking>[farFuture],
        _day,
        window,
      );

      expect(
        result,
        isEmpty,
        reason:
            'a booking on a different calendar day must never render as '
            "though it belonged to the VIEWED day, regardless of its own "
            'local hour',
      );
    });

    test('excludes a booking dated a day BEFORE [day], even though its '
        'time-of-day sits well inside the window', () {
      final DateTime otherDay = _day.subtract(const Duration(days: 1));
      final Booking yesterday = _booking(
        id: 'yesterday',
        startAtUtc: tz.TZDateTime(
          beauticaZone,
          otherDay.year,
          otherDay.month,
          otherDay.day,
          10,
        ).toUtc(),
      );

      final List<Booking> result = bookingsInsideScheduleWindow(
        <Booking>[yesterday],
        _day,
        window,
      );

      expect(result, isEmpty);
    });

    test('a control: the SAME hour, on [day] itself, IS kept — isolating the '
        'day mismatch above as what actually excludes it, not the 10:00 '
        'hour', () {
      final Booking sameDay = _booking(
        id: 'same-day',
        startAtUtc: _kyivAtUtc(10),
      );

      final List<Booking> result = bookingsInsideScheduleWindow(
        <Booking>[sameDay],
        _day,
        window,
      );

      expect(result.map((Booking b) => b.id), <String>['same-day']);
    });
  });

  group('the identity perf contract', () {
    test(
      'returns the EXACT SAME list instance (identical, not merely equal) '
      'when every booking passes the window — the memoization gates both '
      '_visibleBookingsFor and BookingsTimelineGrid.didUpdateWidget depend on',
      () {
        final List<Booking> bookings = <Booking>[
          _booking(id: 'a', startAtUtc: _kyivAtUtc(9)),
          _booking(id: 'b', startAtUtc: _kyivAtUtc(10)),
        ];

        final List<Booking> result = bookingsInsideScheduleWindow(
          bookings,
          _day,
          window,
        );

        expect(
          identical(result, bookings),
          isTrue,
          reason:
              'a fresh (even if element-equal) list here defeats '
              'identical(widget.bookings, oldWidget.bookings) downstream and '
              'reopens the O(N log N) layout recompute on every rebuild',
        );
      },
    );

    test('returns a genuinely NEW list (never identical to the input) when at '
        'least one booking is actually filtered out', () {
      final List<Booking> bookings = <Booking>[
        _booking(id: 'kept', startAtUtc: _kyivAtUtc(9)),
        _booking(id: 'dropped', startAtUtc: _kyivAtUtc(20)),
      ];

      final List<Booking> result = bookingsInsideScheduleWindow(
        bookings,
        _day,
        window,
      );

      expect(identical(result, bookings), isFalse);
      expect(result.length, 1);
    });

    test(
      'an empty input returns cleanly (identical to the empty input list)',
      () {
        final List<Booking> empty = <Booking>[];
        final List<Booking> result = bookingsInsideScheduleWindow(
          empty,
          _day,
          window,
        );
        expect(identical(result, empty), isTrue);
      },
    );
  });
}
