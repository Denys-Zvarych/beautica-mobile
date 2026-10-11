import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'brand_colors.dart';

/// Nunito text theme with every M3 w500 role remapped to the bundled w600.
///
/// MaterialApp merges the M3 typography geometry under this theme, and that
/// geometry makes titleMedium / titleSmall / labelLarge / labelMedium /
/// labelSmall w500. Only Nunito w400/w600/w700/w800 are bundled (no Medium),
/// so a w500 role would render a mismatched face. Remap explicitly: zero bytes.
TextTheme _nunitoTextTheme() {
  const FontWeight semiBold = FontWeight.w600;
  final TextTheme plain = ThemeData.light().textTheme;
  final TextTheme base = plain.copyWith(
    titleMedium: plain.titleMedium?.copyWith(fontWeight: semiBold),
    titleSmall: plain.titleSmall?.copyWith(fontWeight: semiBold),
    labelLarge: plain.labelLarge?.copyWith(fontWeight: semiBold),
    labelMedium: plain.labelMedium?.copyWith(fontWeight: semiBold),
    labelSmall: plain.labelSmall?.copyWith(fontWeight: semiBold),
  );
  return GoogleFonts.nunitoTextTheme(base);
}

/// Beautica Material 3 theme factory — VelvetTouch design system.
///
/// Light-only. The VelvetTouch soft-UI (neumorphic) metaphor requires a
/// single warm-taupe base tone; the shadow / highlight illusion breaks on a
/// dark surface, so a dark theme is architecturally incompatible with this
/// design language.
///
/// seeded from [BrandColors.seed] (mocha `#6A4A28`), surface set to
/// [BrandColors.base] (warm taupe `#E6DDD0`), Nunito text theme.
ThemeData velvetTheme() {
  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: BrandColors.seed,
    brightness: Brightness.light,
    surface: BrandColors.base,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: BrandColors.base,
    textTheme: _nunitoTextTheme(),
    splashColor: BrandColors.accent.withValues(alpha: 0.12),
    highlightColor: BrandColors.accent.withValues(alpha: 0.06),
    // Enable left-edge swipe-to-pop on Android (and all platforms) using the
    // same CupertinoPageTransitionsBuilder that iOS uses natively. This wires
    // the _CupertinoBackGestureDetector into every MaterialPage-based route so
    // that dragging from the left screen edge toward the middle pops the page
    // back — matching the iOS interactive back-swipe behaviour on Android.
    //
    // NOTE: Routes that use CustomTransitionPage (e.g. _instantPage) override
    // this theme-level builder and therefore do NOT get the back-swipe gesture
    // automatically — see app_router.dart for details.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}

// ---------------------------------------------------------------------------
// darkTheme() — ARCHIVED, not wired in MaterialApp.
//
// The VelvetTouch neumorphic design system is light-only. Dark mode support
// is deferred until a separate dark design language is specified and approved.
// Do not pass this to MaterialApp until a VelvetTouch dark variant ships.
// ---------------------------------------------------------------------------
//
// ThemeData _darkTheme() {
//   final ColorScheme scheme = ColorScheme.fromSeed(
//     seedColor: BrandColors.seed,
//     brightness: Brightness.dark,
//   );
//   return ThemeData(
//     useMaterial3: true,
//     colorScheme: scheme,
//     textTheme: GoogleFonts.nunitoTextTheme(),
//   );
// }
