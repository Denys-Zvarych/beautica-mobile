// PROMOTED (REUSE-FIRST) from the private `_EmptyState` in
// `features/services/presentation/services_list_screen.dart` (Phase 5.2),
// which rendered the INDEPENDENT_MASTER's / SALON_MASTER's own "Мої послуги"
// catalogue empty state (medallion glyph + heading + body + optional CTA).
//
// Promoted to `shared/widgets/` — rather than left in `features/services/
// presentation/` — because a SECOND caller now needs it:
// `SalonMasterProfileScreen`'s embedded «Послуги» tab. Per the layer table
// in ARCHITECTURE-mobile.md § "Project Structure", `features/master/
// presentation/` may not import another feature's `presentation/` directly;
// `shared/widgets/` is the sanctioned cross-feature reuse point.
//
// Title/body/CTA label are now caller-supplied (not hardcoded to
// `l10n.servicesEmpty`/`servicesEmptyBody`/`servicesAdd` inside the widget)
// so a read-only viewer (no `onCreate`) can be shown a DIFFERENT body — "ask
// the salon owner/admin" rather than the writable "add your first service" —
// without forking the widget. See `services_list_screen.dart`'s and
// `salon_master_profile_screen.dart`'s call sites.
import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';

/// Empty-catalogue state: recessed spa-glyph medallion, heading, body, and an
/// OPTIONAL primary CTA (hidden — not disabled — when the viewer cannot add
/// services; Phase 320 D3).
class ServicesEmptyState extends StatelessWidget {
  const ServicesEmptyState({
    super.key,
    required this.title,
    required this.body,
    this.onCreate,
    this.createLabel,
    this.iconWidget,
  }) : assert(
         onCreate == null || createLabel != null,
         'createLabel is required whenever onCreate is provided.',
       );

  /// Replaces the default `spa_rounded` glyph inside the inset disc (additive,
  /// Phase 363: the notification feed's bell). `null` — every existing caller
  /// — keeps the spa glyph, byte for byte.
  final Widget? iconWidget;

  /// Empty-state heading, e.g. `l10n.servicesEmpty` ("Послуг ще немає").
  final String title;

  /// Secondary explanatory line. Callers pick the audience-appropriate copy
  /// — e.g. `l10n.servicesEmptyBody` for a viewer who can add services, or a
  /// "ask the owner/admin" hint for a read-only one.
  final String body;

  /// Tap handler for the CTA button. `null` hides the CTA entirely (a
  /// read-only viewer) rather than rendering it disabled.
  final VoidCallback? onCreate;

  /// CTA label, e.g. `l10n.servicesAdd`. Required whenever [onCreate] is
  /// non-null.
  final String? createLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(VelvetSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              height: 104,
              width: 104,
              child: NeumorphicInset(
                // Circular inset medallion — same carved-in treatment as the
                // empty-state in the approved preview.
                radius: 52,
                child: Center(
                  child:
                      iconWidget ??
                      Icon(
                        Icons.spa_rounded,
                        size: 44,
                        color: BrandColors.accent.withValues(alpha: 0.9),
                      ),
                ),
              ),
            ),
            const SizedBox(height: VelvetSpacing.xl),
            Text(
              title,
              style: VelvetText.headingSm,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: VelvetSpacing.sm),
            Text(body, style: VelvetText.body(), textAlign: TextAlign.center),
            if (onCreate != null) ...<Widget>[
              const SizedBox(height: VelvetSpacing.xl),
              SizedBox(
                width: 240,
                child: NeumorphicButton(
                  key: const Key('btn-create-service-empty'),
                  label: createLabel!,
                  icon: Icons.add_rounded,
                  onPressed: onCreate!,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
