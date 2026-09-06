// Phase 311 — WeeklyTemplateEditorScreen self-checks `scheduleEditableProvider`.
//
// This screen's own edit path (loaded/dirty-diff/save/delete/CRUD) is
// exhaustively covered by `weekly_template_editor_screen_test.dart` — that
// file is NOT duplicated here. This file covers exactly the NEW surface
// Phase 311 adds: a non-editable viewer (SALON_MASTER) sees a read-only
// notice, zero editable controls, and — independently of the control being
// hidden — the `.save()`/`.delete()` write path itself refuses to reach the
// repository (D2's belt-and-braces early return).
//
// D2 proof technique: pump the screen EDITABLE (controls visible, Save
// wired), then flip the underlying `authProvider` session to SALON_MASTER via
// a `_MutableAuthNotifier.setSession` WITHOUT an intervening `tester.pump()`.
// Riverpod recomputes `scheduleEditableProvider` on the next `ref.read`
// (synchronous, on demand) but the WIDGET TREE has not rebuilt yet (Flutter's
// `markNeedsBuild()` only schedules a rebuild for the next frame) — so the
// Save button, built while editable, is still findable and tappable. Tapping
// it now exercises `_save()`'s own early return against the FRESH (false)
// provider value, independently of the control's own visibility. This is the
// only technique available from a black-box test: `_save` is a private
// member of a different library and cannot be invoked directly.
//
// Layer: Widget.

import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/schedule/data/schedule_repository.dart';
import 'package:beautica_mobile/features/schedule/data/schedule_repository_provider.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/features/schedule/presentation/weekly_template_editor_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/salon_notice_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

class _MockScheduleRepository extends Mock implements ScheduleRepository {}

class _FakeWeeklySchedule extends Fake implements WeeklySchedule {}

/// Mutable session stub — see this file's header for why `setSession` (not a
/// fixed session) is load-bearing for the D2 proof.
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

final DateTime _clock = DateTime(2026, 6, 9); // a Tuesday

WorkInterval _interval(int sh, int sm, int eh, int em) => WorkInterval(
  start: TimeOfDay(hour: sh, minute: sm),
  end: TimeOfDay(hour: eh, minute: em),
);

WeeklySchedule _template() => WeeklySchedule(
  id: 'sched-1',
  validFrom: _clock,
  validTo: null,
  days: <TemplateDay>[
    for (int dow = 1; dow <= 7; dow++)
      TemplateDay(
        dayOfWeek: dow,
        label: 'd$dow',
        intervals: dow <= 5
            ? <WorkInterval>[_interval(9, 0, 18, 0)]
            : <WorkInterval>[],
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
  await tester.pumpWidget(
    ProviderScope(
      retry: beauticaProviderRetry,
      overrides: <Object>[
        scheduleRepositoryProvider.overrideWithValue(repo),
        clockProvider.overrideWithValue(() => _clock),
        authProvider.overrideWith(() => authNotifier),
      ].cast(),
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('uk'),
        home: WeeklyTemplateEditorScreen(),
      ),
    ),
  );
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
      () => repo.listWeeklySchedules(),
    ).thenAnswer((_) async => <WeeklySchedule>[_template()]);
    when(
      () => repo.upsertWeeklySchedule(
        any(),
        scheduleId: any(named: 'scheduleId'),
      ),
    ).thenAnswer(
      (inv) async => inv.positionalArguments.first as WeeklySchedule,
    );
    when(() => repo.deleteWeeklySchedule(any())).thenAnswer((_) async {});
  });

  group('SALON_MASTER (read-only)', () {
    testWidgets('renders the read-only notice and zero editable controls', (
      tester,
    ) async {
      await _pump(tester, role: UserRole.salonMaster, repo: repo);

      expect(
        find.byKey(const Key('weekly-editor-read-only-notice')),
        findsOneWidget,
      );
      expect(find.byType(SalonNoticeCard), findsOneWidget);

      // Every editable control, named individually.
      for (int dow = 1; dow <= 7; dow++) {
        expect(
          find.byKey(Key('weekly-toggle-$dow')),
          findsNothing,
          reason: 'day-$dow toggle must be absent for a read-only viewer',
        );
      }
      expect(
        find.byKey(const Key('btn-save-weekly-template')),
        findsNothing,
        reason: 'the save button must be absent for a read-only viewer',
      );
      expect(
        find.byKey(const Key('weekly-active-window-card')),
        findsNothing,
        reason:
            'the tappable active-window card (opens the Apply sheet) must '
            'be absent for a read-only viewer',
      );

      verifyNever(
        () => repo.upsertWeeklySchedule(
          any(),
          scheduleId: any(named: 'scheduleId'),
        ),
      );
      verifyNever(() => repo.deleteWeeklySchedule(any()));
    });
  });

  group('INDEPENDENT_MASTER (editable) — positive counterpart', () {
    testWidgets('every control IS present; the read-only notice is absent', (
      tester,
    ) async {
      await _pump(tester, role: UserRole.independentMaster, repo: repo);

      expect(
        find.byKey(const Key('weekly-editor-read-only-notice')),
        findsNothing,
      );
      // Checked BEFORE scrolling the day list — it sits above the day
      // cards in the same lazy ListView and would itself scroll out of
      // the built range once the loop below scrolls past it.
      expect(
        find.byKey(const Key('weekly-active-window-card')),
        findsOneWidget,
      );

      // The day cards live in a scrolling ListView, so lower days lazily
      // build — scroll each into view (mirrors
      // weekly_template_editor_screen_test.dart's identical pattern).
      final Finder list = find.byType(Scrollable).first;
      for (int dow = 1; dow <= 7; dow++) {
        await tester.scrollUntilVisible(
          find.byKey(Key('weekly-toggle-$dow')),
          120,
          scrollable: list,
        );
        expect(find.byKey(Key('weekly-toggle-$dow')), findsOneWidget);
      }
      await tester.scrollUntilVisible(
        find.byKey(const Key('btn-save-weekly-template')),
        120,
        scrollable: list,
      );
      expect(find.byKey(const Key('btn-save-weekly-template')), findsOneWidget);
    });
  });

  group('D2 — the write handler itself refuses a stale-editable tap '
      '(belt-and-braces, independent of the hidden control)', () {
    testWidgets(
      'flipping the session to SALON_MASTER after the Save button is already '
      'wired, then tapping it, must NOT reach the repository',
      (tester) async {
        final authNotifier = await _pump(
          tester,
          role: UserRole.independentMaster,
          repo: repo,
        );

        // Make a real edit so Save is enabled (not disabled-by-pristine).
        final Finder list = find.byType(Scrollable).first;
        await tester.scrollUntilVisible(
          find.byKey(const Key('weekly-toggle-6')),
          120,
          scrollable: list,
        );
        await tester.tap(find.byKey(const Key('weekly-toggle-6'))); // Sat on
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const Key('btn-save-weekly-template')),
          120,
          scrollable: list,
        );
        expect(
          find.byKey(const Key('btn-save-weekly-template')),
          findsOneWidget,
        );

        // Flip the session WITHOUT pumping a frame — the tree still shows the
        // editable build (Save button present), but `scheduleEditableProvider`
        // now resolves `false` on the NEXT `ref.read`.
        authNotifier.setSession(
          const AuthSession.authenticated(
            user: _salonMasterUser,
            accessToken: 'token',
          ),
        );

        await tester.tap(find.byKey(const Key('btn-save-weekly-template')));
        // Deliberately a single `pump`, not `pumpAndSettle`: the point is to
        // observe the immediate synchronous effect of the tap before the
        // provider-change-triggered rebuild (which would hide the button)
        // ever gets a frame.
        await tester.pump();

        verifyNever(
          () => repo.upsertWeeklySchedule(
            any(),
            scheduleId: any(named: 'scheduleId'),
          ),
        );
        verifyNever(() => repo.deleteWeeklySchedule(any()));
      },
    );
  });
}
