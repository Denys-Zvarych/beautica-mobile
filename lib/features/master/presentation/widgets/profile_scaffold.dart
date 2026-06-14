// Phase 4.2 — ProfileScaffold for master-profile screens.
//
// Ported verbatim from the approved preview app at
// `docs/signup-designs/MasterProfileScreen/lib/widgets/profile_scaffold.dart`.
//
// Changes from the preview:
//   • VelvetColors.* → BrandColors.*
//   • VelvetSpacing.* → VelvetSpacing.* (same constants in velvet_geometry.dart)
//   • VelvetText.* unchanged (same names in velvet_text.dart)
//   • maybePop() calls migrated to `context.pop()` (go_router)
//   • `bottomNavBar` parameter dropped — bottom nav is a later-phase shell concern

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/widgets/app_refresh_indicator.dart';
import 'package:beautica_mobile/shared/widgets/velvet_top_bar.dart';

/// Shared chrome for master-profile screens: a safe-area aware [Scaffold] with
/// a fixed top bar (back + centred title + optional trailing action) and a
/// scrollable body.
///
/// All three AsyncValue states (loaded / loading / error) pass their content
/// through [child] so the header sits at an identical position everywhere.
///
/// When [onRefresh] is non-null the scrollable body is wrapped in an
/// [AppRefreshIndicator] so the user can pull down to reload data.  The
/// callback must return a [Future] that completes when the reload is done;
/// the spinner stays visible until the future resolves.
class ProfileScaffold extends StatelessWidget {
  const ProfileScaffold({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.showBack = true,
    this.bottomNavBar,
    this.onRefresh,
  });

  final String title;
  final Widget child;

  /// Top-right action widget (the edit [NeumorphicIconButton] on the loaded
  /// state; absent during loading and error states).
  final Widget? trailing;

  /// Whether to show the back button in the top-left. Defaults to `true`.
  final bool showBack;

  /// Optional bottom navigation bar rendered below the scrollable body,
  /// outside the scroll area. Pass [VelvetBottomNavBar] here for the master
  /// profile shell. When null, no bottom bar is rendered.
  final Widget? bottomNavBar;

  /// When non-null, the scrollable body is wrapped in an [AppRefreshIndicator].
  /// Call `ref.invalidate(provider)` + `await ref.read(provider.future)` here
  /// to reload remote data and dismiss the spinner.
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BrandColors.base,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // Top bar — fixed height so the title never shifts between states.
            VelvetTopBar(
              title: title,
              onBack: showBack ? () => context.pop() : null,
              trailing: trailing,
            ),
            // Fix 2 (PERF HIGH-2): RepaintBoundary prevents the static top bar
            // from being rasterized again during animation frames driven by the
            // entrance stagger — only the scrollable body layer is repainted.
            Expanded(child: RepaintBoundary(child: _buildScrollable(child))),
            // Bottom navigation bar — rendered outside the scroll area so it
            // always sits at the bottom of the screen. Null-safe: omitted when
            // [bottomNavBar] is not provided.
            ?bottomNavBar,
          ],
        ),
      ),
    );
  }

  /// Builds the scrollable body. When [onRefresh] is non-null, wraps the
  /// [SingleChildScrollView] in an [AppRefreshIndicator] so the user can pull
  /// down to reload. The [AlwaysScrollableScrollPhysics] parent ensures the
  /// scroll physics always allow the indicator to be triggered, even when
  /// content underflows the viewport.
  Widget _buildScrollable(Widget content) {
    final Widget scrollable = SingleChildScrollView(
      // AlwaysScrollableScrollPhysics ensures the RefreshIndicator gesture is
      // always interceptable, even when the content is shorter than the
      // viewport (e.g. loading skeleton or error state).
      physics: onRefresh != null
          ? const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics())
          : const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        VelvetSpacing.lg,
        VelvetSpacing.md,
        VelvetSpacing.lg,
        VelvetSpacing.xxl,
      ),
      child: content,
    );

    final Future<void> Function()? refresh = onRefresh;
    if (refresh == null) return scrollable;

    return AppRefreshIndicator(onRefresh: refresh, child: scrollable);
  }
}
