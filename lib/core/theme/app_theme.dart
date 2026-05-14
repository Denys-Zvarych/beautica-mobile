import 'package:flutter/material.dart';

import 'brand_colors.dart';

/// Beautica Material 3 theme factories.
///
/// Single source of truth for `ThemeData`. Both factories seed from
/// [BrandColors.seed] (Midnight) and apply the locked brand role overrides
/// from `ARCHITECTURE-mobile.md` § 9 via `ColorScheme.copyWith`.
///
/// Typography (Manrope via `google_fonts`) is wired in Phase 1.2 — do NOT
/// add a `textTheme:` block here yet.
///
/// Contrast note: `bliss` on white = 1.6:1 — NEVER use bliss as text on white
/// surfaces. Bliss is a CTA fill colour whose labels must render in
/// [BrandColors.midnight] (bliss on midnight = 7.1:1, AA).

/// Light theme — seeded from Midnight, brand-locked secondary/tertiary/error.
ThemeData lightTheme() => ThemeData(
  useMaterial3: true,
  colorScheme:
      ColorScheme.fromSeed(
        seedColor: BrandColors.seed,
        brightness: Brightness.light,
      ).copyWith(
        secondary: BrandColors.bliss,
        secondaryContainer: BrandColors.sunshine,
        tertiary: BrandColors.sand,
        error: BrandColors.cherry,
      ),
);

/// Dark theme — same seed + role overrides, minus `secondaryContainer`.
///
/// Sunshine is too pale to read as a container on a dark surface, so we let
/// the seed derivation pick a dark-appropriate container instead.
ThemeData darkTheme() => ThemeData(
  useMaterial3: true,
  colorScheme:
      ColorScheme.fromSeed(
        seedColor: BrandColors.seed,
        brightness: Brightness.dark,
      ).copyWith(
        secondary: BrandColors.bliss,
        tertiary: BrandColors.sand,
        error: BrandColors.cherry,
      ),
);
