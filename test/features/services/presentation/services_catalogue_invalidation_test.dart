// Phase 7.7 audit remediation (S2) — the shared invalidation edge.
// N2 (2026-09-10) — and, since that refactor, the shared FETCH.
//
// The master's own service catalogue is now cached in exactly ONE `keepAlive`
// provider, and both surfaces read it:
//
//   • `masterServiceCatalogProvider` — the single
//     `GET /independent-masters/me/services`, watched directly by the «Послуга»
//     filter universe on «Мої записи».
//   • `servicesListProvider` — the «Мої послуги» screen, a thin
//     `ref.watch(masterServiceCatalogProvider.future)` view over it.
//
// Phase 7.7 shipped the catalogue provider with NO invalidation edge at all:
// six call sites across the services and master features invalidated the list
// and left the catalogue stale, so a service created mid-session never became
// filterable until the app was restarted. `invalidateMasterServiceCatalogues`
// is the one function that drops the cache, and this file is what stops the
// edge from being quietly lost again — in either direction, because the
// direction that used to WORK (invalidate the list) is now the one that
// silently refreshes nothing.
//
// ## Asserted on FETCH COUNTS, not on provider state
//
// A `keepAlive` provider that was never invalidated still reads back a
// perfectly valid `AsyncData` — the stale one. So "what does the provider hold"
// cannot distinguish the bug from the fix. "Did the repository get asked again"
// can, and it is also the thing the user experiences.
//
// The fetch counts are ALSO the assertion N2 exists for: two live listeners
// used to cost two identical requests on mount and two more per mutation. The
// numbers below are 1 and 1. If a future change reintroduces an independent
// fetch, these are the expectations that go red.
//
// Host-zone independent: no dates anywhere.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beautica_mobile/features/salon/application/salon_service_catalog_notifier.dart';
import 'package:beautica_mobile/features/salon/data/salon_repository.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:beautica_mobile/features/services/data/master_service_catalog_provider.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_target.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_notifier.dart';
import 'package:beautica_mobile/features/services/presentation/service_catalogue_invalidation.dart';

import '../../../helpers/pump_app.dart';

class _FakeServiceRepository extends Fake implements ServiceRepository {
  int fetches = 0;
  List<MasterService> catalogue = <MasterService>[];

  @override
  Future<List<MasterService>> listMyServices() async {
    fetches++;
    return catalogue;
  }
}

/// Counting stand-in for the SALON side of the fan-out.
///
/// Counts `GET /salons/{salonId}/services` and records WHICH salon was asked —
/// the second half matters because `salonServiceCatalogProvider` is a FAMILY,
/// and invalidating the wrong member is indistinguishable from invalidating
/// nothing at all when only a total is asserted.
class _FakeSalonRepository extends Fake implements SalonRepository {
  int catalogFetches = 0;
  final List<String> requestedSalonIds = <String>[];
  List<SalonServiceCategoryEntry> catalogue =
      const <SalonServiceCategoryEntry>[];

  @override
  Future<List<SalonServiceCategoryEntry>> getSalonServiceCatalog(
    String salonId,
  ) async {
    catalogFetches++;
    requestedSalonIds.add(salonId);
    return catalogue;
  }
}

/// Minimal harness: watches BOTH providers (so both are live and therefore
/// actually re-fetch on invalidation) and exposes the helper behind a button.
///
/// The helper takes a `WidgetRef`, which is exactly what all production call
/// sites hand it — so driving it through a real `ConsumerWidget` tests the
/// signature that ships rather than a container-shaped approximation of it.
class _Harness extends ConsumerWidget {
  const _Harness();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(servicesListProvider);
    ref.watch(masterServiceCatalogProvider);
    return Scaffold(
      body: TextButton(
        key: const Key('invalidate'),
        onPressed: () => invalidateMasterServiceCatalogues(ref),
        child: const Text('invalidate'),
      ),
    );
  }
}

/// Watches ONLY «Мої послуги». Proves the list surface refreshes from an
/// invalidation aimed at the shared provider it wraps — the half that would
/// silently break if `ServicesList.build` ever stopped watching upstream.
class _ListOnlyHarness extends ConsumerWidget {
  const _ListOnlyHarness();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(servicesListProvider);
    return Scaffold(
      body: TextButton(
        key: const Key('invalidate'),
        onPressed: () => invalidateMasterServiceCatalogues(ref),
        child: const Text('invalidate'),
      ),
    );
  }
}

/// Subscribes to NOTHING and hands its `WidgetRef` back to the test. This is
/// the shape `ServiceSetupScreen` has: it only ever `ref.read`s the services
/// list, so neither provider has a live listener when the helper runs — and
/// crucially the test can then invalidate and read in ONE synchronous turn,
/// with no frame pumped in between, exactly as `_flagRowsNowOwned` does.
class _RefCaptureHarness extends ConsumerWidget {
  const _RefCaptureHarness(this.onRef);

  final void Function(WidgetRef) onRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    onRef(ref);
    return const Scaffold(body: SizedBox.shrink());
  }
}

/// The SALON arm's harness (2026-09-14 regression guard).
///
/// Watches the salon's own catalogue alongside the master's, which is the
/// shape that ships: the salon shell keeps its «Послуги» tab mounted in an
/// `IndexedStack` while the operator is pushed into a roster master's services,
/// so `salonServiceCatalogProvider` has a LIVE listener AND a 5-minute
/// `keepAlive` across the whole write. Neither expires on its own — an explicit
/// invalidate is the only thing that can refresh the tab.
class _SalonTabHarness extends ConsumerWidget {
  const _SalonTabHarness(this.salonId);

  final String salonId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(servicesListProvider);
    ref.watch(masterServiceCatalogProvider);
    ref.watch(salonServiceCatalogProvider(salonId));
    return Scaffold(
      body: TextButton(
        key: const Key('invalidate'),
        onPressed: () => invalidateMasterServiceCatalogues(ref),
        child: const Text('invalidate'),
      ),
    );
  }
}

void main() {
  late _FakeServiceRepository repo;

  setUp(() {
    repo = _FakeServiceRepository();
    repo.catalogue = <MasterService>[
      const MasterService(
        id: 'svc-a',
        serviceDefId: 'def-a',
        name: 'Манікюр',
        durationMinutes: 60,
      ),
    ];
  });

  Future<ProviderContainer> pump(
    WidgetTester tester,
    Widget harness, {
    // Additive (2026-09-14) — defaults to empty, so every existing call site
    // pumps byte-identically to before.
    List<Object> extraOverrides = const <Object>[],
  }) async {
    await tester.pumpApp(
      harness,
      overrides: <Object>[
        serviceRepositoryProvider.overrideWithValue(repo),
        ...extraOverrides,
      ],
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(harness.runtimeType)),
    );
  }

  void addService() {
    repo.catalogue = <MasterService>[
      ...repo.catalogue,
      const MasterService(
        id: 'svc-new',
        serviceDefId: 'def-new',
        name: 'Нарощення вій',
        durationMinutes: 90,
      ),
    ];
  }

  // MUTATION (2026-09-10): emptied `invalidateMasterServiceCatalogues` to a
  // no-op → FAILED on both per-surface expectations and on the fetch count.
  // Restored.
  //
  // MUTATION (2026-09-10): replaced the helper's body with the pre-N2
  // `ref.invalidate(servicesListProvider)` — the direction that used to be the
  // working one → FAILED, because invalidating the wrapper now re-reads the
  // untouched upstream cache and re-fetches nothing. This is the regression the
  // structural guard below exists to make impossible. Restored.
  //
  // MUTATION (2026-09-10): reverted `ServicesList.build` to call
  // `ref.watch(serviceRepositoryProvider).listMyServices()` directly (the
  // pre-N2 duplicate fetch) → FAILED on `repo.fetches, 1` at mount (was 2).
  // Restored.
  testWidgets(
    'ONE fetch feeds both surfaces, and invalidating it refreshes both',
    (WidgetTester tester) async {
      final ProviderContainer container = await pump(tester, const _Harness());

      // The N2 assertion. Two live listeners, ONE request — before the
      // refactor this was 2.
      expect(
        repo.fetches,
        1,
        reason:
            'both surfaces must share a single '
            'GET /independent-masters/me/services',
      );

      addService();

      await tester.tap(find.byKey(const Key('invalidate')));
      await tester.pumpAndSettle();

      // Per-surface assertions FIRST, the aggregate count last — so a mutation
      // that breaks one surface fails on the expectation that names it, rather
      // than on a shared count that says only "something is missing".
      expect(
        container.read(servicesListProvider).value,
        hasLength(2),
        reason: 'the «Мої послуги» screen must see the new service',
      );
      expect(
        container.read(masterServiceCatalogProvider).value,
        hasLength(2),
        reason:
            'the «Послуга» filter universe must see it too — this is the half '
            'Phase 7.7 shipped without an invalidation edge',
      );
      expect(
        repo.fetches,
        2,
        reason:
            'a mutation must cost exactly ONE refetch however many surfaces '
            'are live — it cost two before N2',
      );
    },
  );

  // The «Мої послуги» surface alone, with a LIVE listener. Proves the list
  // refreshes through the watch edge on the shared fetch, and that it still
  // costs one request rather than two.
  testWidgets(
    '«Мої послуги» alone still refreshes from the shared invalidation',
    (WidgetTester tester) async {
      final ProviderContainer container = await pump(
        tester,
        const _ListOnlyHarness(),
      );
      expect(repo.fetches, 1);
      expect(container.read(servicesListProvider).value, hasLength(1));

      addService();

      await tester.tap(find.byKey(const Key('invalidate')));
      await tester.pumpAndSettle();

      expect(
        container.read(servicesListProvider).value,
        hasLength(2),
        reason:
            'the list wraps masterServiceCatalogProvider.future — dropping the '
            'upstream must rebuild it',
      );
      expect(repo.fetches, 2);
    },
  );

  // ── The second line of the helper is NOT redundant ──────────────────────
  //
  // Riverpod does not propagate an invalidation to a dependent that has NO
  // live listener: `masterServiceCatalogProvider` drops its state and defers
  // the refetch, while `servicesListProvider` keeps handing out its cached
  // future and never learns to rebuild. `ServiceSetupScreen._flagRowsNowOwned`
  // is exactly this shape — the screen only ever `ref.read`s the list, so
  // nothing is subscribed — and it silently answered with the stale pre-save
  // catalogue while the helper invalidated the upstream alone.
  //
  // MUTATION (2026-09-10): dropped `ref.invalidate(masterServiceCatalogProvider)`
  // from the helper, leaving only the wrapper line → this test FAILED: the
  // wrapper rebuilds but re-reads an untouched upstream cache, so
  // `repo.fetches` stayed 1 and the read returned the stale 1-item list.
  // Restored.
  //
  // MUTATION (2026-09-10): dropped `ref.invalidate(servicesListProvider)`
  // instead → this test stayed GREEN and `service_setup_screen_test.dart`'s
  // "_flagRowsNowOwned must re-read the catalogue after the invalidate" went
  // RED. That asymmetry is REPORTED, not papered over: even reading through a
  // captured `WidgetRef` with no frame pumped, a `pumpApp` harness settles the
  // graph enough that the propagation gap does not reproduce here. The pin for
  // the wrapper line therefore lives on the real screen. Do not "strengthen"
  // this test by hand-rolling `container.invalidate(...)` twice — that bypasses
  // the helper and would guard nothing at all.
  testWidgets(
    'an UNLISTENED reader sees the mutation — the read-after-invalidate shape',
    (WidgetTester tester) async {
      // The harness subscribes to NOTHING; the list is only ever `read`, the
      // way `_flagRowsNowOwned` reads it.
      late WidgetRef ref;
      final ProviderContainer container = await pump(
        tester,
        _RefCaptureHarness((WidgetRef r) => ref = r),
      );

      expect(await container.read(servicesListProvider.future), hasLength(1));
      expect(repo.fetches, 1);

      addService();

      // Through the REAL helper, and with NO frame pumped between the
      // invalidation and the read — pumping first lets the scheduler flush the
      // graph and hides the very staleness this test exists to catch.
      invalidateMasterServiceCatalogues(ref);
      final List<MasterService> refreshed = await ref.read(
        servicesListProvider.future,
      );

      expect(
        refreshed,
        hasLength(2),
        reason:
            'a read that follows the invalidation must see the new service — '
            'with the wrapper left un-invalidated it answers from its cached '
            'future and never asks again',
      );
      expect(
        repo.fetches,
        2,
        reason: 'still ONE request for the pair, not two',
      );
    },
  );

  // ── The SALON arm (2026-09-14 regression guard) ─────────────────────────
  //
  // THE BUG. A salon owner assigned an already-offered service to a SECOND
  // roster master at a different price. The locked rule is that a salon's
  // catalogue IS the set of services its active masters perform, priced ACROSS
  // them, so the salon's «Послуги» row should have turned from a single price
  // into a RANGE. It kept showing the first master's single price until the app
  // was restarted: `invalidateMasterServiceCatalogues` dropped only the
  // MASTER-scoped caches, and `salonServiceCatalogProvider` is both `keepAlive`
  // for 5 minutes AND held by a live listener (the salon shell parks the tab in
  // an `IndexedStack`), so nothing ever made it ask again.
  //
  // Asserted on the salon repository's FETCH COUNT for the same reason the
  // three cases above are: an un-invalidated `keepAlive` provider reads back a
  // perfectly valid `AsyncData` — the stale one — and riverpod's invalidate
  // deliberately RETAINS `.value` while the refetch is in flight
  // (`project_riverpod_seamless_invalidate_gotcha`), so NOTHING on the read
  // side can distinguish the bug from the fix. "Did the salon endpoint get
  // asked again" can, and it is what the user experiences.
  //
  // Each of the three cases below was mutation-probed against the defect it
  // actually claims to catch — a negative assertion that is never made to go
  // red is indistinguishable from one that cannot (M14):
  //
  // MUTATION (2026-09-14): commented the whole `if (target is
  // SalonMasterTarget)` block out of the helper — i.e. the shipped bug →
  // CASE A FAILED (`Expected: <2> Actual: <1>`). B and C green, correctly:
  // both assert a NON-fetch. Restored.
  //
  // MUTATION (2026-09-14): kept the arm but keyed it on a hard-coded salon
  // (`salonServiceCatalogProvider('salon-other')`) → CASE C FAILED
  // (`Expected: ['salon-other'] Actual: ['salon-other', 'salon-other']`),
  // and A failed too. Restored.
  //
  // MUTATION (2026-09-14): dropped the `is SalonMasterTarget` GATE, firing the
  // invalidate for every target → CASE B FAILED (`Expected: <1> Actual: <2>`)
  // while A and C stayed green. Restored.
  const String kSalonId = 'salon-xyz';
  const ServiceTarget kSalonTarget = ServiceTarget.salonMaster(
    salonId: kSalonId,
    masterId: 'master-removable',
  );

  late _FakeSalonRepository salonRepo;
  setUp(() => salonRepo = _FakeSalonRepository());

  List<Object> salonOverrides(ServiceTarget? target) => <Object>[
    salonRepositoryProvider.overrideWithValue(salonRepo),
    serviceTargetProvider.overrideWithValue(target),
  ];

  // CASE A — in salon mode the salon's own catalogue must be dropped too.
  testWidgets(
    'a SalonMasterTarget mutation also re-fetches the salon catalogue the '
    'master feeds',
    (WidgetTester tester) async {
      await pump(
        tester,
        const _SalonTabHarness(kSalonId),
        extraOverrides: salonOverrides(kSalonTarget),
      );

      expect(
        salonRepo.catalogFetches,
        1,
        reason: 'the mounted «Послуги» tab loads once',
      );

      await tester.tap(find.byKey(const Key('invalidate')));
      await tester.pumpAndSettle();

      expect(
        salonRepo.catalogFetches,
        2,
        reason:
            'assigning a service to a second master changes the SALON-wide '
            'aggregate (a single price becomes a RANGE) — the tab can only '
            'show that if the helper drops its cache; keepAlive + a live '
            'listener mean it never expires on its own',
      );
      expect(
        salonRepo.requestedSalonIds,
        <String>[kSalonId, kSalonId],
        reason:
            'the family member re-asked must be the TARGET salon — '
            'salonServiceCatalogProvider is a family, and invalidating the '
            'wrong member is indistinguishable from invalidating none when '
            'only a total is asserted',
      );
    },
  );

  // CASE B — THE CONTROL. Without it, a helper that invalidated the family
  // unconditionally (or a hard-coded salon id) would pass case A and silently
  // bill every INDEPENDENT_MASTER an extra GET forever.
  testWidgets('an INDEPENDENT_MASTER (null target) pays NO extra salon GET', (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      const _SalonTabHarness(kSalonId),
      extraOverrides: salonOverrides(null),
    );

    expect(salonRepo.catalogFetches, 1);

    await tester.tap(find.byKey(const Key('invalidate')));
    await tester.pumpAndSettle();

    expect(
      salonRepo.catalogFetches,
      1,
      reason:
          'a solo master has no salon catalogue at all — invalidating a '
          'family member nobody is watching buys an extra '
          'GET /salons/{id}/services for nothing',
    );
    expect(
      repo.fetches,
      2,
      reason:
          'ANTI-VACUITY — the helper still ran and still dropped the '
          'MASTER caches; the salon count stayed at 1 because the arm is '
          'gated, not because nothing happened',
    );
  });

  // CASE C — the same gate, from the other side: the invalidate must be keyed
  // on the TARGET's salon. A hard-coded or mis-keyed family argument is
  // invisible to case A (which watches the very salon it targets).
  testWidgets('a DIFFERENT salon\'s catalogue is left alone', (
    WidgetTester tester,
  ) async {
    const String otherSalonId = 'salon-other';
    await pump(
      tester,
      const _SalonTabHarness(otherSalonId),
      extraOverrides: salonOverrides(kSalonTarget),
    );

    expect(salonRepo.requestedSalonIds, <String>[otherSalonId]);

    await tester.tap(find.byKey(const Key('invalidate')));
    await tester.pumpAndSettle();

    expect(
      salonRepo.requestedSalonIds,
      <String>[otherSalonId],
      reason:
          'only the target salon\'s aggregate changed — a bystander salon '
          'tab must not be forced to refetch',
    );
  });

  // A structural guard, deliberately: the bug was not "the helper is wrong", it
  // was "nobody calls anything". Since N2 it guards BOTH names, and for
  // opposite reasons:
  //
  //   • `invalidate(masterServiceCatalogProvider)` outside the helper —
  //     works, but scatters the fan-out point the helper exists to be.
  //   • `invalidate(servicesListProvider)` anywhere — silently refreshes
  //     NOTHING, because that provider now re-reads an untouched upstream
  //     cache. This is the pre-N2 shape and it is now a live bug.
  //
  // The old `onRetry` exemption was REMOVED with the same change: a retry that
  // invalidates the wrapper is exactly as broken as a mutation that does, so
  // both retry sites (`services_list_screen.dart`,
  // `booking_wizard_steps.dart`) now call the helper. There is no exempt shape.
  test('no production code invalidates either catalogue provider directly', () {
    // The ONE legitimate call site, pinned by FULL path.
    //
    // This was previously a bare `endsWith('services_list_notifier.dart')` —
    // the file the helper was originally going to live in. The helper was then
    // deliberately moved to its own file (see that file's header: it keeps
    // `forbid_provider_self_invalidation.sh`'s signal honest) and the exemption
    // was never repointed, so this guard flagged the very function it exists to
    // mandate. A full path plus the existence assertion below is what makes the
    // next move fail LOUDLY here instead of silently un-exempting the helper or
    // — worse — silently exempting some unrelated file that happens to share a
    // basename.
    const String helperPath =
        'lib/features/services/presentation/service_catalogue_invalidation.dart';
    expect(
      File(helperPath).existsSync(),
      isTrue,
      reason:
          'the exempted helper moved or was renamed — repoint `helperPath` at '
          'its new location, do NOT relax this guard to a basename match',
    );

    const List<String> guarded = <String>[
      'invalidate(servicesListProvider)',
      'invalidate(masterServiceCatalogProvider)',
    ];

    final List<String> offenders = <String>[];
    final Directory lib = Directory('lib');
    for (final FileSystemEntity e in lib.listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      if (e.path.endsWith('.g.dart') || e.path.endsWith('.freezed.dart')) {
        continue;
      }
      if (e.path == helperPath) continue;
      final String src = e.readAsStringSync();
      for (final String line in src.split('\n')) {
        if (!guarded.any(line.contains)) continue;
        // Prose, not a call site — several headers legitimately discuss the
        // invalidation edge by name.
        if (line.trimLeft().startsWith('//')) continue;
        offenders.add('${e.path}: ${line.trim()}');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'after a service create/edit/delete — or on an error-state retry — '
          'call invalidateMasterServiceCatalogues(ref) instead. Invalidating '
          'servicesListProvider re-reads the untouched shared cache and '
          'refreshes nothing at all; invalidating the catalogue provider by '
          'hand scatters the one fan-out point',
    );
  });
}
