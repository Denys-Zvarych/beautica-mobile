// Phase 369 (9.8) — the OWNER-only salon logo / cover editors on the
// management profile hero.
//
// Locked product rule (user, 2026-10-04): only the SALON_OWNER changes the
// salon logo and banner. The management screen builds these widgets for the
// owner alone — a SALON_ADMIN gets the plain read-only [SalonLogo] /
// [SalonCover] with no badge and nothing tappable; the backend 403 (343) is the
// real gate, surfaced as «Змінювати фото салону може лише власник».
//
// REUSE-FIRST — nothing here is a new photo widget:
//   • the flow is the 367 `MediaUploadFlow` (`SalonImageUploadController`);
//   • the tap → source sheet → change / remove → snack, retry and lost-pick
//     recovery are [MediaEditActions] (promoted out of the own-avatar binding);
//   • the marks are [SalonLogo] / [SalonCover] themselves (additive
//     `previewFile` / `overlay` / `editBadge` params), the badge is the
//     avatar editor's [PhotoEditBadge], the cover control is a
//     [CoverIconButton], the busy / failed states are the 072
//     `UploadProgressOverlay` / `UploadFailedOverlay`.

import 'dart:io' show File;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/core/media/beautica_image.dart';
import 'package:beautica_mobile/core/media/pick/media_kind.dart';
import 'package:beautica_mobile/core/media/pick/media_pick_service.dart';
import 'package:beautica_mobile/core/media/pick/pending_pick_store.dart';
import 'package:beautica_mobile/core/media/upload/avatar_editor_binding.dart'
    show MediaEditActions;
import 'package:beautica_mobile/core/media/upload/salon_image_upload_controller.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart'
    show PhotoEditBadge;
import 'package:beautica_mobile/core/widgets/upload_state_overlay.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

import 'salon_cover_widgets.dart';

/// Diameter of the logo's camera badge — smaller than the avatar editor's
/// 30 dp so it reads as a badge on the 68 dp mark, not a second disc.
const double kSalonLogoBadgeSize = 26;

/// The [MediaEditActions] for [salonId]'s [slot], hosted by [host]. A
/// successful upload warms the cache at [decodeSize] (the size the mark
/// requests) before the local preview is released, so the swap never flashes.
MediaEditActions salonImageEditActions({
  required ConsumerState host,
  required String salonId,
  required SalonImageSlot slot,
  required Size decodeSize,
}) {
  final provider = salonImageUploadControllerProvider(salonId, slot);
  return MediaEditActions(
    host: host,
    readState: () => host.ref.read(provider),
    readFlow: () => host.ref.read(provider.notifier),
    kind: switch (slot) {
      SalonImageSlot.logo => MediaKind.salonLogo,
      SalonImageSlot.cover => MediaKind.salonCover,
    },
    precache: (String url) async {
      if (!host.mounted) return;
      await precacheRemoteImage(
        host.context,
        url,
        decodeSize.width,
        decodeSize.height,
      );
    },
    updatedMessage: switch (slot) {
      SalonImageSlot.logo => (AppLocalizations l10n) => l10n.avatarUpdated,
      SalonImageSlot.cover => (AppLocalizations l10n) => l10n.salonCoverUpdated,
    },
    removedMessage: switch (slot) {
      SalonImageSlot.logo => (AppLocalizations l10n) => l10n.avatarRemoved,
      SalonImageSlot.cover => (AppLocalizations l10n) => l10n.salonCoverRemoved,
    },
  );
}

/// Android process-death recovery for [salonId]'s logo / cover: peeks the
/// pending-pick tag ONCE and resumes it through the slot it names (the logo
/// otherwise — whose flow drains a tag that is not ours: another salon,
/// another account, an avatar). One probe for both slots, so the two flows
/// never race to drain each other's tag. No-op off Android.
Future<void> recoverLostSalonImage({
  required ConsumerState host,
  required String salonId,
  required Size logoDecodeSize,
  required Size coverDecodeSize,
}) async {
  if (defaultTargetPlatform != TargetPlatform.android) return;
  final PendingPick? tag = await host.ref.read(pendingPickStoreProvider).read();
  if (!host.mounted) return;
  // Phase 369 audit (mobile-perf LOW) — the common case (no tag) only needs
  // the drain; running the flow would re-read the secure-storage tag a
  // second time just to reach the same drain.
  if (tag == null) {
    await host.ref.read(mediaPickServiceProvider).drainLost();
    return;
  }
  final bool cover = tag.kind == MediaKind.salonCover;
  final SalonImageSlot slot = cover
      ? SalonImageSlot.cover
      : SalonImageSlot.logo;
  // Keep the (autoDispose) controller alive for the whole recovery + upload:
  // the editors may not be mounted yet (the profile is still loading), and an
  // unwatched controller would be disposed — cancelling the upload.
  final ProviderSubscription<AvatarUploadState> keepAlive = host.ref
      .listenManual<AvatarUploadState>(
        salonImageUploadControllerProvider(salonId, slot),
        (_, _) {},
      );
  try {
    await salonImageEditActions(
      host: host,
      salonId: salonId,
      slot: slot,
      decodeSize: cover ? coverDecodeSize : logoDecodeSize,
    ).recoverLost();
  } finally {
    keepAlive.close();
  }
}

/// What a mark shows for one controller state.
typedef _UploadVisuals = ({File? preview, Widget? overlay, bool busy});

_UploadVisuals _visualsFor(
  AvatarUploadState state, {
  required bool circular,
  required VoidCallback onRetry,
  bool showMessage = false,
}) => switch (state) {
  AvatarUploading(:final double progress, :final File? previewFile) => (
    preview: previewFile,
    overlay: UploadProgressOverlay(progress: progress, circular: circular),
    busy: true,
  ),
  AvatarRemoving() => (
    preview: null,
    overlay: UploadProgressOverlay(circular: circular),
    busy: true,
  ),
  // The failed photo stays visible under the retry target.
  AvatarFailed(:final File previewFile) => (
    preview: previewFile,
    overlay: UploadFailedOverlay(
      onRetry: onRetry,
      circular: circular,
      showMessage: showMessage,
    ),
    busy: false,
  ),
  AvatarIdle() => (preview: null, overlay: null, busy: false),
};

/// The owner's salon logo on the management hero: [SalonLogo] + the camera
/// [PhotoEditBadge]; the whole mark is the tap target. Keeps its upload
/// controller alive for its own life.
class SalonLogoEditor extends ConsumerStatefulWidget {
  const SalonLogoEditor({
    super.key,
    required this.salonId,
    required this.diameter,
    required this.monogram,
    required this.imageUrl,
  });

  final String salonId;
  final double diameter;
  final String? monogram;

  /// The current logo (`Salon.avatarUrl`), patched in place on upload.
  final String? imageUrl;

  @override
  ConsumerState<SalonLogoEditor> createState() => _SalonLogoEditorState();
}

class _SalonLogoEditorState extends ConsumerState<SalonLogoEditor> {
  MediaEditActions get _actions {
    final double d = SalonLogo.imageDiameter(widget.diameter);
    return salonImageEditActions(
      host: this,
      salonId: widget.salonId,
      slot: SalonImageSlot.logo,
      decodeSize: Size(d, d),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AvatarUploadState upload = ref.watch(
      salonImageUploadControllerProvider(widget.salonId, SalonImageSlot.logo),
    );
    final _UploadVisuals v = _visualsFor(
      upload,
      circular: true,
      onRetry: () => _actions.retry(),
    );
    final double? progress = upload is AvatarUploading ? upload.progress : null;
    void onTap() => _actions.tap(widget.imageUrl);
    return Semantics(
      button: true,
      enabled: !v.busy,
      label: AppLocalizations.of(context).salonLogoEditLabel,
      value: progress != null
          ? UploadProgressSpinner.percentLabel(progress)
          : null,
      child: GestureDetector(
        key: const Key('salon-logo-editor'),
        behavior: HitTestBehavior.opaque,
        onTap: v.busy ? null : onTap,
        child: SalonLogo(
          diameter: widget.diameter,
          monogram: widget.monogram,
          imageUrl: widget.imageUrl,
          previewFile: v.preview,
          overlay: v.overlay,
          editBadge: PhotoEditBadge(
            size: kSalonLogoBadgeSize,
            badgeKey: const Key('salon-logo-edit-badge'),
            busy: v.busy,
            onTap: onTap,
          ),
        ),
      ),
    );
  }
}

/// The owner's cover: [SalonCover] with the just-picked preview and the
/// upload overlays. Keeps the cover controller alive for its own life; the
/// tap target is [SalonCoverEditButton] in the cover's control row.
class SalonCoverEditor extends ConsumerStatefulWidget {
  const SalonCoverEditor({
    super.key,
    required this.salonId,
    required this.height,
    required this.topInset,
    required this.imageUrl,
  });

  final String salonId;
  final double height;
  final double topInset;

  /// The current cover (`Salon.coverImageUrl`), patched in place on upload.
  final String? imageUrl;

  @override
  ConsumerState<SalonCoverEditor> createState() => _SalonCoverEditorState();
}

class _SalonCoverEditorState extends ConsumerState<SalonCoverEditor> {
  @override
  Widget build(BuildContext context) {
    final AvatarUploadState upload = ref.watch(
      salonImageUploadControllerProvider(widget.salonId, SalonImageSlot.cover),
    );
    final _UploadVisuals v = _visualsFor(
      upload,
      circular: false,
      showMessage: true,
      onRetry: () => salonImageEditActions(
        host: this,
        salonId: widget.salonId,
        slot: SalonImageSlot.cover,
        decodeSize: Size(MediaQuery.sizeOf(context).width, widget.height),
      ).retry(),
    );
    return SalonCover(
      key: const Key('salon-cover-editor'),
      height: widget.height,
      topInset: widget.topInset,
      imageUrl: widget.imageUrl,
      previewFile: v.preview,
      overlay: v.overlay,
    );
  }
}

/// The owner's cover camera control — a [CoverIconButton] in the cover's
/// top-right control row (beside the bell and settings): the cover's lower
/// edge is overlapped by the hero card by a content-dependent amount, so a
/// corner badge there could be hidden; the control row is always clear.
class SalonCoverEditButton extends ConsumerStatefulWidget {
  const SalonCoverEditButton({
    super.key,
    required this.salonId,
    required this.coverHeight,
    required this.imageUrl,
  });

  final String salonId;
  final double coverHeight;
  final String? imageUrl;

  @override
  ConsumerState<SalonCoverEditButton> createState() =>
      _SalonCoverEditButtonState();
}

class _SalonCoverEditButtonState extends ConsumerState<SalonCoverEditButton> {
  @override
  Widget build(BuildContext context) {
    return CoverIconButton(
      key: const Key('salon-cover-edit'),
      icon: Icons.photo_camera_outlined,
      iconColor: BrandColors.accentDeep,
      semanticLabel: AppLocalizations.of(context).salonCoverEditLabel,
      onTap: () => salonImageEditActions(
        host: this,
        salonId: widget.salonId,
        slot: SalonImageSlot.cover,
        decodeSize: Size(MediaQuery.sizeOf(context).width, widget.coverHeight),
      ).tap(widget.imageUrl),
    );
  }
}
