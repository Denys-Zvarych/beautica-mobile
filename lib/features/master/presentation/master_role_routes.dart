// Shared per-[MasterType] route resolution for the master profile
// section-edit pages (Особисті дані / Контакти / …) that are pushed by BOTH
// the INDEPENDENT_MASTER settings hub and the SALON_MASTER one from the same
// widget — see each screen's own "Multi-role reuse" header note.
//
// PROMOTED from `personal_info_edit_screen.dart`'s private `_homeRouteFor`/
// `_menuRouteFor` (2026-09-01) when `contacts_edit_screen.dart` gained the
// identical need — REUSE-FIRST: a second hand-copy would have drifted the
// same way the `_selectRailDay` helpers did.
//
// Mirrors the established `roleHomePath`-on-a-shared-screen pattern
// (`routing/role_home.dart`) but keyed on the already-loaded [Master.type]
// rather than [UserRole] — these screens have the master in hand and would
// otherwise need a second provider read just to re-derive what [Master.type]
// already tells them.

import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/routing/route_names.dart';

/// The tab-root/landing route to return to after a successful save.
String masterHomeRouteFor(MasterType type) => switch (type) {
  MasterType.salonMaster => RouteNames.salonMasterProfile,
  MasterType.independentMaster ||
  MasterType.salonOwner => RouteNames.masterProfile,
};

/// The settings-hub route a section-edit page's `onBack` no-pop fallback
/// returns to, resolved the same way as [masterHomeRouteFor].
String masterMenuRouteFor(MasterType type) => switch (type) {
  MasterType.salonMaster => RouteNames.salonMasterSettings,
  MasterType.independentMaster ||
  MasterType.salonOwner => RouteNames.masterMenu,
};
