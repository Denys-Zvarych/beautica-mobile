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
//   controller is snapped to its end value so all letters appear immediately,
//   and a timer is scheduled to kick the router directly — the status listener
//   will never fire because setting value = 1.0 does not emit
//   AnimationStatus.completed. (MediaQuery is unavailable in initState;
//   accessibilityFeatures reads the same underlying platform flag.)
//
// Why no ScreenProtector here:
//   The splash screen displays only the branded "beautica" wordmark animation —
//   no passwords, OTP codes, or user data are ever rendered on this screen.
//   Applying FLAG_SECURE here caused the Android emulator to render a black
//   window for the entire splash duration, hiding the animation. ScreenProtector
//   is used on auth screens that display sensitive fields (login, verification,
//   register, reset-password, invite-accept, settings).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:go_router/go_router.dart';

import '../../../core/app_start_time.dart';
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
  Timer? _splashTimer;

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

    // Anchor the splash-duration gate to the moment Flutter's surface becomes
    // visible, NOT to app entry. Native splash + Dart VM init can take >1s on
    // Android 12 cold starts, which would otherwise pre-expire the 950 ms gate
    // and cause go_router to redirect to /login before the wordmark animation
    // can paint a single frame.
    AppStartTime.record();

    // Start the animation immediately. AnimationController schedules its own
    // ticker via vsync and does not need a rendered frame — no
    // addPostFrameCallback required. MediaQuery is unavailable in initState;
    // accessibilityFeatures reads the same underlying platform disableAnimations
    // flag via the engine and is available from the very first frame.
    if (WidgetsBinding.instance.accessibilityFeatures.disableAnimations) {
      // Defer the snap until after first build so AnimatedWordmark's FadeTransition
      // listeners have attached — setting value=1.0 in initState fires notifyListeners
      // before any child subscribes, leaving opacity at 0.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _wordmarkController.value = 1.0;
      });
      // Accessibility: animation skipped — status listener will never fire
      // (value = 1.0 does not emit AnimationStatus.completed). Schedule the
      // router refresh directly so accessibility users are not parked on /splash.
      final remaining =
          _minSplashMs -
          AppStartTime.elapsed().inMilliseconds.clamp(0, _minSplashMs);
      _splashTimer = Timer(Duration(milliseconds: remaining), () {
        if (mounted) GoRouter.of(context).refresh();
      });
    } else {
      _wordmarkController.forward();
    }

    // Minimum splash duration gate — router re-kick.
    //
    // In release AOT builds the auth provider can resolve synchronously before
    // the first Flutter frame. GoRouter fires its redirect once (returning
    // /splash because AppStartTime.elapsed() < 950 ms) and then goes quiet —
    // authProvider never emits again, so AuthRefreshNotifier never calls
    // notifyListeners(), and the router never re-evaluates the redirect.
    //
    // Fix: when the animation completes (at ~880 ms), call GoRouter.of().refresh()
    // to force a second redirect evaluation. By that point 880 ms have elapsed,
    // which exceeds the 950 ms gate only if there was negligible startup latency.
    // To be safe we wait the full _minSplashMs before refreshing — the router
    // then immediately routes to /home or /login as appropriate.
    //
    // In debug mode the gate is skipped by auth_redirect.dart (kDebugMode check),
    // so this listener fires but the router routes normally on the first evaluation.
    // The addStatusListener is cheap and harmless in both modes.
    _wordmarkController.addStatusListener(_onAnimationStatus);
  }

  /// Minimum splash wall-clock duration in milliseconds.
  ///
  /// Single source of truth: [AppStartTime.minSplashDuration]. Derived here as
  /// an int so it can be used directly in the [Timer] remainder calculation.
  static final int _minSplashMs = AppStartTime.minSplashDuration.inMilliseconds;

  void _onAnimationStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    // Animation is done (~880 ms). Wait for the full 950 ms gate, then kick
    // the router so it re-runs its redirect callback. By this point
    // AppStartTime.elapsed() will be >= _minSplashDuration and the gate in
    // auth_redirect.dart will pass through to the real auth routing logic.
    final remaining =
        _minSplashMs -
        AppStartTime.elapsed().inMilliseconds.clamp(0, _minSplashMs);
    _splashTimer = Timer(Duration(milliseconds: remaining), () {
      // Guard against the widget being disposed before the delay fires
      // (e.g. in tests or if the OS kills the app while in background).
      if (mounted) GoRouter.of(context).refresh();
    });
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
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
