// Regression guard for the owner services-list wiring.
//
// History: the original guard (2026-05-31) protected against a masterId UUID
// mismatch bug — serviceRepositoryProvider once extracted masterId from the
// User UUID instead of the Master-row UUID, which made the old public
// GET /masters/{masterId}/services endpoint always return [].
//
// Phase 16.9 repointed listMyServices() to the authenticated owner endpoint
// GET /api/v1/independent-masters/me/services (generated getMyServices()),
// which derives the master from the JWT principal and takes NO masterId path
// parameter. The masterId is therefore no longer sent on the wire — but the
// provider still WATCHES masterProfileProvider so the repository is (re)built
// once the profile resolves and so listMyServices() does not fire on an
// unauthenticated session.
//
// This test now verifies two things:
//   1. listMyServices() delegates to the authenticated owner endpoint
//      (getMyServices), NOT the public getMasterServices(masterId: …).
//   2. The provider waits for the master profile to resolve before the call
//      succeeds (the readiness-guard contract).
//
// PHASE 314 additions — the `ServiceTarget` retarget seam (D2):
//   3. With NO override, `serviceTargetProvider` is `null` AND the repository
//      the provider builds carries `target: null` — i.e. every shipped call
//      site is byte-identical to its pre-phase-314 behaviour. Without this row
//      the DEFAULT is untested and a later edit can flip it silently.
//   4. With a root `ProviderScope` override, the repository carries that exact
//      salon/master pair.
//   5. SCOPE CONTAINMENT — a `serviceTargetProvider` override installed in a
//      NESTED `ProviderScope` is LIVE inside that subtree and is NOT visible
//      from the OUTER scope. This is the D2 claim that the seam cannot leak
//      past the subtree (an imperative setter would leave the app pointed at a
//      stranger's menu after the owner navigates away).
//   6. PHASE 317 BLOCKER — that same nested override does NOT yet reach
//      `serviceRepositoryProvider`, because that provider does not declare
//      `dependencies: [serviceTarget]`. Riverpod 3 only re-creates a provider
//      in a child scope when that provider — and every provider that watches
//      it, transitively — declares the scoped dependency; without it the read
//      resolves against the ROOT container and returns `target: null`.
//
//      (5) and (6) are two SEPARATE cases on purpose. Written as one case they
//      asserted `innerTarget == null` AND `outerTarget == null`, which cannot
//      distinguish "the seam does not leak" from "the seam never fired at
//      all" — both hold when the override is silently inert. Split, each fails
//      for exactly one reason: (5) goes red on a LEAK, (6) goes red the day
//      phase 317 wires the dependency (which is the signal 317 wants).
//   7. REBUILD IDENTITY — an equal-valued but distinct `SalonMasterTarget`
//      must NOT hand back a new repository. `serviceRepositoryProvider` is
//      `keepAlive: true` and riverpod gates dependent rebuilds on `!=`
//      (`riverpod-3.1.0/.../provider.dart:349`;
//      `override_with_value.dart:78`), so a `ServiceTarget` without `==`
//      churns the repository on every scope rebuild. Green since the phase 314
//      audit pass made `ServiceTarget` `@freezed`.
//   8. SALON MODE + UNAUTHENTICATED SESSION — a `SalonMasterTarget` whose two
//      ids are merely non-empty must NOT satisfy the readiness guard on its
//      own. Green since the same pass gave `HttpServiceRepository` a
//      `sessionUserId` (fed from `authProvider.select(authUserIdOrNull)`) that
//      the salon arm requires to be non-empty.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/dio_provider.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/service_target.dart';
import 'package:built_collection/built_collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

// ── Mocks ──────────────────────────────────────────────────────────────────

class _MockServiceControllerApi extends Mock implements ServiceControllerApi {}

class _MockDio extends Mock implements Dio {}

// ── Stub notifier ───────────────────────────────────────────────────────────

/// Returns a master whose `.id` field is the master-row UUID ('master-row-uuid').
/// The owner endpoint no longer sends this on the wire, but a non-empty value
/// is still required to pass the repository's readiness guard.
class _StubMasterProfileNotifier extends MasterProfile {
  static const _master = Master(
    id: 'master-row-uuid',
    firstName: 'T',
    lastName: 'T',
    avgRating: 0,
    reviewCount: 0,
    type: MasterType.independentMaster,
  );

  @override
  Future<Master> build() async => _master;
}

/// The NO-SESSION counterpart: `masterProfileProvider` never resolves, so
/// `serviceRepositoryProvider`'s `.value?.id ?? ''` yields `''`.
///
/// `UnauthorizedFailure` is deliberately not transient under
/// `beauticaProviderRetry`, so this fails on attempt 1 rather than burning the
/// ~38 s / 10-attempt curve (`project_asyncvalue_haserror_retrying_trap`).
class _UnauthenticatedMasterProfileNotifier extends MasterProfile {
  @override
  Future<Master> build() async => throw const UnauthorizedFailure();
}

// ── Tests ───────────────────────────────────────────────────────────────────

void main() {
  late _MockServiceControllerApi mockApi;
  late _MockDio mockDio;

  setUp(() {
    mockApi = _MockServiceControllerApi();
    mockDio = _MockDio();

    // Stub the authenticated owner endpoint to return an empty list.
    when(() => mockApi.getMyServices()).thenAnswer(
      (_) async => Response(
        data:
            (ApiResponseListMasterServiceResponseBuilder()
                  ..success = true
                  ..data = ListBuilder<MasterServiceResponse>())
                .build(),
        statusCode: 200,
        requestOptions: RequestOptions(
          path: '/api/v1/independent-masters/me/services',
        ),
      ),
    );
  });

  test(
    'serviceRepositoryProvider.listMyServices delegates to the authenticated '
    'owner endpoint (getMyServices), never the public getMasterServices',
    () async {
      final container = ProviderContainer(
        retry: beauticaProviderRetry,
        overrides: [
          masterProfileProvider.overrideWith(
            () => _StubMasterProfileNotifier(),
          ),
          serviceApiProvider.overrideWithValue(mockApi),
          dioProvider.overrideWithValue(mockDio),
        ],
      );
      addTearDown(container.dispose);

      // Wait for masterProfileProvider to resolve so serviceRepositoryProvider
      // passes its readiness guard before we call listMyServices.
      await container.read(masterProfileProvider.future);

      // listMyServices() delegates to the JWT-derived owner endpoint.
      await container.read(serviceRepositoryProvider).listMyServices();

      // The owner endpoint (drafts included) must have been called exactly once.
      verify(() => mockApi.getMyServices()).called(1);

      // The public, draft-excluding endpoint must NOT be used for the owner's
      // own list (guards against a regression back to the public path).
      verifyNever(
        () => mockApi.getMasterServices(masterId: any(named: 'masterId')),
      );
    },
  );

  // ── Phase 314 — the ServiceTarget retarget seam (D2) ──────────────────────

  group('serviceTargetProvider seam', () {
    /// The root-scope overrides every case below needs: the master profile
    /// stub (so the readiness guard passes) plus the mocked API + Dio.
    /// Deliberately does NOT touch `serviceTargetProvider` — each case decides
    /// for itself whether, and at which depth, to override it.
    // Return type deliberately inferred: riverpod 3.1.0 does not export the
    // `Override` type publicly, so it cannot be written out here.
    baseOverrides() => [
      masterProfileProvider.overrideWith(() => _StubMasterProfileNotifier()),
      serviceApiProvider.overrideWithValue(mockApi),
      dioProvider.overrideWithValue(mockDio),
    ];

    /// Reads `serviceRepositoryProvider` through [ref] and returns the
    /// [ServiceTarget] the provider threaded into it.
    ///
    /// ⚠️ THIS IS A FIELD READ, NOT AN OBSERVED EFFECT
    /// (`project_widget_field_assertion_is_vacuous`). It is acceptable in
    /// phase 314 for exactly one reason, and only while that reason holds:
    /// D3 says the `target` field is STORED AND DISPATCHED NOWHERE — the only
    /// consumer is `_assertAuthenticated`. There is, by design, no request path
    /// to observe yet, so a field read is the only thing there is to assert.
    ///
    /// PHASE 315 MUST CONVERT THIS to a PATH OBSERVATION — assert the URL the
    /// mocked Dio / generated client actually receives for a salon target,
    /// not the value of `HttpServiceRepository.target`. The moment 315 adds
    /// path dispatch, a field-read assertion goes green while dispatch is
    /// broken, which is the precise failure mode this repo has been bitten by
    /// before. It is an explicit acceptance criterion of
    /// `docs/mobile-phases/phase-315-service-repository-salon-target-reads.md`:
    /// a field-read `targetOf` surviving into 315 is a FAIL.
    ServiceTarget? targetOf(WidgetRef ref) =>
        (ref.read(serviceRepositoryProvider) as HttpServiceRepository).target;

    test(
      'with NO override the seam is null and the repository is built exactly '
      'as it was before phase 314 (target: null)',
      () async {
        final container = ProviderContainer(
          retry: beauticaProviderRetry,
          overrides: baseOverrides(),
        );
        addTearDown(container.dispose);

        await container.read(masterProfileProvider.future);

        // The seam itself defaults to null …
        expect(
          container.read(serviceTargetProvider),
          isNull,
          reason:
              'serviceTargetProvider must default to null — "me, the '
              'independent master" — which is what every shipped call site '
              'means today.',
        );

        // … and the repository the provider builds carries that null through.
        final repo =
            container.read(serviceRepositoryProvider) as HttpServiceRepository;
        expect(
          repo.target,
          isNull,
          reason:
              'A repository built with no override must be observationally '
              'identical to the pre-phase-314 one.',
        );
      },
    );

    // NOTE — a ROOT override is a TEST FIXTURE ONLY. A unit test's
    // `ProviderContainer` IS the root and is disposed in `addTearDown`, so the
    // override is bounded by the test. Production code must never install one:
    // it is process-lifetime, survives logout, and would retain a cross-tenant
    // target — see `serviceRepositoryProvider`'s PHASE 317 BLOCKER doc.
    test(
      'with a root override the repository carries that exact salon/master pair',
      () async {
        const target = SalonMasterTarget(
          salonId: 'salon-row-uuid',
          masterId: 'master-row-uuid-of-the-staff-member',
        );

        final container = ProviderContainer(
          retry: beauticaProviderRetry,
          overrides: [
            ...baseOverrides(),
            serviceTargetProvider.overrideWithValue(target),
          ],
        );
        addTearDown(container.dispose);

        await container.read(masterProfileProvider.future);

        final repo =
            container.read(serviceRepositoryProvider) as HttpServiceRepository;
        final threaded = repo.target;

        expect(threaded, isA<SalonMasterTarget>());
        expect((threaded! as SalonMasterTarget).salonId, 'salon-row-uuid');
        expect(
          (threaded as SalonMasterTarget).masterId,
          'master-row-uuid-of-the-staff-member',
          reason:
              'masterId is the `masters` ROW id, never a userId — a userId on '
              '/salons/{s}/masters/{m}/... yields 404, not 403.',
        );
      },
    );

    /// Reads `serviceTargetProvider` itself — the seam value, BEFORE the
    /// repository has had a chance to swallow it. Case 5's anti-vacuity half
    /// depends on this: it is what proves the nested override actually fired.
    ServiceTarget? seamOf(WidgetRef ref) => ref.read(serviceTargetProvider);

    /// Pumps the ROOT scope → outer `Consumer` → NESTED scope (the ONLY place
    /// the target is overridden) → inner `Consumer`. This is the exact shape
    /// phase 317 wraps around the salon-target route subtree, and the reason
    /// it unwinds on pop. A single FLAT scope would make both cases below
    /// vacuous, so the nesting is the fixture, not decoration.
    Future<void> pumpNestedScopes(
      WidgetTester tester, {
      required ServiceTarget target,
      required void Function(WidgetRef outerRef) onOuter,
      required void Function(WidgetRef innerRef) onInner,
    }) => tester.pumpWidget(
      ProviderScope(
        // ROOT scope: no serviceTargetProvider override anywhere here.
        overrides: baseOverrides(),
        child: Consumer(
          builder: (context, outerRef, _) {
            onOuter(outerRef);
            return ProviderScope(
              overrides: [serviceTargetProvider.overrideWithValue(target)],
              child: Consumer(
                builder: (context, innerRef, _) {
                  onInner(innerRef);
                  return const SizedBox.shrink();
                },
              ),
            );
          },
        ),
      ),
    );

    testWidgets(
      'SCOPE CONTAINMENT — the nested override is LIVE inside the subtree and '
      'invisible from the outer scope',
      (tester) async {
        const target = SalonMasterTarget(
          salonId: 'salon-row-uuid',
          masterId: 'master-row-uuid-of-the-staff-member',
        );

        ServiceTarget? innerSeam;
        ServiceTarget? outerSeam;
        ServiceTarget? outerRepoTarget;

        await pumpNestedScopes(
          tester,
          target: target,
          onOuter: (outerRef) {
            outerSeam = seamOf(outerRef);
            outerRepoTarget = targetOf(outerRef);
          },
          onInner: (innerRef) => innerSeam = seamOf(innerRef),
        );

        // ANTI-VACUITY HALF. Without this the two null assertions below hold
        // just as well when the override is silently inert, and the case
        // proves nothing (`project_widget_field_assertion_is_vacuous`, M14).
        expect(
          innerSeam,
          isA<SalonMasterTarget>(),
          reason:
              'the nested override must actually FIRE — if it does not, the '
              'null assertions below are satisfied by an inert seam rather '
              'than by containment',
        );

        // CONTAINMENT HALF. With the line above pinned, each of these can now
        // fail for exactly ONE reason: the seam leaked out of the subtree.
        expect(
          outerSeam,
          isNull,
          reason:
              'the seam must NOT leak past the subtree. An imperative setter '
              'would leave the app pointed at a master after the owner '
              "navigates away — someone reopens /services and sees a "
              "stranger's menu.",
        );
        expect(
          outerRepoTarget,
          isNull,
          reason:
              'and the repository the OUTER scope hands out stays the '
              "independent master's, untouched",
        );
      },
    );

    testWidgets(
      'PHASE 317 BLOCKER — the nested override reaches serviceTargetProvider '
      'but NOT serviceRepositoryProvider',
      (tester) async {
        const target = SalonMasterTarget(
          salonId: 'salon-row-uuid',
          masterId: 'master-row-uuid-of-the-staff-member',
        );

        ServiceTarget? innerSeam;
        ServiceTarget? innerRepoTarget;

        await pumpNestedScopes(
          tester,
          target: target,
          onOuter: (_) {},
          onInner: (innerRef) {
            innerSeam = seamOf(innerRef);
            innerRepoTarget = targetOf(innerRef);
          },
        );

        expect(
          innerSeam,
          isA<SalonMasterTarget>(),
          reason: 'the seam itself IS scoped — it is overridden right here',
        );

        // ⚠️ PHASE 317 MUST FLIP THIS EXPECTATION.
        // `serviceRepositoryProvider` does not declare
        // `dependencies: [serviceTarget]`, so riverpod resolves it against the
        // ROOT container and it reads the root's null target. Phase 314 cannot
        // add that declaration — it cascades onto every dependent
        // (`servicesListProvider`, `serviceByIdProvider`, …), all of which live
        // under `presentation/`, out of this phase's scope, and 68 existing
        // tests go red without it. This case pins the CURRENT truth so 317
        // cannot ship a silently inert scope: 317 either adds `dependencies:`
        // down the whole chain or overrides `serviceRepositoryProvider` itself
        // inside the salon scope, and flips this to `isA<SalonMasterTarget>()`
        // in the same commit.
        //
        // Note the division of labour with the case above: THIS case is the
        // one 317 turns red on purpose. The containment case is the one that
        // must stay green forever — 317 rewiring the dependency must not start
        // leaking the target into the outer scope.
        expect(
          innerRepoTarget,
          isNull,
          reason:
              'Nested serviceTargetProvider overrides do not reach '
              "serviceRepositoryProvider yet — see that provider's "
              'PHASE 317 BLOCKER doc comment. Flip this in phase 317.',
        );
      },
    );

    // ── REBUILD IDENTITY (perf HIGH — ServiceTarget has no ==/hashCode) ─────
    //
    // `serviceRepositoryProvider` is `keepAlive: true` and read from a dozen
    // call sites. Riverpod rebuilds a dependent only when the watched value
    // reports `!=` (`riverpod-3.1.0/lib/src/providers/provider.dart:349`; the
    // `overrideWithValue` path funnels through the same comparison at
    // `core/override_with_value.dart:78`). `SalonMasterTarget` has identity
    // equality, so a `ProviderScope` that rebuilds and hands down a FRESH
    // instance carrying the SAME two ids tears down and re-creates the
    // repository for no semantic change — and, once phase 317 is live, that is
    // exactly what a route-subtree scope does on every rebuild.
    //
    // Two cases, deliberately paired:
    //   • the equal-valued one is the guard (red the moment `ServiceTarget`
    //     loses its `==`/`hashCode`);
    //   • the different-target one is its anti-vacuity control — it proves the
    //     rebuild mechanism this test observes actually fires, so "identical
    //     instance" can never pass because nothing ever rebuilds.
    group('rebuild identity', () {
      /// The base overrides are built ONCE and reused verbatim across both
      /// `updateOverrides` calls. Rebuilding them would hand riverpod fresh
      /// `masterProfileProvider` / api / dio overrides too, which rebuild the
      /// repository on their own and defang the assertion
      /// (`project_fixture_values_can_defang_assertions`).
      Future<(ServiceRepository, ServiceRepository)> repositoryAcross(
        ServiceTarget before,
        ServiceTarget after,
      ) async {
        final base = baseOverrides();
        final container = ProviderContainer(
          retry: beauticaProviderRetry,
          overrides: [...base, serviceTargetProvider.overrideWithValue(before)],
        );
        addTearDown(container.dispose);

        await container.read(masterProfileProvider.future);
        final first = container.read(serviceRepositoryProvider);

        container.updateOverrides([
          ...base,
          serviceTargetProvider.overrideWithValue(after),
        ]);

        return (first, container.read(serviceRepositoryProvider));
      }

      test('a DIFFERENT target rebuilds the repository (control: the mechanism '
          'under observation does fire)', () async {
        final (before, after) = await repositoryAcross(
          const SalonMasterTarget(salonId: 's-1', masterId: 'm-1'),
          const SalonMasterTarget(salonId: 's-2', masterId: 'm-1'),
        );

        expect(
          identical(before, after),
          isFalse,
          reason:
              'retargeting to a different master MUST produce a new '
              'repository — otherwise the equal-valued case below would pass '
              'because nothing ever rebuilds, not because equality works',
        );
      });

      test(
        'an EQUAL-VALUED but distinct target does NOT rebuild the repository',
        () async {
          // Assembled at runtime so the two targets cannot be canonicalised to
          // one instance by the compiler — two separately constructed objects
          // carrying identical ids is the whole scenario.
          final salonId = <String>['salon', 'row', 'uuid'].join('-');
          final masterId = <String>['master', 'row', 'uuid'].join('-');

          final (before, after) = await repositoryAcross(
            SalonMasterTarget(salonId: salonId, masterId: masterId),
            SalonMasterTarget(salonId: salonId, masterId: masterId),
          );

          expect(
            identical(before, after),
            isTrue,
            reason:
                'serviceRepositoryProvider is keepAlive and read from a dozen '
                'places; churning it because two structurally identical '
                'targets are not `==` is the perf HIGH this pins',
          );
        },
      );
    });

    // ── D4 row 5 — salon mode with NO authenticated session ────────────────
    //
    // Deliberately lives HERE, at the provider seam, and NOT as a sixth row of
    // the `_assertAuthenticated` matrix in `service_repository_test.dart`.
    // `HttpServiceRepository` holds no session object — its only session
    // evidence is `_masterId`, and D4 row 3 exists precisely to ALLOW that to
    // be empty in salon mode. So "salon target + unauthenticated" is not
    // expressible as a unit test on the guard; it is only expressible where
    // the target and the session meet, which is `serviceRepositoryProvider`.
    //
    // The case is written mechanism-agnostically on purpose: it asserts the
    // observable outcome (UnauthorizedFailure, no network call), so whichever
    // shape the fix takes — a session predicate threaded into the repository,
    // a guard in the provider, or phase 317 refusing to construct a target off
    // an unauthenticated session — this pins it without being rewritten.
    test('row 5 — a SalonMasterTarget on an UNAUTHENTICATED session throws '
        'UnauthorizedFailure and issues no network call', () async {
      final container = ProviderContainer(
        retry: beauticaProviderRetry,
        overrides: [
          // No session at all. The master profile never resolves AND
          // `authProvider` is left un-overridden, so it stays on its
          // pre-resolution `AsyncLoading` — `authUserIdOrNull` reads `null`
          // and the repository is built with `sessionUserId: ''`.
          masterProfileProvider.overrideWith(
            () => _UnauthenticatedMasterProfileNotifier(),
          ),
          serviceApiProvider.overrideWithValue(mockApi),
          dioProvider.overrideWithValue(mockDio),
          serviceTargetProvider.overrideWithValue(
            // Two arbitrary non-empty strings. Nothing here came from a
            // resolved backend row, and nothing here proves a session — the
            // salon arm must not accept them on their own.
            const SalonMasterTarget(salonId: 'x', masterId: 'y'),
          ),
        ],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(serviceRepositoryProvider).listMyServices(),
        throwsA(isA<UnauthorizedFailure>()),
      );

      verifyNever(() => mockApi.getMyServices());
    });
  });
}
