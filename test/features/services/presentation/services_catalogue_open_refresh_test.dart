// fix/services-catalogue-refresh — opening the service SETUP or EDIT screen
// must re-fetch the keepAlive [approvedCategoriesProvider].
//
// The bug: a category an admin approved after the provider was first read never
// reached the pickers until a cold restart. «Мої послуги» refreshed it (once per
// 5 minutes) but the setup / edit screens, which are the pickers, never did.
//
// Strategy: pre-warm the provider in a container the test owns (so the cached,
// STALE value is what the screen finds on open), then mount the screen while the
// fake serves the NEW category from a test-controlled [Completer]. Asserting an
// INTERMEDIATE `pump()` frame is deliberate — see
// project_riverpod_seamless_invalidate_gotcha: `ref.invalidate` retains the
// previous value while reloading, so the stale list stays on screen until the
// completer settles, and a final-frame-only assertion could not tell "re-fetched"
// from "never fetched but happened to be fresh".
//
// Anti-vacuity: every test also asserts the fetch COUNTER moved (2, not 1). Drop
// the `ref.invalidate` from the screen's initState and the counter stays at 1
// and the new category never appears.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/presentation/category_catalogue_freshness.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_screen.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/domain/service_type_option.dart';
import 'package:beautica_mobile/features/services/presentation/service_edit_screen.dart';
import 'package:beautica_mobile/features/services/presentation/service_setup_screen.dart';
import 'package:beautica_mobile/features/services/presentation/service_types_provider.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_notifier.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'widgets/select_dropdown_test_helpers.dart';

class _MockServiceRepository extends Mock implements ServiceRepository {}

class _SeededServicesList extends ServicesList {
  _SeededServicesList(this.seed);

  final List<MasterService> seed;

  @override
  Future<List<MasterService>> build() => SynchronousFuture(seed);
}

const _manicure = ServiceCategoryOption(
  name: 'MANICURE',
  displayName: 'Манікюр',
);
const _brows = ServiceCategoryOption(name: 'BROWS', displayName: 'Брови');

const _service = MasterService(
  id: 'svc-1',
  serviceDefId: 'def-1',
  name: 'Манікюр класичний',
  durationMinutes: 60,
  priceMin: 500,
  priceDisplay: '500 ₴',
  category: 'MANICURE',
);

void main() {
  late _MockServiceRepository repo;

  /// How many times the [approvedCategoriesProvider] body has run.
  late int fetches;

  /// What the fake serves when no [gate] is set.
  late List<ServiceCategoryOption> served;

  /// When non-null the next fetch parks on it (intermediate-frame assertions).
  Completer<List<ServiceCategoryOption>>? gate;

  setUp(() {
    fetches = 0;
    served = const <ServiceCategoryOption>[_manicure];
    gate = null;
    repo = _MockServiceRepository();
    when(
      () => repo.listMyServices(),
    ).thenAnswer((_) async => const <MasterService>[_service]);
    when(
      () => repo.getMyService(_service.id),
    ).thenAnswer((_) async => _service);
  });

  /// A container the test owns, with the provider PRE-WARMED to the stale list.
  ///
  /// [clock] / [stampedAt] (additive, default off) pin the clock and seed the
  /// success-only freshness stamp, for the 30 s entry-floor rows.
  Future<ProviderContainer> warmContainer({
    List<MasterService> existing = const <MasterService>[],
    DateTime Function()? clock,
    DateTime? stampedAt,
  }) async {
    final container = ProviderContainer(
      retry: beauticaProviderRetry,
      overrides: <Object>[
        if (clock != null) clockProvider.overrideWithValue(clock),
        serviceRepositoryProvider.overrideWithValue(repo),
        servicesListProvider.overrideWith(() => _SeededServicesList(existing)),
        approvedCategoriesProvider.overrideWith((ref) {
          fetches++;
          final parked = gate;
          if (parked != null) return parked.future;
          return Future<List<ServiceCategoryOption>>.value(served);
        }),
        serviceTypesProvider.overrideWith(
          (ref, String categoryName) async => const <ServiceTypeOption>[],
        ),
      ].cast(),
    );
    addTearDown(container.dispose);
    // The session's earlier read: the cache now holds the STALE list.
    await container.read(approvedCategoriesProvider.future);
    expect(fetches, 1, reason: 'pre-warm is the one stale fetch');
    if (stampedAt != null) {
      container
          .read(categoryCatalogueFreshnessProvider.notifier)
          .stamp(stampedAt);
    }
    return container;
  }

  Future<void> mount(
    WidgetTester tester,
    ProviderContainer container,
    Widget screen,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('uk'),
          home: screen,
        ),
      ),
    );
  }

  group('ServiceSetupScreen', () {
    testWidgets('open re-fetches: the new category chip appears', (
      tester,
    ) async {
      final container = await warmContainer();
      served = const <ServiceCategoryOption>[_manicure, _brows];

      await mount(tester, container, const ServiceSetupScreen());
      await tester.pumpAndSettle();

      expect(fetches, 2, reason: 'opening the screen must re-fetch once');
      expect(find.byKey(const ValueKey<String>('cat_MANICURE')), findsOne);
      expect(find.byKey(const ValueKey<String>('cat_BROWS')), findsOne);
    });

    testWidgets(
      'intermediate frame: stale chips stay while the re-fetch is parked, '
      'then the new one lands',
      (tester) async {
        final container = await warmContainer();
        gate = Completer<List<ServiceCategoryOption>>();

        await mount(tester, container, const ServiceSetupScreen());
        await tester.pump(); // first frame
        await tester.pump(); // post-frame invalidate -> re-fetch starts

        // Intermediate frame. NOT `value == null`: the previous list is
        // retained during the reload, so the stale chip is still shown...
        expect(fetches, 2, reason: 're-fetch must have started');
        expect(find.byKey(const ValueKey<String>('cat_MANICURE')), findsOne);
        // ...and the new category is NOT there yet.
        expect(find.byKey(const ValueKey<String>('cat_BROWS')), findsNothing);

        gate!.complete(const <ServiceCategoryOption>[_manicure, _brows]);
        await tester.pump();
        await tester.pump();

        expect(find.byKey(const ValueKey<String>('cat_BROWS')), findsOne);
      },
    );
  });

  group('ServiceEditScreen', () {
    testWidgets('open re-fetches: the new category option appears', (
      tester,
    ) async {
      final container = await warmContainer(
        existing: const <MasterService>[_service],
      );
      served = const <ServiceCategoryOption>[_manicure, _brows];

      await mount(tester, container, const ServiceEditScreen(id: 'svc-1'));
      await tester.pumpAndSettle();

      expect(fetches, 2, reason: 'opening the screen must re-fetch once');
      await openCategoryMenu(tester);
      expect(find.byKey(const Key('chip-category-MANICURE')), findsOne);
      expect(find.byKey(const Key('chip-category-BROWS')), findsOne);
    });

    testWidgets(
      'intermediate frame: the new option is absent while the re-fetch is '
      'parked, present once it settles',
      (tester) async {
        final container = await warmContainer(
          existing: const <MasterService>[_service],
        );
        gate = Completer<List<ServiceCategoryOption>>();

        await mount(tester, container, const ServiceEditScreen(id: 'svc-1'));
        await tester.pump();
        await tester.pump();
        await tester.pump();

        expect(fetches, 2, reason: 're-fetch must have started');
        await openCategoryMenu(tester);
        // The retained (stale) list drives the menu while the reload is parked.
        expect(find.byKey(const Key('chip-category-BROWS')), findsNothing);

        // The open sheet snapshots its options, so dismiss it (barrier tap)
        // before the re-fetch settles and re-open afterwards.
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('chip-category-MANICURE')), findsNothing);

        gate!.complete(const <ServiceCategoryOption>[_manicure, _brows]);
        await tester.pumpAndSettle();

        await openCategoryMenu(tester);
        expect(find.byKey(const Key('chip-category-BROWS')), findsOne);
      },
    );
  });

  // Audit cycle 1 (P1): setup / edit open honour the 30 s entry floor and skip
  // while a fetch is in flight. The rows above run with a null stamp (never
  // refreshed this session), which is why they still refetch unchanged.
  group('30 s entry floor', () {
    final t0 = DateTime.utc(2026, 10, 1, 12);

    testWidgets('setup open 10 s after a refresh does NOT re-fetch', (
      tester,
    ) async {
      final container = await warmContainer(
        clock: () => t0,
        stampedAt: t0.subtract(const Duration(seconds: 10)),
      );
      await mount(tester, container, const ServiceSetupScreen());
      await tester.pumpAndSettle();
      expect(fetches, 1);
    });

    testWidgets('setup open 31 s after a refresh re-fetches once', (
      tester,
    ) async {
      final container = await warmContainer(
        clock: () => t0,
        stampedAt: t0.subtract(const Duration(seconds: 31)),
      );
      await mount(tester, container, const ServiceSetupScreen());
      await tester.pumpAndSettle();
      expect(fetches, 2);
    });

    testWidgets('edit open 10 s after a refresh does NOT re-fetch', (
      tester,
    ) async {
      final container = await warmContainer(
        existing: const <MasterService>[_service],
        clock: () => t0,
        stampedAt: t0.subtract(const Duration(seconds: 10)),
      );
      await mount(tester, container, const ServiceEditScreen(id: 'svc-1'));
      await tester.pumpAndSettle();
      expect(fetches, 1);
    });

    testWidgets('setup open while a fetch is IN FLIGHT does not duplicate it', (
      tester,
    ) async {
      final container = await warmContainer(clock: () => t0);
      gate = Completer<List<ServiceCategoryOption>>();
      container.invalidate(approvedCategoriesProvider);
      unawaited(container.read(approvedCategoriesProvider.future));
      expect(fetches, 2, reason: 'one parked in-flight fetch');

      await mount(tester, container, const ServiceSetupScreen());
      await tester.pump();
      await tester.pump();
      expect(fetches, 2, reason: 'open must join, not start a third');

      gate!.complete(const <ServiceCategoryOption>[_manicure]);
      await tester.pumpAndSettle();
    });

    testWidgets('«Мої послуги» entry then setup open within 30 s = ONE fetch', (
      tester,
    ) async {
      final container = await warmContainer(clock: () => t0);

      await mount(tester, container, const ServicesListScreen());
      await tester.pumpAndSettle();
      expect(fetches, 2, reason: 'list entry refreshed once');

      await mount(tester, container, const ServiceSetupScreen());
      await tester.pumpAndSettle();
      expect(fetches, 2, reason: 'setup open inside the floor adds none');
    });
  });
}
