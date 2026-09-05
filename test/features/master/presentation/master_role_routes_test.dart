// Unit tests for `master_role_routes.dart`'s two pure functions —
// `masterHomeRouteFor` / `masterMenuRouteFor` — PROMOTED (2026-09-01) from
// `personal_info_edit_screen.dart`'s private `_homeRouteFor`/`_menuRouteFor`
// when `contacts_edit_screen.dart` gained the identical need (see that
// file's header, REUSE-FIRST). Now shared by both edit screens, so a
// regression here breaks the post-save navigation and the onBack no-pop
// fallback for BOTH INDEPENDENT_MASTER and SALON_MASTER.
//
// Pure Dart, no Flutter widget tree needed — Layer: Unit.

import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_role_routes.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('masterHomeRouteFor', () {
    test('MasterType.salonMaster resolves to /staff/profile', () {
      expect(
        masterHomeRouteFor(MasterType.salonMaster),
        RouteNames.salonMasterProfile,
      );
    });

    test('MasterType.independentMaster resolves to /master/profile', () {
      expect(
        masterHomeRouteFor(MasterType.independentMaster),
        RouteNames.masterProfile,
      );
    });

    test('MasterType.salonOwner (no dedicated home yet) falls back to '
        '/master/profile — mirrors HttpMasterRepository.updateMyProfile\'s '
        'identical fallback (no salon-owner-as-master caller exists yet)', () {
      expect(
        masterHomeRouteFor(MasterType.salonOwner),
        RouteNames.masterProfile,
      );
    });

    test('salonMaster and independentMaster resolve to DIFFERENT routes '
        '(a collapsed switch would silently send both roles to the same '
        'screen)', () {
      expect(
        masterHomeRouteFor(MasterType.salonMaster),
        isNot(masterHomeRouteFor(MasterType.independentMaster)),
      );
    });
  });

  group('masterMenuRouteFor', () {
    test('MasterType.salonMaster resolves to /staff/settings', () {
      expect(
        masterMenuRouteFor(MasterType.salonMaster),
        RouteNames.salonMasterSettings,
      );
    });

    test('MasterType.independentMaster resolves to /master/menu', () {
      expect(
        masterMenuRouteFor(MasterType.independentMaster),
        RouteNames.masterMenu,
      );
    });

    test('MasterType.salonOwner (no dedicated settings hub yet) falls back to '
        '/master/menu', () {
      expect(masterMenuRouteFor(MasterType.salonOwner), RouteNames.masterMenu);
    });

    test('salonMaster and independentMaster resolve to DIFFERENT routes', () {
      expect(
        masterMenuRouteFor(MasterType.salonMaster),
        isNot(masterMenuRouteFor(MasterType.independentMaster)),
      );
    });
  });
}
