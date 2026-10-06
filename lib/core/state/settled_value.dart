// The SETTLED-value read every in-place cache patch shares.
//
// PROMOTED (2026-10-05, REUSE-FIRST) out of
// `features/salon/application/salon_image_patch.dart`, where it guarded only
// the salon patches (`patchImage`, `patchStaffAvatar`, `patchSalonImage`).
// The two own-avatar patches — `AuthNotifier.patchAvatarUrl` and
// `MasterProfile.patchAvatarUrl` — had the very bug it exists to prevent
// (they read the lenient `.value` and wrote `AsyncData` back) but live in
// features that may not import `salon/`, so the helper moved here. The salon
// file re-exports it, so its existing importers are unchanged.

import 'package:flutter_riverpod/flutter_riverpod.dart';

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
