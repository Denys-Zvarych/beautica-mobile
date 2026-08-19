// Phase 250 — salon master roster for the SALON «Новий запис» wizard's
// `masters` step (STAFF caller: SALON_OWNER / SALON_ADMIN).
//
// ## Why not [publicSalonProfileProvider]
//
// `publicSalonProfileProvider` (`features/salon/application/
// public_salon_profile_notifier.dart`) already fans out
// `SalonRepository.getSalonById` + `SalonRepository.getSalonMasters` in
// parallel and would technically answer "what is this salon's roster" too —
// both `SalonRepository` methods it calls are unauthenticated-safe reads, so
// nothing stops a staff caller from using it. It is the wrong SOURCE anyway,
// for two independent reasons:
//   1. Over-fetch. This wizard's masters step needs ONLY the roster
//      (name/avatar/rating/type) to pick a master and key the coverage/slot
//      queries. `publicSalonProfileProvider` additionally fetches the FULL
//      public salon detail (`Salon` — description, address, hero image,
//      working-hours summary) on every mount, none of which this screen
//      renders. That is a second, wasted network round trip on a screen a
//      staff member opens repeatedly through a shift.
//   2. Wrong semantic. `publicSalonProfileProvider` is the CLIENT-facing
//      public salon profile screen's own data source — its 5-minute
//      `keepAlive` TTL window and cache-eviction-on-auth-change (`ref.watch
//      (authProvider)`, closing it on logout/login) are tuned for that
//      screen's browsing lifecycle, not a staff wizard's. Reusing it here
//      would tie this wizard's cache behaviour to an unrelated screen's
//      requirements by coincidence, not by design.
//
// So this is a NEW, deliberately thin provider — but it reuses the EXISTING
// [SalonRepository.getSalonMasters] method verbatim (no new endpoint, no new
// repository code): the same wire call `publicSalonProfileProvider` makes,
// wrapped on its own so the masters step can watch/invalidate it
// independently of the (irrelevant, here) salon detail fetch.
//
// Cache: `keepAlive` + a 5-minute TTL, mirroring
// [salonServiceCatalogProvider]'s identical pattern — a masters-step visit
// that goes back to `dateTime` (to change the date) and returns should not
// re-fetch the roster every time.

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../salon/data/salon_repository.dart';
import '../../salon/domain/salon_master_summary.dart';

part 'salon_masters_roster_notifier.g.dart';

/// Loads [salonId]'s active-master roster for the salon booking wizard's
/// `masters` step.
///
/// Generated provider name: `salonMastersRosterProvider` — a family, call it
/// with the target salon id.
@riverpod
Future<List<SalonMasterSummary>> salonMastersRoster(
  Ref ref,
  String salonId,
) async {
  final link = ref.keepAlive();
  final Timer timer = Timer(const Duration(minutes: 5), link.close);
  ref.onDispose(timer.cancel);

  return ref.watch(salonRepositoryProvider).getSalonMasters(salonId);
}
