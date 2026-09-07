// ITEM 4 (this track, mobile-debugger) — the STATIC precondition is
// structurally isomorphic to the booking-day crash class (see
// `booking_calendar_invalidation.dart`'s FIX A/B doc for the full
// citation-backed mechanism), and this recipe drives it through the REAL
// production widgets/function.
//
// THE RECIPE
// -----------
//   1. Load `MasterScheduleScreen` on week W — `effectiveScheduleProvider
//      (_range)` builds and pins itself via `_pinForTtl()`'s 5-minute
//      `ref.keepAlive()` timer (`effective_schedule_notifier.dart`).
//   2. Tap the week-nav arrow — the SAME still-mounted screen re-keys its OWN
//      `ref.watch(effectiveScheduleProvider(_range))` onto week W+1 (`_range`
//      is derived from local `_weekStart`). W's element drops to zero
//      listeners, alive only via its keepAlive timer — pinned-but-unwatched.
//   3. Cover the screen with an opaque route.
//   4. Run the REAL `WeeklyScheduleNotifier.save(...)` — the SAME method
//      `weekly_template_editor_screen.dart` calls — through a real
//      `WidgetRef`. Its `_invalidateEffectiveScheduleWindows` (FIX D)
//      enumerates every range `EffectiveScheduleRangeTracker` has seen,
//      including the pinned-but-unwatched W.
//   5. Pop back.
//   6. Tap the week-nav arrow back to W — re-`ref.watch`ing the IDENTICAL
//      family member the save just touched.
//   7. Assert no `FlutterError` and the screen resolves to its content state.
//
// AFTER FIX D: each candidate range is gated on `WidgetRef.exists` before
// invalidating, with an eager `ref.read` back when it was pinned — see
// `weekly_schedule_notifier.dart`'s FIX D doc.
//
// HONEST LIMITATION (checked empirically, mutation-probed against the
// UN-fixed code, same diagnostic technique as
// `master_reviews_sort_pin_race_test.dart`): this file's mutation probe did
// NOT reproduce a crash either — `effectiveScheduleProvider`'s
// `_pinForTtl()`-based keepAlive disposes just as fast as
// `masterReviewsProvider`'s in this harness, closing the observable race
// window before any subsequent widget action can land inside it. Kept for
// the same reason: it drives the REAL widgets/function end-to-end and passes
// with the fix. `weekly_schedule_notifier_test.dart`'s ITEM 6 tests are what
// actually mutation-prove this family's fix, at the unit level.

import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/schedule/data/schedule_repository.dart';
import 'package:beautica_mobile/features/schedule/data/schedule_repository_provider.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_scope.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/features/schedule/presentation/master_schedule_screen.dart';
import 'package:beautica_mobile/features/schedule/presentation/weekly_schedule_notifier.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/keepalive_pin_race_harness.dart';

const User _stubUser = User(
  id: 'u-1',
  email: 'test@beautica.ua',
  role: UserRole.independentMaster,
  firstName: 'Тест',
  lastName: 'Майстер',
);

const Master _stubMaster = Master(
  id: 'master-1',
  firstName: 'Тест',
  lastName: 'Майстер',
  avgRating: 5.0,
  reviewCount: 0,
  type: MasterType.independentMaster,
);

/// What `ownScheduleScopeProvider` resolves to for `_stubMaster` — this test
/// never passes an explicit `scope` to `MasterScheduleScreen`/
/// `WeeklyTemplateEditorScreen`, so every screen resolves "me" via that
/// provider, which watches `masterProfileProvider` (stubbed above).
const ScheduleScope _scope = ScheduleScope.own(masterId: 'master-1');

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

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// A minimal fake [ScheduleRepository] — every day is a template working day
/// (Mon-Fri) so the screen reaches its full content state (never the empty
/// no-schedule body), and every write resolves instantly.
class _FakeScheduleRepository implements ScheduleRepository {
  @override
  Future<List<EffectiveDay>> effectiveSchedule(
    DateTime from,
    DateTime to,
  ) async {
    final List<EffectiveDay> out = <EffectiveDay>[];
    DateTime cursor = _dateOnly(from);
    final DateTime end = _dateOnly(to);
    while (!cursor.isAfter(end)) {
      final bool working =
          cursor.weekday >= DateTime.monday &&
          cursor.weekday <= DateTime.friday;
      out.add(
        EffectiveDay(
          date: cursor,
          source: EffectiveSource.template,
          intervals: working
              ? <WorkInterval>[
                  WorkInterval(
                    start: const TimeOfDay(hour: 9, minute: 0),
                    end: const TimeOfDay(hour: 18, minute: 0),
                  ),
                ]
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
  Future<ScheduleOverride> putOverride(
    ScheduleOverride override, {
    bool cancelOverlapping = false,
  }) async => override;

  @override
  Future<void> clearOverride(DateTime date) async {}

  @override
  Future<OverrideConflictCheck> previewConflicts(ScheduleOverride span) async =>
      const OverrideConflictCheck(
        conflicts: <OverrideConflict>[],
        totalCount: 0,
        truncated: false,
        scanTruncated: false,
      );

  @override
  Future<List<WeeklySchedule>> listWeeklySchedules() async => <WeeklySchedule>[
    WeeklySchedule(
      id: 's1',
      validFrom: DateTime(2020, 1, 1),
      validTo: null,
      days: <TemplateDay>[
        for (var dow = 1; dow <= 7; dow++)
          TemplateDay(
            dayOfWeek: dow,
            label: 'd$dow',
            intervals: dow <= 5
                ? <WorkInterval>[
                    WorkInterval(
                      start: const TimeOfDay(hour: 9, minute: 0),
                      end: const TimeOfDay(hour: 18, minute: 0),
                    ),
                  ]
                : const <WorkInterval>[],
          ),
      ],
    ),
  ];

  @override
  Future<WeeklySchedule> upsertWeeklySchedule(
    WeeklySchedule schedule, {
    String? scheduleId,
  }) async => schedule;

  @override
  Future<void> deleteWeeklySchedule(String scheduleId) async {}
}

WeeklySchedule _template() => WeeklySchedule(
  id: 's1',
  validFrom: DateTime(2020, 1, 1),
  validTo: null,
  days: <TemplateDay>[
    for (var dow = 1; dow <= 7; dow++)
      TemplateDay(
        dayOfWeek: dow,
        label: 'd$dow',
        intervals: dow <= 5
            ? <WorkInterval>[
                WorkInterval(
                  start: const TimeOfDay(hour: 9, minute: 0),
                  end: const TimeOfDay(hour: 18, minute: 0),
                ),
              ]
            : const <WorkInterval>[],
      ),
  ],
);

GoRouter _router() => GoRouter(
  initialLocation: '/schedule',
  routes: <RouteBase>[
    GoRoute(
      path: '/schedule',
      builder: (BuildContext context, GoRouterState state) =>
          const MasterScheduleScreen(),
    ),
    // Opaque and full-screen — mirrors `WeeklyTemplateEditorScreen` covering
    // the calendar, and where this test performs the EXACT
    // `WeeklyScheduleNotifier.save` call via a real `WidgetRef`.
    GoRoute(
      path: '/editor',
      builder: (BuildContext context, GoRouterState state) => Scaffold(
        body: Consumer(
          builder: (BuildContext context, WidgetRef ref, _) => Center(
            child: TextButton(
              key: const Key('run-weekly-schedule-save'),
              onPressed: () => ref
                  .read(weeklyScheduleProvider(_scope).notifier)
                  .save(_template(), scheduleId: 's1'),
              child: const Text('save'),
            ),
          ),
        ),
      ),
    ),
  ],
);

void main() {
  testWidgets('invalidating a pinned-but-unwatched week, then paging back to it after '
      'popping back, throws NO FlutterError and reaches the content state '
      'within a bounded pump budget', (tester) async {
    final GoRouter router = _router();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Object>[
          authProvider.overrideWith(_StubAuthNotifier.new),
          masterProfileProvider.overrideWith(_StubMasterProfile.new),
          scheduleRepositoryProvider.overrideWith(
            (ref, scope) => _FakeScheduleRepository(),
          ),
        ].cast(),
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('uk'),
          routerConfig: router,
        ),
      ),
    );

    // --- steps 1-2: settle week W, then page to W+1 (W becomes
    // --- pinned-but-unwatched via `_pinForTtl()`'s own keepAlive timer).
    await tester.pump();
    await tester.pump();
    // fixed-wait-ok: mirrors master_schedule_screen_refresh_test.dart's own documented settle sequence — no stable Key distinguishes "provider state machine + keepAlive setup flushed" from "one frame in", so there is nothing to pump-until against.
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.byKey(const Key('schedule-weekly-card')),
      findsOneWidget,
      reason: 'sanity: week W reached the content state',
    );

    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pump();
    // fixed-wait-ok: same settle-sequence reasoning as above, after a week-nav tap.
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.byKey(const Key('schedule-weekly-card')),
      findsOneWidget,
      reason: 'sanity: week W+1 loaded — W is now unwatched, not paused',
    );

    await expectKeepAlivePinRaceClosed(
      tester,
      router,
      coverRouteKey: '/editor',
      invalidate: () =>
          tester.tap(find.byKey(const Key('run-weekly-schedule-save'))),
      reestablishWatch: () async {
        // The shared harness's own post-pop pump is a single ZERO-duration
        // frame — not enough for `MasterScheduleScreen`'s own MaterialPage
        // pop transition to reach its final layout, so the week-nav arrow
        // (anchored near the screen edge) can still be off-screen mid-slide.
        // This settling pump is BEFORE the tap, not after, so it does not
        // reopen/close anything about the race window itself — see the
        // file header's HONEST LIMITATION note: this family's disposal is
        // already long complete by this point regardless of pump timing.
        // fixed-wait-ok: settling a MaterialPage pop transition before hit-testing an edge-anchored icon — no stable Key marks "transition complete" to pump-until against.
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byIcon(Icons.chevron_left_rounded));
        // fixed-wait-ok: same settle-sequence reasoning as the steps 1-2 pumps above, after the reselect tap.
        await tester.pump(const Duration(milliseconds: 100));
      },
      loadingFinder: find.byType(CircularProgressIndicator),
      resolvedFinder: find.byKey(const Key('schedule-weekly-card')),
    );
  });
}
