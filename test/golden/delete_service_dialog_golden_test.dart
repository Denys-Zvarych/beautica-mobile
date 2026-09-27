// `DeleteServiceDialog` golden guard — Phase 319.
//
// WHY THIS FILE EXISTS
// ---------------------
// `DeleteServiceDialog` (`lib/features/services/presentation/widgets/
// delete_service_dialog.dart`) is a shared render widget that, as of Phase
// 319, has TWO states: the unblocked deactivation prompt (unchanged since
// phase 5.5) and the new `blocked: true` refusal surface for a 409
// `ServiceUnassignBlockedFailure`. `grep -a -rln "DeleteServiceDialog"
// test/golden/` returned NOTHING before this file — no golden existed for
// EITHER variant. The phase doc's acceptance criterion ("the unblocked
// dialog golden did not regenerate") is therefore checked differently here:
// both goldens are NEW in this PR, seeded once and reviewed as images
// (`feedback_golden_not_acceptance` — a freshly-seeded golden is
// self-referential and proves nothing about correctness on its own; it was
// visually reviewed against the widget's source before being committed).
//
// SINGLE WIDTH, LIKE error_state_golden_test.dart / velvet_snack_golden_
// test.dart
// -------------------------------------------------------------------------
// An AlertDialog sizes to its own content; it does not reflow structurally
// at 320 vs 414 dp the way a full screen does. One representative width
// (360 dp) covers the shape.
//
// SEED / REFRESH: run `flutter test --update-goldens
// test/golden/delete_service_dialog_golden_test.dart` once to seed the PNG
// masters under `test/golden/goldens/`, then commit them.

import 'package:beautica_mobile/features/services/presentation/widgets/delete_service_dialog.dart';
import 'package:flutter/material.dart';

import 'helpers/golden_pump.dart';

const double _kDialogGoldenWidth = 360;

/// An [Align] so the dialog sizes to its own content instead of stretching
/// to fill the tall golden capture area — same fix `velvet_snack_golden_
/// test.dart`'s `_harness` uses, minus the transparency [Material] (the
/// [AlertDialog] provides its own).
Widget _harness(Widget child) =>
    Align(alignment: Alignment.topCenter, child: child);

void main() {
  final List<({String name, Widget Function() builder})> cases =
      <({String name, Widget Function() builder})>[
        (
          name: 'delete_service_dialog_unblocked',
          builder: () => _harness(const DeleteServiceDialog()),
        ),
        (
          name: 'delete_service_dialog_blocked',
          builder: () => _harness(const DeleteServiceDialog(blocked: true)),
        ),
      ];

  for (final ({String name, Widget Function() builder}) c in cases) {
    goldenTest(
      'DeleteServiceDialog ${c.name}',
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
