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
    required String? salonId,

    /// Phase 382 (24.1e) — see [MasterArchiveQuery.of]'s `asOwnerMaster`.
    @Default(false) bool asOwnerMaster,
  }) = _MasterArchiveQuery;

  const MasterArchiveQuery._();

  /// The normalising constructor — the only one callers should use.
  ///
  /// Takes `Set`s (the natural shape from `BookingsFilterSelection`) and
  /// canonicalises them into sorted, unmodifiable `List`s: [statuses] by enum
  /// declaration order, [serviceIds] lexicographically — exactly
  /// [BookingsDayQuery.of]'s discipline.
  ///
  /// [salonId] is the phase-342 SCOPE selector: `null` (the default) means
  /// "mine" — `GET /bookings/me`, byte-identically to every pre-342 caller —
  /// and a non-null id means "this salon's whole history, across every
  /// master" (`GET /bookings/salon/{salonId}`). It is a scalar, so it needs
  /// no canonicalisation. It lives HERE, on the family key, rather than on
  /// the notifier or the screen, precisely because `masterArchiveProvider` is
  /// an **autoDispose family keyed by this class**: two scopes that compared
  /// `==` would share ONE cache entry, so an owner who opened the salon
  /// archive and then their own staff archive would be served the wrong
  /// list, and freezed's `DeepCollectionEquality` would have no field left to
  /// tell them apart. Putting it in the key is what makes the two scopes
  /// independently cached and independently disposed.
  ///
  /// ## Rejects the one combination that cannot be honoured: a salon scope
  /// carrying [serviceIds]
  ///
  /// `GET /bookings/salon/{salonId}` surfaces no service predicate
  /// (`booking_repository.dart`'s `getSalonBookings` doc — deliberately not
  /// surfaced, YAGNI), and the salon host switches the service facet off
  /// (phase 343 D3: an owner has no master service catalogue of their own,
  /// which is why the salon BOARD already passes `showServiceFilter: false`).
  /// So a salon-scoped query carrying service ids describes a filter that
  /// CANNOT reach the wire.
  ///
  /// This is enforced HERE, at construction, rather than in
  /// `MasterArchiveNotifier._fetchPage` where it began life as an `assert`
  /// (audit-fix MEDIUM-2, 2026-09-19). An `assert` is STRIPPED in profile and
  /// release: shipped, the salon arm would silently drop the ids while
  /// [hasFilters] below still reported `true`, so «Скинути» would be offered
  /// for a filter that narrowed nothing. Fail-closed at the type boundary
  /// instead — the invalid state becomes unrepresentable, and unlike an
  /// `assert` it is testable in every build mode (`flutter test --release`
  /// does not exist and the test VM always runs with asserts enabled, so the
  /// assert form was structurally unpinnable).
  ///
  /// [asOwnerMaster] (phase 382 / 24.1e) asks the `salonId == null` arm for
  /// the caller's OWN master-row history as a `SALON_OWNER`
  /// (`GET /bookings/me?asMaster=true`, backend phase 354). Like [salonId]
  /// it lives on the family key so the owner's own archive never shares a
  /// cache entry with any other scope; `false` (the default) sends no
  /// `asMaster` param, byte-identically to every pre-382 caller. Rejected
  /// together with a non-null [salonId] — the salon endpoint has no such
  /// param, so the combination cannot reach the wire.
  ///
  /// [MasterArchiveQuery.raw] is deliberately NOT guarded — it is the freezed
  /// pass-through documented above as "build through [MasterArchiveQuery.of]
  /// instead", and every caller in `lib/` does.
  factory MasterArchiveQuery.of({
    Set<BookingStatus> statuses = const <BookingStatus>{},
    Set<String> serviceIds = const <String>{},
    String? salonId,
    bool asOwnerMaster = false,
  }) {
    if (salonId != null && asOwnerMaster) {
      throw ArgumentError.value(
        asOwnerMaster,
        'asOwnerMaster',
        'A salon-scoped MasterArchiveQuery cannot ask for the owner\'s own '
            'master-row history — GET /bookings/salon/{salonId} has no '
            'asMaster param. Use salonId: null for the own-bookings scope.',
      );
    }
    if (salonId != null && serviceIds.isNotEmpty) {
      throw ArgumentError.value(
        serviceIds,
        'serviceIds',
        'A salon-scoped MasterArchiveQuery must carry no serviceIds — '
            'GET /bookings/salon/{salonId} has no service predicate and the '
            'salon host switches the service facet off (phase 343 D3). '
            'Forwarding them is not expressible, and dropping them silently '
            'would leave hasFilters reporting a filter that narrows nothing. '
            'If a salon service filter is ever wanted, wire it explicitly.',
      );
    }

    final List<BookingStatus> sortedStatuses = statuses.toList(growable: false)
      ..sort((BookingStatus a, BookingStatus b) => a.index.compareTo(b.index));
    final List<String> sortedServiceIds = serviceIds.toList(growable: false)
      ..sort();

    return MasterArchiveQuery.raw(
      statuses: List<BookingStatus>.unmodifiable(sortedStatuses),
      serviceIds: List<String>.unmodifiable(sortedServiceIds),
      salonId: salonId,
      asOwnerMaster: asOwnerMaster,
    );
  }

  /// Whether any filter narrows the list — mirrors
  /// `BookingsFilterSelection.activeCount > 0`/`BookingsDayQuery.hasFilters`.
  ///
  /// [salonId] is deliberately NOT counted: it selects WHICH history is being
  /// read, not how that history is narrowed, so a salon archive with nothing
  /// ticked must still read as unfiltered (the «Скинути» affordance and the
  /// empty-state copy both key off this).
  bool get hasFilters => statuses.isNotEmpty || serviceIds.isNotEmpty;
}
