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
// the token. Phase 369 adds the salon logo / cover variants (keyed by salon).
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
}

/// The four target-specific calls the upload flow delegates to.
final class UploadTargetBinding {
  const UploadTargetBinding({
    required this.kind,
    required this.upload,
    required this.delete,
    required this.apply,
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
}
