// Phase 369 (9.8) — the salon logo / cover upload controller.
//
// The SAME `MediaUploadFlow` as the own-avatar controller (pick → crop →
// upload → progress → retry → remove, gen guards, kept file, pending-pick
// recovery, logout drain) bound to [UploadTarget.salonLogo] /
// [UploadTarget.salonCover] — REUSE-FIRST: no second flow. One instance per
// `(salonId, slot)`, so a logo and a cover upload of the same salon never
// share state, and neither ever lands on another salon.
//
// SALON_OWNER only (locked 2026-10-04): the management profile builds the
// editors for the owner alone; the backend 403s anyone else, surfaced as
// `UploadForbiddenFailure(salonOwnerOnly: true)`.

import 'package:beautica_mobile/core/media/upload/media_upload_flow.dart';
import 'package:beautica_mobile/core/media/upload/media_upload_repository.dart';
import 'package:beautica_mobile/core/media/upload/upload_target.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

export 'package:beautica_mobile/core/media/upload/media_upload_flow.dart';
export 'package:beautica_mobile/core/media/upload/media_upload_repository.dart'
    show SalonImageSlot;

part 'salon_image_upload_controller.g.dart';

/// [salonId]'s [slot] image upload (owner only).
@riverpod
class SalonImageUploadController extends _$SalonImageUploadController
    with MediaUploadFlow {
  @override
  UploadTarget get uploadTarget => switch (slot) {
    SalonImageSlot.logo => UploadTarget.salonLogo(salonId),
    SalonImageSlot.cover => UploadTarget.salonCover(salonId),
  };

  @override
  AvatarUploadState build(String salonId, SalonImageSlot slot) => buildFlow();
}
