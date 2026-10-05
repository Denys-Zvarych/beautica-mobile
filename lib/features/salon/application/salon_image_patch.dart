// Phase 369 (9.8) — the salon logo / cover upload sink.
//
// `POST`/`DELETE /salons/{salonId}/media/{logo|cover}` answer with the new
// state, so a successful upload / removal PATCHES every cached salon that
// renders it — in place, never a refetch chain (mirrors 367's
// `applySelfAvatarUrl`):
//   • `salonManagementProfileProvider(salonId)` — the management hero (owner);
//   • `mySalonsProvider` — the «Мої салони» hub card + rotate-admin picker;
//   • the read-only public caches (`publicSalonProfileProvider`,
//     `salonDetailProvider`) are functional providers with no patch seam, so
//     they are invalidated — and ONLY when alive (an invalidate of a live
//     provider refreshes it in the background with its previous value, so no
//     skeleton; one that is not alive simply fetches fresh when next read).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/core/media/upload/media_upload_repository.dart'
    show SalonImageSlot;
import 'package:beautica_mobile/core/state/settled_value.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';

import '../domain/salon.dart';
import 'my_salons_notifier.dart';
import 'public_salon_profile_notifier.dart';
import 'salon_detail_notifier.dart';
import 'salon_management_profile_notifier.dart';

// PROMOTED to core (2026-10-05) so the own-avatar patches can share it;
// re-exported so every existing importer of this file resolves unchanged.
export 'package:beautica_mobile/core/state/settled_value.dart'
    show settledValueOrNull;

/// [Salon] with [slot]'s image replaced by [url] (`null` = removed).
extension SalonImagePatch on Salon {
  Salon withImage(SalonImageSlot slot, String? url) => switch (slot) {
    SalonImageSlot.logo => copyWith(avatarUrl: url),
    SalonImageSlot.cover => copyWith(coverImageUrl: url),
  };
}

/// Writes [salonId]'s new [slot] image [url] (`null` = removed) into every
/// cached salon that renders it — see the file header.
void applySalonImageUrl(
  Ref ref,
  String salonId,
  SalonImageSlot slot,
  String? url,
) {
  final manage = salonManagementProfileProvider(salonId);
  if (ref.exists(manage)) {
    final bool patched = ref.read(manage.notifier).patchImage(slot, url);
    // Not settled (loading / refreshing / error): its in-flight or failed GET
    // may predate the upload, and a stale value must never be promoted to
    // AsyncData — refetch instead.
    if (!patched) ref.invalidate(manage);
  }
  if (ref.exists(mySalonsProvider)) {
    final bool patched = ref
        .read(mySalonsProvider.notifier)
        .patchImage(salonId, slot, url);
    // Not patched — either not settled (loading / refreshing / error: its GET
    // may predate the upload, and a stale list must never be promoted to
    // AsyncData) or settled without this salon (the list is out of date for
    // a salon the owner just edited). Both refetch.
    if (!patched) ref.invalidate(mySalonsProvider);
  }
  final public = publicSalonProfileProvider(salonId);
  if (ref.exists(public)) ref.invalidate(public);
  final detail = salonDetailProvider(salonId);
  if (ref.exists(detail)) ref.invalidate(detail);
}

/// Writes the signed-in owner's / admin's OWN new avatar [url] (`null` =
/// removed) into the «Команда» roster of every salon they manage that is
/// already cached — called from `applySelfAvatarUrl` after a self-avatar
/// upload. Without it the owner-master's / admin's own card stays on the old
/// photo for as long as the shell keeps `salonManagementProfileProvider`
/// alive (its only rebuild key is the user id).
///
/// - Which salons: an owner's come from `mySalonsProvider`'s SETTLED list —
///   read only when that provider already exists, never built here; an
///   admin's is the session's [adminSalonId]. When the set is unknown (owner
///   list not loaded / unsettled, admin salon id unknown) the whole
///   `salonManagementProfileProvider` family is invalidated instead, which
///   refetches only the members that are alive.
/// - Per salon: patched in place only when its element already exists
///   (`ref.exists` — nothing is built); when it exists but is unsettled or
///   does not list [userId], it is invalidated (its in-flight GET may predate
///   the upload).
///
/// Any other [role] is a no-op — a client or master has no management roster.
void applyOwnStaffAvatarUrl(
  Ref ref, {
  required UserRole? role,
  required String? userId,
  required String? adminSalonId,
  required String? url,
}) {
  if (userId == null) return;
  final Iterable<String>? salonIds = switch (role) {
    UserRole.salonOwner =>
      ref.exists(mySalonsProvider)
          ? settledValueOrNull(
              ref.read(mySalonsProvider),
            )?.map((Salon s) => s.id)
          : null,
    UserRole.salonAdmin => adminSalonId == null ? null : <String>[adminSalonId],
    _ => const <String>[],
  };
  if (salonIds == null) {
    ref.invalidate(salonManagementProfileProvider);
    return;
  }
  for (final String salonId in salonIds) {
    final manage = salonManagementProfileProvider(salonId);
    if (!ref.exists(manage)) continue;
    final bool patched = ref
        .read(manage.notifier)
        .patchStaffAvatar(userId, url);
    if (!patched) ref.invalidate(manage);
  }
}
