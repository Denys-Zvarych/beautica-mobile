// Regression tests — pull-to-refresh on MasterScheduleScreen.
//
// WHAT THIS FILE COVERS
// ─────────────────────
// MasterScheduleScreen wraps its content in an [AppRefreshIndicator] whose
// [onRefresh] callback invalidates BOTH:
//   • `effectiveScheduleProvider(_range)` — the visible month's day list.
//   • `weeklyScheduleProvider`            — the master's weekly template.
// then awaits `effectiveScheduleProvider(_range).future`.
//
// This file proves the wiring is correct: a fling-down pull causes the
// repository fetch to be re-issued for the current range. It guards against
// someone removing the `ref.invalidate` calls or breaking the
// AppRefreshIndicator wiring in `_content()`.
//
// STRATEGY
// ────────
// • Override `scheduleRepositoryProvider` with a COUNTING fake that records
//   how many times `effectiveSchedule()` was called. Because the REAL
//   `EffectiveScheduleNotifier` + `WeeklyScheduleNotifier` run against this
//   repo, the invalidation chain is exercised end-to-end — no fake notifier
//   shortcuts the thing under test.
// • `authProvider` + `masterProfileProvider` are stubbed to avoid network I/O.
// • Finders use source Key constants — not localised strings (M2).
// • `pumpAndSettle` is intentionally NOT used for the refresh gesture: the
//   `effectiveScheduleProvider` has a 5-min keepAlive Timer after it resolves,
//   which means there is always a pending timer in the widget tree.
//   Instead we use a bounded pump sequence (documented below) that covers the
//   indicator's built-in dismiss animation without waiting for timers. (M6
//   exception: timer-driven keepAlive is framework infrastructure, not app
//   logic — suppressing it would require FakeAsync and is out of scope for a
//   pull-to-refresh regression.)
//
// NOTE ON pumpAndSettle / Timer
// ─────────────────────────────
// The effective-schedule notifier registers a 5-minute keepAlive Timer after
// each successful fetch (see EffectiveScheduleNotifier). pumpAndSettle()
// advances through ALL pending timers, so it would attempt to advance 5 min ×
// each notifier instance — effectively hanging the test runner's fake clock.
// The bounded-pump approach avoids that. Each pump step is annotated with its
// purpose so the sequencing is not "magic".

import 'dart:async';

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
import 'package:beautica_mobile/features/schedule/presentation/master_schedule_screen.dart';
import 'package:beautica_mobile/features/schedule/presentation/schedule_range.dart';
import 'package:beautica_mobile/features/calendar/domain/working_hours.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Stub auth / profile
// ─────────────────────────────────────────────────────────────────────────────

const _stubUser = User(
  id: 'u-1',
  email: 'test@beautica.ua',
  role: UserRole.independentMaster,
  firstName: 'Тест',
  lastName: 'Майстер',
);

const _stubMaster = Master(
  id: 'master-1',
  firstName: 'Тест',
  lastName: 'Майстер',
  avgRating: 5.0,
  reviewCount: 0,
  type: MasterType.independentMaster,
);

class _StubAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.authenticated(
    user: _stubUser,
    accessToken: 'test-token',
  );
}

class _StubMasterProfile extends MasterProfile {
  @override
  Future<Master> build() async => _stubMaster;
}

// ─────────────────────────────────────────────────────────────────────────────
// Counting fake repository
// ─────────────────────────────────────────────────────────────────────────────

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

WorkInterval _interval(int sh, int sm, int eh, int em) => WorkInterval(
  start: TimeOfDay(hour: sh, minute: sm),
  end: TimeOfDay(hour: eh, minute: em),
);

/// A fake [ScheduleRepository] that:
///   • Serves a minimal 7-day Mon→Sun week of effective days (Mon/Wed working,
///     others template-noSchedule) — enough for the screen to reach its full
///     content state (skips the empty-schedule body).
///   • Counts how many times `effectiveSchedule` was called so the test can
///     assert that a pull-to-refresh issues a re-fetch beyond the initial load.
class _CountingFakeScheduleRepository implements ScheduleRepository {
  int effectiveScheduleCallCount = 0;

  @override
  Future<List<EffectiveDay>> effectiveSchedule(
    DateTime from,
    DateTime to,
  ) async {
    effectiveScheduleCallCount++;
    // Build a dense list for the requested range (from..to inclusive) with
    // Mon/Wed as working template days so the screen renders CONTENT (not the
    // empty-state body), which is required for the pull gesture to reach the
    // AppRefreshIndicator.
    final List<EffectiveDay> out = <EffectiveDay>[];
    DateTime cursor = _dateOnly(from);
    final DateTime end = _dateOnly(to);
    while (!cursor.isAfter(end)) {
      final bool working =
          cursor.weekday == DateTime.monday ||
          cursor.weekday == DateTime.wednesday;
      out.add(
        EffectiveDay(
          date: cursor,
          source: EffectiveSource.template,
          intervals: working
              ? <WorkInterval>[_interval(9, 0, 18, 0)]
              : const <WorkInterval>[],
        ),
      );
      cursor = _dateOnly(cursor.add(const Duration(days: 1)));
    }
    return out;
  }

  @override
  Future<List<ScheduleOverride>> listOverrides(
    DateTime from,
    DateTime to,
  ) async => const <ScheduleOverride>[];

  @override
  Future<ScheduleOverride> putOverride(ScheduleOverride override) async =>
      override;

  @override
  Future<void> clearOverride(DateTime date) async {}

  @override
  Future<List<WeeklySchedule>> listWeeklySchedules() async =>
      const <WeeklySchedule>[];

  @override
  Future<WeeklySchedule> upsertWeeklySchedule(
    WeeklySchedule schedule, {
    String? scheduleId,
  }) async => schedule;

  @override
  Future<void> deleteWeeklySchedule(String scheduleId) async {}
}

// ─────────────────────────────────────────────────────────────────────────────
// Test harness
// ─────────────────────────────────────────────────────────────────────────────

/// Pumps [MasterScheduleScreen] inside a [ProviderScope] with overrides for
/// auth, master profile, and the schedule repository. Returns the fake
/// repository so callers can inspect call counts.
Future<_CountingFakeScheduleRepository> _pumpScreen(WidgetTester tester) async {
  final fakeRepo = _CountingFakeScheduleRepository();

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Object>[
        authProvider.overrideWith(_StubAuthNotifier.new),
        masterProfileProvider.overrideWith(_StubMasterProfile.new),
        scheduleRepositoryProvider.overrideWithValue(fakeRepo),
      ].cast(),
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('uk'),
        home: MasterScheduleScreen(),
      ),
    ),
  );

  return fakeRepo;
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('MasterScheduleScreen — pull-to-refresh', () {
    // ── 1. Initial load fetches the schedule ───────────────────────────────
    testWidgets('effectiveSchedule is called at least once on initial load', (
      tester,
    ) async {
      final fakeRepo = await _pumpScreen(tester);

      // One pump to start async providers, one to settle data emission.
      await tester.pump();
      await tester.pump();
      // Allow provider state machines and keepAlive setup to flush.
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        fakeRepo.effectiveScheduleCallCount,
        greaterThanOrEqualTo(1),
        reason:
            'Screen must request effective-schedule data from the repository '
            'on initial load',
      );
    });

    // ── 2. Pull-to-refresh re-issues effectiveSchedule ─────────────────────
    //
    // Approach:
    //   a. Pump until the screen reaches its content state (the weekly-card
    //      and calendar are visible — the Scrollable of the content ListView
    //      exists in the tree).
    //   b. Record the baseline call count.
    //   c. Fling down on the scrollable to trigger RefreshIndicator.onRefresh.
    //   d. Let the indicator start and the refresh future resolve (the fake
    //      returns instantly, so after one pump the future completes).
    //   e. Advance past Material's 250 ms dismiss animation.
    //   f. Assert the call count grew by at least 1.
    //
    // WHY NOT pumpAndSettle: explained in the file header — the 5-min
    // keepAlive Timer prevents it from settling. Each pump step is annotated.
    testWidgets('REGRESSION: pull-to-refresh re-fetches effectiveSchedule — '
        'invalidation fires onRefresh and the repository is re-called', (
      tester,
    ) async {
      final fakeRepo = await _pumpScreen(tester);

      // — Settle the initial load —
      // Pump 1: kick off async providers (start microtask queue).
      await tester.pump();
      // Pump 2: data emission from fakes (microtask → state update).
      await tester.pump();
      // Pump 3: let entrance animations and post-frame callbacks fire.
      await tester.pump(const Duration(milliseconds: 100));

      // Confirm the screen has reached the content state (not the spinner or
      // empty-state): the content ListView's Scrollable is present.
      // We look for the AppRefreshIndicator-wrapped scroll area.
      final scrollableFinder = find.byType(Scrollable);
      expect(
        scrollableFinder,
        findsWidgets,
        reason:
            'Screen must have rendered its content state for the pull '
            'gesture to reach the RefreshIndicator',
      );

      // Baseline: record fetches completed so far (initial load + any
      // cache-warming the fake triggers).
      final int baselineCount = fakeRepo.effectiveScheduleCallCount;

      // — Trigger pull-to-refresh —
      // Fling down from the first Scrollable. The screen's content() method
      // wraps the ListView in AppRefreshIndicator, so this Scrollable IS the
      // one the indicator intercepts.
      await tester.fling(scrollableFinder.first, const Offset(0, 400), 800);
      // Pump 1: RefreshIndicator intercepts the gesture, calls onRefresh,
      // and starts the pull animation.
      await tester.pump();
      // Pump 2: async onRefresh runs — invalidate + await provider.future.
      // The fake returns instantly so the future resolves in this pump.
      await tester.pump();
      // Pump 3 + 4: allow keepAlive callback + notifier state transitions.
      await tester.pump(const Duration(milliseconds: 50));
      // Pump 5: advance past Material's 250 ms dismiss animation so the
      // indicator clears and the screen is in a stable state.
      await tester.pump(const Duration(milliseconds: 300));

      // The total call count must have grown: at least one additional
      // `effectiveSchedule` call was issued by the invalidation triggered by
      // pull-to-refresh.
      expect(
        fakeRepo.effectiveScheduleCallCount,
        greaterThan(baselineCount),
        reason:
            'pull-to-refresh must invalidate effectiveScheduleProvider and '
            'cause the repository to re-fetch the effective schedule. '
            'Before fix: onRefresh only cleared the weeklyScheduleProvider '
            'without awaiting or invalidating the effective-schedule family.',
      );
    });

    // ── 3. AppRefreshIndicator is present in the content state ──────────────
    //
    // Structural guard: confirms AppRefreshIndicator is actually wired in for
    // the content state (it is absent from the error and loading states, which
    // are full-screen widgets not inside _content).
    testWidgets('AppRefreshIndicator widget is present in the content layout', (
      tester,
    ) async {
      await _pumpScreen(tester);

      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // The screen must have an AppRefreshIndicator (the brand-styled
      // wrapper) and its underlying Material RefreshIndicator.
      expect(
        find.byType(RefreshIndicator),
        findsOneWidget,
        reason:
            'AppRefreshIndicator (wrapping Material RefreshIndicator) must '
            'be wired in the MasterScheduleScreen content state',
      );
    });
  });
}
