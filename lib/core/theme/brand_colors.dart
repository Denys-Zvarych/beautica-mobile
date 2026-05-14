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
}
