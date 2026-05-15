import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'brand_colors.dart';

/// Beautica Material 3 theme factories.
///
/// Single source of truth for `ThemeData`. Both factories seed from
/// [BrandColors.seed] (Midnight) and apply the locked brand role overrides
/// from `ARCHITECTURE-mobile.md` § 9 via `ColorScheme.copyWith`.
///
/// Typography (Manrope via `google_fonts`) is wired here in Phase 1.2 via
/// [_textTheme]. Manrope ships full Cyrillic glyphs, so Ukrainian
/// `і ї є ґ` render correctly without a fallback font.
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
  textTheme: _textTheme(Brightness.light),
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
  textTheme: _textTheme(Brightness.dark),
);

/// Canonical Beautica type scale, layered on top of the Material 3 defaults.
///
/// `GoogleFonts.manropeTextTheme` rewrites every style in the base text
/// theme to use Manrope while preserving Material 3's sizing for any role
/// we don't explicitly override. The `copyWith` block below pins the six
/// roles the design system actually exercises (display / headline / title
/// / body / label) to the values in `ARCHITECTURE-mobile.md` § 9.
TextTheme _textTheme(Brightness b) =>
    GoogleFonts.manropeTextTheme(ThemeData(brightness: b).textTheme).copyWith(
      displayLarge: const TextStyle(
        fontSize: 57,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.25,
      ),
      headlineLarge: const TextStyle(fontSize: 32, fontWeight: FontWeight.w600),
      titleLarge: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
      bodyLarge: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.5,
      ),
      bodyMedium: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.4,
      ),
      labelLarge: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    );
