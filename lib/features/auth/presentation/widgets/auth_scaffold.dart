import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';

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
  /// Defaults to [Navigator.maybePop] when null, which is correct for screens
  /// that arrive via [GoRouter.push] (e.g. /forgot-password, /reset-password).
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
                        icon: Icons.arrow_back_ios_new_rounded,
                        semanticLabel: 'Назад',
                        onTap: onBack ?? () => Navigator.of(context).maybePop(),
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

/// A dismissible inline banner for form-level (non-field) feedback such as the
/// login "email not verified" state. Pairs an icon + text + optional action so
/// meaning never relies on color alone.
class AuthBanner extends StatelessWidget {
  const AuthBanner({
    super.key,
    required this.icon,
    required this.message,
    required this.color,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final Color color;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      container: true,
      child: NeumorphicCard(
        padding: const EdgeInsets.all(VelvetSpacing.md),
        shadows: VelvetShadows.extrudedSmall,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, color: color, size: 20),
            const SizedBox(width: VelvetSpacing.sm + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    message,
                    style: VelvetText.feedback(
                      BrandColors.text,
                    ).copyWith(height: 1.45),
                  ),
                  if (actionLabel != null && onAction != null) ...<Widget>[
                    const SizedBox(height: VelvetSpacing.sm),
                    GestureDetector(
                      onTap: onAction,
                      child: Text(
                        actionLabel!,
                        style: VelvetText.link().copyWith(color: color),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
