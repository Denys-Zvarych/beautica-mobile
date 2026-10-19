// Kyiv wall-clock -> canonical UTC instant, for booking fixtures.
//
// Fixture days roll with the real clock (`fake_backend.dart`'s `_kFixtureDay`),
// so a fixture can land on either side of a Europe/Kyiv DST switch. Writing a
// booking start as `DateTime.utc(day..., 6)` "because 06:00Z == 09:00 Kyiv"
// only holds in summer (UTC+3); from the last Sunday of October Kyiv is UTC+2
// and the same literal reads as 08:00 Kyiv — outside a 09:00-opening seeded
// window. Build fixture instants from the Kyiv WALL CLOCK through this helper
// instead, and the UTC offset is resolved by the tz database for that day.

import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:timezone/timezone.dart' as tz;

/// The canonical UTC instant at which the Europe/Kyiv wall clock reads
/// [hour]:[minute] on the calendar date of [day] (only its year / month / day
/// are read — pass a date token from `kyivDayOf` / `kyivToday`, never an
/// instant whose UTC date differs from the intended Kyiv date).
///
/// DST-aware: 09:00 Kyiv on 2026-10-24 (UTC+3) is 06:00Z, on 2026-10-26
/// (UTC+2) it is 07:00Z.
///
/// Initialises the timezone database itself ([initBeauticaTimeZones] is
/// idempotent), so it is safe to call before the app under test has booted.
DateTime kyivWallClockUtc(DateTime day, int hour, [int minute = 0]) {
  assert(hour >= 0 && hour < 24, 'hour must be 0..23, got $hour');
  assert(minute >= 0 && minute < 60, 'minute must be 0..59, got $minute');
  initBeauticaTimeZones();
  final tz.TZDateTime kyiv = tz.TZDateTime(
    beauticaZone,
    day.year,
    day.month,
    day.day,
    hour,
    minute,
  );
  // A plain UTC `DateTime` (not a `TZDateTime`), so it compares, serialises
  // and `.add()`s exactly like the `DateTime.utc(...)` literals it replaces.
  return DateTime.fromMillisecondsSinceEpoch(
    kyiv.millisecondsSinceEpoch,
    isUtc: true,
  );
}

/// The Europe/Kyiv calendar day of [instant], as a date token — `kyivDayOf`,
/// made safe to call BEFORE the app under test has booted.
///
/// A fixture day must be the KYIV date of the seeded instant, not its UTC
/// date (they differ from 21:00Z in summer / 22:00Z in winter until UTC
/// midnight). Plain
/// `kyivDayOf` throws a `StateError` until the tz database is initialised,
/// which in an integration flow only happens at boot — and a test run in
/// isolation (`--name`) has no earlier flow to have booted for it.
DateTime kyivFixtureDayOf(DateTime instant) {
  initBeauticaTimeZones();
  return kyivDayOf(instant);
}
