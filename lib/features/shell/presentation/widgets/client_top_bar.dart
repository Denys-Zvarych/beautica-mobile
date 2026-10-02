// Phase 13.3 — Shared CLIENT top bar (wordmark · bell · burger).
//
// Extracted from the byte-identical private `_TopBar` that lived in BOTH
// `home_hub_screen.dart` and `passport_screen.dart`, plus the `BellButton` (now the shared
// `NotificationBellButton`, Phase 361) that
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
//   • the notification [NotificationBellButton] (idle / unread states baked into the SVG);
//   • an OPTIONAL [NeumorphicIconButton] burger on the right.
//
// The bell + burger semantic labels and the burger [Key] are supplied by the
// caller so each host page keeps its own stable test target
// (`btn-menu-client` / `btn-menu-passport`). The burger is optional: Пошук omits
// it (the settings hub it opens is redundant there), so the bell becomes the
// last trailing element on that page.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/beautica_icons.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/shared/widgets/notification_bell_button.dart';

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
    this.bell,
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

  /// Optional bell slot. When non-null it REPLACES the pure
  /// [NotificationBellButton] (and [onBell] / [bellKey] / [hasUnread] /
  /// [bellSemanticLabel] are then unused), so a host can mount a self-watching
  /// bell (`ConnectedNotificationBell`) and keep the unread-flag rebuild scoped
  /// to the bell alone. Omitted, the bar renders exactly as before.
  final Widget? bell;

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
          bell ??
              NotificationBellButton(
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
