// Regression — `serviceById` must SELF-HEAL from the master-profile readiness
// race, with no manual «retry» tap.
//
// THE DEFECT
// ----------
// `serviceRepositoryProvider` resolves its master id from
// `ref.watch(masterProfileProvider).value?.id ?? ''`, and
// `HttpServiceRepository.getMyService` opens with a readiness guard that throws
// `UnauthorizedFailure` while that id is empty. On a COLD deep-link straight to
// `/services/:id/edit` the profile has not resolved yet, so the first build of
// `serviceByIdProvider` fails that guard.
//
// `serviceById` used to take BOTH of its dependencies with `ref.read`, so it
// registered no subscription and could never rebuild when the profile arrived.
// That was invisible for as long as Riverpod's blanket backoff was in play: the
// build was re-run at +200 ms, by which time the profile had resolved, and the
// failure disappeared on its own. Installing `beauticaProviderRetry` correctly
// stopped retrying deterministic failures — and thereby ARMED this bug. The
// screen lands on its error branch and stays there until the user taps «retry».
//
// WHAT THIS TEST PINS
// -------------------
// The recovery itself, not merely the absence of an exception: the edit form
// must end up populated after the profile resolves, with no interaction in
// between. Revert `service_by_id_notifier.dart`'s cache-miss line from
// `ref.watch(serviceRepositoryProvider)` back to `ref.read(...)` and the second
// expectation fails — the error state is still on screen.
//
// `retry:` is passed EXPLICITLY rather than inherited from `pumpApp`, so this
// file states the production policy it is reasoning about instead of depending
// on a harness default (which has its own ratchet in
// `test/helpers/pump_app_retry_policy_test.dart`).
//
// WHY THE REPOSITORY OVERRIDE IS A BUILDER, NOT A VALUE
// -----------------------------------------------------
// The bug lives in the DEPENDENCY EDGE, not in the repository. An
// `overrideWithValue` would pin one instance forever and make the race
// unreproducible. This override mirrors the real
// `serviceRepositoryProvider` body — watch the profile, derive the master id,
// hand back a repository whose readiness guard reflects it — so the graph under
// test has the same shape as production.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/domain/service_type_option.dart';
import 'package:beautica_mobile/features/services/presentation/service_by_id_notifier.dart';
import 'package:beautica_mobile/features/services/presentation/service_edit_screen.dart';
import 'package:beautica_mobile/features/services/presentation/service_types_provider.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockServiceRepository extends Mock implements ServiceRepository {}

const _stubService = MasterService(
  id: 'svc-edit-1',
  serviceDefId: 'def-edit-1',
  name: 'Стрижка жіноча',
  durationMinutes: 60,
  priceType: ServicePriceType.fixed,
  priceMin: 750.0,
  priceDisplay: '750 ₴',
  category: 'HAIRCUT',
);

const _stubMaster = Master(
  id: 'master-uuid-1',
  firstName: 'Т',
  lastName: 'Т',
  avgRating: 0,
  reviewCount: 0,
  type: MasterType.independentMaster,
);

/// Held open so the master profile is UNRESOLVED on the first frame — the cold
/// deep-link state. The test completes it to simulate the profile arriving.
///
/// ZONE TRAP — this MUST be constructed inside each test body, never in
/// `setUp`. `testWidgets` runs its body inside a `FakeAsync` zone; `setUp` runs
/// outside it. A `Completer` created in the outer zone schedules its
/// continuations on the REAL microtask queue, which `tester.pump()` never
/// drains — so `complete()` would leave the notifier parked in `AsyncLoading`
/// forever and this test would report the exact failure it is meant to detect,
/// for entirely the wrong reason.
late Completer<Master> _profileGate;

/// Stands in for `MasterProfile`, parked on [_profileGate].
class _GatedMasterProfileNotifier extends MasterProfile {
  @override
  Future<Master> build() => _profileGate.future;
}

/// Every repository instance the overridden provider handed out, so the test
/// can prove the provider was actually RE-BUILT (a `read`-based notifier would
/// still see instance #1 forever).
late List<_MockServiceRepository> _repoInstances;

/// Mirrors the production `serviceRepository` body: derive the master id from
/// the profile, and expose a repository whose readiness guard reflects it.
_MockServiceRepository _repositoryFor(String masterId) {
  final repo = _MockServiceRepository();
  if (masterId.isEmpty) {
    // The `_assertAuthenticated()` readiness guard, verbatim in effect.
    when(
      () => repo.listMyServices(),
    ).thenAnswer((_) async => throw const UnauthorizedFailure());
    when(
      () => repo.getMyService(_stubService.id),
    ).thenAnswer((_) async => throw const UnauthorizedFailure());
  } else {
    when(
      () => repo.listMyServices(),
    ).thenAnswer((_) async => const <MasterService>[_stubService]);
    when(
      () => repo.getMyService(_stubService.id),
    ).thenAnswer((_) async => _stubService);
  }
  _repoInstances.add(repo);
  return repo;
}

// `Override` is not publicly exported by Riverpod 3, so the list is typed
// `Object` and cast at the call site — the same idiom the rest of the suite and
// `AppHarness.boot` use.
List<Object> _overrides() => <Object>[
  masterProfileProvider.overrideWith(_GatedMasterProfileNotifier.new),
  serviceRepositoryProvider.overrideWith(
    (ref) => _repositoryFor(ref.watch(masterProfileProvider).value?.id ?? ''),
  ),
  // The edit form's category row and type chips fetch directly; keep them calm
  // so nothing in the form subtree fires an un-mocked request.
  approvedCategoriesProvider.overrideWith(
    (ref) async => const <ServiceCategoryOption>[
      ServiceCategoryOption(name: 'HAIRCUT', displayName: 'Стрижка'),
    ],
  ),
  serviceTypesProvider.overrideWith(
    (ref, String categoryName) async => const <ServiceTypeOption>[],
  ),
];

void main() {
  setUp(() {
    _repoInstances = <_MockServiceRepository>[];
  });

  testWidgets(
    'serviceById recovers on its own once the master profile resolves — the '
    'edit form populates with NO manual retry tap',
    (WidgetTester tester) async {
      // In-body construction — see the zone trap on [_profileGate].
      _profileGate = Completer<Master>();
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          // The production predicate — deterministic failures are NOT retried,
          // which is exactly the condition that arms this bug.
          retry: beauticaProviderRetry,
          overrides: _overrides().cast(),
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('uk'),
            home: ServiceEditScreen(id: 'svc-edit-1'),
          ),
        ),
      );
      // Drain the rejected readiness futures without completing the gate.
      await tester.pump();
      await tester.pump();

      // ── Precondition: the cold deep-link really does land on the error branch.
      // Without this the test could pass vacuously (never having reproduced the
      // race at all).
      expect(
        find.byKey(const Key('service_edit_error_state')),
        findsOneWidget,
        reason:
            'the unresolved master profile must produce the UnauthorizedFailure '
            'error surface first — otherwise the recovery below proves nothing',
      );
      expect(_repoInstances, hasLength(greaterThanOrEqualTo(1)));

      // ── The profile arrives. Nothing else happens: no tap, no invalidate.
      _profileGate.complete(_stubMaster);
      // Frame 1: the profile lands and serviceRepositoryProvider is rebuilt.
      // Frame 2: serviceById re-runs and its fetch resolves.
      // Then settle the form's own second-level futures.
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('service_edit_error_state')),
        findsNothing,
        reason:
            'serviceById must re-run when serviceRepositoryProvider is rebuilt '
            'by the resolved profile. Still finding the error state means the '
            'notifier took a snapshot (ref.read) instead of subscribing '
            '(ref.watch), and the screen is stuck until the user taps «retry».',
      );

      final nameField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('field-service-name')),
          matching: find.byType(TextField),
        ),
      );
      expect(
        nameField.controller?.text,
        equals(_stubService.name),
        reason:
            'assert the RECOVERY, not merely that no exception escaped: the '
            'form must actually be populated from the re-fetched service',
      );
    },
  );

  test(
    'serviceById subscribes to serviceRepositoryProvider — a rebuilt '
    'repository re-runs the provider (container-level, no widget tree)',
    () async {
      _profileGate = Completer<Master>();
      final container = ProviderContainer(
        retry: beauticaProviderRetry,
        overrides: _overrides().cast(),
      );
      addTearDown(container.dispose);

      // Keep the provider alive across the rebuild, the way the mounted edit
      // screen does.
      final sub = container.listen(
        serviceByIdProvider(_stubService.id),
        (_, _) {},
      );
      addTearDown(sub.close);

      await expectLater(
        container.read(serviceByIdProvider(_stubService.id).future),
        throwsA(isA<UnauthorizedFailure>()),
      );

      _profileGate.complete(_stubMaster);
      // Let the profile notifier settle so the repository provider rebuilds.
      await container.read(masterProfileProvider.future);

      expect(
        await container.read(serviceByIdProvider(_stubService.id).future),
        equals(_stubService),
        reason:
            'the second read must reflect the READY repository. With ref.read '
            'the provider never re-runs, so this stays the cached '
            'UnauthorizedFailure.',
      );
    },
  );
}
