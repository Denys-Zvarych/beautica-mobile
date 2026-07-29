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
import 'package:beautica_mobile/shared/formatters/uk_calendar.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Idempotent — the global test config also does this; kept here so the file
  // is self-contained when run in isolation.
  initBeauticaTimeZones();

  // A 09:00 Europe/Kyiv slot as it actually arrives from the backend:
  // `2026-07-17T09:00:00+03:00`, normalised to UTC by the generated client.
  //
  // WHY THESE INSTANTS STAY PINNED (stale-future-date gate, 2026-07-21)
  // -------------------------------------------------------------------
  // This suite's assertions are wall-clock STRING equalities — '09:00',
  // '10:00', a Kyiv weekday, a Kyiv month — against a UTC instant whose Kyiv
  // rendering is known in advance. A `futureBookingStart()` anchor would
  // move the expected strings along with the input and assert nothing. The
  // instants are also inert with respect to expiry: nothing on this tier
  // reads `BookingDisplayX.isPast` (it is the only clock-relative predicate
  // in the booking domain, and these are pure formatter/mapper tests), so
  // the day these dates fall into the past not one assertion changes. That
  // is precisely the "deliberate fixed instant" case the gate's
  // `future-date-ok` escape exists for — see the DST cases further down,
  // annotated for the same reason.
  final AvailableSlotResponse slotDto =
      (AvailableSlotResponseBuilder()
            // 06:00Z == 09:00 Kyiv (UTC+3).
            // future-date-ok: pinned Kyiv wire instant — see the block above.
            ..startsAt = DateTime.utc(2026, 7, 17, 6)
            // future-date-ok: pinned Kyiv wire instant — see the block above.
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
  // `formatBookingWindow`, `formatTimeRange`, `formatSlotTimeRange`,
  // `formatFullDate` and
  // `formatStubDayLine` all read raw wire fields before the fix and now convert
  // first. These formatters feed the My Bookings card (time + date stub), the
  // master «Мої записи» timeline card (start–end range), the
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
      // future-date-ok: the WITNESS INSTANT documented directly above — a
      // date-CROSSING UTC instant chosen so the Kyiv wall-clock lands on a
      // different calendar day. Re-anchoring it to `DateTime.now()` would
      // move the expected day/weekday/month with it and make every assertion
      // below vacuous; nothing here reads `isPast`.
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

      // The master «Мої записи» timeline card's label (2026-07-21). Distinct
      // from `formatTimeRange` above in that BOTH ends are real instants, so
      // BOTH need converting — a version that converted only the start would
      // still pass every `formatTimeRange` case (whose end is derived from an
      // already-converted start) while printing "01:00–23:00" here. The
      // second expectation pins exactly that half-converted failure mode.
      test('formatSlotTimeRange → 01:00–02:00, converting BOTH instants', () {
        final DateTime end = crossing.add(const Duration(hours: 1));

        expect(formatSlotTimeRange(crossing, end), '01:00–02:00');
        expect(
          formatSlotTimeRange(crossing, end),
          isNot(contains('23:00')),
          reason:
              'the raw UTC END hour must not leak — a formatter that converts '
              'only the start prints the unconverted 23:00 here',
        );
        expect(formatSlotTimeRange(crossing, end), isNot(contains('22:00')));
      });

      test('formatBookingWindow → Kyiv date + Kyiv start/end times', () {
        final DateTime end = crossing.add(const Duration(hours: 1));
        final String out = formatBookingWindow(crossing, end);

        expect(out, contains('01:00–02:00'));
        expect(out, contains('18')); // Kyiv day, not the raw UTC "17"
        expect(out, contains(weekdayAbbrev(kyivDate.weekday)));
        expect(out, contains(monthAbbrev(kyivDate.month)));
        expect(
          out,
          isNot(contains('22:00')),
          reason: 'the raw UTC start hour must never leak into the window line',
        );
      });

      test('formatBookingDayHeader → Kyiv weekday/day/short-month', () {
        expect(
          formatBookingDayHeader(crossing),
          '${weekdayAbbrev(kyivDate.weekday)}, '
          '${kyivDate.day} ${monthAbbrev(kyivDate.month)}',
        );
        expect(formatBookingDayHeader(crossing), contains('18'));
      });

      test('formatFullDate → Kyiv weekday/day/genitive-month (confirm/success '
          '«Дата» row)', () {
        expect(
          formatFullDate(crossing),
          '${weekdayName(kyivDate.weekday)}, '
          '${kyivDate.day} ${monthGenitive(kyivDate.month)}',
        );
        expect(formatFullDate(crossing), contains('18'));
      });

      test('formatStubDayLine → Kyiv genitive-month + short weekday (My '
          'Bookings card date stub)', () {
        expect(
          formatStubDayLine(crossing),
          '${monthGenitive(kyivDate.month)}, '
          '${weekdayAbbrev(kyivDate.weekday)}',
        );
      });
    },
  );

  // ===========================================================================
  // DST TRANSITIONS — the one case where converting the two instants
  // INDEPENDENTLY is observably different from deriving the end from the start
  // ===========================================================================
  //
  // `formatSlotTimeRange` runs `toBeauticaTime` over `startAt` and `endAt`
  // separately. Every ordinary booking hides that: the two conversions share
  // one UTC offset, so the printed range is exactly `start + duration`. On the
  // two days a year Europe/Kyiv shifts its offset they diverge, and the
  // question this group answers is whether the divergence is CORRECT (the
  // master's own wall clock) or MISLEADING (a lost hour silently absorbed).
  //
  // Ukraine follows the EU rule: the transition happens at 01:00 UTC on the
  // last Sunday of March (EET 03:00 -> EEST 04:00) and the last Sunday of
  // October (EEST 04:00 -> EET 03:00). In 2026 those are 29 March and
  // 25 October. Each test below first asserts that the two instants really
  // resolved to DIFFERENT UTC offsets — without that precondition a tz
  // database that dropped Ukraine's DST (a live legislative possibility) would
  // let these pass vacuously, and the failure would read as "the formatter
  // broke" rather than "the zone rules changed".
  //
  // NOTE ON THE CROSS-MIDNIGHT CONTRACT: nothing here manufactures a
  // cross-midnight interval. The schedule model forbids those at four
  // enforcement layers (a night shift is stored as two ISO-weekday rows), so
  // both fixtures stay strictly inside one Kyiv calendar day — which is also
  // what makes them relevant to a DAY-SCOPED «Мої записи» timeline.
  group('DST transitions — both instants convert independently', () {
    /// The Europe/Kyiv UTC offset [instant] resolves to, in minutes.
    int kyivOffset(DateTime instant) =>
        toBeauticaTime(instant).timeZoneOffset.inMinutes;

    test('SPRING FORWARD — a 60-minute booking across the skipped hour prints '
        'the real wall clock it spans (02:30–04:30), not a hidden 03:30', () {
      // A DST boundary is a fixed calendar instant; the whole assertion is the
      // zone offset at that instant, and nothing here reads the wall clock.
      // (Marker LAST, per the gate's own gotcha — it only unblocks the line
      // it sits on or the line directly above the code.)
      // future-date-ok: pinned spring-forward instant.
      final DateTime start = DateTime.utc(2026, 3, 29, 0, 30); // 02:30 EET
      final DateTime end = start.add(const Duration(minutes: 60)); // 04:30 EEST

      expect(
        kyivOffset(start),
        isNot(kyivOffset(end)),
        reason:
            'precondition: 2026-03-29T01:00Z is Europe/Kyiv\'s spring-forward '
            'transition (EET+120 -> EEST+180). If this fails the tz database '
            'no longer models Ukrainian DST and the rest of this group is '
            'meaningless, not wrong.',
      );

      // The master\'s clock genuinely reads 04:30 when this 60-minute
      // appointment ends — 03:00–04:00 never happened that night. Printing
      // "02:30–03:30" would be the WRONG answer: it names a wall-clock time
      // that did not exist.
      expect(formatSlotTimeRange(start, end), '02:30–04:30');
      expect(formatSlotTimeRange(start, end), isNot('02:30–03:30'));

      // The sibling derived-end formatter agrees, because `.add` on a
      // TZDateTime re-resolves the zone rather than adding to a wall-clock
      // field. That agreement is the point: the two formatters are a
      // deliberate semantic fork (persisted end vs derived end), NOT two
      // different answers to what a clock reads.
      expect(formatTimeRange(start, 60), formatSlotTimeRange(start, end));
    });

    test('FALL BACK — a 60-minute booking across the repeated hour prints '
        '03:30–03:30, and that degenerate-looking range is the honest wall '
        'clock', () {
      // See the spring-forward case above — a pinned DST boundary, no
      // wall-clock read.
      // future-date-ok: pinned fall-back instant.
      final DateTime start = DateTime.utc(2026, 10, 25, 0, 30); // 03:30 EEST
      final DateTime end = start.add(const Duration(minutes: 60)); // 03:30 EET

      expect(
        kyivOffset(start),
        isNot(kyivOffset(end)),
        reason:
            'precondition: 2026-10-25T01:00Z is Europe/Kyiv\'s fall-back '
            'transition (EEST+180 -> EET+120).',
      );

      // CHARACTERIZATION, not an endorsement. A range whose two ends print
      // identically reads as a zero-length appointment, and on the one hour a
      // year Kyiv repeats, that is what the master\'s clock literally shows.
      // Pinned deliberately so the behaviour is a KNOWN, reviewed property
      // rather than a surprise the next time someone reads a bug report about
      // it — and so a future "fix" that starts printing a fabricated 04:30
      // (a wall-clock time that occurs twice, on the wrong side of the
      // transition) has to argue with this test first.
      //
      // Practically unreachable: it needs an appointment running through
      // 03:00–04:00 on the last Sunday of October, and the timeline is
      // day-scoped so both ends land on the same rail day either way.
      expect(formatSlotTimeRange(start, end), '03:30–03:30');
      expect(
        formatTimeRange(start, 60),
        formatSlotTimeRange(start, end),
        reason:
            'this is a property of Kyiv wall-clock DISPLAY shared by the whole '
            'formatter family, not something formatSlotTimeRange introduced',
      );
    });

    test('a DST-day booking OUTSIDE the transition window is ordinary — the '
        'day itself is not special', () {
      // 07:00Z on the spring-forward day is 10:00 EEST; the transition is
      // seven hours behind it, so both ends share one offset.
      // future-date-ok: pinned DST-day instant, no wall-clock read.
      final DateTime start = DateTime.utc(2026, 3, 29, 7);
      final DateTime end = start.add(const Duration(minutes: 90));

      expect(kyivOffset(start), kyivOffset(end));
      expect(formatSlotTimeRange(start, end), '10:00–11:30');
    });
  });
}
