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
// Phase 2.15 — Native-splash handoff (Option A — "Single continuous animation"):
//   The native splash (warm taupe #E6DDD0 bg + Beautica B mark at scale 1.0)
//   is preserved by [FlutterNativeSplash.preserve] in main() and dismissed here
//   via [FlutterNativeSplash.remove] on the first Flutter post-frame callback.
//   Because the native splash already shows the logo at its rest (scale 1.0)
//   pose, the _logoScale Tween now runs 1.0→1.0 (effectively a no-op for the
//   logo), eliminating any geometry jump at the handoff. The opacity fade and
//   the spinner fade-in are preserved unchanged.
//   Reduced-motion: the native splash itself is OS-owned and cannot be skipped,
//   but the Flutter-side animation respects [MediaQueryData.disableAnimations].
//
// Animation (post-Phase 2.15): logo opacity (0→1) over 800 ms [Curves.easeOut];
// logo scale is a no-op (1.0→1.0) preserving the Phase 2.10 architecture without
// removing the controller. Progress indicator fades in after the controller
// completes. Both animations skipped on reduced-motion.

import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/brand_colors.dart';

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

    // Phase 2.15 Option A: begin changed from 0.5 → 1.0 (no-op scale).
    // The native splash already shows the logo at rest (1.0) so removing the
    // 0.5→1.0 bounce here prevents a geometry jump at the handoff.
    _logoScale = Tween<double>(
      begin: 1.0,
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

    // Phase 2.15 — dismiss native splash on first Flutter frame, synchronised
    // with the start of the Phase 2.10 animation. FlutterNativeSplash.remove()
    // is idempotent and safe even if preserve() was not called (debug mode).
    // Defer reduced-motion check to post-frame so MediaQuery is available.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FlutterNativeSplash.remove();
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
      // VelvetTouch palette — warm taupe #E6DDD0 (= BrandColors.base).
      // Must match the native splash color in pubspec.yaml flutter_native_splash.color.
      backgroundColor: BrandColors.base,
      body: Stack(
        children: [
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
