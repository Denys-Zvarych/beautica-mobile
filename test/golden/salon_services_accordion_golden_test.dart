// mobile-qa gap-closure (2026-08-26) — first pixel coverage for
// `_SalonCategoryHeader`'s 20dp leading category glyph, added to
// `salon_services_accordion.dart` (the public "Послуги" tab on the salon
// profile screen).
//
// ── WHY A WIDGET-LEVEL GOLDEN THROUGH THE PUBLIC ENTRY POINT ───────────────
//
// `grep -a -rln "SalonServicesAccordion\|_SalonCategoryHeader" test/golden/`
// returned NO hits before this file. `_SalonCategoryHeader` is a private
// class (`_`-prefixed) — per this repo's private-widget rule (CLAUDE.md
// "Implementation Rules") it is PROMOTED (moved, un-prefixed, call site
// rewired) rather than forked/copied out into a test-only public wrapper.
// Promoting it is a separate, larger change than this icon gap-closure
// warrants, so this golden drives it through [SalonServicesAccordion] — the
// widget's actual public entry point, and the SAME boundary a real screen
// uses — rather than reaching into the private class.
//
// ── MUTATION PROOF this golden actually sees the icon layer ───────────────
//
// Acceptance per mobile-qa brief: NOT a green test — the baseline hash must
// move when the icon is removed. Verified by mutation
// (`salon_services_accordion.dart`'s `_SalonCategoryHeader.build`,
// `iconAsset == null ? null : AppIcon(...)` branch temporarily forced to
// unconditional `null` — i.e. every header, categorised or not, renders the
// empty 20×20 slot) and regenerating
// (`flutter test --update-goldens test/golden/salon_services_accordion_golden_test.dart`):
//
//   salon_services_accordion_360_1x    original sha256 8660a1100b4ce6f90bea55fe50305a8cda6c0ff15aa37db491b8be654b891bd1
//   salon_services_accordion_360_1x    mutated  sha256 84662072ac0a11dc62ca90da6c4188b674c09140b187fcff5fba15f88edf4b86
//   salon_services_accordion_360_1_3x  original sha256 6d2be8817cc03495e44c2dc1bbb4d6534f23b16e6fa2b31fccd8d3e3bae64353
//   salon_services_accordion_360_1_3x  mutated  sha256 02bf96990d9b3f31fae83d6b18e5651573eb6068947df019801e9e3bb8b16ab4
//
// Mutation reverted from a pre-edit `cp` backup (md5-confirmed identical to
// the pre-mutation source); regenerating again from the reverted source
// reproduced the ORIGINAL PNG bytes exactly (`sha256sum` clean) — the
// committed baselines above are the original, un-mutated render.
//
// Fixture: two categories via [SalonServicesAccordion] —
//   • "Манікюр" (`category: 'NAIL_SERVICE'`) — categorised, glyph present,
//     one service, initially EXPANDED (index 0 — matches the widget's own
//     "first category open on load" contract).
//   • "Без категорії" (`category: ''` — the widget only ever receives a
//     non-blank slug in production per [SalonServiceCategoryEntry.category]'s
//     own doc, but `categoryIconOrNullFor` still must treat an empty string
//     defensively as "no icon", and this is the one place in the codebase
//     that can pin that) — uncategorised, glyph ABSENT, one service,
//     initially collapsed (index 1). MUST render the empty same-size slot,
//     label still starting at the same left edge as the iconed header.

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:beautica_mobile/features/salon/presentation/widgets/salon_services_accordion.dart';
import 'package:flutter/material.dart';

import 'helpers/golden_pump.dart';

const List<SalonServiceCategoryEntry> _fixtureCategories =
    <SalonServiceCategoryEntry>[
      SalonServiceCategoryEntry(
        category: 'NAIL_SERVICE',
        displayName: 'Манікюр',
        count: 1,
        services: <SalonCatalogService>[
          SalonCatalogService(
            id: 'svc-1',
            name: 'Манікюр з покриттям',
            durationLabel: '1 год',
            priceDisplay: '500 ₴',
            category: 'NAIL_SERVICE',
          ),
        ],
      ),
      SalonServiceCategoryEntry(
        category: '',
        displayName: 'Без категорії',
        count: 1,
        services: <SalonCatalogService>[
          SalonCatalogService(
            id: 'svc-2',
            name: 'Інша послуга',
            durationLabel: '30 хв',
            priceDisplay: '250 ₴',
          ),
        ],
      ),
    ];

Widget _host(double width) => ColoredBox(
  color: BrandColors.base,
  child: SizedBox(
    width: width,
    child: const SalonServicesAccordion(categories: _fixtureCategories),
  ),
);

void main() {
  const double width = 360;

  for (final double scale in kGoldenTextScales) {
    goldenTest(
      'salon services accordion — categorised + uncategorised header '
      '${width.toInt()}dp x$scale',
      fileName: 'salon_services_accordion_${widthScaleSuffix(width, scale)}',
      constraints: BoxConstraints.tight(const Size(width, 420)),
      textScaleFactor: scale,
      pumpWidget: goldenPumpWidget(width: width),
      builder: () => _host(width),
    );
  }
}
