// Phase 21.6 mobile-qa gap-closure — PIXEL coverage for [SettingsRow]'s new
// `enabled` parameter (`lib/features/master/presentation/widgets/
// settings_row.dart`).
//
// ── WHY THIS FILE EXISTS ──────────────────────────────────────────────────
//
// Phase 21.6 added ONE additive parameter to the shared [SettingsRow],
// `enabled`, defaulting to `true`. `enabled: false` changes THREE things —
// `AnimatedOpacity(opacity: 0.6)`, `AbsorbPointer(absorbing: true)` and
// `Semantics(enabled: false)` — and before this file NOTHING in `test/golden/`
// rendered [SettingsRow] or any settings-hub screen at all
// (`grep -a -rln "SettingsRow\|settings_row" test/ integration_test/`
// returned three files, none of them a golden).
//
// [SettingsRow] is a shared widget with call sites across the settings hub,
// the account page and now the admin settings page — a single edit here lands
// on all of them, which is exactly the class of change a golden exists to
// gate.
//
// ── WHAT THIS FILE CAN AND CANNOT GATE ────────────────────────────────────
//
// This block is the REFERENCE EXAMPLE for documenting the golden tier's
// layer-opacity blind spot; other golden tests should follow its shape (see
// `docs/mobile-phases/phase-299-golden-tier-layer-opacity-contract.md` D1).
//
// It gates GEOMETRY and COPY. It does NOT gate the DIM, and that is a
// MEASURED property of this repo's golden toolchain rather than an omission.
//
// `test/flutter_test_config.dart` runs alchemist in CI-golden mode only
// (`obscureText: true`). That mode captures through
// `BlockedTextPaintingContext.paintSingleChild`
// (`alchemist-0.14.0/lib/src/blocked_text_image.dart:47`), which paints the
// render object directly and rasterizes its own `debugLayer`; a composited
// `OpacityLayer` does not survive that capture. Measured 2026-08-31 with a
// throwaway probe golden holding nothing but
// `Opacity(opacity: A, child: ColoredBox(...))` over a contrasting ground:
// baselines generated at `A = 0.30` compared GREEN at `A = 1.0`, for both
// `Opacity` and `AnimatedOpacity`. Per-element alpha (`Color.withValues`) IS
// captured — the same probe against `salon_booking_wizard_steps.dart`'s
// `_kNonOfferingDim` 0.42 -> 1.0 turned `salon_master_tile_golden_test.dart`
// 6/6 RED.
//
// The dim is therefore gated in
// `test/features/master/presentation/settings_row_disabled_dim_test.dart`,
// which composites the row to a real `ui.Image` and measures the ratio.
// Do NOT "fix" this file by adding a dim assertion here — it cannot see one.
//
// ── SCENARIO 1'S BASELINE IS PRE-CHANGE, NOT A SELF-PORTRAIT ──────────────
//
// The additive-parameter contract ("every pre-existing call site renders
// EXACTLY as before") cannot be testified to by a golden generated from the
// post-change widget — that would be a picture of the very code under
// suspicion. So `settings_row_pre_enabled_param_*` was produced A/B, the same
// device `section_header_golden_test.dart` records for the Phase 21.11
// promotion:
//
//   1. `settings_row.dart` was temporarily reverted to its pre-Phase-21.6
//      shape — the `enabled` field deleted from the widget and its
//      constructor, and `final bool inert = loading || !widget.enabled;`
//      restored to `final bool inert = loading;` — and THAT tree generated
//      the PNGs with `--update-goldens`.
//   2. The current `settings_row.dart` was restored byte-identically and this
//      file re-run WITHOUT `--update-goldens`. It passed on the pre-change
//      bytes, which are the ones committed (sha256
//      981c4fdb… / 0387c2d9… — re-verified unchanged after scenario 2 was
//      generated with `--name`, so scenario 1 was never overwritten by a
//      post-change render).
//
// Green in step 2 is the acceptance: the parameter's `true` default paints
// the same pixels the widget painted before it existed. Recorded here because
// the probe is not reproducible from the committed tree alone.
//
// Scenario 2's baseline is post-change and is proven load-bearing by
// MUTATION (mobile-qa, 2026-08-31): `settings_row.dart`'s
// `static const EdgeInsets _padding = EdgeInsets.all(VelvetSpacing.sm + 4)`
// -> `EdgeInsets.all(VelvetSpacing.sm)` turns all four cells RED. Its job is
// the disabled row's box, glyph and «незабаром» value — the geometry an
// `enabled: false` row must keep IDENTICAL to its enabled neighbour so a
// disabled row never shifts the rows around it.
//
// ── SCENARIOS ─────────────────────────────────────────────────────────────
//   1. The three PRE-EXISTING live configurations, in one frame: a plain
//      navigational row, a navigational row with a trailing `value:`, and the
//      `destructive: true` terminal row. `loading: true` is deliberately NOT
//      here — it renders a perpetual [CircularProgressIndicator] that
//      `pumpAndSettle` cannot quiesce, and it is not what this phase changed.
//   2. An ENABLED control row directly above the `enabled: false` +
//      `value:`-carrying row that Phase 21.6 ships («Перевести в майстри»).
//      Both in ONE frame ON PURPOSE: a reviewer diffs the two faces side by
//      side, and the control proves the dim is a per-row treatment rather
//      than a whole-frame opacity change.
//
// Copy comes from `AppLocalizations`, never Cyrillic literals.
//
// Matrix: 360 dp x {textScale 1.0, 1.3} = 4 PNGs.

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/settings_row.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import 'helpers/golden_pump.dart';

const double _kWidth = 360;

/// Host chrome shared by both scenarios — the base ground the rows sit on in
/// every real settings page, at the page's own horizontal padding.
Widget _host({required Widget Function(AppLocalizations l10n) rows}) =>
    ColoredBox(
      color: BrandColors.base,
      child: SizedBox(
        width: _kWidth,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Builder(
            builder: (BuildContext context) =>
                rows(AppLocalizations.of(context)),
          ),
        ),
      ),
    );

/// Scenario 1 — the three configurations that existed BEFORE `enabled`.
Widget _preEnabledParamRows(AppLocalizations l10n) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  mainAxisSize: MainAxisSize.min,
  children: <Widget>[
    SettingsRow(
      key: const Key('golden-settings-row-plain'),
      icon: Icons.swap_horiz_rounded,
      label: l10n.adminSettingsMoveSalon,
      onTap: _noop,
    ),
    const SizedBox(height: 12),
    SettingsRow(
      key: const Key('golden-settings-row-value'),
      icon: Icons.language_rounded,
      label: l10n.accountLanguageLabel,
      value: l10n.accountLanguageValue,
      onTap: _noop,
    ),
    const SizedBox(height: 12),
    SettingsRow(
      key: const Key('golden-settings-row-destructive'),
      icon: Icons.person_remove_outlined,
      label: l10n.adminSettingsRemove,
      destructive: true,
      showChevron: false,
      onTap: _noop,
    ),
  ],
);

/// Scenario 2 — the Phase 21.6 disabled row beside an enabled control.
Widget _disabledVsEnabledRows(AppLocalizations l10n) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  mainAxisSize: MainAxisSize.min,
  children: <Widget>[
    // CONTROL — the enabled sibling immediately above, so the dim reads as a
    // per-row treatment and not a frame-wide opacity.
    SettingsRow(
      key: const Key('golden-settings-row-enabled-control'),
      icon: Icons.swap_horiz_rounded,
      label: l10n.adminSettingsMoveSalon,
      onTap: _noop,
    ),
    const SizedBox(height: 12),
    // The shipped `AdminSettingsScreen` configuration, verbatim
    // (`admin_settings_screen.dart:328-341`).
    SettingsRow(
      key: const Key('golden-settings-row-disabled'),
      icon: Icons.badge_outlined,
      label: l10n.adminSettingsConvertToMaster,
      enabled: false,
      showChevron: false,
      value: l10n.adminSettingsConvertToMasterSoon,
      onTap: _noop,
    ),
  ],
);

void _noop() {}

void main() {
  for (final double scale in kGoldenTextScales) {
    final String suffix = widthScaleSuffix(_kWidth, scale);

    goldenTest(
      'settings row — pre-`enabled` configurations (plain / value / '
      'destructive) ${_kWidth.toInt()}dp x$scale',
      fileName: 'settings_row_pre_enabled_param_$suffix',
      constraints: BoxConstraints.tight(const Size(_kWidth, 260)),
      textScaleFactor: scale,
      pumpWidget: goldenPumpWidget(width: _kWidth),
      builder: () => _host(rows: _preEnabledParamRows),
    );

    goldenTest(
      'settings row — enabled control above the `enabled: false` row '
      '${_kWidth.toInt()}dp x$scale',
      fileName: 'settings_row_disabled_$suffix',
      constraints: BoxConstraints.tight(const Size(_kWidth, 200)),
      textScaleFactor: scale,
      pumpWidget: goldenPumpWidget(width: _kWidth),
      builder: () => _host(rows: _disabledVsEnabledRows),
    );
  }
}
