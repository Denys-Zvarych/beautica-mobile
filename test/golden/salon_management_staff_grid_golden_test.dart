// mobile-perf LOW fix (2026-09-13) — safety-net golden for
// `_StaffTab`'s roster grid inside [SalonManagementProfileScreen] («Команда»
// tab), captured BEFORE converting the eager `GridView.builder(shrinkWrap:
// true, physics: NeverScrollableScrollPhysics)` to a lazy sliver grid.
//
// WHY THIS FILE EXISTS
// ---------------------
// `grep -a -rln "SalonManagementProfileScreen\|_StaffTab\|salon-manage-staff"
// test/golden/` returned NOTHING before this file — no golden covers this
// screen at all. A layout regression from the eager -> lazy grid conversion
// would have been caught by nothing. This file's two baselines are captured
// against the UNMODIFIED, `shrinkWrap: true` implementation and must stay
// byte-identical once the grid is converted to `SliverGrid.builder` — the
// refactor is rendering-only, not a visual change.
//
// TWO STATES
// ----------
//   1. multi-row roster  — 5 staff members (masters + admins) => 6 grid
//      cells (5 cards + the trailing "+  Запросити" add-tile) => 3 rows at
//      the fixed 2-column layout. Exercises row-wrap, cross-axis spacing and
//      the add-tile sitting in the last, partially-filled row.
//   2. single-row self-only — exactly ONE staff member (the signed-in
//      viewer's own row per the Phase 327 "list every member" decision) =>
//      2 grid cells (1 card + the add-tile) => a single row. Exercises the
//      empty-vs-populated boundary the `staff.isEmpty` empty-state text sits
//      next to (never rendered here — `staff` is non-empty in both states).
//
// Single width (414dp) / single text scale (1.0x), mirroring
// `salon_staff_profile_golden_test.dart`'s precedent for a content-driven,
// non-full-matrix surface — this is a structural pixel-pin, not a responsive
// matrix (that's `salon_management_profile_screen_test.dart`'s job).
//
// Strategy: `salonManagementProfileProvider` overridden directly (mirrors
// `salon_management_profile_screen_test.dart`'s own
// `_AttemptCountingSalonManagementProfile` override shape) so no repository
// or Dio wiring is needed. Viewer is SALON_ADMIN (not owner) so
// `_bounceIfNotOwned` short-circuits on the role check without needing a
// `mySalonsProvider`/`salonRepositoryProvider` override — an owner viewer
// would otherwise leave a real (unmocked) `mySalonsProvider` fetch pending.
// `tab: kSalonStaffSubTab` renders the «Команда» tab directly, skipping the
// «Про салон» default.

import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_management_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_management_profile_screen.dart';

import 'helpers/golden_pump.dart';

const String _kSalonId = 'salon-1';

const _stubSalon = Salon(
  id: _kSalonId,
  name: 'Салон «Вельвет»',
  description: 'Затишний салон краси в серці Печерська.',
  street: 'вул. Велика Васильківська',
  buildingNo: '44',
  avgRating: 4.9,
  reviewCount: 128,
);

const _kAdminViewer = User(
  id: 'admin-viewer-1',
  email: 'admin-viewer@beautica.ua',
  role: UserRole.salonAdmin,
  firstName: 'Ірина',
  lastName: 'Бойко',
);

class _StubAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async =>
      const AuthSession.authenticated(user: _kAdminViewer, accessToken: 'tok');
}

/// Direct override, mirroring
/// `salon_management_profile_screen_test.dart`'s
/// `_AttemptCountingSalonManagementProfile` shape.
class _FixedSalonManagementProfile extends SalonManagementProfile {
  _FixedSalonManagementProfile(this._data);

  final SalonManagementProfileData _data;

  @override
  Future<SalonManagementProfileData> build(String salonId) async => _data;
}

const List<SalonStaffMember> _multiRowRoster = <SalonStaffMember>[
  SalonStaffMember(
    userId: 'master-1',
    masterId: 'master-1',
    role: SalonStaffRole.master,
    firstName: 'Олена',
    lastName: 'Ковальчук',
    professionalTitle: 'Майстер манікюру',
    avgRating: 4.9,
    reviewCount: 12,
  ),
  SalonStaffMember(
    userId: 'master-2',
    masterId: 'master-2',
    role: SalonStaffRole.master,
    firstName: 'Ганна',
    lastName: 'Петренко',
    avgRating: 4.2,
    reviewCount: 5,
  ),
  SalonStaffMember(
    userId: 'admin-1',
    role: SalonStaffRole.admin,
    firstName: 'Ірина',
    lastName: 'Ковальська',
  ),
  SalonStaffMember(
    userId: 'master-3',
    masterId: 'master-3',
    role: SalonStaffRole.master,
    firstName: 'Софія',
    lastName: 'Бондаренко',
  ),
  SalonStaffMember(
    userId: 'admin-2',
    role: SalonStaffRole.admin,
    firstName: 'Наталя',
    lastName: 'Сидоренко',
  ),
];

const List<SalonStaffMember> _selfOnlyRoster = <SalonStaffMember>[
  SalonStaffMember(
    userId: 'admin-viewer-1',
    role: SalonStaffRole.admin,
    firstName: 'Ірина',
    lastName: 'Бойко',
  ),
];

List<Object> _overrides(List<SalonStaffMember> staff) => <Object>[
  authProvider.overrideWith(_StubAuthNotifier.new),
  salonManagementProfileProvider(
    _kSalonId,
  ).overrideWith(() => _FixedSalonManagementProfile((_stubSalon, staff))),
];

const double _kWidth = 414;
const double _kHeight = 1500;

void main() {
  final List<({String name, List<SalonStaffMember> staff})> cases =
      <({String name, List<SalonStaffMember> staff})>[
        (name: 'salon_manage_staff_grid_multi_row', staff: _multiRowRoster),
        (name: 'salon_manage_staff_grid_self_only', staff: _selfOnlyRoster),
      ];

  for (final ({String name, List<SalonStaffMember> staff}) c in cases) {
    goldenTest(
      'SalonManagementProfileScreen «Команда» ${c.name}',
      fileName: c.name,
      constraints: BoxConstraints.tight(const Size(_kWidth, _kHeight)),
      textScaleFactor: 1.0,
      pumpWidget: goldenPumpWidget(
        overrides: _overrides(c.staff),
        width: _kWidth,
      ),
      builder: () => SalonManagementProfileScreen(
        salonId: _kSalonId,
        tab: kSalonStaffSubTab,
        onTabSelected: (_) {},
      ),
    );
  }
}
