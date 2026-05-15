// Shared gradient background widget used by all three auth screens
// (splash, login, register). Extracted from previously duplicated private
// _GradientBackground classes to satisfy DRY (LOW L1 fix).

import 'package:flutter/material.dart';

import '../../../core/theme/brand_colors.dart';

/// Full-screen gradient background — Midnight (#0D3B66) → deep navy (#061E35).
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
        colors: [BrandColors.midnight, Color(0xFF061E35)],
      ),
    ),
    child: SizedBox.expand(),
  );
}
