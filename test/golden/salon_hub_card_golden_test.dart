// Phase 21.6 mobile-qa gap-closure — pixel coverage for the PROMOTED
// [SalonHubCard] (`lib/features/salon/presentation/widgets/salon_hub_card
// .dart`).
//
// ── WHY THIS FILE EXISTS ──────────────────────────────────────────────────
//
// Phase 21.6 promoted `_SalonHubCard` out of `my_salons_screen.dart` into
// `presentation/widgets/salon_hub_card.dart` so [MoveAdminSalonScreen] could
// reuse it instead of forking a near-identical card. `grep -a -rln
// "SalonHubCard\|salon_hub_card" test/ integration_test/` returned NO golden
// before this file, and `test/golden/` holds no «Мої салони» capture at all —
// so the hub's card had, and the promotion shipped with, zero pixel gate.
//
// The forward risk is the one that matters: the widget went from ONE
// feature-local consumer to TWO across two screens, and a single edit here
// now lands on both the owner's salon hub and the rotate-admin picker.
//
// ── NO PRE-PROMOTION A/B, AND WHY ─────────────────────────────────────────
//
// `section_header_golden_test.dart` records an A/B (generate the baseline
// from the pre-promotion class body, then re-run green against the promoted
// one). That device is deliberately NOT claimed here. Two reasons:
//
//   1. mobile-qa runs under an explicit no-`git` constraint for this audit,
//      so the pre-promotion `_SalonHubCard` body is not recoverable from the
//      working tree;
//   2. even if it were, the A/B would be a tautology. The promotion was a
//      pure file move: the class body is unchanged, the public API is
//      byte-identical (`{Key?, required Salon salon, required VoidCallback
//      onTap}` — no parameter added, no default changed; see the widget's own
//      header), so a reconstructed "pre" class would be the SAME code and
//      would necessarily paint the same pixels.
//
// This file is therefore an honest FORWARD lock, not a retroactive proof of
// the move. It is mutation-proven instead (mobile-qa, 2026-08-31): changing
// `salon_hub_card.dart`'s `SalonLogo(diameter: 58, ...)` to `diameter: 40`
// turns all cells RED.
//
// ── SCENARIOS — the two LIVE consumer configurations, no speculative ones ──
//
//   • «Мої салони» — a full [Salon]: primary flag set (so the «Основний»
//     gradient badge renders), a locality line AND a street line, i.e. every
//     optional element the card can draw.
//   • The rotate-admin picker — the display-only [Salon] that
//     `MoveAdminSalonScreen._displaySalon` builds from a
//     [SiblingSalonOption]: name + street/buildingNo ONLY. No `isPrimary`
//     (no badge) and no locality (that endpoint sends none, deliberately —
//     see `SiblingSalonOption`'s header). Two scenarios that rendered
//     identically would mean the card ignored the difference.
//
// Both use a BLANK `cityId`, which short-circuits `resolvedLocalityProvider`
// with no network read at all (see that provider's own guard) — so the hub
// scenario's locality line comes from the legacy `Salon.city` fallback and
// the picker scenario draws none. That keeps the file free of location
// fixtures and of the suite-wide no-network trap.
//
// Matrix: 360 dp x {textScale 1.0, 1.3} = 4 PNGs.

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/sibling_salon_option.dart';
import 'package:beautica_mobile/features/salon/presentation/widgets/salon_hub_card.dart';
import 'package:flutter/material.dart';

import 'helpers/golden_pump.dart';

const double _kWidth = 360;

/// The «Мої салони» configuration — every optional element present.
const Salon _kHubSalon = Salon(
  id: 'salon-hub',
  name: 'Студія «Камелія»',
  city: 'Київ',
  street: 'вул. Хрещатик',
  buildingNo: '12',
  isPrimary: true,
);

/// The picker's source row.
const SiblingSalonOption _kSibling = SiblingSalonOption(
  id: 'salon-2',
  name: 'Барбершоп «Дуб»',
  street: 'вул. Січових Стрільців',
  buildingNo: '4',
);

/// `MoveAdminSalonScreen._displaySalon`, mirrored EXACTLY — the adaptation is
/// private to that screen, so the fixture-parity is deliberate: a drift
/// between the two is its own bug and this golden would then be testing a
/// shape the picker never renders.
const Salon _kPickerSalon = Salon(
  id: 'salon-2',
  name: 'Барбершоп «Дуб»',
  street: 'вул. Січових Стрільців',
  buildingNo: '4',
);

Widget _host() => const ColoredBox(
  color: BrandColors.base,
  child: SizedBox(
    width: _kWidth,
    child: Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SalonHubCard(
            key: Key('golden-salon-hub-card-full'),
            salon: _kHubSalon,
            onTap: _noop,
          ),
          SizedBox(height: 14),
          SalonHubCard(
            key: Key('golden-salon-hub-card-picker'),
            salon: _kPickerSalon,
            onTap: _noop,
          ),
        ],
      ),
    ),
  ),
);

void _noop() {}

void main() {
  // Pins the picker fixture to its real source row, so a change to
  // `SiblingSalonOption`'s shape cannot leave this file goldening a salon the
  // picker could never build.
  assert(_kPickerSalon.name == _kSibling.name);
  assert(_kPickerSalon.street == _kSibling.street);
  assert(_kPickerSalon.buildingNo == _kSibling.buildingNo);

  for (final double scale in kGoldenTextScales) {
    goldenTest(
      'salon hub card — «Мої салони» (badge + locality + street) above the '
      'rotate-admin picker card (street only) ${_kWidth.toInt()}dp x$scale',
      fileName: 'salon_hub_card_${widthScaleSuffix(_kWidth, scale)}',
      constraints: BoxConstraints.tight(const Size(_kWidth, 320)),
      textScaleFactor: scale,
      pumpWidget: goldenPumpWidget(width: _kWidth),
      builder: _host,
    );
  }
}
