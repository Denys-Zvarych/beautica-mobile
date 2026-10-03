// Phase 072 — the ONE upload-state vocabulary shared by every photo widget
// (NeumorphicAvatarEditor, ServicePhotoSlot): a cream veil + camel spinner while
// uploading, a cream veil + retry affordance when it failed. Fixing the look
// here fixes every photo surface.

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Opacity of the cream veil laid over a photo while it is uploading / failed.
const double kUploadVeilAlpha = 0.78;

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

/// Cream veil + centred [UploadProgressSpinner]; fills its parent.
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
          DecoratedBox(
            decoration: BoxDecoration(
              shape: circular ? BoxShape.circle : BoxShape.rectangle,
              color: BrandColors.white.withValues(alpha: kUploadVeilAlpha),
            ),
          ),
          Center(child: UploadProgressSpinner(progress: progress)),
        ],
      ),
    );
  }
}

/// Cream veil + a 48 dp retry target. [showMessage] adds the visible
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
          DecoratedBox(
            decoration: BoxDecoration(
              shape: circular ? BoxShape.circle : BoxShape.rectangle,
              color: BrandColors.white.withValues(alpha: kUploadVeilAlpha),
            ),
          ),
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
                      child: Icon(
                        Icons.refresh_rounded,
                        color: BrandColors.accentDeep,
                        size: 26,
                      ),
                    ),
                  ),
                ),
                if (showMessage)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: VelvetSpacing.md,
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
