// Phase 311 — DayHoursSheet self-checks `scheduleEditableProvider`.
//
// This sheet's own edit path (working-hours/day-off modes, save, clear,
// booking-conflict gate, 409-retry) is exhaustively covered by
// `day_hours_sheet_test.dart` — NOT duplicated here. This file covers exactly
// the NEW surface Phase 311 adds: a non-editable viewer (SALON_MASTER) sees a
// read-only notice, zero editable controls, and — independently of the
// control being hidden — the `.save()`/`.clear()` write path itself refuses
// to reach the repository (D2's belt-and-braces early return).
//
// See `weekly_template_editor_screen_read_only_test.dart`'s header for the
// full explanation of the D2 proof technique (flip the session via a mutable
// auth notifier WITHOUT an intervening `tester.pump()`, then tap the
// still-built control) — `_save`/`_clear` are private members of a different
// library and cannot be invoked directly from a test.
//
// Layer: Widget.

import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/schedule/data/schedule_repository.dart';
import 'package:beautica_mobile/features/schedule/data/schedule_repository_provider.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/presentation/day_hours_sheet.dart';
import 'package:beautica_mobile/features/schedule/presentation/schedule_range.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/salon_notice_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

import '../../../helpers/clock_instant.dart';

class _MockScheduleRepository extends Mock implements ScheduleRepository {}

class _FakeScheduleOverride extends Fake implements ScheduleOverride {}

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

final DateTime _date = DateTime(2026, 6, 21);
final ScheduleRange _range = ScheduleRange(
  from: DateTime(2026, 6, 1),
  to: DateTime(2026, 6, 30),
);

const OverrideConflictCheck _noConflicts = OverrideConflictCheck(
  conflicts: <OverrideConflict>[],
  totalCount: 0,
  truncated: false,
  scanTruncated: false,
);

WorkInterval _interval(int sh, int sm, int eh, int em) => WorkInterval(
  start: TimeOfDay(hour: sh, minute: sm),
  end: TimeOfDay(hour: eh, minute: em),
);

_MockScheduleRepository _happyRepo() {
  final repo = _MockScheduleRepository();
  when(
    () => repo.listOverrides(any(), any()),
  ).thenAnswer((_) async => const <ScheduleOverride>[]);
  when(
    () => repo.previewConflicts(any()),
  ).thenAnswer((_) async => _noConflicts);
  when(
    () => repo.putOverride(
      any(),
      cancelOverlapping: any(named: 'cancelOverlapping'),
    ),
  ).thenAnswer(
    (inv) async => inv.positionalArguments.first as ScheduleOverride,
  );
  when(() => repo.clearOverride(any())).thenAnswer((_) async {});
  return repo;
}

Future<_MutableAuthNotifier> _pump(
  WidgetTester tester, {
  required UserRole role,
  required ScheduleRepository repo,
  bool hasExistingOverride = false,
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
        authProvider.overrideWith(() => authNotifier),
      ].cast(),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('uk'),
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => Center(
              child: ElevatedButton(
                key: const Key('open-sheet'),
                onPressed: () => DayHoursSheet.show(
                  context,
                  date: _date,
                  weekdayFull: 'Неділя',
                  dateLabel: '21 червня',
                  range: _range,
                  initialIntervals: <WorkInterval>[_interval(9, 0, 18, 0)],
                  hasExistingOverride: hasExistingOverride,
                  initialDayOff: false,
                  clock: () => asClockInstant(_date),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open-sheet')));
  await tester.pumpAndSettle();
  return authNotifier;
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeScheduleOverride());
  });

  group('SALON_MASTER (read-only)', () {
    testWidgets('renders the read-only notice and zero editable controls', (
      tester,
    ) async {
      final repo = _happyRepo();
      await _pump(
        tester,
        role: UserRole.salonMaster,
        repo: repo,
        hasExistingOverride: true,
      );

      expect(
        find.byKey(const Key('day-hours-sheet-read-only-notice')),
        findsOneWidget,
      );
      expect(find.byType(SalonNoticeCard), findsOneWidget);

      expect(
        find.byKey(const Key('override-mode-toggle')),
        findsNothing,
        reason: 'the Робочі години/Вихідний mode toggle must be absent',
      );
      expect(
        find.byKey(const Key('override-work-mode-toggle')),
        findsNothing,
        reason: 'the interval/discrete sub-toggle must be absent',
      );
      expect(
        find.byKey(const Key('override-save')),
        findsNothing,
        reason: 'the save button must be absent',
      );
      expect(
        find.byKey(const Key('override-delete')),
        findsNothing,
        reason:
            'the revert-to-template action must be absent even though '
            'hasExistingOverride is true',
      );

      verifyNever(
        () => repo.putOverride(
          any(),
          cancelOverlapping: any(named: 'cancelOverlapping'),
        ),
      );
      verifyNever(() => repo.clearOverride(any()));
    });
  });

  group('INDEPENDENT_MASTER (editable) — positive counterpart', () {
    testWidgets('every control IS present; the read-only notice is absent', (
      tester,
    ) async {
      final repo = _happyRepo();
      await _pump(
        tester,
        role: UserRole.independentMaster,
        repo: repo,
        hasExistingOverride: true,
      );

      expect(
        find.byKey(const Key('day-hours-sheet-read-only-notice')),
        findsNothing,
      );
      expect(find.byKey(const Key('override-mode-toggle')), findsOneWidget);
      expect(
        find.byKey(const Key('override-work-mode-toggle')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('override-save')), findsOneWidget);
      expect(find.byKey(const Key('override-delete')), findsOneWidget);
    });
  });

  group('D2 — the write handlers themselves refuse a stale-editable tap '
      '(belt-and-braces, independent of the hidden control)', () {
    testWidgets(
      'flipping the session to SALON_MASTER after Save is already wired, '
      'then tapping it, must NOT reach putOverride',
      (tester) async {
        final repo = _happyRepo();
        final authNotifier = await _pump(
          tester,
          role: UserRole.independentMaster,
          repo: repo,
        );
        expect(find.byKey(const Key('override-save')), findsOneWidget);

        authNotifier.setSession(
          const AuthSession.authenticated(
            user: _salonMasterUser,
            accessToken: 'token',
          ),
        );

        await tester.tap(find.byKey(const Key('override-save')));
        // Deliberately a single `pump`: observe the tap's synchronous effect
        // before the provider-change-triggered rebuild (which would hide the
        // button) ever gets a frame.
        await tester.pump();

        verifyNever(
          () => repo.putOverride(
            any(),
            cancelOverlapping: any(named: 'cancelOverlapping'),
          ),
        );
      },
    );

    testWidgets(
      'flipping the session to SALON_MASTER after Revert is already wired, '
      'then tapping it, must NOT reach clearOverride',
      (tester) async {
        final repo = _happyRepo();
        final authNotifier = await _pump(
          tester,
          role: UserRole.independentMaster,
          repo: repo,
          hasExistingOverride: true,
        );
        expect(find.byKey(const Key('override-delete')), findsOneWidget);

        authNotifier.setSession(
          const AuthSession.authenticated(
            user: _salonMasterUser,
            accessToken: 'token',
          ),
        );

        await tester.tap(find.byKey(const Key('override-delete')));
        await tester.pump();

        verifyNever(() => repo.clearOverride(any()));
      },
    );
  });
}
