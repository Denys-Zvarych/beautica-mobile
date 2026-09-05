// Phase 21.6 mobile-qa gap-closure — PIXEL proof of [SettingsRow]'s
// `enabled: false` DIM (`lib/features/master/presentation/widgets/
// settings_row.dart:104,136`).
//
// ── WHY THIS IS NOT A GOLDEN ──────────────────────────────────────────────
//
// It was supposed to be. It cannot be, and that is a MEASURED property of
// this repo's golden toolchain, not a preference.
//
// `test/flutter_test_config.dart` runs alchemist in CI-golden mode only
// (`obscureText: true`, `platformGoldensConfig(enabled: false)`). CI mode
// captures through `BlockedTextPaintingContext.paintSingleChild`
// (`alchemist-0.14.0/lib/src/blocked_text_image.dart:47`), which calls
// `child.paint(context, offset)` directly and then rasterizes the render
// object's own `debugLayer`. Opacity is a COMPOSITED layer
// (`RenderAnimatedOpacityMixin.paint` → `context.pushOpacity`), and that
// layer does not survive the capture.
//
// Measured 2026-08-31 with a throwaway probe golden containing nothing but
// `Opacity(opacity: A, child: ColoredBox(...))` over a contrasting ground:
// baselines generated at `A = 0.30` compared GREEN at `A = 1.0`, for both
// `Opacity` and `AnimatedOpacity`. Alchemist CI goldens in this repo are
// structurally BLIND to opacity. (Per-element alpha — `Color.withValues` —
// IS captured; the same probe run against
// `salon_booking_wizard_steps.dart`'s `_kNonOfferingDim` 0.42 → 1.0 turned
// `salon_master_tile_golden_test.dart` 6/6 RED.)
//
// So `test/golden/settings_row_states_golden_test.dart` gates this widget's
// GEOMETRY and COPY, and the dim — the only part of `enabled: false` a
// sighted user actually perceives — is gated HERE instead, by compositing the
// row to a real `ui.Image` through `RenderRepaintBoundary.toImage()` and
// measuring the pixels.
//
// ── THE MEASUREMENT ───────────────────────────────────────────────────────
//
// `Opacity(a)` over an opaque ground `B` composites every pixel to
// `P' = a·P + (1 - a)·B`, so each pixel's DEVIATION from the ground scales
// exactly by `a`:  |P' - B| = a·|P - B|.
//
// Two rows are pumped with IDENTICAL configuration except `enabled`, each in
// its own [RepaintBoundary], both over [BrandColors.base]. Summing
// per-channel deviation from that ground across each row's captured image
// gives a ratio that must equal the production dim:
//
//     Σ|P_disabled - B| / Σ|P_enabled - B|  ==  0.6
//
// Which is a real number read out of real pixels, not a widget field. It
// pins the CONSTANT, not merely "some dimming happens".
//
// MUTATION RECORD (mobile-qa, 2026-08-31 — both run, both RED, both restored
// byte-identically, suite re-run GREEN):
//   • `settings_row.dart:136` `opacity: inert ? 0.6 : 1` → `opacity: 1`
//       → RED, measured ratio 1.0 (the dim is gone entirely);
//   • `settings_row.dart:104` `final bool inert = loading || !widget.enabled`
//       → `final bool inert = loading` → RED, measured ratio 1.0 (`enabled`
//       stops feeding the dim at all — the pre-Phase-21.6 behaviour).

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/settings_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/pump_app.dart';

const Key _kEnabledKey = Key('dim-probe-enabled');
const Key _kDisabledKey = Key('dim-probe-disabled');

/// The production dim, restated here so a change to it is a deliberate edit
/// in TWO places rather than a silently-absorbed drift.
const double _kExpectedDim = 0.6;

/// Composite tolerance — the capture is 8-bit per channel and the rows carry
/// anti-aliased glyph/text edges, so the summed ratio lands a hair off the
/// exact algebraic value. Tight enough that 1.0 (no dim) and 0.05 (the
/// mutants) are both far outside.
const double _kTolerance = 0.02;

/// Two rows, identical but for `enabled`, over the app's own ground.
///
/// The `value:` string is passed to BOTH so the compared subtrees paint the
/// exact same glyph/text/chevron inventory — a difference in what is drawn
/// would make the deviation ratio measure the CONTENT rather than the dim.
Widget _host() => const ColoredBox(
  color: BrandColors.base,
  child: Center(
    child: SizedBox(
      width: 340,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Cell(
            boundaryKey: _kEnabledKey,
            child: SettingsRow(
              icon: Icons.badge_outlined,
              label: 'Aa Bb Cc',
              value: 'Xx',
              showChevron: false,
              onTap: _noop,
            ),
          ),
          SizedBox(height: 12),
          _Cell(
            boundaryKey: _kDisabledKey,
            child: SettingsRow(
              icon: Icons.badge_outlined,
              label: 'Aa Bb Cc',
              value: 'Xx',
              showChevron: false,
              enabled: false,
              onTap: _noop,
            ),
          ),
        ],
      ),
    ),
  ),
);

void _noop() {}

/// One captured cell: an OPAQUE ground inside the [RepaintBoundary], with the
/// row centred on it.
///
/// The ground must be INSIDE the boundary. `RenderRepaintBoundary.toImage()`
/// rasterizes only the boundary's own subtree, so a ground painted by an
/// ancestor is simply absent and every pixel the row does not fully cover
/// comes back TRANSPARENT — which is exactly what a dimmed row produces too.
/// The deviation measurement would then be reading alpha, not the composite a
/// user sees. With the ground inside, `Opacity` composites against it for
/// real and every captured pixel is opaque.
///
/// The margin is wide enough to contain the row's neumorphic drop shadow,
/// which the dim scales along with everything else.
class _Cell extends StatelessWidget {
  const _Cell({required this.boundaryKey, required this.child});

  final Key boundaryKey;
  final Widget child;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    key: boundaryKey,
    child: ColoredBox(
      color: BrandColors.base,
      child: Padding(padding: const EdgeInsets.all(14), child: child),
    ),
  );
}

/// Sums every pixel's per-channel distance from [BrandColors.base] across the
/// image captured under [key].
///
/// Alpha is ignored: the boundary is captured over an opaque ground, so every
/// pixel comes back fully opaque and only the colour carries information.
Future<double> _deviationFromGround(WidgetTester tester, Key key) async {
  final RenderRepaintBoundary boundary = tester
      .renderObject<RenderRepaintBoundary>(find.byKey(key));

  late final ByteData? raw;
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage();
    raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
  });

  final ByteData? bytes = raw;
  expect(bytes, isNotNull, reason: 'the boundary must rasterize');

  final Uint8List px = bytes!.buffer.asUint8List();
  const int groundR = 0xE6;
  const int groundG = 0xDD;
  const int groundB = 0xD0;

  double sum = 0;
  for (int i = 0; i + 3 < px.length; i += 4) {
    sum += (px[i] - groundR).abs().toDouble();
    sum += (px[i + 1] - groundG).abs().toDouble();
    sum += (px[i + 2] - groundB).abs().toDouble();
  }
  return sum;
}

void main() {
  testWidgets(
    'an `enabled: false` row composites to exactly 0.6 of an identical '
    'enabled row\'s deviation from the page ground',
    (tester) async {
      await tester.pumpApp(_host(), width: 400, height: 400);
      await tester.pumpAndSettle();

      final double enabled = await _deviationFromGround(tester, _kEnabledKey);
      final double disabled = await _deviationFromGround(tester, _kDisabledKey);

      // Guard the guard: if the ENABLED row painted nothing distinguishable
      // from the ground, the ratio below would be 0/0 and this test would be
      // measuring the capture rather than the dim.
      expect(
        enabled,
        greaterThan(0),
        reason:
            'the enabled control must paint something other than the ground '
            '— otherwise the ratio is meaningless',
      );

      expect(
        disabled / enabled,
        closeTo(_kExpectedDim, _kTolerance),
        reason:
            'Opacity(a) composites to a·|P - B| deviation, so the ratio IS '
            'the dim: 1.0 would mean `enabled: false` no longer dims at all',
      );
    },
  );

  testWidgets('an enabled row is not dimmed against its own capture', (
    tester,
  ) async {
    // The additive-default half: two ENABLED rows must be indistinguishable,
    // so the measurement above cannot be an artefact of the two boundaries
    // sitting at different offsets.
    await tester.pumpApp(
      const ColoredBox(
        color: BrandColors.base,
        child: Center(
          child: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _Cell(
                  boundaryKey: _kEnabledKey,
                  child: SettingsRow(
                    icon: Icons.badge_outlined,
                    label: 'Aa Bb Cc',
                    value: 'Xx',
                    showChevron: false,
                    onTap: _noop,
                  ),
                ),
                SizedBox(height: 12),
                _Cell(
                  boundaryKey: _kDisabledKey,
                  child: SettingsRow(
                    icon: Icons.badge_outlined,
                    label: 'Aa Bb Cc',
                    value: 'Xx',
                    showChevron: false,
                    onTap: _noop,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      width: 400,
      height: 400,
    );
    await tester.pumpAndSettle();

    final double a = await _deviationFromGround(tester, _kEnabledKey);
    final double b = await _deviationFromGround(tester, _kDisabledKey);

    expect(a, greaterThan(0));
    expect(b / a, closeTo(1.0, _kTolerance));
  });
}
