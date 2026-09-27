// Phase 7.9 — BookingsDayState: the WHOLE set of bookings for one Kyiv
// calendar day, for [bookingsDayProvider].
//
// Retires `MasterBookingsState` (Phase 7.1–7.8), whose `page`/`hasMore`/
// `isLoadingMore` paging fields have no equivalent here — a single request
// (`size: 100, page: 0`) is fetched unconditionally regardless of how many
// bookings the day actually holds; see `bookings_day_notifier.dart`'s "one
// day is NOT provably bounded" note. [isTruncated] is therefore a
// GENUINELY REACHABLE case, not a defensive one — it is what catches
// whatever that single request doesn't cover.
//
// ## Why not reuse `MyBookingsState` [carried from `MasterBookingsState`'s
// header — the reasoning still holds]
//
// The shipped client-side `MyBookingsState` (`application/my_bookings_notifier
// .dart`) is not reused for the same two reasons as before:
//
//   1. The master's toolbar renders a total count («N записів») straight from
//      the server's `totalElements`. `MyBookingsState` has no such field, and
//      widening a shipped, tested client type to serve a master-only need
//      would make one screen's state shape a hostage to the other's.
//   2. `MyBookingsState` is a hand-written `@immutable` class, not freezed —
//      extending it means hand-maintaining `==`/`hashCode`/`copyWith` for a
//      field the client never reads.
//
// [totalElements] survives for the same reason: with a fully-materialised day
// it equals `items.length`, but it is still read from the server so the
// rendered count and the rendered set can never disagree.

import 'package:freezed_annotation/freezed_annotation.dart';

import 'booking.dart';

part 'bookings_day_state.freezed.dart';

/// An immutable snapshot of ONE Kyiv calendar day's bookings — the whole set,
/// not a page of it.
@freezed
abstract class BookingsDayState with _$BookingsDayState {
  const factory BookingsDayState({
    /// Every booking on this day, in **server order** (`startsAt` ASC —
    /// see `bookings_day_notifier.dart`). Rendered directly — never re-sorted
    /// client-side; Phase 7.10's lane assignment depends on this order.
    required List<Booking> items,

    /// Total matching bookings for this day, as reported by the server. With
    /// a fully-materialised day this equals `items.length`, but it is read
    /// from the server rather than derived so the two can never disagree.
    required int totalElements,

    /// `true` when the server reports more results than were returned in
    /// this single request — the belt-and-braces case for the "one day fits
    /// in one page" bound (see `bookings_day_notifier.dart`). Phase 7.11
    /// renders an explicit "day too dense" notice off this flag rather than
    /// looping to page 1 (locked decision, 2026-07-18).
    @Default(false) bool isTruncated,
  }) = _BookingsDayState;

  const BookingsDayState._();

  /// `true` when the day has no bookings at all — the empty-state gate.
  bool get isEmpty => items.isEmpty;
}

/// Wraps [items] so that [BookingsDayState.items] returns a **stable
/// instance** on every access, rather than a freshly-allocated wrapper.
///
/// ## Why this exists — freezed's collection getter is not identity-stable
///
/// `BookingsDayState` is freezed, and freezed generates its list getter as
/// (`bookings_day_state.freezed.dart`):
///
/// ```dart
/// List<Booking> get items {
///   if (_items is EqualUnmodifiableListView) return _items;
///   return EqualUnmodifiableListView(_items);
/// }
/// ```
///
/// so whenever the STORED list is a plain `List` the getter allocates a
/// BRAND NEW wrapper on **every single access**. Two reads of `state.items`
/// then hand back two different objects over the same rows.
///
/// That was the shipped state of affairs, on every route: [PageResponse] is
/// hand-written, not freezed (`core/network/page_response.dart` says so and
/// why), so `page.items` is a plain `List<Booking>`, and every
/// `BookingsDayState` the notifier built stored one. It is NOT specific to
/// `BookingsDayNotifier._narrowSalonDay`'s `sublist` branch — that branch
/// merely produces another plain list, the same as the unnarrowed one.
///
/// Three shipped optimisations key off that identity and were therefore
/// **inert** — every one of them missed on every rebuild:
///
///   1. `_BookingsDiscoveryViewState._visibleBookingsFor`'s memo, which gates
///      on `identical(_cachedVisibleSource, items)`.
///   2. `BookingsTimelineGrid.didUpdateWidget`'s
///      `identical(widget.bookings, oldWidget.bookings)` gate — the one that
///      decides whether to re-run `assignLanes` (O(N log N)) plus the whole
///      per-card layout.
///   3. `bookingsInsideScheduleWindow`'s "return the input instance when
///      nothing was excluded" contract, whose entire point is to preserve (2)
///      — preserving the identity of a list that had no stable identity to
///      begin with bought nothing.
///
/// and `_Loaded.build`'s debug `assert(identical(visible, items))` fired on
/// wrapper identity instead of on the window it exists to police, red-screening
/// the salon board in every asserts-enabled build (mobile-qa HIGH, 2026-09-17).
///
/// Passing the result of this function to the constructor makes freezed's
/// `_items is EqualUnmodifiableListView` test hit, so the getter returns the
/// SAME instance forever after and all three gates work as documented.
///
/// **No behavioural change.** `BookingsDayState.items` already handed out an
/// unmodifiable view — this only stops it allocating a new one per read.
List<Booking> stableBookingList(List<Booking> items) =>
    items is EqualUnmodifiableListView<Booking>
    ? items
    : EqualUnmodifiableListView<Booking>(items);
