// Phase 110 follow-up — mobile-qa gap-closure (2026-08-27): the open LOW from
// the previous QA pass on the SVG-per-category rollout for service-setup
// onboarding.
//
// WHY THIS FILE EXISTS
// ---------------------
// `CategoryChip` and `CategoryGroupHeader` (`service_setup_widgets.dart`)
// moved from a single uniform Material glyph (`Icons.spa_rounded`, same size
// for every category) to a real per-category SVG resolved by
// `categoryIconOrNullFor`, and the swap moved GEOMETRY, not just pixel
// content: chip height 32dp -> 36dp, group-header height 23dp -> ~28dp (see
// `service_setup_widgets.dart`'s `_iconSize` doc comments on both widgets).
// `test/features/services/presentation/widgets/service_setup_widgets_test.dart`
// proves the WIDGET-FIELD contract (resolved asset renders as `AppIcon` at
// the resolver-measured `Size(20, 20)`) but that is a `tester.getSize`
// assertion on ONE widget in isolation — it cannot catch a sibling layout
// regression (e.g. a parent `Row`/`Padding` change that squeezes the chip
// back toward the old 32dp height while the icon itself still measures
// 20x20). Nothing in `test/golden/` covered either widget before this file —
// confirmed via `grep -a -rn "service_setup\|CategoryChip\|CategoryGroupHeader"
// test/golden/`, which found only an unrelated comment in another file.
//
// GOLDENS ARE NOT ACCEPTANCE BY THEMSELVES — see
// `beauty_timeline_rail_golden_test.dart`'s header for the full argument.
// This suite's confidence rests on the `measured ground truth` group below
// (non-golden `testWidgets` proving the SVG layer genuinely resolves and is
// genuinely laid out at 20x20, corroborating the widget-level contract test)
// plus the two independent mutation probes recorded at the bottom of this
// header — not on eyeballing the PNG.
//
// COVERAGE
// --------
// One fixture, two Wraps + two headers, 360dp x {1.0, 1.3}:
//   - Unselected row: HAIRDRESSING, PODOLOGY (dense glyph — thin-stroke set,
//     loses the most detail at 20dp per `project_category_icon_set_thin_locked`
//     memory), MAKEUP, NAIL_SERVICE, and a null-slug ("Без категорії") chip —
//     the reserved-but-empty 20x20 slot.
//   - Selected row: the SAME five categories in the raised camel/mocha pillow
//     state (different tint path from unselected — `BrandColors.white` icon
//     vs `BrandColors.accent`), with a count badge on one chip (NAIL_SERVICE)
//     so the badge layout is also exercised.
//   - Two `CategoryGroupHeader`s: one with a resolved icon (PODOLOGY, dense),
//     one with `iconAsset: null` (uncategorised) — the SAME reserved-slot
//     contract as the null-slug chip, on the header's own geometry.
//
// MUTATION PROOF — two independent axes (mobile-qa, 2026-08-27)
// ---------------------------------------------------------------
// Both probes ran against `service_setup_category_360_1x` only (the other
// cell moves in lockstep — same widget tree, only `textScaleFactor` differs
// — so a single-cell probe is sufficient evidence the golden sees its
// subject; re-verified below is that BOTH cells are wired into the same
// fixture, not that each needed its own probe).
//
//   ORIGINAL (unmutated) baseline:
//     service_setup_category_360_1x    sha256 45d404106aca1555c0688e72833b61bdc1cfc49635ecd26996442c781e19c958
//     service_setup_category_360_1_3x  sha256 1ff103ad0a700170d05582e8d25c62926f82161ccdd8f3eb3ceb86462c7ab57e
//
//   AXIS 1 — PRESENCE (force the PODOLOGY chip's `iconAsset` to `null` at its
//   render site in `_categories`, leaving every other chip untouched):
//     360_1x    0.10%, 154px diff  (mutated sha256 67f203adfc16295016103559bdf61a3b1d124f02359ea2f4d111a0d7687a9004)
//     360_1_3x  0.10%, 153px diff  (mutated sha256 3d9e93785176317b8d3382ca1ad52b5fcb38a4ed574d224cef456cec045eeb2d)
//     Reverted via a `cp` backup of this file; `diff` confirmed byte-identical
//     restore, and re-running from the reverted fixture reproduces the
//     ORIGINAL bytes above exactly.
//
//   AXIS 2 — GEOMETRY (`CategoryChip._iconSize` and
//   `CategoryGroupHeader._iconSize`, `service_setup_widgets.dart`, changed
//   20 -> 12):
//     360_1x    54.99%, 83151px diff (mutated sha256 881e74d24a32e28635b4662551929dee1621d66a86138237f2157f6080290907)
//     360_1_3x  17.37%, 26259px diff (mutated sha256 2153db2187a518b9b1969e36c60f50c22f9c9fdc88e015f040c88f39f05f2714)
//     Reverted via a `cp` backup of `service_setup_widgets.dart`; `diff`
//     confirmed byte-identical restore, and re-running from the restored
//     source reproduces the ORIGINAL bytes above exactly. (The two cells'
//     percentages differ because 1.3x textScale grows the chip/header row
//     heights, changing the icon's share of the frame — both moved, which is
//     the load-bearing fact.)
//
// Both axes independently move the baseline hash and both were confirmed
// reverted to the exact original bytes — the golden genuinely sees the SVG
// layer on both the presence and the geometry axis.

import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_setup_widgets.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/golden_pump.dart';

/// The five categories exercised below: four resolved (one deliberately
/// dense — PODOLOGY) plus one null-slug ("uncategorised") case. Shared
/// between the unselected/selected rows so the SAME five slugs are compared
/// across both tint states.
const List<({String? icon, String label})>
_categories = <({String? icon, String label})>[
  (icon: BeauticaAssetIcons.categoryHairdressing, label: 'Стрижки'),
  // Dense glyph — the thin-stroke set's detail (the toe dot) is the
  // hardest to preserve at 20dp; see `project_category_icon_set_thin_locked`.
  (icon: BeauticaAssetIcons.categoryPodology, label: 'Педикюр'),
  (icon: BeauticaAssetIcons.categoryMakeup, label: 'Макіяж'),
  (icon: BeauticaAssetIcons.categoryNailService, label: 'Манікюр'),
  (icon: null, label: 'Без категорії'),
];

Widget _unselectedRow() => Wrap(
  spacing: 12,
  runSpacing: 12,
  children: <Widget>[
    for (final c in _categories)
      CategoryChip(
        key: ValueKey<String>('unselected-${c.label}'),
        iconAsset: c.icon,
        label: c.label,
        selected: false,
        includedCount: 0,
        onTap: () {},
      ),
  ],
);

Widget _selectedRow() => Wrap(
  spacing: 12,
  runSpacing: 12,
  children: <Widget>[
    for (final c in _categories)
      CategoryChip(
        key: ValueKey<String>('selected-${c.label}'),
        iconAsset: c.icon,
        label: c.label,
        selected: true,
        // A non-zero badge on exactly one chip so the badge layout is
        // exercised alongside the plain selected pillow.
        includedCount: c.label == 'Манікюр' ? 2 : 0,
        onTap: () {},
      ),
  ],
);

Widget _headers() => const Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: <Widget>[
    CategoryGroupHeader(
      iconAsset: BeauticaAssetIcons.categoryPodology,
      label: 'Педикюр',
      includedCount: 2,
      total: 5,
    ),
    CategoryGroupHeader(
      iconAsset: null,
      label: 'Без категорії',
      includedCount: 0,
      total: 3,
    ),
  ],
);

/// Hosts the full fixture on the brand base at [width], matching how the
/// chips/headers actually sit on `ServiceSetupScreen`.
Widget _fixture(double width) => ColoredBox(
  color: BrandColors.base,
  child: SizedBox(
    width: width,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _unselectedRow(),
          const SizedBox(height: 16),
          _selectedRow(),
          const SizedBox(height: 16),
          _headers(),
        ],
      ),
    ),
  ),
);

/// Pumps [child] under the localisation scaffolding [CategoryGroupHeader]
/// needs (`AppLocalizations.of(context)` for the "n з m" count text) — mirrors
/// `service_setup_widgets_test.dart`'s `_pump` helper.
Future<void> _pumpMeasured(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  const double width = 360;

  // ── Measured ground truth (not golden) ──────────────────────────────────
  //
  // What this golden's confidence actually rests on — mirrors the pattern in
  // `category_rail_golden_test.dart` / `beauty_timeline_rail_golden_test.dart`.
  group('CategoryChip / CategoryGroupHeader SVG layer — measured ground truth '
      '(not golden)', () {
    testWidgets(
      'every resolved-icon chip/header renders a real SvgPicture (not a '
      'blank decode placeholder), and the null-slug cases render NONE',
      (tester) async {
        await _pumpMeasured(tester, _fixture(width));
        await tester.pumpAndSettle();

        // 4 resolved chips x 2 rows (unselected + selected) + 1 resolved
        // header = 9. The null-slug chip (x2 rows) and the null-slug
        // header render NO AppIcon/SvgPicture.
        expect(find.byType(AppIcon), findsNWidgets(9));
        expect(find.byType(SvgPicture), findsNWidgets(9));
      },
    );

    testWidgets('every rendered icon is actually LAID OUT at 20x20, not merely '
        'constructed with size: 20 — the vacuous constructor-field trap', (
      tester,
    ) async {
      await _pumpMeasured(tester, _fixture(width));
      await tester.pumpAndSettle();

      for (final Element el in find.byType(SvgPicture).evaluate()) {
        final Size size = tester.getSize(find.byWidget(el.widget));
        expect(size, const Size(20, 20));
      }
    });
  });

  // ── Golden — the fixture above, at {1.0, 1.3} textScale ─────────────────
  group('service setup category chip / header golden', () {
    for (final double scale in kGoldenTextScales) {
      goldenTest(
        'service setup category chips + headers ${width.toInt()}dp x$scale',
        fileName: 'service_setup_category_${widthScaleSuffix(width, scale)}',
        constraints: BoxConstraints.tight(const Size(width, 420)),
        textScaleFactor: scale,
        pumpWidget: goldenPumpWidget(width: width),
        builder: () => _fixture(width),
      );
    }
  });
}
