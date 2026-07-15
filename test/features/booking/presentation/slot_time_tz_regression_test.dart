// Regression (booking auto-confirm branch): the slot-time picker rendered
// instants ~3h EARLIER than the master's real Kyiv working hours.
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
// `formatSlotTime` (shared/formatters/booking_date_labels.dart) reads
// `time.hour`/`time.minute` DIRECTLY, with no `.toLocal()` / Kyiv conversion,
// so the picker prints the UTC wall-clock `06:00` instead of `09:00`.
//
// WHY THIS TEST EXERCISES THE MAPPER + FORMATTER TOGETHER
// -------------------------------------------------------
// The missing conversion could legitimately be added either at the mapper/parse
// boundary (`BookingSlotMapper.fromDto`) OR inside `formatSlotTime`. Driving the
// real `AvailableSlotResponse` DTO through `BookingSlotMapper.fromDto` and then
// through `formatSlotTime` (the exact production path in
// `slot_picker_screen.dart:691`) means EITHER fix turns this green, and only the
// unconverted current code is red.
//
// DETERMINISM
// -----------
// The app carries no `timezone`/`tz` package; its existing conversion
// convention is device `.toLocal()` (see `shared/formatters/relative_date.dart`).
// `.toLocal()` honours the process `TZ`, so this file MUST be run with the zone
// pinned to Europe/Kyiv for the post-fix assertion to be host-independent:
//
//     TZ=Europe/Kyiv flutter test \
//       test/features/booking/presentation/slot_time_tz_regression_test.dart
//
// In July, Europe/Kyiv is UTC+3, so a slot at `06:00Z` is `09:00` local. The
// group below guards that the zone is actually pinned so the test can never
// pass vacuously on a UTC CI runner.
//
// Pure Dart + built_value DTO: no widget tree, no Dio, no network.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/features/booking/data/booking_mapper.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A 09:00 Europe/Kyiv slot as it actually arrives from the backend:
  // `2026-07-17T09:00:00+03:00`, normalised to UTC by the generated client.
  final AvailableSlotResponse slotDto =
      (AvailableSlotResponseBuilder()
            ..startsAt =
                DateTime.utc(2026, 7, 17, 6) // == 09:00 Kyiv (UTC+3)
            ..endsAt = DateTime.utc(2026, 7, 17, 7)) //  == 10:00 Kyiv
          .build();

  group('slot-time display honours Europe/Kyiv wall-clock', () {
    test('run with TZ=Europe/Kyiv (guard against a UTC/other runner)', () {
      // `DateTime.utc(...).toLocal().hour` is 9 only when the process TZ is a
      // UTC+3 zone (Europe/Kyiv in summer). If this fails, re-run with
      // `TZ=Europe/Kyiv` — the assertions below are meaningless otherwise.
      expect(
        DateTime.utc(2026, 7, 17, 6).toLocal().hour,
        9,
        reason: 'Pin the zone: TZ=Europe/Kyiv flutter test <this file>',
      );
    });

    test('picker shows 09:00, not the raw UTC 06:00', () {
      final BookingSlot slot = BookingSlotMapper.fromDto(slotDto)!;

      // The exact production formatting path: slot_picker_screen.dart:691.
      final String shown = formatSlotTime(slot.startAt);

      expect(
        shown,
        '09:00',
        reason:
            'Backend sent 09:00 Kyiv (06:00Z); the picker must render the '
            'Kyiv wall-clock, not the raw UTC hour.',
      );
    });
  });

  // ===========================================================================
  // The SAME `.toLocal()` fix landed on the WHOLE booking_date_labels family,
  // not just `formatSlotTime` — `formatBookingDayHeader`, `formatBookingWindow`,
  // `formatTimeRange`, `formatFullDate` and `formatStubDayLine` all read raw
  // wire fields before the fix and now convert first. These formatters feed the
  // My Bookings card (time + date stub), the booking detail / confirm / success
  // summary cards, the chosen-window line and the conflict-dialog copy — so the
  // whole family must be guarded, or a future edit could silently re-break one
  // surface while the slot-chip test above stays green.
  //
  // WITNESS INSTANT — a DATE-CROSSING one, strictly stronger than 06:00Z→09:00.
  // 2026-07-17T22:00Z is 2026-07-18T01:00 in Kyiv (UTC+3): the LOCAL value is a
  // DIFFERENT DAY *and* a different weekday than the raw UTC fields. A formatter
  // that forgot `.toLocal()` prints "the 17th at 22:00"; the fixed one prints
  // "the 18th at 01:00". Every expected value below is derived from `.toLocal()`
  // and cross-checked against the raw-UTC value it must NOT equal, so none of
  // these assertions can pass vacuously against the pre-fix code.
  group('the whole formatter family honours Europe/Kyiv (date-crossing)', () {
    final DateTime crossing = DateTime.utc(2026, 7, 17, 22); // 01:00 Kyiv, 18th
    final DateTime local = crossing.toLocal();

    test('TZ guard: the crossing instant is next-day 01:00 in Kyiv', () {
      // Doubles as the zone guard for this group: on a UTC runner `local` would
      // still be the 17th at 22:00 and every assertion below would be moot.
      expect(
        local.day,
        18,
        reason: 'Pin the zone: TZ=Europe/Kyiv flutter test <this file>',
      );
      expect(local.hour, 1);
      expect(
        local.weekday,
        isNot(crossing.weekday),
        reason: 'the local wall-clock must land on a different weekday',
      );
    });

    test('formatSlotTime → local 01:00, never the raw UTC 22:00', () {
      expect(formatSlotTime(crossing), '01:00');
      expect(formatSlotTime(crossing), isNot('22:00'));
    });

    test('formatTimeRange → 01:00–02:00 (My Bookings / summary «Час» row)', () {
      // 60-minute service starting at the crossing instant.
      expect(formatTimeRange(crossing, 60), '01:00–02:00');
      expect(formatTimeRange(crossing, 60), isNot(contains('22:00')));
    });

    test('formatBookingWindow → local date + local start/end times', () {
      final DateTime end = crossing.add(const Duration(hours: 1));
      final String out = formatBookingWindow(crossing, end);

      expect(out, contains('01:00–02:00'));
      expect(out, contains(local.day.toString())); // "18", not "17"
      expect(out, contains(kWeekdaysUkShort[local.weekday - 1]));
      expect(out, contains(kMonthsUkShort[local.month - 1]));
      expect(
        out,
        isNot(contains('22:00')),
        reason: 'the raw UTC start hour must never leak into the window line',
      );
    });

    test('formatBookingDayHeader → local weekday/day/short-month', () {
      expect(
        formatBookingDayHeader(crossing),
        '${kWeekdaysUkShort[local.weekday - 1]}, '
        '${local.day} ${kMonthsUkShort[local.month - 1]}',
      );
      expect(formatBookingDayHeader(crossing), contains('18'));
    });

    test('formatFullDate → local weekday/day/genitive-month (confirm/success '
        '«Дата» row)', () {
      expect(
        formatFullDate(crossing),
        '${kWeekdaysUkFull[local.weekday - 1]}, '
        '${local.day} ${kMonthsUkGenitive[local.month - 1]}',
      );
      expect(formatFullDate(crossing), contains('18'));
    });

    test('formatStubDayLine → local genitive-month + short weekday (My '
        'Bookings card date stub)', () {
      expect(
        formatStubDayLine(crossing),
        '${kMonthsUkGenitive[local.month - 1]}, '
        '${kWeekdaysUkShort[local.weekday - 1]}',
      );
    });
  });
}
