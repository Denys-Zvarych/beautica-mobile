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
//   (#E6DDD0) — no B-pillow, no logo, no wordmark. The Flutter splash takes
//   over once the first frame is ready and renders the SAME [VelvetLogo]
//   composite that the login screen uses (`compact: true`) centred on
//   [BrandColors.base]. Result: cold-start → warm-taupe bg only → warm-taupe
//   bg + the login-screen logo (B-pillow + "beautica" wordmark below).
//
//   [FlutterNativeSplash.preserve] in main() holds the OS bg until the first
//   Flutter frame; [FlutterNativeSplash.remove] in [initState] dismisses it.
//
// Splash content — single widget:
//   The splash body is exactly `Center(child: VelvetLogo(compact: true))`,
//   matching `login_screen.dart` line 196 character-for-character. No Lottie
//   animation, no AnimationController, no tri-state asset probe — the
//   splash visual is identical to what the user sees on /login the moment
//   they arrive there, which is the requested behaviour.
//
//   A [Timer] for the remaining [AppStartTime.minSplashDuration] still kicks
//   the GoRouter so we exit /splash into /login or /home as soon as the
//   minimum splash duration has elapsed; without it the auth provider can
//   resolve before the first frame and the redirect never re-fires.
//
// Why no AnimationController here:
//   Splash visual is a static composite — no animation owned by this widget.
//   VelvetLogo internally renders a plain Text wordmark when no
//   AnimationController is supplied, so there is no Ticker dependency.
//
// Why no ScreenProtector here:
//   The splash screen displays only the branded "beautica" wordmark — no
//   passwords, OTP codes, or user data are ever rendered. ScreenProtector is
//   reserved for screens with sensitive fields (login, verification, register,
//   reset-password, invite-accept, settings).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:go_router/go_router.dart';

import '../../../core/app_start_time.dart';
import '../../../core/theme/brand_colors.dart';
import '../../../core/widgets/neumorphic.dart';

/// Cold-start parking screen shown while the auth session resolves.
///
/// Renders the same [VelvetLogo] composite the login screen uses
/// (`compact: true` → 72dp tile + "beautica" wordmark below) centred on
/// [BrandColors.base]. No animation owned by this widget — the visual is
/// intentionally identical to what /login shows on first paint.
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

    // Schedule a router refresh at minSplashDuration. In release AOT builds
    // the auth provider can resolve synchronously before the first Flutter
    // frame, in which case GoRouter fires its redirect once (returning
    // /splash because elapsed < _minSplashMs) and then goes quiet —
    // authProvider never emits again, so AuthRefreshNotifier never calls
    // notifyListeners() and the router never re-evaluates. The timer below
    // kicks it so we exit /splash on schedule.
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

  @override
  void dispose() {
    _splashTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Single centred VelvetLogo — matches login_screen.dart:196 verbatim:
    //   const Center(child: VelvetLogo(compact: true)),
    //
    // The widget renders a 72dp B-pillow tile with the "beautica" wordmark
    // below (VelvetLogo defaults: markFontSize:36, wordmarkFontSize:14,
    // showWordmark:true). No animation, no asset probe — what the user sees
    // on /splash is exactly what they see on /login the moment they arrive.
    return const Scaffold(
      backgroundColor: BrandColors.base,
      body: Center(child: VelvetLogo(compact: true)),
    );
  }
}
