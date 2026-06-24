// Phase 13.3 — Shared CLIENT top bar (wordmark · bell · burger).
//
// Extracted from the byte-identical private `_TopBar` that lived in BOTH
// `home_hub_screen.dart` and `passport_screen.dart`, plus the `BellButton` that
// was `@visibleForTesting` inside the home hub. Hoisting it here gives the three
// CLIENT branch roots (Головна, BEAUTY PASSPORT, Пошук) one source of truth so
// the bar never drifts between pages.
//
// Visuals are preserved exactly:
//   • lowercase "beautica" wordmark (brand literal — NOT translated) sized to its
//     intrinsic width — a single trailing [Spacer] absorbs ALL row slack and
//     pushes the fixed bell + burger to the right. (It is NOT wrapped in
//     Flexible: a Flexible here would split the free space 1:1 with the Spacer,
//     starving the wordmark to ~50% width and truncating it to "Beatu…". The
//     ellipsis + maxLines:1 remain only as a defensive guard against pathological
//     text scaling.);
//   • the notification [BellButton] (idle / unread states baked into the SVG);
//   • an OPTIONAL [NeumorphicIconButton] burger on the right.
//
// The bell + burger semantic labels and the burger [Key] are supplied by the
// caller so each host page keeps its own stable test target
// (`btn-menu-client` / `btn-menu-passport`). The burger is optional: Пошук omits
// it (the settings hub it opens is redundant there), so the bell becomes the
// last trailing element on that page.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/core/theme/beautica_icons.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';

/// The shared CLIENT branch-root top bar: beautica wordmark · bell · burger.
///
/// Used by Головна, BEAUTY PASSPORT and Пошук. Branch roots have no back
/// button — when present, the burger opens the CLIENT settings hub (the caller
/// wires [onBurger]). The burger is optional: pages where the settings hub is
/// redundant (Пошук) omit [onBurger] and no burger renders.
class ClientTopBar extends StatelessWidget {
  const ClientTopBar({
    super.key,
    required this.onBell,
    required this.bellSemanticLabel,
    this.onBurger,
    this.burgerSemanticLabel,
    this.burgerKey,
    this.bellKey,
    this.hasUnread = false,
  });

  /// Invoked when the notification bell is tapped.
  final VoidCallback onBell;

  /// Invoked when the burger menu is tapped (opens the CLIENT settings hub).
  /// When `null`, the burger is omitted entirely.
  final VoidCallback? onBurger;

  /// Accessibility label for the bell.
  final String bellSemanticLabel;

  /// Accessibility label for the burger (ignored when [onBurger] is `null`).
  final String? burgerSemanticLabel;

  /// Stable [Key] for the burger button (per-host test target; ignored when
  /// [onBurger] is `null`).
  final Key? burgerKey;

  /// Optional stable [Key] for the bell button (per-host test target).
  final Key? bellKey;

  /// Whether to render the unread-state bell (dot baked into the asset).
  final bool hasUnread;

  /// Fixed cross-axis extent of the bar — pinned to the burger's square extent
  /// so the centred "beautica" wordmark sits at the SAME vertical offset on
  /// EVERY branch root, regardless of whether the (optional) burger renders.
  ///
  /// Without this, the Row's height collapsed to its tallest child: 48 dp with
  /// the burger (Головна / BEAUTY PASSPORT) but only ~32 dp on Пошук (bell-only,
  /// burger omitted in 7fada10). Switching tabs in the `indexedStack` shell then
  /// read as an ~8 px wordmark jump. Locking the box to [NeumorphicIconButton.extent]
  /// makes the wordmark position burger-INDEPENDENT.
  static const double _barHeight = NeumorphicIconButton.extent;

  @override
  Widget build(BuildContext context) {
    final VoidCallback? onBurger = this.onBurger;
    return SizedBox(
      height: _barHeight,
      child: Row(
        children: <Widget>[
          // beautica wordmark — intentionally lowercase (brand decision). NOT
          // wrapped in Flexible: the trailing Spacer is the row's only flex child,
          // so it absorbs 100% of the slack and the wordmark sizes to its intrinsic
          // width (it is far narrower than the available room at 1.0× text scale).
          // ellipsis + maxLines:1 stay only as a defensive guard against
          // pathological text scaling — never expected to trigger at normal scale.
          Text(
            // ignore: avoid_hardcoded_strings — brand wordmark, NOT translated.
            'beautica',
            style: VelvetText.wordmark(),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          const Spacer(),
          BellButton(
            key: bellKey,
            onTap: onBell,
            semanticLabel: bellSemanticLabel,
            hasUnread: hasUnread,
          ),
          // Burger is optional — omitted on Пошук (redundant settings hub). When
          // absent, the bell is the last trailing element.
          if (onBurger != null) ...<Widget>[
            const SizedBox(width: VelvetSpacing.sm + 4),
            NeumorphicIconButton(
              key: burgerKey,
              icon: BeauticaIcons.menuBurger,
              semanticLabel: burgerSemanticLabel ?? '',
              onTap: onBurger,
            ),
          ],
        ],
      ),
    );
  }
}

/// Top-bar notification bell.
///
/// Swaps between two state-driven bell SVGs:
///   * [hasUnread] `false` ⇒ [BeauticaAssetIcons.notificationPlain] (dotless
///     bell, flattened to [BrandColors.textSecondary] via `srcIn`);
///   * [hasUnread] `true`  ⇒ [BeauticaAssetIcons.notificationUnread] (the same
///     bell silhouette with a baked-in warm red-orange dot at the top-right).
///
/// The unread asset is two-tone, so it renders with `multicolor: true` (no
/// `srcIn` flatten) — that keeps the dot red instead of repainting it to the
/// bell colour. There is **no** `Positioned`/`Stack` overlay dot (it caused a
/// double-dot bug); the dot lives inside the asset and is purely state-driven.
///
/// Moved here (public, no longer `@visibleForTesting`) from `home_hub_screen`
/// so all three CLIENT branch roots share it. The unread-gating regression test
/// pumps it with `hasUnread: true` (production call sites are pinned to `false`
/// until the Phase 14.9 notification provider ships).
class BellButton extends StatelessWidget {
  const BellButton({
    super.key,
    required this.onTap,
    required this.semanticLabel,
    this.hasUnread = false,
  });

  /// Key on the rendered bell icon — stable across both states so a widget test
  /// can grab the [AppIcon] and assert which asset path it points at.
  static const Key bellIconKey = Key('home_hub_bell_icon');

  final VoidCallback onTap;
  final String semanticLabel;

  /// Whether to render the unread-state bell (dot baked into the asset).
  ///
  // TODO(14.9): bind from the unread-notifications provider once the
  // notification center ships (watch the unread count/flag and pass `> 0`).
  // Until then it defaults to `false` so the dotless bell is shown.
  final bool hasUnread;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.all(VelvetSpacing.xs),
          child: hasUnread
              ? const AppIcon(
                  BeauticaAssetIcons.notificationUnread,
                  key: bellIconKey,
                  size: 24,
                  // Two-tone asset: skip the srcIn flatten so the red dot
                  // survives. The bell colour is baked into the SVG to match
                  // the idle bell's tint.
                  multicolor: true,
                )
              : const AppIcon(
                  BeauticaAssetIcons.notificationPlain,
                  key: bellIconKey,
                  size: 24,
                  color: BrandColors.textSecondary,
                ),
        ),
      ),
    );
  }
}
