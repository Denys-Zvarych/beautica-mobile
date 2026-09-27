// Phase 312 — route-level tests for the new
// `/salons/:salonId/manage/staff/:memberId/schedule` subtree (D9).
//
// Two things this file exists to pin, both from the phase's required
// mutation list:
//
//   1. THE MUTATION-CRITICAL CASE — "route builds with no scope → repository
//      drives the WRONG masterId": navigates through the REAL `appRouter`
//      (not a hand-rolled local router — the whole point is pinning the
//      router WIRING itself) to the schedule entry route with the resolved
//      [ScheduleScope] carried as `extra`, then asserts the ACTUAL API call
//      the repository makes — `masterApi.getWeeklySchedules(masterId:
//      'viewed-master-id')` — never the widget field. A regression that
//      drops `state.extra` on the floor (falling back to `ownScheduleScopeProvider`,
//      "me") would call `getWeeklySchedules(masterId: '')` instead (a
//      SALON_ADMIN has no own master row — `own_schedule_scope.dart`) and
//      this test goes red.
//   2. "…/staff/schedule declared before :memberId → negative pin" — nothing
//      declares a literal `/salons/:salonId/manage/staff/schedule` (ONE
//      segment after `staff/`); a URL shaped like that must fall through to
//      the PRE-EXISTING `/salons/:salonId/manage/staff/:memberId` profile
//      route with `:memberId == 'schedule'`, NOT to any of this phase's new
//      routes (which all require a memberId segment BEFORE their own literal
//      tail, i.e. two segments after `staff/`).

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/app_start_time.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/core/network/api_client_provider.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_management_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_staff_profile_screen.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_scope.dart';
import 'package:beautica_mobile/features/schedule/presentation/master_schedule_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/fakes/fake_auth_repository.dart';
import '../helpers/fakes/fake_secure_storage.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const String _kSalonId = 'the-salon-id';
const String _kMemberId = 'the-roster-member-id';
const String _kViewedMasterId = 'viewed-master-id';

const User _kAdmin = User(
  id: 'admin-1',
  email: 'admin@beautica.ua',
  role: UserRole.salonAdmin,
  firstName: 'Тест',
  lastName: 'Адмін',
  salonId: _kSalonId,
);

class _FixedAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async =>
      const AuthSession.authenticated(user: _kAdmin, accessToken: 'tok');
}

/// Resolves the roster IMMEDIATELY to an empty staff list — this test never
/// asserts editability, only which masterId the READ path calls with, so an
/// empty roster (and therefore `scheduleEditableProvider` resolving `false`)
/// costs nothing.
class _SettledEmptyRoster extends SalonManagementProfile {
  @override
  Future<SalonManagementProfileData> build(String salonId) async =>
      (const Salon(id: _kSalonId, name: 'Салон'), const <SalonStaffMember>[]);
}

class _MockMasterControllerApi extends Mock implements MasterControllerApi {}

class _RouterApp extends StatelessWidget {
  const _RouterApp({required this.router});
  final GoRouter router;

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    routerConfig: router,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('uk', 'UA'),
  );
}

void main() {
  setUpAll(() {
    // `getEffectiveSchedule`/`getOverrides` take `Date`-typed `from`/`to`
    // params (the generated OpenAPI client's type, not `DateTime`) — mocktail
    // needs a fallback registered before `any(named: 'from'|'to')` can be
    // used, mirroring `schedule_repository_test.dart`'s identical setup.
    registerFallbackValue(Date(2026, 1, 1));
  });

  setUp(
    () => AppStartTime.setStartForTest(
      DateTime.now().subtract(const Duration(seconds: 5)),
    ),
  );
  tearDown(AppStartTime.resetForTest);

  late _MockMasterControllerApi masterApi;

  setUp(() {
    masterApi = _MockMasterControllerApi();
    when(
      () => masterApi.getWeeklySchedules(masterId: any(named: 'masterId')),
    ).thenAnswer(
      (_) async => Response<ApiResponseListWeeklyScheduleResponse>(
        data: ApiResponseListWeeklyScheduleResponse((b) => b..success = true),
        requestOptions: RequestOptions(
          path: '/api/v1/masters/x/weekly-schedules',
        ),
        statusCode: 200,
      ),
    );
    when(
      () => masterApi.getEffectiveSchedule(
        masterId: any(named: 'masterId'),
        from: any(named: 'from'),
        to: any(named: 'to'),
      ),
    ).thenAnswer(
      (_) async => Response<ApiResponseListEffectiveDayResponse>(
        data: ApiResponseListEffectiveDayResponse((b) => b..success = true),
        requestOptions: RequestOptions(
          path: '/api/v1/masters/x/effective-schedule',
        ),
        statusCode: 200,
      ),
    );
    when(
      () => masterApi.getOverrides(
        masterId: any(named: 'masterId'),
        from: any(named: 'from'),
        to: any(named: 'to'),
      ),
    ).thenAnswer(
      (_) async => Response<ApiResponseListScheduleOverrideResponse>(
        data: ApiResponseListScheduleOverrideResponse((b) => b..success = true),
        requestOptions: RequestOptions(path: '/api/v1/masters/x/overrides'),
        statusCode: 200,
      ),
    );
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      retry: beauticaProviderRetry,
      overrides: [
        authProvider.overrideWith(_FixedAuthNotifier.new),
        authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
        secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
        masterApiProvider.overrideWithValue(masterApi),
        salonManagementProfileProvider.overrideWith(_SettledEmptyRoster.new),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  testWidgets(
    'route entry with extra:ScheduleScope drives the repository at the '
    'VIEWED master, never "me" — the mutation-critical assertion',
    (tester) async {
      final container = makeContainer();
      final router = container.read(appRouterProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _RouterApp(router: router),
        ),
      );
      // Let `authProvider` genuinely settle BEFORE navigating — the initial
      // pump alone can still be on `/splash` (or whatever `authRedirect`
      // parks an unresolved session on), and a `router.go` issued into that
      // window can be re-redirected out from under it.
      await container.read(authProvider.future);
      await tester.pump();

      router.go(
        RouteNames.salonManageStaffSchedule(_kSalonId, _kMemberId),
        extra: const ScheduleScope.salonMaster(
          salonId: _kSalonId,
          masterId: _kViewedMasterId,
        ),
      );
      await tester.pump();

      // NOT `pumpAndSettle` (the salon shell underneath carries repeating
      // shimmer/scale animations that never settle) and NOT a bare
      // `pumpUntilGone(CircularProgressIndicator)` (the salon shell's OWN
      // transient loading spinner satisfies — and clears — that finder
      // before `MasterScheduleScreen`'s OWN data-loading spinner has
      // resolved, since both are the exact same widget type). Wait for the
      // condition that actually matters: `MasterScheduleScreen` mounted AND
      // ITS OWN spinner (scoped as a descendant) gone.
      final Finder screenFinder = find.byType(MasterScheduleScreen);
      final Finder screenSpinner = find.descendant(
        of: screenFinder,
        matching: find.byType(CircularProgressIndicator),
      );
      for (var i = 0; i < 30; i++) {
        if (screenFinder.evaluate().isNotEmpty &&
            screenSpinner.evaluate().isEmpty) {
          break;
        }
        // fixed-wait-ok: this IS pump-until — the loop above exits the
        // instant the compound condition (screen mounted AND its own
        // spinner gone) holds; the 50ms is only the polling step, not a
        // guessed total wait. Same precedent as `wishlist_route_test.dart`'s
        // `_pumpUntil`. `pumpUntilFound` alone can't express this because
        // the condition is a conjunction of two finders, not one.
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.byType(MasterScheduleScreen), findsOneWidget);
      verify(
        () => masterApi.getWeeklySchedules(masterId: _kViewedMasterId),
      ).called(greaterThanOrEqualTo(1));
      // The exact regression this test exists to catch: a route that
      // silently fell back to "me" would call with '' (own_schedule_scope
      // .dart's refusal id for SALON_ADMIN), never `_kViewedMasterId`.
      verifyNever(() => masterApi.getWeeklySchedules(masterId: ''));

      // Drain `EffectiveScheduleNotifier`'s real 5-minute `_pinForTtl()`
      // Timer — mirrors `master_schedule_screen_test.dart`'s
      // `_drainKeepAliveTimers` precedent — or flutter_test's own
      // "Timer still pending after the widget tree was disposed" invariant
      // fires at teardown. Not `pumpAndSettle` (the salon shell underneath
      // carries repeating animations that never settle).
      // fixed-wait-ok: advancing the virtual clock past a known 5-minute TTL
      // Timer so it fires and drains — there is no widget/state CONDITION to
      // pump-until here, only a fixed real-time threshold that must elapse.
      await tester.pump(const Duration(minutes: 6));
    },
  );

  testWidgets(
    'negative pin — /salons/:salonId/manage/staff/schedule (ONE segment) '
    'resolves the PRE-EXISTING profile route with memberId == "schedule", '
    'NOT any Phase 312 route',
    (tester) async {
      final container = makeContainer();
      final router = container.read(appRouterProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _RouterApp(router: router),
        ),
      );
      await tester.pump();

      router.go('/salons/$_kSalonId/manage/staff/schedule');
      await tester.pump();
      await tester.pump();

      expect(
        find.byType(SalonStaffProfileScreen),
        findsOneWidget,
        reason:
            'no route declares a literal one-segment ".../staff/schedule" — '
            'it must fall through to the dynamic :memberId profile route '
            '(memberId == "schedule"), never to any Phase 312 route (all of '
            'which require a memberId segment BEFORE their own literal tail)',
      );
      expect(find.byType(MasterScheduleScreen), findsNothing);

      final SalonStaffProfileScreen screen = tester
          .widget<SalonStaffProfileScreen>(
            find.byType(SalonStaffProfileScreen),
          );
      expect(screen.memberId, 'schedule');
    },
  );
}
