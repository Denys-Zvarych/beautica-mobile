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
// Phase 2.15 — Native-splash handoff (revised 2026-05-27):
//   The OS native splash shows ONLY the warm-taupe background colour
//   (#E6DDD0) — no B-pillow, no logo, no wordmark. The Flutter splash is the
//   SOLE owner of any brand render. There is no static B-pillow on the
//   Flutter splash either — the Lottie wordmark reveal IS the entire splash
//   content. This eliminates the OS-baked-PNG vs Flutter-runtime
//   position+size mismatch users perceived on Android 12+ release builds AND
//   removes the leftover static "B" pillow the user reported seeing on the
//   splash ("now on splash screen I can see simple B but shouldn't").
//
//   [FlutterNativeSplash.preserve] in main() holds the OS bg until the first
//   Flutter frame; [FlutterNativeSplash.remove] in [initState] dismisses it.
//   What the user sees is: warm-taupe background only → warm-taupe background
//   + Lottie wordmark reveal.
//
// Splash content — tri-state probe:
//   The Lottie asset is bundled today, but the splash is robust to a missing
//   asset. On mount, [_checkLottieAsset] probes for
//   `assets/lottie/splash_wordmark.json` via `rootBundle.load()` and the
//   build switches on a tri-state [_lottieAvailable] (`bool?`):
//
//     null  → probing. Nothing rendered on top of the warm-taupe bg. The
//             Lottie reveal owns the wordmark's first appearance — no static
//             text flash beats the animation, and there is no B-pillow to
//             compete for attention.
//     true  → Lottie asset resolved. Lottie wordmark renders centred on the
//             warm-taupe bg.
//     false → Lottie asset failed to load. A plain Text("beautica") renders
//             centred on the warm-taupe bg as a fallback so the user still
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
//   When Lottie resolution fails the static Text fallback is shown so the
//   wordmark is at least visible.
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
import '../../../core/theme/velvet_text.dart';

/// Path of the optional Lottie wordmark animation. When this asset is
/// bundled, the Lottie widget renders; otherwise the static fallback runs.
const String _lottieAssetPath = 'assets/lottie/splash_wordmark.json';

/// Font size of the static-fallback wordmark Text. Kept identical to what
/// [VelvetLogo] uses internally when [VelvetLogo.wordmarkFontSize] is 17, so
/// the fallback path remains visually consistent with wordmark renders
/// elsewhere in the app (e.g. login/register screens).
const double _wordmarkFontSize = 17.0;

/// Cold-start parking screen shown while the auth session resolves.
///
/// Tri-state render driven by [_SplashScreenState._lottieAvailable]:
///   - `null`  (probing) → bg colour only; no widget rendered.
///   - `true`  → centred Lottie wordmark reveal on the warm-taupe bg.
///   - `false` (Lottie asset failed) → centred static "beautica" Text on the
///                                     warm-taupe bg.
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
  ///           Render nothing on top of the bg colour so the wordmark first
  ///           appears via the Lottie reveal (no static-text flash before
  ///           the animation, and no B-pillow competing for attention).
  ///   true  → asset resolved. Render the Lottie reveal animation centred.
  ///   false → asset failed. Render a static "beautica" Text centred so the
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
    // mounts immediately in the probing state (bg colour only, no widget);
    // when the rootBundle.load() future resolves the build flips to either
    // the Lottie path or the static-text fallback via setState() inside
    // [_checkLottieAsset].
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
  /// animation) or `false` (asset failed — render the static Text fallback so
  /// the user still sees the wordmark).
  ///
  /// While [_lottieAvailable] is still `null`, the build deliberately renders
  /// nothing on top of the bg colour so the wordmark's first appearance is
  /// the Lottie reveal — no static-text flash beats the animation.
  Future<void> _checkLottieAsset() async {
    try {
      await rootBundle.load(_lottieAssetPath);
      if (!mounted) return;
      setState(() => _lottieAvailable = true);
    } catch (_) {
      // Asset missing — fall back to a static Text("beautica") so the user
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
    // Single centred child driven by the tri-state probe:
    //   - probing  → SizedBox.shrink (bg colour alone, no widget visible).
    //   - Lottie   → the wordmark reveal animation.
    //   - fallback → a static "beautica" Text.
    //
    // There is intentionally NO static B-pillow on the splash. The Lottie
    // reveal (or its static-Text fallback) is the entire splash content.
    return Scaffold(
      backgroundColor: BrandColors.base,
      body: Center(
        child: switch (_lottieAvailable) {
          true => Lottie.asset(
            _lottieAssetPath,
            width: 400,
            height: 80,
            fit: BoxFit.contain,
            repeat: false,
          ),
          false => Text(
            'beautica',
            // Style is the cached VelvetText.wordmark() with fontSize:17 —
            // matches the wordmark render used elsewhere in the app, so the
            // fallback path is visually consistent.
            style: VelvetText.wordmark().copyWith(fontSize: _wordmarkFontSize),
          ),
          null => const SizedBox.shrink(),
        },
      ),
    );
  }
}
