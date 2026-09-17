// mobile-security MEDIUM + mobile-perf LOW (both found it independently,
// 2026-09-17) — the Phase 335 salon-board cache survived logout.
//
// The MIRROR of `effective_schedule_cross_session_isolation_test.dart`, for the
// salon-scoped family that phase shipped. Read that file first; this one only
// explains where the two diverge, because the divergence is the entire reason
// this test had to exist as well.
//
// ## Why the sibling's structural guarantee does NOT carry over
//
// `effectiveScheduleProvider` is keyed on `ScheduleScope`, whose `masterId`
// DIFFERS per account: master A and master B key different family members, so a
// session flip re-keys onto a fresh member all by itself and isolation holds
// even with the 5-minute `keepAlive()` pin in place (that sibling test says so
// in its "Phase 312 ADDENDUM").
//
// `salonEffectiveScheduleProvider` is keyed on `(salonId, ScheduleRange)`.
// NEITHER component carries the authenticated identity, and on the scenario
// that matters — a shared salon tablet, one owner signs out, the next signs in
// to THE SAME SALON — the salonId is IDENTICAL and the range is the same
// `ScheduleRange.month(kyivToday(clock))`. Same key, same member, still pinned.
// Its whole chain (`salonRosterScheduleRepositoryProvider` →
// `scheduleSalonApiProvider` → `dioProvider`) contains no `authProvider` watch
// at any hop, so nothing rebuilds it and nothing evicts it either. The outgoing
// session's WHOLE ROSTER of working hours (186–310 parsed `EffectiveDay`s in
// the audited shape) would be served to the incoming one from memory, with no
// wire call and no server re-check.
//
// The fix is the explicit bare-family `ref.invalidate(salonEffectiveSchedule
// Provider)` in `AuthNotifier.logout()`'s session-boundary sweep, beside the
// two schedule sweeps that were already there. THIS TEST IS THAT LINE'S ONLY
// GUARD.
//
// ## Why this is OUTCOME-based, not a `verify(spy.clear())` interaction
//
// `auth_notifier_test.dart`'s `dayKeepAliveLruProvider.clear()` test had to
// assert the INTERACTION, because for that family Riverpod's own
// `invalidateSelf()` cascade (triggered by a real `authProvider` watch inside
// the notifier) already produced the outcome and the interaction test was the
// only thing that could discriminate the two layers. Here there is no such
// cascade to confound it: the family watches nothing auth-shaped, so the ONLY
// thing that can make the second read hit the network is the invalidate under
// test. An outcome assertion is therefore both sufficient and strictly
// stronger, and it is what the mutation below moves.
//
// MUTATION-VERIFIED — see the agent report for the transcript: deleting
// `ref.invalidate(salonEffectiveScheduleProvider)` from `auth_notifier.dart`
// turns this RED (fetch count stays at 1; salon owner B observes owner A's
// cached roster hours); restoring it turns it GREEN.
//
// ## ADDENDUM (mobile-security MEDIUM, 2026-09-17) — THE SWEEP STOPPED ONE
// ## HOP SHORT, and the second test in this file is that hop
//
// The fix above evicted `salonEffectiveScheduleProvider`. It did NOT evict the
// MASTER-scoped `overridesProvider`, and `EffectiveScheduleNotifier.build`
// `await`s `ref.watch(overridesProvider(scope, range).future)` as its GATING
// dependency. `OverridesNotifier.build` pins every member with its own
// `ref.keepAlive()` + 5-minute `Timer` and watches nothing auth-shaped, so an
// invalidated effective-schedule window immediately RE-DERIVED from the
// outgoing session's still-pinned override rows.
//
// The key collision is what makes it reachable, and only ONE of the two scope
// shapes has it. `ScheduleScope.own(masterId:)` carries the master id in its
// freezed structural identity, so two accounts never share a member and a
// session flip re-keys all by itself — the same structural guarantee the
// sibling test relies on. `ScheduleScope.salonMaster(salonId:, masterId:)` is
// byte-identical across two DIFFERENT accounts managing the SAME salon: on a
// shared reception device, owner B lands on owner A's pinned rows for the same
// roster master. Those rows are that master's per-date absences.
//
// `overridesRevisionProvider` is swept with it and has its own test below: it
// is the one-way counter `EffectiveScheduleNotifier` reads ALONGSIDE the
// overrides (its `writtenRange` drives the cross-range recompute-or-skip
// short-circuit), so a counter left holding the outgoing session's last
// written range is half the pair staying session-bound.
//
// NO live listener is held across the boundary, deliberately, and this is the
// one place the sibling's recipe is knowingly NOT copied. That sibling holds a
// subscription open for its whole body because its notifier has a cache-hit
// short-circuit that does NOT re-arm `ref.keepAlive()`, so an incidentally
// disposed-and-recreated instance could "pass" for the wrong reason. This
// notifier has exactly ONE completing path (its own header says so) and no
// hand-rolled cache field, so nothing here can pass by accident — and the
// listener-free shape is also the realistic one: the owner taps «Вийти», the
// board unmounts, and the member is left pinned ONLY by its own `keepAlive()`.
// That is precisely the state the finding describes.

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/auth_tokens.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/schedule/data/schedule_repository.dart';
import 'package:beautica_mobile/features/schedule/data/schedule_repository_provider.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_scope.dart';
import 'package:beautica_mobile/features/schedule/presentation/effective_schedule_notifier.dart';
import 'package:beautica_mobile/features/schedule/presentation/overrides_notifier.dart';
import 'package:beautica_mobile/features/schedule/presentation/overrides_revision_provider.dart';
import 'package:beautica_mobile/features/schedule/presentation/salon_effective_schedule_notifier.dart';
import 'package:beautica_mobile/features/schedule/presentation/schedule_range.dart';

import '../../../helpers/fakes/fake_secure_storage.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockSalonRosterScheduleRepository extends Mock
    implements SalonRosterScheduleRepository {}

class _MockScheduleRepository extends Mock implements ScheduleRepository {}

/// THE SAME salon on both sides of the boundary — a shared reception tablet.
/// If this differed per session the family key would differ and the whole
/// finding would be structurally impossible; making them equal is what puts
/// the cache-hit on the table.
const String _salonId = 'salon-velvet';

const User _ownerA = User(
  id: 'owner-a',
  email: 'owner-a@beautica.ua',
  role: UserRole.salonOwner,
  firstName: 'Оля',
  lastName: 'Коваль',
);

const User _ownerB = User(
  id: 'owner-b',
  email: 'owner-b@beautica.ua',
  role: UserRole.salonOwner,
  firstName: 'Ірина',
  lastName: 'Бондар',
);

const AuthTokens _tokensA = AuthTokens(
  accessToken: 'access-a',
  refreshToken: 'refresh-a',
);

const AuthTokens _tokensB = AuthTokens(
  accessToken: 'access-b',
  refreshToken: 'refresh-b',
);

/// One working day, distinguishable per session by its hours.
EffectiveDay _day(int startHour, int endHour) => EffectiveDay(
  date: DateTime(2026, 6, 15),
  source: EffectiveSource.template,
  intervals: <WorkInterval>[
    WorkInterval(
      start: TimeOfDay(hour: startHour, minute: 0),
      end: TimeOfDay(hour: endHour, minute: 0),
    ),
  ],
);

void main() {
  test('a logout followed by a DIFFERENT owner signing in to the SAME salon '
      'forces a FRESH roster-schedule fetch for the SAME month — owner B never '
      "observes owner A's keepAlive-cached roster hours (mobile-security "
      'MEDIUM regression guard, 2026-09-17)', () async {
    final authRepo = _MockAuthRepository();
    final rosterScheduleRepo = _MockSalonRosterScheduleRepository();
    final storage = FakeSecureStorage();
    await storage.writeRefreshToken(_tokensA.refreshToken);

    // Cold start restores owner A; the explicit login below brings owner B in.
    when(
      () => authRepo.refresh(_tokensA.refreshToken),
    ).thenAnswer((_) async => _tokensA);
    // `GET /auth/me` answers whoever is currently signing in — the cold-start
    // restore resolves owner A, and `login()` re-reads it for owner B's full
    // profile (`auth_notifier.dart:522`), so one mutable stub covers both.
    var meUser = _ownerA;
    when(() => authRepo.me()).thenAnswer((_) async => meUser);
    when(() => authRepo.logout()).thenAnswer((_) async {});
    when(
      () => authRepo.login(email: _ownerB.email, password: 'pw-b'),
    ).thenAnswer((_) async => (_ownerB, _tokensB));

    // Manual counter, not a second `verify(...).called(n)` — mocktail's
    // `verify` CONSUMES the interactions it matches, so asserting the same
    // filter twice would see "no matching calls" on the second assertion
    // regardless of what happened (the sibling test writes this out at
    // length).
    var fetches = 0;
    when(
      () =>
          rosterScheduleRepo.salonRosterEffectiveSchedule(any(), any(), any()),
    ).thenAnswer((_) async {
      fetches++;
      // Owner A's roster opens at 09:00, owner B's at 11:00 — so a stale serve
      // is visible in the DATA, not only in the call count. Without this a
      // regression that returned the right count for the wrong reason could
      // still pass.
      return <String, List<EffectiveDay>>{
        'm1': <EffectiveDay>[fetches == 1 ? _day(9, 18) : _day(11, 20)],
      };
    });

    final container = ProviderContainer(
      retry: beauticaProviderRetry,
      overrides: [
        authRepositoryProvider.overrideWith((_) => authRepo),
        secureStorageProvider.overrideWith((_) => storage),
        salonRosterScheduleRepositoryProvider.overrideWithValue(
          rosterScheduleRepo,
        ),
      ],
    );
    addTearDown(container.dispose);

    // The SAME key object shape both sessions resolve — literally what the
    // board passes (`ScheduleRange.month(kyivToday(clock))`), pinned to a
    // fixture month so the test cannot straddle a real month boundary.
    final ScheduleRange month = ScheduleRange.month(DateTime(2026, 6, 15));

    // ── 1. Owner A's session resolves the month — one real fetch, then
    // keepAlive-pinned for 5 minutes.
    final AuthSession sessionA = await container.read(authProvider.future);
    expect(
      sessionA,
      const AuthSession.authenticated(user: _ownerA, accessToken: 'access-a'),
    );

    final Map<String, List<EffectiveDay>> pageA = await container.read(
      salonEffectiveScheduleProvider(_salonId, month).future,
    );
    expect(pageA['m1']!.single.intervals.single.start.hour, 9);
    expect(fetches, 1);

    // ── 2. Same session, same key — served from the pin, no second call.
    // This step is load-bearing: it proves the cache is REAL, so step 4's
    // "a fetch happened" cannot be explained away by the member never having
    // been cached at all (the vacuous-negative trap).
    await container.read(
      salonEffectiveScheduleProvider(_salonId, month).future,
    );
    expect(
      fetches,
      1,
      reason:
          'the keepAlive pin genuinely serves the same key from memory — '
          'without this the next assertion would prove nothing',
    );

    // ── 3. Owner A signs out; owner B signs in to the SAME salon, well within
    // the 5-minute TTL. The REAL `logout()`, not a hand-rolled equivalent.
    await container.read(authProvider.notifier).logout();
    meUser = _ownerB;
    await container.read(authProvider.notifier).login(_ownerB.email, 'pw-b');
    expect(
      container.read(authProvider).value,
      const AuthSession.authenticated(user: _ownerB, accessToken: 'access-b'),
      reason: 'owner B is genuinely signed in before the second read',
    );

    // ── 4. Owner B's read of the SAME (salonId, month) key must go to the
    // network and return owner B's OWN roster hours.
    final Map<String, List<EffectiveDay>> pageB = await container.read(
      salonEffectiveScheduleProvider(_salonId, month).future,
    );

    expect(
      fetches,
      2,
      reason:
          'the session boundary must EVICT this family — serving owner B from '
          "owner A's pin is a whole-roster read with no wire call and no "
          'server re-check',
    );
    expect(
      pageB['m1']!.single.intervals.single.start.hour,
      11,
      reason:
          "owner B must observe owner B's OWN roster hours, never owner A's "
          'keepAlive-cached page',
    );
  });

  test('a logout followed by a DIFFERENT owner managing the SAME salon forces '
      'a FRESH listOverrides fetch for the SAME salonMaster scope — owner B '
      "never observes owner A's keepAlive-cached per-date absences "
      '(mobile-security MEDIUM regression guard, 2026-09-17)', () async {
    final authRepo = _MockAuthRepository();
    final scheduleRepo = _MockScheduleRepository();
    final storage = FakeSecureStorage();
    await storage.writeRefreshToken(_tokensA.refreshToken);

    when(
      () => authRepo.refresh(_tokensA.refreshToken),
    ).thenAnswer((_) async => _tokensA);
    var meUser = _ownerA;
    when(() => authRepo.me()).thenAnswer((_) async => meUser);
    when(() => authRepo.logout()).thenAnswer((_) async {});
    when(
      () => authRepo.login(email: _ownerB.email, password: 'pw-b'),
    ).thenAnswer((_) async => (_ownerB, _tokensB));

    // Manual counter, not `verify(...).called(n)` — mocktail's `verify`
    // CONSUMES the interactions it matches, so a second assertion on the same
    // filter would see "no matching calls" regardless of what happened.
    var fetches = 0;
    when(() => scheduleRepo.listOverrides(any(), any())).thenAnswer((_) async {
      fetches++;
      // Owner A's view of this master has a day off on the 15th; owner B's
      // does not — so a stale serve is visible in the DATA, not only in the
      // call count. Without this, a regression returning the right count for
      // the wrong reason would still pass.
      return fetches == 1
          ? <ScheduleOverride>[
              ScheduleOverride.dayOff(
                start: DateTime(2026, 6, 15),
                end: DateTime(2026, 6, 15),
              ),
            ]
          : const <ScheduleOverride>[];
    });

    final container = ProviderContainer(
      retry: beauticaProviderRetry,
      overrides: [
        authRepositoryProvider.overrideWith((_) => authRepo),
        secureStorageProvider.overrideWith((_) => storage),
        scheduleRepositoryProvider.overrideWith((ref, scope) => scheduleRepo),
      ],
    );
    addTearDown(container.dispose);

    // THE COLLIDING KEY. `ScheduleScope.salonMaster` is byte-identical across
    // two different accounts managing the same salon — that equality is the
    // whole finding, so it is asserted rather than assumed. (`ScheduleScope
    // .own` would NOT collide: its masterId is part of its freezed identity,
    // which is why the sibling master-scoped family needed no sweep.)
    const ScheduleScope scope = ScheduleScope.salonMaster(
      salonId: _salonId,
      masterId: 'master-1',
    );
    expect(
      scope,
      const ScheduleScope.salonMaster(salonId: _salonId, masterId: 'master-1'),
      reason:
          'the two sessions must land on the SAME family member, or the '
          'finding is structurally impossible and this test proves nothing',
    );
    final ScheduleRange month = ScheduleRange.month(DateTime(2026, 6, 15));

    // ── 1. Owner A resolves the range — one real fetch, then keepAlive-pinned.
    final AuthSession sessionA = await container.read(authProvider.future);
    expect(
      sessionA,
      const AuthSession.authenticated(user: _ownerA, accessToken: 'access-a'),
    );

    final List<ScheduleOverride> pageA = await container.read(
      overridesProvider(scope, month).future,
    );
    expect(pageA.single.kind, OverrideKind.dayOff);
    expect(fetches, 1);

    // ── 2. Same session, same key — served from the pin. Load-bearing: it
    // proves the cache is REAL, so step 4 cannot be explained away by the
    // member never having been cached at all (the vacuous-negative trap).
    await container.read(overridesProvider(scope, month).future);
    expect(
      fetches,
      1,
      reason:
          'the keepAlive pin genuinely serves the same key from memory — '
          'without this the next assertion would prove nothing',
    );

    // ── 3. Owner A signs out; owner B signs in, well inside the 5-minute TTL.
    await container.read(authProvider.notifier).logout();
    meUser = _ownerB;
    await container.read(authProvider.notifier).login(_ownerB.email, 'pw-b');
    expect(
      container.read(authProvider).value,
      const AuthSession.authenticated(user: _ownerB, accessToken: 'access-b'),
      reason: 'owner B is genuinely signed in before the second read',
    );

    // ── 4. Owner B's read of the SAME key must go to the network.
    final List<ScheduleOverride> pageB = await container.read(
      overridesProvider(scope, month).future,
    );
    expect(
      fetches,
      2,
      reason:
          'the session boundary must EVICT overridesProvider — serving owner '
          "B from owner A's pin hands over a roster master's per-date "
          'absences with no wire call and no server re-check',
    );
    expect(
      pageB,
      isEmpty,
      reason:
          "owner B must observe owner B's OWN override rows, never owner A's "
          'keepAlive-cached page',
    );
  });

  test(
    'a logout resets overridesRevisionProvider to its never-bumped initial '
    "state — the incoming session cannot inherit the outgoing one's last "
    'written range (mobile-security MEDIUM regression guard, 2026-09-17)',
    () async {
      final authRepo = _MockAuthRepository();
      final storage = FakeSecureStorage();
      await storage.writeRefreshToken(_tokensA.refreshToken);

      when(
        () => authRepo.refresh(_tokensA.refreshToken),
      ).thenAnswer((_) async => _tokensA);
      when(() => authRepo.me()).thenAnswer((_) async => _ownerA);
      when(() => authRepo.logout()).thenAnswer((_) async {});

      final container = ProviderContainer(
        retry: beauticaProviderRetry,
        overrides: [
          authRepositoryProvider.overrideWith((_) => authRepo),
          secureStorageProvider.overrideWith((_) => storage),
        ],
      );
      addTearDown(container.dispose);

      const ScheduleScope scope = ScheduleScope.salonMaster(
        salonId: _salonId,
        masterId: 'master-1',
      );
      final ScheduleRange month = ScheduleRange.month(DateTime(2026, 6, 15));

      await container.read(authProvider.future);

      // A live listener, deliberately — unlike the two tests above. This is a
      // plain `Notifier` with no `ref.keepAlive()` of its own, so an unwatched
      // member would be disposed by ordinary autoDispose and a fresh read would
      // hand back the initial state for a reason that has nothing to do with
      // the sweep under test. Holding the subscription keeps the SAME element
      // alive across the boundary, so the assertion can only move if the
      // invalidate actually fired.
      final sub = container.listen(
        overridesRevisionProvider(scope),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);

      container.read(overridesRevisionProvider(scope).notifier).bump(month);
      expect(
        container.read(overridesRevisionProvider(scope)).writtenRange,
        month,
        reason: 'the counter genuinely carries the outgoing session\'s write',
      );

      await container.read(authProvider.notifier).logout();

      expect(
        container.read(overridesRevisionProvider(scope)).writtenRange,
        isNull,
        reason:
            'the session boundary must reset the revision counter — a stale '
            "writtenRange drives EffectiveScheduleNotifier's cross-range "
            'recompute-or-skip short-circuit and can suppress the incoming '
            "session's first fetch",
      );
    },
  );

  // ---------------------------------------------------------------------------
  // THE INVALIDATE ORDER INSIDE logout() — cycle-2 finding B3
  // ---------------------------------------------------------------------------
  //
  // `auth_notifier.dart:1314` carries a comment asserting that
  // `ref.invalidate(overridesProvider)` MUST run BEFORE
  // `invalidateAllEffectiveScheduleWindows(ref)`. The dependency is real by
  // inspection — `EffectiveScheduleNotifier.build:323-324` `await`s
  // `ref.watch(overridesProvider(scope, range).future)` as its GATING
  // dependency, and `invalidateAllEffectiveScheduleWindows:206-207` does a
  // `wasPinned`-gated EAGER `ref.read` that forces that build to start
  // immediately — but until this test, REVERSING the two lines broke nothing:
  // `test/features/schedule/` 522, `test/features/auth/` 572 and `test/core/`
  // 699 all stayed green.
  //
  // Why none of them moved, so nobody re-derives it:
  //   • The two salon tests above never read `effectiveScheduleProvider` at
  //     all, so `EffectiveScheduleRangeTracker` is EMPTY and the sweep is a
  //     no-op there — the order of a no-op cannot matter.
  //   • `effective_schedule_cross_session_isolation_test.dart:326` does hold a
  //     live listener across the boundary, but on `ScheduleScope.own` with
  //     DIFFERENT masterIds per session (`:167-168`), so the two sessions key
  //     different family members and never collide.
  //   • `provider_cycle_guard_test.dart:469,491` exercises the eager re-read
  //     but asserts only "no CircularDependencyError, settles Unauthenticated"
  //     — true under either order.
  //
  // So this test supplies the one shape that discriminates: a COLLIDING
  // `ScheduleScope.salonMaster` key AND a live `effectiveScheduleProvider`
  // listener held across the boundary.
  //
  // WHAT IT ASSERTS, and why it is an ordering assertion rather than a data
  // one. Under EITHER order the window ends up correct eventually — the
  // bare `ref.invalidate(overridesProvider)` still fires, and a live listener
  // still drives one more rebuild afterwards. What the order decides is
  // whether the FIRST post-logout resolution derives from the outgoing
  // session's still-pinned override rows. So the fake records, for every
  // `effectiveSchedule` call, how many `listOverrides` calls had completed
  // when it ran:
  //   • correct order → [1, 2]: session A's window saw A's rows; the first
  //     resolution after the boundary already saw B's freshly fetched rows.
  //   • reversed      → [1, 1, …]: the eager `ref.read` re-derived the whole
  //     window off A's pinned rows with NO wire call, exactly the "stopped one
  //     hop short" shape the ADDENDUM above describes, before the overrides
  //     sweep landed.
  //
  // MUTATION-VERIFIED (2026-09-17): moving `ref.invalidate(overridesProvider)`
  // + `ref.invalidate(overridesRevisionProvider)` BELOW
  // `invalidateAllEffectiveScheduleWindows(ref)` in `auth_notifier.dart` turns
  // this RED (`[1, 1, 2]`); restoring the order turns it GREEN.
  test('the effective-schedule window a logout re-derives NEVER resolves '
      "against the outgoing session's still-pinned override rows — pins the "
      'invalidate ORDER inside logout(), not just the set of families it '
      'sweeps (cycle-2 finding B3, 2026-09-17)', () async {
    final authRepo = _MockAuthRepository();
    final scheduleRepo = _MockScheduleRepository();
    final storage = FakeSecureStorage();
    await storage.writeRefreshToken(_tokensA.refreshToken);

    when(
      () => authRepo.refresh(_tokensA.refreshToken),
    ).thenAnswer((_) async => _tokensA);
    var meUser = _ownerA;
    when(() => authRepo.me()).thenAnswer((_) async => meUser);
    when(() => authRepo.logout()).thenAnswer((_) async {});
    when(
      () => authRepo.login(email: _ownerB.email, password: 'pw-b'),
    ).thenAnswer((_) async => (_ownerB, _tokensB));

    // Manual counters, not `verify(...).called(n)` — mocktail's `verify`
    // CONSUMES the interactions it matches (the tests above say so at length).
    var overridesFetches = 0;
    when(() => scheduleRepo.listOverrides(any(), any())).thenAnswer((_) async {
      overridesFetches++;
      return overridesFetches == 1
          ? <ScheduleOverride>[
              ScheduleOverride.dayOff(
                start: DateTime(2026, 6, 15),
                end: DateTime(2026, 6, 15),
              ),
            ]
          : const <ScheduleOverride>[];
    });

    // THE ORACLE. Each entry is the number of COMPLETED `listOverrides` calls
    // at the moment an `effectiveSchedule` fetch began — i.e. which session's
    // override rows that window was resolving against.
    final List<int> overridesSeenByEffectiveFetch = <int>[];
    when(() => scheduleRepo.effectiveSchedule(any(), any())).thenAnswer((
      _,
    ) async {
      overridesSeenByEffectiveFetch.add(overridesFetches);
      return <EffectiveDay>[
        overridesSeenByEffectiveFetch.length == 1 ? _day(9, 18) : _day(11, 20),
      ];
    });

    final container = ProviderContainer(
      retry: beauticaProviderRetry,
      overrides: [
        authRepositoryProvider.overrideWith((_) => authRepo),
        secureStorageProvider.overrideWith((_) => storage),
        scheduleRepositoryProvider.overrideWith((ref, scope) => scheduleRepo),
      ],
    );
    addTearDown(container.dispose);

    // THE COLLIDING KEY — byte-identical for owner A and owner B, because
    // neither component carries the authenticated identity. `ScheduleScope
    // .own` would re-key on its own and the ordering would be unobservable.
    const ScheduleScope scope = ScheduleScope.salonMaster(
      salonId: _salonId,
      masterId: 'master-1',
    );
    final ScheduleRange month = ScheduleRange.month(DateTime(2026, 6, 15));

    await container.read(authProvider.future);

    // A LIVE listener held across the boundary — load-bearing twice over. It
    // keeps `ref.exists(effectiveScheduleProvider(...))` true, which is the
    // `wasPinned` gate that makes `invalidateAllEffectiveScheduleWindows` do
    // its EAGER `ref.read` at all; without it the sweep degenerates to a bare
    // invalidate whose rebuild is deferred until someone reads it, by which
    // time the overrides sweep has landed under either order and the test
    // proves nothing.
    final sub = container.listen(
      effectiveScheduleProvider(scope, month),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(sub.close);

    // ── 1. Owner A resolves the window — one overrides fetch, one effective
    // fetch, both keepAlive-pinned for 5 minutes.
    final List<EffectiveDay> pageA = await container.read(
      effectiveScheduleProvider(scope, month).future,
    );
    expect(pageA.single.intervals.single.start.hour, 9);
    expect(overridesFetches, 1);
    expect(overridesSeenByEffectiveFetch, <int>[1]);

    // ── 2. Same session, same key — served from the pins, no extra calls.
    // Load-bearing: proves both caches are REAL, so step 4 cannot be explained
    // away by the members never having been cached (the vacuous-negative
    // trap).
    await container.read(effectiveScheduleProvider(scope, month).future);
    expect(overridesFetches, 1);
    expect(overridesSeenByEffectiveFetch, <int>[1]);

    // ── 3. The REAL `logout()`, with the window still watched. Everything the
    // ordering decides happens inside this one call.
    await container.read(authProvider.notifier).logout();
    meUser = _ownerB;
    await container.read(authProvider.notifier).login(_ownerB.email, 'pw-b');
    expect(
      container.read(authProvider).value,
      const AuthSession.authenticated(user: _ownerB, accessToken: 'access-b'),
    );

    // ── 4. Let the eagerly-restarted window settle, then read the oracle.
    final List<EffectiveDay> pageB = await container.read(
      effectiveScheduleProvider(scope, month).future,
    );

    expect(
      overridesSeenByEffectiveFetch,
      <int>[1, 2],
      reason:
          'the FIRST effective-schedule resolution after the boundary must '
          "already be reading owner B's freshly fetched override rows. A "
          'leading `1` on the second entry means the eager `ref.read` in '
          '`invalidateAllEffectiveScheduleWindows` re-derived the whole window '
          "from owner A's still-pinned rows — the exact 'stopped one hop "
          "short' shape the sweep order exists to prevent.",
    );
    expect(
      overridesFetches,
      2,
      reason:
          'exactly one fresh overrides fetch for owner B — more would mean '
          'the window churned through several resolutions, which is the '
          'reversed-order signature',
    );
    expect(
      pageB.single.intervals.single.start.hour,
      11,
      reason: "owner B observes owner B's own hours, never owner A's",
    );
  });
}
