// mobile-qa gap-closure (2026-08-26) — first pixel coverage for
// [CatalogueCategoryHeader]'s 20dp leading category glyph, added to
// `service_catalogue_accordion.dart` (shared by the independent-master and
// salon booking flows via `CatalogueCategorySection`).
//
// ── WHY A WIDGET-LEVEL GOLDEN, NOT A SCREEN-LEVEL ONE ──────────────────────
//
// `grep -a -rln "CatalogueCategoryHeader" test/golden/` returned NO hits
// before this file — no golden anywhere renders this widget, so the icon had
// zero pixel coverage. [CatalogueCategoryHeader] is a public, standalone
// `StatelessWidget` (see `service_catalogue_accordion.dart`'s class doc) —
// the same shape `service_category_cards_golden_test.dart` and
// `category_rail_golden_test.dart` already established a precedent for: a
// shared render widget gets its OWN widget-level golden rather than being
// bolted onto a screen-level capture (`ServiceSelectorSheet` /
// `SalonServiceSelectionScreen` are both bottom-sheet/full-screen flows with
// their own separate, unrelated golden gaps — out of scope here).
//
// ── MUTATION PROOF this golden actually sees the icon layer ───────────────
//
// Acceptance per mobile-qa brief: NOT a green test — the baseline hash must
// move when the icon is removed. Verified by mutation
// (`service_catalogue_accordion.dart`'s `CatalogueCategoryHeader.build`,
// `iconAsset == null ? null : AppIcon(...)` branch temporarily forced to
// unconditional `null` — i.e. every header, categorised or not, renders the
// empty 20×20 slot) and regenerating:
//
//   catalogue_category_header_360_1x    original sha256 b4d44ed1336cd6c5a0dfbc0b434f7e3542bc931ee9fde1a53f02a708a502430f
//   catalogue_category_header_360_1x    mutated  sha256 3a790d14fc4a9578a46999cd01c57b663b769f784ed653b0df2c02e2daa5df94
//   catalogue_category_header_360_1_3x  original sha256 d4093062c1f378158935096b2b2b926354a8ac82bb701291c6a0016bf121dd5d
//   catalogue_category_header_360_1_3x  mutated  sha256 db0f571ab0282ec60990085fe3faf735a920abcbcd8e4aae161a63c15ae2c6ec
//
// Mutation reverted from a pre-edit `cp` backup (md5-confirmed identical to
// the pre-mutation source); regenerating again from the reverted source
// reproduced the ORIGINAL PNG bytes exactly (`sha256sum` clean) — the
// committed baselines above are the original, un-mutated render.
//
// Fixture: two headers stacked in a Column —
//   • "Манікюр" with `slug: 'NAIL_SERVICE'` — categorised, glyph present.
//   • "Без категорії" with `slug: null` — the uncategorized bucket. MUST
//     render the empty same-size slot, label still starting at the same
//     left edge as the iconed header (the slot is reserved unconditionally
//     — see the widget's own [CatalogueCategoryHeader.slug] doc).
// Both showCountBadges: true (the independent-master flow's configuration —
// the richer of the two configurations this header supports) with a non-zero
// selectedCount so the trailing badge row is also exercised.

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/service_catalogue_accordion.dart';
import 'package:flutter/material.dart';

import 'helpers/golden_pump.dart';

Widget _host(double width) => ColoredBox(
  color: BrandColors.base,
  child: SizedBox(
    width: width,
    child: const Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          CatalogueCategoryHeader(
            key: Key('golden-catalogue-header-categorised'),
            label: 'Манікюр',
            count: 3,
            selectedCount: 1,
            expanded: true,
            onTap: _noop,
            semanticsLabel: 'Манікюр, 3 послуги, 1 обрано, розгорнуто',
            verticalPadding: 14,
            slug: 'NAIL_SERVICE',
          ),
          SizedBox(height: 12),
          CatalogueCategoryHeader(
            key: Key('golden-catalogue-header-uncategorised'),
            label: 'Без категорії',
            count: 2,
            selectedCount: 0,
            expanded: false,
            onTap: _noop,
            semanticsLabel: 'Без категорії, 2 послуги, згорнуто',
            verticalPadding: 14,
            slug: null,
          ),
        ],
      ),
    ),
  ),
);

// Top-level so the `const` header constructors above can close over it.
void _noop() {}

void main() {
  const double width = 360;

  for (final double scale in kGoldenTextScales) {
    goldenTest(
      'catalogue category header — categorised + uncategorised ${width.toInt()}dp x$scale',
      fileName: 'catalogue_category_header_${widthScaleSuffix(width, scale)}',
      constraints: BoxConstraints.tight(const Size(width, 220)),
      textScaleFactor: scale,
      pumpWidget: goldenPumpWidget(width: width),
      builder: () => _host(width),
    );
  }
}
