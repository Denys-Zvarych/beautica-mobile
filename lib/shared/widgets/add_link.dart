import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';

/// A small inline "add this" text link — a leading `+` glyph and a mocha
/// [VelvetText.link] label, nothing else.
///
/// REUSE-FIRST — PROMOTED from the private `_AddLink` in
/// `features/salon/presentation/salon_management_profile_screen.dart`
/// (`_AboutReadView`'s empty «Додати опис» description state). Phase 351
/// reuses it for the master's OWN profile empty-bio affordance (both the
/// independent `MasterProfileScreen` and, where it renders a bio block, the
/// salon master's own `SalonMasterProfileScreen`) — see those screens'
/// `salonManageAddDescriptionLink`-keyed «Додати опис» rows.
///
/// The salon's own call site (`salon-manage-add-description`) is rewired
/// onto this promoted widget unchanged — see
/// `salon_management_profile_screen_test.dart` for the "unchanged" proof.
class AddLink extends StatelessWidget {
  const AddLink({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          // Vertical padding only — the link stays flush with the column's
          // left edge, exactly where the placeholder text it replaces sat,
          // while still clearing a comfortable touch target.
          padding: const EdgeInsets.symmetric(vertical: VelvetSpacing.xs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.add_rounded,
                size: 14,
                color: BrandColors.accentDeep,
              ),
              const SizedBox(width: 3),
              Text(label, style: VelvetText.link()),
            ],
          ),
        ),
      ),
    );
  }
}
