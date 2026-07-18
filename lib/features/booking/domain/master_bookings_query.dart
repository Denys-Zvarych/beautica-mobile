// Phase 7.1 — MasterBookingsQuery: the family key for [masterBookingsProvider].
//
// One value object carrying every server-side filter the independent master's
// «Мої записи» screen can express. Changing any filter builds a NEW query → a
// NEW family member → a fresh page 0.
//
// ## No `sort` field (Phase 7.8)
//
// It used to carry one. Sorting was retired as a user-facing feature, so there
// is nothing left to vary: `MasterBookingsNotifier` sends a fixed
// `BookingSort.newest`. Keeping the field would have kept the family key wider
// than the set of states the UI can actually reach.
//
// ## Why `List`, not `Set`
//
// The obvious shape for `statuses`/`serviceIds` is a `Set`, and freezed's
// generated `==` would handle it correctly (it emits `DeepCollectionEquality`,
// which compares sets by membership). Equality is not the problem —
// **iteration order** is. A `Set`'s order is insertion-dependent, so
// `{confirmed, completed}` and `{completed, confirmed}` are `==`-equal yet
// serialise to two DIFFERENT query strings:
//
//   ?status=CONFIRMED&status=COMPLETED
//   ?status=COMPLETED&status=CONFIRMED
//
// Both are accepted by the backend, so nothing breaks on the wire.
//
// What breaks is this class's ONE JOB. A freezed `List` field compares
// order-sensitively, so `[confirmed, completed]` and `[completed, confirmed]`
// are two DIFFERENT values — and therefore two different family keys, two
// members, two fetches, two cached pages, for one user-visible filter. Sorting
// in [MasterBookingsQuery.of] is what collapses them to one. That is the
// reason the sort exists; it is not a wire-format concern.
//
// (The emitted URL is canonicalised separately, at the serialisation boundary
// in `BookingRepository.getMyBookings` — it has to be, because
// `MyBookingsNotifier` reaches that boundary without passing through this
// class at all. Both sorts now order by enum `index` so the two agree and the
// repository's is idempotent on a query built here. Perf P5 read the two as
// duplicates of each other; they guard different invariants.)
//
// ## The real family-leak vector: an un-normalised `DateTime`
//
// `Set` ordering is a test-quality problem. The genuine bug is `from`/`to`:
// these are *dates*, but a `DateTime` is an *instant*. A date picker that
// hands back `DateTime.now()`-derived values makes two taps on the same
// calendar day at 09:14 and 09:15 two DIFFERENT keys — two family members,
// two network fetches, two cached pages, for one user-visible filter. The
// [MasterBookingsQuery.of] factory truncates both bounds to local midnight
// ([dateOnly]) so that collapses to one member.
//
// This is why the raw freezed constructor is not the intended entry point:
// [MasterBookingsQuery.of] is the ONLY normalising path, and every caller —
// including tests — should go through it.

import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:beautica_mobile/shared/formatters/api_date.dart';

import 'booking_status.dart';

part 'master_bookings_query.freezed.dart';

/// An immutable, canonically-normalised filter for the master's booking list.
/// Build with [MasterBookingsQuery.of].
@freezed
abstract class MasterBookingsQuery with _$MasterBookingsQuery {
  /// Pass-through freezed constructor. Assumes [statuses]/[serviceIds] are
  /// already canonically sorted and [from]/[to] already date-only — build
  /// through [MasterBookingsQuery.of] instead, which guarantees both.
  ///
  /// Not underscore-prefixed for the same reason as `WorkingDaysQuery.raw`:
  /// freezed derives its `map`/`when` parameter names from the factory name
  /// and a leading underscore is illegal there.
  const factory MasterBookingsQuery.raw({
    required List<BookingStatus> statuses,
    required List<String> serviceIds,
    DateTime? from,
    DateTime? to,
  }) = _MasterBookingsQuery;

  const MasterBookingsQuery._();

  /// The normalising constructor — the only one callers should use.
  ///
  /// Takes `Set`s (the natural shape for a multi-select filter, and what the
  /// filter sheet holds) and canonicalises them into sorted, unmodifiable
  /// `List`s: [statuses] by enum declaration order, [serviceIds]
  /// lexicographically. Truncates [from]/[to] to local midnight. The result
  /// is that two independently-built queries describing the same filter are
  /// always `==`-equal and always serialise to the same URL — see the file
  /// header for why each half of that matters.
  factory MasterBookingsQuery.of({
    Set<BookingStatus> statuses = const <BookingStatus>{},
    Set<String> serviceIds = const <String>{},
    DateTime? from,
    DateTime? to,
  }) {
    final List<BookingStatus> sortedStatuses = statuses.toList(growable: false)
      ..sort((BookingStatus a, BookingStatus b) => a.index.compareTo(b.index));
    final List<String> sortedServiceIds = serviceIds.toList(growable: false)
      ..sort();

    return MasterBookingsQuery.raw(
      statuses: List<BookingStatus>.unmodifiable(sortedStatuses),
      serviceIds: List<String>.unmodifiable(sortedServiceIds),
      from: from == null ? null : dateOnly(from),
      to: to == null ? null : dateOnly(to),
    );
  }

  /// Whether any filter narrows the list — drives the toolbar's "filters
  /// active" affordance and the empty state's copy.
  bool get hasFilters =>
      statuses.isNotEmpty ||
      serviceIds.isNotEmpty ||
      from != null ||
      to != null;
}
