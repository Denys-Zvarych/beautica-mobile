// Phase 324 (mobile-qa D1) — Visual regression goldens for [ServiceCard] in
// isolation.
//
// WHY THIS FILE EXISTS
// ---------------------
// `ServiceCard` (`lib/features/services/presentation/widgets/
// service_category_list.dart`) already appears inside the full-screen
// `services_list_golden_test.dart` baselines (writable DATA cells render it
// with a non-null `onEdit`; the phase-320 READ-ONLY cell renders it with
// `onEdit: null`), but embedded in a whole scrolling screen. This file pins
// the card ALONE, mirroring `delete_service_dialog_golden_test.dart`'s
// precedent for a shared, content-driven widget: single representative
// width, reviewed as a standalone image.
//
// STATES
// ------
//   • `service_card_with_onedit`    — a non-null `onEdit` callback → the
//     trailing edit-pencil pillow (`_EditButton`) renders, and the card is
//     wrapped in a `GestureDetector` (Phase 320 D3: tappable).
//   • `service_card_onedit_null`    — `onEdit: null` (a read-only viewer) →
//     the pencil pillow is replaced by a same-size BLANK slot (D3's "same
//     tree, fewer affordances" — pure subtraction, the row does not
//     reflow), and there is NO `GestureDetector` wrapping the content at
//     all (a tap has nothing to hit, not "hits a no-op").
//
// SINGLE WIDTH, LIKE delete_service_dialog_golden_test.dart
// -----------------------------------------------------------
// A card sizes to its own content plus the row's Expanded width; the two
// states differ only in the trailing slot, not in structural reflow across
// widths — one representative width (360dp) covers the shape.
//
// No ProviderScope override needed: `ServiceCard` takes a plain
// [MasterService] value and a callback, with no provider watches of its
// own (`PhotoThumbnail` / `ServiceInfo` are pure presentation).

import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_category_list.dart';
import 'package:beautica_mobile/shared/formatters/duration_minutes.dart';
import 'package:flutter/material.dart';

import 'helpers/golden_pump.dart';

const double _kCardGoldenWidth = 360;

const _seedService = MasterService(
  id: 'svc-card-1',
  serviceDefId: 'def-card-1',
  name: 'Стрижка жіноча',
  category: 'HAIRCUT',
  durationMinutes: 60,
  priceType: ServicePriceType.fixed,
  priceMin: 750,
  priceDisplay: '750 ₴',
);

// Phase 469 (acceptance 3) — two copies of one service type that share the
// displayed name. The owner list hands each card its copy hint (the duration,
// via `serviceNameHints`), rendered after the name as « · {hint}». Pinned at
// 1.0 and 1.3 text scale: the hint is capped at half the row and both halves
// ellipsize, so the larger scale is where a layout regression would show.
const _copySixty = MasterService(
  id: 'svc-copy-60',
  serviceDefId: 'def-copy-60',
  name: 'Класичний манікюр',
  category: 'NAILS',
  durationMinutes: 60,
  priceType: ServicePriceType.fixed,
  priceMin: 500,
  priceDisplay: '500 ₴',
);

const _copyNinety = MasterService(
  id: 'svc-copy-90',
  serviceDefId: 'def-copy-90',
  name: 'Класичний манікюр',
  category: 'NAILS',
  durationMinutes: 90,
  priceType: ServicePriceType.fixed,
  priceMin: 650,
  priceDisplay: '650 ₴',
);

Widget _duplicatePairWithHints() => _harness(
  Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      ServiceCard(
        service: _copySixty,
        onEdit: () {},
        nameHint: DurationMinutes.format(_copySixty.durationMinutes),
      ),
      const SizedBox(height: 12),
      ServiceCard(
        service: _copyNinety,
        onEdit: () {},
        nameHint: DurationMinutes.format(_copyNinety.durationMinutes),
      ),
    ],
  ),
);

/// Padding-wrapped so the card's own margin-free edges are visible against
/// the golden background, mirroring the `_harness` pattern in
/// `delete_service_dialog_golden_test.dart` / `velvet_snack_golden_test.dart`.
Widget _harness(Widget child) => Align(
  alignment: Alignment.topCenter,
  child: Padding(padding: const EdgeInsets.all(16), child: child),
);

void main() {
  final List<({String name, double scale, Widget Function() builder})> cases =
      <({String name, double scale, Widget Function() builder})>[
        (
          name: 'service_card_with_onedit',
          scale: 1.0,
          builder: () =>
              _harness(ServiceCard(service: _seedService, onEdit: () {})),
        ),
        (
          name: 'service_card_onedit_null',
          scale: 1.0,
          builder: () =>
              _harness(const ServiceCard(service: _seedService, onEdit: null)),
        ),
        (
          name: 'service_card_duplicate_pair_hints_360_1x',
          scale: 1.0,
          builder: _duplicatePairWithHints,
        ),
        (
          name: 'service_card_duplicate_pair_hints_360_1_3x',
          scale: 1.3,
          builder: _duplicatePairWithHints,
        ),
      ];

  for (final ({String name, double scale, Widget Function() builder}) c
      in cases) {
    goldenTest(
      'ServiceCard ${c.name}',
      fileName: c.name,
      constraints: BoxConstraints.tight(
        const Size(_kCardGoldenWidth, kGoldenHeight),
      ),
      textScaleFactor: c.scale,
      pumpWidget: goldenPumpWidget(width: _kCardGoldenWidth),
      builder: c.builder,
    );
  }
}
