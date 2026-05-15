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

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:flutter/material.dart';

/// Cold-start parking screen shown while the auth session resolves.
///
/// Styled with [BrandColors.midnight] background and a [BrandColors.bliss]
/// progress indicator to match the brand identity during app startup.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: BrandColors.midnight,
    body: Center(child: CircularProgressIndicator(color: BrandColors.bliss)),
  );
}
