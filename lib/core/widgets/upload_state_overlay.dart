// Phase 072 — the ONE upload-state vocabulary shared by every photo widget
// (NeumorphicAvatarEditor, ServicePhotoSlot): a camel spinner while uploading,
// a retry affordance when it failed. Fixing the look here fixes every photo
// surface.
//
// Phase 073 audit — the photo must stay clearly visible while it uploads / when
// it failed (it is the user's confirmation of WHAT they picked). So there is no
// full-coverage cream veil any more: just a faint espresso scrim over the photo
// plus a small opaque-ish cream chip behind the spinner / retry icon / message,
// which keeps them legible on light AND dark photos.

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Opacity of the faint espresso scrim laid over a photo while it is uploading
/// / failed (a hint of "busy"; the photo stays clearly visible).
const double kUploadScrimAlpha = 0.16;

/// Opacity of the cream chip behind the spinner / retry icon / message.
const double kUploadChipAlpha = 0.92;

/// Diameter of the chip behind the spinner / retry icon.
const double kUploadChipSize = 44;

/// Minimum interactive target (Material / WCAG 2.5.5).
const double kUploadRetryTarget = 48;

/// Camel progress ring. [progress] is 0..1; `null` — and `>= 1` — render the
/// INDETERMINATE ring.
///
/// `>= 1` is deliberately indeterminate: the transfer stream can reach 1.0
/// BEFORE the server answers, and the request may still fail, so a full ring
/// would claim "done" too early. The ring only goes away when the owner stops
/// passing a progress.
class UploadProgressSpinner extends StatelessWidget {
  const UploadProgressSpinner({super.key, this.progress});

  final double? progress;

  static const double _size = 30;

  /// Determinate value, or null while unknown / at the not-yet-confirmed 100%.
  static double? ringValue(double? progress) =>
      (progress == null || progress >= 1) ? null : progress.clamp(0.0, 1.0);

  /// Whole-percent text for the semantics `value`, capped at 99 so an
  /// unconfirmed upload never announces "100%".
  static String percentLabel(double progress) =>
      '${(progress.clamp(0.0, 1.0) * 100).floor().clamp(0, 99)}%';

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _size,
      width: _size,
      child: CircularProgressIndicator(
        strokeWidth: 3,
        color: BrandColors.accent,
        value: ringValue(progress),
      ),
    );
  }
}

/// Faint scrim over the photo, [UploadChip] shape.
class _UploadScrim extends StatelessWidget {
  const _UploadScrim({required this.circular});

  final bool circular;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      shape: circular ? BoxShape.circle : BoxShape.rectangle,
      color: BrandColors.text.withValues(alpha: kUploadScrimAlpha),
    ),
  );
}

/// Cream disc behind the spinner / retry icon so they read on any photo.
class UploadChip extends StatelessWidget {
  const UploadChip({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: BrandColors.white.withValues(alpha: kUploadChipAlpha),
    ),
    child: SizedBox(
      width: kUploadChipSize,
      height: kUploadChipSize,
      child: Center(child: child),
    ),
  );
}

/// Faint scrim + centred [UploadProgressSpinner] on a [UploadChip]; fills its
/// parent.
class UploadProgressOverlay extends StatelessWidget {
  const UploadProgressOverlay({
    super.key,
    this.progress,
    this.circular = false,
  });

  final double? progress;

  /// Clip the veil to a circle (avatar disc). The slot's veil is clipped by its
  /// own rounded rect.
  final bool circular;

  @override
  Widget build(BuildContext context) {
    // No Semantics here: the owning widget (avatar editor / photo slot) already
    // carries the label and exposes the percentage as the semantics `value`.
    // RepaintBoundary: the indeterminate ring repaints every frame; this keeps
    // that out of the photo / shadow ring beneath. Upload path only — callers
    // that never upload never build this widget.
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          _UploadScrim(circular: circular),
          Center(
            child: UploadChip(child: UploadProgressSpinner(progress: progress)),
          ),
        ],
      ),
    );
  }
}

/// Faint scrim + a 48 dp retry target on a [UploadChip]. [showMessage] adds the visible
/// «Не вдалося завантажити фото» line (room permitting — the avatar disc is too
/// small for it and carries it in semantics only).
class UploadFailedOverlay extends StatelessWidget {
  const UploadFailedOverlay({
    super.key,
    required this.onRetry,
    this.circular = false,
    this.showMessage = false,
  });

  final VoidCallback? onRetry;
  final bool circular;
  final bool showMessage;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          _UploadScrim(circular: circular),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Semantics(
                  button: true,
                  enabled: onRetry != null,
                  label: '${l10n.photoUploadFailed}. ${l10n.retryLabel}',
                  excludeSemantics: true,
                  child: GestureDetector(
                    key: const Key('upload-retry'),
                    behavior: HitTestBehavior.opaque,
                    onTap: onRetry,
                    child: const SizedBox(
                      height: kUploadRetryTarget,
                      width: kUploadRetryTarget,
                      child: Center(
                        child: UploadChip(
                          child: Icon(
                            Icons.refresh_rounded,
                            color: BrandColors.accentDeep,
                            size: 26,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (showMessage)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: VelvetSpacing.md,
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: BrandColors.white.withValues(
                          alpha: kUploadChipAlpha,
                        ),
                        borderRadius: BorderRadius.circular(VelvetRadii.field),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: VelvetSpacing.sm,
                          vertical: VelvetSpacing.xs,
                        ),
                        child: Text(
                          l10n.photoUploadFailed,
                          key: const Key('upload-failed-message'),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: VelvetText.bodyStrong(),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
