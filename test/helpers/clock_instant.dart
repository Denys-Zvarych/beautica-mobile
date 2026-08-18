// Shared time-anchor helper for widgets that take a `clock:` seam.
//
// THE BUG THIS PREVENTS
// ----------------------
// `clock:` hands a widget an INSTANT, not a calendar day. Downstream code
// (e.g. `lib/shared/time/kyiv_day.dart`'s `kyivDayOf`) converts that instant
// through the Kyiv business zone to derive "today". A bare local
// `DateTime(y, m, d, ...)` resolves its underlying instant through the HOST
// PROCESS's own `TZ` — so what it actually pins differs per machine, and can
// land on the WRONG side of the Kyiv day boundary depending on the host's
// own zone (e.g. under `TZ=Asia/Tokyo`, host-local midnight is already
// 15:00Z the day before = 18:00 Kyiv the day before — a day early). This
// shipped for real on 2026-08-02: three schedule-widget test files fed a
// host-local instant through `clock:` via variable indirection
// (`clock: () => _today`, `clock: _testToday`), producing 28 deterministic
// failures under `TZ=Asia/Tokyo` while staying accidentally green on the dev
// VM (whose `TZ=Europe/Kyiv` happens to equal the business zone).
//
// THE FIX
// -------
// Anchor a `clock:`-fed instant with [asClockInstant] instead of passing a
// DATE TOKEN (e.g. `_today`, `_date`, `_clock` — a host-local midnight
// `DateTime` whose `.year`/`.month`/`.day` carry the intended calendar day,
// see `lib/shared/time/kyiv_day.dart`) straight through. Use this helper
// instead of hand-rolling `DateTime.utc(dayToken.year, ..., 12)` at each
// call site so the fix — and its rationale — lives in one place.
//
// WHY NOON, SPECIFICALLY
// ------------------------
// Noon UTC on [dayToken]'s calendar day is inside the Kyiv civil day for
// that SAME date from any realistic host offset: Kyiv is UTC+2 or UTC+3
// (DST), so noon UTC is 14:00-15:00 Kyiv — nowhere near either midnight
// boundary. Any other zone a real device might plausibly run under is
// closer to UTC than +/-12h, so noon UTC round-trips through `kyivDayOf` to
// exactly [dayToken] everywhere. (Midnight UTC would NOT be safe — that is
// only 02:00-03:00 Kyiv, uncomfortably close to the Kyiv boundary itself for
// a value meant to sit safely inside the day.)
//
// [dayToken] itself should stay a plain date token, used directly for
// `date:`/target-date fixtures and comparisons — only the value actually fed
// to a `clock:` parameter needs this conversion.
//
// CALL WITH AN IDENTIFIER, NOT AN INLINE LITERAL
// ------------------------------------------------
// Prefer `asClockInstant(_today)` over `asClockInstant(DateTime(2026, 6, 9))`.
// Both are equally safe at RUNTIME (only `.year`/`.month`/`.day` are ever
// read, which a local `DateTime(...)` constructor reports exactly as written
// regardless of host `TZ`), but the STATIC gate
// (`scripts/forbid_host_local_instant_anchor.sh`, RULE 2 IDENTIFIER
// RESOLUTION) cannot tell "a literal wrapped in this SAFE helper" apart from
// "a literal wrapped in an unsafe one" from text alone, and will flag the
// inline-literal form as a false positive. Passing an existing date-token
// identifier avoids that and is better style besides (reuses the named
// token instead of repeating the date). See the gate's own header for the
// full "HONEST LIMITS" note this call-style rule is documenting the other
// half of.
//
// Guarded by `scripts/forbid_host_local_instant_anchor.sh` (RULE 2 /
// RULE 2 IDENTIFIER RESOLUTION).

/// Converts a date token (a host-local midnight `DateTime` whose
/// `.year`/`.month`/`.day` carry the intended calendar day) into a genuine
/// INSTANT — noon UTC on that same day — safe to feed a widget's `clock:`
/// seam. See the file-level doc comment above for why noon specifically, and
/// for why [dayToken] should be an existing identifier, not an inline
/// `DateTime(...)` literal.
DateTime asClockInstant(DateTime dayToken) =>
    DateTime.utc(dayToken.year, dayToken.month, dayToken.day, 12);
