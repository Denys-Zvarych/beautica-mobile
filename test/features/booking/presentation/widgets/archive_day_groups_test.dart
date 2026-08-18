// Pinning tests for `archive_day_groups.dart` — the master «Архів» page's
// date-group-header flattening logic (see that file's own header for the
// full grouping/page-boundary-merge contract).
//
// Pure Dart, no widget tree — [groupArchiveByKyivDay] takes a plain
// `List<Booking>` and returns a plain `List<ArchiveListEntry>`.
//
// TIMEZONE: every fixture instant is anchored with `DateTime.utc(...)`, never
// a bare `DateTime(...)` — the same discipline `kyiv_day_test.dart` and
// `booking_date_labels_test.dart` follow. The cross-midnight case is run
// again under `TZ=UTC` (see the run instructions in this suite's PR) so the
// dev VM's `TZ=Europe/Kyiv` default cannot mask a device-local grouping bug.

import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/archive_day_groups.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:flutter_test/flutter_test.dart';

Booking _booking({required String id, required DateTime startAt}) => Booking(
  id: id,
  masterId: 'm-$id',
  masterFirstName: 'Марія',
  masterLastName: 'Іванюк',
  masterType: 'INDEPENDENT_MASTER',
  clientFirstName: 'Олена',
  clientLastName: 'Ковальчук',
  serviceId: 's-$id',
  serviceName: 'Манікюр',
  durationMinutes: 60,
  price: 500,
  startAt: startAt,
  endAt: startAt.add(const Duration(hours: 1)),
  status: BookingStatus.completed,
  canReview: false,
  awaitingClosure: false,
);

List<String> _headerDayLabels(List<ArchiveListEntry> entries) => entries
    .whereType<ArchiveDayHeaderEntry>()
    .map((ArchiveDayHeaderEntry e) => e.kyivDay.toIso8601String())
    .toList();

void main() {
  // Idempotent — kept here so the file is self-contained when run in
  // isolation, mirroring `kyiv_day_test.dart`/`booking_date_labels_test.dart`.
  initBeauticaTimeZones();

  group('groupArchiveByKyivDay — same-day merge, different-day split', () {
    test('two bookings on the SAME Kyiv day render under ONE header; a third '
        'on a different day gets its own, newest-first order preserved', () {
      // Server order is newest-first — the notifier never re-sorts.
      final List<Booking> items = <Booking>[
        _booking(id: 'a', startAt: DateTime.utc(2024, 8, 12, 11)), // 14:00 Kyiv
        _booking(
          id: 'b',
          startAt: DateTime.utc(2024, 8, 12, 6),
        ), // 09:00 Kyiv, same day
        _booking(
          id: 'c',
          startAt: DateTime.utc(2024, 8, 10, 8),
        ), // different day
      ];

      final List<ArchiveListEntry> entries = groupArchiveByKyivDay(items);

      expect(entries, <Object>[
        isA<ArchiveDayHeaderEntry>(),
        isA<ArchiveBookingEntry>().having(
          (ArchiveBookingEntry e) => e.booking.id,
          'booking.id',
          'a',
        ),
        isA<ArchiveBookingEntry>().having(
          (ArchiveBookingEntry e) => e.booking.id,
          'booking.id',
          'b',
        ),
        isA<ArchiveDayHeaderEntry>(),
        isA<ArchiveBookingEntry>().having(
          (ArchiveBookingEntry e) => e.booking.id,
          'booking.id',
          'c',
        ),
      ]);

      expect(
        _headerDayLabels(entries),
        <String>[
          DateTime(2024, 8, 12).toIso8601String(),
          DateTime(2024, 8, 10).toIso8601String(),
        ],
        reason:
            'exactly two distinct headers, in the same newest-first '
            'order as the input — the 12th before the 10th',
      );
    });

    test('an empty list produces an empty entry list', () {
      expect(groupArchiveByKyivDay(const <Booking>[]), isEmpty);
    });

    test('THREE bookings, all on the SAME Kyiv day, collapse under exactly '
        'ONE header — isolated from the 2-same-day+1-different fixture '
        'above, distinguishable by row count', () {
      final List<Booking> items = <Booking>[
        _booking(id: 'p', startAt: DateTime.utc(2024, 8, 15, 17)), // 20:00 Kyiv
        _booking(id: 'q', startAt: DateTime.utc(2024, 8, 15, 11)), // 14:00 Kyiv
        _booking(
          id: 'r',
          startAt: DateTime.utc(2024, 8, 15, 4, 30),
        ), // 07:30 Kyiv
      ];

      final List<ArchiveListEntry> entries = groupArchiveByKyivDay(items);

      // Exact entry sequence: ONE header followed by all THREE booking
      // rows, in that order — not merely "a header exists somewhere".
      expect(entries, <Object>[
        isA<ArchiveDayHeaderEntry>(),
        isA<ArchiveBookingEntry>().having(
          (ArchiveBookingEntry e) => e.booking.id,
          'booking.id',
          'p',
        ),
        isA<ArchiveBookingEntry>().having(
          (ArchiveBookingEntry e) => e.booking.id,
          'booking.id',
          'q',
        ),
        isA<ArchiveBookingEntry>().having(
          (ArchiveBookingEntry e) => e.booking.id,
          'booking.id',
          'r',
        ),
      ]);

      expect(
        entries.whereType<ArchiveDayHeaderEntry>().length,
        1,
        reason: 'exactly ONE header for N=3 same-day rows',
      );
      expect(
        entries.whereType<ArchiveBookingEntry>().length,
        3,
        reason: 'all three rows still present, none dropped by the merge',
      );
      expect(_headerDayLabels(entries), <String>[
        DateTime(2024, 8, 15).toIso8601String(),
      ]);
    });
  });

  group('groupArchiveByKyivDay — page-boundary merge (the core trap)', () {
    test('a Kyiv day whose bookings straddle two raw server pages collapses to '
        'exactly ONE header when the pages are concatenated into the '
        'notifier\'s accumulated `items`, not two', () {
      // Simulates `MasterArchiveState.items` AFTER `loadMore()` appended
      // raw page 1 onto raw page 0 — exactly what
      // `master_archive_screen.dart` feeds this function every build.
      // Page 0's LAST row and page 1's FIRST row share the same Kyiv day
      // (2024-08-12): 23:50 Kyiv (page 0 tail) and 00:10 Kyiv (page 1
      // head) are both August 12th in Kyiv, even though the second is a
      // later UTC instant on a "new" raw page.
      final List<Booking> page0 = <Booking>[
        _booking(id: 'p0-first', startAt: DateTime.utc(2024, 8, 12, 8)),
        _booking(
          id: 'p0-last',
          startAt: DateTime.utc(2024, 8, 12, 20, 50), // 23:50 Kyiv (EEST +3)
        ),
      ];
      final List<Booking> page1 = <Booking>[
        _booking(
          id: 'p1-first',
          // 20:00 Kyiv (EEST +3) — earlier than page 0's 23:50 tail, so
          // overall newest-first order is preserved, but still the SAME
          // Kyiv calendar day (Aug 12).
          startAt: DateTime.utc(2024, 8, 12, 17),
        ),
        _booking(id: 'p1-second', startAt: DateTime.utc(2024, 8, 11, 9)),
      ];
      final List<Booking> accumulated = <Booking>[...page0, ...page1];

      final List<ArchiveListEntry> entries = groupArchiveByKyivDay(accumulated);

      expect(
        _headerDayLabels(entries),
        <String>[
          DateTime(2024, 8, 12).toIso8601String(),
          DateTime(2024, 8, 11).toIso8601String(),
        ],
        reason:
            'exactly ONE header for Aug 12 covering all three rows that '
            'share that Kyiv day, even though the third sits on a '
            'DIFFERENT raw server page than the first two — a naive '
            'per-page grouping (header at the start of every fetched '
            'page) would wrongly emit a SECOND Aug 12 header here',
      );

      // Positional check: no header sits between p0-last and p1-first.
      final List<String> ids = entries
          .map(
            (ArchiveListEntry e) => switch (e) {
              ArchiveDayHeaderEntry() => '#header',
              ArchiveBookingEntry(:final Booking booking) => booking.id,
            },
          )
          .toList();
      expect(ids, <String>[
        '#header',
        'p0-first',
        'p0-last',
        'p1-first',
        '#header',
        'p1-second',
      ]);
    });
  });

  group('groupArchiveByKyivDay — Kyiv-day boundary correctness (device-TZ '
      'independent; run this file under TZ=UTC too — the dev VM\'s '
      'TZ=Europe/Kyiv masks a device-local grouping bug)', () {
    test('a booking at 00:30 Kyiv groups under the NEXT Kyiv day, not the '
        'previous UTC day its wire instant falls on', () {
      // 2024-08-12T21:30Z = 2024-08-13 00:30 Kyiv (EEST, +3h in August).
      final DateTime crossing = DateTime.utc(2024, 8, 12, 21, 30);
      final Booking sameEveningLatePrevDay = _booking(
        id: 'late-evening',
        startAt: DateTime.utc(2024, 8, 12, 19), // 22:00 Kyiv, Aug 12
      );
      final Booking justAfterMidnight = _booking(
        id: 'just-after-midnight',
        startAt: crossing,
      );

      final List<ArchiveListEntry> entries = groupArchiveByKyivDay(<Booking>[
        sameEveningLatePrevDay,
        justAfterMidnight,
      ]);

      // Two DIFFERENT Kyiv days → two headers, even though both wire
      // instants land on the SAME UTC calendar date (2024-08-12).
      expect(_headerDayLabels(entries), <String>[
        DateTime(2024, 8, 12).toIso8601String(),
        DateTime(2024, 8, 13).toIso8601String(),
      ]);
    });
  });
}
