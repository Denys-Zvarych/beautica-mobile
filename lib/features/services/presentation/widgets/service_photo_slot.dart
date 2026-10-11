// Phase 5.4 — Service cover-photo affordance.
//
// A reusable neumorphic inset 4:3 tile at the top of the service edit form.
// Transcribed 1:1 from the approved preview app at
// `docs/signup-designs/ServiceEditForm/lib/widgets/service_photo_slot.dart`.
//
// Two states:
//   - empty  → camera icon + "Додати фото" label + subtitle
//   - filled → warm camel gradient stand-in + "Змінити фото" overlay chip
//
// Tapping the slot is a placeholder for the real photo picker (Phase 9.x).
// The widget does not trigger any repository call; it simply calls [onTap].
//
// Accessibility: the Semantics wrapper announces the current state and marks
// the widget as a button so screen readers surface the tap affordance.

import 'dart:io' show File;

import 'package:beautica_mobile/core/media/beautica_image.dart';
import 'package:beautica_mobile/core/media/local_preview_image.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/core/widgets/upload_state_overlay.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// The service cover-photo affordance used in [ServiceEditScreen].
///
/// [imageUrl] — when null (and no [previewFile]) the empty state is shown.
/// [onTap] is called when the slot is tapped; pass null to disable interaction.
class ServicePhotoSlot extends StatefulWidget {
  const ServicePhotoSlot({
    super.key,
    this.imageUrl,
    this.onTap,
    this.previewFile,
    this.uploadProgress,
    this.uploadFailed = false,
    this.onRetry,
  });

  /// When non-null the filled state is rendered. The photo goes through the
  /// allow-listed `RemoteImage`; a disallowed host / failed fetch leaves the
  /// warm gradient stand-in visible.
  final String? imageUrl;

  /// Phase 072 — the just-picked local file, shown (via `LocalPreviewImage`, a
  /// `File`, never a URL) while it uploads. Takes precedence over [imageUrl].
  final File? previewFile;

  /// Phase 072 — upload progress 0.0–1.0. Non-null shows the cream veil + camel
  /// ring, hides the «Змінити фото» chip and ignores taps. At >= 1.0 the ring
  /// turns indeterminate (the server may still reject — 100% is not "done").
  final double? uploadProgress;

  /// Phase 072 — the upload failed: veil + message + 48 dp retry target.
  final bool uploadFailed;

  /// Invoked by the retry target shown when [uploadFailed].
  final VoidCallback? onRetry;

  /// Called when the user taps the slot. Pass null to disable interaction
  /// (e.g. while the form is submitting).
  final VoidCallback? onTap;

  /// A gentle 4:3 cover ratio reads as a listing thumbnail without dominating
  /// the form above the name field.
  static const double _aspect = 4 / 3;

  @override
  State<ServicePhotoSlot> createState() => _ServicePhotoSlotState();
}

class _ServicePhotoSlotState extends State<ServicePhotoSlot> {
  // Hoisted statics — avoids allocating new objects on every build().
  static final TextStyle _changePhotoLabelStyle = VelvetText.ctaSm;
  static final BoxDecoration _iconPillNormal = BoxDecoration(
    color: BrandColors.base,
    borderRadius: BorderRadius.circular(VelvetRadii.field),
    boxShadow: VelvetShadows.extrudedSmall,
  );
  static final BoxDecoration _iconPillPressed = BoxDecoration(
    color: BrandColors.base,
    borderRadius: BorderRadius.circular(VelvetRadii.field),
  );

  bool _pressed = false;

  bool get _uploading => widget.uploadProgress != null;
  bool get _interactive => widget.onTap != null && !_uploading;
  bool get _filled => widget.imageUrl != null || widget.previewFile != null;

  Widget _buildEmpty(AppLocalizations l10n) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        // Small extruded camel pillow cradling the camera glyph.
        Container(
          height: 56,
          width: 56,
          decoration: _pressed ? _iconPillPressed : _iconPillNormal,
          child: const Icon(
            Icons.add_a_photo_rounded,
            color: BrandColors.accent,
            size: 26,
          ),
        ),
        const SizedBox(height: VelvetSpacing.sm + 2),
        Text(l10n.servicePhotoAdd, style: VelvetText.subheading()),
      ],
    );
  }

  static const Widget _gradient = DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          BrandColors.accentLogo,
          BrandColors.accent,
          BrandColors.accentLatte,
        ],
        stops: <double>[0.0, 0.55, 1.0],
      ),
    ),
  );

  Widget _buildFilled(AppLocalizations l10n) {
    // Warm camel gradient: the base layer (the photo layers below use an EMPTY
    // fallback so the gradient is never painted twice — a second antialiased
    // pass at the rounded clip edge would move the no-photo baseline), so it
    // also shows while the photo is still loading and when the URL is
    // disallowed / the fetch fails. It stays under a loaded photo on purpose:
    // skipping it once the image has a frame needs the gradient inside the
    // photo's own clip, and that second clipped pass moves the url / uploading /
    // failed goldens by ~940 px (audit 072 cycle 1, finding 5 — escalated).
    final File? preview = widget.previewFile;
    final String? url = widget.imageUrl;
    // Decode bound from the known slot geometry (no LayoutBuilder): the slot is
    // at most screen-wide and 4:3. The photo layer is laid out TIGHT by the
    // expanding Stack, so these only size the decode, never the render.
    final double decodeW = MediaQuery.sizeOf(context).width;
    final double decodeH = decodeW / ServicePhotoSlot._aspect;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        _gradient,
        if (preview != null)
          LocalPreviewImage(
            file: preview,
            width: decodeW,
            height: decodeH,
            fallback: const SizedBox.shrink(),
          )
        else if (url != null)
          RemoteImage(
            url: url,
            width: decodeW,
            height: decodeH,
            borderRadius: BorderRadius.circular(VelvetRadii.card),
            excludeFromSemantics: true,
            fallback: const SizedBox.shrink(),
          ),
        // Bottom-anchored dark veil so the "Змінити фото" chip stays legible.
        const Align(
          alignment: Alignment.bottomCenter,
          child: FractionallySizedBox(
            heightFactor: 0.5,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Color(0x00000000), Color(0x59000000)],
                ),
              ),
            ),
          ),
        ),
        // "Змінити фото" chip, bottom-left — hidden while an upload is shown.
        if (!_uploading && !widget.uploadFailed)
          Positioned(
            left: VelvetSpacing.md,
            bottom: VelvetSpacing.md,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.photo_camera_rounded,
                  color: BrandColors.white,
                  size: 18,
                ),
                const SizedBox(width: VelvetSpacing.sm),
                Text(l10n.servicePhotoChange, style: _changePhotoLabelStyle),
              ],
            ),
          ),
      ],
    );
  }

  /// Layers the phase-072 upload veil over [content]; with no upload state it
  /// returns [content] untouched, so existing callers keep the identical tree.
  Widget _withUploadState(Widget content) {
    final double? progress = widget.uploadProgress;
    if (progress != null) {
      return Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // Upload path only: the photo is its own layer, so the ring's
          // per-frame repaint never re-rasterises it.
          RepaintBoundary(child: content),
          UploadProgressOverlay(progress: progress),
        ],
      );
    }
    if (widget.uploadFailed) {
      return Stack(
        fit: StackFit.expand,
        children: <Widget>[
          RepaintBoundary(child: content),
          UploadFailedOverlay(onRetry: widget.onRetry, showMessage: true),
        ],
      );
    }
    return content;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final double? uploadProgress = widget.uploadProgress;

    final Widget well = AspectRatio(
      aspectRatio: ServicePhotoSlot._aspect,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(VelvetRadii.card),
          // Camel ring frames the filled state so the image edge reads.
          border: Border.all(
            color: _filled
                ? BrandColors.accent.withValues(alpha: 0.35)
                : Colors.transparent,
            width: _filled ? 1.4 : 0,
          ),
        ),
        child: NeumorphicInset(
          radius: VelvetRadii.card,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(VelvetRadii.card),
            child: _withUploadState(
              Padding(
                padding: EdgeInsets.all(_filled ? 0 : VelvetSpacing.sm),
                child: _filled ? _buildFilled(l10n) : _buildEmpty(l10n),
              ),
            ),
          ),
        ),
      ),
    );

    return Semantics(
      button: true,
      enabled: _interactive,
      label: _uploading
          ? l10n.photoUploading
          : _filled
          ? l10n.servicePhotoChangeSemantics
          : l10n.servicePhotoAddSemantics,
      value: uploadProgress == null
          ? null
          : UploadProgressSpinner.percentLabel(uploadProgress),
      child: GestureDetector(
        onTapDown: _interactive ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: _interactive
            ? () => setState(() => _pressed = false)
            : null,
        onTapUp: _interactive
            ? (_) {
                setState(() => _pressed = false);
                widget.onTap!();
              }
            : null,
        child: AnimatedScale(
          scale: _pressed ? 0.99 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: well,
        ),
      ),
    );
  }
}
