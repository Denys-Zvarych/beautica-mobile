// Phase 403 (9.8, D7) — the ONE portfolio write controller, for a salon and
// for an independent master alike: add (pick → crop → upload, with progress),
// retry / discard a failed upload, delete a stored photo, and Android
// lost-pick recovery.
//
// NOT `MediaUploadFlow`: that mixin models a single-slot REPLACE (one avatar /
// logo / cover); a portfolio APPENDS to a list and deletes by media id. What
// IS reused (REUSE-FIRST): `MediaPickService` (pick / crop / compress /
// discard / lost-data), `PendingPickStore` (account- and target-bound
// recovery tag), `MediaUploadRepository` (`uploadPortfolioPhoto` /
// `deletePortfolioPhoto` on the shared multipart `_upload`), `UploadTask`,
// the `UploadFailure` hierarchy, and the `AvatarChangeResult` outcome types.
//
// State: the uploads that are NOT yet part of the stored portfolio —
// `[PendingPortfolioUpload]` (local file, progress, failure?). A successful
// upload drops its entry and PREPENDS the server-returned photo to the cached
// `portfolioProvider(owner)` list (newest first); a delete drops the id from
// it. Either falls back to an invalidate only when there is no settled cached
// value — never a 50-row refetch per write. A delete answered 404 also drops
// the id, then invalidates so the list re-syncs with the server (the 404 may
// not mean "already gone").
// A failed upload KEEPS its (cropped,
// EXIF-stripped) scratch file so `retry` re-sends the same photo; `discard`
// drops it. ONE upload at a time: `add` / `retry` are refused while an upload
// or a pick is in flight ([canAdd]).
//
// Lifetime / safety (mirrors `MediaUploadFlow`):
//   • every `ref`-derived dependency is captured BEFORE the first `await`;
//   • a generation counter makes an operation that outlives its build a
//     no-op (no state write, no invalidation);
//   • a sign-out / account switch rebuilds the controller (identity-only
//     `select`), which cancels the in-flight upload and deletes every kept
//     file — one account's photo is never retried under another;
//   • nothing here logs a path, a URL or an id.

import 'dart:async';
import 'dart:io';

import 'package:beautica_mobile/core/media/pick/crop_labels.dart';
import 'package:beautica_mobile/core/media/pick/media_kind.dart';
import 'package:beautica_mobile/core/media/pick/media_pick_service.dart';
import 'package:beautica_mobile/core/media/pick/pending_pick_store.dart';
import 'package:beautica_mobile/core/media/portfolio/portfolio_notifier.dart';
import 'package:beautica_mobile/core/media/portfolio/portfolio_owner.dart';
import 'package:beautica_mobile/core/media/portfolio/portfolio_photo.dart';
import 'package:beautica_mobile/core/media/upload/media_upload_flow.dart'
    show
        AvatarChangeCancelled,
        AvatarChangeFailed,
        AvatarChangeResult,
        AvatarChangeSucceeded;
import 'package:beautica_mobile/core/media/upload/media_upload_repository.dart';
import 'package:beautica_mobile/core/media/upload/upload_failure.dart';
import 'package:beautica_mobile/core/media/upload/upload_task.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show ProviderListenableSelect;
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

export 'package:beautica_mobile/core/media/upload/media_upload_flow.dart'
    show
        AvatarChangeCancelled,
        AvatarChangeFailed,
        AvatarChangeResult,
        AvatarChangeSucceeded;

part 'portfolio_edit_controller.freezed.dart';
part 'portfolio_edit_controller.g.dart';

/// The pending-list progress step. The repository already throttles its
/// stream at 1 %; a list-state write per 1 % would rebuild every listener up
/// to ~100 times per upload, so the list moves in 5 % steps (plus a final
/// 100 %, always emitted).
const double kPortfolioProgressStep = 0.05;

/// One upload that is not (yet) part of the stored portfolio.
///
/// `toString()` is hand-redacted: [file] is a scratch path.
@Freezed(toStringOverride: false)
abstract class PendingPortfolioUpload with _$PendingPortfolioUpload {
  const factory PendingPortfolioUpload({
    /// Local, per-controller id (`retry` / `discard` key) — never a media id.
    required String id,

    /// The cropped, EXIF-stripped scratch file being (re-)sent.
    required File file,

    /// 0.0–1.0 send progress; >= 1.0 still means "waiting for the server".
    @Default(0.0) double progress,

    /// Why the last attempt failed; `null` while uploading.
    UploadFailure? failure,
  }) = _PendingPortfolioUpload;

  const PendingPortfolioUpload._();

  /// In flight (not failed).
  bool get isUploading => failure == null;

  @override
  String toString() =>
      'PendingPortfolioUpload(uploading: $isUploading, '
      'progress: $progress, failure: ${failure.runtimeType})';
}

/// Dependencies resolved while the ref is still guaranteed alive.
final class _Deps {
  const _Deps({
    required this.pick,
    required this.uploads,
    required this.pending,
    required this.ownerId,
  });

  final MediaPickService pick;
  final MediaUploadRepository uploads;
  final PendingPickStore pending;

  /// The signed-in user (the pending-pick tag's owner).
  final String? ownerId;
}

/// Adds / deletes photos of [owner]'s portfolio. See the file header.
@riverpod
class PortfolioEditController extends _$PortfolioEditController {
  bool _disposed = false;
  bool _picking = false;
  bool _deleting = false;
  int _gen = 0;
  int _seq = 0;
  UploadTask<PortfolioPhoto>? _task;

  /// Every pending entry's file, by entry id (uploading AND failed) — what
  /// dispose deletes. Mirrors [state].
  final Map<String, PickedImage> _files = <String, PickedImage>{};

  /// Completes when a [recoverLost] has decided whether there is anything to
  /// resume, so a user tap queues behind it, not past it.
  Completer<void>? _recoveryProbe;

  @override
  List<PendingPortfolioUpload> build(PortfolioOwner owner) {
    _disposed = false;
    // Sign-out / account switch → rebuild → onDispose below.
    ref.watch(authProvider.select(authUserIdOrNull));
    ref.onDispose(() {
      _disposed = true;
      _gen++;
      // Resolves the task with UploadCancelledFailure → a quiet cancel.
      _task?.cancel();
      final List<PickedImage> files = _files.values.toList();
      _files.clear();
      // Fire-and-forget: no sync file I/O on the main isolate. Best effort —
      // logout's scratch-dir wipe sweeps anything left.
      for (final PickedImage f in files) {
        unawaited(f.file.delete().catchError((Object _) => f.file));
      }
    });
    return const <PendingPortfolioUpload>[];
  }

  /// The pending-pick tag scope: one per portfolio, so a lost pick of salon
  /// A's portfolio is never resumed into salon B's (or a master's).
  String get _pendingKey => switch (owner) {
    final PortfolioOwnerSalon o => 'portfolio:salon:${o.salonId}',
    final PortfolioOwnerMasterSelf o => 'portfolio:master:${o.masterId}',
  };

  bool get _uploading => state.any((PendingPortfolioUpload p) => p.isUploading);

  /// Whether [add] (and [retry]) may start now: no pick and no upload in
  /// flight.
  bool get canAdd => !_picking && !_uploading;

  bool _alive(int gen) => !_disposed && gen == _gen;

  _Deps _deps() => _Deps(
    pick: ref.read(mediaPickServiceProvider),
    uploads: ref.read(mediaUploadRepositoryProvider),
    pending: ref.read(pendingPickStoreProvider),
    ownerId: authUserIdOrNull(ref.read(authProvider)),
  );

  /// Client-side cap pre-check: the CACHED stored portfolio (never triggers a
  /// fetch; 0 when nothing is cached) PLUS every pending entry still in the
  /// list (a failed upload not yet discarded will land on retry), so a user
  /// can't queue past the cap. The server's 409 stays authoritative.
  bool _atCap() {
    final provider = portfolioProvider(owner);
    final int stored = ref.exists(provider)
        ? (ref.read(provider).value?.length ?? 0)
        : 0;
    return stored + state.length >= kPortfolioMaxPhotos;
  }

  /// Picks from [source], crops to [MediaKind.portfolio], uploads.
  ///
  /// Pass [labels] (`CropLabels.forKind(l10n, MediaKind.portfolio)`) so the
  /// native crop screen is localised. Already at [kPortfolioMaxPhotos] →
  /// [AvatarChangeFailed] with [PortfolioLimitReachedFailure], no picker.
  Future<AvatarChangeResult> add(
    MediaPickSource source, {
    CropLabels? labels,
  }) async {
    final int gen = _gen;
    final _Deps deps = _deps();
    await _recoveryProbe?.future;
    if (!_alive(gen) || !canAdd) return const AvatarChangeCancelled();
    if (_atCap()) {
      return const AvatarChangeFailed(PortfolioLimitReachedFailure());
    }
    _picking = true;
    final PickedImage? picked;
    try {
      await deps.pending.begin(
        deps.ownerId,
        MediaKind.portfolio,
        scope: _pendingKey,
      );
      picked = await deps.pick.pick(
        MediaKind.portfolio,
        source,
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
    return _upload(picked, deps, gen, 'p${_seq++}');
  }

  /// Re-sends the failed upload [id] — the same photo, no picker.
  Future<AvatarChangeResult> retry(String id) async {
    final PickedImage? kept = _files[id];
    if (kept == null || !_isFailed(id) || !canAdd) {
      return const AvatarChangeCancelled();
    }
    final int gen = _gen;
    final _Deps deps = _deps();
    final bool exists = await kept.file.exists();
    if (!_alive(gen)) return const AvatarChangeCancelled();
    if (!exists) {
      _files.remove(id);
      _remove(gen, id);
      return const AvatarChangeFailed(UploadUnknownFailure());
    }
    return _upload(kept, deps, gen, id);
  }

  /// Drops the failed upload [id] and deletes its file. No-op while it is
  /// uploading.
  Future<void> discard(String id) async {
    if (!_isFailed(id)) return;
    final MediaPickService pick = ref.read(mediaPickServiceProvider);
    final PickedImage? kept = _files.remove(id);
    _remove(_gen, id);
    if (kept != null) await pick.discard(kept);
  }

  /// Deletes stored photo [mediaId]. Success drops it from the cached
  /// `portfolioProvider(owner)` list (no refetch). A 404 is also reported as
  /// success and drops it locally, but then invalidates the list so it
  /// re-syncs with the server — a 404 from an unbound owner or a wrong route
  /// must not leave a still-live photo looking deleted. Any other failure
  /// leaves the list unchanged. One delete at a time.
  Future<AvatarChangeResult> delete(String mediaId) async {
    if (_deleting) return const AvatarChangeCancelled();
    final int gen = _gen;
    final _Deps deps = _deps();
    _deleting = true;
    try {
      await deps.uploads.deletePortfolioPhoto(owner, mediaId);
      _removeStored(gen, mediaId);
      return const AvatarChangeSucceeded();
    } on UploadNotFoundFailure {
      // Most likely already gone: drop it locally and report success
      // (idempotent delete; no error surfaced) — but re-sync with the server,
      // since a 404 can have another cause and the photo may still be live.
      _removeStored(gen, mediaId);
      _resyncStored(gen);
      return const AvatarChangeSucceeded();
    } on UploadFailure catch (f) {
      return _asResult(f);
    } finally {
      _deleting = false;
    }
  }

  /// Android process-death recovery: resumes a portfolio pick the OS dropped
  /// and uploads it — only when the CURRENT user started it for THIS
  /// portfolio; any other lost pick (incl. one with no tag) is drained.
  Future<AvatarChangeResult> recoverLost({CropLabels? labels}) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const AvatarChangeCancelled();
    }
    if (!canAdd) return const AvatarChangeCancelled();
    final int gen = _gen;
    final _Deps deps = _deps();
    _picking = true;
    final Completer<void> probe = Completer<void>();
    _recoveryProbe = probe;
    final PickedImage? picked;
    try {
      final PendingPick? tag = await deps.pending.read();
      if (tag == null ||
          !tag.belongsTo(
            deps.ownerId,
            MediaKind.portfolio,
            expectedScope: _pendingKey,
          )) {
        await deps.pick.drainLost();
        return const AvatarChangeCancelled();
      }
      picked = await deps.pick.recoverLost(MediaKind.portfolio, labels: labels);
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
    return _upload(picked, deps, gen, 'p${_seq++}');
  }

  Future<AvatarChangeResult> _upload(
    PickedImage picked,
    _Deps deps,
    int gen,
    String id,
  ) async {
    _files[id] = picked;
    _put(gen, PendingPortfolioUpload(id: id, file: picked.file));
    StreamSubscription<double>? sub;
    UploadTask<PortfolioPhoto>? task;
    var keepFile = false;
    try {
      final UploadTask<PortfolioPhoto> started = deps.uploads
          .uploadPortfolioPhoto(owner, picked.file);
      task = started;
      _task = started;
      var last = 0.0;
      sub = started.progress.listen((double p) {
        final bool isFinal = p >= 1 && last < 1;
        if (!isFinal && (p - last).abs() < kPortfolioProgressStep) return;
        last = p;
        _put(
          gen,
          PendingPortfolioUpload(id: id, file: picked.file, progress: p),
        );
      });
      final PortfolioPhoto photo = await started.result;
      _prependStored(gen, photo);
      return const AvatarChangeSucceeded();
    } on UploadFailure catch (f) {
      if (f is! UploadCancelledFailure && _alive(gen)) {
        keepFile = true;
        _put(
          gen,
          PendingPortfolioUpload(id: id, file: picked.file, failure: f),
        );
      }
      return _asResult(f);
    } finally {
      if (task != null && identical(_task, task)) _task = null;
      await sub?.cancel();
      if (!keepFile) {
        _files.remove(id);
        _remove(gen, id);
        await deps.pick.discard(picked);
      }
    }
  }

  bool _isFailed(String id) =>
      state.any((PendingPortfolioUpload p) => p.id == id && !p.isUploading);

  /// Inserts or replaces entry [next] (by id), keeping order.
  void _put(int gen, PendingPortfolioUpload next) {
    if (!_alive(gen)) return;
    final List<PendingPortfolioUpload> list = <PendingPortfolioUpload>[
      ...state,
    ];
    final int i = list.indexWhere(
      (PendingPortfolioUpload p) => p.id == next.id,
    );
    if (i == -1) {
      list.add(next);
    } else {
      list[i] = next;
    }
    state = List<PendingPortfolioUpload>.unmodifiable(list);
  }

  /// Drops entry [id]. Checks liveness BEFORE touching [state] (a disposed
  /// notifier's state must not be read).
  void _remove(int gen, String id) {
    if (!_alive(gen)) return;
    state = List<PendingPortfolioUpload>.unmodifiable(
      state.where((PendingPortfolioUpload p) => p.id != id),
    );
  }

  /// Prepends [photo] to the cached stored list; invalidates only when there
  /// is no settled cached value to patch.
  void _prependStored(int gen, PortfolioPhoto photo) =>
      _patchStored(gen, (PortfolioNotifier n) => n.prependLocal(photo));

  /// Drops [mediaId] from the cached stored list (same fallback).
  void _removeStored(int gen, String mediaId) =>
      _patchStored(gen, (PortfolioNotifier n) => n.removeLocal(mediaId));

  void _patchStored(int gen, bool Function(PortfolioNotifier) patch) {
    if (!_alive(gen)) return;
    final provider = portfolioProvider(owner);
    if (ref.exists(provider) && patch(ref.read(provider.notifier))) return;
    ref.invalidate(provider);
  }

  /// Invalidates the stored list so it re-reads the server. 404-delete only.
  void _resyncStored(int gen) {
    if (!_alive(gen)) return;
    ref.invalidate(portfolioProvider(owner));
  }

  AvatarChangeResult _asResult(UploadFailure f) => f is UploadCancelledFailure
      ? const AvatarChangeCancelled()
      : AvatarChangeFailed(f);
}
