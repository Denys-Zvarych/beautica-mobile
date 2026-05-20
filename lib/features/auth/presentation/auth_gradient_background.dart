// Warm-Mocha gradient background for the auth flow (splash / login /
// register / verification).
//
// A previous iteration used a Bayer-4×4 ordered-dither CustomPainter
// recording ~288 k drawRect calls to suppress banding. On 2026-05-20 the
// frame-timings callback proved it cost ~2.5 s of GPU raster per frame on
// Mali-G52 / Impeller-Vulkan, making the app unusable. Reverted to a plain
// LinearGradient — single GPU draw call, zero per-frame work. Banding
// (if any) is a polish concern; F8 plan: pre-bake to a PNG asset.

import 'package:flutter/material.dart';

/// Full-screen Warm Mocha gradient background.
///
/// Drop-in replacement for the previous Bayer-dither painter. The public API
/// (`const AuthGradientBackground({super.key})`) is unchanged so all existing
/// call sites (AuthScaffold, SplashScreen, SettingsScreen) continue to work.
/// Wrapped in a [RepaintBoundary] so the (now-trivial) layer is composited
/// once and isolated from sibling animation ticks.
class AuthGradientBackground extends StatelessWidget {
  const AuthGradientBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF3A2615), // upper-left: lighter mocha-brown
              Color(0xFF1E140A), // mid: dark espresso transition
              Color(0xFF0D0906), // bottom-right: espresso bg
            ],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        // SizedBox.expand forces the DecoratedBox to fill its parent in any
        // context (Stack non-positioned child, Scaffold body, plain column).
        child: SizedBox.expand(),
      ),
    );
  }
}
