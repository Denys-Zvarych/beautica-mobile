// Phase 111 field-test fix (mobile-qa) — «Улюблені» card goldens.
//
// WHY THIS FILE EXISTS NOW, NOT AT PHASE 111 SHIP
// -------------------------------------------------
// `favorite_cards.dart`'s own inline-fontsize allowlist justification
// (`scripts/.inline_fontsize_allow:26`) reads "at any extent a caller (or a
// golden) asks for" — written for a golden that did not exist. The backlog
// carried this as an INFO for exactly that reason.
//
// The field-test fix changes what THIS FILE MUST PIN, not just whether it
// should exist at all:
//
//   * D1 (`_IdentityLine`, `maxLines: 1` → `2`) makes row height genuinely
//     DATA-DEPENDENT for the first time — a long name now grows the card, and
//     the widget tier proved the wrap+alignment with layout maths
//     (`favorite_cards_test.dart`), but never with a rendered pixel.
//   * D2 (`_AffiliationLine`) and D3 (unsuppressed affiliated-master address)
//     each add a render band this file never drew before Phase 111's fix.
//
// So this pins FOUR scenarios, at the project's standard {320, 360, 414}dp x
// 1.0 matrix (matching `discovery_result_card_golden_test.dart` — no
// textScale row: neither card carries the login/master-profile screens'
// history of textScale-only overflow):
//
//   1. An INDEPENDENT master — the pre-Phase-111 baseline shape.
//   2. A SALON-AFFILIATED master — D2 + D3, both new bands present at once.
//   3. A master with a LONG NAME — D1's two-line wrap + top-aligned rating,
//      at the narrowest width where the wrap is tightest.
//   4. A salon card — `_IdentityLine` is SHARED with the master card, so this
//      is the control: a change that regresses only via the master arm would
//      otherwise ship unpinned for the salon arm.
//
// NOT covered by `test/features/favorites/` scope — run by name:
//   flutter test test/golden/favorite_cards_golden_test.dart
//
// Cards take plain `onOpen`/`onUnlike` callbacks and no Riverpod provider
// (unlike the discovery result cards, which watch `favoriteToggleProvider` via
// `authProvider`), so no ProviderScope override is needed here at all.

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/features/favorites/domain/favorite_item.dart';
import 'package:beautica_mobile/features/favorites/presentation/widgets/favorite_cards.dart';
import 'package:flutter/material.dart';

import 'helpers/golden_pump.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const FavoriteItem _independentMaster = FavoriteItem(
  id: 'master-1',
  kind: FavoriteKind.master,
  name: 'Марта Гончар',
  initials: 'МГ',
  rating: 4.7,
  cityLabel: 'Київ',
  street: 'Хрещатик',
  buildingNo: '22',
  locationNote: 'вхід з двору',
);

const FavoriteItem _affiliatedMaster = FavoriteItem(
  id: 'master-2',
  kind: FavoriteKind.master,
  name: 'Ірина Подільська',
  initials: 'ІП',
  rating: 4.9,
  salonName: 'Crystal Room',
  cityLabel: 'Київ',
  street: 'Січових Стрільців',
  buildingNo: '9',
);

const FavoriteItem _longNameMaster = FavoriteItem(
  id: 'master-3',
  kind: FavoriteKind.master,
  name: 'Соломія Константиновська-Забродська',
  initials: 'СК',
  rating: 4.6,
  cityLabel: 'Львів',
  street: 'Галицька',
  buildingNo: '5',
);

const FavoriteItem _salon = FavoriteItem(
  id: 'salon-1',
  kind: FavoriteKind.salon,
  name: 'Beauty Studio «Камелія»',
  initials: 'BS',
  rating: 4.8,
  cityLabel: 'Львів',
  districtLabel: 'Галицький район',
  street: 'Личаківська',
  buildingNo: '18',
  locationNote: 'другий поверх',
);

/// Hosts [child] on the brand base with the favourites list's own horizontal
/// page padding, so the card lays out exactly as it does on screen.
Widget _host(double width, Widget child) => ColoredBox(
  color: BrandColors.base,
  child: SizedBox(
    width: width,
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: VelvetSpacing.lg,
        vertical: VelvetSpacing.sm,
      ),
      child: child,
    ),
  ),
);

void main() {
  for (final double width in kGoldenWidths) {
    final String w = width.toInt().toString();

    goldenTest(
      'favorites independent master card ${w}dp x1.0',
      fileName: 'favorites_independent_master_${w}_1x',
      constraints: BoxConstraints.tightFor(width: width),
      textScaleFactor: 1.0,
      pumpWidget: goldenPumpWidget(width: width),
      builder: () => _host(
        width,
        FavoriteMasterCard(
          item: _independentMaster,
          onOpen: () {},
          onUnlike: () {},
        ),
      ),
    );

    goldenTest(
      'favorites salon-affiliated master card ${w}dp x1.0',
      fileName: 'favorites_affiliated_master_${w}_1x',
      constraints: BoxConstraints.tightFor(width: width),
      textScaleFactor: 1.0,
      pumpWidget: goldenPumpWidget(width: width),
      builder: () => _host(
        width,
        FavoriteMasterCard(
          item: _affiliatedMaster,
          onOpen: () {},
          onUnlike: () {},
        ),
      ),
    );

    goldenTest(
      'favorites long-name master card ${w}dp x1.0',
      fileName: 'favorites_long_name_master_${w}_1x',
      constraints: BoxConstraints.tightFor(width: width),
      textScaleFactor: 1.0,
      pumpWidget: goldenPumpWidget(width: width),
      builder: () => _host(
        width,
        FavoriteMasterCard(
          item: _longNameMaster,
          onOpen: () {},
          onUnlike: () {},
        ),
      ),
    );

    goldenTest(
      'favorites salon card ${w}dp x1.0',
      fileName: 'favorites_salon_card_${w}_1x',
      constraints: BoxConstraints.tightFor(width: width),
      textScaleFactor: 1.0,
      pumpWidget: goldenPumpWidget(width: width),
      builder: () => _host(
        width,
        FavoriteSalonCard(item: _salon, onOpen: () {}, onUnlike: () {}),
      ),
    );
  }
}
