// Phase 7.7 audit remediation (S2) — the shared invalidation edge.
//
// The master's own service catalogue is cached in TWO independent `keepAlive`
// providers, which by design cannot watch each other (see
// `master_service_catalog_provider.dart`'s header):
//
//   • `servicesListProvider`          — the «Мої послуги» screen.
//   • `masterServiceCatalogProvider`  — the «Послуга» filter universe on «Мої
//                                        записи».
//
// Phase 7.7 shipped the second one with NO invalidation edge at all: six call
// sites across the services and master features invalidated the first and left
// the second stale, so a service created mid-session never became filterable
// until the app was restarted. `invalidateMasterServiceCatalogues` is the one
// function that now drops both, and this file is what stops the second line
// from being quietly lost again.
//
// ## Asserted on FETCH COUNTS, not on provider state
//
// A `keepAlive` provider that was never invalidated still reads back a
// perfectly valid `AsyncData` — the stale one. So "what does the provider hold"
// cannot distinguish the bug from the fix. "Did the repository get asked again"
// can, and it is also the thing the user experiences.
//
// Host-zone independent: no dates anywhere.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beautica_mobile/features/services/data/master_service_catalog_provider.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
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

/// Minimal harness: watches BOTH providers (so both are live and therefore
/// actually re-fetch on invalidation) and exposes the helper behind a button.
///
/// The helper takes a `WidgetRef`, which is exactly what all six production
/// call sites hand it — so driving it through a real `ConsumerWidget` tests the
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

  Future<ProviderContainer> pump(WidgetTester tester) async {
    await tester.pumpApp(
      const _Harness(),
      overrides: <Object>[serviceRepositoryProvider.overrideWithValue(repo)],
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(_Harness)));
  }

  // MUTATION: dropped `ref.invalidate(masterServiceCatalogProvider)` from
  // `invalidateMasterServiceCatalogues`, leaving only the `servicesListProvider`
  // line (i.e. exactly the pre-fix behaviour) → this test FAILED on the
  // «Послуга»-filter-universe expectation. Restored.
  //
  // MUTATION: dropped `ref.invalidate(servicesListProvider)` instead → this
  // test FAILED on the «Мої послуги» expectation, and the catalogue one stayed
  // green. Restored.
  //
  // The two mutations failing on DIFFERENT expectations is not incidental — it
  // is why the per-provider assertions were ordered ahead of the aggregate
  // fetch count. With the count first, both mutations failed on the same
  // "<4> vs <3>" line, which localises nothing.
  testWidgets('invalidateMasterServiceCatalogues drops BOTH cached views', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = await pump(tester);

    // Two live providers, two independent fetches — the documented cost of
    // keeping them independent.
    expect(repo.fetches, 2);

    repo.catalogue = <MasterService>[
      ...repo.catalogue,
      const MasterService(
        id: 'svc-new',
        serviceDefId: 'def-new',
        name: 'Нарощення вій',
        durationMinutes: 90,
      ),
    ];

    await tester.tap(find.byKey(const Key('invalidate')));
    await tester.pumpAndSettle();

    // Per-provider assertions FIRST, the aggregate count last — so a mutation
    // to either line of the helper fails on the expectation that names it,
    // rather than on a shared count that says only "something is missing".
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
      4,
      reason: 'both providers must re-fetch, not just the services list',
    );
  });

  // A structural guard, deliberately: the bug was not "the helper is wrong", it
  // was "nobody calls anything". If a future mutation path invalidates
  // `servicesListProvider` directly again, the catalogue silently goes stale
  // and no behavioural test in this repo would notice — the regression is
  // invisible until someone opens the filter sheet on a real device.
  test('no production code invalidates servicesListProvider directly', () {
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
        if (!line.contains('invalidate(servicesListProvider)')) continue;
        // Prose, not a call site — several headers legitimately discuss the
        // invalidation edge by name.
        if (line.trimLeft().startsWith('//')) continue;
        // `onRetry:` on the list screen's own error state is a re-fetch of THAT
        // screen, not a mutation — the catalogue is unaffected by a failed read.
        if (line.contains('onRetry')) continue;
        offenders.add('${e.path}: ${line.trim()}');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'after a service create/edit/delete, call '
          'invalidateMasterServiceCatalogues(ref) instead — invalidating the '
          'list alone leaves the «Послуга» filter universe stale until the app '
          'restarts',
    );
  });
}
