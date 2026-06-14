// Phase 15.5 — Dart mirror of the backend `ScheduleDateMath`
// (`com.beautica.master.service.ScheduleDateMath`).
//
// The "apply weekly schedule to a period" surface computes preset ranges
// («Весь поточний місяць / Наступні 3 місяці / Весь рік») and clamps a custom
// selection client-side BEFORE it ever reaches the wire, so the user sees an
// honest range and a disabled / explained CTA instead of a silent backend 400.
// Every rule here MUST match the backend table verified by
// `ScheduleDateMathTest`:
//
//   • Far-future cap     — `today + 2 years` (Feb-29 origin clamps to Feb-28).
//   • whole-current-month— `[max(today, firstOfMonth), lastDayOfMonth]`.
//   • next-N-months      — `[today, today.plusMonths(n)]` with end-of-month
//                          clamping (2024-01-31 +1mo → 2024-02-29;
//                          2023-01-31 +1mo → 2023-02-28;
//                          2024-11-30 +3mo → 2025-02-28).
//   • whole-year         — `[today, Dec 31 of THIS year]` (NOT +1 year).
//   • 366-day span guard — a span wider than 365 days BETWEEN endpoints
//                          (i.e. > 366 inclusive dates) is rejected.
//
// Dart's naive `DateTime(y, m + n, day)` ROLLS OVER an end-of-month origin
// (Jan 31 + 1mo → Mar 2/3) instead of clamping, so [addMonths] / [addYears]
// are hand-rolled to pin onto the last valid day of the target month, exactly
// like `java.time.LocalDate.plusMonths` / `plusYears`.
//
// All dates are date-only (local midnight); the caller injects "today" so the
// presets and cap are wall-clock independent and unit-testable against the
// backend expectation table (the backend pins "today" to Kyiv civil time — the
// mobile client takes its already-local `DateTime.now()` and strips the time,
// which is the equivalent client-side notion of "today").

import 'package:flutter/foundation.dart';

/// An inclusive date-only range `[start, end]` (both local midnight). Mirrors
/// the backend `DateRange` record used by the schedule presets.
@immutable
class ScheduleRangeDates {
  const ScheduleRangeDates(this.start, this.end);

  final DateTime start;
  final DateTime end;

  /// Inclusive day count (1 for a single-day range).
  int get inclusiveDays => end.difference(start).inDays + 1;

  @override
  bool operator ==(Object other) =>
      other is ScheduleRangeDates &&
      _sameDay(other.start, start) &&
      _sameDay(other.end, end);

  @override
  int get hashCode => Object.hash(
    start.year,
    start.month,
    start.day,
    end.year,
    end.month,
    end.day,
  );

  @override
  String toString() => 'ScheduleRangeDates($start, $end)';

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

/// Pure calendar arithmetic for the validity-window presets and the far-future
/// cap. Stateless except for an injectable [today] so every rule is unit
/// testable against the backend `ScheduleDateMathTest` expectation table.
class ScheduleDateMath {
  /// Builds with an explicit "today" (date-only). Production callers pass
  /// `DateTime.now()`; tests pass a fixed date so presets/cap are deterministic.
  ScheduleDateMath({required DateTime today})
    : today = DateTime(today.year, today.month, today.day);

  /// Hard upper bound on how far ahead any validity window may reach:
  /// `today + 2 years`. Mirrors the backend `FAR_FUTURE_CAP_YEARS`.
  static const int farFutureCapYears = 2;

  /// Maximum number of days BETWEEN the endpoints of a window — 365 days
  /// between → 366 inclusive dates (a full leap year). Mirrors the backend
  /// `MAX_EXPANSION_SPAN_DAYS`.
  static const int maxSpanDays = 365;

  /// Today (date-only, local midnight).
  final DateTime today;

  /// A date strictly before [today] is past; [today] itself is not past.
  bool isPast(DateTime date) => _dateOnly(date).isBefore(today);

  /// Today and any future date are selectable; past dates are frozen.
  bool isSelectable(DateTime date) => !isPast(date);

  /// Far-future cap: `today + 2 years`, with a Feb-29 origin clamped to Feb-28
  /// in a non-leap target year (2024-02-29 → 2026-02-28).
  DateTime cap() => addYears(today, farFutureCapYears);

  /// `today + [n] months`, clamping an end-of-month origin onto a shorter
  /// target month instead of rolling over (Java `LocalDate.plusMonths`
  /// semantics). [n] may be negative.
  DateTime addMonths(DateTime date, int n) {
    final DateTime d = _dateOnly(date);
    // Normalise the target year/month, then clamp the day to that month's last.
    final int zeroBasedMonth = d.month - 1 + n;
    final int targetYear = d.year + _floorDiv(zeroBasedMonth, 12);
    final int targetMonth = _floorMod(zeroBasedMonth, 12) + 1;
    final int lastDay = _lastDayOfMonth(targetYear, targetMonth);
    final int clampedDay = d.day <= lastDay ? d.day : lastDay;
    return DateTime(targetYear, targetMonth, clampedDay);
  }

  /// `today + [n] years`, clamping a Feb-29 origin to Feb-28 in a non-leap
  /// target year (Java `LocalDate.plusYears` semantics). [n] may be negative.
  DateTime addYears(DateTime date, int n) {
    final DateTime d = _dateOnly(date);
    final int targetYear = d.year + n;
    final int lastDay = _lastDayOfMonth(targetYear, d.month);
    final int clampedDay = d.day <= lastDay ? d.day : lastDay;
    return DateTime(targetYear, d.month, clampedDay);
  }

  /// «Весь поточний місяць»: from the later of [today] and the 1st of the
  /// month, through the last (leap-aware) day of the current month.
  ScheduleRangeDates wholeCurrentMonth() {
    final DateTime firstOfMonth = DateTime(today.year, today.month, 1);
    final DateTime from = today.isAfter(firstOfMonth) ? today : firstOfMonth;
    final DateTime to = DateTime(
      today.year,
      today.month,
      _lastDayOfMonth(today.year, today.month),
    );
    return ScheduleRangeDates(from, to);
  }

  /// «Наступні N місяців»: from [today] through `today.plusMonths(n)` with the
  /// documented end-of-month clamp. [n] must be positive.
  ScheduleRangeDates nextNMonths(int n) {
    assert(n > 0, 'Month count must be positive');
    return ScheduleRangeDates(today, addMonths(today, n));
  }

  /// «Весь рік»: from [today] through Dec 31 of the CURRENT year — never
  /// `+1 year`, which would roll a Feb-29 origin into next year.
  ScheduleRangeDates wholeYear() {
    return ScheduleRangeDates(today, DateTime(today.year, 12, 31));
  }

  /// True when [to] reaches past the far-future [cap].
  bool exceedsCap(DateTime to) => _dateOnly(to).isAfter(cap());

  /// True when the inclusive span of `[from, to]` is wider than a full leap
  /// year (more than 366 inclusive dates / more than 365 days between).
  bool exceedsSpan(DateTime from, DateTime to) =>
      _dateOnly(to).difference(_dateOnly(from)).inDays > maxSpanDays;

  /// Clamps a candidate window end to no later than the far-future [cap] so a
  /// preset / custom selection never sends a too-far-future `validTo` that the
  /// backend would reject with a 400.
  DateTime clampToCap(DateTime to) {
    final DateTime end = _dateOnly(to);
    final DateTime ceiling = cap();
    return end.isAfter(ceiling) ? ceiling : end;
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Last day of [month] in [year] (28/29/30/31), leap-aware. `DateTime(y, m+1,
  /// 0)` resolves to the last day of month `m`.
  static int _lastDayOfMonth(int year, int month) =>
      DateTime(year, month + 1, 0).day;

  /// Floor division (toward negative infinity) so negative month offsets borrow
  /// a whole year correctly (e.g. month index -1 → previous year's December).
  static int _floorDiv(int a, int b) => (a - (a % b + b) % b) ~/ b;

  /// Floor modulo (always in `[0, b)`), pairing with [_floorDiv].
  static int _floorMod(int a, int b) => (a % b + b) % b;
}
