// Phase — SALON_MASTER own-profile loader.
//
// Fixes the "blank home" landing bug: a SALON_MASTER previously fell through
// `roleHomePath`'s wildcard onto the bare `_Placeholder('home')` (see
// `routing/role_home.dart`). This loader resolves everything
// `SalonMasterProfileScreen` renders in ONE [AsyncValue]: the master's own
// identity/stats/bio/contacts, paired with their active services (for the
// stats-row services count and the read-only «Мої категорії» section) AND
// their employing salon (for the read-only salon-name + salon-address rows
// on the identity card — user requirement, 2026-09-01: "location for salon
// master should [be the] salon location", "in salon master we need somewhere
// to show the salon name").
//
// ── REUSE ─────────────────────────────────────────────────────────────────
// Nothing here fetches anything new — all three reads are ALREADY-SHIPPED:
//   1. `masterProfileProvider` — the keepAlive `GET /masters/me` read.
//      `MasterController.java:110`'s `@PreAuthorize` already admits
//      SALON_MASTER (confirmed against the backend contract — no backend
//      change needed or permitted for this phase).
//   2. `publicServiceRepositoryProvider.getMasterServices(masterId)` — the
//      PUBLIC `GET /masters/{masterId}/services`. The same call
//      `salon_staff_member_notifier.dart`, `public_master_profile_notifier
//      .dart` AND `owner_own_profile_notifier.dart` already make.
//   3. `salonRepositoryProvider.getSalonById(salonId)` — the PUBLIC (`permitAll`)
//      `GET /salons/{salonId}` read, already shipped for the client-facing
//      public salon profile (Phase 13.6). Deliberately NOT
//      `getSalonStaff`/`GET /salons/{salonId}/staff` — that endpoint is
//      owner/admin-management-scoped and 403s for a SALON_MASTER caller
//      (`SalonRepository.getSalonStaff`'s own doc: "Requires management
//      access to the salon").
//
// A NARROWER ALTERNATIVE WAS CONSIDERED AND REJECTED. The backend's
// `MasterDetailResponse` (`/masters/me`'s own DTO) already embeds a nested
// `PublicSalonResponse salon` — `MasterMapper.fromDto` today reads only
// `dto.salon?.id` off it and discards the rest, so in principle the name +
// address this phase needs are already sitting in the SAME response
// `masterProfileProvider` fetches above, at zero extra round trips. That
// path was rejected here: reusing it without duplicating
// `SalonMapper.fromDto`'s mapping logic would require `master/data/`
// (`MasterMapper`) to import `salon/data/` (`SalonMapper`), which this
// codebase's layering rule forbids (`data/` may import only its OWN
// feature's `domain/`) — and duplicating that mapping is the exact drift
// REUSE-FIRST exists to prevent. A dedicated `GET /salons/{salonId}` read
// from THIS file (`master/application/`, which — like
// `owner_own_profile_notifier.dart` importing `services/data/` — is not
// bound by the strict data-layer import table) reuses
// `SalonRepository.getSalonById` and `SalonMapper.fromDto` exactly as they
// already exist, at the cost of one extra request that fully overlaps the
// services read below. Flagged here rather than silently taken, per this
// phase's brief.
//
// ── WHY NOT `servicesListProvider` ────────────────────────────────────────
// `owner_own_profile_notifier.dart`'s header explains this exact trap:
// `servicesListProvider` → `ServiceRepository.listMyServices()` →
// `GET /independent-masters/me/services`, which is
// `@PreAuthorize("hasRole('INDEPENDENT_MASTER')")` (`ServiceController.java`)
// — a SALON_MASTER gets 403, always. The master-row-keyed PUBLIC endpoint
// (keyed on `Master.id`, which only `/masters/me` supplies) is the only one
// this role may call — the same reason `owner_own_profile_notifier.dart`
// reaches for it instead of the obvious-looking `servicesListProvider` reuse.
//
// ── TWO INDEPENDENT OPTIONAL READS, STARTED TOGETHER ────────────────────
// The services read (keyed on `Master.id`) and the salon read (keyed on
// `Master.salonId`) share no dependency on each other, only on `master`
// above — so both futures are started here, before either is awaited, the
// same "every ref.watch/ref.read happens before the first await, only the
// FUTURES are awaited later" shape `owner_own_profile_notifier.dart` uses for
// its own two-independent-reads case. Each folds its own failure to an
// ABSENT result via `.then(onError: ...)` at CREATION time (so an unawaited
// rejected Future is never left as an unhandled zone error) rather than
// erroring the whole profile — the identity/stats/bio/contacts sections stay
// fully usable if either the catalogue or the salon endpoint is unreachable.
// A SALON_MASTER with no `salonId` (should not happen in practice, but the
// field is nullable on [Master]) skips the salon network call entirely
// rather than calling with a null id.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/data/salon_repository.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';

part 'salon_master_own_profile_notifier.g.dart';

/// The data [SalonMasterProfileScreen] renders: the signed-in SALON_MASTER's
/// own master row, their active services, and their employing salon.
///
/// [salon] is `null` when the master carries no `salonId`, or when the salon
/// read failed — both degrade to the identity card simply omitting the
/// salon-name/salon-address rows, never a crash or a `—` placeholder.
typedef SalonMasterOwnProfileData = (
  Master master,
  List<MasterService> services,
  Salon? salon,
);

/// Loads the authenticated SALON_MASTER's own profile + active services +
/// employing salon.
///
/// Generated provider name: `salonMasterOwnProfileProvider`.
@riverpod
Future<SalonMasterOwnProfileData> salonMasterOwnProfile(Ref ref) async {
  final Master master = await ref.watch(masterProfileProvider.future);

  // WARM-START, not a read (mobile-perf LOW, 2026-09-01) — mirrors
  // `owner_own_profile_notifier.dart:161`'s identical fix. The category
  // cards resolve their human labels from `approvedCategoriesProvider`,
  // which `ServiceCategoryCardList` first touches from its own `build()` —
  // a hop that otherwise only STARTS after the loaded body's first paint,
  // so «Мої категорії» visibly swaps from `humanizeCategorySlug` fallback
  // labels to the real names and relayouts under the user. Kicking it off
  // here overlaps it with the services + salon reads below instead.
  //
  // Unlike the owner sibling, this notifier has no `hasMasterProfile ==
  // false` early-return arm to guard against wasting the warm-start on a
  // section that will never render — `masterProfileProvider` having already
  // resolved above IS this notifier's proof a services section exists to
  // label, so the warm-start is unconditional here.
  //
  // `ref.read`, not `ref.watch`: this provider is `keepAlive`, so a read is
  // enough to start AND retain the fetch, and no dependency edge is
  // created — its later resolution must rebuild the CARDS (which watch it
  // themselves), never this loader. `.ignore()` because the value is
  // consumed there, not here, and a failure must degrade to slug labels
  // rather than error the tab.
  ref.read(approvedCategoriesProvider.future).ignore();

  // Started together, BEFORE either is awaited — see the file header's
  // "TWO INDEPENDENT OPTIONAL READS" note. A failed services read degrades
  // to "no services"; a failed (or absent) salon read degrades to "no
  // salon" — neither errors the whole profile.
  final Future<List<MasterService>> servicesFuture = ref
      .read(publicServiceRepositoryProvider)
      .getMasterServices(master.id)
      .then<List<MasterService>>(
        (List<MasterService> services) => services,
        onError: (Object _, StackTrace _) => const <MasterService>[],
      );

  final String? salonId = master.salonId;
  final Future<Salon?> salonFuture = salonId == null
      ? Future<Salon?>.value()
      : ref
            .read(salonRepositoryProvider)
            .getSalonById(salonId)
            .then<Salon?>(
              (Salon salon) => salon,
              onError: (Object _, StackTrace _) => null,
            );

  return (master, await servicesFuture, await salonFuture);
}
