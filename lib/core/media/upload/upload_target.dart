// Phase 367 (9.6) — what an upload writes to.
//
// The upload FLOW (pick → crop → upload → progress → retry → remove, see
// `media_upload_flow.dart`) is target-agnostic; only four calls differ per
// target: which crop spec to pick with, which endpoint uploads, which endpoint
// deletes, and which cached state the server's answer is written into. A
// [UploadTarget] names the target; `resolveUploadTargetBinding` turns it into
// those four calls ([UploadTargetBinding]).
//
// Locked product rule (2026-10-04): a personal avatar is set ONLY by the
// person themselves, for every role. [UploadTarget.selfAvatar] therefore
// carries NO user id, and no variant ever will — the server derives "me" from
// the token. Phase 369 adds the salon logo / cover variants (keyed by salon;
// SALON_OWNER only — locked 2026-10-04).
//
// Pure Dart: no Flutter imports.

import 'dart:io';

import 'package:beautica_mobile/core/media/pick/media_kind.dart';
import 'package:beautica_mobile/core/media/upload/upload_task.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'upload_target.freezed.dart';

/// The thing an upload writes to.
@freezed
sealed class UploadTarget with _$UploadTarget {
  /// The signed-in user's OWN avatar (`POST`/`DELETE /media/avatar`). Every
  /// role. No user id — "me" is the token's subject.
  const factory UploadTarget.selfAvatar() = SelfAvatarTarget;

  /// Phase 369 — [salonId]'s logo (`POST`/`DELETE
  /// /salons/{salonId}/media/logo`). SALON_OWNER of that salon only — the UI
  /// offers it to the owner alone and the backend 403s everyone else.
  const factory UploadTarget.salonLogo(String salonId) = SalonLogoTarget;

  /// Phase 369 — [salonId]'s 16:9 cover banner (`…/media/cover`). Same
  /// owner-only rule as [UploadTarget.salonLogo].
  const factory UploadTarget.salonCover(String salonId) = SalonCoverTarget;
}

/// The four target-specific calls the upload flow delegates to.
final class UploadTargetBinding {
  const UploadTargetBinding({
    required this.kind,
    required this.upload,
    required this.delete,
    required this.apply,
    this.pendingKey,
  });

  /// The pick / crop / compress spec (and the pending-pick recovery tag).
  final MediaKind kind;

  /// Starts the upload of the cropped [File]; resolves to the new URL.
  final UploadTask<String> Function(File file) upload;

  /// Removes the current photo server-side.
  final Future<void> Function() delete;

  /// Writes the server's answer (null = removed) into the cached state that
  /// renders it — in place, never a refetch chain.
  final void Function(String? url) apply;

  /// Phase 369 — narrows the Android lost-pick tag beyond owner + [kind]:
  /// `salonLogo:<salonId>` / `salonCover:<salonId>`, so a pick lost for one
  /// salon is never resumed into another (nor under another account — the
  /// owner half of the tag still applies). `null` (the self avatar: there is
  /// only one) keeps the pre-369 tag byte-identical.
  final String? pendingKey;
}
