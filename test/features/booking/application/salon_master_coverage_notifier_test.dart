// Phase 14.13 QA follow-up (mobile-perf re-audit) — regression tests for
// `salonMasterServiceCoverageProvider`'s three perf-critical behaviours that
// no existing test exercised directly:
//
//   1. The `GET /masters/{id}/services` fan-out is CHUNKED — at most
//      `_kFetchChunkSize` (8) calls are ever in flight concurrently, even for
//      a roster bigger than one chunk.
//   2. The merged coverage map is complete and correct for EVERY master in
//      the roster, not just the first chunk (a naive off-by-one in the chunk
//      loop would silently drop the tail).
//   3. The provider's 5-minute `ref.keepAlive()` release [Timer] is cancelled
//      on `ref.onDispose` — disposing the [ProviderContainer] well within the
//      TTL window must not leave a dangling [Timer]. `flutter_test` fails a
//      `testWidgets` body outright if any [Timer] is still pending when the
//      test ends, so this is a self-verifying assertion: if the provider
//      regressed to NOT cancelling the timer, this test would fail with a
//      "pending timer" error, not a normal `expect` mismatch.
//
// Mirrors the widget-level fixtures in
// `test/features/booking/presentation/salon_master_selection_screen_test.dart`
// (same salon id, same `MasterType`) and the keepAlive-Timer idiom already
// proven for the sibling provider `salonReviewSummaryProvider` in
// `test/features/salon/application/salon_tab_providers_keepalive_test.dart`.

import 'dart:async';

import 'package:beautica_mobile/features/booking/application/salon_master_coverage_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/salon/application/public_salon_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_master_summary.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockServiceRepository extends Mock implements ServiceRepository {}

const String _kSalonId = 'salon-1';

const Salon _stubSalon = Salon(id: _kSalonId, name: 'Салон «Вельвет»');

/// A single service definition id every fixture master "covers" via
/// [_serviceFor] — only its presence/absence in the returned [MasterService]
/// list matters for this test, not its content.
MasterService _serviceFor(String masterId) => MasterService(
  id: 'assignment-$masterId',
  serviceDefId: 'svc-$masterId',
  name: 'Service of $masterId',
  durationMinutes: 60,
  priceMin: 300,
  priceDisplay: '300 грн',
);

List<SalonMasterSummary> _rosterOf(int count) =>
    List<SalonMasterSummary>.generate(
      count,
      (int i) => SalonMasterSummary(
        masterId: 'm$i',
        firstName: 'Майстер',
        lastName: '$i',
        type: MasterType.salonMaster,
      ),
    );

void main() {
  group('salonMasterServiceCoverageProvider — bounded fan-out chunking', () {
    test('issues at most 8 concurrent getMasterServices calls for a roster of '
        '20 masters, and never dispatches the next chunk before the current '
        'one settles', () async {
      final repo = _MockServiceRepository();
      final List<SalonMasterSummary> roster = _rosterOf(20);

      int inFlight = 0;
      int maxInFlight = 0;
      int totalDispatched = 0;
      final Map<String, Completer<List<MasterService>>> pending =
          <String, Completer<List<MasterService>>>{};

      when(() => repo.getMasterServices(any())).thenAnswer((
        Invocation invocation,
      ) {
        final String masterId = invocation.positionalArguments[0] as String;
        inFlight++;
        totalDispatched++;
        if (inFlight > maxInFlight) maxInFlight = inFlight;
        final completer = Completer<List<MasterService>>();
        pending[masterId] = completer;
        return completer.future.whenComplete(() => inFlight--);
      });

      final container = ProviderContainer(
        overrides: [
          publicSalonProfileProvider(
            _kSalonId,
          ).overrideWith((ref) => (_stubSalon, roster)),
          publicServiceRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      final Future<Map<String, Map<String, String>>> resultFuture = container
          .read(salonMasterServiceCoverageProvider(_kSalonId).future);

      // Let the microtask queue drain enough for `publicSalonProfileProvider`
      // to resolve and the first chunk's calls to be dispatched, WITHOUT
      // resolving any of them yet.
      await pumpEventQueue();

      expect(
        totalDispatched,
        8,
        reason:
            'first chunk must dispatch exactly _kFetchChunkSize (8) calls '
            'for a 20-master roster',
      );
      expect(
        maxInFlight,
        8,
        reason: 'no more than 8 calls may be in flight at once',
      );

      // Settle chunk 1 (masters m0..m7).
      for (final String id in pending.keys.toList()) {
        pending[id]!.complete(<MasterService>[_serviceFor(id)]);
      }
      await pumpEventQueue();

      expect(
        totalDispatched,
        16,
        reason:
            'chunk 2 (masters m8..m15) must dispatch only after chunk 1 '
            'fully settled',
      );
      expect(maxInFlight, 8, reason: 'chunk 2 must also cap at 8 in flight');

      // Settle chunk 2 (masters m8..m15).
      for (final String id in pending.keys.toList()) {
        if (pending[id]!.isCompleted) continue;
        pending[id]!.complete(<MasterService>[_serviceFor(id)]);
      }
      await pumpEventQueue();

      expect(
        totalDispatched,
        20,
        reason:
            'the final partial chunk (masters m16..m19, only 4 masters) '
            'must still be dispatched — an off-by-one in the chunk loop '
            'would silently drop the tail',
      );

      // Settle the final partial chunk (masters m16..m19).
      for (final String id in pending.keys.toList()) {
        if (pending[id]!.isCompleted) continue;
        pending[id]!.complete(<MasterService>[_serviceFor(id)]);
      }

      final Map<String, Map<String, String>> coverage = await resultFuture;

      expect(
        coverage.keys.toSet(),
        roster.map((SalonMasterSummary m) => m.masterId).toSet(),
        reason:
            'the merged coverage map must contain EVERY master in the '
            'roster, not just the first chunk',
      );
      for (final SalonMasterSummary m in roster) {
        // Phase 14.16/14.17 bugfix regression guard: asserts the FULL
        // `serviceDefId -> assignmentId` map, not just which serviceDefIds
        // are present — a regression that keyed the map correctly but
        // discarded/overwrote `MasterService.id` (e.g. reverted to
        // collapsing into a bare `Set<String>` of serviceDefIds) would pass
        // a presence-only check but fail this value-level assertion.
        expect(
          coverage[m.masterId],
          <String, String>{'svc-${m.masterId}': 'assignment-${m.masterId}'},
          reason:
              'each master\'s coverage map must carry the exact '
              'serviceDefId -> assignmentId pairs from its OWN '
              'getMasterServices response (MasterService.serviceDefId -> '
              'MasterService.id) — a chunk-index mix-up would cross-assign '
              'another master\'s services, and dropping the assignment id '
              'would reintroduce the masterService-not-found bug',
        );
      }
    });

    test('a roster that is an exact multiple of the chunk size (16) dispatches '
        'in exactly two chunks of 8, with no trailing empty chunk', () async {
      final repo = _MockServiceRepository();
      final List<SalonMasterSummary> roster = _rosterOf(16);

      int totalDispatched = 0;
      final Map<String, Completer<List<MasterService>>> pending =
          <String, Completer<List<MasterService>>>{};

      when(() => repo.getMasterServices(any())).thenAnswer((
        Invocation invocation,
      ) {
        final String masterId = invocation.positionalArguments[0] as String;
        totalDispatched++;
        final completer = Completer<List<MasterService>>();
        pending[masterId] = completer;
        return completer.future;
      });

      final container = ProviderContainer(
        overrides: [
          publicSalonProfileProvider(
            _kSalonId,
          ).overrideWith((ref) => (_stubSalon, roster)),
          publicServiceRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      final Future<Map<String, Map<String, String>>> resultFuture = container
          .read(salonMasterServiceCoverageProvider(_kSalonId).future);

      await pumpEventQueue();
      expect(totalDispatched, 8);

      for (final String id in pending.keys.toList()) {
        pending[id]!.complete(<MasterService>[_serviceFor(id)]);
      }
      await pumpEventQueue();
      expect(
        totalDispatched,
        16,
        reason: 'second chunk covers the remaining 8 masters exactly',
      );

      for (final String id in pending.keys.toList()) {
        if (pending[id]!.isCompleted) continue;
        pending[id]!.complete(<MasterService>[_serviceFor(id)]);
      }
      final Map<String, Map<String, String>> coverage = await resultFuture;
      expect(coverage.length, 16);
      // No third chunk was ever dispatched (would have bumped this past 16).
      expect(totalDispatched, 16);
    });
  });

  group('salonMasterServiceCoverageProvider — keepAlive Timer lifecycle', () {
    testWidgets(
      'cancels its 5-minute keepAlive Timer on dispose (no dangling Timer '
      'when the container is disposed well within the TTL window)',
      (tester) async {
        final repo = _MockServiceRepository();
        when(
          () => repo.getMasterServices(any()),
        ).thenAnswer((_) async => <MasterService>[]);

        final container = ProviderContainer(
          overrides: [
            publicSalonProfileProvider(
              _kSalonId,
            ).overrideWith((ref) => (_stubSalon, _rosterOf(2))),
            publicServiceRepositoryProvider.overrideWithValue(repo),
          ],
        );

        // Resolve the provider — this is what starts the 5-minute release
        // Timer (see the provider body's `ref.keepAlive()` + `Timer(...)`).
        await container.read(
          salonMasterServiceCoverageProvider(_kSalonId).future,
        );

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
