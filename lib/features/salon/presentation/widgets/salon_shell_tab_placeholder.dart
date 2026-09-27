// Phase 21.8 — Salon Shell tab placeholder («Записи» / «Профіль»).
//
// The two shell tabs with no real host screen yet (Записи → Phase 21.12
// salon-wide schedule; owner Профіль → Phase 21.14; admin Профіль →
// Phase 21.16). Rendered per the shell's `IndexedStack`, so it fills the
// same body area a real tab host would — no AppBar/back chrome of its own
// (the shell's own bottom nav is the only navigation surface).
//
// Follows the same "real routed placeholder, never a SnackBar dead end"
// convention as `schedule_editor_stubs.dart` — centred icon + title + a
// "coming soon" blurb — but reuses the shared [NeumorphicCard] primitive
// (REUSE-FIRST) rather than the stub screen's own bespoke shadowed circle,
// since this placeholder sits INSIDE a shell body rather than owning a full
// `Scaffold`+`AppBar`.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';

/// A "coming soon" tab body for a shell tab whose real host screen has not
/// shipped yet. [icon] must match the tab's own `SalonBottomNav` glyph so the
/// placeholder reads as a continuation of the tab just tapped, not a
/// generic error surface.
class SalonShellTabPlaceholder extends StatelessWidget {
  const SalonShellTabPlaceholder({
    super.key,
    required this.icon,
    required this.title,
    required this.blurb,
  });

  final IconData icon;
  final String title;
  final String blurb;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: BrandColors.base,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(VelvetSpacing.xl),
            child: NeumorphicCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    height: 64,
                    width: 64,
                    decoration: const BoxDecoration(
                      color: BrandColors.base,
                      shape: BoxShape.circle,
                      boxShadow: VelvetShadows.extrudedSmall,
                    ),
                    child: Icon(icon, size: 28, color: BrandColors.accentDeep),
                  ),
                  const SizedBox(height: VelvetSpacing.lg),
                  Text(
                    title,
                    style: VelvetText.heading(),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: VelvetSpacing.sm),
                  Text(
                    blurb,
                    style: VelvetText.body(),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
