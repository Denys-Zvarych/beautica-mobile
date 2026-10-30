import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/shared/widgets/velvet_banner.dart';

/// Shared screen chrome for the auth flow: safe-area aware, scrollable so the
/// keyboard never clips fields, with an optional inset back button.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.child,
    this.showBack = true,
    this.onBack,
    this.bottomBar,
  });

  final Widget child;
  final bool showBack;

  /// Called when the user taps the back affordance.
  ///
  /// Defaults to [GoRouter.pop] (`context.pop()`) when null, which is correct
  /// for screens that arrive via [GoRouter.push] (e.g. /forgot-password, /reset-password).
  ///
  /// Wizard screens that arrive via [GoRouter.go] MUST supply an explicit
  /// callback (e.g. `onBack: () => context.go(RouteNames.register)`) because
  /// [context.go] replaces the stack, leaving [maybePop] with nothing to pop.
  final VoidCallback? onBack;

  /// Pinned to the bottom (above the safe area) — used for the primary CTA so
  /// it never scrolls away.
  final Widget? bottomBar;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BrandColors.base,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              // The back button is overlaid (Stack) rather than placed in its
              // own row, so its presence never pushes the brand header down —
              // the logo sits at an identical vertical position on every
              // screen, with or without a back affordance.
              child: Stack(
                children: <Widget>[
                  SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(
                      VelvetSpacing.lg,
                      VelvetSpacing.lg,
                      VelvetSpacing.lg,
                      VelvetSpacing.xl,
                    ),
                    child: child,
                  ),
                  if (showBack)
                    Positioned(
                      top: VelvetSpacing.md,
                      left: VelvetSpacing.lg,
                      child: NeumorphicIconButton(
                        key: const ValueKey<String>('auth_scaffold_back'),
                        icon: Icons.arrow_back_ios_new_rounded,
                        semanticLabel: 'Назад',
                        onTap: onBack ?? () => context.pop(),
                      ),
                    ),
                ],
              ),
            ),
            if (bottomBar != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  VelvetSpacing.lg,
                  VelvetSpacing.sm,
                  VelvetSpacing.lg,
                  VelvetSpacing.md,
                ),
                child: bottomBar,
              ),
          ],
        ),
      ),
    );
  }
}

/// The auth flow's inline banner — PROMOTED (REUSE-FIRST, phase 424) to
/// `shared/widgets/velvet_banner.dart` as [VelvetBanner] so the moderation
/// report sheet renders the same banner. This alias keeps every auth call site
/// and test (`find.byType(AuthBanner)`) pointing at the one shared class.
typedef AuthBanner = VelvetBanner;
