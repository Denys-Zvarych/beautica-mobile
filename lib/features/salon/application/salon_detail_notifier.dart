// Single-salon detail loader — `GET /salons/{salonId}` and NOTHING else.
//
// ── WHY THIS EXISTS (mobile-perf + mobile-security LOW, 2026-09-05) ────────
// [AdminOwnProfileScreen]'s «Салон» affiliation card needs exactly one thing:
// the [Salon] it is affiliated with. Inside `SalonShellScreen` it gets that
// for free by watching `salonManagementProfileProvider(salonId)`, which slot 0
// has already warmed — zero requests, and an in-shell salon edit updates both
// surfaces at once. On the STAND-ALONE `/profile/admin` route there is no
// shell and therefore nothing warm, so that same watch cold-started the
// management family and issued TWO parallel requests: `GET /salons/{id}` AND
// `GET /salons/{id}/staff`. The roster is the management-scoped, UNMASKED
// staff-contacts list (see [SalonRepository.getSalonStaff]) and the screen
// destructures it away unread — a wasted round trip AND a data-minimisation
// miss.
//
// This provider is the narrow read that path actually wants. The shell path is
// untouched and still watches the management family (see
// `AdminOwnProfileScreen.hostSalonId`), so the zero-request/live-update
// property of the primary surface is preserved.
//
// ── REUSE ─────────────────────────────────────────────────────────────────
// The endpoint call and its mapping are `SalonRepository.getSalonById` +
// `SalonMapper.fromDto`, verbatim — the same PUBLIC (`permitAll`) read
// `publicSalonProfileProvider`, `salonManagementProfileProvider` and
// `salonMasterOwnProfileProvider` already make. No shipped provider exposes it
// UNPAIRED, though: every one of those three pairs it with a second read
// (masters rail / staff roster / services), which is precisely the cost being
// removed here — so this is a narrowing of an existing read, not a new one.

// `ProviderListenable.select` is not part of `riverpod_annotation`'s
// show-list — same reason `salon_management_profile_notifier.dart` reaches for
// the full package.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../auth/presentation/auth_notifier.dart';
import '../data/salon_repository.dart';
import '../domain/salon.dart';

part 'salon_detail_notifier.g.dart';

/// Loads the salon detail for [salonId].
///
/// Generated provider name: `salonDetailProvider` (a family — call it with the
/// target salon id, e.g. `salonDetailProvider(salonId)`).
@riverpod
Future<Salon> salonDetail(Ref ref, String salonId) async {
  // Auth-boundary eviction, mirroring `salonManagementProfileProvider` —
  // narrowed to the signed-in IDENTITY so a silent token refresh does not
  // refetch, while a logout / cross-account switch on the same device still
  // tears the cached salon down.
  ref.watch(authProvider.select(authUserIdOrNull));
  return ref.read(salonRepositoryProvider).getSalonById(salonId);
}
