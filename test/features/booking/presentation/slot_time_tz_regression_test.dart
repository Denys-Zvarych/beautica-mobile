// Regression (booking auto-confirm branch): the slot-time picker rendered
// instants at the WRONG wall-clock depending on the device/runner timezone.
//
// ROOT CAUSE
// ----------
// The backend emits each available slot's `startsAt` at the Kyiv wall-clock it
// represents (`BookingService` → `atZoneSameInstant(TimeZones.KYIV)`), so a
// 09:00 Kyiv slot arrives on the wire as `2026-07-17T09:00:00+03:00`. The
// generated built_value client normalises every `DateTime` to UTC
// (`Iso8601DateTimeSerializer.deserialize` ends in `.toUtc()`), so
// `AvailableSlotResponse.startsAt` — and therefore `BookingSlot.startAt` — is a
// UTC `DateTime` whose `.hour` is `6`, not `9`.
//
// The first fix converted with device `.toLocal()`, which only renders the Kyiv
// wall-clock when the DEVICE sits in Kyiv time — wrong for other-timezone
// devices AND failing on CI's UTC runner (expected '09:00', got '06:00').
//
// THE FIX UNDER TEST
// ------------------
// `formatSlotTime` (and the whole `booking_date_labels` family) now converts
// the canonical-UTC instant to the salon market zone Europe/Kyiv via
// `shared/time/time_zones.dart` (`toBeauticaTime` → `tz.TZDateTime.from`), which
// is DST-aware AND host-independent. A 06:00Z July instant is 09:00 Kyiv on ANY
// runner — including `TZ=UTC`.
//
// HOST-INDEPENDENCE
// -----------------
// Because the display zone is now PINNED to Europe/Kyiv (not the process `TZ`),
// this file must pass identically under `TZ=UTC` (the CI runner) and
// `TZ=Europe/Kyiv` (a dev box). Every expected value below is the KNOWN Kyiv
// wall-clock, derived either as a literal or from a bare calendar date
// (`DateTime(y, m, d)` — its `.weekday`/`.month` are timezone-independent
// calendar facts), NEVER from `.toLocal()`. There is no `TZ` guard: the zone is
// pinned in code, so the test can never pass vacuously on a UTC runner.
//
// The process-global test harness (`test/flutter_test_config.dart`) calls
// `initBeauticaTimeZones()` before any test main, so the tz database is loaded.
// `main` also calls it (idempotent) so this file is self-contained.
//
// Pure Dart + built_value DTO: no widget tree, no Dio, no network.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/features/booking/data/booking_mapper.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Idempotent — the global test config also does this; kept here so the file
  // is self-contained when run in isolation.
  initBeauticaTimeZones();

  // A 09:00 Europe/Kyiv slot as it actually arrives from the backend:
  // `2026-07-17T09:00:00+03:00`, normalised to UTC by the generated client.
  final AvailableSlotResponse slotDto =
      (AvailableSlotResponseBuilder()
            ..startsAt =
                DateTime.utc(2026, 7, 17, 6) // == 09:00 Kyiv (UTC+3)
            ..endsAt = DateTime.utc(2026, 7, 17, 7)) //  == 10:00 Kyiv
          .build();

  group('slot-time display is pinned to the Europe/Kyiv wall-clock', () {
    test('picker shows 09:00 on ANY runner (incl. TZ=UTC), not raw 06:00', () {
      final BookingSlot slot = BookingSlotMapper.fromDto(slotDto)!;

      // The exact production formatting path: slot_picker_screen.dart:691.
      final String shown = formatSlotTime(slot.startAt);

      expect(
        shown,
        '09:00',
        reason:
            'Backend sent 09:00 Kyiv (06:00Z); the picker must render the '
            'pinned Kyiv wall-clock on every runner, not the raw UTC hour and '
            'not the device-local hour.',
      );
      expect(shown, isNot('06:00'));
    });
  });

  // ===========================================================================
  // The SAME Kyiv-pinned conversion landed on the WHOLE booking_date_labels
  // family, not just `formatSlotTime` — `formatBookingDayHeader`,
  // `formatBookingWindow`, `formatTimeRange`, `formatFullDate` and
  // `formatStubDayLine` all read raw wire fields before the fix and now convert
  // first. These formatters feed the My Bookings card (time + date stub), the
  // booking detail / confirm / success summary cards, the chosen-window line and
  // the conflict-dialog copy — so the whole family must be guarded, or a future
  // edit could silently re-break one surface while the slot-chip test above
  // stays green.
  //
  // WITNESS INSTANT — a DATE-CROSSING one, strictly stronger than 06:00Z→09:00.
  // 2026-07-17T22:00Z is 2026-07-18T01:00 in Kyiv (UTC+3): the Kyiv wall-clock
  // is a DIFFERENT DAY *and* a different weekday than the raw UTC fields. A
  // formatter that forgot the conversion prints "the 17th at 22:00"; the fixed
  // one prints "the 18th at 01:00". Expected date components come from the bare
  // calendar date `DateTime(2026, 7, 18)` (whose weekday/month are
  // timezone-independent calendar facts) and are cross-checked against the raw
  // UTC-17th values they must NOT equal, so none of these assertions can pass
  // vacuously against the pre-fix code OR on a UTC runner.
  group(
    'the whole formatter family is pinned to Europe/Kyiv (date-crossing)',
    () {
      final DateTime crossing = DateTime.utc(
        2026,
        7,
        17,
        22,
      ); // 01:00 Kyiv, 18th
      // Bare calendar date for the Kyiv day — its .weekday/.month are pure
      // calendar facts, identical on every runner (no instant conversion).
      final DateTime kyivDate = DateTime(2026, 7, 18);

      test(
        'the crossing instant is next-day (18th), a different day than UTC',
        () {
          // Sanity anchor for the group: the Kyiv date is the 18th, the raw UTC
          // date is the 17th, and their weekdays differ.
          expect(kyivDate.day, 18);
          expect(crossing.day, 17); // raw UTC field
          expect(
            kyivDate.weekday,
            isNot(crossing.weekday),
            reason: 'the Kyiv wall-clock must land on a different weekday',
          );
        },
      );

      test('formatSlotTime → Kyiv 01:00, never the raw UTC 22:00', () {
        expect(formatSlotTime(crossing), '01:00');
        expect(formatSlotTime(crossing), isNot('22:00'));
      });

      test(
        'formatTimeRange → 01:00–02:00 (My Bookings / summary «Час» row)',
        () {
          // 60-minute service starting at the crossing instant.
          expect(formatTimeRange(crossing, 60), '01:00–02:00');
          expect(formatTimeRange(crossing, 60), isNot(contains('22:00')));
        },
      );

      test('formatBookingWindow → Kyiv date + Kyiv start/end times', () {
        final DateTime end = crossing.add(const Duration(hours: 1));
        final String out = formatBookingWindow(crossing, end);

        expect(out, contains('01:00–02:00'));
        expect(out, contains('18')); // Kyiv day, not the raw UTC "17"
        expect(out, contains(kWeekdaysUkShort[kyivDate.weekday - 1]));
        expect(out, contains(kMonthsUkShort[kyivDate.month - 1]));
        expect(
          out,
          isNot(contains('22:00')),
          reason: 'the raw UTC start hour must never leak into the window line',
        );
      });

      test('formatBookingDayHeader → Kyiv weekday/day/short-month', () {
        expect(
          formatBookingDayHeader(crossing),
          '${kWeekdaysUkShort[kyivDate.weekday - 1]}, '
          '${kyivDate.day} ${kMonthsUkShort[kyivDate.month - 1]}',
        );
        expect(formatBookingDayHeader(crossing), contains('18'));
      });

      test('formatFullDate → Kyiv weekday/day/genitive-month (confirm/success '
          '«Дата» row)', () {
        expect(
          formatFullDate(crossing),
          '${kWeekdaysUkFull[kyivDate.weekday - 1]}, '
          '${kyivDate.day} ${kMonthsUkGenitive[kyivDate.month - 1]}',
        );
        expect(formatFullDate(crossing), contains('18'));
      });

      test('formatStubDayLine → Kyiv genitive-month + short weekday (My '
          'Bookings card date stub)', () {
        expect(
          formatStubDayLine(crossing),
          '${kMonthsUkGenitive[kyivDate.month - 1]}, '
          '${kWeekdaysUkShort[kyivDate.weekday - 1]}',
        );
      });
    },
  );
}
