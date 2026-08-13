// Phase 244 follow-up — the master «Мої записи» day view for an
// EXPLICIT_TIMES working day (the master declared discrete times like
// `11:00`, `15:00`, `16:30` instead of a continuous working window).
//
// Originally ported from the approved preview
// `docs/signup-designs/MasterTimelineExplicitTimes/lib/widgets/
// declared_time_cards.dart`, Option E2 — a bespoke three-line card (time /
// client / `service · duration`), no price pill, no status badge.
//
// ## THE SWAP (2026-08) — booked entries now render the SHIPPED
// `MasterBookingCard`, not a bespoke card
//
// User decision, verbatim: "use the shipped card for booked slots (1 hour
// maybe will be the best option i think)". The bespoke three-line card never
// read [Booking.status], so a CANCELLED/DECLINED/NOT_COMPLETED booking used
// to render identically to a CONFIRMED one here — a real gap against the
// INTERVAL-day grid, which always shows a status signal via
// [MasterBookingCard]. That gap, and the missing price pill and client
// avatar, are what this swap restores, at the cost of the old three-line
// text shape: a booked entry now prints a TIME RANGE («11:00–12:30»&nbsp;—
// [MasterBookingCard]'s own recipe) instead of «Манікюр · 60 хв», and the
// declared time moves INSIDE the card rather than leading the row as its own
// line. Both are accepted consequences of the swap, not regressions.
//
// [MasterBookingCard] is reused VERBATIM — see [_kEntryMinHeight]'s doc for
// exactly which constructor argument selects its layout and why. Nothing in
// this file forks, restyles or re-parameterises that widget.
//
// ## THE SHAPE, now
//
// One box per entry, in ascending time order, ALL THE SAME FOOTPRINT — see
// [_kEntryMinHeight]:
//   * booked — the shipped [MasterBookingCard], unmodified, at
//     `minHeight: _kEntryMinHeight` (its FULL body: client name, time range,
//     service, price/price-band, status badge, client avatar mark).
//   * free — [_FreeTimeCard]: time / «Вільно», muted. Same fill, radius,
//     border and floor as the booked box; the only difference is LIFT — the
//     booked card keeps its shadow, the free card drops it and stands on its
//     border alone. NOT a button, no tap target.
//
// NO hour ruler, NO gridlines, NO hour labels — nothing here derives from
// `BookingsTimelineGrid`'s `_kHourH`, and duration still never drives this
// list's GEOMETRY (it DOES drive MEMBERSHIP — see the "CONSUMED DECLARED
// TIMES" section below; the two are different questions): every entry floors
// at [_kEntryMinHeight] regardless of the booking's length, so 30/60/90-minute
// bookings render at the same box —
// pinned by `declared_time_cards_test.dart`'s "uniform card heights" group,
// which now also asserts a FREE card and a BOOKED card in the same list
// match, box for box (a hard requirement, not a judgement call).
//
// ## THE ENTRY LIST IS A UNION, NEVER A FILTER
//
// [_mergeDeclaredAndBookings] is the whole of this file's correctness
// contract. [BookingsDiscoveryView] hands this widget [bookings] UNFILTERED
// by `bookingsInsideScheduleWindow` — that predicate is a GRID concept
// (INTERVAL days only) and must never silently drop a row here.
//
// ⚠ "UNFILTERED" HERE MEANS "NOT FILTERED CLIENT-SIDE". It never meant
// "complete". [bookings] is `BookingsDayState.items`, which the master's
// status/service filter narrows SERVER-SIDE, on the wire — a fact this
// contract did not anticipate when it was written, and the source of the
// false-«Вільно» bug fixed on 2026-08-13. See the "FREE CARDS ARE A CLAIM"
// section below and [DeclaredTimeCards.showsAllOccupancy].
//
// Every booking in [bookings] gets exactly one card:
//   * its start matches a declared time  -> that declared time's card is
//     booked;
//   * its start matches NO declared time (e.g. it was booked before the
//     master edited that day's hours) -> it still renders, as its OWN entry
//     at its OWN time, merged into the list in time order. Dropping it would
//     be data loss, not tidiness.
// A declared time with no matching booking renders as a free card, UNLESS it
// is CONSUMED (see the next section) or free cards are SUPPRESSED outright
// (see "FREE CARDS ARE A CLAIM"). The header count above this widget
// ([BookingsDiscoveryView]'s `masterBookingsCount`) is derived from the SAME
// [bookings] list this widget renders every card of — see that file's
// `_Loaded._body` — so the two can never disagree: free entries are not
// bookings and are never counted, and a consumed declared time was never a
// booking either, so dropping it cannot move that count.
//
// ## CONSUMED DECLARED TIMES ARE DROPPED — MEMBERSHIP, NOT GEOMETRY
//
// User decision, 2026-08-13: a declared time swallowed by an EARLIER
// booking's duration is HIDDEN — no card, no muted state, no «Зайнято»
// label. Rationale: it mirrors the backend, which already omits such a time
// from `GET /slots`, so the master's own day view matches what clients
// actually see when they try to book.
//
// READ THIS TOGETHER WITH the "duration still never drives this list's
// GEOMETRY" note further down — the two do NOT contradict each other:
//   * GEOMETRY (unchanged): a booking's length never changes the SIZE or the
//     POSITION of any box. Every entry still floors at [_kEntryMinHeight] and
//     still sits at its own start minute; a 90-minute booking occupies
//     exactly the same box as a 30-minute one.
//   * MEMBERSHIP (what changed): a booking's length now decides WHICH
//     declared times are in the list at all. `endAt` is read for that
//     question, and for nothing else.
//
// See [consumesDeclaredTimes] and [_mergeDeclaredAndBookings]'s pass 1b for
// the exact predicate, its half-open boundary, and its status allowlist.
//
// ## FREE CARDS ARE A CLAIM — SUPPRESSED WHEN THE QUERY CANNOT BACK IT
//
// Bug fixed 2026-08-13 (user-reported). «Вільно» is an ASSERTION about the
// master's clock: nothing occupies this declared time. This list can only
// make that assertion from [bookings], and [bookings] is narrowed on the
// WIRE by the master's own filter — so with «Завершені» ticked, every
// upcoming CONFIRMED booking was off the list and its declared time printed
// «Вільно» over a genuinely-booked slot. Same for «Скасовані», «Підтверджені»
// and «Не відбулися» alone, and — independently of status — for ANY service
// filter, which hides every booking of another service even in the default
// view.
//
// [DeclaredTimeCards.showsAllOccupancy] is the caller's answer to "can this
// list see everything that occupies the clock?" (`BookingsDayQuery
// .showsAllOccupancy` — the invariant is stated ONCE, there, next to
// `dayListWireStatuses`, which created the situation). When it is `false`,
// [_mergeDeclaredAndBookings] emits NO free entries at all: booked entries
// and strays only.
//
// SUPPRESSION, NOT RESTYLING — considered and rejected: a muted/unknown
// variant of the free card is still a card claiming to know something about
// that minute. This mirrors the INTERVAL grid, which has never had this bug
// precisely because it draws only what it fetched: absence of a card is not
// an affirmative claim of freedom. No second network request is made.
//
// The screen handles the resulting all-empty case: `BookingsDiscoveryView
// ._body` routes a filtered day with nothing left to render to the
// filter-aware «Немає записів за цим фільтром» state rather than to a blank
// column.
//
// ## Kyiv time discipline
//
// [Booking.startAt] is canonical UTC. Matching it against a declared
// [TimeOfDay] (a pure wall-clock value, carrying no zone of its own) reads
// through [toBeauticaTime] — never `.hour`/`.minute` off the raw UTC instant,
// which would render the wrong card on any non-Kyiv device or CI's UTC
// runner. Mirrors `bookings_timeline_grid.dart`'s own
// `_minutesSinceDayStart` (kept private there; re-derived here rather than
// exported, since the two files' minute conventions — this one never needs
// values >= 1440, that file's R1 fix explicitly does for a booking crossing
// midnight — are not quite the same contract).
//
// ## Gating — EXPLICIT_TIMES days only
//
// This widget is never constructed for an INTERVAL day. `BookingsDiscoveryView
// ._Loaded` gates the branch on `EffectiveDay.isExplicitTimes`; every
// INTERVAL day keeps rendering `BookingsTimelineGrid`, byte-for-byte
// unchanged, exactly as before this feature.

import 'package:flutter/foundation.dart' show listEquals, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart'
    show formatTime;
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';

import '../../domain/booking.dart';
import '../../domain/booking_status.dart';
import 'master_booking_card.dart';

/// One resolved row of the declared-times list — a declared time with an
/// OPTIONAL matched booking, or a booking whose start matched no declared
/// time (see [_mergeDeclaredAndBookings]'s "stray" pass). [time] is always
/// the entry's own Kyiv wall-clock minute, whether it came from the day's
/// declared times or from an unmatched booking's own start.
class _DeclaredEntry {
  const _DeclaredEntry({
    required this.minute,
    required this.time,
    required this.booking,
  });

  /// Minutes since the selected Kyiv day's midnight — the sort key.
  final int minute;
  final TimeOfDay time;
  final Booking? booking;
}

/// Kyiv wall-clock minutes-since-midnight for [instant] on the day
/// [midnight] anchors — mirrors `bookings_timeline_grid.dart`'s
/// `_minutesSinceDayStart`. Not exported from that file (see this file's
/// header); re-derived here rather than duplicated via a shared export
/// because the two live on genuinely separate contracts (see the header).
int _kyivMinutesSinceMidnight(DateTime instant, tz.TZDateTime midnight) {
  final tz.TZDateTime local = toBeauticaTime(instant);
  return local.difference(midnight).inMinutes;
}

/// Whether a booking in [status] OCCUPIES the clock for the purpose of
/// hiding a later declared time — see this file's "CONSUMED DECLARED TIMES
/// ARE DROPPED" section.
///
/// An ALLOWLIST, deliberately, mirroring `BookingDisplayX.showsPrice`'s own
/// `confirmed || completed` idiom (`booking_display_x.dart:118-119`): only an
/// appointment that will happen or did happen takes the master's time. A
/// CANCELLED, DECLINED or NOT_COMPLETED booking frees the clock again, so a
/// declared time behind one of those is genuinely FREE and must still render.
///
/// [BookingStatus.unknown] does NOT consume — and this is a DELIBERATE
/// divergence from `booking_lane_layout.dart`'s `_isActiveClass`, which does
/// treat `unknown` as active. Do not "fix" it into agreement. The two answer
/// opposite questions: there, including `unknown` grants the booking a lane
/// (it stays VISIBLE); here, including it would HIDE a slot. Hiding is the
/// destructive direction, and [BookingStatus.unknown]'s own doc pins the
/// contract as "grant nothing" — so an unrecognised wire status may not earn
/// the power to erase a declared time from the master's day.
///
/// This is deliberately STRICTER than pass 1's exact-start pairing, which is
/// status-blind (a CANCELLED booking starting exactly on a declared time
/// still takes that time's card, rendered with its own cancelled badge — see
/// the "status renders and differentiates" test group). That asymmetry is
/// intentional: pass 1 SHOWS the booking, pass 1b HIDES a slot.
///
/// VISIBLE FOR TESTING, and for exactly one reason: this allowlist is the
/// other half of `BookingsDayQuery.showsAllOccupancy`'s lockstep. While it was
/// file-private the guard in `bookings_day_query_test.dart` could only restate
/// the predicate against a hand-copied literal — adding a status here could
/// not turn any test red. `bookings_day_query_test.dart`'s lockstep group now
/// reads THIS function (`BookingStatus.filterable.where(consumesDeclaredTimes)`)
/// so a drift fails mechanically. Production callers stay inside this file.
@visibleForTesting
bool consumesDeclaredTimes(BookingStatus status) => switch (status) {
  BookingStatus.confirmed => true,
  BookingStatus.completed => true,
  BookingStatus.cancelled => false,
  BookingStatus.declined => false,
  BookingStatus.notCompleted => false,
  BookingStatus.unknown => false,
};

/// The union of [declaredTimes] and [bookings] — see this file's "THE ENTRY
/// LIST IS A UNION" section. Every booking in [bookings] appears in exactly
/// one returned entry; no BOOKING is ever dropped.
///
/// A DECLARED TIME, by contrast, CAN be dropped — exactly two ways, both
/// about list MEMBERSHIP and neither touching the geometry contract:
///   * pass 1b removes an unmatched declared time that an active booking's
///     duration already swallowed (this file's "CONSUMED DECLARED TIMES ARE
///     DROPPED" section);
///   * pass 1c removes EVERY unmatched declared time when
///     [showsAllOccupancy] is `false` (this file's "FREE CARDS ARE A CLAIM"
///     section).
///
/// Matching is by exact Kyiv minute, first-unconsumed-booking-wins when more
/// than one booking shares a minute (a double-booked declared time is not the
/// common case this mode is designed for, but every such booking still gets
/// its own card rather than being silently discarded). "First" is a
/// genuinely deterministic order: [sortedBookings] below sorts by
/// `startAt` with [Booking.id] as an explicit tie-break, because
/// `List.sort` is NOT stable in Dart — leaving two identical-`startAt`
/// bookings' relative order to the sort algorithm's whim would make this
/// doc's own "first" claim false for that case.
List<_DeclaredEntry> _mergeDeclaredAndBookings(
  List<TimeOfDay> declaredTimes,
  List<Booking> bookings,
  DateTime day, {
  required bool showsAllOccupancy,
}) {
  final tz.TZDateTime midnight = tz.TZDateTime(
    beauticaZone,
    day.year,
    day.month,
    day.day,
  );

  // Bookings arrive pre-sorted by `startAt` ASC from the server, but the
  // FINAL merge's two-pointer step (further below) depends on that
  // ordering — sort defensively rather than trust it silently. Pass 1
  // (immediately below) does NOT depend on this order for correctness — it
  // looks up by minute via a map — but it DOES rely on it for the
  // documented tie-break (see [_mergeDeclaredAndBookings]'s doc:
  // "first-unconsumed-booking-wins"), since indices are appended to each
  // minute's bucket in this sorted order. `startAt` alone is NOT a
  // sufficient sort key: two bookings can genuinely share one `startAt`
  // (a double-booked declared time), and `List.sort`'s algorithm is
  // explicitly documented as unstable, so equal-`startAt` elements could
  // land in either relative order on any given run. [Booking.id] (globally
  // unique, stable, comparable) is the secondary key that makes the sort —
  // and therefore "first" — actually deterministic.
  final List<Booking> sortedBookings = List<Booking>.of(bookings)
    ..sort((Booking a, Booking b) {
      final int byStart = a.startAt.compareTo(b.startAt);
      return byStart != 0 ? byStart : a.id.compareTo(b.id);
    });
  final List<int> bookingMinutes = sortedBookings
      .map((Booking b) => _kyivMinutesSinceMidnight(b.startAt, midnight))
      .toList(growable: false);
  final List<bool> consumed = List<bool>.filled(sortedBookings.length, false);

  // One O(B) pass building a minute -> booking-indices index, so pass 1
  // below is O(D) lookups instead of an O(D×B) nested scan of
  // `sortedBookings` per declared time. NOT the two-pointer discipline —
  // that applies only to the final merge step further below, where both
  // input lists are already known-ascending; a minute -> indices map is the
  // right tool here because pass 1 needs random-access-by-minute, not a
  // linear co-walk.
  final Map<int, List<int>> indicesByMinute = <int, List<int>>{};
  for (int j = 0; j < sortedBookings.length; j++) {
    indicesByMinute.putIfAbsent(bookingMinutes[j], () => <int>[]).add(j);
  }

  // Pass 1 — one entry per declared time, VERBATIM order, matched against
  // the first unconsumed booking at that exact minute via the map built
  // above (O(1) amortized per declared time, not a scan of every booking).
  final List<_DeclaredEntry> declaredEntries = <_DeclaredEntry>[];
  for (final TimeOfDay t in declaredTimes) {
    final int dm = t.hour * 60 + t.minute;
    int matchIndex = -1;
    final List<int>? candidates = indicesByMinute[dm];
    if (candidates != null) {
      for (final int j in candidates) {
        if (!consumed[j]) {
          matchIndex = j;
          break;
        }
      }
    }
    if (matchIndex == -1) {
      declaredEntries.add(_DeclaredEntry(minute: dm, time: t, booking: null));
    } else {
      consumed[matchIndex] = true;
      declaredEntries.add(
        _DeclaredEntry(
          minute: dm,
          time: t,
          booking: sortedBookings[matchIndex],
        ),
      );
    }
  }

  // Pass 1b — DROP every declared time that is CONSUMED by some booking's
  // duration (see this file's "CONSUMED DECLARED TIMES ARE DROPPED"
  // section). Only entries pass 1 left unmatched are candidates: an entry
  // that already carries its own booking renders that booking's card and is
  // never a "free" slot to begin with.
  //
  // THE PREDICATE — half-open `[startAt, endAt)` in KYIV minutes:
  //     startMinute <= dm && dm < endMinute
  // `endAt == the declared time` is NOT consumption: an 11:00 booking ending
  // exactly at 12:00 leaves 12:00 genuinely free and still rendered. Same
  // "touching endpoints don't count" rule as `booking_lane_layout.dart`'s
  // `_overlaps` (`a.endAt == b.startAt` is NOT an overlap) and as the
  // backend's own strict `isBefore`/`isAfter` slot test — one convention,
  // not two.
  //
  // A CONSUMING BOOKING NEED NOT START ON A DECLARED TIME. The schedule
  // template can be edited after the fact, the day can be an override, or
  // the booking can predate the create-time guard — so this scans every
  // booking rather than only the ones pass 1 matched.
  //
  // O(D×B) ON PURPOSE, not an oversight. Pass 1 above uses a minute -> index
  // map because it asks an EQUALITY question; this asks a RANGE question,
  // where the cheap trick would be an ascending sweep with a running max
  // `endMinute`. That sweep leans on both inputs staying in step, and its
  // failure mode is DESTRUCTIVE — desynchronise it and it silently DROPS an
  // early declared time sitting behind a later booking, which is exactly the
  // class of bug this pass exists to fix. So the nested scan is
  // order-independent BY CHOICE: it stays correct without depending on an
  // upstream ordering invariant, and at these sizes — one day's declared
  // times times one day's bookings (both single-to-low-double digits),
  // computed once per input change ([_DeclaredTimeCardsState.didUpdateWidget]'s
  // memo), never per frame — the saved comparisons are worth far less than
  // that independence.
  final List<int> bookingEndMinutes = sortedBookings
      .map((Booking b) => _kyivMinutesSinceMidnight(b.endAt, midnight))
      .toList(growable: false);

  bool isConsumed(int dm) {
    for (int j = 0; j < sortedBookings.length; j++) {
      if (!consumesDeclaredTimes(sortedBookings[j].status)) continue;
      if (bookingMinutes[j] <= dm && dm < bookingEndMinutes[j]) return true;
    }
    return false;
  }

  declaredEntries.removeWhere(
    (_DeclaredEntry e) => e.booking == null && isConsumed(e.minute),
  );

  // Pass 1c — when the caller's query CANNOT see every occupying booking,
  // drop every remaining unmatched declared time: a free card is a CLAIM
  // this list is no longer entitled to make. See the file header's "FREE
  // CARDS ARE A CLAIM" section and [DeclaredTimeCards.showsAllOccupancy].
  //
  // Deliberately AFTER pass 1b rather than replacing it: the two rules
  // compose, and keeping 1b first means the occupancy-complete path (the
  // default view, and select-all) runs byte-for-byte as before — this pass
  // is a no-op there.
  //
  // Touches ONLY `e.booking == null` entries, so it can never drop a
  // BOOKING; the union contract above is untouched. Pass 2 (strays) runs
  // next and is unaffected — a booking whose start matches no declared time
  // still renders, filtered wire or not.
  if (!showsAllOccupancy) {
    declaredEntries.removeWhere((_DeclaredEntry e) => e.booking == null);
  }

  // Pass 2 — every booking pass 1 did NOT consume (its start matches no
  // declared time) gets its own entry, at its own minute. Never dropped.
  // UNTOUCHED by pass 1b: dropping the 12:00 slot a 10:00 booking swallowed
  // must never drop the 10:00 booking itself. `consumed[]` (pass 1's
  // matched-booking bookkeeping — an unrelated meaning of the word to pass
  // 1b's) is not written by pass 1b at all.
  final List<_DeclaredEntry> strayEntries = <_DeclaredEntry>[];
  for (int j = 0; j < sortedBookings.length; j++) {
    if (consumed[j]) continue;
    final int m = bookingMinutes[j];
    strayEntries.add(
      _DeclaredEntry(
        minute: m,
        time: TimeOfDay(hour: (m ~/ 60) % 24, minute: m % 60),
        booking: sortedBookings[j],
      ),
    );
  }

  // Merge — both lists are ascending by minute (declaredTimes is resolved
  // sorted+de-duped by the schedule mapper; sortedBookings was just sorted
  // above and pass 2 preserves that order), so a stable two-pointer merge is
  // enough; ties favour the declared entry.
  final List<_DeclaredEntry> merged = <_DeclaredEntry>[];
  int di = 0;
  int si = 0;
  while (di < declaredEntries.length && si < strayEntries.length) {
    if (declaredEntries[di].minute <= strayEntries[si].minute) {
      merged.add(declaredEntries[di++]);
    } else {
      merged.add(strayEntries[si++]);
    }
  }
  merged.addAll(declaredEntries.skip(di));
  merged.addAll(strayEntries.skip(si));
  return merged;
}

/// THE ONE BOX every entry in this list occupies — booked or free. A hard
/// product requirement, not a judgement call: every card in the column must
/// read as the same footprint down the page, never a taller booked card next
/// to a shorter free one.
///
/// 120 is not an arbitrary round number:
///   * It is `bookings_timeline_grid.dart`'s own `_kHourH` (that file's
///     `static const double _kHourH = 120`) — literally "one hour" at that
///     grid's dp/hour scale, matching the user's own stated preference for
///     the booked card's size ("1 hour maybe will be the best option").
///   * It clears [MasterBookingCard.fullLayoutMinHeight] (118dp — the floor
///     at or above which that card renders its FULL body rather than compact
///     or micro; see that constant's own doc) with 2dp to spare. A booked
///     entry here therefore ALWAYS selects the full body — never falls back
///     to compact/micro — which is the whole point of picking the "1 hour"
///     size deliberately rather than any value `>= 118`.
///   * [MasterBookingCard.occupiedHeightFor] resolves this to exactly
///     `max(120, 118) == 120` at textScaler 1.0, so the booked card's REAL
///     rendered box is 120, not merely floored at it with slack above.
///
/// [_FreeTimeCard] is floored at this SAME constant (a `BoxConstraints
/// (minHeight: _kEntryMinHeight)` on its own `Container`, never a fixed
/// `height:` — same reasoning as [MasterBookingCard.minHeight] being a floor,
/// not a ceiling: real content past it still grows the box instead of
/// clipping).
///
/// THE SCALE-1.0 CONSTANT both variants share. Above 1.0, [_FreeTimeCard]
/// does not use this bare number as its floor — it calls
/// [_freeCardMinHeightFor] instead. See that function's doc for the closed
/// gap this used to describe.
const double _kEntryMinHeight = 120;

/// [_FreeTimeCard]'s scale-aware floor — the mechanism that keeps it equal
/// to a booked [MasterBookingCard] ABOVE textScaler 1.0, not just at 1.0.
///
/// THE GAP THIS CLOSES: [MasterBookingCard]'s full body is a fixed stack of
/// single-line rows, so its REAL rendered box grows past `minHeight: 120` as
/// the ambient text scale rises — nothing here has to make that happen, it
/// falls out of the card's own real `Text` widgets scaling like any other
/// text. [_FreeTimeCard]'s own two-line content, by contrast, never grows
/// enough on its own to reach a taller floor at any realistic scale, so a
/// bare `120` constraint on it stopped matching the booked card's real box
/// above 1.0 — measured 124dp @ 1.15 and 132dp @ 1.3 for the booked card,
/// pinned by [MasterBookingCard.fullLayoutNaturalHeight]'s own doc ("ONLY AT
/// 1.0 ... at 1.15 (a 17dp line box) and 1.3 (20dp) ... those two naturals
/// are unchanged at 124 / 132dp — re-measured, not assumed"). This function
/// makes [_FreeTimeCard]'s floor track that same growth.
///
/// NO SCALE-AWARE API EXISTS ON [MasterBookingCard] TO REUSE HERE.
/// [MasterBookingCard.fullLayoutNaturalHeight] is a `static const` — it
/// cannot read a scale — and its own doc says so explicitly: "TEXT SCALE 1.0
/// ONLY ... any caller predicting a box from this constant MUST gate itself
/// on `MediaQuery.textScalerOf(context).scale(1) <= 1.0`".
/// [MasterBookingCard.occupiedHeightFor] is the same: "Valid at textScaler
/// 1.0 only". Both exist purely to predict the card's box WITHOUT building it
/// (for `bookings_timeline_grid.dart`'s viewport culling), and neither was
/// ever extended past 1.0 because nothing needed that until this fix — so
/// the three measured points below are re-derived here, matching the exact
/// numbers those two docs already publish, rather than inventing a second,
/// possibly-drifting copy of the same measurement.
///
/// THE THREE MEASURED POINTS (re-measured, never assumed):
///   * 1.00 -> 120 (the booked card's full body naturally measures 118dp at
///     1.0 — [MasterBookingCard.fullLayoutNaturalHeight] — under the 120dp
///     floor, so the floor wins and both variants land on 120)
///   * 1.15 -> 124
///   * 1.30 -> 132
///
/// THE DERIVATION — piecewise-linear across those three points, each segment
/// exact at its own endpoints (not merely "close"):
///   * at or below 1.0 -> flat at [_kEntryMinHeight] (120);
///   * (1.0, 1.15] -> linear between (1.0, 120) and (1.15, 124);
///   * (1.15, +inf) -> linear between (1.15, 124) and (1.30, 132),
///     EXTRAPOLATED past 1.3, never clamped — the booked card keeps growing
///     past 1.3 too (nothing in [MasterBookingCard]'s full body caps out
///     there), so clamping this side would silently reopen the exact gap
///     this function exists to close, right where accessibility text sizes
///     are largest.
///
/// WHY NOT A SHARED INTRINSIC-HEIGHT PASS (option (a), rejected) — this list
/// already had exactly that shape once and paid for it: `master_booking_card
/// .dart`'s "THE COMPACT PRICE CAP IS GONE" section describes a
/// `LayoutBuilder`-driven per-card measurement pulled as a mobile-perf
/// MEDIUM, because it made the card illegal under `IntrinsicHeight` and cost
/// a relayout boundary per card. A per-build read of
/// [MediaQuery.textScalerOf] plus four multiplications is O(1), adds no
/// relayout boundary, and needs no `IntrinsicHeight` — closing the same gap
/// at a fraction of the cost.
double _freeCardMinHeightFor(BuildContext context) {
  final double scale = MediaQuery.textScalerOf(context).scale(1);
  if (scale <= 1.0) return _kEntryMinHeight;

  const double kAt115 = 124;
  if (scale <= 1.15) {
    // (1.0 -> 120) to (1.15 -> 124).
    return _kEntryMinHeight +
        (scale - 1.0) / 0.15 * (kAt115 - _kEntryMinHeight);
  }

  const double kAt130 = 132;
  // (1.15 -> 124) to (1.30 -> 132) — extrapolated, not clamped, past 1.30.
  return kAt115 + (scale - 1.15) / 0.15 * (kAt130 - kAt115);
}

/// The declared-times day body — a plain scrolling list, one box per
/// [_mergeDeclaredAndBookings] entry: the shipped [MasterBookingCard] for a
/// booked entry, [_FreeTimeCard] for a free one — see this file's header.
/// Sits inside the same `Expanded(child: Padding(...))` slot
/// `BookingsDiscoveryView._Loaded._body` gives `BookingsTimelineGrid` on an
/// INTERVAL day, so it owns its own scrolling exactly like that widget does.
///
/// A [StatefulWidget], NOT the `StatelessWidget` this shipped as originally
/// (mobile-perf MEDIUM fix) — `_Loaded` (the parent) is itself a
/// `StatelessWidget` constructed fresh by its own parent `Consumer` on every
/// rebuild, so a plain `build()`-time call to [_mergeDeclaredAndBookings]
/// reran on every rebuild regardless of whether [declaredTimes]/[bookings]/
/// [day] had actually changed — the same regression class already fixed
/// twice on the sibling INTERVAL path (see `bookings_discovery_view.dart`'s
/// `_visibleBookingsFor` feeding [BookingsTimelineGrid]'s own
/// `didUpdateWidget` gate). [BookingsTimelineGrid] is the closer sibling of
/// the two idioms available: it is itself a leaf `StatefulWidget` occupying
/// this exact slot, owning its OWN recompute cache in `didUpdateWidget`
/// rather than reaching up into a parent `State` — no plumbing across a
/// widget boundary, and no need to expose the file-private [_DeclaredEntry]
/// shape outside this file (hoisting the memo into
/// `_BookingsDiscoveryViewState`, `_visibleBookingsFor`'s home, would
/// require exactly that). This widget mirrors that shape instead.
class DeclaredTimeCards extends StatefulWidget {
  const DeclaredTimeCards({
    required this.declaredTimes,
    required this.bookings,
    required this.day,
    required this.showsAllOccupancy,
    required this.onTapBooking,
    super.key,
  });

  /// The day's declared times, VERBATIM — one card each, in declared order,
  /// unless dropped by [_mergeDeclaredAndBookings]'s pass 1b/1c. Nothing is
  /// generated between them and nothing is padded onto the ends.
  final List<TimeOfDay> declaredTimes;

  /// The day's bookings, UNFILTERED by any working-hours window — see this
  /// file's header. Every one of these renders as a card. NOT necessarily
  /// every booking the day HAS: the master's status/service filter narrows
  /// this list on the wire, which is what [showsAllOccupancy] is about.
  final List<Booking> bookings;

  /// Whether [bookings] can be trusted to contain EVERY booking that occupies
  /// this day's clock — i.e. whether "no booking at this declared time" may
  /// be rendered as «Вільно».
  ///
  /// `BookingsDayQuery.showsAllOccupancy` off the LIVE query is the only
  /// intended source; that getter owns the predicate and its lockstep with
  /// [consumesDeclaredTimes]. `false` suppresses every free card — see this
  /// file's "FREE CARDS ARE A CLAIM" section for why suppression rather than
  /// a muted variant, and why no second fetch is made.
  ///
  /// Required, never defaulted: defaulting to `true` would fail OPEN — a new
  /// call site that forgot to thread it would silently reintroduce the exact
  /// bug this parameter exists to close.
  final bool showsAllOccupancy;

  /// The selected Kyiv calendar day — the anchor
  /// [_kyivMinutesSinceMidnight] measures every booking's start against.
  final DateTime day;

  /// Fires with the tapped booking. No `Navigator`/`context.push` in this
  /// leaf widget — the caller owns navigation, same contract as
  /// `BookingsTimelineGrid.onBookingTap`.
  final ValueChanged<Booking> onTapBooking;

  @override
  State<DeclaredTimeCards> createState() => _DeclaredTimeCardsState();
}

class _DeclaredTimeCardsState extends State<DeclaredTimeCards> {
  /// The last-computed merge — recomputed only in [initState] and,
  /// conditionally, in [didUpdateWidget]. `build()` never calls
  /// [_mergeDeclaredAndBookings] directly, which is the whole of the fix:
  /// a rebuild with unchanged inputs (a fresh `DeclaredTimeCards` instance
  /// from the parent's own rebuild, same data) reuses this list instead of
  /// reallocating one.
  late List<_DeclaredEntry> _entries;

  @override
  void initState() {
    super.initState();
    _entries = _mergeDeclaredAndBookings(
      widget.declaredTimes,
      widget.bookings,
      widget.day,
      showsAllOccupancy: widget.showsAllOccupancy,
    );
  }

  @override
  void didUpdateWidget(covariant DeclaredTimeCards oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Mirrors [BookingsTimelineGrid.didUpdateWidget]'s gate:
    //   * `bookings` — `identical`, not `==`. `List` has reference equality
    //     anyway, and `BookingsDayState.items` (this file's caller always
    //     passes that list, or a filtered derivative of it) only changes
    //     identity on a genuine re-fetch — see `bookings_discovery_view
    //     .dart`'s `_visibleBookingsFor` doc.
    //   * `day` — value comparison; `DateTime` overrides `==`.
    //   * `declaredTimes` — value comparison via [listEquals], NOT
    //     `identical`. Unlike `bookings`, this list is `resolved.times` off
    //     a fresh `EffectiveDay` the schedule notifier constructs on every
    //     resolve regardless of whether the declared times actually changed
    //     (the same reason `_visibleBookingsFor` compares
    //     `ScheduleTimelineWindow`'s fields by value rather than by
    //     reference) — an `identical` check here would defeat the memo on
    //     every schedule refetch, changed or not. [TimeOfDay] overrides
    //     `==`, so [listEquals] is a true value comparison.
    //   * `showsAllOccupancy` — a plain `bool` value comparison. It changes
    //     only when the master applies or clears a filter, but it changes
    //     WHICH entries exist (pass 1c), so leaving it out of this gate
    //     would serve a stale free-card list for exactly one rebuild after a
    //     filter change — and a rebuild whose `bookings` list is `identical`
    //     is genuinely reachable (a filter that returns the same rows).
    if (!identical(widget.bookings, oldWidget.bookings) ||
        widget.day != oldWidget.day ||
        widget.showsAllOccupancy != oldWidget.showsAllOccupancy ||
        !listEquals(widget.declaredTimes, oldWidget.declaredTimes)) {
      _entries = _mergeDeclaredAndBookings(
        widget.declaredTimes,
        widget.bookings,
        widget.day,
        showsAllOccupancy: widget.showsAllOccupancy,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      key: const Key('declared-time-cards'),
      padding: EdgeInsets.zero,
      itemCount: _entries.length,
      separatorBuilder: (BuildContext context, int index) =>
          const SizedBox(height: VelvetSpacing.md),
      itemBuilder: (BuildContext context, int index) {
        final _DeclaredEntry entry = _entries[index];
        final Booking? booking = entry.booking;
        if (booking == null) {
          return _FreeTimeCard(time: entry.time);
        }
        // The shipped card, VERBATIM — see this file's header. `minHeight:
        // _kEntryMinHeight` is the ONLY non-default constructor argument;
        // everything else (decoration, the full/compact/micro switch, the
        // status badge, the price pill, the client avatar mark) is
        // [MasterBookingCard]'s own, untouched. `RepaintBoundary` mirrors
        // `BookingsTimelineGrid`'s own MEDIUM-1 fix for the same card: its
        // press animation (`AnimatedScale` + `AnimatedContainer`) must not
        // dirty this whole scrolling list on a single tap.
        return RepaintBoundary(
          child: MasterBookingCard(
            key: ValueKey<String>('declared-master-booking-card-${booking.id}'),
            booking: booking,
            onTap: () => widget.onTapBooking(booking),
            minHeight: _kEntryMinHeight,
          ),
        );
      },
    );
  }
}

/// One FREE declared time — time / «Вільно», muted, informational only,
/// never a button. See [_kEntryMinHeight]'s doc for why this is floored at
/// the exact same height as a booked [MasterBookingCard] rather than at some
/// independently-tuned number, and [_freeCardMinHeightFor]'s doc for how that
/// floor tracks the booked card's growth above textScaler 1.0.
class _FreeTimeCard extends StatelessWidget {
  const _FreeTimeCard({required this.time});

  final TimeOfDay time;

  static const EdgeInsets _kPadding = EdgeInsets.all(VelvetSpacing.lg);

  /// Same fill, radius and border as [MasterBookingCard]'s own recipe (that
  /// card's `_decorationUnpressed` — base fill, `VelvetRadii.card`, a 1.5dp
  /// camel border at alpha 0.38) so the two variants read as siblings at
  /// rest, not just at the same height — minus the shadow, which is the one
  /// deliberate difference: the free card does not rise off the base.
  static final BoxDecoration _decoration = BoxDecoration(
    color: BrandColors.base,
    borderRadius: BorderRadius.circular(VelvetRadii.card),
    border: Border.all(
      color: BrandColors.accent.withValues(alpha: 0.38),
      width: 1.5,
    ),
  );

  /// The declared time. `VelvetText.masterFreeCardTime` — the sibling
  /// [MasterBookingCard]'s own FULL-layout client-name tier (Comfortaa
  /// 13.5/600), recoloured to mocha so the card's anchor still reads as
  /// structure. Was `VelvetText.statValue()` (Comfortaa 17/700) — a full
  /// size tier louder than anything else in this list; see
  /// `velvet_text.dart`'s "Phase 244 typography-scale fix" comment for why
  /// that read as out-of-scale against the booked card beside it.
  static final TextStyle _timeStyle = VelvetText.masterFreeCardTime;

  /// «Вільно», muted. `VelvetText.masterFreeCardLabel` — the sibling
  /// [MasterBookingCard]'s own FULL-layout secondary tier (Nunito 11/700,
  /// muted), verbatim. Was `VelvetText.subheading()` (Comfortaa 14/600) —
  /// same over-scale issue as [_timeStyle] above.
  static final TextStyle _freeStyle = VelvetText.masterFreeCardLabel;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return MergeSemantics(
      child: Semantics(
        key: Key(
          'declared-time-card-free-'
          '${time.hour.toString().padLeft(2, '0')}'
          '${time.minute.toString().padLeft(2, '0')}',
        ),
        label: '${formatTime(time)} — ${l10n.masterBookingsDeclaredTimeFree}',
        child: Container(
          constraints: BoxConstraints(
            minHeight: _freeCardMinHeightFor(context),
          ),
          padding: _kPadding,
          decoration: _decoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(formatTime(time), style: _timeStyle),
              const SizedBox(height: VelvetSpacing.sm),
              Text(l10n.masterBookingsDeclaredTimeFree, style: _freeStyle),
            ],
          ),
        ),
      ),
    );
  }
}
