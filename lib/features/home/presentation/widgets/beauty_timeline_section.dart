// Phase 13.7 — BEAUTY TIMELINE section.
// Phase 110 (13.9) — data-wired; `onSeeAll` widened to optional (no timeline
// page exists — see below) and tile tap now opens «Деталі запису» when a row
// carries a bookingId.
// Phase 110 Part 2 — real category SVG icons + two-line caption. Category
// glyphs now come from the shared `categoryIconFor` resolver
// (`lib/core/icons/category_icons.dart`) instead of a private in-file
// Material-icon mapper — this rail is that resolver's first caller; see its
// file header for the reuse contract (`booking_card.dart` and
// `favorites_filter.dart` keep their own private mappers for now — migrating
// them is a separate, out-of-scope visual review). Tile width/rail height
// grew (84→100 / 108→118) and the caption gained a second line to stop
// «Ін'єкційна косметологія» truncating to «Ін'єкц…».
//
// MEDALLION ICON SIZE — CORRECTED HISTORY (2026-08-26)
// The `_TimelineNode` medallion `Container` (64×64) had no `alignment`, so
// its tight `BoxConstraints` forced the child `AppIcon` to render at 64dp
// regardless of the `size:` value passed. That means every earlier size —
// 26, then 36, then 32 — was inert; the icon actually painted at 64dp the
// whole time. `alignment: Alignment.center` (added below, do not remove)
// finally made `size:` take effect, and the icon is now set to 48dp — a
// deliberate 25% reduction from the 64dp the user was actually looking at,
// leaving an 8dp inset inside the 64dp medallion.
//
// Title "BEAUTY TIMELINE" is an untranslated English brand constant (locked
// product decision). The section label itself uses [HubSectionTitle] with
// `literal: true` for wider tracking.
//
// Ported from `_TimelineSection` + `_DottedLine` in the approved preview.
// Timeline rail height was 108dp (preview value); see [_railHeight]'s doc
// comment for the Part 2 resize.
//
// NO "SEE ALL" DESTINATION: there is no standalone timeline page and none is
// planned ("there shouldn't be new page, just railway on home client profile
// page" — locked product decision). [onSeeAll] is therefore OPTIONAL
// (`VoidCallback?`); the trailing link only renders when a caller supplies
// one, so wiring real data (which used to leave a dead debug-log-only tap
// target behind) never ships a visible, tappable no-op control.

import 'package:flutter/material.dart';

import '../../../../core/icons/app_icon.dart';
import '../../../../core/icons/category_icons.dart';
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

  // Phase 110 Part 2: 108 → 118. Grown alongside [_tileWidth] and the
  // caption's `maxLines: 1` → `2` to fit the two-line category caption
  // without shrinking the fixed-height rail's headroom for scaled text — see
  // [_scaledTextHeadroom].
  static const double _railHeight = 118;
  static const double _medallion = 64;

  // Tile width. Also given as a TIGHT width to [_TimelineNode] (via the
  // SizedBox below) so its inner Column always centres the 64dp circle at a
  // constant x-origin, regardless of caption length — see the connector
  // maths in `left:` below, which assumes exactly that. Without the tight
  // width, a loose Stack-imposed constraint lets the Column shrink to its
  // widest child (the caption Text), which drifts the circle's x-origin with
  // caption length and desyncs it from the hard-coded connector position.
  //
  // Phase 110 Part 2: 84 → 100. A `TextPainter` probe found «косметологія»
  // (the longest unbreakable token across the 20 category display names) is
  // the binding constraint: 84dp truncated at both text scales
  // («Ін'єкційна косметологія» → «Ін'єкц…»); 100dp holds at scale 1.0 and
  // degrades gracefully at the 1.3 accessibility cap; 112dp holds 1.3 too but
  // drops the rail from 3.5 to 3.1 visible tiles, so 100dp was chosen as the
  // best fit/density trade-off. The connector maths below is expressed
  // entirely in terms of [_tileWidth] and [_medallion], so this resize needed
  // no connector change — verified by re-deriving both endpoints (see the
  // Positioned's own comment).
  static const double _tileWidth = 100;

  // Extra height to absorb scaled text below the fixed medallion. Phase 110
  // Part 2: the caption grew from 1 line to 2 (see the Text below), so the
  // headroom formula grew from a flat `textLinesBase` constant to
  // `11 + 12 * captionLines` — 11dp for the date line plus 12dp per category
  // caption line — so a 2-line caption gets proportionally more scaled-text
  // cushion than the old fixed 23dp assumed 1 line of category text.
  static double _scaledTextHeadroom(
    BuildContext context, {
    int captionLines = 2,
  }) {
    final double scale = MediaQuery.textScalerOf(context).scale(1.0);
    final double textLinesBase = 11.0 + 12.0 * captionLines;
    return ((scale - 1.0).clamp(0.0, 0.3)) * textLinesBase + 6;
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
                        // Circle occupies local x [18, 82] (centred 64dp
                        // medallion in the 100dp tight-width tile — see
                        // _tileWidth's doc comment). The connector starts
                        // exactly at the circle's right edge (82, i.e.
                        // `_tileWidth / 2 + _medallion / 2`) so none of it
                        // renders under the circle's translucent fill, and
                        // extends to local x 118 (`right: -18`, i.e.
                        // `-(_tileWidth - _medallion) / 2`) — the next
                        // tile's circle left edge — so the dotted line
                        // spans the full inter-circle gap instead of
                        // stopping 18dp short at the tile boundary.
                        //
                        // Phase 110 Part 2 re-derivation (84→100 tile resize):
                        // left = 100/2 + 64/2 = 82; right = -(100-64)/2 = -18,
                        // whose resolved right-edge (stackWidth − right =
                        // 100 − (−18) = 118) still lands exactly on the next
                        // tile's circle left edge (100 + 18 = 118) — both
                        // endpoints are formulas in [_tileWidth]/[_medallion],
                        // so the resize needed no edit here, only re-checking.
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
          // `alignment` is required here, not cosmetic: without it Container
          // has no Align layer, so its tight 64×64 BoxConstraints pass
          // straight through and force ANY child — including AppIcon's own
          // `size:`-driven SizedBox — to render at 64×64 regardless of the
          // value passed. Confirmed via `tester.getSize()`: `size: 32` with
          // no `alignment` measured 64×64; adding `alignment: Alignment
          // .center` measured the intended 32×32 (mobile-qa, 2026-08-26,
          // Phase 110 Part 2 gap-closure — this is what actually explained
          // the golden byte-identical finding, not an SVG-decode timing
          // issue). Do not remove.
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: BrandColors.white.withValues(alpha: 0.5),
            shape: BoxShape.circle,
            border: Border.all(
              color: BrandColors.accent.withValues(alpha: 0.55),
              width: 1.4,
            ),
          ),
          child: AppIcon(
            // Phase 110 Part 2: real SVG via the shared categoryIconFor
            // resolver, replacing the retired Material-icon private mapper.
            categoryIconFor(
              categoryKey: entry.categoryKey,
              categoryName: entry.category,
            ),
            // 48dp, inset within the 64dp medallion. The 26/36/32 values
            // that preceded this never actually rendered — see the file
            // header for why (the Container had no `alignment`, so every
            // earlier size was clobbered to 64dp regardless of this field).
            size: 48,
            color: BrandColors.accentDeep,
          ),
        ),
        const SizedBox(height: VelvetSpacing.sm - 2),
        Text(
          entry.category,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
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

// Phase 110 Part 2: the private `_categoryIcon`/`_categoryIconFromName`
// Material-icon mappers that used to live here are RETIRED — category
// glyphs now come from the shared `categoryIconFor` resolver
// (`lib/core/icons/category_icons.dart`), called directly above in
// [_TimelineNode.build]. See that file's header for the resolver contract.

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
