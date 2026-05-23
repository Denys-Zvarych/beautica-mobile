// Phase 2.9 — Splash / cold-start parking screen.
//
// Displayed while [authProvider] is in the AsyncLoading state (i.e. the app
// is determining whether a stored refresh token exists and whether it is still
// valid). The [authRedirect] guard keeps unauthenticated and authenticated
// users parked here until the session is settled.
//
// Once [authProvider] resolves:
//   - Authenticated → guard sends user to RouteNames.home.
//   - Unauthenticated → guard sends user to RouteNames.login.
//
// No user interaction is expected here; there is intentionally no retry or
// skip button.
//
// Animation: logo scale (0.5→1.0) + opacity (0→1) over 800 ms using
// [Curves.easeOutBack]. The progress indicator fades in after the logo
// animation completes. Both animations are skipped when the OS
// [MediaQueryData.disableAnimations] flag is set (reduced-motion support).

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/brand_colors.dart';
import 'auth_gradient_background.dart';

/// Cold-start parking screen shown while the auth session resolves.
///
/// Displays the Beautica logo with a cinematic scale+fade entrance animation
/// and a branded progress indicator. The animation is skipped automatically
/// when the system's reduced-motion preference is active.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _logoCtrl;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;

  bool _showSpinner = false;

  @override
  void initState() {
    super.initState();

    _logoCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _logoScale = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOutBack));

    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoCtrl,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _logoCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _showSpinner = true);
      }
    });

    // Defer reduced-motion check to post-frame so MediaQuery is available.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.of(context).disableAnimations) {
        _logoCtrl.value = 1.0;
        if (mounted) setState(() => _showSpinner = true);
      } else {
        _logoCtrl.forward();
      }
    });
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Warm Mocha palette — must match the shared AuthGradientBackground
      // (espresso #0D0906), not the legacy navy midnight.
      backgroundColor: BrandColors.base,
      body: Stack(
        children: [
          // PERF: RepaintBoundary hoists the gradient layer so the logo
          // scale+fade entrance animation does not invalidate the background
          // on every frame. AuthGradientBackground also has an internal
          // RepaintBoundary; the duplicate is coalesced by Flutter. The
          // background itself is now a single LinearGradient draw call
          // (was a 288 k drawRect Bayer-dither painter; reverted 2026-05-20
          // — measured ~2.5 s GPU raster/frame on Mali-G52).
          const RepaintBoundary(child: AuthGradientBackground()),
          // Align at (0, -0.4) shifts the logo into the upper-middle zone —
          // roughly 38% from the top — rather than dead centre.
          Align(
            alignment: const Alignment(0.0, -0.4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // FadeTransition drives opacity via the animation object directly,
                // avoiding the per-frame SaveLayer that Opacity(opacity: x!=1)
                // would create. The inner AnimatedBuilder handles only scale.
                FadeTransition(
                  opacity: _logoOpacity,
                  child: AnimatedBuilder(
                    animation: _logoScale,
                    builder: (_, child) =>
                        Transform.scale(scale: _logoScale.value, child: child),
                    child: SvgPicture.asset(
                      'assets/images/logo.svg',
                      width: 200,
                      semanticsLabel: 'Beautica',
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                AnimatedOpacity(
                  opacity: _showSpinner ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: const CircularProgressIndicator(
                    color: BrandColors.accent,
                    strokeWidth: 2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
