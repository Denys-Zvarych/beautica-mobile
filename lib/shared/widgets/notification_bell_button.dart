// Phase 361 — the ONE notification bell, shared by every role's header.
//
// [NotificationBellButton] is the pure, state-driven glyph (promoted from
// `ClientTopBar`'s `BellButton`, and replacing the salon hub's private
// `_BellButton` mirror). [ConnectedNotificationBell] wraps it with the global
// unread flag and the route push, so a header only has to drop it in.
//
// GLOBAL by design: the connected bell reads ONLY
// [hasUnreadNotificationsProvider] (per user, across every salon an owner
// owns). It must never read a salon-scoped provider — switching salons never
// changes the dot.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/features/notifications/presentation/unread_notifications_notifier.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';

/// Notification bell glyph.
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
/// Pure: [hasUnread] is an explicit parameter (goldens pump both states). Use
/// [ConnectedNotificationBell] in production headers.
class NotificationBellButton extends StatelessWidget {
  const NotificationBellButton({
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

/// Builds the bell visual for a host header from the live unread flag, the
/// localised accessible name and the tap handler.
typedef NotificationBellBuilder =
    Widget Function(
      BuildContext context,
      bool hasUnread,
      String semanticLabel,
      VoidCallback onTap,
    );

/// The bell every header mounts: reads the GLOBAL unread flag and opens the
/// notification feed on tap.
///
/// [builder] is an additive hook for headers whose approved design draws the
/// bell inside its own chrome (e.g. the salon cover's `CoverIconButton`); it
/// receives the same flag, label and tap. Omitted, the plain
/// [NotificationBellButton] renders.
class ConnectedNotificationBell extends ConsumerWidget {
  const ConnectedNotificationBell({super.key, this.buttonKey, this.builder});

  /// Optional [Key] forwarded to the default [NotificationBellButton].
  final Key? buttonKey;

  /// Optional custom visual (see class doc).
  final NotificationBellBuilder? builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool hasUnread = ref.watch(hasUnreadNotificationsProvider);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String label = hasUnread
        ? l10n.notificationBellUnreadLabel
        : l10n.notificationBellLabel;
    void onTap() => context.push(RouteNames.notifications);

    final NotificationBellBuilder? custom = builder;
    if (custom != null) return custom(context, hasUnread, label, onTap);
    return NotificationBellButton(
      key: buttonKey,
      onTap: onTap,
      semanticLabel: label,
      hasUnread: hasUnread,
    );
  }
}
