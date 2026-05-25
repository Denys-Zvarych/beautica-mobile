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
//   Because the native splash already shows the logo at rest (scale 1.0), the
//   previous _logoScale Tween ran 1.0→1.0 (no-op). It has been removed to avoid
//   the unnecessary AnimatedBuilder rebuild + Matrix4 allocation on every tick.
//   The opacity fade and the spinner fade-in are preserved unchanged.
//   Reduced-motion: the native splash itself is OS-owned and cannot be skipped,
//   but the Flutter-side animation respects [MediaQueryData.disableAnimations].
//
// AnimationController replaced with Timer in Batch 6 perf fix — the 1.0→1.0
// FadeTransition was a no-op and has been removed.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/brand_colors.dart';
import '../../../core/widgets/neumorphic.dart';

/// Cold-start parking screen shown while the auth session resolves.
///
/// Displays the Beautica logo with a branded progress indicator. The spinner
/// is revealed after 800 ms via a cancellable [Timer] (or immediately when the
/// system's reduced-motion preference is active).
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _spinnerTimer;

  bool _showSpinner = false;

  @override
  void initState() {
    super.initState();

    // Phase 2.15 — dismiss native splash on first Flutter frame.
    // FlutterNativeSplash.remove() is idempotent and safe even if preserve()
    // was not called (debug mode).
    // Defer reduced-motion check to post-frame so MediaQuery is available.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FlutterNativeSplash.remove();
      if (!mounted) return;
      if (MediaQuery.of(context).disableAnimations) {
        if (mounted) setState(() => _showSpinner = true);
      } else {
        _spinnerTimer = Timer(const Duration(milliseconds: 800), () {
          if (mounted) setState(() => _showSpinner = true);
        });
      }
    });
  }

  @override
  void dispose() {
    _spinnerTimer?.cancel();
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
                const VelvetLogo(),
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
