// The ONE master role-label resolver, shared by every surface that has to
// name what a master IS rather than what they call themselves.
//
// PROMOTED out of `features/booking/presentation/widgets/master_strip.dart`,
// where it lived as a top-level function beside the booking strip: the salon
// management surfaces (`salon_management_profile_screen.dart`,
// `salon_staff_profile_screen.dart`) need the same wording, and a salon
// presentation file must not import a BOOKING widget file just to read a
// label. The body is unchanged by the move — every former caller resolves
// byte-identical text.
//
// Lives under `master/presentation/` because the label is keyed by
// [MasterType], the master feature's own domain enum.

import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

/// Resolves a display label for [type]. Shared by every booking-flow screen
/// that renders a `MasterStrip` / day-header chip and by the salon roster /
/// staff-profile surfaces, so the wording never drifts from
/// `PublicMasterProfileScreen`'s own `_roleLabel`.
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
