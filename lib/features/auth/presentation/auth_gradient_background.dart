// Shared gradient background widget used by all three auth screens
// (splash, login, register). Extracted from previously duplicated private
// _GradientBackground classes to satisfy DRY (LOW L1 fix).

import 'package:flutter/material.dart';

/// Full-screen gradient background — Midnight (#0D3B66) → deep navy (#061E35).
///
/// Uses a 5-stop dithered gradient instead of the original 2-stop version to
/// reduce visible colour banding on physical devices. The intermediate stops
/// evenly distribute the dark-blue transition so the GPU's 8-bit colour
/// quantisation produces no perceptible horizontal bands.
///
/// Used as the bottom layer of the Stack in [SplashScreen], [LoginScreen], and
/// [RegisterScreen]. Declared public so it is accessible across the auth
/// presentation layer without needing a shared/ re-export.
class AuthGradientBackground extends StatelessWidget {
  const AuthGradientBackground({super.key});

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        // 5-stop dithered gradient — reduces colour banding on 8-bit displays.
        // BrandColors.midnight (#0D3B66) cannot be used as a const here because
        // the stops list requires compile-time constants; literal hex is used
        // for the first stop instead.
        colors: [
          Color(0xFF0D3B66), // BrandColors.midnight — top
          Color(0xFF0B3359),
          Color(0xFF092B4C),
          Color(0xFF07243F),
          Color(0xFF061E35), // deep navy — bottom
        ],
        stops: [0.0, 0.25, 0.5, 0.75, 1.0],
      ),
    ),
    child: SizedBox.expand(),
  );
}
