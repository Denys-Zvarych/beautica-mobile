// Phase 324 (mobile-qa D1) — Visual regression goldens for
// [SalonStaffProfileScreen].
//
// WHY THIS FILE EXISTS
// ---------------------
// `grep -a -rln "SalonStaffProfileScreen" test/golden/` returned NOTHING
// before this file — backlog rows 806 and 807 deferred a golden for this
// screen deliberately, on the grounds that a freshly generated baseline is
// self-referential and needs human review before it can serve as a
// regression baseline (`feedback_golden_not_acceptance`). Phase 324 is that
// review point: the four PNGs this file seeds are NOT acceptance evidence on
// their own — they were reviewed as images against the widget's source
// before being committed, and from here their only job is to catch
// unintended pixel drift.
//
// FOUR STATES (phase 324 D1's matrix row for this surface)
// ----------------------------------------------------------
//   1. owner viewing a master       — «Послуги» / «Графік роботи» card pair
//      both ENABLED, the `tune_rounded` management gear IS shown (the owner
//      is not looking at their own row).
//   2. admin viewing a master       — SAME master fixture, but the viewer is
//      a SALON_ADMIN, not the owner. Pins the Phase 307 locked asymmetry:
//      the gear is a SALON_OWNER-only affordance on a MASTER row, so it is
//      ABSENT here even though it was present in state 1 — same data, only
//      the viewer role differs.
//   3. master entry, no `masterId`  — the Phase 318 data-anomaly case: both
//      action cards render `enabled: false` (the D2-mirrored
//      `hasMasterId` guard).
//   4. admin entry                  — no stats row, no bio, no services
//      block, no action-card pair at all; the gear IS shown (an ADMIN row
//      always gets it, regardless of viewer role).
//
// Single width (414dp) / single text scale (1.0x) per state — this screen's
// responsive behaviour is already covered by
// `test/features/salon/presentation/salon_staff_profile_screen_test.dart`;
// this file's job is pixel-pinning four STRUCTURAL states, not a responsive
// matrix (mirrors `delete_service_dialog_golden_test.dart`'s single-width
// precedent for a content-driven, non-full-matrix surface).
//
// Height: a custom 1900dp viewport (not the shared `kGoldenHeight` 900) —
// this is a long scrolling profile (identity + stats + bio + services grid +
// contacts + action-card pair) and a 900dp capture would clip content a
// human reviewer needs to see. Extra blank space below shorter states (the
// admin entry, the no-masterId master) is harmless — no RenderFlex overflow
// is possible in a `SingleChildScrollView`.
//
// Strategy: identical fixtures to
// `salon_staff_profile_screen_test.dart` (`_masterMember`,
// `_masterMemberNoMasterId`, `_adminMember`), `salonStaffMemberProfileProvider`
// overridden directly, `weeklyScheduleProvider` fixed to a Mon–Fri template
// so the schedule card shows real hours (not a loading skeleton — every
// state here must be a SETTLED frame), `approvedCategoriesProvider` stubbed
// empty (same "real Dio call hangs pumpAndSettle" footgun the widget test
// documents), `authProvider` stubbed per state to select the viewer role.

import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_staff_member_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_staff_profile_screen.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_scope.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/features/schedule/presentation/weekly_schedule_notifier.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:flutter/material.dart';

import 'helpers/golden_pump.dart';

// ---------------------------------------------------------------------------
// Fixtures — mirror salon_staff_profile_screen_test.dart verbatim (same ids,
// same field values) so this golden's rendered content matches what the
// widget-test suite already asserts field-by-field.
// ---------------------------------------------------------------------------

const String _kSalonId = 'salon-1';
const String _kMasterId = 'staff-master-1';
const String _kAdminId = 'staff-admin-1';

const _masterMember = SalonStaffMember(
  userId: _kMasterId,
  masterId: 'master-row-1',
  role: SalonStaffRole.master,
  firstName: 'Олена',
  lastName: 'Ковальчук',
  professionalTitle: 'Майстер манікюру',
  phoneNumber: '+380671112233',
  bio: 'Досвідчений майстер з 5-річним стажем роботи.',
  avgRating: 4.8,
  reviewCount: 32,
);

const _masterMemberNoMasterId = SalonStaffMember(
  userId: _kMasterId,
  role: SalonStaffRole.master,
  firstName: 'Ганна',
  lastName: 'Петренко',
  avgRating: 4.0,
  reviewCount: 2,
);

const _adminMember = SalonStaffMember(
  userId: _kAdminId,
  role: SalonStaffRole.admin,
  firstName: 'Ірина',
  lastName: 'Ковальська',
  phoneNumber: '+380509998877',
);

const List<MasterService> _masterServices = <MasterService>[
  MasterService(
    id: 'svc-1',
    serviceDefId: 'def-1',
    name: 'Манікюр з покриттям',
    durationMinutes: 90,
    priceMin: 500,
    priceDisplay: '500 ₴',
    category: 'NAILS',
  ),
  MasterService(
    id: 'svc-2',
    serviceDefId: 'def-2',
    name: 'Корекція брів',
    durationMinutes: 30,
    priceMin: 250,
    priceDisplay: '250 ₴',
    category: 'BROWS',
  ),
];

final ScheduleScope _scheduleRowScope = ScheduleScope.salonMaster(
  salonId: _kSalonId,
  masterId: _masterMember.masterId!,
);

final List<WeeklySchedule> _weekdayTemplate = <WeeklySchedule>[
  WeeklySchedule(
    id: 'wt-1',
    validFrom: DateTime(2020, 1, 1),
    validTo: null,
    days: <TemplateDay>[
      for (int day = 1; day <= 7; day++)
        TemplateDay(
          dayOfWeek: day,
          label: 'day-$day',
          intervals: day <= 5
              ? <WorkInterval>[
                  WorkInterval(
                    start: const TimeOfDay(hour: 9, minute: 0),
                    end: const TimeOfDay(hour: 18, minute: 0),
                  ),
                ]
              : <WorkInterval>[],
        ),
    ],
  ),
];

class _FixedWeekly extends WeeklyScheduleNotifier {
  @override
  Future<List<WeeklySchedule>> build(ScheduleScope scope) async =>
      _weekdayTemplate;
}

// ---------------------------------------------------------------------------
// Viewers
// ---------------------------------------------------------------------------

const User _kOwner = User(
  id: 'owner-1',
  email: 'owner@beautica.ua',
  role: UserRole.salonOwner,
  firstName: 'Оксана',
  lastName: 'Швець',
);

const User _kAdminViewer = User(
  id: 'admin-viewer-1',
  email: 'admin-viewer@beautica.ua',
  role: UserRole.salonAdmin,
  firstName: 'Ірина',
  lastName: 'Бойко',
);

class _StubAuthNotifier extends AuthNotifier {
  _StubAuthNotifier(this._user);

  final User _user;

  @override
  Future<AuthSession> build() async =>
      AuthSession.authenticated(user: _user, accessToken: 'tok');
}

// ---------------------------------------------------------------------------
// Override factory
// ---------------------------------------------------------------------------

List<Object> _overrides(
  String memberId,
  SalonStaffMemberProfileData data,
  User viewer,
) => <Object>[
  salonStaffMemberProfileProvider(
    _kSalonId,
    memberId,
  ).overrideWith((ref) async => data),
  approvedCategoriesProvider.overrideWith(
    (ref) async => const <ServiceCategoryOption>[],
  ),
  weeklyScheduleProvider(_scheduleRowScope).overrideWith(_FixedWeekly.new),
  authProvider.overrideWith(() => _StubAuthNotifier(viewer)),
];

const double _kWidth = 414;
const double _kHeight = 1900;

// ---------------------------------------------------------------------------
// Goldens
// ---------------------------------------------------------------------------

void main() {
  final List<({String name, Widget Function() builder, List<Object> overrides})>
  cases = <({String name, Widget Function() builder, List<Object> overrides})>[
    (
      name: 'salon_staff_profile_owner_viewing_master',
      builder: () => const SalonStaffProfileScreen(
        salonId: _kSalonId,
        memberId: _kMasterId,
      ),
      overrides: _overrides(_kMasterId, (
        _masterMember,
        _masterServices,
      ), _kOwner),
    ),
    (
      name: 'salon_staff_profile_admin_viewing_master',
      builder: () => const SalonStaffProfileScreen(
        salonId: _kSalonId,
        memberId: _kMasterId,
      ),
      overrides: _overrides(_kMasterId, (
        _masterMember,
        _masterServices,
      ), _kAdminViewer),
    ),
    (
      name: 'salon_staff_profile_master_no_masterid',
      builder: () => const SalonStaffProfileScreen(
        salonId: _kSalonId,
        memberId: _kMasterId,
      ),
      overrides: _overrides(_kMasterId, (
        _masterMemberNoMasterId,
        const <MasterService>[],
      ), _kOwner),
    ),
    (
      name: 'salon_staff_profile_admin_entry',
      builder: () => const SalonStaffProfileScreen(
        salonId: _kSalonId,
        memberId: _kAdminId,
      ),
      overrides: _overrides(_kAdminId, (
        _adminMember,
        const <MasterService>[],
      ), _kOwner),
    ),
  ];

  for (final ({String name, Widget Function() builder, List<Object> overrides})
      c
      in cases) {
    goldenTest(
      'SalonStaffProfileScreen ${c.name}',
      fileName: c.name,
      constraints: BoxConstraints.tight(const Size(_kWidth, _kHeight)),
      textScaleFactor: 1.0,
      pumpWidget: goldenPumpWidget(overrides: c.overrides, width: _kWidth),
      builder: c.builder,
    );
  }
}
