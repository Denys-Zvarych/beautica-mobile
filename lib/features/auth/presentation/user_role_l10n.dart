// Phase 2.6 — Localised label extension for [UserRole].
//
// Lives in presentation/ because it depends on [AppLocalizations] and
// [flutter/material.dart] (Flutter dependencies). The pure domain [UserRole]
// enum stays in domain/ with no Flutter imports.

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../domain/user_role.dart';

/// Provides a localised display label for each [UserRole] value.
extension UserRoleL10n on UserRole {
  /// Returns the localised string for this role suitable for display in the UI.
  String label(AppLocalizations l10n) => switch (this) {
    UserRole.client => l10n.roleClient,
    UserRole.salonOwner => l10n.roleSalonOwner,
    UserRole.salonAdmin => l10n.roleSalonAdmin,
    UserRole.salonMaster => l10n.roleSalonMaster,
    UserRole.independentMaster => l10n.roleIndependentMaster,
  };

  /// Returns a Material icon glyph that represents this role in summary chips
  /// and other compact UI surfaces (e.g. done screen, profile header).
  IconData get icon => switch (this) {
    UserRole.client => Icons.person_outline_rounded,
    UserRole.salonOwner => Icons.store_outlined,
    UserRole.salonAdmin => Icons.admin_panel_settings_outlined,
    UserRole.salonMaster => Icons.content_cut_outlined,
    UserRole.independentMaster => Icons.auto_fix_high_outlined,
  };
}
