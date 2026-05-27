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
// Phase 2.15 — Native-splash handoff:
//   The native splash (warm taupe #E6DDD0 bg + composite B + "beautica" PNG)
//   is preserved by [FlutterNativeSplash.preserve] in main() and dismissed
//   here via [FlutterNativeSplash.remove] inside [initState]. Because the OS
//   splash PNG already shows the full composite, the handoff to the Flutter
//   splash is visually seamless even with zero animation in the static path.
//
// Splash content — Lottie or static:
//   On mount the splash probes for `assets/lottie/splash_wordmark.json` via
//   `rootBundle.load()`. If the asset loads:
//     - Lottie path: B pillow alone (showWordmark: false) + Lottie.asset()
//       rendering the animated wordmark beneath it.
//   If the asset is missing:
//     - Static path: standard [VelvetLogo] (B pillow + plain "beautica" Text).
//       This is the visual baseline that exactly mirrors the OS-baked splash
//       PNG, so the cold-start handoff has zero visible jump.
//
//   Regardless of which path renders, a [Timer] for the remaining
//   [AppStartTime.minSplashDuration] kicks the GoRouter so we exit /splash
//   into /login or /home as soon as the gate is satisfied.
//
// Why no AnimationController here:
//   Earlier iterations used an [AnimationController]-driven letter-by-letter
//   reveal ([AnimatedWordmark]). On Android 12 release AOT builds, the Ticker
//   did not deliver vsync ticks during the OS native-splash phase, causing the
//   animation to snap to its end state in a single frame. A Lottie file —
//   pre-rendered frame data — sidesteps the Ticker entirely; the animation
//   plays at its baked frame rate from frame 0 the moment the widget mounts.
//   Until the user drops a `.json` file in, the static fallback renders the
//   exact same composite the OS splash PNG already shows.
//
// Why no ScreenProtector here:
//   The splash screen displays only the branded "beautica" wordmark — no
//   passwords, OTP codes, or user data are ever rendered. ScreenProtector is
//   reserved for screens with sensitive fields (login, verification, register,
//   reset-password, invite-accept, settings).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';

import '../../../core/app_start_time.dart';
import '../../../core/theme/brand_colors.dart';
import '../../../core/widgets/neumorphic.dart';

/// Path of the optional Lottie wordmark animation. When this asset is
/// bundled, the Lottie widget renders; otherwise the static fallback runs.
/// File-scope so [_LottieSplashContent] can reference it without poking into
/// `_SplashScreenState`'s private fields.
const String _lottieAssetPath = 'assets/lottie/splash_wordmark.json';

/// Cold-start parking screen shown while the auth session resolves.
///
/// Displays the Beautica logo. When `assets/lottie/splash_wordmark.json` is
/// bundled, the wordmark is rendered as a Lottie animation; otherwise the
/// static [VelvetLogo] is shown (matching the OS-baked native splash PNG so
/// the handoff is seamless).
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  /// Minimum splash wall-clock duration in milliseconds. Single source of
  /// truth: [AppStartTime.minSplashDuration].
  static final int _minSplashMs = AppStartTime.minSplashDuration.inMilliseconds;

  Timer? _splashTimer;
  bool _lottieAvailable = false;

  @override
  void initState() {
    super.initState();

    // Dismiss the native splash immediately. initState only fires while the
    // widget IS mounted, so there is no risk of releasing the native overlay
    // after the widget is gone. FlutterNativeSplash.remove() is idempotent:
    // if main() already released the overlay (returning-user bypass path
    // where go_router skips /splash entirely), this call is a safe no-op.
    FlutterNativeSplash.remove();

    // Anchor the splash-duration gate to the moment Flutter's surface becomes
    // visible, NOT to app entry. Native splash + Dart VM init can take >1s on
    // Android 12 cold starts, which would otherwise pre-expire the 2000 ms
    // gate and cause go_router to redirect to /login before the splash can
    // paint a single frame.
    AppStartTime.record();

    // Probe for the optional Lottie animation asynchronously. The widget
    // mounts immediately with the static fallback; if the asset resolves
    // before the splash exits, the Lottie path takes over via setState().
    _checkLottieAsset();

    // Schedule a router refresh at minSplashDuration regardless of which
    // wordmark path renders. In release AOT builds the auth provider can
    // resolve synchronously before the first Flutter frame, in which case
    // GoRouter fires its redirect once (returning /splash because elapsed <
    // _minSplashMs) and then goes quiet — authProvider never emits again, so
    // AuthRefreshNotifier never calls notifyListeners() and the router never
    // re-evaluates. The timer below kicks it so we exit /splash on schedule.
    final int remaining =
        _minSplashMs -
        AppStartTime.elapsed().inMilliseconds.clamp(0, _minSplashMs);
    _splashTimer = Timer(Duration(milliseconds: remaining), () {
      if (!mounted) return;
      // `GoRouter.of(context)` throws if no router ancestor exists (common in
      // widget tests that use a plain MaterialApp). Catch and no-op so the
      // timer is safe in any tree.
      try {
        GoRouter.of(context).refresh();
      } catch (_) {
        // No router in this tree — tests typically. The widget is the visible
        // result and that's all that matters in that context.
      }
    });
  }

  /// Attempts to load the Lottie wordmark asset. If successful, flips the
  /// build to render `Lottie.asset(...)` in place of the static wordmark.
  /// On any failure (FlutterError "Unable to load asset", FileSystemException
  /// in tests, etc.) the static fallback is kept silently — this is the
  /// expected baseline state until the user drops the JSON file in.
  Future<void> _checkLottieAsset() async {
    try {
      await rootBundle.load(_lottieAssetPath);
      if (!mounted) return;
      setState(() => _lottieAvailable = true);
    } catch (_) {
      // Asset missing — keep static fallback. Intentionally silent: missing
      // file is the documented baseline, not an error condition.
    }
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BrandColors.base,
      body: Stack(
        children: <Widget>[
          Align(
            alignment: const Alignment(0.0, -0.4),
            child: _lottieAvailable
                ? const _LottieSplashContent()
                : const VelvetLogo(
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

/// Renders the B pillow + a [Lottie.asset] wordmark animation. Used when the
/// optional `assets/lottie/splash_wordmark.json` is bundled. The B pillow is
/// reused from [VelvetLogo] with `showWordmark: false` so the Lottie file owns
/// the wordmark slot exclusively.
class _LottieSplashContent extends StatelessWidget {
  const _LottieSplashContent();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const VelvetLogo(tileSize: 92, markFontSize: 42, showWordmark: false),
        const SizedBox(height: 16),
        Lottie.asset(
          _lottieAssetPath,
          width: 400,
          height: 80,
          fit: BoxFit.contain,
          repeat: false,
        ),
      ],
    );
  }
}
