// Phase 2.6 — Localised label extension for [UserRole].
//
// Lives in presentation/ because it depends on [AppLocalizations] (a Flutter
// dependency). The pure domain [UserRole] enum stays in domain/ with no
// Flutter imports.

import 'package:beautica_mobile/l10n/app_localizations.dart';

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
}
