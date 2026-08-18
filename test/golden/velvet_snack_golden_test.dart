// VelvetSnack (`lib/shared/feedback/velvet_snack.dart`) variant golden guard
// — mobile-qa, 2026-08-06.
//
// WHY THIS FILE EXISTS
// ---------------------
// `VelvetSnack` is a pure `StatelessWidget` — deliberately built (per its own
// file-level doc comment) to be golden-testable WITHOUT pumping a controller
// or an `Overlay`. It is also, after the 63-call-site migration this suite
// guards, the single most-reused new visual surface in the app. A silent
// restyle of the spine width, the icon tint plate, the hairline border, or
// the action/close affordances would land on every one of those call sites
// at once with no pixel-level guard — exactly the gap `error_state_golden_
// test.dart` closed for the shared error surface (mobile-qa M3). This is
// that same treatment for VelvetSnack.
//
// WHAT THIS DOES NOT COVER
// -------------------------
// Not a duplicate of the structural assertions in
// `test/shared/feedback/velvet_snack_test.dart` (which one, this test
// wouldn't be able to tell you WHY it moved). This is a pixel guard for the
// exact spine width / accent tint / hairline / spacing values, complementing
// — not replacing — the mutation-proven structural tests there.
//
// SINGLE WIDTH, LIKE error_state_golden_test.dart
// -------------------------------------------------
// The snack's own layout is width-driven only by however wide its host
// happens to make it (`Positioned(left:, right:)` in production); the
// component itself does not reflow differently at 320 vs 414 — sweeping the
// full {320,360,414}×{1.0,1.3} matrix would just triple near-identical PNGs
// for no discriminating value. One representative width (360dp) covers the
// shape; the maxLines/truncation behaviour at a squeeze width is already
// mutation-proven (not merely goldened) in the widget-tier test.
//
// SEED / REFRESH: run `flutter test --update-goldens
// test/golden/velvet_snack_golden_test.dart` once to seed the PNG masters
// under `test/golden/goldens/`, then commit them.

import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:flutter/material.dart';

import 'helpers/golden_pump.dart';

const double _kSnackGoldenWidth = 360;

/// Matches the [MaterialType.transparency] ancestor `velvet_snack_host.dart`
/// provides in production (needed for the action/close `InkWell`s), plus an
/// [Align] so the snack sizes to its own content instead of stretching to
/// fill the tall golden capture area — the same fix
/// `velvet_snack_test.dart`'s `_harness` needed for the identical reason.
Widget _harness(Widget child) => Material(
  type: MaterialType.transparency,
  child: Align(alignment: Alignment.topCenter, child: child),
);

void main() {
  final List<({String name, Widget Function() builder})> cases =
      <({String name, Widget Function() builder})>[
        (
          name: 'velvet_snack_success',
          builder: () => _harness(
            const VelvetSnack(
              variant: VelvetSnackVariant.success,
              message: 'Зміни збережено',
            ),
          ),
        ),
        (
          name: 'velvet_snack_error',
          builder: () => _harness(
            const VelvetSnack(
              variant: VelvetSnackVariant.error,
              message: 'Не вдалося зберегти',
            ),
          ),
        ),
        (
          name: 'velvet_snack_info',
          builder: () => _harness(
            const VelvetSnack(
              variant: VelvetSnackVariant.info,
              message: 'Скоро буде доступно',
            ),
          ),
        ),
        (
          name: 'velvet_snack_warning',
          builder: () => _harness(
            const VelvetSnack(
              variant: VelvetSnackVariant.warning,
              message: 'Досягнуто ліміт послуг',
            ),
          ),
        ),
        // The action + close variant together — the busiest real layout
        // (503-retry pattern in `service_setup_screen.dart`), so a spacing
        // regression between the message, the action and the close button
        // shows up here even though no single production call site combines
        // BOTH an action and an explicit close.
        (
          name: 'velvet_snack_error_with_action_and_close',
          builder: () => _harness(
            VelvetSnack(
              variant: VelvetSnackVariant.error,
              message: 'Не вдалося зберегти',
              actionLabel: 'Повторити',
              onAction: () {},
              onDismiss: () {},
            ),
          ),
        ),
      ];

  for (final ({String name, Widget Function() builder}) c in cases) {
    goldenTest(
      'VelvetSnack ${c.name}',
      fileName: c.name,
      constraints: BoxConstraints.tight(
        const Size(_kSnackGoldenWidth, kGoldenHeight),
      ),
      textScaleFactor: 1.0,
      pumpWidget: goldenPumpWidget(width: _kSnackGoldenWidth),
      builder: c.builder,
    );
  }
}
