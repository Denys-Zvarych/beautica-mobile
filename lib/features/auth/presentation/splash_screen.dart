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
//
// Splash animation — letter-by-letter wordmark reveal:
//   The [CircularProgressIndicator] + Timer have been replaced by an
//   [AnimatedWordmark] that reveals "beautica" letter-by-letter over 880 ms.
//   Each letter fades in and slides up with a 90 ms stagger. The animation
//   serves as both a brand moment and a visual loading indicator.
//   Reduced-motion: when [MediaQueryData.disableAnimations] is true the
//   controller is snapped to its end value so all letters appear immediately.

import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import '../../../core/theme/brand_colors.dart';
import '../../../core/widgets/neumorphic.dart';

/// Cold-start parking screen shown while the auth session resolves.
///
/// Displays the Beautica logo with an animated letter-by-letter wordmark
/// reveal. The [VelvetLogo] is rendered slightly larger than on other screens
/// to give the splash a premium, spacious feel.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  /// Total controller duration — covers 8 letters × 90 ms stagger + 250 ms
  /// per-letter duration = 630 + 250 = 880 ms.
  static const Duration _animDuration = Duration(milliseconds: 880);

  late final AnimationController _wordmarkController;

  @override
  void initState() {
    super.initState();
    _wordmarkController = AnimationController(
      vsync: this,
      duration: _animDuration,
    );

    // Phase 2.15 — dismiss native splash on first Flutter frame.
    // FlutterNativeSplash.remove() is idempotent and safe even if preserve()
    // was not called (debug mode).
    // Defer reduced-motion check to post-frame so MediaQuery is available.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FlutterNativeSplash.remove();
      if (!mounted) return;
      if (MediaQuery.of(context).disableAnimations) {
        // Snap all letters to fully visible — no per-tick animation.
        _wordmarkController.value = 1.0;
      } else {
        _wordmarkController.forward();
      }
    });
  }

  @override
  void dispose() {
    _wordmarkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // VelvetTouch palette — warm taupe #E6DDD0 (= BrandColors.base).
      // Must match the native splash color in pubspec.yaml flutter_native_splash.color.
      backgroundColor: BrandColors.base,
      body: Stack(
        children: <Widget>[
          // Align at (0, -0.4) shifts the logo into the upper-middle zone —
          // roughly 38% from the top — rather than dead centre.
          Align(
            alignment: const Alignment(0.0, -0.4),
            child: VelvetLogo(
              animationController: _wordmarkController,
              // Slightly larger on splash only — compact: false (default)
              // + explicit overrides keep all other call sites unchanged.
              tileSize: 92,
              markFontSize: 42,
              wordmarkFontSize: 17,
            ),
          ),
        ],
      ),
    );
  }
}
