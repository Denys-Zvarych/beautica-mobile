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
import 'package:beautica_mobile/features/schedule/presentation/salon_effective_schedule_notifier.dart';
import 'package:beautica_mobile/features/schedule/presentation/schedule_range.dart';

import '../../../helpers/fakes/fake_secure_storage.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockSalonRosterScheduleRepository extends Mock
    implements SalonRosterScheduleRepository {}

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
}
