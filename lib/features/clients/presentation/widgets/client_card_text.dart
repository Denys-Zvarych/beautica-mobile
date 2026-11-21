// M510 — the client card's type scale: the preview's `comfortaa(size)` /
// `nunito(size)` helpers expressed over the shipped [VelvetText] bases, so the
// fonts stay the app's (Comfortaa headings, Nunito body) — never `GoogleFonts`
// called inline.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';

/// Comfortaa [size] / w700 (the preview's `comfortaa`).
TextStyle clientHeading(
  double size, {
  Color color = BrandColors.text,
  double? height,
}) => VelvetText.heading().copyWith(
  fontSize: size,
  fontWeight: FontWeight.w700,
  color: color,
  height: height,
);

/// Nunito [size] / w600 by default (the preview's `nunito`).
TextStyle clientBody(
  double size, {
  FontWeight weight = FontWeight.w600,
  Color color = BrandColors.text,
}) => VelvetText.body().copyWith(
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: null,
);

/// «4,9» — one decimal, Ukrainian comma.
String formatClientRatingAvg(double avg) =>
    avg.toStringAsFixed(1).replaceAll('.', ',');
