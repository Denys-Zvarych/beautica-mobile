// Phase 226 (ARCHITECTURE-mobile.md § 0.9) — the single canonical Kyiv
// calendar-day derivation for the whole client.
//
// THE LOCKED PRINCIPLE
// ---------------------
// The device clock supplies the current INSTANT; Europe/Kyiv decides which
// calendar DAY that instant falls in. The backend already enforces exactly
// this on every date param it accepts — `atStartOfDay(TimeZones.KYIV)` in
// `BookingService` (:481-482, :548-549), `SlotCalculationService` (:210,
// :214, :656-657), `MasterService` (:799-800),
// `ScheduleOverrideConflictService` (:439-440), `DashboardService` (:292-293)
// — with no bare `atStartOfDay()` anywhere on that side. So this file is not
// a new wire contract; it brings the mobile client into compliance with one
// that already exists.
//
// THE TYPE HAZARD THIS FILE EXISTS TO NAME
// -----------------------------------------
// [kyivDayOf] and [kyivToday] both return a **date token**: a host-local
// [DateTime] sitting at host-local midnight, whose `.year`/`.month`/`.day`
// carry the KYIV calendar day — not the device's, and not UTC's. It is NOT
// an instant, even though Dart gives it the exact same runtime type an
// instant would have. That type-level indistinguishability is the real root
// cause of this whole bug class: nothing in the type system stops a caller
// from treating a date token as though it still measured wall-clock time
// somewhere, and every place that happened, the value silently drifted a day
// near midnight in whatever direction the device's own zone disagreed with
// Kyiv's.
//
// LEGAL on a date token:
//   • `==` against another date token.
//   • Reading `.year` / `.month` / `.day`.
//   • Passing to `toApiDate` (which reads exactly those three fields).
//   • `.isBefore` / `.isAfter` against another date token.
//   • Subtracting another date token — but ONLY via [kyivDaysBetween], never
//     via a hand-written `.difference(...).inDays`. Both operands are
//     host-local midnights, so a HOST DST transition between them makes the
//     hand-written form 23 h or 25 h and `.inDays` truncates to N-1. See
//     [kyivDaysBetween]'s own doc; Phase 284.
//
// ILLEGAL on a date token:
//   • `.toUtc()` — there is no meaningful "UTC form" of a value that was
//     never really an instant; the call compiles, runs, and returns garbage.
//   • `.difference(...)` against an INSTANT (e.g. `Booking.startAt`, which is
//     canonical UTC) — mixes a calendar-day token with a wall-clock instant
//     and measures a bogus duration.
//   • `.isBefore(...)` / `.isAfter(...)` against a booking timestamp or any
//     other instant, for the same reason.
//
// Confusing these two — using a date token as if it were still an instant,
// or an instant as if it were already a date token — is what caused this
// whole class of bug (Phase 225 audit cycles 4 and 5, and again on
// 2026-08-02): a value that LOOKS like an ordinary `DateTime` computed from
// "now" quietly stopped being anchored to Kyiv's calendar (or started being
// treated as though it still measured wall-clock time) the moment it crossed
// that line, and nothing about its type flagged the mistake.
//
// USAGE
// -----
// Never call `DateTime.now()` and strip the time-of-day by hand — that reads
// the DEVICE's calendar day, not Kyiv's, which is exactly the bug this file
// exists to close. Call [kyivToday], passing the injected clock seam (see
// `core/time/clock_provider.dart`), instead. To derive a Kyiv day from an
// already-known instant (not "now"), call [kyivDayOf] directly.
//
// Enforced by `scripts/forbid_raw_clock_read.sh`: every live-code
// `DateTime.now` reference (call form or bare tear-off) outside
// `clock_provider.dart`'s own definition must either flow through the
// injected clock seam or carry a `// instant-ok: <reason>` annotation
// justifying a genuine absolute-instant read. That guard is a DECLARATION
// gate, not a dataflow one — it flags every raw clock read, not only the
// ones that end up mis-typed as a date token; see the script's own header
// for why a classifying gate is impossible here. Nothing statically catches
// misusing an already-derived date token (the ILLEGAL list above) — that
// stays a review responsibility.
//
// Pure Dart — no widget-tree dependencies.

import 'package:beautica_mobile/shared/formatters/api_date.dart' show dateOnly;
import 'package:beautica_mobile/shared/time/time_zones.dart'
    show toBeauticaTime;

/// Converts [instant] — any real instant, however it was obtained — to its
/// Kyiv calendar day, returned as a **date token** (see file header): a
/// host-local [DateTime] at host-local midnight whose `.year`/`.month`/`.day`
/// are the Kyiv day [instant] falls on.
///
/// Use this when a specific instant (not "now") needs to be classified into a
/// Kyiv day — e.g. a booking's `startAt`. For "now", use [kyivToday].
DateTime kyivDayOf(DateTime instant) => dateOnly(toBeauticaTime(instant));

/// "Today", Kyiv-anchored, read through the injected clock seam.
///
/// [clock] is a `DateTime Function()` — in production, `ref.read
/// (clockProvider)` / `ref.watch(clockProvider)` (see
/// `core/time/clock_provider.dart`); in tests, a fixed or mutable closure —
/// so a test can pin the device's current instant and observe the RETURNED
/// DAY follow Kyiv's calendar, not the device's. Returns a date token; see
/// the file header for what is (and is not) legal to do with the result.
DateTime kyivToday(DateTime Function() clock) => kyivDayOf(clock());

/// Whole Kyiv calendar days from [earlier] to [later], both **date tokens**
/// (see the file header) — positive when [later] is after [earlier], negative
/// when it is before, zero when they name the same day.
///
/// THE ONLY SANCTIONED WAY TO SUBTRACT TWO DATE TOKENS. Writing
/// `later.difference(earlier).inDays` by hand is the bug this function
/// exists to remove, and it is a bug that has now shipped twice.
///
/// A date token is a HOST-LOCAL [DateTime] at host-local midnight.
/// [DateTime.difference] measures elapsed ABSOLUTE time, so subtracting two
/// host-local midnights that straddle the HOST zone's DST transition yields
/// 23 h (spring forward) or 25 h (fall back) rather than 24 h, and
/// [Duration.inDays] truncates toward zero — silently returning ONE DAY FEWER
/// than the calendar actually spans. On a Europe/Kyiv-zoned device (i.e. most
/// of this app's installs) that is not an edge case: every interval reaching
/// back past the last Sunday of March counts one day low until the October
/// fall-back cancels it.
///
/// Fall-back is benign on its own — a 25 h day still truncates to 1 — which
/// is exactly what makes the spring-forward half so easy to miss in review.
///
/// This counts by RECONSTRUCTING both tokens at UTC midnight from their
/// `.year`/`.month`/`.day` components. UTC observes no transitions, so every
/// calendar day there is uniformly 24 h and the subtraction is always exact.
/// Note this is a reconstruction, NOT `.toUtc()` on a token — that call is on
/// the file header's ILLEGAL list (and is gated by
/// `scripts/forbid_host_local_instant_anchor.sh` RULE 6) because it
/// reinterprets host-local midnight as an instant; reading the three calendar
/// fields, which a date token is DEFINED by, is legal and host-independent.
///
/// Phase 284 promoted this out of
/// `features/booking/presentation/widgets/bookings_day_rail.dart`, where it
/// lived as the private-to-that-feature `calendarDayCount` while
/// `shared/formatters/relative_date.dart` hand-rolled the unsafe form two
/// directories away. `calendarDayCount` now delegates here.
int kyivDaysBetween(DateTime earlier, DateTime later) {
  final DateTime earlierUtc = DateTime.utc(
    earlier.year,
    earlier.month,
    earlier.day,
  );
  final DateTime laterUtc = DateTime.utc(later.year, later.month, later.day);
  return laterUtc.difference(earlierUtc).inDays;
}
