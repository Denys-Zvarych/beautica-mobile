// Phase 4.2 — ProfileScaffold for master-profile screens.
//
// Ported verbatim from the approved preview app at
// `docs/signup-designs/MasterProfileScreen/lib/widgets/profile_scaffold.dart`.
//
// Changes from the preview:
//   • VelvetColors.* → BrandColors.*
//   • VelvetSpacing.* → VelvetSpacing.* (same constants in velvet_geometry.dart)
//   • VelvetText.* unchanged (same names in velvet_text.dart)
//   • `Navigator.of(context).maybePop()` → `context.pop()` (go_router)
//   • `bottomNavBar` parameter dropped — bottom nav is a later-phase shell concern

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';

/// Shared chrome for master-profile screens: a safe-area aware [Scaffold] with
/// a fixed top bar (back + centred title + optional trailing action) and a
/// scrollable body.
///
/// All three AsyncValue states (loaded / loading / error) pass their content
/// through [child] so the header sits at an identical position everywhere.
class ProfileScaffold extends StatelessWidget {
  const ProfileScaffold({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.showBack = true,
    this.bottomNavBar,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BrandColors.base,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // Top bar — fixed height so the title never shifts between states.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                VelvetSpacing.lg,
                VelvetSpacing.md,
                VelvetSpacing.lg,
                VelvetSpacing.xs,
              ),
              child: SizedBox(
                height: 48,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    if (showBack)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: NeumorphicIconButton(
                          icon: Icons.arrow_back_ios_new_rounded,
                          semanticLabel: 'Назад',
                          onTap: () => context.pop(),
                        ),
                      ),
                    Text(
                      title,
                      style: VelvetText.subheading(),
                      textAlign: TextAlign.center,
                    ),
                    if (trailing != null)
                      Align(alignment: Alignment.centerRight, child: trailing),
                  ],
                ),
              ),
            ),
            // Fix 2 (PERF HIGH-2): RepaintBoundary prevents the static top bar
            // from being rasterized again during animation frames driven by the
            // entrance stagger — only the scrollable body layer is repainted.
            Expanded(
              child: RepaintBoundary(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    VelvetSpacing.lg,
                    VelvetSpacing.md,
                    VelvetSpacing.lg,
                    VelvetSpacing.xxl,
                  ),
                  child: child,
                ),
              ),
            ),
            // Bottom navigation bar — rendered outside the scroll area so it
            // always sits at the bottom of the screen. Null-safe: omitted when
            // [bottomNavBar] is not provided.
            ?bottomNavBar,
          ],
        ),
      ),
    );
  }
}
