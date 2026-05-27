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
//   The OS native splash now shows ONLY the warm-taupe background colour
//   (#E6DDD0) — no B-pillow, no logo, no wordmark. The Flutter splash is the
//   SOLE owner of the logo render. This eliminates the OS-baked-PNG vs
//   Flutter-runtime position+size mismatch users perceived on Android 12+
//   release builds (different density buckets baked the PNG at slightly
//   different sizes; the runtime VelvetLogo sat at a different on-screen
//   coordinate than the OS layer).
//
//   [FlutterNativeSplash.preserve] in main() holds the OS bg until the first
//   Flutter frame; [FlutterNativeSplash.remove] in [initState] dismisses it.
//   What the user sees is: warm-taupe background only → warm-taupe background
//   + B-pillow (Flutter paints it for the first time) → wordmark reveal.
//
// Splash content — tri-state probe:
//   The Lottie asset is bundled today, but the splash is robust to a missing
//   asset. On mount, [_checkLottieAsset] probes for
//   `assets/lottie/splash_wordmark.json` via `rootBundle.load()` and the
//   build switches on a tri-state [_lottieAvailable] (`bool?`):
//
//     null  → probing. Wordmark slot empty; B pillow visible. The Lottie
//             reveal owns the wordmark's first appearance — no static-text
//             flash beats the animation.
//     true  → Lottie asset resolved. Lottie wordmark renders below the
//             B pillow.
//     false → Lottie asset failed to load. A plain Text("beautica") renders
//             below the B pillow as a fallback so the user still sees the
//             brand wordmark — better a static name than no name.
//
//   Critical layout invariant: the B-pillow's on-screen position is IDENTICAL
//   across all three branches. It is rendered as a single fixed widget
//   (VelvetLogo with `showWordmark: false`) centered via [Align] of the
//   viewport. The wordmark (Lottie or static Text) renders as a SIBLING
//   [Positioned] layer offset from viewport center so the B-pillow does not
//   reflow / shift when the probe resolves. This fixes the "B-pillow jumps
//   upward when the Lottie renders" regression caused by the earlier
//   Column-based layout.
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
import '../../../core/theme/velvet_text.dart';
import '../../../core/widgets/neumorphic.dart';

/// Path of the optional Lottie wordmark animation. When this asset is
/// bundled, the Lottie widget renders; otherwise the static fallback runs.
const String _lottieAssetPath = 'assets/lottie/splash_wordmark.json';

/// Splash B-pillow dimensions — sized so the Flutter-side logo paint matches
/// the brand's intended cold-start hero scale. These are the SINGLE SOURCE of
/// truth for the pillow geometry inside the splash; tests assert against them
/// via [VelvetLogo.tileSize] / [VelvetLogo.markFontSize].
const double _pillowTileSize = 92.0;
const double _pillowMarkFontSize = 42.0;

/// Vertical gap (dp) between the bottom edge of the B-pillow and the top edge
/// of the wordmark (Lottie or static Text). Matches [VelvetSpacing.md] used by
/// the standalone [VelvetLogo] composite, so the visual spacing matches every
/// other VelvetLogo render in the app.
const double _pillowToWordmarkGap = 16.0;

/// Font size of the static-fallback wordmark Text. Kept identical to what
/// [VelvetLogo] uses internally when [VelvetLogo.wordmarkFontSize] is 17, so
/// the fallback path is visually indistinguishable from the legacy composite.
const double _wordmarkFontSize = 17.0;

/// Cold-start parking screen shown while the auth session resolves.
///
/// Tri-state render driven by [_SplashScreenState._lottieAvailable]:
///   - `null`  (probing) → B pillow visible (centered); no wordmark.
///   - `true`  → B pillow centered + Lottie wordmark below it.
///   - `false` (Lottie asset failed) → B pillow centered + static Text below.
///
/// The B-pillow is rendered as a single [VelvetLogo] with `showWordmark:false`
/// in EVERY branch, centered via [Align], so its on-screen position never
/// shifts. The wordmark is a sibling [Positioned] that appears below the
/// pillow once the probe resolves.
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
    // Layout invariant: the B-pillow is rendered as a SINGLE VelvetLogo with
    // showWordmark:false, centered via Align(Alignment.center) in ALL three
    // tri-state branches. It never moves when the probe resolves. The
    // wordmark (Lottie or static Text) is a sibling Positioned layer below
    // the pillow — it appears, but it does NOT reflow the pillow.
    //
    // Why a Positioned-with-explicit-top instead of a Column:
    //   A Column would size to the union of its children and Align would then
    //   centre that union — which means the B-pillow's centre shifts upward
    //   the moment the wordmark child is added. Putting the wordmark in a
    //   sibling Positioned anchored to the viewport's top-axis decouples its
    //   position from the pillow's layout completely.
    final Size viewport = MediaQuery.sizeOf(context);
    final double wordmarkTop =
        viewport.height / 2 + _pillowTileSize / 2 + _pillowToWordmarkGap;

    return Scaffold(
      backgroundColor: BrandColors.base,
      body: Stack(
        children: <Widget>[
          // B-pillow — always centered, identical position in every state.
          // Matches the Flutter-splash brand-mark hero position; the OS native
          // splash above shows ONLY the bg colour, so there is no double-paint
          // and no handoff jump.
          const Align(
            alignment: Alignment.center,
            child: VelvetLogo(
              tileSize: _pillowTileSize,
              markFontSize: _pillowMarkFontSize,
              showWordmark: false,
            ),
          ),
          // Wordmark reveal — rendered as a sibling Positioned ONLY after the
          // probe resolves. The pillow above does not move when this widget
          // is added or removed from the Stack.
          if (_lottieAvailable != null)
            Positioned(
              top: wordmarkTop,
              left: 0,
              right: 0,
              child: Center(
                child: _lottieAvailable == true
                    ? Lottie.asset(
                        _lottieAssetPath,
                        width: 400,
                        height: 80,
                        fit: BoxFit.contain,
                        repeat: false,
                      )
                    : Text(
                        'beautica',
                        // Style is the EXACT cached TextStyle that VelvetLogo
                        // would use internally for its built-in wordmark with
                        // wordmarkFontSize:17 — so this sibling-Text fallback
                        // is visually indistinguishable from the legacy
                        // composite. Single source of truth: VelvetText.
                        style: VelvetText.wordmark().copyWith(
                          fontSize: _wordmarkFontSize,
                        ),
                      ),
              ),
            ),
        ],
      ),
    );
  }
}
