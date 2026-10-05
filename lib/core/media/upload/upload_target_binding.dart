// Phase 367 (9.6) — resolves an [UploadTarget] to its [UploadTargetBinding].
//
// Called from the upload flow while its `ref` is still guaranteed alive (the
// flow captures every dependency BEFORE its first `await`), so the returned
// closures hold the repository instance that was current at that moment.
// [UploadTargetBinding.apply] still reads providers lazily — the flow only
// invokes it while the operation that owns it is the live one.

import 'dart:io';

import 'package:beautica_mobile/core/media/pick/media_kind.dart';
import 'package:beautica_mobile/core/media/upload/media_upload_repository.dart';
import 'package:beautica_mobile/core/media/upload/upload_target.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_image_patch.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

/// The binding for [target], resolved against [ref].
UploadTargetBinding resolveUploadTargetBinding(Ref ref, UploadTarget target) {
  final MediaUploadRepository uploads = ref.read(mediaUploadRepositoryProvider);
  return switch (target) {
    SelfAvatarTarget() => UploadTargetBinding(
      kind: MediaKind.avatar,
      upload: uploads.uploadAvatar,
      delete: uploads.deleteAvatar,
      apply: (String? url) => applySelfAvatarUrl(ref, url),
    ),
    SalonLogoTarget(:final String salonId) => _salonBinding(
      ref,
      uploads,
      salonId,
      SalonImageSlot.logo,
      MediaKind.salonLogo,
    ),
    SalonCoverTarget(:final String salonId) => _salonBinding(
      ref,
      uploads,
      salonId,
      SalonImageSlot.cover,
      MediaKind.salonCover,
    ),
  };
}

/// Phase 369 — a salon logo / cover binding: the slot's endpoints, its crop
/// spec, the per-salon pending key, and the in-place salon patch.
UploadTargetBinding _salonBinding(
  Ref ref,
  MediaUploadRepository uploads,
  String salonId,
  SalonImageSlot slot,
  MediaKind kind,
) => UploadTargetBinding(
  kind: kind,
  upload: (File file) => uploads.uploadSalonImage(salonId, slot, file),
  delete: () => uploads.deleteSalonImage(salonId, slot),
  apply: (String? url) => applySalonImageUrl(ref, salonId, slot, url),
  pendingKey: '${kind.name}:$salonId',
);

/// The self-avatar sink (D3): writes the new own-avatar [url] (null =
/// removed) into every cached own-profile that renders it, with no refetch.
///
/// - The session `User` — always, every role (owner / admin / client cards and
///   «Особисті дані» read it).
/// - `masterProfileProvider` — patched only when it ALREADY exists, for every
///   role. Reading it otherwise would BUILD it (a `GET /masters/me`), and for
///   a master the patch would then miss the still-loading build and fall back
///   to an invalidate — a second `GET /masters/me` (Phase 367 audit, perf
///   INFO); a non-master session would 403 on it. Nothing to update either:
///   whoever builds it later fetches the profile with the new photo. When it
///   exists, INDEPENDENT_MASTER / SALON_MASTER behave exactly as Phase 073
///   did (patch, or a seamless invalidate when the cached build has no value
///   yet; the SALON_MASTER own-profile loader watches it, so it follows); any
///   other role (an owner who also performs services) is patched only.
void applySelfAvatarUrl(Ref ref, String? url) {
  ref.read(authProvider.notifier).patchAvatarUrl(url);
  if (!ref.exists(masterProfileProvider)) return;
  final UserRole? role = authUserRoleOrNull(ref.read(authProvider));
  final bool isMaster =
      role == UserRole.independentMaster || role == UserRole.salonMaster;
  final bool patched = ref
      .read(masterProfileProvider.notifier)
      .patchAvatarUrl(url);
  if (isMaster && !patched) ref.invalidate(masterProfileProvider);
}
