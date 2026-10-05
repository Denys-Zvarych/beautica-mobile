// Phase 073 — own avatar upload controller; Phase 367 (9.6) — generalised.
//
// The flow itself (pick → crop → upload → progress → retry → remove, gen
// guards, kept file, pending-pick recovery, logout drain) now lives ONCE in
// `MediaUploadFlow` (`lib/core/media/upload/media_upload_flow.dart`). This
// notifier is that flow bound to [UploadTarget.selfAvatar] — the signed-in
// user's OWN avatar, for EVERY role (CLIENT, SALON_OWNER, SALON_ADMIN,
// SALON_MASTER, INDEPENDENT_MASTER). There is no target-user parameter: a
// personal avatar is set only by the person themselves (locked 2026-10-04).
//
// Success writes the new URL into the session `User` (every role) and, for the
// master roles, into `masterProfileProvider` exactly as Phase 073 did — see
// `applySelfAvatarUrl`.
//
// The provider name, the class name and every state / result type are kept
// (D2): Phase 073 code and tests reference them unchanged. Phase 369's salon
// logo / cover notifier reuses the same `MediaUploadFlow` with its own target.

import 'package:beautica_mobile/core/media/upload/media_upload_flow.dart';
import 'package:beautica_mobile/core/media/upload/upload_target.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

export 'package:beautica_mobile/core/media/upload/media_upload_flow.dart';
export 'package:beautica_mobile/core/media/upload/upload_target.dart';

part 'avatar_upload_controller.g.dart';

/// The signed-in user's own avatar upload, for every role.
@riverpod
class AvatarUploadController extends _$AvatarUploadController
    with MediaUploadFlow {
  @override
  UploadTarget get uploadTarget => const UploadTarget.selfAvatar();

  @override
  AvatarUploadState build() => buildFlow();
}
