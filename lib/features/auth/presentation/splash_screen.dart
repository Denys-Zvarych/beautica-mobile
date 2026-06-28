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
//   over once the first frame is ready and renders a centred Column
//   composite (static B-pillow tile + animated Lottie wordmark reveal) on
//   [BrandColors.base]. Result: cold-start → warm-taupe bg only → warm-taupe
//   bg + the brand mark animating into place.
//
//   [FlutterNativeSplash.preserve] in main() holds the OS bg until the first
//   Flutter frame; [FlutterNativeSplash.remove] in [initState] dismisses it.
//
// Splash content — centred composite (revised 2026-05-27):
//   The splash body is a single `Center` widget wrapping a `Column` whose
//   children are:
//     1. [VelvetLogo](compact: true, showWordmark: false) — the rounded
//        72dp B-pillow tile only.
//     2. A fixed [_bToWordmarkGap] (8 dp) gap, matching the internal vertical
//        rhythm of VelvetLogo's default composite.
//     3. [_SplashWordmark] — a [Lottie.asset] that plays the wordmark reveal
//        animation bundled at `assets/lottie/splash_wordmark.json` (400×80,
//        60 fps). The Lottie replaces the static "beautica" Text the default
//        VelvetLogo composite would have rendered, so the visual outline
//        matches the login-screen logo exactly while the wordmark itself
//        animates letter-by-letter on the splash.
//
//   The Column uses `mainAxisSize: MainAxisSize.min` so that `Center` treats
//   the whole composite as a single unit — its vertical midpoint lands on
//   the viewport's true vertical centre. This is the fix for the user's
//   complaint that the previous layout had the logo "at the top of the
//   page".
//
//   The Lottie asset is bundled in the APK (declared in pubspec.yaml under
//   `flutter > assets`), so no runtime probe is required; if the asset is
//   missing the Lottie widget will throw at build time, which is a
//   build-invariant failure and therefore correct to surface loudly.
//
//   A [Timer] for the remaining [AppStartTime.minSplashDuration] still kicks
//   the GoRouter so we exit /splash into /login or /home as soon as the
//   minimum splash duration has elapsed; without it the auth provider can
//   resolve before the first frame and the redirect never re-fires.
//
// Why no AnimationController here:
//   The wordmark animation lives inside the Lottie widget, which owns its
//   own Ticker via [Lottie.asset]. The splash widget therefore has no
//   AnimationController of its own to dispose.
//
// Why no ScreenProtector here:
//   The splash screen displays only the branded B-pillow and the animated
//   wordmark — no passwords, OTP codes, or user data are ever rendered.
//   ScreenProtector is reserved for screens with sensitive fields (login,
//   verification, register, reset-password, invite-accept, settings).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';

import '../../../core/app_start_time.dart';
import '../../../core/theme/brand_colors.dart';
import '../../../core/widgets/neumorphic.dart';

/// Asset path for the splash wordmark Lottie reveal animation. Bundled in
/// the APK via the `assets/lottie/` declaration in `pubspec.yaml`.
const String _lottieAssetPath = 'assets/lottie/splash_wordmark.json';

/// Vertical gap between the B-pillow tile and the wordmark below it. Matches
/// the internal spacing of the default `VelvetLogo(compact: true)` composite
/// so the splash visual rhythm matches the login-screen header.
const double _bToWordmarkGap = 8.0;

/// Render width of the Lottie wordmark on the splash. 320×64 chosen after
/// user feedback that 280 was good but "a little bit more bigger" was desired;
/// 5:1 aspect ratio preserved. The Lottie's letter sprites occupy ~17.5% of
/// canvas height, so bounding-box parity with the login wordmark text (~94 dp
/// wide) renders letters too small to read; 320×64 keeps letters clearly
/// legible while preserving the native 5:1 aspect ratio (400×80 composition).
const double _lottieWidth = 320.0;

/// Render height of the Lottie wordmark on the splash. See [_lottieWidth].
/// Locked to `_lottieWidth / 5` to preserve the asset's native 5:1 aspect.
const double _lottieHeight = 64.0;

/// Cold-start parking screen shown while the auth session resolves.
///
/// Renders a centred [Column] composite on [BrandColors.base]:
///   - [VelvetLogo](compact: true, showWordmark: false) — static B-pillow.
///   - 8 dp gap ([_bToWordmarkGap]).
///   - [_SplashWordmark] — animated Lottie wordmark reveal.
///
/// The composite is wrapped in a [Center] widget and the inner [Column] uses
/// `mainAxisSize: MainAxisSize.min` so the whole composite is treated as a
/// single unit centred at the viewport midpoint, vertically and
/// horizontally.
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
    // Centred composite, vertically and horizontally:
    //   B-pillow  (VelvetLogo with showWordmark:false — just the rounded tile)
    //   8 dp gap
    //   Lottie wordmark reveal  (animated "beautica" letter-by-letter)
    //
    // Mirrors the visual structure of the login-screen header
    // (`VelvetLogo(compact: true)`) but the wordmark text is replaced by the
    // Lottie reveal animation. The Column is sized to its children
    // (`mainAxisSize: MainAxisSize.min`) so Center treats it as one unit and
    // lands its midpoint on the viewport's true centre — no top-of-page
    // drift.
    return const Scaffold(
      backgroundColor: BrandColors.base,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            VelvetLogo(compact: true, showWordmark: false),
            SizedBox(height: _bToWordmarkGap),
            // PERF: isolate the Lottie wordmark's per-frame repaints so the
            // reveal animation does not dirty the static B-pillow sibling above.
            RepaintBoundary(child: _SplashWordmark()),
          ],
        ),
      ),
    );
  }
}

/// Animated wordmark for the splash composite. Plays the bundled Lottie
/// reveal once (no looping) at a fixed render size below the B-pillow.
///
/// Extracted into a private widget so the outer build tree can remain
/// entirely `const` — `Lottie.asset(...)` is not a const constructor.
class _SplashWordmark extends StatelessWidget {
  const _SplashWordmark();

  @override
  Widget build(BuildContext context) {
    return Lottie.asset(
      _lottieAssetPath,
      width: _lottieWidth,
      height: _lottieHeight,
      fit: BoxFit.contain,
      repeat: false,
    );
  }
}
