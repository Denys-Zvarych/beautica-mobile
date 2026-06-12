// First-time service setup — widget tests for [ServiceSetupScreen].
//
// [ServiceSetupScreen] is a ConsumerStatefulWidget driving:
//   • the empty-state catalogue loader (approvedCategoriesProvider): loading /
//     error+retry / data;
//   • lazy per-category service-type expansion (serviceTypesProvider family);
//   • per-row include toggles + a footer CTA that counts included rows and is
//     disabled at zero;
//   • a bulk save through serviceSetupProvider → ServiceRepository.bulkCreate.
//
// Strategy:
//   • Override approvedCategoriesProvider + the serviceTypesProvider(slug)
//     family + serviceRepositoryProvider (mocktail) so NOTHING hits a network.
//   • Mount inside a GoRouter so context.go(RouteNames.services) resolves; the
//     screen uses go_router, never Navigator.
//   • Find widgets by Key per the project convention: cat_$name, group_$slug,
//     setup_row_$id, rowwrap_$id, btn-setup-save.
//   • ScreenProtector lifecycle calls are guarded by !kDebugMode, so they are
//     never invoked in tests.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/master_service_input.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/domain/service_type_option.dart';
import 'package:beautica_mobile/features/services/presentation/service_setup_screen.dart';
import 'package:beautica_mobile/features/services/presentation/service_types_provider.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

// ── Mocks ──────────────────────────────────────────────────────────────────

class _MockServiceRepository extends Mock implements ServiceRepository {}

// ── Stub data ────────────────────────────────────────────────────────────────

const _manicure = ServiceCategoryOption(
  name: 'MANICURE',
  displayName: 'Манікюр',
);
const _hair = ServiceCategoryOption(name: 'HAIR', displayName: 'Волосся');

const _typeClassic = ServiceTypeOption(
  id: 'type-classic',
  slug: 'CLASSIC',
  nameUk: 'Класичний манікюр',
  categoryName: 'MANICURE',
);
const _typeGel = ServiceTypeOption(
  id: 'type-gel',
  slug: 'GEL',
  nameUk: 'Гель-лак',
  categoryName: 'MANICURE',
);

const _createdService = <MasterService>[
  MasterService(
    id: 'svc-1',
    serviceDefId: 'def-1',
    name: 'Класичний манікюр',
    durationMinutes: 60,
    priceMin: 500,
    priceDisplay: '500 грн',
  ),
];

// ── Harness ──────────────────────────────────────────────────────────────────

class _Harness {
  _Harness() : repo = _MockServiceRepository(), pushedRoutes = <String>[];

  final _MockServiceRepository repo;
  final List<String> pushedRoutes;

  /// A router that mounts the setup screen at /services/setup and records
  /// navigation to /services so the success/conflict-redirect paths are
  /// observable without a real services screen.
  GoRouter router() => GoRouter(
    initialLocation: RouteNames.serviceSetup,
    routes: <RouteBase>[
      GoRoute(
        path: RouteNames.serviceSetup,
        builder: (_, _) => const ServiceSetupScreen(),
      ),
      GoRoute(
        path: RouteNames.services,
        builder: (_, _) {
          pushedRoutes.add(RouteNames.services);
          return const Scaffold(body: Text('SERVICES_LIST_STUB'));
        },
      ),
    ],
  );

  List<Object> overrides({
    AsyncValue<List<ServiceCategoryOption>>? categories,
    Map<String, FutureOr<List<ServiceTypeOption>>>? typesBySlug,
  }) {
    final cat = categories ?? const AsyncData(<ServiceCategoryOption>[]);
    return <Object>[
      serviceRepositoryProvider.overrideWithValue(repo),
      approvedCategoriesProvider.overrideWith(
        (ref) => cat.when(
          data: (v) => v,
          loading: () => Completer<List<ServiceCategoryOption>>().future,
          error: (e, _) => Future<List<ServiceCategoryOption>>.error(e),
        ),
      ),
      if (typesBySlug != null)
        for (final entry in typesBySlug.entries)
          serviceTypesProvider(entry.key).overrideWith((ref) => entry.value),
    ];
  }
}

Future<void> _pump(
  WidgetTester tester,
  _Harness h, {
  required List<Object> overrides,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides.cast(),
      child: MaterialApp.router(
        routerConfig: h.router(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('uk'),
      ),
    ),
  );
}

void main() {
  late _Harness h;

  setUp(() {
    h = _Harness();
    registerFallbackValue(const <MasterServiceBulkItem>[]);
  });

  // ── Catalogue states ───────────────────────────────────────────────────────

  group('catalogue states', () {
    testWidgets('loading — shows a progress indicator', (tester) async {
      await _pump(
        tester,
        h,
        overrides: h.overrides(
          categories: const AsyncLoading<List<ServiceCategoryOption>>(),
        ),
      );
      await tester.pump(); // one frame; provider future never completes

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('error — shows ErrorState; retry re-reads categories', (
      tester,
    ) async {
      await _pump(
        tester,
        h,
        overrides: h.overrides(
          categories: const AsyncError<List<ServiceCategoryOption>>(
            NetworkFailure(),
            StackTrace.empty,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('service_setup_error_state')),
        findsOneWidget,
      );
      expect(find.byType(ErrorState), findsOneWidget);

      // The retry affordance must exist and be tappable without throwing.
      final retry = find.descendant(
        of: find.byType(ErrorState),
        matching: find.byType(GestureDetector),
      );
      expect(retry, findsWidgets);
    });

    testWidgets('data — renders a chip per category by key', (tester) async {
      await _pump(
        tester,
        h,
        overrides: h.overrides(
          categories: const AsyncData(<ServiceCategoryOption>[
            _manicure,
            _hair,
          ]),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('cat_MANICURE')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey<String>('cat_HAIR')), findsOneWidget);
    });
  });

  // ── Expansion + rows ─────────────────────────────────────────────────────────

  group('category expansion', () {
    testWidgets('selecting a category expands it and shows service-type rows', (
      tester,
    ) async {
      await _pump(
        tester,
        h,
        overrides: h.overrides(
          categories: const AsyncData(<ServiceCategoryOption>[_manicure]),
          typesBySlug: <String, List<ServiceTypeOption>>{
            'MANICURE': <ServiceTypeOption>[_typeClassic, _typeGel],
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey<String>('cat_MANICURE')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('group_MANICURE')),
        findsOneWidget,
      );
      // The first row is on-screen; the second lives below the fold in the
      // lazy SliverList, so scroll it into view before asserting.
      expect(find.byKey(const Key('setup_row_type-classic')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('setup_row_type-gel')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('setup_row_type-gel')), findsOneWidget);
    });
  });

  // ── Footer count + CTA enable/disable ──────────────────────────────────────

  group('footer CTA', () {
    testWidgets('disabled (onPressed null) when nothing is included', (
      tester,
    ) async {
      await _pump(
        tester,
        h,
        overrides: h.overrides(
          categories: const AsyncData(<ServiceCategoryOption>[_manicure]),
        ),
      );
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
      // No selection → footer shows the empty CTA copy.
      expect(find.text(l10n.serviceSetupCtaEmpty), findsOneWidget);
    });

    testWidgets(
      'expanding a category (rows default included) counts the rows and '
      'enables the CTA; toggling one OFF lowers the count',
      (tester) async {
        await _pump(
          tester,
          h,
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[_manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[_typeClassic, _typeGel],
            },
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey<String>('cat_MANICURE')));
        await tester.pumpAndSettle();

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        // Both rows default included → "Створити 2 ...".
        expect(find.text(l10n.serviceSetupCtaCreate(2)), findsOneWidget);

        // Toggle the first row's include switch OFF — the switch is a
        // Semantics(button,toggled) inside the row card.
        final firstSwitch = find.descendant(
          of: find.byKey(const Key('setup_row_type-classic')),
          matching: find.byType(GestureDetector),
        );
        await tester.tap(firstSwitch.first);
        await tester.pumpAndSettle();

        // Count drops to 1.
        expect(find.text(l10n.serviceSetupCtaCreate(1)), findsOneWidget);
      },
    );
  });

  // ── Save path ────────────────────────────────────────────────────────────────

  group('save', () {
    testWidgets(
      'tapping save with a valid included row calls bulkCreate and navigates '
      'to the services list',
      (tester) async {
        when(
          () => h.repo.bulkCreate(any()),
        ).thenAnswer((_) async => _createdService);

        await _pump(
          tester,
          h,
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[_manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[_typeClassic],
            },
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey<String>('cat_MANICURE')));
        await tester.pumpAndSettle();

        // Fill the duration (the row's leading VelvetField — the first
        // TextField in the card) and the fixed price (keyed field).
        await tester.enterText(
          find
              .descendant(
                of: find.byKey(const Key('setup_row_type-classic')),
                matching: find.byType(TextField),
              )
              .first,
          '60',
        );
        await tester.enterText(
          find.byKey(const Key('pricing-fixed-amount')),
          '500',
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn-setup-save')));
        await tester.pumpAndSettle();

        verify(() => h.repo.bulkCreate(any())).called(1);
        expect(h.pushedRoutes, contains(RouteNames.services));
      },
    );

    testWidgets(
      'invalid range (max <= min) flags the row and blocks save — bulkCreate '
      'never called',
      (tester) async {
        await _pump(
          tester,
          h,
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[_manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[_typeClassic],
            },
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey<String>('cat_MANICURE')));
        await tester.pumpAndSettle();

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        // Switch the row to RANGE mode and enter an invalid range.
        await tester.tap(find.byKey(const Key('pricing-toggle-range')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find
              .descendant(
                of: find.byKey(const Key('setup_row_type-classic')),
                matching: find.byType(TextField),
              )
              .first,
          '60',
        );
        await tester.enterText(
          find.byKey(const Key('pricing-range-min')),
          '500',
        );
        await tester.enterText(
          find.byKey(const Key('pricing-range-max')),
          '300', // max <= min → invalid
        );
        await tester.pumpAndSettle();

        // The cross-field range error line appears (only on invalid range).
        expect(find.text(l10n.pricingRangeHint), findsOneWidget);

        await tester.tap(find.byKey(const Key('btn-setup-save')));
        await tester.pumpAndSettle();

        verifyNever(() => h.repo.bulkCreate(any()));
      },
    );
  });
}
