// PhoneFirstAuth (M515) — PROMOTED: the 72 dp extruded icon tile every auth
// wizard step inlined as a byte-identical `Center > Container` (register steps
// 1 / 2, verification, reset OTP). One widget, so a fix lands on every step.
//
// Rewired: the phone-first wizard steps (phone, code, password, name) in M515;
// the verification + reset-OTP screens and the M517 add-phone step in M517
// (their inline copies were byte-identical: same 72 dp box, radius, shadow,
// 30 dp camel glyph).

import 'package:flutter/material.dart';

import '../../../../core/theme/brand_colors.dart';
import '../../../../core/theme/velvet_geometry.dart';

/// 72 × 72 neumorphic tile with a camel 30 dp glyph, centred.
class AuthIconTile extends StatelessWidget {
  const AuthIconTile({super.key, required this.icon, this.tileKey});

  final IconData icon;

  /// Optional key on the tile itself (the register step 1 tile keeps its
  /// `step1_icon_tile` key for existing finders).
  final Key? tileKey;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        key: tileKey,
        height: 72,
        width: 72,
        decoration: const BoxDecoration(
          color: BrandColors.base,
          borderRadius: BorderRadius.all(Radius.circular(VelvetRadii.logoTile)),
          boxShadow: VelvetShadows.extrudedSmall,
        ),
        child: Icon(icon, color: BrandColors.accent, size: 30),
      ),
    );
  }
}
