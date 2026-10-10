// Phase 137 (21.15) — pixel lock for the three `SettingsHubScreen`
// configurations: default (INDEPENDENT_MASTER), SALON_ADMIN and SALON_OWNER.
//
// The default and admin baselines were recorded BEFORE `showContacts` was
// added to the hub and re-run unchanged AFTER it, proving the additive param
// moved no existing caller. The owner baseline is new (no «Контакти», no
// «Локація»).

import 'package:beautica_mobile/features/master/presentation/settings_hub_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';

import 'helpers/golden_pump.dart';

void main() {
  const double width = 360;

  goldenTest(
    'settings hub — default (master) config',
    fileName: 'settings_hub_master_360_1x',
    constraints: BoxConstraints.tight(const Size(width, 760)),
    textScaleFactor: 1.0,
    pumpWidget: goldenPumpWidget(width: width),
    builder: () => const SettingsHubScreen(),
  );

  goldenTest(
    'settings hub — admin config',
    fileName: 'settings_hub_admin_360_1x',
    constraints: BoxConstraints.tight(const Size(width, 760)),
    textScaleFactor: 1.0,
    pumpWidget: goldenPumpWidget(width: width),
    builder: () => const SettingsHubScreen(
      showLocation: false,
      personalInfoRoute: RouteNames.adminEditPersonal,
      contactsRoute: RouteNames.adminEditContacts,
      fallbackHomeRoute: RouteNames.adminOwnProfile,
    ),
  );

  goldenTest(
    'settings hub — owner config',
    fileName: 'settings_hub_owner_360_1x',
    constraints: BoxConstraints.tight(const Size(width, 760)),
    textScaleFactor: 1.0,
    pumpWidget: goldenPumpWidget(width: width),
    builder: () => const SettingsHubScreen(
      showLocation: false,
      showContacts: false,
      personalInfoRoute: RouteNames.ownerEditPersonal,
      fallbackHomeRoute: RouteNames.ownerMasterProfile,
    ),
  );
}
