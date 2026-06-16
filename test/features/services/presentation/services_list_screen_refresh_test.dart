// Stale-cache regression — ServicesListScreen invalidates the serviceTypes
// family on every refresh surface (entry / pop-back / pull-to-refresh).
//
// The bug: a service type approved out-of-band by an admin under an EXISTING
// category never appeared in the "Тип послуги" dropdown, because the
// serviceTypes(category) family was pinned alive (keepAlive + 3-min Timer) and
// never re-fetched on picker re-entry.
//
// The fix added `ref.invalidate(serviceTypesProvider)` (whole family) alongside
// the existing approvedCategoriesProvider invalidations at THREE sites in
// [ServicesListScreen]:
//   1. initState (first entry),
//   2. _openAndRefresh (return from a pushed route — create / edit flows),
//   3. RefreshIndicator.onRefresh (pull-to-refresh).
//
// These tests pin sites (1) and (3) by attaching a live listener to a specific
// family key (so the family actually fetches), then asserting the screen
// re-issues `fetchServiceTypes(category)` for that key. They guard against
// someone re-adding keepAlive or dropping an invalidation call.
//
// Strategy:
//   • Build a real [ProviderContainer] with the repository mocked, host the
//     screen under an [UncontrolledProviderScope] so the test owns the
//     container and can attach a listener / count fetches on it.
//   • Keep a live subscription on serviceTypesProvider('HAIRCUT') for the whole
//     test so each invalidation triggers a real re-fetch we can verify.

import 'dart:async';

import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/domain/service_type_option.dart';
import 'package:beautica_mobile/features/services/presentation/service_types_provider.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_notifier.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// ── Mocks ──────────────────────────────────────────────────────────────────

class _MockServiceRepository extends Mock implements ServiceRepository {}

// ── Stub data ────────────────────────────────────────────────────────────────

const _hairTypes = <ServiceTypeOption>[
  ServiceTypeOption(
    id: 'type-1',
    slug: 'WOMENS_CUT',
    nameUk: 'Жіноча стрижка',
    categoryName: 'HAIRCUT',
  ),
];

const _populatedService = MasterService(
  id: 'svc-001',
  serviceDefId: 'def-001',
  name: 'Стрижка',
  durationMinutes: 45,
  priceMin: 750,
  priceDisplay: '750 грн',
  category: 'HAIRCUT',
);

// ── Stub notifier ─────────────────────────────────────────────────────────────

/// Resolves [servicesListProvider] to a data state after one loading frame.
class _StubServicesList extends ServicesList {
  _StubServicesList(this._target);

  final List<MasterService> _target;

  @override
  Future<List<MasterService>> build() {
    Future<void>.microtask(() => state = AsyncData(_target));
    return Completer<List<MasterService>>().future;
  }
}

void main() {
  late _MockServiceRepository repo;

  setUp(() {
    repo = _MockServiceRepository();
    when(
      () => repo.listMyServices(),
    ).thenAnswer((_) async => const <MasterService>[_populatedService]);
    when(() => repo.fetchApprovedCategories()).thenAnswer(
      (_) async => const <ServiceCategoryOption>[
        ServiceCategoryOption(name: 'HAIRCUT', displayName: 'Стрижка'),
      ],
    );
    when(
      () => repo.fetchServiceTypes('HAIRCUT'),
    ).thenAnswer((_) async => _hairTypes);
  });

  /// Builds a container the test owns, hosts [ServicesListScreen] under an
  /// [UncontrolledProviderScope], and keeps a live listener on the
  /// serviceTypes('HAIRCUT') key so every family invalidation re-fetches.
  Future<ProviderContainer> pumpScreen(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        serviceRepositoryProvider.overrideWithValue(repo),
        servicesListProvider.overrideWith(
          () => _StubServicesList(const <MasterService>[_populatedService]),
        ),
      ],
    );
    addTearDown(container.dispose);

    // Keep the family key alive for the whole test: the screen invalidates the
    // family, but a fetch only fires when something watches it (the picker, in
    // production). This listener stands in for that picker subscription.
    final sub = container.listen(serviceTypesProvider('HAIRCUT'), (_, _) {});
    addTearDown(sub.close);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('uk'),
          home: ServicesListScreen(),
        ),
      ),
    );
    return container;
  }

  // ── 1. initState (first entry) invalidates the family ───────────────────────
  //
  // The post-frame callback in initState invalidates serviceTypesProvider. With
  // a live listener on 'HAIRCUT', that invalidation forces a re-fetch — so the
  // initial fetch (from the listener attaching) PLUS the entry invalidation =
  // at least two calls. Pre-fix (no initState invalidate of serviceTypes) this
  // would be exactly one.
  testWidgets(
    'REGRESSION: initState invalidates serviceTypes family — fetch re-issued '
    'on entry',
    (tester) async {
      await pumpScreen(tester);
      // Loading frame → microtask data → data frame → post-frame invalidation.
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      verify(
        () => repo.fetchServiceTypes('HAIRCUT'),
      ).called(greaterThanOrEqualTo(2));
    },
  );

  // ── 2. pull-to-refresh invalidates the family ───────────────────────────────
  //
  // RefreshIndicator.onRefresh invalidates serviceTypesProvider (whole family)
  // alongside approvedCategoriesProvider. Triggering the pull must re-issue
  // fetchServiceTypes('HAIRCUT') beyond the entry calls. This guards the
  // pull-to-refresh surface against a dropped invalidation / re-added keepAlive.
  testWidgets(
    'REGRESSION: pull-to-refresh invalidates serviceTypes family — fetch '
    're-issued for the active category',
    (tester) async {
      await pumpScreen(tester);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      // Baseline: consume (and reset) the fetch counter for the entry calls so
      // the post-pull verify counts ONLY fetches issued by the refresh.
      // (mocktail's verify() clears the recorded invocations it matches.)
      verify(() => repo.fetchServiceTypes('HAIRCUT')).called(greaterThan(0));

      // Drag down to trigger the RefreshIndicator. The loaded body is a
      // ListView; an overscroll drag from the top fires onRefresh.
      await tester.fling(
        find.byType(Scrollable).first,
        const Offset(0, 400),
        1000,
      );
      await tester.pump(); // start the indicator
      await tester.pump(const Duration(seconds: 1)); // settle the refresh
      await tester.pumpAndSettle();

      // The pull-to-refresh invalidation must have re-issued at least one fetch
      // for the active category since the baseline verify reset the counter.
      // Pre-fix (no serviceTypes invalidate in onRefresh) this would be zero.
      verify(
        () => repo.fetchServiceTypes('HAIRCUT'),
      ).called(greaterThanOrEqualTo(1));
    },
  );
}
