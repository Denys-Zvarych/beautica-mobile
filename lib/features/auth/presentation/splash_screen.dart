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
//   via [FlutterNativeSplash.remove] directly inside [initState].
//
// Why initState, not addPostFrameCallback:
//   In release AOT, the auth provider (SecureStorage) resolves synchronously
//   before the first Flutter frame is painted. go_router therefore redirects
//   to /login or /home before SplashScreen gets a chance to paint, which means
//   the widget is either never mounted or is immediately disposed. An
//   addPostFrameCallback fires AFTER the first frame — i.e. after go_router
//   has already navigated away — so mounted == false and forward() is never
//   called. Starting the animation in initState avoids this race entirely:
//   initState runs while the widget IS mounted, and AnimationController
//   schedules its own ticker via vsync without needing a rendered frame.
//
// Splash animation — letter-by-letter wordmark reveal:
//   The [CircularProgressIndicator] + Timer have been replaced by an
//   [AnimatedWordmark] that reveals "beautica" letter-by-letter over 880 ms.
//   Each letter fades in and slides up with a 90 ms stagger. The animation
//   serves as both a brand moment and a visual loading indicator.
//   Reduced-motion: when [accessibilityFeatures.disableAnimations] is true the
//   controller is snapped to its end value so all letters appear immediately.
//   (MediaQuery is unavailable in initState; accessibilityFeatures reads the
//   same underlying platform flag.)

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:screen_protector/screen_protector.dart';

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

    // Phase 2.15 fix — dismiss native splash immediately when this State is
    // created. initState only fires while the widget IS mounted, so there is
    // no risk of releasing the native overlay after the widget is gone.
    // FlutterNativeSplash.remove() is idempotent: if main() already released
    // the overlay (returning-user bypass path where go_router skips /splash
    // entirely), this call is a safe no-op.
    FlutterNativeSplash.remove();

    // MASVS-PLATFORM / MS6 — prevent OS-level screenshot / screen recording
    // while the splash (and therefore the auth flow entry point) is visible.
    // Mirrors the same guard used on every other auth screen.
    if (!kDebugMode) {
      ScreenProtector.preventScreenshotOn();
    }

    // Start the animation immediately. AnimationController schedules its own
    // ticker via vsync and does not need a rendered frame — no
    // addPostFrameCallback required. MediaQuery is unavailable in initState;
    // accessibilityFeatures reads the same underlying platform disableAnimations
    // flag via the engine and is available from the very first frame.
    if (WidgetsBinding.instance.accessibilityFeatures.disableAnimations) {
      // Snap all letters to fully visible — no per-tick animation.
      _wordmarkController.value = 1.0;
    } else {
      _wordmarkController.forward();
    }
  }

  @override
  void dispose() {
    if (!kDebugMode) {
      ScreenProtector.preventScreenshotOff();
    }
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
