// The attachment tray — the support screen's signature element. It communicates
// every backend constraint through the UI itself:
//   • a "+" add tile that disables at maxFiles,
//   • a "n/maxFiles" counter,
//   • per-file extruded chips with a type glyph, name, size and remove well,
//   • a thin neumorphic size meter that fills camel and flips to the error tone
//     once the total budget (5 MB) is exceeded.
//
// Design source: `docs/signup-designs/ContactSupport/lib/widgets/
// attachment_tray.dart` — ported 1:1, swapping VelvetColors → BrandColors,
// the mock Attachment → the domain [SupportAttachment], and all copy to l10n.

import 'dart:ui' show PathMetric;

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/features/support/domain/support_attachment.dart';
import 'package:beautica_mobile/features/support/presentation/support_format.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// The attachment tray for the support-contact form.
class AttachmentTray extends StatelessWidget {
  const AttachmentTray({
    super.key,
    required this.attachments,
    required this.onAdd,
    required this.onRemove,
    required this.maxFiles,
    required this.maxTotalBytes,
  });

  final List<SupportAttachment> attachments;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final int maxFiles;
  final int maxTotalBytes;

  int get _totalBytes =>
      attachments.fold<int>(0, (int sum, SupportAttachment a) => sum + a.size);

  bool get _canAdd => attachments.length < maxFiles;
  bool get _overBudget => _totalBytes > maxTotalBytes;

  // Hoisted styles — never recompute per build.
  static final TextStyle _labelStyle = VelvetText.label();
  static final TextStyle _counterMuted = VelvetText.feedbackMutedSm;
  static final TextStyle _counterFull = VelvetText.feedbackAccentSm;
  static final TextStyle _hintStyle = VelvetText.feedbackMuted12w600;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bool full = attachments.length >= maxFiles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(l10n.contactSupportAttachmentsLabel, style: _labelStyle),
            const Spacer(),
            Text(
              '${attachments.length}/$maxFiles',
              style: full ? _counterFull : _counterMuted,
            ),
          ],
        ),
        const SizedBox(height: VelvetSpacing.sm + 2),
        _AddTile(
          key: const Key('support-add-attachment'),
          enabled: _canAdd,
          onTap: _canAdd ? onAdd : null,
        ),
        if (attachments.isNotEmpty) ...<Widget>[
          const SizedBox(height: VelvetSpacing.sm + 4),
          for (int i = 0; i < attachments.length; i++) ...<Widget>[
            _AttachmentChip(
              key: Key('support-attachment-chip-$i'),
              removeKey: Key('support-attachment-remove-$i'),
              attachment: attachments[i],
              onRemove: () => onRemove(i),
            ),
            if (i != attachments.length - 1)
              const SizedBox(height: VelvetSpacing.sm),
          ],
          const SizedBox(height: VelvetSpacing.md),
          _SizeMeter(
            totalBytes: _totalBytes,
            maxTotalBytes: maxTotalBytes,
            overBudget: _overBudget,
          ),
        ],
        const SizedBox(height: VelvetSpacing.sm + 2),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            l10n.contactSupportAttachmentsHint(maxFiles),
            style: _hintStyle,
          ),
        ),
      ],
    );
  }
}

/// The "add attachment" affordance — a recessed dashed well with an extruded
/// "+" pillow, reading as a slot waiting to be filled.
class _AddTile extends StatelessWidget {
  const _AddTile({super.key, required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback? onTap;

  static final TextStyle _titleStyle = VelvetText.bodyStrong14;
  static final TextStyle _subtitleStyle = VelvetText.feedbackMuted12w600;

  static const BoxDecoration _pillowDecoration = BoxDecoration(
    color: BrandColors.base,
    borderRadius: BorderRadius.all(Radius.circular(VelvetRadii.field)),
    boxShadow: VelvetShadows.extrudedSmall,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      enabled: enabled,
      label: l10n.contactSupportAddAttachment,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: GestureDetector(
          onTap: onTap,
          // Isolate the hand-drawn dashed border so sibling repaints (the
          // size-meter AnimatedContainer, chip add/remove) never force the
          // painter to re-rasterize. `_DashedBorderPainter.shouldRepaint`
          // already returns false for unchanged props.
          child: RepaintBoundary(
            child: CustomPaint(
              painter: const _DashedBorderPainter(
                color: BrandColors.faint,
                radius: VelvetRadii.field,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: VelvetSpacing.md,
                  vertical: VelvetSpacing.md,
                ),
                child: Row(
                  children: <Widget>[
                    Container(
                      height: 44,
                      width: 44,
                      decoration: _pillowDecoration,
                      child: const Icon(
                        Icons.add_rounded,
                        color: BrandColors.accent,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: VelvetSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            l10n.contactSupportAddAttachment,
                            style: _titleStyle,
                          ),
                          const SizedBox(height: 1),
                          Text(
                            enabled
                                ? l10n.contactSupportAddAttachmentSubtitle
                                : l10n.contactSupportAttachmentsLimitReached,
                            style: _subtitleStyle,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A single attached file rendered as a resting extruded chip.
class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({
    super.key,
    required this.removeKey,
    required this.attachment,
    required this.onRemove,
  });

  final Key removeKey;
  final SupportAttachment attachment;
  final VoidCallback onRemove;

  static const BoxDecoration _chipDecoration = BoxDecoration(
    color: BrandColors.base,
    borderRadius: BorderRadius.all(Radius.circular(VelvetRadii.field)),
    boxShadow: VelvetShadows.extrudedSmall,
  );

  static const BoxDecoration _removeWellDecoration = BoxDecoration(
    color: BrandColors.base,
    borderRadius: BorderRadius.all(Radius.circular(10)),
    boxShadow: <BoxShadow>[
      BoxShadow(
        color: BrandColors.shadowLightStrong,
        offset: Offset(-2, -2),
        blurRadius: 4,
      ),
      BoxShadow(
        color: BrandColors.shadowDarkButton,
        offset: Offset(2, 2),
        blurRadius: 4,
      ),
    ],
  );

  static final TextStyle _nameStyle = VelvetText.bodyStrong14;
  static final TextStyle _metaStyle = VelvetText.feedbackMuted12w600;

  // Precomputed glyph-tile tints (tone @ 12% alpha), one per kind — never
  // recompute the withValues blend per build.
  static final Color _pdfTint = BrandColors.error.withValues(alpha: 0.12);
  static final Color _imageTint = BrandColors.accentDeep.withValues(
    alpha: 0.12,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bool isPdf = attachment.kind == SupportAttachmentKind.pdf;
    final Color tone = isPdf ? BrandColors.error : BrandColors.accentDeep;
    final Color tint = isPdf ? _pdfTint : _imageTint;
    final String size = formatBytes(attachment.size);
    return Semantics(
      label: '${attachment.name}, $size',
      child: DecoratedBox(
        decoration: _chipDecoration,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            VelvetSpacing.sm + 2,
            VelvetSpacing.sm + 2,
            VelvetSpacing.sm,
            VelvetSpacing.sm + 2,
          ),
          child: Row(
            children: <Widget>[
              // Type glyph — a small tinted tile, PDF vs image.
              Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isPdf ? Icons.picture_as_pdf_rounded : Icons.image_outlined,
                  size: 20,
                  color: tone,
                ),
              ),
              const SizedBox(width: VelvetSpacing.sm + 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      attachment.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _nameStyle,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${isPdf ? l10n.contactSupportKindPdf : l10n.contactSupportKindImage} · $size',
                      style: _metaStyle,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: VelvetSpacing.sm),
              Semantics(
                button: true,
                label: l10n.contactSupportRemoveAttachment(attachment.name),
                child: GestureDetector(
                  key: removeKey,
                  onTap: onRemove,
                  child: Container(
                    height: 32,
                    width: 32,
                    decoration: _removeWellDecoration,
                    child: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: BrandColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A thin inset track that fills camel as files accumulate, switching to the
/// error tone (and an over-budget caption) once the total budget is exceeded.
class _SizeMeter extends StatelessWidget {
  const _SizeMeter({
    required this.totalBytes,
    required this.maxTotalBytes,
    required this.overBudget,
  });

  final int totalBytes;
  final int maxTotalBytes;
  final bool overBudget;

  static final TextStyle _captionMuted = VelvetText.feedbackMutedSm;
  static final TextStyle _captionError = VelvetText.feedbackError12;

  // Meter fill — two fixed brand colors, keyed on over-budget. No per-build
  // recompute.
  static const Color _fillNormal = BrandColors.accent;
  static const Color _fillOver = BrandColors.error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final double fraction = (totalBytes / maxTotalBytes).clamp(0.0, 1.0);
    final Color fill = overBudget ? _fillOver : _fillNormal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 8,
            child: Stack(
              children: <Widget>[
                const DecoratedBox(
                  decoration: BoxDecoration(color: BrandColors.shadowDarkCard),
                  child: SizedBox.expand(),
                ),
                FractionallySizedBox(
                  widthFactor: fraction == 0 ? 0.001 : fraction,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    decoration: BoxDecoration(color: fill),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: VelvetSpacing.xs + 2),
        Row(
          children: <Widget>[
            Icon(
              overBudget ? Icons.warning_amber_rounded : Icons.cloud_outlined,
              size: 14,
              color: overBudget ? BrandColors.error : BrandColors.muted,
            ),
            const SizedBox(width: VelvetSpacing.xs + 2),
            Expanded(
              child: Text(
                overBudget
                    ? l10n.contactSupportSizeMeterOver
                    : l10n.contactSupportSizeMeterUsed(formatBytes(totalBytes)),
                style: overBudget ? _captionError : _captionMuted,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Dashed rounded border for the add tile — drawn by hand because Flutter has no
/// dashed [Border]. Kept faint so the tile reads as an empty slot.
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final RRect rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final Path path = Path()..addRRect(rrect);

    const double dash = 6;
    const double gap = 5;
    for (final PathMetric metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final double next = distance + dash;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
