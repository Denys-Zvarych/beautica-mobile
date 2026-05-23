// Shared auth screen scaffold — Phase 2.x visual redesign (Defect 2 fix).
//
// Both the login and register screens previously built their own
// Scaffold → Stack → SafeArea → (Center | LayoutBuilder) → SingleChildScrollView
// → ConstrainedBox tree. Login additionally wrapped its column in an
// IntrinsicHeight and used a Spacer() to bottom-anchor the register row;
// register wrapped its content in a Center. Those two structurally different
// trees gave the brand row a different vertical origin on each screen, so the
// logo + form visibly jumped when switching Login ↔ Register (and between
// register steps).
//
// [AuthScaffold] is the single source of truth for the outer geometry. Every
// auth screen passes only its screen-specific column content as [child]; the
// scaffold guarantees identical:
//   - Warm Mocha linear-gradient background (AuthGradientBackground)
//   - SafeArea inset
//   - 16 px symmetric horizontal scroll padding
//   - minHeight == viewport height (so short content still fills the screen
//     WITHOUT a Spacer/Center/IntrinsicHeight, which is what caused the jump)
//   - maxWidth 400 content column
//
// The brand row + its surrounding fixed gaps live in the screen-specific
// [child] so callers can keep identical top geometry; this widget only owns
// the box the column lives in.

import 'package:flutter/material.dart';

import '../../core/theme/brand_colors.dart';
import '../../features/auth/presentation/auth_gradient_background.dart';

/// Shared outer scaffold for the auth screens (login + register).
///
/// Provides the Warm Mocha linear-gradient background, safe area, a
/// single scroll view, and a `minHeight == viewport` constrained 400 px-wide
/// column. The [child] is the screen-specific column content (brand row,
/// headline, form, etc.).
///
/// Removing the per-screen `Spacer` / `Center` / `IntrinsicHeight` in favour
/// of one `ConstrainedBox(minHeight: viewport)` is the validated fix for the
/// vertical jump (UX rule: content-jumping — reserve identical space across
/// screens instead of letting layout push content around).
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.child});

  /// The screen-specific column content. Callers are responsible for the
  /// shared top geometry (a leading `SizedBox(height: 24)` then the brand
  /// row then `SizedBox(height: 36)`) so every auth screen lands the brand
  /// row at the exact same Y.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BrandColors.base,
      body: Stack(
        children: [
          // PERF: Belt-and-braces — AuthGradientBackground also wraps itself
          // in a RepaintBoundary internally. Wrapping again at the call site
          // guarantees the layer is hoisted even if a future refactor inside
          // AuthGradientBackground removes the inner boundary. Flutter
          // coalesces adjacent RepaintBoundary widgets, so this is free.
          const RepaintBoundary(child: AuthGradientBackground()),
          SafeArea(
            child: LayoutBuilder(
              builder: (ctx, c) => SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: c.maxHeight,
                    maxWidth: 400,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
