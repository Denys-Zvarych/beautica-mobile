// Phase 14.13 — per-master service coverage for the salon booking flow's
// master-assignment step.
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
// The backend DOES expose the missing edge on the master side: the already-
// wired, CLIENT-safe `GET /masters/{masterId}/services`
// ([ServiceRepository.getMasterServices], via [publicServiceRepositoryProvider]
// — the exact same call [publicMasterProfileProvider] already makes for the
// Phase 13.5 public master profile). This provider fans that call out over
// every master in the salon's roster (small N — a salon's masters rail, not
// an unbounded list) and reduces each master's returned [MasterService] list
// to a `serviceDefId -> assignmentId` map, which is directly comparable
// (via its keys) against [SalonCatalogService.id] / the `selectedServiceIds`
// carried in [SalonBookingMasterSelectionArgs] — AND (via its values) carries
// forward each service's own `MasterServiceResponse.id`, the per-master
// assignment id the slot-availability endpoint actually requires (see
// `salon_master_schedule.dart`'s `primaryServiceAssignmentId` field —
// resolving that id was the whole reason this map keeps the assignment id
// instead of collapsing to a bare `Set<String>` of covered service ids, which
// is all a pre-fix version of this file computed).
//
// No new repository method was added — both reads are calls the codebase
// already makes elsewhere ([publicSalonProfileProvider] for the roster,
// [ServiceRepository.getMasterServices] for coverage); this provider only
// adds the fan-out + reduction gluing them together.
//
// Keyed on [salonId] (a plain `String`, not the master id list) so the family
// cache key stays trivially `==`-stable across rebuilds — a `List<String>`
// key would use identity equality by default and re-fetch on every rebuild
// that constructs a fresh list literal. The master id list is instead
// re-derived internally by watching [publicSalonProfileProvider], which is
// itself `keepAlive` + TTL-cached, so this costs no extra network round trip.
//
// BOUNDED FAN-OUT (mobile-perf HIGH-1 fix, Phase 14.13 audit) — the roster
// can hold up to `kSalonMastersPageSize` (50, see `salon_repository.dart`)
// masters. Firing one `GET /masters/{id}/services` call per master
// unconditionally in a single `Future.wait` is an unbounded parallel
// fan-out. Requests are now issued in bounded-size chunks so at most
// [_kFetchChunkSize] are ever in flight at once.
//
// Cache: [ref.keepAlive] + a 5-minute TTL (mobile-perf MEDIUM fix, same
// audit) — mirrors [salonReviewSummaryProvider]'s identical pattern. A plain
// `autoDispose` refired the FULL bounded fan-out on every intermediate pop
// (e.g. client tweaks the service selection, then re-enters this step)
// within the same booking session; the TTL keeps that round trip cached
// without keeping it alive indefinitely.

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../salon/application/public_salon_profile_notifier.dart';
import '../../salon/domain/salon_master_summary.dart';
import '../../services/data/service_repository.dart';
import '../../services/domain/master_service.dart';

part 'salon_master_coverage_notifier.g.dart';

/// Max concurrent `GET /masters/{id}/services` calls in flight at once.
const int _kFetchChunkSize = 8;

/// Maps each of [salonId]'s master ids to a `serviceDefId -> assignmentId`
/// map of the services they currently perform: the key is the catalog id
/// (comparable against [SalonCatalogService.id]), the value is that master's
/// OWN `MasterServiceResponse.id` for the same service — the id the slot-
/// availability endpoint actually requires (see `salon_master_schedule.dart`'s
/// `primaryServiceAssignmentId`). "Does master X cover service Y" is still a
/// simple `coverage[x]?.containsKey(y) ?? false` check.
///
/// Generated provider name: `salonMasterServiceCoverageProvider` — a family,
/// call it with the target salon id.
@riverpod
Future<Map<String, Map<String, String>>> salonMasterServiceCoverage(
  Ref ref,
  String salonId,
) async {
  // 5-minute cache window — see the file header's "Cache" note. The timer is
  // cancelled on dispose so it can never fire after the provider is gone.
  final link = ref.keepAlive();
  final Timer timer = Timer(const Duration(minutes: 5), link.close);
  ref.onDispose(timer.cancel);

  final (_, List<SalonMasterSummary> masters) = await ref.watch(
    publicSalonProfileProvider(salonId).future,
  );
  final ServiceRepository repo = ref.watch(publicServiceRepositoryProvider);

  final Map<String, Map<String, String>> coverage =
      <String, Map<String, String>>{};
  for (int start = 0; start < masters.length; start += _kFetchChunkSize) {
    final int end = start + _kFetchChunkSize < masters.length
        ? start + _kFetchChunkSize
        : masters.length;
    final List<SalonMasterSummary> batch = masters.sublist(start, end);
    final List<List<MasterService>> results = await Future.wait(
      batch.map((SalonMasterSummary m) => repo.getMasterServices(m.masterId)),
    );
    for (int i = 0; i < batch.length; i++) {
      coverage[batch[i].masterId] = <String, String>{
        for (final MasterService s in results[i]) s.serviceDefId: s.id,
      };
    }
  }
  return coverage;
}
