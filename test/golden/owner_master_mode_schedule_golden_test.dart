// Phase 381 (24.1d) — pixel coverage for the SALON_OWNER's «master mode»
// «Графік» tab: [MasterScheduleScreen] mounted exactly as the
// `RouteNames.ownerMasterSchedule` route mounts it — the owner's OWN-row
// `ScheduleScope.salonMaster`, the owner tile-2 [VelvetBottomNavBar] and the
// top-left labelled «‹ Салон» back pill (phase 378's `VelvetTopBar.backLabel`).
//
// The all-null default (every pre-existing mount) is pinned byte-identical by
// the unchanged `test/features/schedule/presentation/goldens/schedule_*.png`
// baselines in `master_schedule_screen_test.dart`.
//
// Matrix: {320, 360, 414} dp × {textScale 1.0, 1.3} = 6 golden PNGs.

import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/salon/application/my_salons_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_management_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_scope.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/features/schedule/presentation/effective_schedule_notifier.dart';
import 'package:beautica_mobile/features/schedule/presentation/master_schedule_screen.dart';
import 'package:beautica_mobile/features/schedule/presentation/schedule_range.dart';
import 'package:beautica_mobile/features/schedule/presentation/weekly_schedule_notifier.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart' show kyivAddDays;
import 'package:beautica_mobile/shared/widgets/velvet_bottom_nav_bar.dart';
import 'package:flutter/material.dart' show TimeOfDay;

import '../helpers/clock_instant.dart';
import 'helpers/golden_pump.dart';

const String _kSalonId = 'salon-owner-golden';
const String _kOwnerRowId = 'master-row-owner-golden';

/// Fixed Kyiv DATE TOKEN — a Saturday, so the visible week is Mon 8 .. Sun 14
/// June 2026 regardless of the run day.
final DateTime _today = DateTime(2026, 6, 13);

/// Visible label of the back pill — the l10n value of `ownerMasterModeBack`.
const String _kBackLabel = 'Салон';

WorkInterval _interval(int sh, int eh) => WorkInterval(
  start: TimeOfDay(hour: sh, minute: 0),
  end: TimeOfDay(hour: eh, minute: 0),
);

/// Mon–Fri 10:00–18:00, weekend off — the owner's own template.
bool _isWeekday(int dow) => dow <= 5;

List<EffectiveDay> _days() {
  final DateTime monday = kyivAddDays(_today, 1 - _today.weekday);
  return <EffectiveDay>[
    for (int i = 0; i < 7; i++)
      EffectiveDay(
        date: kyivAddDays(monday, i),
        source: EffectiveSource.template,
        intervals: _isWeekday(i + 1)
            ? <WorkInterval>[_interval(10, 18)]
            : const <WorkInterval>[],
      ),
  ];
}

class _OwnerAuth extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.authenticated(
    user: User(id: 'u-owner', email: 'o@b.c', role: UserRole.salonOwner),
    accessToken: 'tkn',
  );
}

class _Days extends EffectiveScheduleNotifier {
  @override
  Future<List<EffectiveDay>> build(
    ScheduleScope scope,
    ScheduleRange range,
  ) async => _days();
}

class _Weekly extends WeeklyScheduleNotifier {
  @override
  Future<List<WeeklySchedule>> build(ScheduleScope scope) async =>
      <WeeklySchedule>[
        WeeklySchedule(
          validFrom: _today,
          validTo: null,
          days: <TemplateDay>[
            for (int dow = 1; dow <= 7; dow++)
              TemplateDay(
                dayOfWeek: dow,
                label: 'd$dow',
                intervals: _isWeekday(dow)
                    ? <WorkInterval>[_interval(10, 18)]
                    : const <WorkInterval>[],
              ),
          ],
        ),
      ];
}

class _MySalons extends MySalons {
  @override
  Future<List<Salon>> build() async => const <Salon>[
    Salon(id: _kSalonId, name: 'Salon', isPrimary: true),
  ];
}

class _Roster extends SalonManagementProfile {
  @override
  Future<SalonManagementProfileData> build(String salonId) async => (
    const Salon(id: _kSalonId, name: 'Salon', isPrimary: true),
    const <SalonStaffMember>[
      SalonStaffMember(
        userId: 'u-owner',
        masterId: _kOwnerRowId,
        role: SalonStaffRole.master,
        firstName: 'Олена',
        lastName: 'Ковальчук',
      ),
    ],
  );
}

List<Object> _overrides() => <Object>[
  authProvider.overrideWith(_OwnerAuth.new),
  effectiveScheduleProvider.overrideWith(_Days.new),
  weeklyScheduleProvider.overrideWith(_Weekly.new),
  mySalonsProvider.overrideWith(_MySalons.new),
  salonManagementProfileProvider.overrideWith(_Roster.new),
];

void main() {
  for (final double width in kGoldenWidths) {
    for (final double scale in kGoldenTextScales) {
      final String suffix = widthScaleSuffix(width, scale);

      goldenTest(
        'owner_master_mode_schedule $suffix',
        fileName: 'owner_master_mode_schedule_$suffix',
        constraints: BoxConstraints.tight(Size(width, kGoldenHeight)),
        textScaleFactor: scale,
        pumpWidget: goldenPumpWidget(overrides: _overrides(), width: width),
        builder: () => MasterScheduleScreen(
          clock: () => asClockInstant(_today),
          scope: const ScheduleScope.salonMaster(
            salonId: _kSalonId,
            masterId: _kOwnerRowId,
          ),
          // Mirrors `app_router.dart`'s private `_kOwnerMasterNavBars[2]`.
          bottomNavBar: const VelvetBottomNavBar(
            activeIndex: 2,
            servicesRoute: RouteNames.ownerMasterServices,
            scheduleRoute: RouteNames.ownerMasterSchedule,
            profileRoute: RouteNames.ownerMasterProfile,
          ),
          backLabel: _kBackLabel,
          onBack: () {},
        ),
      );
    }
  }
}
