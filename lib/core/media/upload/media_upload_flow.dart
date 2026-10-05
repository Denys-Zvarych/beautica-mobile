// Phase 367 (9.6) — the target-agnostic upload flow, PROMOTED out of the
// Phase 073 `AvatarUploadController` (REUSE-FIRST: one flow, every target —
// never a second controller).
//
// Orchestrates the existing building blocks and owns NO transport of its own:
//   pick → crop → compress   `MediaPickService` (071)
//   upload / delete / apply  the target's [UploadTargetBinding] (367)
//   progress + failure UI    `NeumorphicAvatarEditor` (072), driven by the
//                            screen from [AvatarUploadState]
//
// The upload endpoint answers with the new URL, so success PATCHES the cached
// state through [UploadTargetBinding.apply] (no refetch, no fan-out).
//
// 100 % progress is NEVER success: only the resolved `UploadTask.result`
// counts (the server may still answer 503 after the last byte is sent).
//
// A FAILED upload keeps its (cropped, EXIF-stripped) scratch file in
// [AvatarUploadState.failed] so `retry` re-sends the SAME photo. That file
// lives only in the notifier's state and sits in the `media_upload` scratch
// dir (logout's `wipeAll` removes it); it is deleted on success, on a new pick,
// on remove and on dispose. The notifier rebuilds (→ disposes) when the
// signed-in user changes, so a kept file can never be retried under another
// account.
//
// Every dependency is captured BEFORE the first `await`: `ref.read` after
// dispose throws, which used to leak the scratch file and escape into the UI.
//
// HOW A NOTIFIER USES IT: `class X extends _$X with MediaUploadFlow` — supply
// [MediaUploadFlow.uploadTarget] and return [MediaUploadFlow.buildFlow] from
// `build()`. The generated base class provides `ref` and `state`.
//
// Never logs paths or URLs.

import 'dart:async';
import 'dart:io';

import 'package:beautica_mobile/core/media/pick/crop_labels.dart';
import 'package:beautica_mobile/core/media/pick/image_source_sheet.dart';
import 'package:beautica_mobile/core/media/pick/media_kind.dart'
    show MediaPickSource;
import 'package:beautica_mobile/core/media/pick/media_pick_service.dart';
import 'package:beautica_mobile/core/media/pick/pending_pick_store.dart';
import 'package:beautica_mobile/core/media/upload/upload_failure.dart';
import 'package:beautica_mobile/core/media/upload/upload_target.dart';
import 'package:beautica_mobile/core/media/upload/upload_target_binding.dart';
import 'package:beautica_mobile/core/media/upload/upload_task.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, protected;
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show ProviderListenableSelect;
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'media_upload_flow.freezed.dart';

/// Smallest progress step worth a state emit (1 %): the transfer stream fires
/// per chunk and every emit rebuilds the avatar editor.
const double kAvatarProgressStep = 0.01;

/// Upper bound on warming the image cache with the new remote avatar before
/// the local preview is released.
const Duration kAvatarPrecacheTimeout = Duration(seconds: 2);

/// Warms the image cache with the new remote avatar [url]; supplied by the
/// screen (it owns the `BuildContext`).
typedef AvatarPrecache = Future<void> Function(String url);

/// What the avatar editor should currently show.
@freezed
sealed class AvatarUploadState with _$AvatarUploadState {
  /// Nothing in flight.
  const factory AvatarUploadState.idle() = AvatarIdle;

  /// Upload in flight. [progress] is 0.0–1.0 (>= 1.0 still means "waiting for
  /// the server"); [previewFile] is the cropped scratch file being uploaded.
  const factory AvatarUploadState.uploading({
    required double progress,
    File? previewFile,
  }) = AvatarUploading;

  /// The upload failed. [previewFile] is KEPT so the editor still shows the
  /// picked photo and `retry()` re-sends it without reopening the picker.
  const factory AvatarUploadState.failed({
    required File previewFile,
    required UploadFailure failure,
  }) = AvatarFailed;

  /// `DELETE /media/avatar` in flight.
  const factory AvatarUploadState.removing() = AvatarRemoving;
}

/// Outcome of [MediaUploadFlow.change] / `retry` / `remove` /
/// `recoverLost`.
sealed class AvatarChangeResult {
  const AvatarChangeResult();
}

/// The user backed out (sheet, picker or crop) — the UI shows nothing.
final class AvatarChangeCancelled extends AvatarChangeResult {
  const AvatarChangeCancelled();
}

/// The server accepted the change and the cached profile was updated.
final class AvatarChangeSucceeded extends AvatarChangeResult {
  const AvatarChangeSucceeded();
}

/// The change failed; [failure] carries the localisable reason. A
/// [UploadCancelledFailure] is mapped to [AvatarChangeCancelled] instead.
final class AvatarChangeFailed extends AvatarChangeResult {
  const AvatarChangeFailed(this.failure);

  final UploadFailure failure;
}

/// Dependencies resolved while the ref is still guaranteed alive.
final class _Deps {
  const _Deps({
    required this.pick,
    required this.target,
    required this.pending,
  });

  final MediaPickService pick;
  final UploadTargetBinding target;
  final PendingPickStore pending;
}

/// The upload flow, shared by every upload notifier (see the file header).
mixin MediaUploadFlow {
  /// Provided by the generated notifier base class.
  Ref get ref;

  /// Provided by the generated notifier base class.
  AvatarUploadState get state;
  set state(AvatarUploadState value);

  /// What this notifier uploads to.
  UploadTarget get uploadTarget;

  bool _disposed = false;
  bool _picking = false;
  // Bumped on every dispose (incl. the rebuild a user change triggers), so an
  // operation that outlives its build() can tell it is stale — `_disposed`
  // alone is reset by the next build().
  int _gen = 0;
  UploadTask<String>? _task;

  /// The failed upload's file, kept for [retry]. Mirrors [AvatarFailed].
  PickedImage? _kept;

  /// Completes when a [recoverLost] has decided whether there is anything to
  /// resume (BEFORE any upload), so a user tap queues behind it, not past it.
  Completer<void>? _recoveryProbe;

  /// The notifier's `build()` body: wires the dispose / user-change teardown
  /// and starts idle.
  @protected
  AvatarUploadState buildFlow() {
    _disposed = false;
    // A sign-out / account switch rebuilds this controller (→ onDispose), which
    // deletes any kept file: it can never be retried under another account.
    ref.watch(authProvider.select(authUserIdOrNull));
    ref.onDispose(() {
      _disposed = true;
      _gen++;
      // A cancel resolves the task with UploadCancelledFailure, which the
      // in-flight [_upload] maps to a quiet [AvatarChangeCancelled].
      _task?.cancel();
      final PickedImage? kept = _kept;
      _kept = null;
      if (kept != null) _deleteSync(kept.file);
    });
    return const AvatarUploadState.idle();
  }

  bool get _busy =>
      _picking || state is AvatarUploading || state is AvatarRemoving;

  bool _alive(int gen) => !_disposed && gen == _gen;

  /// Writes [next] only while the operation that owns [gen] is still the live
  /// one — `build()` resets `_disposed`, so a stale operation outliving a
  /// user-change rebuild would otherwise write into the NEW build's state.
  void _set(int gen, AvatarUploadState next) {
    if (_alive(gen)) state = next;
  }

  _Deps _deps() => _Deps(
    pick: ref.read(mediaPickServiceProvider),
    target: resolveUploadTargetBinding(ref, uploadTarget),
    pending: ref.read(pendingPickStoreProvider),
  );

  String? _ownerId() => authUserIdOrNull(ref.read(authProvider));

  /// Picks from [source] (gallery / camera), crops, uploads.
  ///
  /// Pass [labels] (`CropLabels.of(l10n)`) so the native crop screen is
  /// localised; [precache] warms the new remote photo before the local preview
  /// is released. [ImageSourceChoice.remove] is routed to [remove].
  Future<AvatarChangeResult> change(
    ImageSourceChoice source, {
    CropLabels? labels,
    AvatarPrecache? precache,
  }) async {
    if (source == ImageSourceChoice.remove) return remove();
    // A tap that lands while Android recovery is still probing queues behind
    // it instead of being silently dropped.
    // Everything that reads `ref` / `state` is captured BEFORE the wait: both
    // throw once this build is disposed.
    final int gen = _gen;
    final _Deps deps = _deps();
    final String? owner = _ownerId();
    await _recoveryProbe?.future;
    if (!_alive(gen) || _busy) return const AvatarChangeCancelled();
    _picking = true;
    final PickedImage? picked;
    try {
      await deps.pending.begin(
        owner,
        deps.target.kind,
        scope: deps.target.pendingKey,
      );
      picked = await deps.pick.pick(
        deps.target.kind,
        source == ImageSourceChoice.camera
            ? MediaPickSource.camera
            : MediaPickSource.gallery,
        labels: labels,
      );
    } on UploadFailure catch (f) {
      return _asResult(f);
    } finally {
      _picking = false;
      await deps.pending.clear();
    }
    if (picked == null) return const AvatarChangeCancelled();
    if (!_alive(gen)) {
      await deps.pick.discard(picked);
      return const AvatarChangeCancelled();
    }
    return _upload(picked, deps, gen, precache);
  }

  /// Re-sends the file of the last FAILED upload — the same photo, no picker.
  Future<AvatarChangeResult> retry({AvatarPrecache? precache}) async {
    final PickedImage? kept = _kept;
    if (kept == null || _busy) return const AvatarChangeCancelled();
    final int gen = _gen;
    final _Deps deps = _deps();
    _kept = null;
    final bool exists = await kept.file.exists();
    // `_kept` is already null, so a dispose landing in the await above did not
    // delete the file: do it here, and never open a request.
    if (!_alive(gen)) {
      await deps.pick.discard(kept);
      return const AvatarChangeCancelled();
    }
    if (!exists) {
      _set(gen, const AvatarUploadState.idle());
      return const AvatarChangeFailed(UploadUnknownFailure());
    }
    return _upload(kept, deps, gen, precache);
  }

  /// Android process-death recovery: resumes a pick the OS dropped and uploads
  /// it — but only when it was started by the CURRENT user for an avatar; any
  /// other lost pick — including one with NO owner tag — is drained and
  /// deleted. Returns [AvatarChangeCancelled] when there was nothing to
  /// recover (the common case: one storage read plus the drain's native
  /// `retrieveLostData`, which returns nothing).
  Future<AvatarChangeResult> recoverLost({
    CropLabels? labels,
    AvatarPrecache? precache,
  }) async {
    // `retrieveLostData` is Android-only.
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const AvatarChangeCancelled();
    }
    if (_busy) return const AvatarChangeCancelled();
    final int gen = _gen;
    final _Deps deps = _deps();
    final String? owner = _ownerId();
    _picking = true;
    final Completer<void> probe = Completer<void>();
    _recoveryProbe = probe;
    final PickedImage? picked;
    try {
      final PendingPick? tag = await deps.pending.read();
      // No owner tag = no pick of OURS to resume — but Android may still hold
      // a lost-pick record (the tag write never landed, or an earlier wipe
      // cleared only the tag). Drain it rather than leave it resumable by
      // whoever opens the editor next (Phase 367 audit, security LOW).
      if (tag == null ||
          !tag.belongsTo(
            owner,
            deps.target.kind,
            expectedScope: deps.target.pendingKey,
          )) {
        await deps.pick.drainLost();
        return const AvatarChangeCancelled();
      }
      picked = await deps.pick.recoverLost(deps.target.kind, labels: labels);
    } on UploadFailure catch (f) {
      return _asResult(f);
    } on Object {
      // No scratch dir / no plugin channel: nothing to recover, never fatal.
      return const AvatarChangeCancelled();
    } finally {
      _picking = false;
      await deps.pending.clear();
      if (identical(_recoveryProbe, probe)) _recoveryProbe = null;
      probe.complete();
    }
    if (picked == null) return const AvatarChangeCancelled();
    if (!_alive(gen)) {
      await deps.pick.discard(picked);
      return const AvatarChangeCancelled();
    }
    return _upload(picked, deps, gen, precache);
  }

  /// Deletes the current avatar.
  Future<AvatarChangeResult> remove() async {
    if (_busy) return const AvatarChangeCancelled();
    final int gen = _gen;
    final _Deps deps = _deps();
    await _releaseKept(deps.pick);
    _set(gen, const AvatarUploadState.removing());
    try {
      await deps.target.delete();
      if (_alive(gen)) deps.target.apply(null);
      return const AvatarChangeSucceeded();
    } on UploadFailure catch (f) {
      return _asResult(f);
    } finally {
      _set(gen, const AvatarUploadState.idle());
    }
  }

  Future<AvatarChangeResult> _upload(
    PickedImage picked,
    _Deps deps,
    int gen,
    AvatarPrecache? precache,
  ) async {
    // A replacement exists: the previous failed file is no longer needed.
    await _releaseKept(deps.pick, except: picked);
    if (!_alive(gen)) {
      await deps.pick.discard(picked);
      return const AvatarChangeCancelled();
    }
    StreamSubscription<double>? sub;
    UploadTask<String>? task;
    var keepFile = false;
    var deferRelease = false;
    try {
      _set(
        gen,
        AvatarUploadState.uploading(progress: 0, previewFile: picked.file),
      );
      final UploadTask<String> started = deps.target.upload(picked.file);
      task = started;
      _task = started;
      var last = 0.0;
      sub = started.progress.listen((double p) {
        // Emit the first value, the final one and any step >= 1 %: every emit
        // rebuilds the editor, the stream fires per chunk.
        final bool isFinal = p >= 1 && last < 1;
        if (!isFinal && (p - last).abs() < kAvatarProgressStep) return;
        last = p;
        _set(
          gen,
          AvatarUploadState.uploading(progress: p, previewFile: picked.file),
        );
      });
      final String url = await started.result;
      if (_alive(gen)) deps.target.apply(url);
      if (precache != null && _alive(gen)) {
        // Keep the local preview up until the remote photo is decoded, so the
        // editor never flashes between "uploaded" and "painted". Bounded, and
        // off the result's critical path.
        deferRelease = true;
        unawaited(_releaseAfterPrecache(picked, deps.pick, url, precache, gen));
      }
      return const AvatarChangeSucceeded();
    } on UploadFailure catch (f) {
      if (f is! UploadCancelledFailure && _alive(gen)) {
        // Keep the file: the editor still shows it and `retry()` re-sends it.
        keepFile = true;
        _kept = picked;
        _set(
          gen,
          AvatarUploadState.failed(previewFile: picked.file, failure: f),
        );
      }
      return _asResult(f);
    } finally {
      // A rebuild reuses this notifier: only clear OUR task, never the new
      // build's.
      if (task != null && identical(_task, task)) _task = null;
      await sub?.cancel();
      if (!keepFile && !deferRelease) {
        _set(gen, const AvatarUploadState.idle());
        await deps.pick.discard(picked);
      }
    }
  }

  Future<void> _releaseAfterPrecache(
    PickedImage picked,
    MediaPickService pick,
    String url,
    AvatarPrecache precache,
    int gen,
  ) async {
    try {
      await precache(url).timeout(kAvatarPrecacheTimeout);
    } on Object {
      // A failed / slow precache only costs a brief flash.
    }
    _set(gen, const AvatarUploadState.idle());
    await pick.discard(picked);
  }

  /// Drops the kept failed file (new pick / remove).
  Future<void> _releaseKept(
    MediaPickService pick, {
    PickedImage? except,
  }) async {
    final PickedImage? kept = _kept;
    if (kept == null || identical(kept, except)) return;
    _kept = null;
    await pick.discard(kept);
  }

  AvatarChangeResult _asResult(UploadFailure f) => f is UploadCancelledFailure
      ? const AvatarChangeCancelled()
      : AvatarChangeFailed(f);

  static void _deleteSync(File file) {
    try {
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException {
      // Best effort: logout's wipeAll sweeps the scratch dir regardless.
    }
  }
}
