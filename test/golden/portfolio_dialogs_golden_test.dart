// Phase 405 (9.10, D5) — the «Видалити фото?» confirmation golden. Built on
// the shared ConfirmDialogShell (pinned for its original consumers by
// admin_action_dialogs_golden_test.dart). Freshly seeded — reviewed as an
// image against the widget source, not self-proving.

import 'package:beautica_mobile/shared/widgets/portfolio_dialogs.dart';
import 'package:flutter/material.dart';

import 'helpers/golden_pump.dart';

const double _kDialogGoldenWidth = 360;

void main() {
  goldenTest(
    'DeletePortfolioPhotoDialog',
    fileName: 'portfolio_delete_dialog',
    constraints: BoxConstraints.tight(
      const Size(_kDialogGoldenWidth, kGoldenHeight),
    ),
    textScaleFactor: 1.0,
    pumpWidget: goldenPumpWidget(width: _kDialogGoldenWidth),
    builder: () => const Align(
      alignment: Alignment.topCenter,
      child: DeletePortfolioPhotoDialog(),
    ),
  );
}
