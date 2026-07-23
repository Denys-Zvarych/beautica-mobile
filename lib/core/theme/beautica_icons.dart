// Shared icon constants for Beautica Mobile.
//
// Centralises the `IconData` literals that must be identical across multiple
// screens so a future change to one without the other is caught at compile
// time (the constant reference) AND at test time (the cross-screen
// consistency test in `test/consistency/menu_icon_consistency_test.dart`).
//
// ADDING A NEW SHARED ICON:
//   1. Add a `static const IconData` here with a descriptive name.
//   2. Use the constant in every screen that renders the icon.
//   3. Add a new scenario to `test/consistency/menu_icon_consistency_test.dart`
//      following the pattern already established for `menuBurger`.
//
// Current shared icons:
//   • menuBurger — top-bar "settings/menu" button (tune_rounded).
//     Rendered by MasterProfileScreen (Key('btn-menu-master')) and
//     HomeHubScreen (Key('btn-menu-client')). The bug that prompted this
//     constant was the two screens inadvertently using different icons
//     (Phase 13.7 cleanup).
//
// Intentionally NOT included here:
//   • Icons used by a single screen (no consistency risk).
//   • Icons that are deliberately distinct per-role (e.g. the role glyphs
//     in AuthRoleIcons — those are meant to differ).

import 'package:flutter/material.dart';

/// Shared icon constants for Beautica screens.
///
/// Import this class wherever a shared icon is needed. The consistency
/// guard test asserts every screen that is supposed to use a constant
/// actually renders that exact `IconData`.
abstract final class BeauticaIcons {
  /// The top-bar "settings/menu" burger button icon.
  ///
  /// Used by:
  ///   • [MasterProfileScreen] — `Key('btn-menu-master')`
  ///   • [HomeHubScreen]       — `Key('btn-menu-client')`
  ///
  /// Both `NeumorphicIconButton` instances pass this as their `icon:` argument.
  static const IconData menuBurger = Icons.tune_rounded;
}
