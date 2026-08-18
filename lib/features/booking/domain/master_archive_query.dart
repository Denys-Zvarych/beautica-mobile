// Phase 231 — MasterArchiveQuery: the family key for
// `masterArchiveNotifierProvider` (the master «Архів» page).
//
// Mirrors `BookingsDayQuery.of`'s canonicalisation discipline verbatim (see
// that file's header for the full reasoning) — a `Set<BookingStatus>` /
// `Set<String>` is the natural shape for a multi-select filter, but a
// Riverpod family key must be built from CANONICAL, insertion-order-
// independent `List`s so two selections describing the SAME filter are
// always `==`-equal and hit the SAME cached provider instance. A raw `Set`
// would technically compare correctly too (freezed emits
// `DeepCollectionEquality` for it), but a fresh `{BookingStatus.confirmed,
// BookingStatus.completed}` literal built on one rebuild and
// `{BookingStatus.completed, BookingStatus.confirmed}` built on the next
// still `==`-equal as Sets — the real reason for `List` here is the SAME one
// `BookingsDayQuery` documents: keeping the emitted query-param order
// deterministic, not equality. See that file's header before "fixing" this
// to a bare `Set` field.
//
// Only `statuses` reflects the master's TICKED `BookingStatusFilterGroup`
// selection — the archive's own request-shaping (partition, the legacy
// status fallback, and the "select all collapses to no filter" resolution)
// lives in `master_archive_notifier.dart`, not here. This class is a pure
// canonicalised carrier, same division of labour as
// `BookingsDayQuery.masterOwn`/`.of` versus `.dayList`.
//
// Pure Dart: no Flutter imports.

import 'package:freezed_annotation/freezed_annotation.dart';

import 'booking_status.dart';

part 'master_archive_query.freezed.dart';

/// An immutable, canonically-normalised filter for the master «Архів» page.
/// Build with [MasterArchiveQuery.of].
@freezed
sealed class MasterArchiveQuery with _$MasterArchiveQuery {
  /// Pass-through freezed constructor. Assumes [statuses]/[serviceIds] are
  /// already canonically sorted — build through [MasterArchiveQuery.of]
  /// instead, which guarantees it.
  const factory MasterArchiveQuery.raw({
    required List<BookingStatus> statuses,
    required List<String> serviceIds,
  }) = _MasterArchiveQuery;

  const MasterArchiveQuery._();

  /// The normalising constructor — the only one callers should use.
  ///
  /// Takes `Set`s (the natural shape from `BookingsFilterSelection`) and
  /// canonicalises them into sorted, unmodifiable `List`s: [statuses] by enum
  /// declaration order, [serviceIds] lexicographically — exactly
  /// [BookingsDayQuery.of]'s discipline.
  factory MasterArchiveQuery.of({
    Set<BookingStatus> statuses = const <BookingStatus>{},
    Set<String> serviceIds = const <String>{},
  }) {
    final List<BookingStatus> sortedStatuses = statuses.toList(growable: false)
      ..sort((BookingStatus a, BookingStatus b) => a.index.compareTo(b.index));
    final List<String> sortedServiceIds = serviceIds.toList(growable: false)
      ..sort();

    return MasterArchiveQuery.raw(
      statuses: List<BookingStatus>.unmodifiable(sortedStatuses),
      serviceIds: List<String>.unmodifiable(sortedServiceIds),
    );
  }

  /// Whether any filter narrows the list — mirrors
  /// `BookingsFilterSelection.activeCount > 0`/`BookingsDayQuery.hasFilters`.
  bool get hasFilters => statuses.isNotEmpty || serviceIds.isNotEmpty;
}
