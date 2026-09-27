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
// TWO STATES
// ----------
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

/// Padding-wrapped so the card's own margin-free edges are visible against
/// the golden background, mirroring the `_harness` pattern in
/// `delete_service_dialog_golden_test.dart` / `velvet_snack_golden_test.dart`.
Widget _harness(Widget child) => Align(
  alignment: Alignment.topCenter,
  child: Padding(padding: const EdgeInsets.all(16), child: child),
);

void main() {
  final List<({String name, Widget Function() builder})> cases =
      <({String name, Widget Function() builder})>[
        (
          name: 'service_card_with_onedit',
          builder: () =>
              _harness(ServiceCard(service: _seedService, onEdit: () {})),
        ),
        (
          name: 'service_card_onedit_null',
          builder: () =>
              _harness(const ServiceCard(service: _seedService, onEdit: null)),
        ),
      ];

  for (final ({String name, Widget Function() builder}) c in cases) {
    goldenTest(
      'ServiceCard ${c.name}',
      fileName: c.name,
      constraints: BoxConstraints.tight(
        const Size(_kCardGoldenWidth, kGoldenHeight),
      ),
      textScaleFactor: 1.0,
      pumpWidget: goldenPumpWidget(width: _kCardGoldenWidth),
      builder: c.builder,
    );
  }
}
