// Beautica market timezone anchor.
//
// Booking / slot instants are canonical UTC everywhere they are stored or
// transmitted (the generated built_value client normalises every wire
// `DateTime` to UTC via `Iso8601DateTimeSerializer.deserialize`). The salon
// market, however, is Ukraine — every booking wall-clock a user sees must read
// at the Europe/Kyiv wall-clock regardless of the device's (or a CI runner's)
// own timezone.
//
// The device `.toLocal()` convention used earlier only rendered correctly when
// the device happened to sit in Kyiv time, and it made the slot-time regression
// test fail on CI's UTC runner (expected 09:00, got 06:00). Pinning the display
// zone to Europe/Kyiv via the IANA `timezone` package fixes both: it is
// DST-aware (UTC+2 winter / UTC+3 summer) and host-independent.
//
// This mirrors the backend's `TimeZones.KYIV` anchor (see
// `BookingService.atZoneSameInstant(TimeZones.KYIV)`); the naming is kept
// parallel (`beauticaZone`) so the two sides read as one convention.
//
// USAGE
// -----
//   • Call [initBeauticaTimeZones] exactly once during app startup (main.dart),
//     the process-global test harness (`test/flutter_test_config.dart`) and the
//     integration_test boot path — BEFORE any formatter reads [beauticaZone].
//     It is idempotent, so extra calls are cheap no-ops.
//   • Convert any instant for display with [toBeauticaTime]; never mutate the
//     stored/transmitted instant — conversion is display-only.
//
// Pure Dart — no widget-tree dependencies (the `timezone` package is pure Dart),
// so the pure-Dart formatters in `shared/formatters/booking_date_labels.dart`
// can call straight into it. The only Flutter dependency is a `foundation` import
// for the `@visibleForTesting` annotation + `kReleaseMode` release guard on the
// test-only reset backdoor (mirrors `core/app_start_time.dart`).

import 'package:flutter/foundation.dart' show kReleaseMode, visibleForTesting;
import 'package:timezone/data/latest_10y.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// The IANA name of the salon market zone. Mirrors the backend's
/// `TimeZones.KYIV`.
const String kBeauticaTimeZoneName = 'Europe/Kyiv';

bool _initialized = false;
tz.Location? _beauticaZone;

/// Loads the IANA timezone database and resolves the [beauticaZone] location.
///
/// Idempotent: the first call populates the tz database and caches the
/// Europe/Kyiv [tz.Location]; subsequent calls return immediately. Safe to call
/// from every startup path (app `main`, the process-global test config, each
/// integration flow's boot) without guarding at the call site.
void initBeauticaTimeZones() {
  if (_initialized) return;
  tz_data.initializeTimeZones();
  _beauticaZone = tz.getLocation(kBeauticaTimeZoneName);
  _initialized = true;
}

/// The salon market wall-clock zone (Europe/Kyiv, DST-aware UTC+2/+3).
///
/// Throws a [StateError] if read before [initBeauticaTimeZones] has run — a
/// loud failure is preferable to silently rendering the wrong zone.
tz.Location get beauticaZone {
  final tz.Location? zone = _beauticaZone;
  if (zone == null) {
    throw StateError(
      'initBeauticaTimeZones() must be called (app startup / test harness) '
      'before beauticaZone is read.',
    );
  }
  return zone;
}

/// Converts [instant] (canonical UTC, or any [DateTime]) to the Beautica market
/// wall-clock (Europe/Kyiv), DST-aware.
///
/// The returned [tz.TZDateTime] extends [DateTime], so callers read
/// `.hour` / `.minute` / `.day` / `.weekday` / `.month` off it directly and get
/// the Kyiv wall-clock values. Display-only — the source [instant] is never
/// mutated.
tz.TZDateTime toBeauticaTime(DateTime instant) =>
    tz.TZDateTime.from(instant, beauticaZone);

/// Clears the cached init state so [beauticaZone] throws its pre-init
/// [StateError] again — letting a test exercise that defensive branch, which is
/// otherwise unreachable because the process-global harness
/// (`test/flutter_test_config.dart`) initialises tz once for the whole run.
///
/// **Test-only** — asserts (and no-ops) in release so it can never wipe the
/// timezone database in a shipped build. Callers MUST re-run
/// [initBeauticaTimeZones] before the test ends so the rest of the process-wide
/// suite still sees an initialised database.
@visibleForTesting
void resetBeauticaTimeZonesForTest() {
  assert(!kReleaseMode, 'resetBeauticaTimeZonesForTest() is test-only.');
  if (kReleaseMode) return;
  _initialized = false;
  _beauticaZone = null;
}
