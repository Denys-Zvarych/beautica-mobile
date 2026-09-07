// mobile-security LOW follow-up (2026-08-12) — `effective_schedule_notifier.
// dart` and `overrides_notifier.dart` both pin themselves with
// `ref.keepAlive()` for 5 minutes and carry hand-rolled instance cache fields
// (`_lastDays` / `_lastOverridesSeen`). This exact shape — `keepAlive` + a
// hand-rolled cache field on a Notifier — produced a real HIGH finding on
// 2026-07-19 for `BookingsDayNotifier`/`dayKeepAliveLruProvider` (see
// `bookings_day_notifier_test.dart`'s "session-boundary PII" group, which
// this test mirrors). No test previously proved the schedule pair's
// analogous claim: that a session flip forces a fresh fetch rather than
// serving the outgoing master's cached page to the next account.
//
// The chain under test (none of it modified by this test, all pre-existing):
//   `scheduleRepositoryProvider` → `ref.watch(masterProfileProvider).value`
//   `masterProfileProvider`      → `ref.watch(authProvider)`, throws
//                                   UnauthorizedFailure while unauthenticated
//   `OverridesNotifier.build`    → `ref.watch(scheduleRepositoryProvider)`
//                                   (unconditional — no `.select`)
//   `EffectiveScheduleNotifier.build` → awaits
//                                   `overridesProvider(range).future` FIRST,
//                                   before its own short-circuit (see that
//                                   file's `_lastOverridesSeen` doc)
//
// SCENARIO (matches the finding's exact ask):
//   1. Master A resolves `effectiveScheduleProvider(range)` — one real fetch,
//      keepAlive-pinned.
//   2. A benign, UNRELATED-range override write bumps
//      `overridesRevisionProvider` (mirrors
//      `effective_schedule_stale_build_race_test.dart` /
//      `effective_schedule_cross_range_revision_test.dart`). This forces the
//      short-circuit to actually be REACHABLE for the rest of the test —
//      without a prior bump, `writtenRange` stays `null` forever and the
//      short-circuit's `revisionOverlapsRange` term is permanently `true`,
//      so it could never fire and the mutation below would be silently inert
//      (an M14 vacuous-negative-assertion trap). This step proves the
//      short-circuit DOES serve the cache in the ordinary (same-session)
//      case: no second `getEffectiveSchedule` call.
//   3. Master A logs out; master B logs in — SAME `range` object, well
//      within the 5-minute TTL.
//   4. Master B's read of `effectiveScheduleProvider(range)` (and
//      `overridesProvider(range)`) must be master B's OWN data, fetched
//      fresh over the network — never master A's cached page.
//
// A SINGLE `container.listen` subscription is held open for the WHOLE test
// (never closed until `addTearDown`) — this is load-bearing, not stylistic.
// Discovered while mutation-probing: `ref.keepAlive()` (the instance's OWN
// 5-minute pin) is only called on the REAL-FETCH path, never on the
// short-circuit's early return (`effective_schedule_notifier.dart`
// line ~190) — a "cache hit" build does not re-arm it. So a test that
// closes its listener between steps (an earlier revision of this test did)
// can let the notifier instance be disposed and silently RECREATED the
// moment nothing watches it, which wipes `_lastDays`/`_lastOverridesSeen` by
// accident and "passes" for the wrong reason — the same trap M14 warns
// about. Holding one live listener open (mirrors
// `bookings_day_notifier_test.dart`'s "actively watched" case — see its own
// comment on why the other session-boundary tests in that file can't
// exercise this) keeps the instance alive throughout, so the assertions
// below are actually exercising `overridesChanged`/`revisionOverlapsRange`,
// not incidental disposal.
//
// Phase 312 ADDENDUM — `effectiveScheduleProvider`/`overridesProvider` gained
// a `ScheduleScope` FAMILY PARAMETER, resolved via `ownScheduleScopeProvider`
// (which still reactively watches `masterProfileProvider`/`authProvider`,
// unchanged) rather than being read reactively FROM INSIDE the notifier. That
// means master A's and master B's reads below now key DIFFERENT family
// instances (different `scope.masterId`) rather than the SAME instance
// re-resolving a swapped `scheduleRepositoryProvider` — session isolation is
// now ALSO structurally guaranteed by the family key, on top of the
// hand-rolled cache-field behaviour this test originally probed alone. The
// test is kept (mechanically adapted, `scope` re-read via
// `ownScheduleScopeProvider` after each auth transition) as an end-to-end
// regression pin over the REAL auth→masterProfile→scope chain plus per-master
// data correctness — not because the original single-instance leak is still
// reachable the same way.
//
// Mutation-verified (see the QA report for the transcript): dropping the
// `!overridesChanged` requirement from `EffectiveScheduleNotifier.build`'s
// short-circuit condition (line ~190) turns this RED — master B observes
// master A's cached `template` page instead of B's own `overrideDayOff`
// page; restoring it turns it GREEN. The FIRST attempt at this mutation (on
// a since-discarded close-per-step version of this test) did NOT go red —
// that false negative is what surfaced the disposal gap above.

import 'package:beautica_api/beautica_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/core/network/api_client_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_scope.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/features/schedule/presentation/effective_schedule_notifier.dart';
import 'package:beautica_mobile/features/schedule/presentation/overrides_notifier.dart';
import 'package:beautica_mobile/features/schedule/presentation/overrides_revision_provider.dart';
import 'package:beautica_mobile/features/schedule/presentation/schedule_range.dart';

class _MockMasterControllerApi extends Mock implements MasterControllerApi {}

class _MockMasterRepository extends Mock implements MasterRepository {}

// ---------------------------------------------------------------------------
// Mutable auth notifier — mirrors bookings_day_notifier_test.dart's
// `_MutableAuthNotifier` / auth_notifier_test.dart's session-boundary stubs:
// lets this test flip the settled session AFTER build(), exactly like
// `AuthNotifier.logout()` / a fresh login do in production.
// ---------------------------------------------------------------------------

class _MutableAuthNotifier extends AuthNotifier {
  _MutableAuthNotifier(this._initial);

  final AuthSession _initial;

  @override
  Future<AuthSession> build() async => _initial;

  void setSession(AuthSession session) =>
      state = AsyncData<AuthSession>(session);
}

const User _masterAUser = User(
  id: 'user-a',
  email: 'master-a@beautica.ua',
  role: UserRole.independentMaster,
  firstName: 'Оля',
  lastName: 'Коваль',
);

const User _masterBUser = User(
  id: 'user-b',
  email: 'master-b@beautica.ua',
  role: UserRole.independentMaster,
  firstName: 'Ірина',
  lastName: 'Бондар',
);

const Master _masterAProfile = Master(
  id: 'master-a-id',
  firstName: 'Оля',
  lastName: 'Коваль',
  avgRating: 0,
  reviewCount: 0,
  type: MasterType.independentMaster,
);

const Master _masterBProfile = Master(
  id: 'master-b-id',
  firstName: 'Ірина',
  lastName: 'Бондар',
  avgRating: 0,
  reviewCount: 0,
  type: MasterType.independentMaster,
);

/// Phase 312 — what `ownScheduleScopeProvider` resolves to for each master,
/// once `masterProfileProvider` settles. The test re-reads the CURRENT
/// scope after each auth transition rather than caching one value, exactly
/// like `ownScheduleScopeProvider` itself does.
const ScheduleScope _scopeA = ScheduleScope.own(masterId: 'master-a-id');
const ScheduleScope _scopeB = ScheduleScope.own(masterId: 'master-b-id');

Response<ApiResponseListEffectiveDayResponse> _effectiveScheduleEnvelope({
  required String masterId,
  required DateTime date,
  required EffectiveDayResponseSource_Enum source,
}) {
  final envelope = ApiResponseListEffectiveDayResponse(
    (b) => b
      ..success = true
      ..data.replace(<EffectiveDayResponse>[
        EffectiveDayResponse(
          (db) => db
            ..date = Date(date.year, date.month, date.day)
            ..source_ = source,
        ),
      ]),
  );
  return Response<ApiResponseListEffectiveDayResponse>(
    data: envelope,
    requestOptions: RequestOptions(
      path: '/api/v1/masters/$masterId/effective-schedule',
    ),
    statusCode: 200,
  );
}

Response<ApiResponseListScheduleOverrideResponse> _overridesEnvelope({
  required String masterId,
  Iterable<ScheduleOverrideResponse> rows = const <ScheduleOverrideResponse>[],
}) {
  final envelope = ApiResponseListScheduleOverrideResponse(
    (b) => b
      ..success = true
      ..data.replace(rows),
  );
  return Response<ApiResponseListScheduleOverrideResponse>(
    data: envelope,
    requestOptions: RequestOptions(path: '/api/v1/masters/$masterId/overrides'),
    statusCode: 200,
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(Date(2026, 1, 1));
  });

  test('a logout followed by a different master logging in forces a FRESH '
      'fetch for the SAME range — master B never observes master A\'s '
      'keepAlive-cached effective schedule (mobile-security LOW regression '
      'guard, 2026-08-12)', () async {
    final masterApi = _MockMasterControllerApi();
    final masterRepo = _MockMasterRepository();

    when(
      () => masterRepo.getMyProfile(_masterAUser.id),
    ).thenAnswer((_) async => _masterAProfile);
    when(
      () => masterRepo.getMyProfile(_masterBUser.id),
    ).thenAnswer((_) async => _masterBProfile);

    final range = ScheduleRange(
      from: DateTime(2026, 7, 20),
      to: DateTime(2026, 7, 20),
    );
    // Disjoint from `range` — used only to make the short-circuit's
    // `revisionOverlapsRange` term reachable (see the header comment).
    final otherRange = ScheduleRange(
      from: DateTime(2026, 9, 1),
      to: DateTime(2026, 9, 1),
    );

    // Manual call counters rather than a second round of mocktail
    // `verify(...).called(n)` calls — mocktail's `verify` CONSUMES the
    // interactions it matches (mirrors mockito), so asserting a call
    // count more than once for the same filter would silently see "no
    // matching calls" on the second assertion regardless of what actually
    // happened. Counting via the stub closures is unambiguous and cannot
    // give a false pass.
    var effFetchCountA = 0;
    var effFetchCountB = 0;
    when(
      () => masterApi.getEffectiveSchedule(
        masterId: 'master-a-id',
        from: any(named: 'from'),
        to: any(named: 'to'),
      ),
    ).thenAnswer((_) async {
      effFetchCountA++;
      return _effectiveScheduleEnvelope(
        masterId: 'master-a-id',
        date: range.from,
        source: EffectiveDayResponseSource_Enum.TEMPLATE,
      );
    });
    when(
      () => masterApi.getEffectiveSchedule(
        masterId: 'master-b-id',
        from: any(named: 'from'),
        to: any(named: 'to'),
      ),
    ).thenAnswer((_) async {
      effFetchCountB++;
      return _effectiveScheduleEnvelope(
        masterId: 'master-b-id',
        date: range.from,
        source: EffectiveDayResponseSource_Enum.OVERRIDE_DAY_OFF,
      );
    });
    when(
      () => masterApi.getOverrides(
        masterId: 'master-a-id',
        from: any(named: 'from'),
        to: any(named: 'to'),
      ),
    ).thenAnswer((_) async => _overridesEnvelope(masterId: 'master-a-id'));
    when(
      () => masterApi.getOverrides(
        masterId: 'master-b-id',
        from: any(named: 'from'),
        to: any(named: 'to'),
      ),
    ).thenAnswer((_) async => _overridesEnvelope(masterId: 'master-b-id'));

    final auth = _MutableAuthNotifier(
      const AuthSession.authenticated(
        user: _masterAUser,
        accessToken: 'token-a',
      ),
    );

    final container = ProviderContainer(
      retry: beauticaProviderRetry,
      overrides: [
        authProvider.overrideWith(() => auth),
        masterApiProvider.overrideWithValue(masterApi),
        masterRepositoryProvider.overrideWithValue(masterRepo),
      ],
    );
    addTearDown(container.dispose);

    // A SINGLE live listener held open for the entire test — deliberately
    // never closed until `addTearDown`, mirroring
    // `bookings_day_notifier_test.dart`'s "actively watched" session-
    // boundary case: "the realistic 'master is looking at the screen when
    // the session ends' scenario ... since both [other tests] always close
    // their listener before touching auth." Closing between steps (an
    // earlier version of this test did) lets the instance be disposed the
    // moment its `ref.keepAlive()` link is unheld between builds — the
    // short-circuit path below does NOT call `ref.keepAlive()` (only the
    // real-fetch path does), so a closed-then-reopened listener can
    // accidentally "pass" by wiping the very cache this test exists to
    // probe, rather than by the session-scoping logic actually working.
    // Holding one subscription open for the whole flow is what makes the
    // hand-rolled `_lastDays`/`_lastOverridesSeen` fields — not incidental
    // disposal — the thing under test.
    final ProviderSubscription<AsyncValue<List<EffectiveDay>>> liveSub =
        container.listen(effectiveScheduleProvider(_scopeA, range), (_, _) {});
    addTearDown(liveSub.close);

    // ── 1. Master A resolves the range — one real fetch, keepAlive-pinned.
    await container.read(authProvider.future);
    await container.read(masterProfileProvider.future);
    final List<EffectiveDay> firstPage = await container.read(
      effectiveScheduleProvider(_scopeA, range).future,
    );

    expect(firstPage.single.source, EffectiveSource.template);
    expect(effFetchCountA, 1);
    expect(effFetchCountB, 0);

    // ── 2. A benign, disjoint-range revision bump — makes the
    // short-circuit reachable (see header comment) and proves it behaves
    // correctly in the ordinary same-session case: still master A, still
    // exactly ONE fetch.
    container
        .read(overridesRevisionProvider(_scopeA).notifier)
        .bump(otherRange);
    final List<EffectiveDay> cachedPage = await container.read(
      effectiveScheduleProvider(_scopeA, range).future,
    );

    expect(
      cachedPage.single.source,
      EffectiveSource.template,
      reason: 'an unrelated-range bump must still serve the cached page',
    );
    expect(
      effFetchCountA,
      1,
      reason: 'no extra network call — the short-circuit fired',
    );

    // ── 3. Master A logs out; master B logs in — SAME `range`, well
    // within the 5-minute keepAlive TTL.
    auth.setSession(const AuthSession.unauthenticated());
    auth.setSession(
      const AuthSession.authenticated(
        user: _masterBUser,
        accessToken: 'token-b',
      ),
    );
    await container.read(masterProfileProvider.future);

    // ── 4. Master B's read of the SAME range must be master B's OWN
    // data, fetched fresh — never master A's cached page.
    final List<ScheduleOverride> overridesForB = await container.read(
      overridesProvider(_scopeB, range).future,
    );
    final List<EffectiveDay> pageForB = await container.read(
      effectiveScheduleProvider(_scopeB, range).future,
    );

    expect(
      overridesForB,
      isEmpty,
      reason: "master B's own (empty) overrides — never master A's list",
    );
    expect(
      pageForB.single.source,
      EffectiveSource.overrideDayOff,
      reason:
          "master B must observe master B's OWN effective schedule — "
          "never master A's keepAlive-cached page",
    );
    expect(
      effFetchCountB,
      1,
      reason: "a genuine fresh fetch for master B's masterId",
    );
    // Master A's masterId is never queried again — the count from step 1
    // stays at exactly 1 for the whole test. If this regresses to 0, the
    // isolation held for the wrong reason (master A was never fetched at
    // all); the step-1 assertion above already pins that at 1.
    expect(effFetchCountA, 1);
  });
}
