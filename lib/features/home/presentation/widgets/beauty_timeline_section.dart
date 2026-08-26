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
// finally made `size:` take effect, and the icon was then set to 48dp — a
// deliberate 25% reduction from the 64dp the user was actually looking at,
// leaving an 8dp inset inside the 64dp medallion.
//
// MEDALLION MATCHED TO THE NAV-BAR SEARCH DISC (2026-08-26, same day,
// follow-up decision)
// The flat 64dp circle above was a DIFFERENT visual material from the
// client bottom-nav's elevated search disc (`client_bottom_nav.dart`
// `_CenterSearchButton`) — flat translucent fill + hairline border, vs. the
// disc's camel→mocha gradient + dual extruded shadow + bevel sheen. Locked
// product decision: "just make circles same as search button circle" — the
// medallion is now the search disc's exact treatment at the search disc's
// exact size (52dp, down from 64dp), consuming the SAME promoted tokens
// (`VelvetShadows.extrudedDiscAccent` / `VelvetGradients.accentDiscFace` /
// `VelvetGradients.accentDiscBevel` — see `core/theme/velvet_geometry.dart`)
// rather than a copy, per this repo's REUSE-FIRST rule. The icon shrank
// 48dp → 22dp alongside it: 22/52 is the search disc's OWN icon-to-disc
// ratio (its `searchFilled` glyph is 22dp inside the 52dp disc), applied
// here rather than re-deriving a new proportion, and its tint flipped dark
// (`accentDeep`) → cream (`BrandColors.white`, the on-accent-gradient text
// colour) because a dark glyph is invisible on the now-dark gradient face.
// `_railHeight` dropped 118 → 106 (exactly the 12dp the medallion shrank by
// — every other element in the tile's Column is unchanged) — see
// [_railHeight]'s own doc comment.
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
  //
  // 2026-08-26 (disc-match): 118 → 106. [_medallion] shrank 64 → 52 (12dp)
  // to match the nav-bar search disc's size (see the file header); nothing
  // else in the tile's Column changed, so the height budget drops by exactly
  // that 12dp. Verified overflow-free at the accessibility ceiling by
  // `test/features/home/presentation/home_hub_overflow_test.dart`'s 320×1.3
  // matrix cell, which still passes unchanged against this value.
  static const double _railHeight = 106;

  // 2026-08-26: 64 → 52, matching `client_bottom_nav.dart`'s
  // `_CenterSearchButton._centerSize` exactly — see the file header. The
  // connector geometry in the `Positioned` below is expressed entirely as
  // formulas in [_tileWidth]/[_medallion], so it re-derives automatically;
  // re-verified by measurement in `home_hub_overflow_test.dart`'s connector-
  // alignment group (circle x-origin now (100-52)/2 = 24.0, was 18.0).
  static const double _medallion = 52;

  // Tile width. Also given as a TIGHT width to [_TimelineNode] (via the
  // SizedBox below) so its inner Column always centres the 52dp circle at a
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
                        // Circle occupies local x [24, 76] (centred 52dp
                        // medallion in the 100dp tight-width tile — see
                        // _tileWidth's doc comment). The connector starts
                        // exactly at the circle's right edge (76, i.e.
                        // `_tileWidth / 2 + _medallion / 2`) so none of it
                        // renders under the circle's translucent fill, and
                        // extends to local x 124 (`right: -24`, i.e.
                        // `-(_tileWidth - _medallion) / 2`) — the next
                        // tile's circle left edge — so the dotted line
                        // spans the full inter-circle gap instead of
                        // stopping 24dp short at the tile boundary.
                        //
                        // Phase 110 Part 2 re-derivation (84→100 tile resize):
                        // left = 100/2 + 64/2 = 82; right = -(100-64)/2 = -18,
                        // whose resolved right-edge (stackWidth − right =
                        // 100 − (−18) = 118) still lands exactly on the next
                        // tile's circle left edge (100 + 18 = 118) — both
                        // endpoints are formulas in [_tileWidth]/[_medallion],
                        // so the resize needed no edit here, only re-checking.
                        //
                        // 2026-08-26 re-derivation (64→52 medallion,
                        // disc-match resize): left = 100/2 + 52/2 = 76;
                        // right = -(100-52)/2 = -24, whose resolved right
                        // edge (100 − (−24) = 124) still lands exactly on
                        // the next tile's circle left edge (100 + 24 = 124)
                        // — again both endpoints are formulas in
                        // [_tileWidth]/[_medallion], so only re-checking was
                        // needed, no edit.
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

  // Hoisted bevel DecoratedBox — matches `client_bottom_nav.dart`'s
  // `_CenterSearchButton._bevelSheen` (same promoted tokens, same rationale):
  // shared across every `_TimelineNode.build()` so the sheen layer is never
  // re-created per tile per rebuild — the rail paints 3-4 of these at once.
  static final Widget _bevelSheen = IgnorePointer(
    child: DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: VelvetGradients.accentDiscBevel,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final String? bookingId = entry.bookingId;
    final bool isTappable =
        onOpen != null && bookingId != null && bookingId.isNotEmpty;

    final Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          height: BeautyTimelineSection._medallion,
          width: BeautyTimelineSection._medallion,
          // `alignment` is required here, not cosmetic: without it Container
          // has no Align layer, so its tight BoxConstraints pass straight
          // through and force ANY child to render at the medallion's own
          // size regardless of what that child requests. Confirmed via
          // `tester.getSize()`: `size: 32` with no `alignment` measured
          // 64×64; adding `alignment: Alignment.center` measured the
          // intended 32×32 (mobile-qa, 2026-08-26, Phase 110 Part 2
          // gap-closure — this is what actually explained the golden
          // byte-identical finding, not an SVG-decode timing issue). Do not
          // remove.
          alignment: Alignment.center,
          // Same-material match with the client bottom-nav's elevated
          // search disc (`client_bottom_nav.dart` `_CenterSearchButton`) —
          // both consume the SAME promoted tokens, not private copies. See
          // the file header's "MEDALLION MATCHED TO THE NAV-BAR SEARCH
          // DISC" note.
          // NOT `shape: BoxShape.circle`: a blurred BoxShadow on a circle
          // shape rasterizes as a hard-edged square under Impeller-GLES (the
          // shadow's bounding box) — see
          // `test/features/booking/impeller_circle_shadow_guard_test.dart`
          // header. This repo's established remedy is an RRect at half the
          // box side, which is visually identical and routes through
          // Impeller's correct RRect blur path. Worse here than at the nav
          // bar this decoration is shared with: the rail paints 3-4 tiles
          // simultaneously inside a `Clip.none` Stack, so a square artifact
          // has room to bleed into the neighbouring tile.
          // NOT `const BoxDecoration`: `BorderRadius.circular` is not a
          // const constructor (`this.all(Radius.circular(radius))` is a
          // redirecting non-const ctor) — matches the established precedent
          // in `master_avatar_badge.dart`, which drops `const` for the same
          // reason.
          decoration: BoxDecoration(
            // 26 = half of `_medallion` (52dp), spelled as a literal per the
            // guard's own established convention (`master_avatar_badge.dart`).
            borderRadius: BorderRadius.circular(26),
            gradient: VelvetGradients.accentDiscFace,
            boxShadow: VelvetShadows.extrudedDiscAccent,
          ),
          // A plain `AppIcon` child would receive LOOSE constraints from the
          // `alignment` Align layer above and size to its own 22×22 intent —
          // fine for the icon itself, but the bevel sheen below needs to
          // fill the full 52×52 circle, which a loose-constrained Stack
          // would NOT do (it would shrink to its largest non-positioned
          // child, i.e. the 22×22 icon). This inner SizedBox re-establishes
          // a tight 52×52 box for the Stack without touching the outer
          // `alignment: Alignment.center` requirement above.
          child: SizedBox(
            height: BeautyTimelineSection._medallion,
            width: BeautyTimelineSection._medallion,
            child: Stack(
              children: <Widget>[
                Center(
                  child: AppIcon(
                    // Phase 110 Part 2: real SVG via the shared
                    // categoryIconFor resolver, replacing the retired
                    // Material-icon private mapper.
                    categoryIconFor(
                      categoryKey: entry.categoryKey,
                      categoryName: entry.category,
                    ),
                    // 22dp — the search disc's OWN icon-to-disc ratio
                    // (22/52) applied here, not a re-derived proportion. On
                    // a light-on-dark camel→mocha gradient the icon must be
                    // the light/cream tone (`BrandColors.white` is the
                    // on-accent-gradient cream, `#F5EDE0`) — the previous
                    // `accentDeep` (dark mocha) is invisible on this dark
                    // face.
                    size: 22,
                    color: BrandColors.white,
                  ),
                ),
                // Inner bevel sheen, matching the disc's — sells the
                // "physical pillow" read. `DecoratedBox`'s own
                // `shape: BoxShape.circle` clips the gradient to the circle
                // inscribed in this 52×52 box, so it never bleeds past the
                // medallion's own rounded edge.
                Positioned.fill(child: _bevelSheen),
              ],
            ),
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
