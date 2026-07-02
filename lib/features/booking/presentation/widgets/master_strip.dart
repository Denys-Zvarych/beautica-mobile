// Phase 14.1 — MasterStrip: the "who you're booking with" context card.
//
// Transcribed verbatim (tokens, layout, shadows) from
// `docs/signup-designs/BookingServiceSelection/lib/widgets/selection_widgets.dart`
// (`MasterStrip`) / `docs/signup-designs/BookingSlotPicker/lib/widgets/master_strip.dart`
// — both preview apps carry an identical copy. Reused across the service
// selector (Step 1) and the date screen (Step 2a); the time screen (Step 2b)
// folds the same name/role onto its slimmer day-header chip instead.
//
// Takes the domain [Master] directly (rather than separate name/role strings)
// so every call site derives the display name + role label the exact same
// way.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

/// Resolves a display label for [type]. Shared by every booking-flow screen
/// that renders a [MasterStrip] / day-header chip so the wording never drifts
/// from `PublicMasterProfileScreen`'s own `_roleLabel`.
String masterRoleLabel(MasterType type, AppLocalizations l10n) {
  switch (type) {
    case MasterType.independentMaster:
      return l10n.masterRoleIndependent;
    case MasterType.salonMaster:
      return l10n.masterRoleSalonMaster;
    case MasterType.salonOwner:
      return l10n.masterRoleSalonOwner;
  }
}

/// A compact "who you're booking with" strip — a camel-wash card with a small
/// raised avatar glyph + the master's name and role.
class MasterStrip extends StatelessWidget {
  const MasterStrip({super.key, required this.master});

  final Master master;

  /// Camel-wash surface — the same lighter taupe used by the pinned booking
  /// summary shelf, so the strip reads as sitting on its own elevated card.
  static const Color _stripSurface = Color(0xFFEDE4D5);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String name = '${master.firstName} ${master.lastName}'.trim();
    final String role = masterRoleLabel(master.type, l10n);

    return Semantics(
      label: l10n.bookingMasterStripSemantics(name, role),
      child: NeumorphicCard(
        color: _stripSurface,
        padding: const EdgeInsets.all(VelvetSpacing.sm + 4),
        child: Row(
          children: <Widget>[
            Container(
              height: 48,
              width: 48,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[Color(0xFFD8BE9C), Color(0xFF6A4A28)],
                ),
                boxShadow: VelvetShadows.extrudedSmall,
              ),
              child: Center(
                child: Icon(
                  Icons.person_rounded,
                  color: BrandColors.white.withValues(alpha: 0.82),
                  size: 24,
                ),
              ),
            ),
            const SizedBox(width: VelvetSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    l10n.bookingMasterStripLabel,
                    style: VelvetText.feedback(
                      BrandColors.textSecondary,
                    ).copyWith(fontSize: 11),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    name,
                    style: VelvetText.subheading().copyWith(fontSize: 16),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
