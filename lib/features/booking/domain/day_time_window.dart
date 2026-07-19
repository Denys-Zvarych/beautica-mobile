// Phase 7.12 — DayTimeWindow: the optional client-side "time-of-day window"
// that narrows the master's «Мої записи» timeline to an hour range within the
// ONE selected Kyiv day (e.g. 09:00–14:00). See
// `docs/mobile-phases/phase-212-7.12-day-time-window.md` and
// `bookings_discovery_view.dart`'s Step 3 wiring for the full picture.
//
// ## It is VIEW STATE — never part of `BookingsDayQuery`
//
// The backend cannot express an intra-day filter (`GET /bookings/me`'s
// `from`/`to` are `LocalDate`s, whole-day only — see the phase doc's "It is
// client-side, and it has to be" section). Phase 7.9 already fetches the
// WHOLE selected day in one request, so every booking a window could ever
// select is already in memory: this class is a pure, client-side predicate
// over that already-fetched set, held as `BookingsDiscoveryView`'s own state
// (`_window`), never folded into `BookingsDayQuery`. Doing the latter would
// mint a new `bookingsDayProvider` family member — and therefore a brand-new
// network fetch of BYTE-IDENTICAL data — for every window edit, exactly the
// family-leak class `scripts/forbid_raw_bookings_query.sh` exists to catch on
// the query side. See `bookings_discovery_view.dart` for the corollary this
// forces on `hasFilters`.
//
// ## Minutes-from-day-start, never `TimeOfDay`
//
// [startMinute]/[endMinute] measure minutes since the SELECTED Kyiv day's
// midnight — exactly the anchor `BookingsTimelineGrid`'s R1 fix already uses
// for its own extent math (see that file's header). `TimeOfDay` wraps at
// 24:00 by construction and cannot represent "past midnight", the same
// reason R1 abandoned scalar hours for the grid's extent. A window built from
// `TimeOfDay` values could never compose with the grid's
// `windowStartMinute`/`windowEndMinute` overrides without an unwrap-then-
// rewrap step at every call site — this class IS that shared currency.
//
// ## Start-inside is the membership rule — NOT full containment
//
// [contains] only requires the booking's START to fall inside
// `[startMinute, endMinute)`. A 13:30 booking that runs past a 14:00 window
// edge still counts as "in the window": the user asked what is happening
// during that period, not what fits entirely within it. **Do not "fix" this
// into a full-containment check** — that reading was considered and
// explicitly rejected (phase 7.12 doc, Step 1); it would silently drop
// exactly the bookings straddling the window's own edges, which are usually
// the most relevant ones (the booking that is IN PROGRESS at the boundary
// the user picked).
//
// ## Why a plain hand-rolled class, not `@freezed`
//
// Every other domain value in this feature (`Booking`, `BookingsDayQuery`,
// `BookingsDayState`) is `@freezed`. This one deliberately is not:
// [DayTimeWindow.new] must reject `endMinute <= startMinute` with a thrown
// `ArgumentError` right at CONSTRUCTION time (the picker sheet — Step 2 —
// guards this in the UI so the throw is never actually hit from a live
// screen), and freezed's generated factory constructors cannot carry that
// kind of validating body without a second, PUBLICLY-named pass-through
// constructor (the same constraint `BookingsDayQuery.masterOwn` documents —
// a leading underscore is illegal on a freezed factory). For a two-`int`
// value object that lives purely as in-memory view state — never
// serialised, never sent over the wire, never part of a Riverpod family key
// — that ceremony buys nothing. A hand-rolled `==`/`hashCode` pair is the
// standard Dart shape for exactly that situation. (Correction: an earlier
// draft of this note cited `BookingsFilterSelection`
// [`bookings_filter_sheet.dart`] as a precedent for this pattern — checked
// during the Phase 7.12 QA audit and that class carries NO `==`/`hashCode`
// override at all, so it is not actually an example of anything here; the
// claim has been removed rather than left to mislead a future reader.)
//
// Pure Dart — no `package:flutter/material.dart` import — so this unit-tests
// without a widget pump. [contains] does reach into `shared/time/
// time_zones.dart` for [toBeauticaTime]; that file's only Flutter dependency
// is `package:flutter/foundation.dart`, for a `kReleaseMode`/
// `visibleForTesting` TEST-ONLY guard — not the widget tree — so importing it
// does not pull this file into the presentation layer or require a pump to
// exercise.

import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:timezone/timezone.dart' as tz;

import 'booking.dart';

/// An optional, client-side, intra-day time-of-day window over the master's
/// «Мої записи» timeline. Immutable view state only — see the file header
/// for why this must never reach `BookingsDayQuery` or any provider family
/// key.
class DayTimeWindow {
  /// Throws [ArgumentError] if [endMinute] does not exceed [startMinute].
  /// UI callers (the picker sheet) must guard this invariant themselves —
  /// disabling «Застосувати» — rather than relying on this throw as a UI
  /// mechanism; see the file header.
  DayTimeWindow({required this.startMinute, required this.endMinute}) {
    if (endMinute <= startMinute) {
      throw ArgumentError(
        'DayTimeWindow: endMinute ($endMinute) must be greater than '
        'startMinute ($startMinute).',
      );
    }
  }

  /// Minutes since the selected Kyiv day's midnight — inclusive lower bound.
  final int startMinute;

  /// Minutes since the selected Kyiv day's midnight — EXCLUSIVE upper bound.
  final int endMinute;

  /// Whether [booking]'s Kyiv start falls inside `[startMinute, endMinute)`
  /// on the given [day] — see the file header for why this is start-inside,
  /// deliberately NOT full containment.
  bool contains(Booking booking, DateTime day) {
    final int start = _minutesSinceDayStart(booking.startAt, day);
    return start >= startMinute && start < endMinute;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DayTimeWindow &&
          other.startMinute == startMinute &&
          other.endMinute == endMinute);

  @override
  int get hashCode => Object.hash(startMinute, endMinute);

  @override
  String toString() =>
      'DayTimeWindow(startMinute: $startMinute, endMinute: $endMinute)';
}

/// Minutes between [day]'s Kyiv midnight and [instant]'s Kyiv wall-clock.
///
/// Deliberately duplicated from `bookings_timeline_grid.dart`'s identically-
/// named private helper rather than shared across the domain/presentation
/// boundary — a presentation-layer file must never be imported from
/// `domain/` (see `ARCHITECTURE-mobile.md`'s layer table).
int _minutesSinceDayStart(DateTime instant, DateTime day) {
  final tz.TZDateTime local = toBeauticaTime(instant);
  final tz.TZDateTime midnight = tz.TZDateTime(
    beauticaZone,
    day.year,
    day.month,
    day.day,
  );
  return local.difference(midnight).inMinutes;
}
