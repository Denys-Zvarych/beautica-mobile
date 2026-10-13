// Admin / master confirmation dialogs golden guard — phase 405 (9.10).
//
// WHY THIS FILE EXISTS
// ---------------------
// Phase 405 PROMOTES the private `_DialogShell` / `_ActionBadge` out of
// `lib/features/salon/presentation/widgets/admin_action_dialogs.dart` into
// `lib/shared/widgets/confirm_dialog_shell.dart` (REUSE-FIRST: the portfolio
// «Видалити фото?» confirmation needs the identical chrome). No golden pinned
// any of the three dialogs before, so these baselines were SEEDED against the
// pre-promotion source and then re-run unchanged after the move — the
// promotion is proven render-identical by these PNGs, not eyeballed.
//
// SINGLE WIDTH — a Dialog sizes to its own content (see
// delete_service_dialog_golden_test.dart).

import 'package:beautica_mobile/features/salon/presentation/widgets/admin_action_dialogs.dart';
import 'package:flutter/material.dart';

import 'helpers/golden_pump.dart';

const double _kDialogGoldenWidth = 360;

Widget _harness(Widget child) =>
    Align(alignment: Alignment.topCenter, child: child);

void main() {
  final List<({String name, Widget Function() builder})> cases =
      <({String name, Widget Function() builder})>[
        (
          name: 'admin_dialog_remove_admin',
          builder: () => _harness(
            const RemoveAdminDialog(adminName: 'Ірина Адміністратор'),
          ),
        ),
        (
          name: 'admin_dialog_remove_master',
          builder: () =>
              _harness(const RemoveMasterDialog(masterName: 'Олена Ковальчук')),
        ),
        (
          name: 'admin_dialog_move_admin',
          builder: () => _harness(
            const MoveAdminDialog(
              adminName: 'Ірина Адміністратор',
              destinationSalonName: 'Салон «Лілія»',
            ),
          ),
        ),
      ];

  for (final ({String name, Widget Function() builder}) c in cases) {
    goldenTest(
      'admin action dialog ${c.name}',
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
