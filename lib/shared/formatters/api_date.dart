// Phase 7.1 — `yyyy-MM-dd` wire-date helpers for the backend's `LocalDate`
// query params (`@DateTimeFormat(iso = DateTimeFormat.ISO.DATE)`).
//
// ## Why this exists rather than `toIso8601String()`
//
// The backend's `from`/`to` on `GET /bookings/me` and `GET /bookings/me/
// booked-days` are `LocalDate`s interpreted in **Europe/Kyiv**. A `DateTime`
// carries an instant, not a calendar day — and the two disagree near
// midnight. `DateTime(2026, 7, 18).toIso8601String()` emits a full timestamp
// the backend's ISO.DATE binder rejects outright; worse,
// `.toUtc().toIso8601String()` silently yields `2026-07-17T21:00:00Z` for a
// UTC+3 device, i.e. the WRONG DAY, and the user's filter quietly slides by
// one.
//
// [toApiDate] therefore reads `.year`/`.month`/`.day` off the LOCAL
// `DateTime` directly and formats them by hand. There is no zone conversion
// anywhere on this path, which makes the day-shift bug structurally
// impossible rather than merely absent: the day the user sees on the picker
// IS the day that reaches the wire, whatever the device offset.
//
// Corollary rule for callers: never `.toUtc()` a value before handing it to
// [toApiDate], and never hand it a value that was already UTC-normalised
// upstream (e.g. `Booking.startAt`, which is canonical UTC — convert it to
// local FIRST if you need its calendar day).
//
// Pure Dart: no Flutter imports.

/// Formats [d]'s **local** calendar day as the backend's `yyyy-MM-dd`.
///
/// Reads `.year`/`.month`/`.day` as-is — no zone conversion, so the emitted
/// day always matches the day [d] represents in the device's own zone. See
/// the file header for why this is not `toIso8601String()`.
String toApiDate(DateTime d) {
  final String m = d.month.toString().padLeft(2, '0');
  final String day = d.day.toString().padLeft(2, '0');
  return '${d.year.toString().padLeft(4, '0')}-$m-$day';
}

/// Truncates [d] to local midnight — the canonical form for any value used as
/// a Riverpod family key.
///
/// Two `DateTime`s on the same calendar day but at different clock times are
/// NOT `==`, so keying a family on an un-normalised `DateTime` mints a fresh
/// provider (and a fresh network fetch) per tap. Normalising at construction
/// collapses them to one member.
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Parses a bare backend `yyyy-MM-dd` string into a **local** date-only
/// [DateTime].
///
/// Deliberately NOT `DateTime.parse`: that reads a bare date as local midnight
/// today, but would also silently accept a full timestamp (and any `Z` suffix
/// in it), reintroducing the zone-shift this file exists to prevent. Building
/// the value from the three parsed components keeps the result date-only by
/// construction and directly comparable to [dateOnly] output.
///
/// Throws [FormatException] on any input that is not exactly three
/// `-`-separated integers, OR whose year/month/day fall outside a sane
/// calendar range (see the bound check below) — every caller in this repo
/// (`app_router.dart`'s `?date=` route, `booking_repository.dart`'s
/// `getMyBookedDays`) catches only [FormatException] and expects a malformed
/// value to land there, never propagate as something else.
///
/// NEVER lets `DateTime(y, m, d)` see an out-of-range component. The
/// `DateTime` constructor is not a safe fallback for validation: a year
/// outside its internal representable range throws `ArgumentError` (NOT
/// `FormatException`) and reaches an `on FormatException` catch uncaught;
/// worse, a year so large `int.tryParse` still accepts it but `DateTime`
/// does not reject it either — `DateTime(9999999999999, 1, 1)` returns a
/// real, silently-absurd `DateTime` with no exception at all. Both failure
/// modes are closed by bound-checking the parsed components BEFORE
/// construction, here, once — every caller benefits without adding its own
/// defensive catch.
DateTime parseApiDate(String s) {
  final List<String> parts = s.split('-');
  if (parts.length != 3) {
    throw FormatException('Expected yyyy-MM-dd', s);
  }
  final int? y = int.tryParse(parts[0]);
  final int? m = int.tryParse(parts[1]);
  final int? d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) {
    throw FormatException('Expected yyyy-MM-dd', s);
  }
  // `0001`-`9999` comfortably covers every real calendar year AND every
  // value `toApiDate`'s 4-digit zero-padded year can round-trip; the day
  // bound is deliberately generous (`1..31`, not per-month) because the
  // rollover check just below rejects an in-range-but-invalid day (e.g. `31`
  // in April) more precisely than a per-month table would need to.
  if (y < 1 || y > 9999 || m < 1 || m > 12 || d < 1 || d > 31) {
    throw FormatException('Expected yyyy-MM-dd', s);
  }
  final DateTime result = DateTime(y, m, d);
  // A day that does not exist in `m` does NOT throw — `DateTime` silently
  // NORMALISES it into the next month instead (April 31 becomes May 1).
  // Reject that rather than hand back the wrong date: a rollover always
  // moves `.month` away from the one that was asked for.
  if (result.month != m) {
    throw FormatException('Expected yyyy-MM-dd', s);
  }
  return result;
}
