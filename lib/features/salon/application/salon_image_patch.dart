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

import '../domain/salon.dart';
import 'my_salons_notifier.dart';
import 'public_salon_profile_notifier.dart';
import 'salon_detail_notifier.dart';
import 'salon_management_profile_notifier.dart';

/// [Salon] with [slot]'s image replaced by [url] (`null` = removed).
extension SalonImagePatch on Salon {
  Salon withImage(SalonImageSlot slot, String? url) => switch (slot) {
    SalonImageSlot.logo => copyWith(avatarUrl: url),
    SalonImageSlot.cover => copyWith(coverImageUrl: url),
  };
}

/// The value of [state] ONLY when it is a SETTLED [AsyncData] — not loading,
/// not refreshing (`AsyncData` + `isLoading`, Riverpod 3's `invalidate` shape),
/// not reloading (`AsyncLoading` carrying the previous value, the
/// dependency-change / account-switch shape), and not [AsyncError] carrying a
/// stale value. `null` otherwise.
///
/// Phase 369 audit (MASVS-AUTH, defence in depth): `patchImage` used to read
/// `state.value`, which keeps the PREVIOUS value through a refetch or an
/// error, and then wrote `AsyncData` back — promoting a stale snapshot (after
/// an account switch: the previous account's) to "resolved" and reopening the
/// ownership gates that deliberately ignore a stale `.value`. A refresh in
/// progress is deliberately NOT patchable: its in-flight GET may predate the
/// upload, and the caller's invalidate is the safe answer.
ValueT? settledValueOrNull<ValueT>(AsyncValue<ValueT> state) => switch (state) {
  AsyncData<ValueT>(:final ValueT value, isLoading: false) => value,
  _ => null,
};

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
