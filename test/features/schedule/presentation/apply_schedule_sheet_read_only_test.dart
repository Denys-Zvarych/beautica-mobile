// Phase 311 — ApplyScheduleSheet self-checks `scheduleEditableProvider`.
//
// This sheet's own edit path (presets, custom range, upsert, overlap
// rejection) is exhaustively covered by `apply_schedule_sheet_test.dart` —
// NOT duplicated here. This file covers exactly the NEW surface Phase 311
// adds: a non-editable viewer (SALON_MASTER) sees a read-only notice, zero
// editable controls, and — independently of the control being hidden — the
// `.save()` write path itself refuses to reach the repository (D2's
// belt-and-braces early return).
//
// See `weekly_template_editor_screen_read_only_test.dart`'s header for the
// full explanation of the D2 proof technique (flip the session via a mutable
// auth notifier WITHOUT an intervening `tester.pump()`, then tap the
// still-built control) — `_apply` is a private member of a different
// library and cannot be invoked directly from a test.
//
// Layer: Widget.

import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/schedule/data/schedule_repository.dart';
import 'package:beautica_mobile/features/schedule/data/schedule_repository_provider.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/features/schedule/presentation/apply_schedule_sheet.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/salon_notice_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

class _MockScheduleRepository extends Mock implements ScheduleRepository {}

class _FakeWeeklySchedule extends Fake implements WeeklySchedule {}

/// Mutable session stub — see this file's header / the weekly-editor sibling
/// for why `setSession` (not a fixed session) is load-bearing for the D2
/// proof.
class _MutableAuthNotifier extends AuthNotifier {
  _MutableAuthNotifier(this._initial);
  final AuthSession _initial;

  @override
  Future<AuthSession> build() async => _initial;

  void setSession(AuthSession session) =>
      state = AsyncData<AuthSession>(session);
}

const User _independentMasterUser = User(
  id: 'master-1',
  email: 'master1@beautica.ua',
  role: UserRole.independentMaster,
  firstName: 'Оля',
  lastName: 'Коваль',
);

const User _salonMasterUser = User(
  id: 'staff-1',
  email: 'staff1@beautica.ua',
  role: UserRole.salonMaster,
  firstName: 'Іван',
  lastName: 'Петров',
);

/// Phase 312 — `ApplyScheduleSheet` (no explicit `scope:` in this file — see
/// `showApplyScheduleSheet` below) resolves `ownScheduleScopeProvider`, which
/// watches `masterProfileProvider` for BOTH roles this file exercises
/// (INDEPENDENT_MASTER and SALON_MASTER both have an own master row). Without
/// a stub it falls through to the real `masterRepositoryProvider` → a
/// genuine Dio HTTP attempt that leaves a pending platform timer and trips
/// `!timersPending` on this file's D2 tests (no intervening `tester.pump()`
/// between the session flip and the tap, by design — see this file's header).
class _StubMasterProfile extends MasterProfile {
  @override
  Future<Master> build() async => const Master(
    id: 'master-row-1',
    firstName: 'Оля',
    lastName: 'Коваль',
    avgRating: null,
    reviewCount: 0,
    type: MasterType.independentMaster,
  );
}

final DateTime _today = DateTime(2024, 5, 22);

WeeklySchedule _baseSchedule() => WeeklySchedule(
  id: 's1',
  validFrom: _today,
  validTo: null,
  days: <TemplateDay>[
    for (var dow = 1; dow <= 7; dow++)
      TemplateDay(
        dayOfWeek: dow,
        label: 'd$dow',
        intervals: const <WorkInterval>[],
      ),
  ],
);

Future<_MutableAuthNotifier> _pump(
  WidgetTester tester, {
  required UserRole role,
  required ScheduleRepository repo,
}) async {
  final authNotifier = _MutableAuthNotifier(
    AuthSession.authenticated(
      user: role == UserRole.independentMaster
          ? _independentMasterUser
          : _salonMasterUser,
      accessToken: 'token',
    ),
  );
  final router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const Key('open-apply-sheet'),
              onPressed: () => showApplyScheduleSheet(
                context,
                baseSchedule: _baseSchedule(),
                today: _today,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      retry: beauticaProviderRetry,
      overrides: <Object>[
        scheduleRepositoryProvider.overrideWith((ref, scope) => repo),
        authProvider.overrideWith(() => authNotifier),
        // Phase 312 — see `_StubMasterProfile`'s doc.
        masterProfileProvider.overrideWith(_StubMasterProfile.new),
      ].cast(),
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('uk'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('open-apply-sheet')));
  await tester.pumpAndSettle();
  return authNotifier;
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeWeeklySchedule());
  });

  late _MockScheduleRepository repo;

  setUp(() {
    repo = _MockScheduleRepository();
    when(
      () => repo.upsertWeeklySchedule(
        any(),
        scheduleId: any(named: 'scheduleId'),
      ),
    ).thenAnswer(
      (inv) async => inv.positionalArguments.first as WeeklySchedule,
    );
  });

  group('SALON_MASTER (read-only)', () {
    testWidgets('renders the read-only notice and zero editable controls', (
      tester,
    ) async {
      await _pump(tester, role: UserRole.salonMaster, repo: repo);

      expect(
        find.byKey(const Key('apply-schedule-read-only-notice')),
        findsOneWidget,
      );
      expect(find.byType(SalonNoticeCard), findsOneWidget);

      expect(find.byKey(const Key('preset-this-month')), findsNothing);
      expect(find.byKey(const Key('preset-next-3-months')), findsNothing);
      expect(find.byKey(const Key('preset-whole-year')), findsNothing);
      expect(find.byKey(const Key('apply-schedule-date-well')), findsNothing);
      expect(find.byKey(const Key('btn-apply-schedule')), findsNothing);

      verifyNever(
        () => repo.upsertWeeklySchedule(
          any(),
          scheduleId: any(named: 'scheduleId'),
        ),
      );
    });
  });

  group('INDEPENDENT_MASTER (editable) — positive counterpart', () {
    testWidgets('every control IS present; the read-only notice is absent', (
      tester,
    ) async {
      await _pump(tester, role: UserRole.independentMaster, repo: repo);

      expect(
        find.byKey(const Key('apply-schedule-read-only-notice')),
        findsNothing,
      );
      expect(find.byKey(const Key('preset-this-month')), findsOneWidget);
      expect(find.byKey(const Key('preset-next-3-months')), findsOneWidget);
      expect(find.byKey(const Key('preset-whole-year')), findsOneWidget);
      expect(find.byKey(const Key('apply-schedule-date-well')), findsOneWidget);
      expect(find.byKey(const Key('btn-apply-schedule')), findsOneWidget);
    });
  });

  group('D2 — the write handler itself refuses a stale-editable tap '
      '(belt-and-braces, independent of the hidden control)', () {
    testWidgets(
      'flipping the session to SALON_MASTER after Apply is already wired, '
      'then tapping it, must NOT reach upsertWeeklySchedule',
      (tester) async {
        final authNotifier = await _pump(
          tester,
          role: UserRole.independentMaster,
          repo: repo,
        );

        // Pick a preset so the CTA is enabled (not inert-by-no-range).
        await tester.tap(find.byKey(const Key('preset-this-month')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('btn-apply-schedule')), findsOneWidget);

        authNotifier.setSession(
          const AuthSession.authenticated(
            user: _salonMasterUser,
            accessToken: 'token',
          ),
        );

        await tester.tap(find.byKey(const Key('btn-apply-schedule')));
        // Deliberately a single `pump`: observe the tap's synchronous effect
        // before the provider-change-triggered rebuild (which would hide the
        // button) ever gets a frame.
        await tester.pump();

        verifyNever(
          () => repo.upsertWeeklySchedule(
            any(),
            scheduleId: any(named: 'scheduleId'),
          ),
        );
      },
    );
  });
}
