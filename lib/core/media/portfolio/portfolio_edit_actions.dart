// Phase 405 (9.10, D4/D5/D7) — the portfolio editor's USER flow: source sheet
// → add, failed-tile retry / discard, confirm → delete (optimistic hide,
// restored on failure), and the result snacks. ONE flow for both editor
// surfaces — the independent master's own profile and the salon's «Про
// салон» — so a fix here reaches both (REUSE-FIRST; same shape as
// [MediaEditActions] for the avatar / logo / cover editors).
//
// WRITE GATE. This class holds NO way to reach a portfolio write on its own:
// the caller hands it [readController], and the only way to obtain a
// [PortfolioEditController] is the provider whose name the structural gate
// (`test/core/media/portfolio/portfolio_owner_call_sites_test.dart`) pins to
// the two owner-context screens. Nothing here aliases, re-exports or wraps
// that provider under another name.
//
// SNACKS OUTLIVE THE RAIL (405 audit Q1). [host] is the RAIL's state, and the
// rail unmounts on a tab switch while the screen keeps the write controller
// (and so the upload) alive. Each flow therefore captures, while [host] is
// still mounted, a [_ResultSink]: the SCREEN's context ([resultHost] — the
// state that keeps the write controller, and so the upload, alive; it
// survives in-screen tab switches) and the [ProviderContainer]. The result
// snack (which lands on the app's root overlay anyway —
// `velvet_snack_host.dart`) and the 403 re-read then go through those, never
// through the possibly-disposed rail. A disposed screen shows nothing: its
// upload was cancelled with it.
//
// 405 audit cycle 2 (perf INFO) — the screen is found by the caller with
// `findAncestorStateOfType` (no dependency). The earlier `ModalRoute.of`
// lookup subscribed the rail to EVERY route-status aspect, so after the first
// tap each sheet / dialog push and pop rebuilt the rail.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/core/media/pick/crop_labels.dart';
import 'package:beautica_mobile/core/media/pick/image_source_sheet.dart';
import 'package:beautica_mobile/core/media/pick/media_kind.dart';
import 'package:beautica_mobile/core/media/portfolio/portfolio_edit_controller.dart';
import 'package:beautica_mobile/core/media/portfolio/portfolio_notifier.dart';
import 'package:beautica_mobile/core/media/portfolio/portfolio_owner.dart';
import 'package:beautica_mobile/core/media/portfolio/portfolio_photo.dart';
import 'package:beautica_mobile/core/media/upload/upload_failure.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/feedback/show_velvet_snack.dart';
import 'package:beautica_mobile/shared/widgets/portfolio_dialogs.dart';

/// Where a flow's result lands: captured while the editor is mounted, both
/// outlive it (the screen's context as long as the screen; the container as
/// long as the [ProviderScope]).
final class _ResultSink {
  const _ResultSink(this.context, this.container);

  final BuildContext context;
  final ProviderContainer container;
}

/// The portfolio editor tap flows for [owner]. Build one per call from the
/// editor's [State] (cheap — it holds only references).
final class PortfolioEditActions {
  const PortfolioEditActions({
    required this.host,
    required this.owner,
    required this.readController,
    required this.setHidden,
    this.resultHost,
  });

  /// The editor's state: `mounted` / `context` (checked after every await
  /// that leads back to the editor itself). Result snacks do NOT depend on it
  /// staying mounted — see the file header.
  final State host;

  /// The screen-level state the result snacks / 403 re-read go through, so
  /// they survive the rail unmounting (a tab switch mid-upload). Resolved
  /// lazily — only when a flow runs, never per build — and without
  /// registering a dependency (callers use `findAncestorStateOfType`).
  /// `null` (the default), or returning `null` → [host].
  final State? Function()? resultHost;

  /// Whose portfolio — used only to re-sync the READ cache on a 403 (D7).
  final PortfolioOwner owner;

  /// The controller, read lazily and only while [host] is mounted.
  final PortfolioEditController Function() readController;

  /// Optimistic delete (D5): hide stored photo `id` while its delete is in
  /// flight; unhide when it settles (on success the controller has already
  /// dropped it from the cached list).
  final void Function(String id, {required bool hidden}) setHidden;

  /// The add tile: source sheet → pick / crop / upload. Ignored while a pick
  /// or an upload is already running (the controller runs one at a time).
  Future<void> add() async {
    if (!host.mounted || !readController().canAdd) return;
    final ImageSourceChoice? choice = await showImageSourceSheet(host.context);
    if (choice == null || !host.mounted) return;
    final _ResultSink sink = _sink();
    final CropLabels labels = CropLabels.forKind(
      AppLocalizations.of(host.context),
      MediaKind.portfolio,
    );
    final AvatarChangeResult result = await readController().add(
      choice == ImageSourceChoice.camera
          ? MediaPickSource.camera
          : MediaPickSource.gallery,
      labels: labels,
    );
    _show(sink, result, deleted: false);
  }

  /// The failed pending tile's retry: re-sends the SAME photo (no picker).
  Future<void> retry(PendingPortfolioUpload upload) async {
    if (!host.mounted) return;
    final _ResultSink sink = _sink();
    final AvatarChangeResult result = await readController().retry(upload.id);
    _show(sink, result, deleted: false);
  }

  /// The failed pending tile's discard badge.
  Future<void> discard(PendingPortfolioUpload upload) async {
    if (!host.mounted) return;
    await readController().discard(upload.id);
  }

  /// The photo's remove badge: confirm → optimistic hide → delete; on
  /// failure the photo reappears with an error snack.
  Future<void> delete(PortfolioPhoto photo) async {
    if (!host.mounted) return;
    final bool? confirmed = await showDeletePortfolioPhotoDialog(host.context);
    if (confirmed != true || !host.mounted) return;
    final _ResultSink sink = _sink();
    setHidden(photo.id, hidden: true);
    final AvatarChangeResult result = await readController().delete(photo.id);
    // The hide is the rail's own state — only while it is still there.
    if (host.mounted) setHidden(photo.id, hidden: false);
    _show(sink, result, deleted: true);
  }

  /// Resolves the [_ResultSink] — call only while [host] is mounted.
  _ResultSink _sink() {
    final BuildContext context = host.context;
    final State? screen = resultHost?.call();
    return _ResultSink(
      screen != null && screen.mounted ? screen.context : context,
      ProviderScope.containerOf(context, listen: false),
    );
  }

  void _show(
    _ResultSink sink,
    AvatarChangeResult result, {
    required bool deleted,
  }) {
    final BuildContext context = sink.context;
    if (!context.mounted) return;
    final AppLocalizations l10n = AppLocalizations.of(context);
    switch (result) {
      case AvatarChangeCancelled():
        return;
      case AvatarChangeSucceeded():
        showSuccessSnack(
          context,
          deleted ? l10n.portfolioPhotoDeleted : l10n.portfolioPhotoAdded,
        );
      case AvatarChangeFailed(failure: final PortfolioLimitReachedFailure f):
        // D4 — the cap: a warning, not an error (nothing broke).
        showWarningSnack(context, f.message(l10n));
      case AvatarChangeFailed(failure: final UploadForbiddenFailure f):
        // D7 — the role changed mid-session: say so and re-read the list
        // (the backend is the gate; the UI never relies on its own).
        // A failed add's tile is dropped by the controller (S3): its retry
        // could only 403 again.
        showErrorSnack(context, f.message(l10n));
        sink.container.invalidate(portfolioProvider(owner));
      case AvatarChangeFailed(:final failure):
        // An upload failure keeps its tile in the failed/retry state; a pick
        // failure (e.g. camera denied → UploadUnknownFailure) has no tile, so
        // the snack is its only trace.
        showErrorSnack(
          context,
          deleted ? l10n.portfolioDeleteFailed : failure.message(l10n),
        );
    }
  }
}
