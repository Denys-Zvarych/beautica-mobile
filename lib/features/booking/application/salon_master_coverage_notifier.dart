// Phase 14.13 — per-service bookable-master coverage for the salon booking
// flow's master-assignment step. Rewired (Phase 23.x) onto the dedicated
// `GET /salons/{salonId}/services/{serviceDefId}/masters` endpoint.
//
// WHY THIS PROVIDER EXISTS
// -------------------------
// `SalonMasterSelectionScreen` must show only the masters who perform at
// least one of the client's selected services (Phase 14.12 output), and for
// each selected service resolve which of the picked masters can do it. Neither
// existing salon read carries that information:
//   • [publicSalonProfileProvider]'s masters rail ([SalonMasterSummary]) has
//     no service list at all.
//   • [salonServiceCatalogProvider]'s catalogue ([SalonCatalogService]) has no
//     master list either — a salon service can be assigned to several
//     masters (`master_services` join table, backend `MasterServiceAssignment`),
//     and the public catalogue DTO deliberately omits that ownership mapping
//     (it is a display-only read).
//
// REWIRE (Phase 23.x, bookable-masters endpoint) — this provider used to
// fan `GET /masters/{masterId}/services` out over the salon's FULL roster
// (up to `kSalonMastersPageSize`, 50, bounded-chunked at 8-concurrent) and
// derive coverage by intersecting each master's own service list against the
// client's selection. That had two problems the backend's new endpoint fixes
// at the source:
//   1. A master with an active assignment but NO usable weekly schedule
//      still showed up as "covers this service", so picking them opened a
//      calendar with every date disabled (the bug this rewire fixes).
//   2. The fan-out scaled with roster size (up to 50 calls), not with what
//      the client actually selected.
// `SalonRepository.getBookableMasters(salonId, serviceDefId)` is called
// ONCE PER SELECTED SERVICE instead: the backend already filters to masters
// who are active, actively assigned, AND schedule-usable, so a scheduleless
// master is simply absent from the response — it can never reach this map,
// and therefore can never be picked on this screen. No roster read is needed
// here anymore; `publicSalonProfileProvider` is still watched by the SCREEN
// (not this provider) purely for master display data (name/avatar/rating) —
// see `salon_master_selection_screen.dart`'s file header, "DATA — per-master
// service coverage gap".
//
// FAMILY KEY — composite (salonId, selectedServiceIds), reusing
// [SalonBookingMasterSelectionArgs] (the screen's own nav payload) as the key
// type rather than inventing a parallel query class: freezed already gives it
// value equality with `DeepCollectionEquality` on [selectedServiceIds]
// (verified against the generated `.freezed.dart`), so re-watching with the
// SAME args instance — the normal case, since the screen holds `widget.args`
// as a stable field — resolves to the same cached family member instead of
// re-fetching. Keying on [selectedServiceIds] (not just [salonId], as
// before) is required now: the coverage map itself depends on which services
// were selected, since each selected service is its own network call.
//
// GRACEFUL DEGRADATION (backlog line 122) — the old `Future.wait` over the
// roster fan-out was all-or-nothing: one master's failed request blanked the
// ENTIRE grid. Each selected service's call is now caught independently, so
// one failing service degrades to "no bookable masters for that service"
// (surfaces as an uncovered service on screen) rather than failing the whole
// provider.
//
// BOUNDED FAN-OUT (mobile-perf LOW fix, Phase 23.x audit) — selections are
// normally 1-3 services, but the catalogue multi-select doesn't cap how many
// a client can pick, so the per-service `Future.wait` is issued in bounded
// chunks of [_kFetchChunkSize] rather than firing every call at once — the
// same cap the pre-rewire roster fan-out used (see the REWIRE note above).
//
// Cache: [ref.keepAlive] + a 5-minute TTL (mobile-perf MEDIUM fix, Phase
// 14.13 audit) — mirrors [salonReviewSummaryProvider]'s identical pattern. A
// plain `autoDispose` refired the full fetch on every intermediate pop (e.g.
// client tweaks the service selection, then re-enters this step) within the
// same booking session; the TTL keeps that round trip cached without keeping
// it alive indefinitely.

import 'dart:async';
import 'dart:developer';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../salon/data/salon_repository.dart';
import '../../salon/domain/bookable_master_assignment.dart';
import '../domain/salon_booking_args.dart';

part 'salon_master_coverage_notifier.g.dart';

/// Max concurrent `GET /salons/{salonId}/services/{serviceDefId}/masters`
/// calls in flight at once — mirrors the pre-rewire roster fan-out's cap
/// (mobile-perf LOW fix, Phase 23.x audit).
const int _kFetchChunkSize = 8;

/// Maps each master id bookable for ≥1 of [args.selectedServiceIds] to a
/// `serviceDefId -> assignmentId` map of the services (from that selection)
/// they are bookable for: the key is the catalog id (comparable against
/// [SalonCatalogService.id]), the value is that master's OWN
/// `MasterServiceAssignment` id for the same service — the id the slot-
/// availability endpoint actually requires (see `salon_master_schedule.dart`'s
/// `orderedMasterServiceIds`). "Does master X cover service Y" is still a
/// simple `coverage[x]?.containsKey(y) ?? false` check.
///
/// Generated provider name: `salonMasterServiceCoverageProvider` — a family,
/// call it with the screen's [SalonBookingMasterSelectionArgs].
@riverpod
Future<Map<String, Map<String, String>>> salonMasterServiceCoverage(
  Ref ref,
  SalonBookingMasterSelectionArgs args,
) async {
  // 5-minute cache window — see the file header's "Cache" note. The timer is
  // cancelled on dispose so it can never fire after the provider is gone.
  final link = ref.keepAlive();
  final Timer timer = Timer(const Duration(minutes: 5), link.close);
  ref.onDispose(timer.cancel);

  final SalonRepository repo = ref.watch(salonRepositoryProvider);

  // One `getBookableMasters` call per selected service, issued in bounded-
  // size chunks of at most [_kFetchChunkSize] concurrent requests (mobile-
  // perf LOW fix — mirrors the pre-rewire roster fan-out's cap, see the file
  // header's REWIRE note). Selections are normally 1-3 services, but the
  // catalogue multi-select doesn't cap how many a client can pick, so an
  // unbounded `Future.wait` over the full selection would still be an
  // unbounded parallel fan-out in the worst case. Each call is wrapped in
  // its own try/catch so a single failing service degrades to "no bookable
  // masters for that service" instead of failing every other
  // already-resolved (or still in-flight) service's coverage too, and
  // results are assembled chunk-by-chunk so `perService[i]` stays aligned
  // with `args.selectedServiceIds[i]` regardless of chunking.
  final List<List<BookableMasterAssignment>> perService =
      <List<BookableMasterAssignment>>[];
  for (
    int start = 0;
    start < args.selectedServiceIds.length;
    start += _kFetchChunkSize
  ) {
    final int end = start + _kFetchChunkSize < args.selectedServiceIds.length
        ? start + _kFetchChunkSize
        : args.selectedServiceIds.length;
    final List<String> batch = args.selectedServiceIds.sublist(start, end);
    final List<List<BookableMasterAssignment>> batchResults = await Future.wait(
      batch.map((String serviceDefId) async {
        try {
          return await repo.getBookableMasters(
            salonId: args.salonId,
            serviceDefId: serviceDefId,
          );
        } on Failure catch (e, st) {
          // Debug-only, matching the rest of the feature (`booking_mapper`,
          // `appointment_repository`). Today's payload is a `Failure` plus a
          // catalogue `serviceDefId` — no PII — but the gate is what keeps it
          // that way once a release-mode crash reporter (Phase 8.1) starts
          // ingesting `log()` output.
          if (kDebugMode) {
            log(
              'getBookableMasters($serviceDefId) failed — treating as no '
              'bookable masters for this service',
              name: 'booking.salonMasterCoverage',
              level: 900,
              error: e,
              stackTrace: st,
            );
          }
          return const <BookableMasterAssignment>[];
        }
      }),
    );
    perService.addAll(batchResults);
  }

  final Map<String, Map<String, String>> coverage =
      <String, Map<String, String>>{};
  for (int i = 0; i < args.selectedServiceIds.length; i++) {
    final String serviceDefId = args.selectedServiceIds[i];
    for (final BookableMasterAssignment row in perService[i]) {
      coverage.putIfAbsent(
        row.masterId,
        () => <String, String>{},
      )[serviceDefId] = row.masterServiceId;
    }
  }
  return coverage;
}
