// Phase 23.x rewire — regression tests for `salonMasterServiceCoverageProvider`
// against the dedicated `GET /salons/{salonId}/services/{serviceDefId}/masters`
// endpoint (`SalonRepository.getBookableMasters`).
//
// SUPERSEDES the Phase 14.13 fixture set: the provider no longer fans
// `GET /masters/{id}/services` out over the salon's FULL roster (bounded to 8
// concurrent) and derives coverage by intersecting each master's own service
// list — it calls [SalonRepository.getBookableMasters] ONCE PER SELECTED
// SERVICE instead, letting the backend do the active/assigned/schedule-usable
// filtering server-side. See `salon_master_coverage_notifier.dart`'s file
// header for the full rationale.
//
// Covers (this session's regression set):
//   1. Bookable-included — a master [getBookableMasters] returns is present
//      and selectable in the resulting coverage map.
//   2. Scheduleless-excluded (THE bug this rewire fixes) — a master the
//      endpoint simply omits from its response (the server-side stand-in for
//      "active assignment but no usable schedule") never reaches the
//      coverage map, for ANY selected service, even though its sibling
//      master on the SAME service is included.
//   3. Per-service graceful degradation — one selected service's call
//      failing degrades to "no bookable masters for that service" (that
//      service is simply absent from every master's coverage entry) without
//      throwing and without blanking the already-resolved/still-succeeding
//      services' data.
//   4. Multi-service aggregation — a master bookable for 2 of the client's
//      selected services accumulates BOTH `serviceDefId -> masterServiceId`
//      entries in its single coverage-map row, not just the last one
//      resolved.
//   5. Exactly one `getBookableMasters` call per selected service, with the
//      correct (salonId, serviceDefId) arguments — never a roster fan-out.
//   6. Family-key caching — re-reading with a DIFFERENT
//      [SalonBookingMasterSelectionArgs] instance carrying the SAME
//      (salonId, selectedServiceIds) resolves to the same cached family
//      member (freezed value equality) instead of re-fetching.
//   7. keepAlive Timer lifecycle — the 5-minute release [Timer] is cancelled
//      on dispose, mirroring the sibling `salonReviewSummaryProvider` pattern
//      already proven elsewhere in the suite.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/booking/application/salon_master_coverage_notifier.dart';
import 'package:beautica_mobile/features/booking/domain/salon_booking_args.dart';
import 'package:beautica_mobile/features/salon/data/salon_repository.dart';
import 'package:beautica_mobile/features/salon/domain/bookable_master_assignment.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

class _MockSalonRepository extends Mock implements SalonRepository {}

const String _kSalonId = 'salon-1';

/// Stubs [repo.getBookableMasters] so each `serviceDefId` in [bySvc] resolves
/// to its own fixed list (or throws, when the value is a [Failure] instead of
/// a list) — lets a test give DIFFERENT services DIFFERENT outcomes in one
/// `when` registration instead of one `when` per service.
void _stubBySvc(
  _MockSalonRepository repo,
  Map<String, Object> bySvc, // List<BookableMasterAssignment> or Failure
) {
  when(
    () => repo.getBookableMasters(
      salonId: any(named: 'salonId'),
      serviceDefId: any(named: 'serviceDefId'),
    ),
  ).thenAnswer((Invocation invocation) async {
    final String serviceDefId =
        invocation.namedArguments[#serviceDefId] as String;
    final Object? outcome = bySvc[serviceDefId];
    if (outcome is Failure) throw outcome;
    return (outcome as List<BookableMasterAssignment>?) ??
        const <BookableMasterAssignment>[];
  });
}

void main() {
  group('salonMasterServiceCoverageProvider — bookable-master inclusion', () {
    test(
      'a master getBookableMasters returns for a service is present and '
      'selectable in the coverage map, keyed by its OWN masterServiceId',
      () async {
        final repo = _MockSalonRepository();
        _stubBySvc(repo, <String, Object>{
          'svc-1': const <BookableMasterAssignment>[
            (masterId: 'm1', masterServiceId: 'assignment-m1-svc-1'),
          ],
        });

        final container = ProviderContainer(
          retry: beauticaProviderRetry,
          overrides: [salonRepositoryProvider.overrideWithValue(repo)],
        );
        addTearDown(container.dispose);

        const args = SalonBookingMasterSelectionArgs(
          salonId: _kSalonId,
          selectedServiceIds: <String>['svc-1'],
        );
        final Map<String, Map<String, String>> coverage = await container.read(
          salonMasterServiceCoverageProvider(args).future,
        );

        expect(coverage.containsKey('m1'), isTrue);
        expect(coverage['m1'], <String, String>{
          'svc-1': 'assignment-m1-svc-1',
        });
      },
    );

    test('a master bookable for 2 of the selected services accumulates BOTH '
        'entries in its single coverage row', () async {
      final repo = _MockSalonRepository();
      _stubBySvc(repo, <String, Object>{
        'svc-1': const <BookableMasterAssignment>[
          (masterId: 'm1', masterServiceId: 'assignment-m1-svc-1'),
        ],
        'svc-2': const <BookableMasterAssignment>[
          (masterId: 'm1', masterServiceId: 'assignment-m1-svc-2'),
        ],
      });

      final container = ProviderContainer(
        retry: beauticaProviderRetry,
        overrides: [salonRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      const args = SalonBookingMasterSelectionArgs(
        salonId: _kSalonId,
        selectedServiceIds: <String>['svc-1', 'svc-2'],
      );
      final Map<String, Map<String, String>> coverage = await container.read(
        salonMasterServiceCoverageProvider(args).future,
      );

      expect(coverage['m1'], <String, String>{
        'svc-1': 'assignment-m1-svc-1',
        'svc-2': 'assignment-m1-svc-2',
      });
    });
  });

  group('salonMasterServiceCoverageProvider — scheduleless-master exclusion '
      '(the bug this rewire fixes)', () {
    test(
      'a master the endpoint simply omits (server-filtered: active '
      'assignment but no usable schedule) never reaches the coverage map, '
      'even though a sibling master on the SAME service is included',
      () async {
        final repo = _MockSalonRepository();
        // "Роман" has an active assignment on svc-1 in production but no
        // usable weekly schedule — the backend's Phase 23.x filter omits
        // him from the response entirely rather than flagging him as
        // ineligible. Only m1 (schedule-usable) comes back.
        _stubBySvc(repo, <String, Object>{
          'svc-1': const <BookableMasterAssignment>[
            (masterId: 'm1', masterServiceId: 'assignment-m1-svc-1'),
          ],
        });

        final container = ProviderContainer(
          retry: beauticaProviderRetry,
          overrides: [salonRepositoryProvider.overrideWithValue(repo)],
        );
        addTearDown(container.dispose);

        const args = SalonBookingMasterSelectionArgs(
          salonId: _kSalonId,
          selectedServiceIds: <String>['svc-1'],
        );
        final Map<String, Map<String, String>> coverage = await container.read(
          salonMasterServiceCoverageProvider(args).future,
        );

        expect(coverage.containsKey('m1'), isTrue);
        expect(
          coverage.containsKey('roman-scheduleless'),
          isFalse,
          reason:
              'a master absent from getBookableMasters\' response must '
              'never appear in the coverage map — this is the server-side '
              'gate that fixes the calendar-all-dates-disabled bug at the '
              'source; the client has no way to "see" a scheduleless '
              'master because the endpoint never sends him',
        );
        // The map has exactly the one bookable master — not an empty
        // masterId key or any other artifact of the omitted master.
        expect(coverage.keys, <String>['m1']);
      },
    );

    test('omitted from svc-1 but present for svc-2 — the SAME master id can '
        'be eligible for one selected service and excluded from another, '
        'entirely per-service', () async {
      final repo = _MockSalonRepository();
      _stubBySvc(repo, <String, Object>{
        // m2 has a usable schedule for svc-2 but is NOT returned for
        // svc-1 (e.g. an assignment exists but that service's slots
        // never resolve to a bookable day) — omission is per-service,
        // not a blanket master-level flag.
        'svc-1': const <BookableMasterAssignment>[
          (masterId: 'm1', masterServiceId: 'assignment-m1-svc-1'),
        ],
        'svc-2': const <BookableMasterAssignment>[
          (masterId: 'm2', masterServiceId: 'assignment-m2-svc-2'),
        ],
      });

      final container = ProviderContainer(
        retry: beauticaProviderRetry,
        overrides: [salonRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      const args = SalonBookingMasterSelectionArgs(
        salonId: _kSalonId,
        selectedServiceIds: <String>['svc-1', 'svc-2'],
      );
      final Map<String, Map<String, String>> coverage = await container.read(
        salonMasterServiceCoverageProvider(args).future,
      );

      expect(coverage['m1'], <String, String>{'svc-1': 'assignment-m1-svc-1'});
      expect(coverage['m2'], <String, String>{'svc-2': 'assignment-m2-svc-2'});
      expect(
        coverage['m1']!.containsKey('svc-2'),
        isFalse,
        reason: 'm1 was never returned for svc-2 — must not leak in',
      );
      expect(
        coverage['m2']!.containsKey('svc-1'),
        isFalse,
        reason: 'm2 was never returned for svc-1 — must not leak in',
      );
    });
  });

  group(
    'salonMasterServiceCoverageProvider — per-service graceful degradation',
    () {
      test('one selected service\'s getBookableMasters call throwing degrades '
          'to "no bookable masters for that service" — the provider future '
          'still resolves (never rethrows) and the OTHER, succeeding service\'s '
          'coverage is unaffected', () async {
        final repo = _MockSalonRepository();
        _stubBySvc(repo, <String, Object>{
          'svc-1': const NetworkFailure(),
          'svc-2': const <BookableMasterAssignment>[
            (masterId: 'm2', masterServiceId: 'assignment-m2-svc-2'),
          ],
        });

        final container = ProviderContainer(
          retry: beauticaProviderRetry,
          overrides: [salonRepositoryProvider.overrideWithValue(repo)],
        );
        addTearDown(container.dispose);

        const args = SalonBookingMasterSelectionArgs(
          salonId: _kSalonId,
          selectedServiceIds: <String>['svc-1', 'svc-2'],
        );

        // The provider's own Future must resolve normally — a regression
        // back to an unguarded `Future.wait` would instead throw here and
        // fail this `await` with the NetworkFailure, blanking the WHOLE
        // grid instead of just the failed service.
        final Map<String, Map<String, String>> coverage = await container.read(
          salonMasterServiceCoverageProvider(args).future,
        );

        // svc-1 contributed no masters at all — no coverage row carries
        // 'svc-1' as a key.
        for (final Map<String, String> row in coverage.values) {
          expect(row.containsKey('svc-1'), isFalse);
        }
        // svc-2's real result is untouched by svc-1's failure.
        expect(coverage['m2'], <String, String>{
          'svc-2': 'assignment-m2-svc-2',
        });
      });

      test('ALL selected services failing resolves to an empty coverage map, '
          'never a thrown error', () async {
        final repo = _MockSalonRepository();
        _stubBySvc(repo, <String, Object>{
          'svc-1': const NetworkFailure(),
          'svc-2': const ServerFailure(statusCode: 500),
        });

        final container = ProviderContainer(
          retry: beauticaProviderRetry,
          overrides: [salonRepositoryProvider.overrideWithValue(repo)],
        );
        addTearDown(container.dispose);

        const args = SalonBookingMasterSelectionArgs(
          salonId: _kSalonId,
          selectedServiceIds: <String>['svc-1', 'svc-2'],
        );

        final Map<String, Map<String, String>> coverage = await container.read(
          salonMasterServiceCoverageProvider(args).future,
        );

        expect(coverage, isEmpty);
      });

      // CHUNK-BOUNDARY ALIGNMENT UNDER FAILURE (mobile-qa gap-fix — the
      // MEDIUM this file was flagged for).
      //
      // The two degradation tests above both fit in a single fetch chunk, so
      // neither exercises the invariant that actually makes degradation SAFE:
      // `perService[i]` must stay aligned with `selectedServiceIds[i]` even
      // when an earlier entry failed. The provider holds that alignment by
      // returning an EMPTY LIST from its catch — the failed slot keeps its
      // index — and the obvious "tidy-up" edit (dropping empty results while
      // assembling `perService`, or filtering the failures out of
      // `batchResults`) silently shifts every subsequent index by one.
      //
      // That is not a cosmetic misattribution. The map's VALUE is the
      // master-scoped `masterServiceId` that the slot query and ultimately
      // `POST /bookings` are keyed on (see `salon_master_schedule.dart`'s
      // id-space note), so a one-slot shift books the client a DIFFERENT
      // service than the one they picked, with no visible symptom until the
      // appointment. Ten services span two chunks (`_kFetchChunkSize` is 8)
      // with the failure inside the first, so both the shift-within-chunk and
      // the shift-across-the-chunk-boundary cases are pinned at once.
      test('a service failing inside the FIRST chunk keeps every LATER '
          'service — including those past the chunk boundary — attributed to '
          'its OWN serviceDefId and assignment id', () async {
        final repo = _MockSalonRepository();
        final List<String> selected = <String>[
          for (int i = 1; i <= 10; i++) 'svc-$i',
        ];
        _stubBySvc(repo, <String, Object>{
          for (final String svc in selected)
            svc: <BookableMasterAssignment>[
              (masterId: 'm-$svc', masterServiceId: 'assign-$svc'),
            ],
          // Overrides the entry spread above — svc-3 is index 2, well inside
          // the first chunk.
          'svc-3': const NetworkFailure(),
        });

        final container = ProviderContainer(
          retry: beauticaProviderRetry,
          overrides: [salonRepositoryProvider.overrideWithValue(repo)],
        );
        addTearDown(container.dispose);

        final args = SalonBookingMasterSelectionArgs(
          salonId: _kSalonId,
          selectedServiceIds: selected,
        );
        final Map<String, Map<String, String>> coverage = await container.read(
          salonMasterServiceCoverageProvider(args).future,
        );

        for (final String svc in selected) {
          if (svc == 'svc-3') continue;
          expect(
            coverage['m-$svc'],
            <String, String>{svc: 'assign-$svc'},
            reason:
                '$svc must resolve to its OWN master and its OWN assignment '
                'id; anything else means the failed svc-3 slot collapsed and '
                'shifted the tail of the selection',
          );
        }

        // The failed service contributes nothing anywhere — neither its own
        // row, nor (via a collapsed index) some later service\'s row.
        for (final Map<String, String> row in coverage.values) {
          expect(
            row.containsKey('svc-3'),
            isFalse,
            reason: 'svc-3 resolved to no masters at all',
          );
        }
        expect(coverage.containsKey('m-svc-3'), isFalse);
        expect(
          coverage,
          hasLength(9),
          reason: 'exactly the nine succeeding services contributed a master',
        );
      });
    },
  );

  // THE CEILING OF THE DEGRADATION GUARD (mobile-qa gap-fix).
  //
  // The guard above is `on Failure catch` — deliberately narrow — and the
  // repository it wraps only maps `DioException` (`getBookableMasters` in
  // `salon_repository.dart`: `on Failure { rethrow }` / `on DioException {
  // map }`). So an error that is NEITHER — the realistic one being a mapper
  // `TypeError` from a malformed row in an otherwise-200 response — escapes
  // BOTH layers and fails the whole provider, blanking the entire master-
  // selection grid over one bad row on one service.
  //
  // This test does not claim that is the right behaviour; it makes the blast
  // radius VISIBLE, because nothing else in this file states where the
  // degradation stops. If the guard is ever widened to a bare `catch` this
  // test goes red on purpose — that is the point at which the widening should
  // be a considered decision (it also starts swallowing programming errors)
  // rather than a silent side effect.
  group('salonMasterServiceCoverageProvider — degradation ceiling', () {
    test('a NON-Failure error is NOT degraded — it propagates out of the '
        'provider instead of resolving to partial coverage', () async {
      final repo = _MockSalonRepository();
      when(
        () => repo.getBookableMasters(
          salonId: any(named: 'salonId'),
          serviceDefId: any(named: 'serviceDefId'),
        ),
      ).thenAnswer(
        (_) async => throw StateError('malformed BookableMasterAssignment row'),
      );

      final container = ProviderContainer(
        overrides: [salonRepositoryProvider.overrideWithValue(repo)],
        // No auto-retry: the assertion is about the FIRST outcome, and a
        // retry timer would outlive the test.
        retry: (int _, Object _) => null,
      );
      addTearDown(container.dispose);

      const args = SalonBookingMasterSelectionArgs(
        salonId: _kSalonId,
        selectedServiceIds: <String>['svc-1'],
      );

      await expectLater(
        container.read(salonMasterServiceCoverageProvider(args).future),
        throwsA(isA<StateError>()),
      );

      final AsyncValue<Map<String, Map<String, String>>> state = container.read(
        salonMasterServiceCoverageProvider(args),
      );
      expect(state.hasError, isTrue);
      expect(state.error, isA<StateError>());
    });
  });

  group(
    'salonMasterServiceCoverageProvider — call shape (one call per selected '
    'service, never a roster fan-out)',
    () {
      test('issues exactly one getBookableMasters call per selected service, '
          'each with the correct (salonId, serviceDefId) pair', () async {
        final repo = _MockSalonRepository();
        _stubBySvc(repo, <String, Object>{
          'svc-1': const <BookableMasterAssignment>[],
          'svc-2': const <BookableMasterAssignment>[],
          'svc-3': const <BookableMasterAssignment>[],
        });

        final container = ProviderContainer(
          retry: beauticaProviderRetry,
          overrides: [salonRepositoryProvider.overrideWithValue(repo)],
        );
        addTearDown(container.dispose);

        const args = SalonBookingMasterSelectionArgs(
          salonId: _kSalonId,
          selectedServiceIds: <String>['svc-1', 'svc-2', 'svc-3'],
        );
        await container.read(salonMasterServiceCoverageProvider(args).future);

        for (final String svc in <String>['svc-1', 'svc-2', 'svc-3']) {
          verify(
            () =>
                repo.getBookableMasters(salonId: _kSalonId, serviceDefId: svc),
          ).called(1);
        }
        verifyNoMoreInteractions(repo);
      });
    },
  );

  group('salonMasterServiceCoverageProvider — family-key caching', () {
    test(
      're-reading with a DIFFERENT SalonBookingMasterSelectionArgs instance '
      'carrying the SAME (salonId, selectedServiceIds) resolves to the same '
      'cached family member — freezed value equality, not identity',
      () async {
        final repo = _MockSalonRepository();
        int callCount = 0;
        when(
          () => repo.getBookableMasters(
            salonId: any(named: 'salonId'),
            serviceDefId: any(named: 'serviceDefId'),
          ),
        ).thenAnswer((_) async {
          callCount++;
          return const <BookableMasterAssignment>[];
        });

        final container = ProviderContainer(
          retry: beauticaProviderRetry,
          overrides: [salonRepositoryProvider.overrideWithValue(repo)],
        );
        addTearDown(container.dispose);

        const args1 = SalonBookingMasterSelectionArgs(
          salonId: _kSalonId,
          selectedServiceIds: <String>['svc-1'],
        );
        // A SEPARATE, non-const instance (built from a runtime `List.of`, so
        // Dart's const-canonicalization can never fold it onto [args1]) —
        // `==` to args1 by freezed's generated equality, but deliberately
        // never `identical()` to it, which is the whole point of this test.
        final List<String> runtimeIds = List<String>.of(<String>['svc-1']);
        final args2 = SalonBookingMasterSelectionArgs(
          salonId: _kSalonId,
          selectedServiceIds: runtimeIds,
        );
        expect(identical(args1, args2), isFalse);
        expect(args1, args2);

        await container.read(salonMasterServiceCoverageProvider(args1).future);
        await container.read(salonMasterServiceCoverageProvider(args2).future);

        expect(
          callCount,
          1,
          reason:
              'args1/args2 are `==` (same salonId + selectedServiceIds) so '
              'Riverpod\'s family must resolve them to the SAME cached '
              'provider instance — a regression that keyed the family on '
              'object identity (or reverted to a bare String salonId key '
              'that ignores selectedServiceIds) would either refetch here '
              'or, worse, silently share stale coverage across different '
              'service selections',
        );
      },
    );

    test('a DIFFERENT selectedServiceIds list (same salonId) is a DIFFERENT '
        'family member and fetches independently', () async {
      final repo = _MockSalonRepository();
      _stubBySvc(repo, <String, Object>{
        'svc-1': const <BookableMasterAssignment>[],
        'svc-2': const <BookableMasterAssignment>[],
      });

      final container = ProviderContainer(
        retry: beauticaProviderRetry,
        overrides: [salonRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      const argsSvc1 = SalonBookingMasterSelectionArgs(
        salonId: _kSalonId,
        selectedServiceIds: <String>['svc-1'],
      );
      const argsSvc2 = SalonBookingMasterSelectionArgs(
        salonId: _kSalonId,
        selectedServiceIds: <String>['svc-2'],
      );

      await container.read(salonMasterServiceCoverageProvider(argsSvc1).future);
      await container.read(salonMasterServiceCoverageProvider(argsSvc2).future);

      verify(
        () =>
            repo.getBookableMasters(salonId: _kSalonId, serviceDefId: 'svc-1'),
      ).called(1);
      verify(
        () =>
            repo.getBookableMasters(salonId: _kSalonId, serviceDefId: 'svc-2'),
      ).called(1);
    });
  });

  group('salonMasterServiceCoverageProvider — keepAlive Timer lifecycle', () {
    testWidgets(
      'cancels its 5-minute keepAlive Timer on dispose (no dangling Timer '
      'when the container is disposed well within the TTL window)',
      (tester) async {
        final repo = _MockSalonRepository();
        when(
          () => repo.getBookableMasters(
            salonId: any(named: 'salonId'),
            serviceDefId: any(named: 'serviceDefId'),
          ),
        ).thenAnswer((_) async => const <BookableMasterAssignment>[]);

        final container = ProviderContainer(
          retry: beauticaProviderRetry,
          overrides: [salonRepositoryProvider.overrideWithValue(repo)],
        );
        // M1 pairing. This container is disposed EXPLICITLY mid-test (that
        // disposal IS the subject), so it used to be the one construction in
        // this file without an `addTearDown` partner — and the gap was real,
        // not cosmetic: if the `await` below throws, or an `expect` ahead of
        // the explicit `dispose()` fails, the container never gets torn down
        // and its keepAlive Timer leaks into whichever test runs next, where
        // it surfaces as an unrelated "pending timer" failure. Pairing it here
        // is safe because `ProviderContainer.dispose()` is idempotent
        // (`if (_disposed) return;` — riverpod 3.x `provider_container.dart`),
        // so the explicit call still does the real work and this is a no-op.
        addTearDown(container.dispose);

        const args = SalonBookingMasterSelectionArgs(
          salonId: _kSalonId,
          selectedServiceIds: <String>['svc-1'],
        );
        // Resolve the provider — this is what starts the 5-minute release
        // Timer (see the provider body's `ref.keepAlive()` + `Timer(...)`).
        await container.read(salonMasterServiceCoverageProvider(args).future);

        // Dispose immediately — nowhere near the 5-minute TTL. If the
        // provider's `ref.onDispose(timer.cancel)` regressed (e.g. the Timer
        // outlived the provider), `flutter_test` would fail THIS test with a
        // "pending Timer" error at teardown, even though no `expect` below
        // ever fires. Reaching the explicit `expect` is itself proof the
        // Timer was cancelled cleanly.
        container.dispose();

        expect(true, isTrue, reason: 'reaching here means no Timer leaked');
      },
    );
  });
}
