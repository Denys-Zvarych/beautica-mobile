// Phase 13.7 — BEAUTY TIMELINE section.
//
// Title "BEAUTY TIMELINE" is an untranslated English brand constant (locked
// product decision). The section label itself uses [HubSectionTitle] with
// `literal: true` for wider tracking.
//
// Category icons are produced by the local [_categoryIcon] helper (mirrors the
// preview's sample icons). A full `categoryIconFor(slug)` helper will land in
// Phase 13.3 (discovery); for now we map by category string.
//
// Ported from `_TimelineSection` + `_DottedLine` in the approved preview.
// Timeline rail height is locked at 108dp (preview value).

import 'package:flutter/material.dart';

import '../../../../core/theme/brand_colors.dart';
import '../../../../core/theme/velvet_geometry.dart';
import '../../../../core/theme/velvet_text.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/home_hub_models.dart';
import '../widgets/hub_widgets.dart';

/// BEAUTY TIMELINE horizontal rail or empty state.
class BeautyTimelineSection extends StatelessWidget {
  const BeautyTimelineSection({
    super.key,
    required this.entries,
    required this.onSeeAll,
  });

  final List<TimelineEntry> entries;
  final VoidCallback onSeeAll;

  static const double _railHeight = 108;
  static const double _medallion = 64;

  // Extra height to absorb scaled text below the fixed medallion. The two text
  // lines (~23dp at scale 1.0) gain ~30% at the clamped 1.3 cap; this adds that
  // delta (and a small cushion) so the rail tolerates large accessibility fonts
  // without redesigning the fixed-height layout.
  static double _scaledTextHeadroom(BuildContext context) {
    final double scale = MediaQuery.textScalerOf(context).scale(1.0);
    const double textLinesBase = 23; // category (12) + date (11)
    return ((scale - 1.0).clamp(0.0, 0.3)) * textLinesBase + 4;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        HubSectionTitle(
          // "BEAUTY TIMELINE" — intentionally untranslated (brand constant).
          // ignore: avoid_hardcoded_strings — locked brand literal
          title: 'BEAUTY TIMELINE',
          literal: true,
          trailing: entries.isEmpty
              ? null
              : HubSeeAllLink(
                  key: const Key('timeline_see_all'),
                  label: l10n.homeHubTimelineSeeAll,
                  onTap: onSeeAll,
                ),
        ),
        const SizedBox(height: VelvetSpacing.md),
        if (entries.isEmpty)
          HubFlatCard(
            key: const Key('timeline_empty'),
            padding: const EdgeInsets.symmetric(
              horizontal: VelvetSpacing.md,
              vertical: VelvetSpacing.lg,
            ),
            child: HubEmptyState(
              icon: Icons.history_rounded,
              message: l10n.homeHubTimelineEmpty,
            ),
          )
        else
          SizedBox(
            key: const Key('timeline_rail'),
            // Overflow-hardening: the medallion is fixed (64dp) but the two
            // text lines below it grow with the (clamped) text scale. Add the
            // scaled text headroom on top of the fixed base so the inner
            // Column never overflows at textScale up to 1.3.
            height: _railHeight + _scaledTextHeadroom(context),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              itemCount: entries.length,
              itemBuilder: (BuildContext context, int i) {
                final TimelineEntry entry = entries[i];
                final bool isLast = i == entries.length - 1;
                return SizedBox(
                  width: 84,
                  child: Stack(
                    children: <Widget>[
                      if (!isLast)
                        const Positioned(
                          left: 84 / 2 + _medallion / 2 - 4,
                          right: 0,
                          top: _medallion / 2 - 1,
                          child: _DottedLine(),
                        ),
                      _TimelineNode(entry: entry),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _TimelineNode extends StatelessWidget {
  const _TimelineNode({required this.entry});

  final TimelineEntry entry;

  static final TextStyle _categoryStyle = VelvetText.bodyStrong().copyWith(
    fontSize: 12,
  );
  static final TextStyle _dateStyle = VelvetText.body().copyWith(fontSize: 11);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          height: 64,
          width: 64,
          decoration: BoxDecoration(
            color: BrandColors.white.withValues(alpha: 0.5),
            shape: BoxShape.circle,
            border: Border.all(
              color: BrandColors.accent.withValues(alpha: 0.55),
              width: 1.4,
            ),
          ),
          child: Icon(
            _categoryIcon(entry.category),
            size: 26,
            color: BrandColors.accentDeep,
          ),
        ),
        const SizedBox(height: VelvetSpacing.sm - 2),
        Text(
          entry.category,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _categoryStyle,
        ),
        Text(
          entry.dateLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _dateStyle,
        ),
      ],
    );
  }
}

/// Maps a category name (Ukrainian) to a representative Material icon.
/// Phase 13.3 will expose a shared `categoryIconFor(slug)` utility;
/// until then, we do a simple switch on the category string.
IconData _categoryIcon(String category) {
  final lower = category.toLowerCase();
  if (lower.contains('манікюр') || lower.contains('педикюр')) {
    return Icons.front_hand_rounded;
  }
  if (lower.contains('бров')) return Icons.remove_red_eye_rounded;
  if (lower.contains('волос') || lower.contains('стриж')) {
    return Icons.content_cut_rounded;
  }
  if (lower.contains('масаж')) return Icons.spa_rounded;
  if (lower.contains('косметол') || lower.contains('обличч')) {
    return Icons.face_retouching_natural_rounded;
  }
  if (lower.contains('вій') || lower.contains('lash')) {
    return Icons.auto_awesome_rounded;
  }
  if (lower.contains('макіяж')) return Icons.brush_rounded;
  return Icons.spa_rounded;
}

// ---------------------------------------------------------------------------
// Dotted connector line between timeline medallions (ported verbatim)
// ---------------------------------------------------------------------------

class _DottedLine extends StatelessWidget {
  const _DottedLine();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 2,
      child: CustomPaint(
        painter: _DottedLinePainter(),
        size: const Size(double.infinity, 2),
      ),
    );
  }
}

class _DottedLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = BrandColors.faint
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const double dash = 2;
    const double gap = 4;
    double x = 0;
    final double y = size.height / 2;
    while (x < size.width) {
      canvas.drawLine(Offset(x, y), Offset(x + dash, y), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_DottedLinePainter oldDelegate) => false;
}
