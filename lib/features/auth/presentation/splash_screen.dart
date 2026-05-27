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
//   The native splash (warm taupe #E6DDD0 bg + B-only pillow PNG) is preserved
//   by [FlutterNativeSplash.preserve] in main() and dismissed here via
//   [FlutterNativeSplash.remove] inside [initState]. The OS PNG intentionally
//   shows the B pillow ONLY — the "beautica" wordmark is reserved for the
//   Flutter-side Lottie reveal so the user sees the brand name appear for
//   the FIRST time via the animation (no double-wordmark on cold start).
//
// Splash content — tri-state probe:
//   The Lottie asset is bundled today, but the splash is robust to a missing
//   asset. On mount, [_checkLottieAsset] probes for
//   `assets/lottie/splash_wordmark.json` via `rootBundle.load()` and the
//   build switches on a tri-state [_lottieAvailable] (`bool?`):
//
//     null  → probing. Render B pillow ONLY (showWordmark: false). This
//             suppresses any flash of the static "beautica" text before the
//             Lottie kicks in, preserving the "wordmark appears via Lottie"
//             promise.
//     true  → Lottie asset resolved. Render B pillow + Lottie.asset() reveal
//             animation beneath it.
//     false → Lottie asset failed to load. Fall back to the full static
//             composite (B pillow + plain "beautica" Text) so the user still
//             sees the brand wordmark — better a static name than no name.
//
//   Regardless of which state renders, a [Timer] for the remaining
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
//   When Lottie resolution fails the static composite is shown as a
//   degraded fallback so the wordmark is at least visible.
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
/// Tri-state render driven by [_SplashScreenState._lottieAvailable]:
///   - `null`  (probing) → B pillow only, wordmark suppressed so the Lottie
///     reveal is the first place the user sees "beautica".
///   - `true`  → B pillow + Lottie wordmark reveal.
///   - `false` (Lottie asset failed) → static [VelvetLogo] composite as a
///     fallback so the user still gets the wordmark.
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

  /// Tri-state Lottie asset probe:
  ///
  ///   null  → still probing (the rootBundle.load() future has not resolved).
  ///           Render the B pillow ONLY so the wordmark first appears via the
  ///           Lottie reveal (no static-text flash before the animation).
  ///   true  → asset resolved. Render the Lottie reveal animation.
  ///   false → asset failed. Fall back to the full static composite so the
  ///           wordmark is at least visible.
  bool? _lottieAvailable;

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
    // mounts immediately in the probing state (B pillow only, wordmark
    // suppressed); when the rootBundle.load() future resolves the build
    // flips to either the Lottie path or the static-composite fallback via
    // setState() inside [_checkLottieAsset].
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

  /// Attempts to load the Lottie wordmark asset. Flips [_lottieAvailable]
  /// from `null` (probing) to either `true` (Lottie ready — render the
  /// animation) or `false` (asset failed — render the static composite as a
  /// fallback so the user still sees the wordmark).
  ///
  /// While [_lottieAvailable] is still `null`, the build deliberately renders
  /// the B pillow ALONE so the wordmark's first appearance is the Lottie
  /// reveal — no static-text flash beats the animation.
  Future<void> _checkLottieAsset() async {
    try {
      await rootBundle.load(_lottieAssetPath);
      if (!mounted) return;
      setState(() => _lottieAvailable = true);
    } catch (_) {
      // Asset missing — fall back to the full static composite so the user
      // still sees the brand wordmark. Better a static name than no name.
      if (!mounted) return;
      setState(() => _lottieAvailable = false);
    }
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Tri-state render: while probing, the wordmark is intentionally
    // suppressed so the Lottie reveal owns the brand's first appearance.
    final Widget content;
    switch (_lottieAvailable) {
      case true:
        content = const _LottieSplashContent();
      case false:
        // Lottie genuinely failed — show the full static composite so the
        // user still gets the wordmark.
        content = const VelvetLogo(
          tileSize: 92,
          markFontSize: 42,
          wordmarkFontSize: 17,
        );
      case null:
        // Probing — B pillow only. The Lottie animation will be the first
        // place the user sees "beautica".
        content = const VelvetLogo(
          tileSize: 92,
          markFontSize: 42,
          showWordmark: false,
        );
    }
    return Scaffold(
      backgroundColor: BrandColors.base,
      body: Stack(
        children: <Widget>[
          // Matches the Android 12 OS native splash icon position so the handoff doesn't visibly jump.
          Align(alignment: Alignment.center, child: content),
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
