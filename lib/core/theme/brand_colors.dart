import 'package:flutter/material.dart';

/// Beautica brand palette — locked in `ARCHITECTURE-mobile.md` § 9.
///
/// Sourced from the Coolors "Sunset" palette:
/// https://coolors.co/0d3b66-faf0ca-f4d35e-ee964b-f95738
///
/// [midnight] is the Material 3 `ColorScheme.fromSeed` seed; [bliss] is the
/// locked secondary applied via `copyWith`. The full theme wire-up lands in
/// Phase 1.1 — this stub only exposes the constants so downstream features
/// can already reference them.
abstract final class BrandColors {
  /// Primary identity — body text, dark surfaces, app-bar background.
  static const Color midnight = Color(0xFF0D3B66);

  /// Accent / CTA fill — labels rendered in [midnight] only.
  static const Color bliss = Color(0xFFF4D35E);

  /// Warm light surface tint — light card backgrounds.
  static const Color sunshine = Color(0xFFFAF0CA);

  /// Warning / muted state — soft conflicts, calendar exceptions.
  static const Color sand = Color(0xFFEE964B);

  /// Error / cancellation — validation, declined bookings.
  static const Color cherry = Color(0xFFF95738);

  /// Material 3 seed color for `ColorScheme.fromSeed`.
  static const Color seed = midnight;

  /// Dark input field background — slightly lighter than [midnight] to give
  /// form fields a subtle lifted appearance on the gradient auth screens.
  static const Color darkSurface = Color(0xFF0A2540);

  // ---------------------------------------------------------------------------
  // Warm Mocha palette — auth screens (Phase 2.x visual redesign)
  // Reference: docs/signup-designs/*.html
  // ---------------------------------------------------------------------------

  /// Espresso — deepest background / phone shell. Replaces the old navy
  /// gradient on all auth screens. #0D0906.
  static const Color espresso = Color(0xFF0D0906);

  /// Mocha — CTA gradient seed / primary warm tone. #6A4A28.
  static const Color mocha = Color(0xFF6A4A28);

  /// Latte — CTA gradient highlight (brightest stop). #8A6840.
  static const Color latte = Color(0xFF8A6840);

  /// Camel — accent: selected state borders, focus rings, checkmarks. #B89A7A.
  static const Color camel = Color(0xFFB89A7A);

  /// Cream — primary on-dark text colour. #F5EDE0.
  static const Color cream = Color(0xFFF5EDE0);

  /// Ash — muted / dividers / secondary labels. #D4B896.
  static const Color ash = Color(0xFFD4B896);

  /// Error rust — validation errors and cancellation states on mocha screens.
  /// Replaces [cherry] for the auth surface only; [cherry] remains the booking
  /// status token. #A84040.
  static const Color errorRust = Color(0xFFA84040);
}
