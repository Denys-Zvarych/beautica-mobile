// Phase 7.1 — the day-rail's dot set: which days the master has bookings on.
//
// One unpaged call to `GET /bookings/me/booked-days` (backend Phase 26.5)
// covering today ± [kBookedDaysSpanDays].
//
// ## Filter-independent BY DESIGN — do not key this on the query
//
// This provider deliberately takes NO [MasterBookingsQuery] and must never be
// widened into a family keyed by one. The design computes the rail's dots from
// ALL of the master's bookings, not from the filtered list: the rail is a
// navigation affordance ("where in time is my work?"), not a mirror of the
// list below it. Keying it on the filter would make the dots evaporate as the
// user narrows — so the rail would stop showing them the days they'd need to
// clear the filter to reach, which is precisely when it is most useful.
//
// The backend agrees and enforces it: `/me/booked-days` exposes no status or
// serviceId param at all.
//
// Invalidate this after any action that changes a booking's EXISTENCE
// (Phase 7.3 cancel / no-show); a mere status change does not move a dot.

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:beautica_mobile/shared/formatters/api_date.dart';

import '../data/booking_providers.dart';

part 'booked_days_notifier.g.dart';

/// Half-width of the rail's window, in days — the design's `_railSpan`.
///
/// The resulting inclusive span is `2 * 180 + 1 = 361` days, deliberately
/// under the backend's 366-day range cap with room to spare. Widening this to
/// 183 would produce 367 days and a hard 400 from the endpoint, so the
/// arithmetic — not just the constant — is what must stay under the cap.
const int kBookedDaysSpanDays = 180;

/// The set of local, date-only days on which the master has at least one
/// booking, across today ± [kBookedDaysSpanDays].
///
/// Returns a `Set` because the only consumer question is membership ("does
/// this rail cell get a dot?"), which must stay O(1) — the rail rebuilds this
/// lookup for every visible cell on every scroll frame.
///
/// Generated provider name: `bookedDaysProvider`.
@riverpod
Future<Set<DateTime>> bookedDays(Ref ref) async {
  // Survive navigation for 30 minutes (perf P3). This is the single heaviest
  // request in the feature — a full ±180-day sweep — and plain autoDispose
  // re-issued it on every entry to «Мої записи» AND every return from a
  // detail screen.
  //
  // 30 minutes rather than the list's 5 because the dots are a navigational
  // HINT, not a correctness gate (nothing is authorised off them), so staleness
  // is cheap here. It is not free, though: the window below is computed from
  // `DateTime.now()` at build time, so a cached instance held across local
  // midnight describes a window one day behind. The TTL is what bounds that
  // drift — 30 minutes of a one-day-shifted ±180-day window moves no dot the
  // user can see, whereas an unconditional keepAlive would let it persist for
  // the whole session. Any action that changes a booking's EXISTENCE should
  // still invalidate this explicitly (see the file header).
  final link = ref.keepAlive();
  final Timer timer = Timer(const Duration(minutes: 30), link.close);
  ref.onDispose(timer.cancel);

  // Recomputed on every build — never hoisted to a field or a top-level final,
  // which would pin "today" to first-use for the process's lifetime.
  final DateTime today = dateOnly(DateTime.now());
  // CALENDAR arithmetic, not `Duration(days: n)`. `DateTime.add`/`subtract`
  // add absolute 24h blocks, so crossing a Europe/Kyiv DST transition lands on
  // 23:00 or 01:00 — and `toApiDate`, which reads local `.day` verbatim, would
  // then send a bound one day off twice a year. `DateTime(y, m, d ± n)`
  // normalises out-of-range day components against the calendar and always
  // yields local midnight.
  final DateTime from = DateTime(
    today.year,
    today.month,
    today.day - kBookedDaysSpanDays,
  );
  final DateTime to = DateTime(
    today.year,
    today.month,
    today.day + kBookedDaysSpanDays,
  );

  final List<DateTime> days = await ref
      .read(bookingRepositoryProvider)
      .getMyBookedDays(from: from, to: to);

  // The repository already returns date-only locals; `dateOnly` again is a
  // cheap idempotent guard so a membership test can never miss on a stray
  // time component.
  return days.map(dateOnly).toSet();
}
