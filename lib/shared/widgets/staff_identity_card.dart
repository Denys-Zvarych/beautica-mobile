// The staff/owner identity card — avatar + display name + role chip, with an
// optional self-declared title sub-line.
//
// PROMOTED (REUSE-FIRST, Phase 21.16) out of TWO screens that had each written
// the same widget tree inline and privately:
//
//   • `features/salon/presentation/owner_own_profile_screen.dart`'s
//     `_OwnerProfileBody.build` (Phase 21.14) — the version WITH the
//     `professionalTitle` sub-line;
//   • `features/salon/presentation/salon_staff_profile_screen.dart`'s
//     `_StaffProfileBody.build` (Phase 21.5) — the same tree without it.
//
// Phase 21.16's `AdminOwnProfileScreen` would have been the THIRD hand-copy;
// its phase doc names this widget `StaffIdentityCard` and lists it as
// something Phase 21.5 was supposed to have extracted already. Being inline
// and private was the signal a promotion was due, not a licence to copy it a
// third time.
//
// ── WHAT IS ADDITIVE ──────────────────────────────────────────────────────
// [professionalTitle] and the three `*Key` parameters all default to `null` —
// the values every pre-existing call site takes by omission — so the staff
// caller (which passes no title) renders exactly what it always did, and each
// caller keeps its OWN widget keys rather than being forced onto a shared
// naming scheme its tests would have to be rewritten for. Nothing here is
// required that was not already required at both call sites.
//
// ── PROVEN, NOT ASSERTED ──────────────────────────────────────────────────
// `test/golden/staff_identity_card_golden_test.dart` pins the pixels for all
// three live configurations, and its baselines were generated A/B from the
// PRE-promotion inline markup before this file existed — see that file's own
// header for the procedure. The promotion is therefore golden-verified rather
// than eyeballed.
//
// ── WHY IT LIVES IN `shared/` ─────────────────────────────────────────────
// All three current callers sit in `features/salon/presentation/`, so this
// could have stayed feature-local — but the Phase 21.19 `SALON_MASTER` own
// profile lives in `features/master/`, and a fourth caller reaching across
// features for a `presentation/` widget is exactly the import this project
// forbids. `shared/` is where the card can serve all of them. The two leaves
// it composes ([ProfileAvatar], [RoleChip]) still live under
// `features/master/presentation/widgets/` — that file already re-exports
// `shared/widgets/contact_tile.dart` for the mirror-image reason, and moving
// them is a rename across ~10 call sites this phase does not own.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/profile_avatar.dart';

/// A person's identity card on a profile screen: the recessed avatar well, the
/// display name, a [RoleChip] naming what they are, and — when they have set
/// one — their self-declared professional title on the line below.
///
/// The title sits UNDER the chip rather than replacing its label (which is
/// what `master_profile_screen.dart` does): on these screens the ROLE is the
/// fact the card exists to state, so a title supplements it instead of
/// displacing it.
class StaffIdentityCard extends StatelessWidget {
  const StaffIdentityCard({
    super.key,
    required this.displayName,
    required this.roleLabel,
    this.roleIcon = Icons.auto_awesome_rounded,
    this.professionalTitle,
    this.nameKey,
    this.roleChipKey,
    this.professionalTitleKey,
  });

  /// The person's full display name. Callers compose and trim it — this widget
  /// renders whatever it is handed, wrapping to at most two lines.
  final String displayName;

  /// The [RoleChip]'s label — «Власник салону», «Адмін», «Адміністратор», a
  /// master's own professional title, and so on. Which noun belongs here is
  /// the caller's decision, not this widget's.
  final String roleLabel;

  /// The [RoleChip]'s glyph. Defaults to the sparkle every current caller
  /// passes, so it is an override rather than a new obligation.
  final IconData roleIcon;

  /// The self-declared title rendered on its own muted line below the chip, or
  /// `null` to omit that line entirely (never render it blank).
  ///
  /// ADDITIVE: `null` is what the Phase 21.5 staff caller passes by omission,
  /// which is why that caller's render is byte-identical to its pre-promotion
  /// inline version.
  final String? professionalTitle;

  /// Optional [Key]s on the three text-bearing leaves, so each caller keeps
  /// the key names its own widget tests already target instead of being
  /// migrated onto a shared scheme. All default to `null`; a null [Key]
  /// changes nothing about what is painted.
  final Key? nameKey;
  final Key? roleChipKey;
  final Key? professionalTitleKey;

  @override
  Widget build(BuildContext context) {
    final String? professionalTitle = this.professionalTitle;
    return NeumorphicCard(
      color: const Color(0xFFEDE4D5),
      padding: const EdgeInsets.all(VelvetSpacing.md),
      // [RoleChip] uses [NeumorphicInset], whose RepaintBoundary can paint
      // near the card's rounded corners — the same reason
      // `master_profile_screen.dart` opts its identity card into ClipRRect and
      // leaves every other card at the default.
      clipContent: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          const ProfileAvatar(),
          const SizedBox(width: VelvetSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  displayName,
                  key: nameKey,
                  style: VelvetText.displayName(),
                  maxLines: 2,
                  softWrap: true,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: VelvetSpacing.xs + 2),
                RoleChip(key: roleChipKey, label: roleLabel, icon: roleIcon),
                if (professionalTitle != null) ...<Widget>[
                  const SizedBox(height: VelvetSpacing.xs),
                  Text(
                    professionalTitle,
                    key: professionalTitleKey,
                    style: VelvetText.feedbackMutedXs,
                    maxLines: 2,
                    softWrap: true,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
