// Phase 13.7 — BEAUTY TIMELINE section.
// Phase 110 (13.9) — data-wired; `onSeeAll` widened to optional (no timeline
// page exists — see below) and tile tap now opens «Деталі запису» when a row
// carries a bookingId; `_categoryIcon` now prefers the backend's stable
// `categoryKey`.
//
// Title "BEAUTY TIMELINE" is an untranslated English brand constant (locked
// product decision). The section label itself uses [HubSectionTitle] with
// `literal: true` for wider tracking.
//
// Category icons are produced by the local [_categoryIcon] helper (mirrors
// the preview's sample icons) — see that function's doc for why this stays a
// PRIVATE, in-file mapper rather than a shared `categoryIconFor` (two other
// screens, `booking_card.dart` and `favorites_filter.dart`, already carry
// their own drifted private mappers; reconciling all three is a separate,
// out-of-scope decision — see `favorites_filter.dart`'s header).
//
// Ported from `_TimelineSection` + `_DottedLine` in the approved preview.
// Timeline rail height is locked at 108dp (preview value).
//
// NO "SEE ALL" DESTINATION: there is no standalone timeline page and none is
// planned ("there shouldn't be new page, just railway on home client profile
// page" — locked product decision). [onSeeAll] is therefore OPTIONAL
// (`VoidCallback?`); the trailing link only renders when a caller supplies
// one, so wiring real data (which used to leave a dead debug-log-only tap
// target behind) never ships a visible, tappable no-op control.

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
    this.onSeeAll,
    this.onOpenBooking,
  });

  final List<TimelineEntry> entries;

  /// Optional — see the file header. Null renders no trailing link.
  final VoidCallback? onSeeAll;

  /// Optional callback fired when a tile whose [TimelineEntry.bookingId] is
  /// non-null/non-empty is tapped, with that id. Null (the default) makes
  /// tiles non-interactive, matching this rail's "read-only" phase decision
  /// unless a caller opts in.
  final ValueChanged<String>? onOpenBooking;

  static const double _railHeight = 108;
  static const double _medallion = 64;

  // Tile width. Also given as a TIGHT width to [_TimelineNode] (via the
  // SizedBox below) so its inner Column always centres the 64dp circle at a
  // constant x-origin, regardless of caption length — see the connector
  // maths in `left:` below, which assumes exactly that. Without the tight
  // width, a loose Stack-imposed constraint lets the Column shrink to its
  // widest child (the caption Text), which drifts the circle's x-origin with
  // caption length and desyncs it from the hard-coded connector position.
  static const double _tileWidth = 84;

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
          trailing: entries.isEmpty || onSeeAll == null
              ? null
              : HubSeeAllLink(
                  key: const Key('timeline_see_all'),
                  label: l10n.homeHubTimelineSeeAll,
                  onTap: onSeeAll!,
                ),
        ),
        const SizedBox(height: VelvetSpacing.md),
        if (entries.isEmpty)
          // Width is pinned to the full content width on purpose. The outer
          // Column uses CrossAxisAlignment.start, which hands its children
          // LOOSE width constraints, so an unpinned HubFlatCard would shrink to
          // its widest child — the message Text. That made this card render
          // narrower than the favourites empty state purely because
          // `homeHubTimelineEmpty` is a shorter string. Pinning the width keeps
          // the two sections aligned regardless of future l10n copy edits.
          SizedBox(
            width: double.infinity,
            child: HubFlatCard(
              key: const Key('timeline_empty'),
              padding: const EdgeInsets.symmetric(
                horizontal: VelvetSpacing.md,
                vertical: VelvetSpacing.lg,
              ),
              child: HubEmptyState(
                icon: Icons.history_rounded,
                message: l10n.homeHubTimelineEmpty,
              ),
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
                  width: _tileWidth,
                  child: Stack(
                    // The connector below deliberately overhangs this tile's
                    // right edge (negative `right`) so it reaches the NEXT
                    // tile's circle instead of stopping short at the tile
                    // boundary — see the Positioned's own comment. Clip.none
                    // lets that overhang paint; it lands in the next tile's
                    // local x 0..10, which is empty padding before that
                    // tile's own circle, so nothing is obscured or doubled.
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      if (!isLast)
                        // Circle occupies local x [10, 74] (centred 64dp
                        // medallion in the 84dp tight-width tile — see
                        // _tileWidth's doc comment). The connector starts
                        // exactly at the circle's right edge (74, i.e.
                        // `_tileWidth / 2 + _medallion / 2`) so none of it
                        // renders under the circle's translucent fill, and
                        // extends to local x 94 (`right: -10`, i.e.
                        // `-(_tileWidth - _medallion) / 2`) — the next
                        // tile's circle left edge — so the dotted line
                        // spans the full inter-circle gap instead of
                        // stopping 10dp short at the tile boundary.
                        const Positioned(
                          left: _tileWidth / 2 + _medallion / 2,
                          right: -(_tileWidth - _medallion) / 2,
                          top: _medallion / 2 - 1,
                          child: _DottedLine(),
                        ),
                      // Tight width so _TimelineNode's inner Column centres
                      // the circle at a constant x-origin instead of at the
                      // caption Text's (variable) intrinsic width — see
                      // _tileWidth's doc comment.
                      SizedBox(
                        width: _tileWidth,
                        child: _TimelineNode(
                          entry: entry,
                          onOpen: onOpenBooking,
                        ),
                      ),
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
  const _TimelineNode({required this.entry, this.onOpen});

  final TimelineEntry entry;

  /// See [BeautyTimelineSection.onOpenBooking]. Only invoked when
  /// [TimelineEntry.bookingId] is non-null and non-empty (checked below) —
  /// [onOpen] itself never has to re-guard a blank id.
  final ValueChanged<String>? onOpen;

  static final TextStyle _categoryStyle = VelvetText.bodyStrong12;
  static final TextStyle _dateStyle = VelvetText.body11;

  @override
  Widget build(BuildContext context) {
    final String? bookingId = entry.bookingId;
    final bool isTappable =
        onOpen != null && bookingId != null && bookingId.isNotEmpty;

    final Widget content = Column(
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
            _categoryIcon(entry),
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

    if (!isTappable) return content;
    return InkWell(
      key: Key('timeline_tile_$bookingId'),
      borderRadius: BorderRadius.circular(VelvetRadii.card),
      onTap: () => onOpen!(bookingId),
      child: content,
    );
  }
}

/// Resolves a representative Material icon for one timeline tile.
///
/// Prefers [TimelineEntry.categoryKey] (the backend's stable uppercase slug,
/// e.g. `"NAIL_SERVICE"` — matched against the current platform-category
/// taxonomy, `platform_categories.name` /
/// `V74__seed_taxonomy_platform_categories.sql`) when the row carries one.
/// Falls back to keyword-matching [TimelineEntry.category] (the Ukrainian
/// display name) for rows with no key — e.g. pre-Phase-110 callers/tests.
///
/// This stays a PRIVATE, in-file mapper — see the file header for why a
/// shared `categoryIconFor` is deliberately not introduced by this change.
IconData _categoryIcon(TimelineEntry entry) {
  final String? key = entry.categoryKey;
  if (key != null && key.isNotEmpty) {
    final String upper = key.toUpperCase();
    if (upper.contains('NAIL') ||
        upper.contains('MANICURE') ||
        upper.contains('PEDICURE') ||
        upper.contains('PODOLOGY')) {
      return Icons.front_hand_rounded;
    }
    if (upper.contains('LASH')) return Icons.auto_awesome_rounded;
    if (upper.contains('BROW')) return Icons.remove_red_eye_rounded;
    if (upper.contains('HAIR') ||
        upper.contains('BARBER') ||
        upper.contains('BEARD') ||
        upper.contains('SHAV') ||
        upper.contains('TRICHOLOGY')) {
      return Icons.content_cut_rounded;
    }
    if (upper.contains('COSMETOLOGY') ||
        upper.contains('AESTHETIC') ||
        upper.contains('LASER') ||
        upper.contains('INJECTION')) {
      return Icons.face_retouching_natural_rounded;
    }
    if (upper.contains('MAKEUP')) return Icons.brush_rounded;
    if (upper.contains('MASSAGE')) return Icons.spa_rounded;
    // Any other/unknown key (e.g. "OTHER", "UNKNOWN") falls through to the
    // name-based matcher below rather than defaulting here, so a row that
    // also carries a categoryName still gets its best-effort keyword match.
  }
  return _categoryIconFromName(entry.category);
}

/// Maps a category name (Ukrainian) to a representative Material icon.
/// [_categoryIcon]'s fallback for rows with no `categoryKey`.
IconData _categoryIconFromName(String category) {
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
