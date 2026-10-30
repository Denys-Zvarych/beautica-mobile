// `BlockClientDialog` golden guard — phase 425 + backend 398 follow-up.
//
// The block confirmation now has TWO bodies: the independent-master copy
// (`blockDialogBody`, "all their upcoming bookings with you will be cancelled")
// and the salon owner / admin copy (`blockDialogBodySalon`, `salonScope:
// true`). Both are long Ukrainian paragraphs inside the shared
// `ConfirmDialogShell`, so a wrap / overflow regression is a pixel-level
// concern. `grep -a -rln "BlockClientDialog" test/golden/` returned nothing
// before this file — both PNGs are NEW, seeded once and reviewed as images
// (`feedback_golden_not_acceptance`: a freshly seeded golden proves nothing
// on its own; the copy itself is pinned verbatim by
// `booking_client_actions_test.dart`).
//
// Single 360 dp width, same reasoning as `delete_service_dialog_golden_test`:
// a dialog sizes to its own content.
//
// SEED / REFRESH: `flutter test --update-goldens
// test/golden/block_client_dialog_golden_test.dart`, then commit the PNGs
// under `test/golden/goldens/`.

import 'package:beautica_mobile/features/moderation/presentation/widgets/block_confirm_dialog.dart';
import 'package:flutter/material.dart';

import 'helpers/golden_pump.dart';

const double _kDialogGoldenWidth = 360;

Widget _harness(Widget child) =>
    Align(alignment: Alignment.topCenter, child: child);

void main() {
  final List<({String name, Widget Function() builder})> cases =
      <({String name, Widget Function() builder})>[
        (
          name: 'block_client_dialog_master',
          builder: () =>
              _harness(const BlockClientDialog(name: 'Олена Ковальчук')),
        ),
        (
          name: 'block_client_dialog_salon',
          builder: () => _harness(
            const BlockClientDialog(name: 'Олена Ковальчук', salonScope: true),
          ),
        ),
      ];

  for (final ({String name, Widget Function() builder}) c in cases) {
    goldenTest(
      'BlockClientDialog ${c.name}',
      fileName: c.name,
      constraints: BoxConstraints.tight(
        const Size(_kDialogGoldenWidth, kGoldenHeight),
      ),
      textScaleFactor: 1.0,
      pumpWidget: goldenPumpWidget(width: _kDialogGoldenWidth),
      builder: c.builder,
    );
  }
}
